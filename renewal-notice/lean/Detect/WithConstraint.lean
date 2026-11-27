import RenewalNotice.Spec
/-!
# パターン2：組み合わせの安全制約を定理として書く場合

対策なし版について、「どんな実行順でも安全制約が守られる」を定理として書き、
対策版と同じ証明の方針（1ステップで保たれることを示し、帰納法で任意の長さに広げる）で証明を試みる。

    lake build DetectWithConstraint

ビルドは失敗する。失敗するのは「D を1回実行しても安全制約が保たれる」の部分だけで、
エラーには、証明しきれずに残った条件（ゴール）が表示される。そのゴールが、

* どの制御動作で（D）
* どんな状況なら（tC に対象外の会員がいる／tC に送信済みの会員がいる）
* 安全制約が破れるか

を示している。実行順を1本も列挙していない。すべての状態と、制御動作の種類（7通り）を
記号的に扱っているので、実行順の長さの上限もない。

失敗したゴールから組み立てた反例は `Detect/Counterexample.lean` で確かめる。
-/
-- この版は説明用なので、Lean Atlas の注記を求めない
set_option linter.confidenceCheck false
set_option linter.proofProgressCheck false
set_option linter.defProgressCheck false

namespace RenewalNotice.Detect

/-! ## SC1（H1 の否定）：送信記録はすべて、送った時点で本当の対象者宛て -/

/-- D を1回実行しても SC1 が保たれる。

対策版の `batchDSafe_sentOk` と同じ手順で証明を試みる。対策版では、送る相手（`pending`）を作るときに
`isTarget` を確かめているので最後のゴールが閉じる。対策なし版はそれを確かめていないので、
`(u, s.world.isTarget u).2 = true`（tC にいる u が本当の対象者であること）が証明できずに残る。 -/
theorem naive_D_preserves_sc1 (k : Option Nat) (s : State) (h : SentOk s) :
    SentOk (batchDNaive k s) := by
  intro p hp
  simp only [batchDNaive, List.mem_append, record, List.mem_map] at hp
  rcases hp with hp | ⟨u, hu, rfl⟩
  · exact h p hp
  · skip

/-- どの制御動作を1回実行しても SC1 が保たれる。D 以外は送信記録に触らないので証明できる。 -/
theorem naive_step_preserves_sc1 (s : State) (a : Action) (h : SentOk s) :
    SentOk (step .naive s a) := by
  cases a with
  | runA        => exact h
  | runB        => exact h
  | runC        => exact h
  | runD        => exact naive_D_preserves_sc1 none s h
  | crashD k    => exact naive_D_preserves_sc1 (some k) s h
  | use _       => exact h
  | breakSource => exact h

/-- 対策なし版でも、どんな実行順でも H1 は起きない（と主張する）。 -/
theorem naive_no_H1 (t : List Action) (s : State) (h : SentOk s) :
    SentOk (run .naive s t) := by
  induction t generalizing s with
  | nil => exact h
  | cons a t ih => exact ih _ (naive_step_preserves_sc1 s a h)

/-! ## SC2（H2 の否定）：同じ会員に重複して送らない -/

/-- 送信済みの一覧に重複がない（SC2 を命題にしたもの）。 -/
def SentNodup (s : State) : Prop := (sentUsers s).Nodup

/-- D を1回実行しても SC2 が保たれる。

今回送る相手の中に重複がないこと（`hk`）は仮定に置き、
「送信済みの人に、また送らないか」だけを問題にする。
対策版は送る相手から送信済みの人を除いている（`pending_not_sent`）ので証明できる。
対策なし版は除いていないので、「送信済みの人と、今回送る人が重ならない」が証明できずに残る。 -/
theorem naive_D_preserves_sc2 (k : Option Nat) (s : State) (h : SentNodup s)
    (hk : (limit k s.tC.rows).Nodup) :
    SentNodup (batchDNaive k s) := by
  simp only [SentNodup, sentUsers, batchDNaive, List.map_append, map_fst_record] at h ⊢
  rw [List.nodup_append]
  refine ⟨h, hk, ?_⟩
  skip

end RenewalNotice.Detect
