import RenewalNotice.Spec
/-!
# 証明の失敗から反例を組み立てる

`Detect/WithConstraint.lean` のビルドが失敗したとき、残ったゴールは次のことを言っている。

| 安全制約 | 残ったゴール（Lean の表示そのまま） | 読み方 |
|---|---|---|
| SC1 | `hu : u ∈ limit k s.tC.rows` ⊢ `(u, s.world.isTarget u).snd = true` | D は tC にいる u に送るが、u が本当の対象者である保証がない |
| SC2 | ⊢ `∀ (a : User), a ∈ List.map (fun x => x.fst) s.sent → ∀ (b : User), b ∈ limit k s.tC.rows → a ≠ b` | 送信済みの人と、D が今回送る tC の人が重ならない保証がない |

ただし、ゴールが証明できないことは、まだ「ハザードがある」ことを意味しない。
ゴールが求める状況（tC に対象外の会員がいる、など）に、初期状態から実際に到達できなければ、
それは証明の仕方（不変条件）が弱いだけかもしれない。

そこで、ゴールの状況に実際に到達する実行順を組み立て、`decide` で確かめる。
確かめられれば、それが本物の反例（バグ）になる。

    lake build DetectCounterexample
-/
-- この版は説明用なので、Lean Atlas の注記を求めない
set_option linter.confidenceCheck false
set_option linter.proofProgressCheck false
set_option linter.defProgressCheck false

namespace RenewalNotice.Detect

/-! ## SC1 の反例：tC に対象外の会員がいる状況 -/

-- ゴールの状況に到達する最短の実行順を探す（docs/10-practice.md の手順3）。
-- 空の実行順（初期状態）ですでに到達している（`some []`）。
#eval (tracesUpTo alphabet 5).find?
  (fun t => let s := run .naive init t; s.tC.rows.any (fun u => !s.world.isTarget u))

/-- 失敗したゴールが求める状況「tC に、本当の対象者でない会員がいる」は、初期状態ですでに成り立っている。
    前回サイクルの tC に残っている会員0は、最近利用を再開したので対象外である。 -/
theorem sc1_goal_reachable_at_init :
    0 ∈ init.tC.rows ∧ init.world.isTarget 0 = false := by decide

/-- したがって、初期状態で D を1回実行するだけで SC1 が破れる（H1）。 -/
theorem sc1_counterexample : sc1 (run .naive init [.runD]) = false := by decide

/-! ## SC2 の反例：tC に送信済みの会員がいる状況 -/

/-- 失敗したゴールが求める状況「tC にいる会員が、すでに送信済み」は、D を1回実行した後に成り立つ。
    tC は変わらず会員0を含み、会員0はすでに送信済みである。 -/
theorem sc2_goal_reachable_after_D :
    0 ∈ (run .naive init [.runD]).tC.rows ∧ (sentUsers (run .naive init [.runD])).contains 0 = true := by
  decide

/-- したがって、D をもう1回実行すると SC2 が破れる（H2）。 -/
theorem sc2_counterexample : sc2 (run .naive init [.runD, .runD]) = false := by decide

end RenewalNotice.Detect
