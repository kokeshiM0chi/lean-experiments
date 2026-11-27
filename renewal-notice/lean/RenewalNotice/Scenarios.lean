import RenewalNotice.ModelCheck
/-!
# 定理で使う実行順と補助の定義

ここには主張（定理）の本体を置かない。Lean Atlas の注記の対象外にするため、
`LeanAtlas` を import しないファイルに分けている。

`crashD k` は「配信基盤が k 件を受理した後で、D が失敗として終わる」動作で、
記事のシナリオB（途中で異常終了）とシナリオC（タイムアウトで結果が分からない）の両方を表す。
どちらも、配信基盤側では受理済みなのに、D とスケジューラーからは失敗に見える。
-/
namespace RenewalNotice

/-! ## 元記事の Loss Scenario A〜D -/

/-- シナリオA（バッチの依存関係が守られない）：
    非アクティブユーザー抽出（A）が遅延しているのに、時刻設定どおりに C が起動し、
    前回の A の結果で積集合を取る。その後で A が終わり、D が送る。 -/
def scenarioA : List Action := [.runB, .runC, .runA, .runD]

/-- シナリオB（部分失敗後のリトライで重複）：
    D が対象者の一部（2人中1人）に送った時点で異常終了し、スケジューラーが D 全体を再実行する。 -/
def scenarioB : List Action := [.runA, .runB, .runC, .crashD 1, .runD]

/-- シナリオC（送信状態を認識できない）：
    配信基盤は全員分を受理したが、応答がタイムアウトして D は失敗として終わる。
    スケジューラーが D を再実行する。 -/
def scenarioC : List Action := [.runA, .runB, .runC, .crashD 2, .runD]

/-- シナリオD（正常終了したのに通知が送られない）：
    利用ログのテーブル名が変わり、A が 0 件のまま正常終了する。後続もすべて正常終了する。 -/
def scenarioD : List Action := [.breakSource, .runA, .runB, .runC, .runD]

/-! ## 記事にないシナリオ -/

/-- 自動探索で見つかった最短の H1：前回分の表 tC のまま D が送る。 -/
def traceOnlyD : List Action := [.runD]
/-- 自動探索で見つかった最短の H2：送信済みを確かめずに D を2回実行する。 -/
def traceDTwice : List Action := [.runD, .runD]
/-- 自動探索で見つかった H3：D が C より先に古い表で送り、最後に C が終わって全ジョブが正常に見える。 -/
def traceDBeforeC : List Action := [.runA, .runB, .runD, .runC]
/-- C が対象を確定した後、D が送る前に会員が利用を再開する（TOCTOU）。 -/
def traceTOCTOU : List Action := [.runA, .runB, .runC, .use 1, .runD]

/-! ## 補助の定義と補題 -/

/-- 送信記録はすべて、送信時点で本当の対象者宛てだった（SC1 を命題にしたもの）。 -/
def SentOk (s : State) : Prop := ∀ p ∈ s.sent, p.2 = true

/-- tC に今日の日付が付いているなら、本当に今日の A・B の結果から作られている。 -/
def FreshTC (s : State) : Prop := s.tC.asOf = s.today → s.tCInputsAsOf = s.today

/-- 実行順にログソースの故障が含まれない。 -/
def noSourceFault (t : List Action) : Bool := !t.contains .breakSource

theorem mem_limit {k : Option Nat} {us : List User} {u : User} (h : u ∈ limit k us) : u ∈ us := by
  cases k with
  | none   => exact h
  | some n => exact List.mem_of_mem_take h

theorem map_fst_record (s : State) (us : List User) : (record s us).map (·.1) = us := by
  simp [record, Function.comp_def]

end RenewalNotice
