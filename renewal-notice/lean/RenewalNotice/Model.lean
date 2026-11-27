/-!
# 退会案内通知バッチの形式モデル

STPA の制御構造をそのままモデル化する。

* 制御対象プロセス（現実）: `World`。ユーザーが本当に非アクティブか、本当に翌月更新か。
* コントローラー: バッチ A/B/C/D（`batchA` など）
* プロセスモデル（コントローラーの認識）: 抽出結果テーブル `tA` `tB` `tC`
* 制御動作: 各バッチの実行、通知の送信
* スケジューラー: 実行順序は保証しない。任意の `List Action` をトレースとして扱う
* 外乱: ユーザーの利用再開（`use`）、ログソースの故障（`breakSource`）

Go 実装 `go/batch/system.go` と1対1に対応させてある。
-/
namespace RenewalNotice

abbrev User := Nat

/-- 制御対象プロセスの真の状態。 -/
structure World where
  users    : List User
  inactive : List User
  renewing : List User
  logOk    : Bool := true
deriving Repr

/-- 真の通知対象（非アクティブかつ翌月更新）。 -/
def World.isTarget (w : World) (u : User) : Bool :=
  w.inactive.contains u && w.renewing.contains u

/-- バッチ A が読む利用ログソース。故障すると 0 件を返す。 -/
def World.inactiveLog (w : World) : List User :=
  if w.logOk then w.inactive else []

/-- 抽出結果テーブル（プロセスモデル）。`asOf` は基準日。 -/
structure Table where
  asOf : Nat
  rows : List User
deriving Repr

inductive JobResult where
  | notRun | ok | failed
deriving Repr, DecidableEq

structure State where
  today : Nat
  world : World
  tA    : Table
  tB    : Table
  tC    : Table
  /-- 配信基盤が受理した通知。`(宛先, 送信時点で本当に対象者だったか)`。
      第2成分は観測者視点の真値で、バッチ自身は知らない。 -/
  sent  : List (User × Bool)
  rA : JobResult := .notRun
  rB : JobResult := .notRun
  rC : JobResult := .notRun
  rD : JobResult := .notRun
deriving Repr

/-- `naive`: 各バッチは単体仕様どおりだが、バッチ間の前提を確認しない。
    `safe` : STPA で導いた安全制約を実装したもの。 -/
inductive Design where
  | naive | safe
deriving Repr, DecidableEq

inductive Action where
  | runA | runB | runC | runD
  /-- D が k 件送ったところで異常終了する（タイムアウトを含む）。 -/
  | crashD (k : Nat)
  /-- 外乱: ユーザー u が利用を再開する。 -/
  | use (u : User)
  /-- 外乱: 利用ログソースが壊れる（テーブル名変更などで 0 件を返す）。 -/
  | breakSource
deriving Repr, DecidableEq

def sentUsers (s : State) : List User := s.sent.map (·.1)

/-! ## コントローラー（バッチ） -/

def batchA (s : State) : State :=
  { s with
    tA := { asOf := s.today, rows := s.world.users.filter (fun u => s.world.inactiveLog.contains u) }
    rA := .ok }

def batchB (s : State) : State :=
  { s with
    tB := { asOf := s.today, rows := s.world.users.filter (fun u => s.world.renewing.contains u) }
    rB := .ok }

def intersect (a b : Table) (asOf : Nat) : Table :=
  { asOf := asOf, rows := a.rows.filter (fun u => b.rows.contains u) }

/-- naive は入力の鮮度を確認せず、結果に今日の日付を付ける。
    プロセスモデルが現実とずれる原因になる。 -/
def batchC : Design → State → State
  | .naive, s => { s with tC := intersect s.tA s.tB s.today, rC := .ok }
  | .safe,  s =>
    if s.tA.asOf = s.today ∧ s.tB.asOf = s.today then
      { s with tC := intersect s.tA s.tB s.today, rC := .ok }
    else
      { s with rC := .failed }

def record (s : State) (us : List User) : List (User × Bool) :=
  us.map (fun u => (u, s.world.isTarget u))

def limit : Option Nat → List User → List User
  | none,   us => us
  | some n, us => us.take n

def doneResult : Option Nat → JobResult
  | none   => .ok
  | some _ => .failed

def batchDNaive (k : Option Nat) (s : State) : State :=
  { s with sent := s.sent ++ record s (limit k s.tC.rows), rD := doneResult k }

/-- safe な D が実際に送る相手。
    * 配信基盤の受理記録（フィードバック）を見て、送信済みは除外する
    * 送る直前に真のソースで対象者かを確認する -/
def pending (s : State) : List User :=
  s.tC.rows.filter (fun u => !(sentUsers s).contains u && s.world.isTarget u)

def batchDSafe (k : Option Nat) (s : State) : State :=
  if s.tC.asOf = s.today then
    { s with sent := s.sent ++ record s (limit k (pending s)), rD := doneResult k }
  else
    { s with rD := .failed }

def batchD : Design → Option Nat → State → State
  | .naive => batchDNaive
  | .safe  => batchDSafe

/-! ## スケジューラー（順序を保証しない） -/

def step (d : Design) (s : State) : Action → State
  | .runA        => batchA s
  | .runB        => batchB s
  | .runC        => batchC d s
  | .runD        => batchD d none s
  | .crashD k    => batchD d (some k) s
  | .use u       => { s with world := { s.world with inactive := s.world.inactive.filter (· != u) } }
  | .breakSource => { s with world := { s.world with logOk := false } }

def run (d : Design) : State → List Action → State
  | s, []     => s
  | s, a :: t => run d (step d s a) t

/-- 初期状態。前回サイクル（day 0）の抽出結果が残ったまま、今日（day 1）のサイクルを始める。 -/
def init : State :=
  { today := 1
    world := { users := [0, 1, 2], inactive := [1, 2], renewing := [1, 2] }
    tA    := { asOf := 0, rows := [0, 1] }
    tB    := { asOf := 0, rows := [0] }
    tC    := { asOf := 0, rows := [0] }
    sent  := [] }

end RenewalNotice
