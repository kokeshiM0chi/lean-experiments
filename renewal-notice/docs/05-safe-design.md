# 5. 対策版の安全性（`SafeDesign.lean`）

ソース：[`lean/RenewalNotice/SafeDesign.lean`](../lean/RenewalNotice/SafeDesign.lean)

## この章で言いたいこと

対策版（safe）が、元記事のハザードと UCA をどこまで防げているかを、保証の強さごとに分けて示す。

| 保証の強さ | 何を言っているか | 定理 |
|---|---|---|
| 任意長で証明済み | どんな順序・外乱・長さの実行順でも起きない | `safe_no_uca_timing`、`safe_no_uca_providing`、`safe_no_H1` |
| 記事のシナリオで証明済み | 記事のシナリオ A〜C では安全制約が守られる | `safe_prevents_scenarios_ABC` |
| 有界検査 | 長さ5以下の全実行順（ログ故障を除く）では起きない | `safe_bounded` |
| 未証明（`sorry`） | 任意長で起きないと思うが、まだ証明できていない | `safe_no_H2`、`safe_no_H3_without_fault`、`safe_no_uca_notProviding_without_fault` |

対策版が実装している元記事の設計要求は次の3つである（[1章](01-model.md)の safe のバッチ C・D）。

| 元記事の設計要求 | 対策版での実装 |
|---|---|
| 抽出バッチの成功だけでなく、基準日時を確認する | C と D は、入力の表の基準日が今日でなければ失敗で終わる |
| 同一ユーザーへの通知指示を一意に管理する | D は配信基盤の受理記録を見て、受理済みの人には送らない |
| 配信結果が不明な場合、自動再送を行わない | タイムアウトでも受理記録に残るので、再実行しても送らない |

## 任意長の証明の考え方：帰納法

「どんな長さの実行順でも成り立つ」は、具体的な実行順を全部試すことでは示せない（実行順は無限にある）。そこで帰納法を使う。

1. **1ステップの補題**：ある性質 P が成り立っている状態で、どの動作を1つ実行しても、P は成り立ったままである
2. **帰納法**：最初の状態で P が成り立っていれば、1ステップの補題を繰り返し使って、何ステップ後でも P が成り立つ

```text
P(s0) ─動作1→ P(s1) ─動作2→ P(s2) ─ … ─動作n→ P(sn)
      1ステップの補題を、動作の数だけ繰り返し使う
```

このファイルの任意長の定理は、すべてこの形をしている。

## 補題：safe の1ステップで送信記録はどう変わるか

### ここで言いたいこと

safe では、1つの動作で送信記録は「変わらない」か、「tC が今日のものであるときに、`pending s`（未送信かつ今も対象の人）の一部が追加される」かのどちらかである。後の UCA の証明は、この補題で場合分けする。

```lean
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
```

### 読み方

どんな状態 `s` と動作 `a` についても、次のどちらかが成り立つ。

- 動作後の送信記録は、動作前と同じ
- tC は今日のもので、ある `k` について、動作後の送信記録は「動作前の記録 ＋ `limit k (pending s)` の人への送信」

### 証明の中身

`cases a` で、動作の種類ごとに示す。

- `runA`、`runB`、`use`、`breakSource`：送信記録に触らないので、「変わらない」側（`Or.inl`）が計算だけで成り立つ（`rfl`）
- `runC`：C は `if` で2つに分かれるが、どちらの枝でも送信記録に触らない。`split` で分けて、それぞれ `rfl`
- `runD`、`crashD k`：`by_cases` で「tC が今日のものか」に分ける
  - 今日のものなら、追加される側（`Or.inr`）。`k` には `none`（全員）または `some k` を渡す
  - そうでなければ、D は何も送らないので「変わらない」側

## UCA Timing：どんな長さでも起きない

### ここで言いたいこと

safe では、「今日の A・B の結果から作られていない通知対象で、送信を始める」ことは、どんな実行順でも起きない。

### 不変条件：safe の C は日付を偽らない

まず、証明に使う性質（不変条件）を決める。[`Scenarios.lean`](../lean/RenewalNotice/Scenarios.lean) で定義している。

```lean
/-- tC に今日の日付が付いているなら、本当に今日の A・B の結果から作られている。 -/
def FreshTC (s : State) : Prop := s.tC.asOf = s.today → s.tCInputsAsOf = s.today
```

safe のどの動作も、この性質を壊さないことを示す。

```lean
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
```

読み方：動作前に FreshTC が成り立っていれば（仮定 `h`）、safe でどの動作をしても、動作後も FreshTC が成り立つ。

証明の中身：

- C 以外の動作は、tC も `tCInputsAsOf` も今日の日付も変えないので、仮定 `h` がそのまま使える
- C で、入力が今日のもの（`hc`）なら：新しい tC は今日の日付、`tCInputsAsOf` は `min tA.asOf tB.asOf`。`hc` から両方とも今日なので、`min` も今日になる。`simp [FreshTC, hc.1, hc.2]` がこれを計算して閉じる
- C で、入力が古いなら：C は tC を変えないので、仮定 `h` がそのまま使える

naive の C は、古い入力でも tC に今日の日付を付けるので、この不変条件は成り立たない。ここが naive と safe の違いである。

### 1ステップの補題

```lean
@[formalMeta "1ステップでUCA Timingなし" "safeでは、今日の抽出から作られていない対象で送信を始めることはない" "補題",
  confidence high, proof_progress complete]
theorem safe_no_uca_timing_step (s : State) (a : Action) (h : FreshTC s) :
    ucaTiming .safe s a = false := by
  unfold ucaTiming newSends
  rcases safe_step_sent s a with hs | ⟨hd, _, _⟩
  · simp [hs]
  · simp [h hd]
```

読み方：FreshTC が成り立つ状態では、safe のどの動作も UCA Timing に当たらない。

証明の中身：`ucaTiming` は「`tCInputsAsOf` が今日でない」かつ「誰かに送った」である。`safe_step_sent` で場合分けする。

- 送信記録が変わらない場合（`hs`）：新たに送った人がいないので、「誰かに送った」が false
- 送った場合：そのとき tC は今日のもの（`hd`）。FreshTC（`h`）に `hd` を渡すと、`tCInputsAsOf` も今日（`h hd`）。よって「今日でない」が false

### 任意長の定理

```lean
@[formalMeta "対策版にUCA Timingなし" "どんな順序・外乱・長さの実行順でも、抽出完了前に通知を始めない" "記事 UCA Timing/Order が起きない" mainTheorem,
  confidence high, proof_progress complete]
theorem safe_no_uca_timing (t : List Action) (s : State) (h : FreshTC s) :
    ucaInTrace .safe .timing s t = false := by
  induction t generalizing s with
  | nil => rfl
  | cons a t ih =>
    simp only [ucaInTrace, Uca.occurs, safe_no_uca_timing_step s a h, Bool.false_or]
    exact ih _ (step_safe_freshTC s a h)
```

読み方：FreshTC が成り立つ状態から始めれば、どんな実行順 `t` のどこでも、UCA Timing は起きない。

証明の中身：実行順 `t` について帰納法を使う。

- `nil`（空の実行順）：何もしないので UCA は起きない。`ucaInTrace` の定義から計算だけで false（`rfl`）
- `cons a t`（先頭が `a`、残りが `t`）：
  - `ucaInTrace` の定義から、示すべきことは「`a` で UCA が起きない」かつ「残り `t` でも起きない」
  - 前半は、1ステップの補題 `safe_no_uca_timing_step` で false。`Bool.false_or` で「false または X」を「X」に整理する
  - 後半は、帰納法の仮定 `ih`（短い実行順では成り立つ）を使う。そのためには、`a` を実行した後の状態でも FreshTC が成り立つ必要がある。それを `step_safe_freshTC` で示している

`generalizing s` は、「帰納法の仮定を、どの開始状態についても使えるようにする」という指定である。1ステップ進むと状態が変わるので、これが必要になる。

初期状態 `init` では tC の基準日が0（今日は1）なので、FreshTC は自動的に成り立つ。したがって、初期状態からのどんな実行順でも UCA Timing は起きない。

## UCA Providing：どんな長さでも起きない

### ここで言いたいこと

safe では、「配信基盤が受理済みの人に、また送る」ことは、どんな実行順でも起きない。

```lean
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
```

### 証明の中身

1ステップの補題は、`safe_step_sent` で場合分けする。

- 送信記録が変わらない場合：新たに送った人がいないので false
- 送った場合：
  - `rw [hs, List.drop_left, map_fst_record]` で、「新たに送った人」を `limit k (pending s)` に書き換える（`List.drop_left` は「`(l1 ++ l2)` から `l1` の長さ分を取り除くと `l2`」、`map_fst_record` は「`record` で組にしてから宛先を取り出すと元のまま」）
  - `List.any_eq_false` で、「どれかが受理済み、が false」を「どの人も受理済みでない」に言い換える
  - 送った人 `u` について、[3章](03-spec.md)の `pending_not_sent` を使うと「`u` は受理済みでない」が言える（`mem_limit` は「`limit` で切っても元のリストに入っている」という補題）

任意長の定理は、UCA Timing と同じ帰納法である。この性質には不変条件が要らないので、仮定なしで成り立つ。

## H1：どんな長さでも起きない

### ここで言いたいこと

safe では、対象外の会員に送ることは、どんな実行順でも起きない（安全制約 SC1 が常に守られる）。

```lean
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
```

### 証明の中身

- 1ステップの補題：D 以外は送信記録に触らないので、仮定 `h` がそのまま使える。D については、[3章](03-spec.md)の `batchDSafe_sentOk`（safe の D は対象者にだけ送る）を使う
- 任意長の定理：帰納法。空の実行順では仮定 `h` そのもの。1ステップ進めた状態でも `SentOk` が成り立つことを補題で示し、残りに帰納法の仮定 `ih` を使う

[3章](03-spec.md)の D 単体の性質が、ここで「システム全体でどんな順でも成り立つ」に持ち上がっている。

## 元記事のシナリオ A〜C を防ぐ

```lean
@[formalMeta "対策版は記事のシナリオA〜Cを防ぐ" "シナリオA・B・Cの実行順でも、対策版はSC1〜SC3を満たす" "記事 Loss Scenario A〜C への対策",
  confidence high, proof_progress complete]
theorem safe_prevents_scenarios_ABC :
    safeAll (run .safe init scenarioA) = true ∧
    safeAll (run .safe init scenarioB) = true ∧
    safeAll (run .safe init scenarioC) = true := by decide
```

読み方：naive でハザードが起きたシナリオ A〜C を safe で実行すると、3つの安全制約がすべて守られる。

証明は `decide`（計算して確かめる）。たとえばシナリオA では、C が「tA が古い」ので失敗し、D も「tC が古い」ので失敗して、誰にも送らない。

```lean
#eval (run .safe init scenarioA).rC     -- RenewalNotice.JobResult.failed
#eval (run .safe init scenarioA).sent   -- []
#eval sentUsers (run .safe init scenarioC)   -- [1, 2]（再実行しても重複しない）
```

## 有界検査：長さ5以下の全実行順

### ここで言いたいこと

任意長ではまだ証明できていない性質も含めて、長さ5以下の実行順はすべて確かめた。

```lean
@[formalMeta "対策版の有界全数検査" "ログ故障を除く長さ5以下の全実行順で、SC1〜SC3が成り立ち、UCA Not Providingも起きない" "SC1〜SC3・UCA（有界）" mainTheorem,
  confidence medium, proof_progress complete]
theorem safe_bounded :
    (tracesUpTo alphabetNoSourceFault searchBound).all
      (fun t => safeAll (run .safe init t) && !ucaNotProviding (run .safe init t)) = true := by
  native_decide
```

### 読み方

ログ故障を除く6種類の動作を組み合わせた、長さ5以下のすべての実行順（9,331本）について、safe を実行すると、SC1〜SC3 がすべて守られ、UCA Not Providing も起きていない。

`tracesUpTo` は、長さ n 以下の実行順をすべて並べる関数である（[6章](06-counterexamples.md)）。

```lean
#eval (tracesUpTo alphabetNoSourceFault 5).length   -- 9331
```

### 証明の中身

`native_decide` は `decide` と同じく計算で確かめるが、Lean のカーネルではなく、コンパイルしたコードで計算する。9,331本を `decide` で計算するとカーネルでは時間がかかりすぎるので、こちらを使っている。

その代わり、Lean のコンパイラが正しいことを信頼することになる。そのため確信度を `medium` にしている。[7章](07-build-audit.md)のビルド時の検査は、`native_decide` に依存する定理の数を数えて表示する。

長さ5以下で成り立つことは、長さ6以上で成り立つことを意味しない。そのため、次の「未証明の主張」が別に必要になる。

## 未証明の主張（ハザード候補）

### ここで言いたいこと

次の3つは、おそらく成り立つが、まだ証明できていない。`sorry` のまま残し、ハザードの候補として扱う。

```lean
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
```

### なぜ未証明なのか

いずれも、UCA Timing と同じ帰納法で証明できるはずだが、そのためには適切な不変条件を見つける必要がある。

| 主張 | 証明に必要そうな不変条件 |
|---|---|
| `safe_no_H2` | tC に同じ会員が2回入らない。送信済みの一覧に重複がない |
| `safe_no_H3_without_fault` | 正常終了した D は、そのときの tC の対象者全員に送っている。会員の「対象者」状態は、利用再開で減ることはあっても増えない |
| `safe_no_uca_notProviding_without_fault` | 同上 |

`sorry` のままでも、ビルドの警告と Lean Atlas の「sorryあり」で常に見える。注記は `proof_progress stub` にしてあり、[7章](07-build-audit.md)の検査が、注記と実際の状態（`sorry` に依存している）が一致していることを毎回確かめている。
