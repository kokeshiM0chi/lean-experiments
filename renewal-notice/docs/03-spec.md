# 3. 各バッチは単体では正しい（`Spec.lean`）

ソース：[`lean/RenewalNotice/Spec.lean`](../lean/RenewalNotice/Spec.lean)

## この章で言いたいこと

**どのバッチも、単体で見れば仕様どおりに動く。** これを、すべての入力（すべての状態 `s`）について証明する。

STAMP の主張は「部品が正常でも事故は起きる」である。それを示すには、まず「部品が正常である」ことをはっきりさせておく必要がある。この章の定理がその「部品は正常」にあたり、[4章](04-hazards.md)の「それでも事故は起きる」と対になる。

単体テストは、いくつかの入力で確かめるだけである。ここでは同じことを、すべての入力について保証する。

| バッチ | naive の単体仕様 | safe の単体仕様 |
|---|---|---|
| A | `batchA_spec`（両設計共通） | 同左 |
| B | `batchB_spec`（両設計共通） | 同左 |
| C | `batchC_naive_spec` | `batchC_safe_spec_fresh`、`batchC_safe_spec_stale` |
| D | `batchD_naive_spec` | `batchD_safe_spec_fresh`、`batchD_safe_spec_stale`、`pending_not_sent`、`batchDSafe_sentOk` |

## A・B：抽出は正しい

### ここで言いたいこと

A は「利用ログに載っている会員を、漏れも余分もなく抽出し、今日の日付で正常終了する」。B も同様に契約情報について成り立つ。

```lean
@[formalMeta "A単体仕様" "Aは利用ログどおりに非アクティブ者を抽出し、正常終了する（両設計共通）" "STPA: コンポーネントの正しさ",
  confidence high, proof_progress complete]
theorem batchA_spec (s : State) (u : User) :
    (u ∈ (batchA s).tA.rows ↔ u ∈ s.world.users ∧ s.world.inactiveLog.contains u = true) ∧
    (batchA s).tA.asOf = s.today ∧ (batchA s).rA = .ok := by
  simp [batchA, List.mem_filter]
```

### 読み方

どんな状態 `s` と会員 `u` についても、次の3つが成り立つ。

1. A を実行した後の tA に `u` が入っている ⟺ `u` は会員で、かつ利用ログに載っている（漏れも余分もない）
2. tA の基準日は今日である
3. A の結果は正常終了である

`batchB_spec` は、利用ログを契約情報（`renewing`）に置き換えた同じ形の定理である。

### 証明の中身

`simp [batchA, List.mem_filter]` の1行で終わる。

- `batchA` を指定したので、`batchA s` が定義どおりに展開される。`(batchA s).tA.asOf` は `s.today` に、`(batchA s).rA` は `.ok` になる
- `List.mem_filter` は「`x ∈ l.filter p` ⟺ `x ∈ l ∧ p x = true`」という既存の定理で、1つ目の主張の左辺を右辺と同じ形に書き換える
- 3つとも「左辺と右辺が同じ」になるので、`simp` が自動で閉じる

### 注意

利用ログが壊れていると（`logOk = false`）、`inactiveLog` は空になり、A は0件の表を書いて正常終了する。この定理はそれも含めて「A は読んだとおりに書く」と言っている。A 自身は正しく、問題は入力の側にある。これが[4章](04-hazards.md)のシナリオDにつながる。

## C：積集合は正しい

### naive

```lean
@[formalMeta "C単体仕様（naive）" "CはtAとtBの積集合を取り、正常終了する" "STPA: コンポーネントの正しさ",
  confidence high, proof_progress complete]
theorem batchC_naive_spec (s : State) (u : User) :
    (u ∈ (batchC .naive s).tC.rows ↔ u ∈ s.tA.rows ∧ s.tB.rows.contains u = true) ∧
    (batchC .naive s).rC = .ok := by
  simp [batchC, intersect, List.mem_filter]
```

読み方：naive の C を実行すると、tC に入るのは「tA にも tB にもいる会員」だけで、C は正常終了する。

証明は A と同じく `simp` で、`batchC`（naive の場合）と `intersect` を展開し、`List.mem_filter` で書き換えている。

ここで言えるのは「C は渡された tA と tB の積集合を正しく取る」ことである。tA が古いかどうかには触れていない。それが単体仕様の範囲である。

### safe：入力が新しいとき・古いとき

```lean
@[formalMeta "C単体仕様（safe・入力が新しい）" "tAとtBの基準日が今日なら、積集合を取り正常終了する" "STPA: コンポーネントの正しさ",
  confidence high, proof_progress complete]
theorem batchC_safe_spec_fresh (s : State) (h : s.tA.asOf = s.today ∧ s.tB.asOf = s.today) :
    (batchC .safe s).tC = intersect s.tA s.tB s.today ∧ (batchC .safe s).rC = .ok := by
  simp [batchC, h]

@[formalMeta "C単体仕様（safe・入力が古い）" "tAかtBの基準日が今日でなければ、tCを変えずに失敗で終わる" "STPA: コンポーネントの正しさ",
  confidence high, proof_progress complete]
theorem batchC_safe_spec_stale (s : State) (h : ¬ (s.tA.asOf = s.today ∧ s.tB.asOf = s.today)) :
    (batchC .safe s).tC = s.tC ∧ (batchC .safe s).rC = .failed := by
  simp [batchC, h]
```

読み方：

- `_fresh`：tA と tB の基準日がどちらも今日なら（仮定 `h`）、safe の C は積集合を取って正常終了する
- `_stale`：そうでなければ（仮定 `h` が否定）、tC を変えずに失敗で終わる

証明の中身：`simp [batchC, h]` は、safe の C の `if` の条件を仮定 `h` で true（または false）に書き換え、`if` の片方の枝だけを残す。残った式は両辺が同じになるので閉じる。

この2つで、safe の C の動作をすべての場合について言い切っている。

## D：送信は正しい

### naive

```lean
@[formalMeta "D単体仕様（naive）" "DはtCの全員に送り、正常終了する" "STPA: コンポーネントの正しさ",
  confidence high, proof_progress complete]
theorem batchD_naive_spec (s : State) :
    sentUsers (batchD .naive none s) = sentUsers s ++ s.tC.rows ∧
    (batchD .naive none s).rD = .ok := by
  simp [batchD, batchDNaive, sentUsers, record, limit, doneResult, List.map_append, List.map_map,
    Function.comp_def]
```

読み方：naive の D を（途中で失敗せずに）実行すると、送信済みの一覧の後ろに tC の全員が追加され、D は正常終了する。

証明の中身：

- `batchD`、`batchDNaive`、`limit`、`doneResult` を展開すると、`sent` は `s.sent ++ record s s.tC.rows` になる
- `sentUsers` は送信記録から宛先だけを取り出す（`map (·.1)`）。`List.map_append` で連結の `map` を分け、`List.map_map` と `Function.comp_def` で「`record` で組にしてから宛先を取り出す」が「元のまま」になることを示す
- 両辺が `sentUsers s ++ s.tC.rows` になって閉じる

### safe：入力が新しいとき・古いとき

```lean
@[formalMeta "D単体仕様（safe・入力が新しい）" "tCの基準日が今日なら、未送信かつ今も対象の人全員に送り、正常終了する" "STPA: コンポーネントの正しさ",
  confidence high, proof_progress complete]
theorem batchD_safe_spec_fresh (s : State) (h : s.tC.asOf = s.today) :
    sentUsers (batchD .safe none s) = sentUsers s ++ pending s ∧
    (batchD .safe none s).rD = .ok := by
  simp [batchD, batchDSafe, h, sentUsers, record, limit, doneResult, List.map_append, List.map_map,
    Function.comp_def]

@[formalMeta "D単体仕様（safe・入力が古い）" "tCの基準日が今日でなければ、何も送らずに失敗で終わる" "STPA: コンポーネントの正しさ",
  confidence high, proof_progress complete]
theorem batchD_safe_spec_stale (s : State) (k : Option Nat) (h : s.tC.asOf ≠ s.today) :
    (batchD .safe k s).sent = s.sent ∧ (batchD .safe k s).rD = .failed := by
  simp [batchD, batchDSafe, h]
```

読み方：

- `_fresh`：tC が今日のものなら、safe の D は `pending s`（未送信かつ今も対象の人）全員に送り、正常終了する
- `_stale`：tC が今日のものでなければ、途中失敗の有無（`k`）によらず、何も送らずに失敗で終わる

証明は C の safe 版と同じ考え方で、仮定 `h` で `if` を片方に決めてから `simp` で整理している。

### safe：送信済みの人には送らない

#### ここで言いたいこと

safe の D が送る相手（`pending s`）には、すでに配信基盤が受理した人は含まれない。これが「同一ユーザーへの通知指示を一意に管理する」の、D 単体についての保証である。

```lean
@[formalMeta "D単体仕様（safe・送信済みは除く）" "safeのDが送る相手には、送信済みの人が含まれない" "STPA: フィードバックの利用",
  confidence high, proof_progress complete]
theorem pending_not_sent (s : State) (u : User) (hu : u ∈ pending s) :
    (sentUsers s).contains u = false := by
  simp only [pending, List.mem_filter, Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true] at hu
  exact hu.2.1
```

読み方：`u` が `pending s` に入っているなら（仮定 `hu`）、`u` は送信済みの一覧に含まれない。

証明の中身：

1. `simp only [...] at hu` で、仮定 `hu` を書き換える。`pending` を展開し、`List.mem_filter` で「`u ∈ tC.rows` かつ（未送信 かつ 対象者）」に分解する。`Bool.and_eq_true` などで Bool の式を「〜かつ〜」の形にそろえる
2. 書き換えた後の `hu` は「`u ∈ s.tC.rows` ∧ `(sentUsers s).contains u = false` ∧ `s.world.isTarget u = true`」になっている
3. `exact hu.2.1` で、その2つ目（未送信）を取り出してゴールに渡す

### safe：対象者にだけ送る

#### ここで言いたいこと

safe の D を実行しても、「送信記録はすべて、送った時点で本当の対象者宛て」という性質は壊れない。これは安全制約 SC1 を D 単体について示したもので、[5章](05-safe-design.md)の帰納法の部品になる。

```lean
@[formalMeta "D単体仕様（safe・対象者だけ）" "safeのDは、送る時点で本当に対象の人にだけ送る" "STPA: Safety Constraint SC1 の局所版",
  confidence high, proof_progress complete]
theorem batchDSafe_sentOk (k : Option Nat) (s : State) (h : SentOk s) :
    SentOk (batchDSafe k s) := by
  unfold batchDSafe
  split
  · intro p hp
    simp only [List.mem_append, record, List.mem_map] at hp
    rcases hp with hp | ⟨u, hu, rfl⟩
    · exact h p hp
    · have hu' : u ∈ pending s := by
        cases k with
        | none   => exact hu
        | some n => exact List.mem_of_mem_take hu
      simp only [pending, List.mem_filter, Bool.and_eq_true] at hu'
      exact hu'.2.2
  · exact h
```

`SentOk` は [`Scenarios.lean`](../lean/RenewalNotice/Scenarios.lean) で定義した、SC1 を命題にしたものである。

```lean
def SentOk (s : State) : Prop := ∀ p ∈ s.sent, p.2 = true
```

読み方：実行前の状態で SentOk が成り立っていれば（仮定 `h`）、safe の D を実行した後も SentOk が成り立つ。

証明の中身：

1. `unfold batchDSafe` で D の定義を展開する。中に `if s.tC.asOf = s.today then ... else ...` が現れる
2. `split` で `if` の2つの場合に分ける
3. tC が今日のもので、実際に送る場合：
   - `intro p hp` で「送信記録の任意の要素 `p`」を取り出す。`hp` は「`p` は送信記録に入っている」
   - `simp only [List.mem_append, record, List.mem_map] at hp` で、`hp` を「`p` は元の記録に入っている」または「`p` は今回送った `(u, isTarget u)` の形」に分解する
   - `rcases` で2つの場合に分ける
     - 元の記録に入っている場合：仮定 `h` から、`p.2 = true` がすぐに分かる（`exact h p hp`）
     - 今回送った場合：`p = (u, s.world.isTarget u)` なので、示すべきことは `s.world.isTarget u = true`。`u` は `limit k (pending s)` に入っているので、`limit` の定義で場合分けして `u ∈ pending s` を得る（`take` で切っても要素は元のリストに入っている：`List.mem_of_mem_take`）。最後に `pending` を展開すると、3つ目の条件がちょうど `isTarget u = true` になる（`exact hu'.2.2`）
4. tC が古く、何も送らない場合：送信記録は変わらないので、仮定 `h` がそのまま使える（`exact h`）

ポイントは、safe の D が送る直前に `isTarget` で対象者かを確かめていることが、証明の3つ目の手順に効いていることである。
