import RenewalNotice.Spec
/-!
# パターン1：組み合わせの安全制約を書かない場合

各バッチの単体仕様（`RenewalNotice/Spec.lean`）だけを読み込み、
「4つのバッチは、どれも単体仕様どおりに動く」ことを1つの定理にまとめる。

組み合わせたときの安全制約（SC1〜SC3）については、何も主張しない。

    lake build DetectWithoutConstraint

ビルドは成功し、ハザードについての警告も出ない。Lean は書かれた主張しか検査しないので、
組み合わせについて主張していなければ、組み合わせの問題は検出されない。
単体テストがすべて通っても、組み合わせの事故を見つけられないのと同じである。
-/
-- この版は説明用なので、Lean Atlas の注記を求めない
set_option linter.confidenceCheck false
set_option linter.proofProgressCheck false
set_option linter.defProgressCheck false

namespace RenewalNotice.Detect

/-- 対策なし版の4つのバッチは、すべての入力について単体仕様どおりに動く。 -/
theorem naive_units_correct :
    (∀ s u, (u ∈ (batchA s).tA.rows ↔ u ∈ s.world.users ∧ s.world.inactiveLog.contains u = true) ∧
            (batchA s).tA.asOf = s.today ∧ (batchA s).rA = .ok) ∧
    (∀ s u, (u ∈ (batchB s).tB.rows ↔ u ∈ s.world.users ∧ s.world.renewing.contains u = true) ∧
            (batchB s).tB.asOf = s.today ∧ (batchB s).rB = .ok) ∧
    (∀ s u, (u ∈ (batchC .naive s).tC.rows ↔ u ∈ s.tA.rows ∧ s.tB.rows.contains u = true) ∧
            (batchC .naive s).rC = .ok) ∧
    (∀ s, sentUsers (batchD .naive none s) = sentUsers s ++ s.tC.rows ∧
          (batchD .naive none s).rD = .ok) :=
  ⟨batchA_spec, batchB_spec, batchC_naive_spec, batchD_naive_spec⟩

end RenewalNotice.Detect
