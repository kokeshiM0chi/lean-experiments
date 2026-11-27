import RenewalNotice.Spec
/-!
# 対策版（safe）の安全性

対策版は、元記事が導いた設計要求のうち次の3つを実装している。

* 対象者抽出バッチの成功だけでなく、基準日時を確認する（C と D は基準日が今日でなければ失敗で終わる）
* 同一ユーザーへの通知指示を一意に管理する（D は配信基盤の受理記録を見て、受理済みには送らない）
* 配信結果が不明な場合、自動再送を行わない（タイムアウトで結果不明でも受理記録に残るので、送らない）

記事の残りの設計要求（対象者集合の完全性の確認、対象者数と送信指示数の照合、0件の検証）は
まだ実装していない。そのため記事のシナリオDは対策版でも残る（`safe_residual_scenarioD`）。

| 主張 | 状態 |
|---|---|
| UCA Timing / Providing が起きない | 任意長の実行順で証明済み |
| H1 が起きない（SC1） | 任意長の実行順で証明済み |
| SC1〜SC3 と UCA Not Providing（ログ故障なし） | 長さ5以下の全実行順で検査済み（`native_decide`） |
| H2 が起きない（SC2）を任意長で | 未証明（`sorry`） |
| H3 が起きない（SC3）を、ログ故障なし・任意長で | 未証明（`sorry`） |
| UCA Not Providing が起きないを、ログ故障なし・任意長で | 未証明（`sorry`） |

未証明の安全主張は、まだ見つかっていないハザードが潜んでいるかもしれない場所なので、
`sorry` のまま残してハザード候補として扱う。`lake build` で警告になり、Lean Atlas でも見える。
-/
namespace RenewalNotice

/-! ## 1ステップで送信記録がどう変わるか -/

@[formalMeta "safeの1ステップの送信" "safeでは、送信記録は変わらないか、tCが今日のものであるときに未送信の対象者分だけ増える" "補題",
  confidence high, proof_progress complete]
theorem safe_step_sent (s : State) (a : Action) :
    (step .safe s a).sent = s.sent ∨
    (s.tC.asOf = s.today ∧ ∃ k, (step .safe s a).sent = s.sent ++ record s (limit k (pending s))) := by
  cases a with
  | runA => exact Or.inl rfl
  | runB => exact Or.inl rfl
  | runC =>
    left
    show (batchC .safe s).sent = s.sent
    simp only [batchC]
    split
    · rfl
    · rfl
  | runD =>
    show (batchDSafe none s).sent = s.sent ∨ _
    by_cases h : s.tC.asOf = s.today
    · exact Or.inr ⟨h, none, by simp [step, batchD, batchDSafe, h]⟩
    · left
      simp [batchDSafe, h]
  | crashD k =>
    show (batchDSafe (some k) s).sent = s.sent ∨ _
    by_cases h : s.tC.asOf = s.today
    · exact Or.inr ⟨h, some k, by simp [step, batchD, batchDSafe, h]⟩
    · left
      simp [batchDSafe, h]
  | use _ => exact Or.inl rfl
  | breakSource => exact Or.inl rfl

/-! ## UCA Timing：任意長で起きない -/

@[formalMeta "safeのCは日付を偽らない" "safeでは、tCに今日の日付が付いていれば、今日のA・Bの結果から作られている（どの動作でも保たれる）" "補題（不変条件）",
  confidence high, proof_progress complete]
theorem step_safe_freshTC (s : State) (a : Action) (h : FreshTC s) :
    FreshTC (step .safe s a) := by
  cases a with
  | runA => exact h
  | runB => exact h
  | runC =>
    show FreshTC (batchC .safe s)
    simp only [batchC]
    split
    · next hc => simp [FreshTC, hc.1, hc.2]
    · exact h
  | runD =>
    show FreshTC (batchDSafe none s)
    unfold batchDSafe
    split
    · exact h
    · exact h
  | crashD k =>
    show FreshTC (batchDSafe (some k) s)
    unfold batchDSafe
    split
    · exact h
    · exact h
  | use _ => exact h
  | breakSource => exact h

@[formalMeta "1ステップでUCA Timingなし" "safeでは、今日の抽出から作られていない対象で送信を始めることはない" "補題",
  confidence high, proof_progress complete]
theorem safe_no_uca_timing_step (s : State) (a : Action) (h : FreshTC s) :
    ucaTiming .safe s a = false := by
  unfold ucaTiming newSends
  rcases safe_step_sent s a with hs | ⟨hd, _, _⟩
  · simp [hs]
  · simp [h hd]

@[formalMeta "対策版にUCA Timingなし" "どんな順序・外乱・長さの実行順でも、抽出完了前に通知を始めない" "記事 UCA Timing/Order が起きない" mainTheorem,
  confidence high, proof_progress complete]
theorem safe_no_uca_timing (t : List Action) (s : State) (h : FreshTC s) :
    ucaInTrace .safe .timing s t = false := by
  induction t generalizing s with
  | nil => rfl
  | cons a t ih =>
    simp only [ucaInTrace, Uca.occurs, safe_no_uca_timing_step s a h, Bool.false_or]
    exact ih _ (step_safe_freshTC s a h)

/-! ## UCA Providing：任意長で起きない -/

@[formalMeta "1ステップでUCA Providingなし" "safeでは、配信基盤が受理済みの人にまた送ることはない" "補題",
  confidence high, proof_progress complete]
theorem safe_no_uca_providing_step (s : State) (a : Action) :
    ucaProviding .safe s a = false := by
  unfold ucaProviding newSends
  rcases safe_step_sent s a with hs | ⟨_, k, hs⟩
  · simp [hs]
  · rw [hs, List.drop_left, map_fst_record, List.any_eq_false]
    intro u hu
    have hn := pending_not_sent s u (mem_limit hu)
    simpa using hn

@[formalMeta "対策版にUCA Providingなし" "どんな順序・外乱・長さの実行順でも、通知済みか不明な人に新しい送信を始めない" "記事 UCA Providing が起きない" mainTheorem,
  confidence high, proof_progress complete]
theorem safe_no_uca_providing (t : List Action) (s : State) :
    ucaInTrace .safe .providing s t = false := by
  induction t generalizing s with
  | nil => rfl
  | cons a t ih =>
    simp only [ucaInTrace, Uca.occurs, safe_no_uca_providing_step s a, Bool.false_or]
    exact ih _

/-! ## H1（SC1）：任意長で起きない -/

@[formalMeta "1ステップでSC1を保つ" "safeのどの動作も、送信記録が対象者宛てだけという性質を壊さない" "補題",
  confidence high, proof_progress complete]
theorem step_safe_sentOk (s : State) (a : Action) (h : SentOk s) :
    SentOk (step .safe s a) := by
  cases a with
  | runA        => exact h
  | runB        => exact h
  | runC        =>
    show SentOk (batchC .safe s)
    simp only [batchC]
    split
    · exact h
    · exact h
  | runD        => exact batchDSafe_sentOk none s h
  | crashD k    => exact batchDSafe_sentOk (some k) s h
  | use _       => exact h
  | breakSource => exact h

@[formalMeta "対策版にH1なし" "どんな順序・外乱・長さの実行順でも、通知対象外の会員に送らない" "記事 H1 が起きない（SC1）" mainTheorem,
  confidence high, proof_progress complete]
theorem safe_no_H1 (t : List Action) (s : State) (h : SentOk s) :
    SentOk (run .safe s t) := by
  induction t generalizing s with
  | nil => exact h
  | cons a t ih => exact ih _ (step_safe_sentOk s a h)

/-! ## 記事のシナリオと有界検査 -/

@[formalMeta "対策版は記事のシナリオA〜Cを防ぐ" "シナリオA・B・Cの実行順でも、対策版はSC1〜SC3を満たす" "記事 Loss Scenario A〜C への対策",
  confidence high, proof_progress complete]
theorem safe_prevents_scenarios_ABC :
    safeAll (run .safe init scenarioA) = true ∧
    safeAll (run .safe init scenarioB) = true ∧
    safeAll (run .safe init scenarioC) = true := by decide

@[formalMeta "対策版の有界全数検査" "ログ故障を除く長さ5以下の全実行順で、SC1〜SC3が成り立ち、UCA Not Providingも起きない" "SC1〜SC3・UCA（有界）" mainTheorem,
  confidence medium, proof_progress complete]
theorem safe_bounded :
    (tracesUpTo alphabetNoSourceFault searchBound).all
      (fun t => safeAll (run .safe init t) && !ucaNotProviding (run .safe init t)) = true := by
  native_decide

/-! ## 未証明の安全主張（ハザード候補） -/

@[formalMeta "対策版にH2なし（未証明）" "どんな長さの実行順でも、同じ会員に重複して送らない" "記事 H2 が起きない（記事の安全制約）：未証明＝ハザード候補" mainTheorem,
  confidence medium, proof_progress stub]
theorem safe_no_H2 (t : List Action) : sc2 (run .safe init t) = true := by
  sorry

@[formalMeta "対策版にH3なし・故障なし（未証明）" "ログ故障がなければ、どんな長さの実行順でも、全ジョブ正常終了時に対象者全員に送られている" "記事 H3 が起きない（SC3）：未証明＝ハザード候補" mainTheorem,
  confidence medium, proof_progress stub]
theorem safe_no_H3_without_fault (t : List Action) (h : noSourceFault t = true) :
    sc3 (run .safe init t) = true := by
  sorry

@[formalMeta "対策版にUCA Not Providingなし・故障なし（未証明）" "ログ故障がなければ、どんな長さの実行順でも、抽出済みの対象者に送らないまま全ジョブ正常にならない" "記事 UCA Not Providing が起きない：未証明＝ハザード候補" mainTheorem,
  confidence medium, proof_progress stub]
theorem safe_no_uca_notProviding_without_fault (t : List Action) (h : noSourceFault t = true) :
    ucaNotProviding (run .safe init t) = false := by
  sorry

end RenewalNotice
