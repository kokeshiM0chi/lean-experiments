# 4. それでも組み合わせると危険（`Scenarios.lean`、`Hazards.lean`）

ソース：[`lean/RenewalNotice/Scenarios.lean`](../lean/RenewalNotice/Scenarios.lean)、[`lean/RenewalNotice/Hazards.lean`](../lean/RenewalNotice/Hazards.lean)

## この章で言いたいこと

**各バッチは単体で正しい（[3章](03-spec.md)）のに、組み合わせると安全制約を破る実行順がある。** これが STAMP の「部品が正常でも事故は起きる」の形式化である。

具体的には、次の3種類の定理を書いている。

| 言いたいこと | 定理 |
|---|---|
| 元記事の Loss Scenario A〜D で、実際にハザードが起きる | `scenarioA_H1`、`scenarioB_H2`、`scenarioC_H2`、`scenarioD_H3` |
| 元記事の UCA が実際に起き、ハザードにつながる | `uca_timing_naive`、`uca_providing_naive`、`uca_notProviding_naive` |
| まとめて「対策なし版は安全ではない」 | `naive_unsafe` |

## ハザードの扱い方

「証明できなかったらハザード」とはしていない。Lean は、証明に失敗した理由（主張が偽なのか、証明が下手なだけなのか）を区別できないからである。

その代わりに、**安全制約を破る実行順を具体的に1つ示し、それで本当に破れることを Lean に検査させる。** 示した実行順が、STPA の Loss Scenario になる。

## シナリオを実行順として書く（`Scenarios.lean`）

```lean
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
```

元記事の文章を、`Action` の並びに置き換えただけである。「A が遅延して C が先に起動する」は「C を A より前に並べる」、「タイムアウト」は「`crashD 2`（2件受理された後で失敗）」と表している。

記事にないシナリオも同じファイルに置いている。

```lean
/-- 自動探索で見つかった最短の H1：前回分の表 tC のまま D が送る。 -/
def traceOnlyD : List Action := [.runD]
/-- 自動探索で見つかった最短の H2：送信済みを確かめずに D を2回実行する。 -/
def traceDTwice : List Action := [.runD, .runD]
/-- 自動探索で見つかった H3：D が C より先に古い表で送り、最後に C が終わって全ジョブが正常に見える。 -/
def traceDBeforeC : List Action := [.runA, .runB, .runD, .runC]
/-- C が対象を確定した後、D が送る前に会員が利用を再開する（TOCTOU）。 -/
def traceTOCTOU : List Action := [.runA, .runB, .runC, .use 1, .runD]
```

## 元記事のシナリオでハザードが起きる

### ここで言いたいこと

元記事のシナリオ A〜D を対策なし版（naive）で実行すると、それぞれ安全制約が破れる。

```lean
@[formalMeta "シナリオA：依存関係が守られない" "Aが遅延中にCが時刻どおり起動し、前回のAの結果で対象を作るので、対象外の会員0に届く" "記事 Loss Scenario A → H1 → L1",
  confidence high, proof_progress complete]
theorem scenarioA_H1 : sc1 (run .naive init scenarioA) = false := by decide

@[formalMeta "シナリオB：部分失敗後のリトライ" "Dが1人に送った時点で異常終了し、D全体の再実行でその人にまた送る" "記事 Loss Scenario B → H2 → L2",
  confidence high, proof_progress complete]
theorem scenarioB_H2 : sc2 (run .naive init scenarioB) = false := by decide

@[formalMeta "シナリオC：送信状態を認識できない" "配信基盤は全員分を受理したがタイムアウトし、Dの再実行で全員にまた送る" "記事 Loss Scenario C → H2 → L2",
  confidence high, proof_progress complete]
theorem scenarioC_H2 : sc2 (run .naive init scenarioC) = false := by decide

@[formalMeta "シナリオD：正常終了なのに届かない" "ログ故障でAが0件のまま正常終了し、全ジョブ正常なのに対象者に届かない" "記事 Loss Scenario D → H3 → L3",
  confidence high, proof_progress complete]
theorem scenarioD_H3 : sc3 (run .naive init scenarioD) = false := by decide
```

### 読み方

たとえば `scenarioA_H1` は、「初期状態からシナリオA の順に naive のバッチを実行すると、安全制約 SC1 が false になる（＝ H1 が起きる）」と読む。

### 証明の中身

どれも `by decide` の1語である。`decide` は、主張を実際に計算して確かめる。

1. `run .naive init scenarioA` を計算する。[1章](01-model.md)の表のとおり、送信記録は `[(0, false), (1, true)]` になる
2. `sc1` を計算する。送信記録の第2成分に false があるので、`sc1` は false
3. 主張は `false = false` になり、正しいと確かめられる

計算は Lean のカーネル（証明を検査する核の部分）が行うので、計算結果そのものが証明になる。

各シナリオの計算結果は次のとおり。

| シナリオ | 送信記録（宛先） | 破れる安全制約 |
|---|---|---|
| A：B, C, A, D | 0, 1（会員0は対象外、会員2には届かない） | SC1（H1）。全ジョブ正常終了なので SC3（H3）も |
| B：A, B, C, crashD 1, D | 1, 1, 2 | SC2（H2） |
| C：A, B, C, crashD 2, D | 1, 2, 1, 2 | SC2（H2） |
| D：breakSource, A, B, C, D | なし | SC3（H3） |

```lean
#eval sentUsers (run .naive init scenarioC)   -- [1, 2, 1, 2]
```

## UCA が起きて、ハザードにつながる

### ここで言いたいこと

元記事の UCA 表の3つが、対策なし版で実際に起き、それぞれハザードにつながる。

```lean
@[formalMeta "UCA Timing：抽出完了前に通知" "シナリオAの最後のDは、今日のAの結果から作られていない対象で送信を始め、H1になる" "記事 UCA Timing/Order → H1",
  confidence high, proof_progress complete]
theorem uca_timing_naive :
    ucaTiming .naive (run .naive init [.runB, .runC, .runA]) .runD = true ∧
    sc1 (run .naive init scenarioA) = false := by decide

@[formalMeta "UCA Providing：通知済みの人に再送" "シナリオCで、配信基盤が受理済みの人に、Dの再実行でまた送り、H2になる" "記事 UCA Providing → H2",
  confidence high, proof_progress complete]
theorem uca_providing_naive :
    ucaProviding .naive (run .naive init [.runA, .runB, .runC, .crashD 2]) .runD = true ∧
    sc2 (run .naive init scenarioC) = false := by decide

@[formalMeta "UCA Not Providing：抽出済みなのに送らない" "DがCより先に古い表で送り、最後にCが終わると、今日の対象者に送られないまま全ジョブ正常になり、H3になる" "記事 UCA Not Providing → H3",
  confidence high, proof_progress complete]
theorem uca_notProviding_naive :
    ucaNotProviding (run .naive init traceDBeforeC) = true ∧
    sc3 (run .naive init traceDBeforeC) = false := by decide
```

### 読み方

`uca_timing_naive` は2つの主張を「かつ」でつないでいる。

1. シナリオA の途中（B, C, A まで実行した状態）で D を出すと、それは UCA の Timing に当たる
2. シナリオA を最後まで実行すると、SC1 が破れる（H1）

つまり「シナリオA の最後の D が UCA であり、その結果 H1 が起きる」という因果のつながりを、1つの定理として書いている。他の2つも同じ形である。

### 証明の中身

どれも `by decide`。状態を計算し、UCA の関数と安全制約の関数がそれぞれ true / false になることを確かめている。

## シナリオD は通知制御の UCA ではない

### ここで言いたいこと

形式化して初めて分かったことがある。シナリオD では、通知制御（C と D）の UCA は1つも起きていない。

```lean
@[formalMeta "シナリオDは通知制御のUCAではない" "シナリオDでは通知制御のUCAは起きていない。H3の原因は、A（抽出）の出力が不完全なこと" "記事 Loss Scenario D の分析",
  confidence high, proof_progress complete]
theorem scenarioD_no_notification_uca :
    ucaInTrace .naive .timing init scenarioD = false ∧
    ucaInTrace .naive .providing init scenarioD = false ∧
    ucaInTrace .naive .notProviding init scenarioD = false := by decide
```

### 読み方

シナリオD のどの時点でも、Timing・Providing・Not Providing のどれも起きていない。

シナリオD では、A が0件の表を書く。C は0件の積集合を取り、D は0人に送る。通知制御は、渡された対象者（0件）に対して正しく動いている。それでも H3（対象者に届かない）は起きる（`scenarioD_H3`）。

原因は、抽出バッチ A の出力が不完全なことである。元記事の UCA 表は通知制御だけを対象にしているので、このシナリオの原因を UCA として捉えるには、抽出バッチの制御動作についても UCA を考える必要がある。

## 記事にないシナリオ

```lean
@[formalMeta "追加：Dだけで起きるH1" "前回分の表tCのままDが送る（自動探索で見つかった最短の反例）" "Loss Scenario → H1",
  confidence high, proof_progress complete]
theorem H1_onlyD : sc1 (run .naive init traceOnlyD) = false := by decide

@[formalMeta "追加：Dを2回でH2" "送信済みを確かめずにDを再実行する（自動探索で見つかった最短の反例）" "Loss Scenario → H2",
  confidence high, proof_progress complete]
theorem H2_DTwice : sc2 (run .naive init traceDTwice) = false := by decide

@[formalMeta "追加：TOCTOU" "Cが対象を確定した後、Dが送る前に会員が利用を再開し、対象外に送る" "Loss Scenario → H1",
  confidence high, proof_progress complete]
theorem H1_toctou : sc1 (run .naive init traceTOCTOU) = false := by decide
```

`H1_onlyD` と `H2_DTwice` は、[6章](06-counterexamples.md)の自動探索が見つけた最短の反例を、そのまま定理にしたものである。元記事のシナリオより短く、「前回分の表のまま D を1回実行するだけで H1 が起きる」ことを示している。

## まとめて「対策なし版は安全ではない」

### ここで言いたいこと

個々のシナリオではなく、「どんな実行順でも安全」という主張そのものが偽であることを示す。

```lean
@[formalMeta "部品は正常でもシステムは危険" "各バッチは単体仕様どおりだが、組み合わせると安全制約を破る実行順が存在する" "STPA: Hazard の存在" mainTheorem,
  confidence high, proof_progress complete]
theorem naive_unsafe :
    ¬ ∀ t : List Action, safeAll (run .naive init t) = true := by
  intro h
  exact absurd (h scenarioB) (by decide)
```

### 読み方

「どんな実行順 `t` でも、naive は安全制約をすべて満たす」は成り立たない。

[3章](03-spec.md)の「各バッチは単体で正しい」と並べると、「部品は正常なのに、システムは安全ではない」という STAMP の主張そのものになる。

### 証明の中身

「〜ではない」を示すには、「〜だと仮定すると矛盾する」ことを示す。

1. `intro h`：「どんな実行順でも安全」を仮定として取り出し、`h` と名付ける
2. `h scenarioB`：仮定 `h` をシナリオB に当てはめると、「シナリオB でも安全（`safeAll ... = true`）」が得られる
3. `by decide`：一方で、シナリオB を実際に計算すると `safeAll` は false になる。つまり「`safeAll ... = true` ではない」
4. `absurd`：同じ主張について「成り立つ」と「成り立たない」が両方得られたので、矛盾。これで証明が終わる

反例を1つ（ここではシナリオB）示すだけで、全称の主張を否定できる。

## 対策後も残るハザード

```lean
@[formalMeta "残留ハザード：シナリオD" "対策版でも、ログ故障でAが0件になると対象者に届かない" "記事 Loss Scenario D → 新しい安全要求（対象者集合の完全性）" mainTheorem,
  confidence high, proof_progress complete]
theorem safe_residual_scenarioD : sc3 (run .safe init scenarioD) = false := by decide
```

読み方：対策版（safe）でシナリオD を実行しても、SC3 が破れる（H3 が残る）。

対策版は「基準日の確認」と「送信済みの確認」を実装したが、「抽出結果の件数が正しいか」は確かめていない。A が0件でも、今日の日付が付いていれば C も D も先に進んでしまう。この定理が、元記事の残りの設計要求（対象者集合の完全性の確認、0件の検証）が必要な理由になっている。
