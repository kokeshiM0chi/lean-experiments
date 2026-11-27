# 7. ビルド時の検査（`Audit.lean`）

ソース：[`lean/RenewalNotice/Audit.lean`](../lean/RenewalNotice/Audit.lean)

## この章で言いたいこと

**`lake build` を実行するだけで、ハザード・UCA・未証明の主張が見え、証明状況の表示が実態とずれていないことも保証される。** CI でも同じ `lake build` を実行するので、チームの誰が変更しても同じ検査がかかる。

このファイルは定理ではなく、ビルドのたびに実行される検査プログラムである。2つのことを行う。

| 検査 | 結果の出し方 |
|---|---|
| ハザードと UCA の検出（全実行順の探索） | 見つかったら警告、見つからなければ情報メッセージ |
| 証明状況の照合（注記と実際の証明） | 未証明は警告、注記と実態の食い違いはエラー（ビルドが止まる） |

## ファイルの先頭

```lean
import Lean
import RenewalNotice.Hazards
import RenewalNotice.SafeDesign
```

```lean
open Lean Elab Command
open LeanAtlas.Metadata

-- この中は検査用のプログラムで、主張（定理）ではないので Lean Atlas の注記を求めない
set_option linter.confidenceCheck false
set_option linter.defProgressCheck false
```

- `import Lean` で、Lean 自身の機能（メッセージを出す、定理の情報を調べる）を使えるようにする
- `Hazards` と `SafeDesign` を読み込むので、このファイルはすべての定理の検査が終わった後にビルドされる
- Lean Atlas は、注記のない定義に警告を出す。このファイルの関数は主張ではないので、その警告を止めている

## 検査1：ハザードと UCA の検出

### ここで言いたいこと

ビルドのたびに、全実行順を探索し、naive と safe のそれぞれでハザードと UCA が起きるかを報告する。[6章](06-counterexamples.md)の `lake exe explore` と同じ探索を、ビルドの中で行う。

```lean
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
```

### 読み方

- `CommandElabM Unit` は「Lean がファイルを処理している最中に実行できるプログラム」の型である。この中で `logWarning` を呼ぶと、ビルドの警告として表示される
- 設計 × ハザードについて `counterexample` で反例を探し、見つかれば警告、なければ情報メッセージを出す
- 設計 × UCA についても、`ucaExample` で同じことをする

### 実行する

```lean
#eval RenewalNotice.Audit.scanHazards
```

`#eval` は、ファイルを処理するときにその場でプログラムを実行する。`lake build` はファイルを処理するので、そのたびにこの探索が走る。

実際の出力：

```text
warning: ハザード検出 [naive] H1: 通知対象外のユーザーが、退会案内の配信対象に含まれている (→L1)
  Loss Scenario: ["D"] （安全制約を初めて破った制御動作: D）
warning: ハザード検出 [naive] H2: 同じユーザー・契約更新期に対する通知が、重複して発行可能な状態にある (→L2)
  Loss Scenario: ["D", "D"] （安全制約を初めて破った制御動作: D）
warning: ハザード検出 [naive] H3: 案内が必要な対象者について、通知期限までに送信を開始できない状態にある (→L3)
  Loss Scenario: ["A", "B", "D", "C"] （安全制約を初めて破った制御動作: C）
warning: UCA検出 [naive] Not Providing: 対象者の抽出が完了しているのに、期限までに送信を開始しない
  実行順: ["A", "B", "D", "C"]
warning: UCA検出 [naive] Providing: 通知済みか不明なユーザーに対して、新しい送信を開始する
  実行順: ["D", "D"]
warning: UCA検出 [naive] Timing / Order: 対象者抽出の完了前に通知を開始する
  実行順: ["D"]
info: [safe] H1: 長さ5以下の反例なし
info: [safe] H2: 長さ5以下の反例なし
warning: ハザード検出 [safe] H3: 案内が必要な対象者について、通知期限までに送信を開始できない状態にある (→L3)
  Loss Scenario: ["B", "breakSource", "A", "C", "D"] （安全制約を初めて破った制御動作: D）
info: [safe] UCA Not Providing: 長さ5以下では起きない
info: [safe] UCA Providing: 長さ5以下では起きない
info: [safe] UCA Timing / Order: 長さ5以下では起きない
```

ハザードが見つかっても、ビルドは失敗しない。naive のハザードは、わざと残しているものだからである。

## 検査2：証明状況の照合

### ここで言いたいこと

Lean Atlas の注記（`@[proof_progress complete]` や `@[proof_progress stub]`）は、人が手で書くものである。手で書いた注記は、証明を進めたり壊したりしたときに、実態とずれる。

そこで、ビルドのたびに、注記と「実際に `sorry` に頼っているか」を照合する。ずれていればビルドをエラーで止める。

```lean
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
```

### 読み方

1. `getAllProofProgressEntries env` で、`@[proof_progress ...]` が付いた定理を全部取り出す（Lean Atlas の機能）。このプロジェクトの定理（名前が `RenewalNotice.` で始まるもの）だけに絞り、名前順に並べる
2. 各定理について、`collectAxioms` で「その証明が最終的に頼っている公理」を集める。依存先の補題も、すべてたどる
   - 証明のどこかに `sorry` があれば、`sorryAx` が入る
   - `native_decide` を使っていれば、名前に `_native` を含む補助の公理が入る
3. 注記と照らし合わせる

| 注記 | `sorry` に依存しているか | 結果 |
|---|---|---|
| `complete` | していない | 証明済みとして数える。`native_decide` に依存していれば、その数も数える |
| `complete` | している | **エラー**：証明済みと書いてあるのに、依存先に未証明の補題がある |
| `stub` など | している | 警告：未証明の主張（ハザード候補）として報告する |
| `stub` など | していない | **エラー**：未証明と書いてあるのに、実は証明済み。注記の更新漏れ |

4. 最後に件数をまとめて表示する

### lean-atlas 自身の検査との違い

lean-atlas も、`@[proof_progress complete]` が付いた定理に `sorry` があればエラーにする。ただし、見るのは**その定理の中に直接書かれた `sorry` だけ**である。

```lean
-- lean-atlas の検査では見逃す例
theorem helper : P := by sorry            -- ここに sorry がある

@[proof_progress complete]
theorem main_result : Q := by
  exact use_helper helper                 -- main_result 自体には sorry がない
```

`main_result` は `helper` に頼っているので、実質的には未証明である。このファイルの検査は `collectAxioms` で依存先までたどるので、これをエラーにできる。

### 実行する

```lean
#eval RenewalNotice.Audit.auditProofStatus
```

実際の出力：

```text
warning: 未証明の主張（ハザード候補）: RenewalNotice.safe_no_H2（注記: stub）
warning: 未証明の主張（ハザード候補）: RenewalNotice.safe_no_H3_without_fault（注記: stub）
warning: 未証明の主張（ハザード候補）: RenewalNotice.safe_no_uca_notProviding_without_fault（注記: stub）
info: 証明状況: 証明済み 33 件（うち native_decide に依存 1 件）、未証明 3 件
```

### ずれを検出できることの確認

証明済みの `scenarioB_H2` の注記を、わざと `proof_progress stub` に書き換えてビルドすると、次のエラーで止まる。

```text
error: RenewalNotice.scenarioB_H2: stub と注記されているが、実際は sorry なしで証明済み。注記を complete に更新すること
error: build failed
```

逆に、`sorry` がある定理に `proof_progress complete` を付けると、lean-atlas 自身の検査で次のエラーになる。

```text
error: @[proof_progress complete] cannot be used with definitions containing sorry. Use 'partially', 'mostly', or 'stub' instead.
```

## ビルドのメッセージの全体像

`lake build` の出力には、この章の検査の結果と、Lean 自身の警告が混ざる。

| メッセージ | 出しているもの | 意味 |
|---|---|---|
| `warning: declaration uses 'sorry'` | Lean 自身 | その定理は証明が省略されている |
| `warning: ハザード検出 ...` | 検査1 | 安全制約を破る実行順が見つかった |
| `warning: UCA検出 ...` | 検査1 | UCA に当たる制御動作を含む実行順が見つかった |
| `info: ... 反例なし` / `... 起きない` | 検査1 | 長さ5以下では見つからなかった |
| `warning: 未証明の主張（ハザード候補）...` | 検査2 | `sorry` に依存する主張がある |
| `info: 証明状況: ...` | 検査2 | 証明済み・未証明の件数 |
| `error: ... と注記されているが ...` | 検査2 | 注記と実態がずれている。ビルドが止まる |
| `error: ...`（その他） | Lean 自身 | 証明が通らない。ビルドが止まる |

## 自分のアプリに当てはめるとき

このファイルはほぼそのまま使える。変えるのは次の部分だけである。

- `RenewalNotice` という名前空間を、自分のプロジェクトのものにする（`getRoot == \`RenewalNotice` の部分を含む）
- ループで回すハザードと UCA の一覧を、自分の STPA の分析結果に合わせる

対策版で新しいハザードが見つかったら CI を失敗させたい場合は、safe の結果を `logWarning` ではなく `logError` で出すように変える。ただし、既知の残留ハザード（このプロジェクトでは、ログ故障による H3）は例外として扱う必要がある。
