import RenewalNotice.SafeDesign
/-!
# 偽の警報の例：主張は正しいのに、証明が止まる

対策版（safe）では、UCA Timing（今日の抽出から作られていない通知対象で送信を始める）は
どんな実行順でも起きない。これは `RenewalNotice/SafeDesign.lean` の `safe_no_uca_timing` で証明済みである。

ここでは、その1ステップの補題を、不変条件 `FreshTC` を仮定に加えずに証明しようとする。
主張は正しいが、証明は止まり、ビルドは失敗する。

    lake build DetectFalseAlarm

残ったゴールが求める状況（tC に今日の日付が付いているのに、実際は古い表から作られている）は、
safe では初期状態から到達できない。だからこれはハザードではなく、証明に必要な事実が足りないだけである。
不変条件 `FreshTC` を仮定に加えると、証明は通る（`safe_no_uca_timing_step`）。
-/
-- この版は説明用なので、Lean Atlas の注記を求めない
set_option linter.confidenceCheck false
set_option linter.proofProgressCheck false
set_option linter.defProgressCheck false

namespace RenewalNotice.Detect

/-- 対策版では、どの状態からでも、1回の制御動作で UCA Timing は起きない（と主張する）。

`safe_no_uca_timing_step` と同じ手順だが、仮定 `h : FreshTC s` がない。
送信が起きる場合、分かっているのは「tC に今日の日付が付いている（`hd`）」ことだけで、
「tC が実際に今日の表から作られた（`tCInputsAsOf = today`）」ことは言えないので、証明が止まる。 -/
theorem safe_uca_timing_step_without_invariant (s : State) (a : Action) :
    ucaTiming .safe s a = false := by
  unfold ucaTiming newSends
  rcases safe_step_sent s a with hs | ⟨hd, k, hs⟩
  · simp [hs]
  · rw [hs, List.drop_left, map_fst_record]
    skip

/-! ## 切り分け：ゴールの状況に到達する実行順を探す（docs/10-practice.md の手順3） -/

/-- ゴールの状況：tC に今日の日付が付いているのに、実際は古い表から作られている。 -/
def staleButStamped (s : State) : Bool := s.tC.asOf == s.today && s.tCInputsAsOf != s.today

-- 対策版では、長さ5以下のどの実行順でも到達しない（`none`）。
#eval (tracesUpTo alphabet 5).find? (fun t => staleButStamped (run .safe init t))

-- 対策なし版では、C を1回実行するだけで到達する（`some [runC]`）。
#eval (tracesUpTo alphabet 5).find? (fun t => staleButStamped (run .naive init t))

end RenewalNotice.Detect
