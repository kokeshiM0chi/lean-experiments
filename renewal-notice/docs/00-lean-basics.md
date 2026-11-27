# 0. このコードを読むための Lean の基本

このプロジェクトで使っている Lean の要素だけを説明する。

## 定義と定理

Lean のファイルには、大きく分けて **定義**（`def`、`structure`、`inductive`）と **定理**（`theorem`）が書かれている。

- **定義**はプログラムである。普通の関数型言語と同じように、値を計算する
- **定理**は主張とその証明である。`theorem 名前 : 主張 := 証明` の形をしている

```lean
-- 定義：状態 s を受け取り、Bool を返す関数
def sc1 (s : State) : Bool := s.sent.all (fun p => p.2)

-- 定理：「シナリオAを naive で実行すると sc1 が false になる」という主張と、その証明
theorem scenarioA_H1 : sc1 (run .naive init scenarioA) = false := by decide
```

定理は「すべての入力についてのテスト」と考えるとよい。普通のテストは入力をいくつか試すが、定理は引数（上の例では引数なし、他の定理では `(s : State)` など）のすべての値について成り立つことを主張する。Lean は証明を機械的に検査し、通らなければビルドがエラーになる。

## 型と構文

| 書き方 | 意味 | 例 |
|---|---|---|
| `structure` | フィールドを持つレコード型 | `structure Table where asOf : Nat; rows : List User` |
| `inductive` | 列挙型（各値が引数を持てる） | `inductive Action where \| runA \| crashD (k : Nat)` |
| `abbrev` | 型の別名 | `abbrev User := Nat` |
| `{ s with f := v }` | `s` のフィールド `f` だけを `v` に変えた値 | `{ s with rC := .ok }` |
| `.ok`、`.naive` | 型が分かっているときの省略形 | `JobResult.ok` を `.ok` と書く |
| `fun x => ...` | 無名関数 | `fun u => b.rows.contains u` |
| `(·.1)` | 「引数の1つ目の成分を取る」無名関数 | `s.sent.map (·.1)` |
| `l.filter p` | リスト `l` のうち `p` が true のもの | |
| `l.contains x` | `l` に `x` が含まれるか（Bool） | |
| `l.all p`、`l.any p` | すべて／どれかが `p` を満たすか（Bool） | |
| `a ++ b` | リストの連結 | |
| `&&`、`\|\|`、`!` | Bool の論理積・論理和・否定 | |
| `-- ...`、`/-- ... -/` | コメント、ドキュメントコメント | |

## 主張に出てくる記号

| 記号 | 読み方 |
|---|---|
| `∀ x, P x` | すべての x について P x が成り立つ |
| `∃ x, P x` | P x を満たす x が存在する |
| `P ∧ Q` | P かつ Q |
| `P ∨ Q` | P または Q |
| `¬ P` | P ではない |
| `P → Q` | P ならば Q |
| `P ↔ Q` | P と Q は同値 |
| `x ∈ l` | x はリスト l の要素である |
| `a = b`、`a ≠ b` | 等しい、等しくない |

`Bool`（true / false の値）と `Prop`（主張）は別物である。このプロジェクトでは、安全制約を計算できるように `Bool` で書き、定理では `sc1 s = true` や `sc1 s = false` の形で主張している。

## 証明で使っているタクティク

`by` の後に書くのが証明である。証明は「タクティク」と呼ばれる命令を並べて書く。

| タクティク | 何をするか | このプロジェクトでの使いどころ |
|---|---|---|
| `decide` | 主張を実際に計算して、true になることを Lean のカーネルが確かめる | 具体的な実行順でハザードが起きることの証明 |
| `native_decide` | `decide` と同じだが、コンパイルしたコードで計算する。速いが、Lean のコンパイラを信頼することになる | 9,331 本の実行順をすべて調べる有界検査 |
| `simp [定義名, ...]` | 定義を展開し、既知の等式で式を簡単にする | 単体仕様の証明 |
| `rfl` | 両辺が計算すると同じになることを示す | 状態が変わらないことの証明 |
| `exact 式` | ゴールにちょうど当てはまる証明を渡す | 仮定をそのまま使う |
| `intro h` | 「P ならば Q」や「すべての x」の仮定を取り出す | |
| `cases a with \| runA => ... \| ...` | 値 `a` の種類ごとに場合分けする | 制御動作の種類ごとの証明 |
| `induction t with \| nil => ... \| cons a t ih => ...` | リスト `t` について帰納法を使う。`ih` は「短いリストでは成り立つ」という仮定 | 任意の長さの実行順で成り立つことの証明 |
| `split` | ゴールの中の `if` で場合分けする | `if` を含むバッチの証明 |
| `by_cases h : P` | P が成り立つ場合と成り立たない場合に分ける | |
| `rcases h with h1 \| ⟨x, hx⟩` | 「または」や「存在する」の仮定を分解する | |
| `unfold 定義名` | 定義を展開する | |
| `show 式` | ゴールを、計算上同じ別の形に書き直す | |
| `left`、`right` | 「P または Q」のどちらを示すかを選ぶ | |
| `sorry` | 証明を省略する。ビルドで警告が出る | 未証明の主張 |

## `sorry` について

`sorry` は「この証明は省略する」という意味である。

```lean
theorem safe_no_H2 (t : List Action) : sc2 (run .safe init t) = true := by
  sorry
```

- Lean はこの定理を証明なしで受け付け、他の定理から使うこともできる
- ビルドすると `declaration uses 'sorry'` という警告が出る
- `sorry` を使った定理に依存する定理も、実質的には未証明になる

このプロジェクトでは、まだ証明できていない安全の主張を `sorry` のまま残し、ハザードの候補として扱っている。

## `#eval` で値を確かめる

定義は普通のプログラムなので、`#eval` で計算結果を見られる。証明を書く前に、主張が本当に成り立ちそうかを確かめるのに便利である。

```lean
#eval (run .naive init scenarioA).sent        -- [(0, false), (1, true)]
#eval sc1 (run .naive init scenarioA)         -- false
```

## Lean Atlas の注記

定理の前の `@[...]` は、Lean Atlas の注記である。証明の正しさには影響しない。

```lean
@[formalMeta "名前" "要約" "参照" mainTheorem,
  confidence high, proof_progress complete]
theorem ...
```

| 注記 | 意味 |
|---|---|
| `formalMeta "名前" "要約" "参照"` | ビューアに表示する名前と説明。参照には STPA 上の役割を書いた |
| `mainTheorem` | 主定理。ビューアのプルダウンに出る |
| `confidence high` / `medium` | 主張が意図どおりの意味になっているかの確信度 |
| `proof_progress complete` / `stub` | 証明の進み具合。`complete` なのに `sorry` があるとエラーになる |
