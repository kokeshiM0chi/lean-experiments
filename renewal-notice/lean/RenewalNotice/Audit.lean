import Lean
import RenewalNotice.Hazards
import RenewalNotice.SafeDesign
/-!
# ビルド時の検査

`lake build` のたびに次の2つを実行し、結果をビルドのメッセージとして出す。

1. ハザードと UCA の検出：長さ `searchBound` 以下の全実行順を試し、安全制約を破るものと、
   記事の UCA に当たる制御動作を含むものを、警告として出す
2. 証明状況の照合：Lean Atlas の `@[proof_progress]` の注記と、実際に `sorry` に依存しているかを
   照合する。食い違っていればビルドをエラーにする

2 は依存先の補題までたどって調べる（`collectAxioms`）。lean-atlas 自身の検査は、
その宣言の中に直接書かれた `sorry` しか見ないので、間接的な依存はここで補う。
-/
open Lean Elab Command
open LeanAtlas.Metadata

-- この中は検査用のプログラムで、主張（定理）ではないので Lean Atlas の注記を求めない
set_option linter.confidenceCheck false
set_option linter.defProgressCheck false

namespace RenewalNotice.Audit

/-- 全設計・全ハザードについて反例を探し、見つかったものを警告として出す。 -/
def scanHazards : CommandElabM Unit := do
  for d in [Design.naive, Design.safe] do
    for h in [Hazard.H1, Hazard.H2, Hazard.H3] do
      match counterexample d h alphabet searchBound with
      | some t =>
        let uca := match firstViolation d h init t with
          | some (_, a) => s!"（安全制約を初めて破った制御動作: {a.str}）"
          | none => ""
        logWarning m!"ハザード検出 [{d.name}] {h.name}: {h.describe}\n  Loss Scenario: {traceStr t} {uca}"
      | none =>
        logInfo m!"[{d.name}] {h.name}: 長さ{searchBound}以下の反例なし"
    for u in [Uca.notProviding, Uca.providing, Uca.timing] do
      match ucaExample d u alphabet searchBound with
      | some t =>
        logWarning m!"UCA検出 [{d.name}] {u.name}: {u.describe}\n  実行順: {traceStr t}"
      | none =>
        logInfo m!"[{d.name}] UCA {u.name}: 長さ{searchBound}以下では起きない"

def progressStr : ProofProgress → String
  | .complete  => "complete"
  | .mostly    => "mostly"
  | .partially => "partially"
  | .stub      => "stub"

/-- `@[proof_progress]` の注記と、実際の `sorry` への依存を照合する。 -/
def auditProofStatus : CommandElabM Unit := do
  let env ← getEnv
  let entries := (getAllProofProgressEntries env).filter (·.declName.getRoot == `RenewalNotice)
  let entries := entries.qsort (fun a b => a.declName.toString < b.declName.toString)
  let mut proven : Nat := 0
  let mut native : Nat := 0
  let mut unproven : Nat := 0
  for e in entries do
    let axs ← collectAxioms e.declName
    let usesSorry := axs.contains ``sorryAx
    -- native_decide は `<定理名>._native.native_decide.ax_…` という補助の公理を作る
    let usesNative := axs.any (fun n => (n.components.contains `_native))
    if e.proofProgress == .complete then
      if usesSorry then
        logError m!"{e.declName}: complete と注記されているが、依存先に未証明（sorry）の補題がある"
      else
        proven := proven + 1
        if usesNative then native := native + 1
    else
      if usesSorry then
        unproven := unproven + 1
        logWarning m!"未証明の主張（ハザード候補）: {e.declName}（注記: {progressStr e.proofProgress}）"
      else
        logError m!"{e.declName}: {progressStr e.proofProgress} と注記されているが、実際は sorry なしで証明済み。注記を complete に更新すること"
  logInfo m!"証明状況: 証明済み {proven} 件（うち native_decide に依存 {native} 件）、未証明 {unproven} 件"

end RenewalNotice.Audit

#eval RenewalNotice.Audit.scanHazards
#eval RenewalNotice.Audit.auditProofStatus
