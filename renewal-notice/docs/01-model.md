# 1. アプリのモデル（`Model.lean`）

ソース：[`lean/RenewalNotice/Model.lean`](../lean/RenewalNotice/Model.lean)

## このファイルで言いたいこと

Go で実装したアプリ（[`go/batch/system.go`](../go/batch/system.go)）を、Lean の関数として写す。
STPA の制御構造の要素を、次のように型と関数に対応させている。

| STPA の要素 | このファイル |
|---|---|
| 制御対象プロセス（現実） | `World` |
| プロセスモデル（コントローラーの認識） | 表 `tA`・`tB`・`tC`（`Table`） |
| コントローラー | `batchA`〜`batchD` |
| 制御動作・外乱 | `Action` |
| スケジューラー | `step`、`run` |

ここには定理はない。後の章で、ここで定義した関数について定理を書く。

## 現実：`World`

```lean
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
```

- 会員は自然数（0, 1, 2, …）で表す
- `inactive` は「本当に使っていない会員」、`renewing` は「本当に翌月更新の会員」。バッチはこれを直接は見られない
- `isTarget` は「本当の通知対象か」の判定。安全制約（[2章](02-safety-and-uca.md)）は、これを基準にする
- `logOk` が false になると、バッチA が読む利用ログ（`inactiveLog`）が空になる。元記事のシナリオD（テーブル名が変わって0件になる）を表すための値である

## バッチの認識：`Table`

```lean
/-- 抽出結果テーブル（プロセスモデル）。`asOf` は基準日。 -/
structure Table where
  asOf : Nat
  rows : List User
deriving Repr
```

各バッチが書き出す表である。`asOf` は「いつのデータか」を表す基準日。バッチ同士は、この表だけでつながっている。

## 全体の状態：`State`

```lean
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
  /-- tC を作ったときに実際に使った tA・tB のうち、古いほうの基準日。
      `sent` の第2成分と同じく観測者視点の真値で、バッチ自身は見ない。
      naive の C は入力が古くても tC に今日の日付を付けるので、
      tC の `asOf` だけでは「今日の抽出が終わる前に作った表か」が分からない。 -/
  tCInputsAsOf : Nat := 0
deriving Repr
```

状態には、2種類の情報が入っている。

| 種類 | フィールド | 誰が見るか |
|---|---|---|
| アプリが実際に持つ情報 | `today`、`tA`、`tB`、`tC`、`rA`〜`rD`、`sent` の宛先 | バッチ |
| 観測者だけが知る真実 | `world`、`sent` の第2成分、`tCInputsAsOf` | 安全制約と UCA の判定だけ |

観測者だけが知る情報を持たせているのは、「バッチの認識が現実とずれる」ことを判定するためである。

- `sent` の第2成分には、送った瞬間に相手が本当に対象者だったか（`isTarget` の値）を記録する。送った後で会員が利用を再開しても、この記録は変わらない
- `tCInputsAsOf` には、tC を作るのに実際に使った表の基準日を記録する。対策なし版の C は、古い表から作っても tC に今日の日付を付けてしまうので、tC の `asOf` だけでは本当の鮮度が分からない

`rA`〜`rD` は、スケジューラーや監視から見えるジョブの結果である。

## 設計と動作：`Design`、`Action`

```lean
/-- `naive`: 各バッチは単体仕様どおりだが、バッチ間の前提を確認しない。
    `safe` : STPA で導いた安全制約を実装したもの。 -/
inductive Design where
  | naive | safe
deriving Repr, DecidableEq

inductive Action where
  | runA | runB | runC | runD
  /-- 配信基盤が k 件を受理した後で、D が失敗として終わる。
      途中での異常終了（記事のシナリオB）と、応答のタイムアウト（シナリオC）の両方を表す。 -/
  | crashD (k : Nat)
  /-- 外乱: ユーザー u が利用を再開する。 -/
  | use (u : User)
  /-- 外乱: 利用ログソースが壊れる（テーブル名変更などで 0 件を返す）。 -/
  | breakSource
deriving Repr, DecidableEq
```

- `Design` は2つの設計を切り替える。同じバッチでも、設計によって動きが変わる
- `Action` は、スケジューラーが起こすこと（バッチの実行）と、外から起きること（外乱）を並べたもの。実行順は `List Action`（たとえば `[.runB, .runC, .runA, .runD]`）で表す

## バッチ A・B

```lean
def sentUsers (s : State) : List User := s.sent.map (·.1)

def batchA (s : State) : State :=
  { s with
    tA := { asOf := s.today, rows := s.world.users.filter (fun u => s.world.inactiveLog.contains u) }
    rA := .ok }

def batchB (s : State) : State :=
  { s with
    tB := { asOf := s.today, rows := s.world.users.filter (fun u => s.world.renewing.contains u) }
    rB := .ok }
```

- バッチは「状態を受け取り、新しい状態を返す関数」である
- A は利用ログから非アクティブな会員を抜き出し、今日の日付で tA に書く。B は契約情報から翌月更新の会員を抜き出し、tB に書く
- どちらも、設計（naive / safe）によらず同じ定義である
- A は利用ログが壊れていても（`inactiveLog` が空でも）、0件の表を書いて正常終了する。単体として見れば「読んだデータを正しく書いた」ことになる

## バッチ C

```lean
def intersect (a b : Table) (asOf : Nat) : Table :=
  { asOf := asOf, rows := a.rows.filter (fun u => b.rows.contains u) }

/-- naive は入力の鮮度を確認せず、結果に今日の日付を付ける。
    プロセスモデルが現実とずれる原因になる。 -/
def batchC : Design → State → State
  | .naive, s => { s with tC := intersect s.tA s.tB s.today, rC := .ok,
                          tCInputsAsOf := min s.tA.asOf s.tB.asOf }
  | .safe,  s =>
    if s.tA.asOf = s.today ∧ s.tB.asOf = s.today then
      { s with tC := intersect s.tA s.tB s.today, rC := .ok,
               tCInputsAsOf := min s.tA.asOf s.tB.asOf }
    else
      { s with rC := .failed }
```

- naive：tA と tB の積集合を取り、今日の日付で tC に書く。tA や tB が古くても気にしない
- safe：tA と tB がどちらも今日のものなら積集合を取る。そうでなければ tC を変えずに失敗で終わる（元記事の設計要求「基準日時を確認する」）
- どちらも `tCInputsAsOf` に、実際に使った表の基準日（古いほう）を記録する

## バッチ D

```lean
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
```

- `k` は「途中で失敗するか」を表す。`none` なら全員に送って正常終了、`some n` なら n 件を受理させたところで失敗として終わる
- `record` は、送った相手と「その瞬間に本当に対象だったか」を組にして記録する
- naive：tC の全員に送る。送信済みかどうかは見ない
- safe：tC が今日のものでなければ失敗で終わる。今日のものなら、`pending` で「まだ受理されていない」かつ「今も対象」の人だけに送る（元記事の設計要求「通知指示を一意に管理する」「結果が不明なら自動再送しない」）

## スケジューラー：`step`、`run`

```lean
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
```

- `step` は1つの動作を実行する。`use u` は会員 u を「非アクティブ」から外し、`breakSource` は利用ログを壊す
- `run` は実行順を先頭から1つずつ実行する。`a :: t` は「先頭が a、残りが t」のリスト
- スケジューラーは順序を保証しないので、どんな `List Action` でも `run` に渡してよい。この「どんな順でも」が、後で定理の `∀ t : List Action` になる

## 初期状態：`init`

```lean
/-- 初期状態。前回サイクル（day 0）の抽出結果が残ったまま、今日（day 1）のサイクルを始める。

* 会員0：翌月更新を迎えるが、最近利用を再開した（前回の抽出では非アクティブだった）→ 通知対象外
* 会員1・2：翌月更新を迎え、今も使っていない → 通知対象

前回の表 tA には会員0が残っているので、古い tA を使うと会員0に案内が届いてしまう
（記事のシナリオA「前回の抽出結果が利用され、本来対象外のユーザーに退会案内が送信される」）。 -/
def init : State :=
  { today := 1
    world := { users := [0, 1, 2], inactive := [1, 2], renewing := [0, 1, 2] }
    tA    := { asOf := 0, rows := [0, 1] }
    tB    := { asOf := 0, rows := [0] }
    tC    := { asOf := 0, rows := [0] }
    sent  := [] }
```

| 会員 | 翌月更新 | 今の利用状況 | 本当の通知対象か | 前回の tA にいるか |
|---|---|---|---|---|
| 0 | する | 最近利用を再開した | 対象外 | いる |
| 1 | する | 使っていない | 対象 | いる |
| 2 | する | 使っていない | 対象 | いない |

前回の表が残っているので、どのバッチから実行しても意味のある状態になる。

## 計算してみる

シナリオA（B → C → A → D）を naive で実行すると、次のように進む。

| 動作 | 変わったところ |
|---|---|
| （初期） | tA = (day 0, [0, 1])、tB = (day 0, [0])、tC = (day 0, [0]) |
| B | tB = (day 1, [0, 1, 2]) |
| C | tC = (day 1, [0, 1])。古い tA と新しい tB の積集合。`tCInputsAsOf` = 0 |
| A | tA = (day 1, [1, 2])。ただし C はもう終わっている |
| D | tC の [0, 1] に送る。`sent` = [(0, false), (1, true)] |

`#eval` で確かめた結果：

```lean
#eval (run .naive init scenarioA).tC            -- { asOf := 1, rows := [0, 1] }
#eval (run .naive init scenarioA).tCInputsAsOf  -- 0
#eval (run .naive init scenarioA).sent          -- [(0, false), (1, true)]
```

会員0（対象外）に送ってしまい、会員2（対象）には送っていない。これが[4章](04-hazards.md)で証明するハザードである。
