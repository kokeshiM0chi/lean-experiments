# renewal-notice: 契約更新前の退会案内アプリと、その STPA 分析の Lean による形式化

[STAMP/STPA を SRE の視点で解説した記事](https://zenn.dev/maruloop/articles/7ff108e29741b5)の例（退会案内バッチ）を題材に、
アプリを Go で実装し、記事の Loss・Hazard・UCA・Loss Scenario を Lean 4 で形式化したもの。
解説は [Zenn の記事](../articles/stpa-lean-renewal-notice.md) にある。Lean のソースコードの詳しい解説は [docs/](docs/README.md) にある。

```
go/    Go の webapp（バッチ A〜D と HTTP API）とテスト
lean/  同じシステムの Lean 4 モデル、定理、ビルド時の検査
```

## 実行

```sh
cd lean
lake build                                    # 定理の検査、ハザード・UCA の検出、証明状況の照合
lake exe explore > out/counterexamples.json   # 反例を JSON に書き出す
cd ../go
go test ./... -count=1 -v                     # Lean の反例と記事のシナリオ A〜D を Go 実装で再生する
go run ./cmd/server                           # :8080
```

## CI

[`.github/workflows/renewal-notice.yml`](../.github/workflows/renewal-notice.yml) で、push のたびに次を実行する。

1. `lake build`（定理の検査、ハザード・UCA の検出、証明状況の照合）
2. `lake exe explore` で反例を書き出す
3. `go test` で、Lean の反例と記事のシナリオ A〜D を Go 実装に再生する

## 証明の失敗からハザードを見つける（説明用のビルド対象）

通常の `lake build` には含めていない。詳しくは [docs/08-detect-by-proof-failure.md](docs/08-detect-by-proof-failure.md) と、ビルドが失敗したときの切り分け手順 [docs/10-practice.md](docs/10-practice.md)。

```sh
cd lean
lake build DetectWithoutConstraint   # 単体仕様だけ → ビルド成功、ハザードは見つからない
lake build DetectWithConstraint      # 組み合わせの安全制約を定理にする → ビルド失敗、D の箇所を指す
lake build DetectCounterexample      # 失敗箇所から組み立てた反例 [D]、[D, D] を確かめる
lake build DetectFalseAlarm          # 偽の警報の例：主張は正しいが、不変条件がなく証明が止まる
```

## Lean のファイル構成

| ファイル | 内容 |
|---|---|
| `Model.lean` | 状態（現実とバッチの認識）、バッチ A〜D、スケジューラー |
| `Safety.lean` | 記事の Loss・Hazard と安全制約 `sc1`〜`sc3` |
| `Uca.lean` | 記事の UCA 表を述語にしたもの |
| `ModelCheck.lean` | 全実行順の列挙と反例探索 |
| `Scenarios.lean` | 記事の Loss Scenario A〜D と追加シナリオの実行順 |
| `Spec.lean` | 各バッチの単体仕様（両設計） |
| `Hazards.lean` | 対策なし版のハザードと UCA の存在の証明 |
| `SafeDesign.lean` | 対策版の安全性（証明済み・有界検査・未証明） |
| `Audit.lean` | ビルド時の検査（ハザード・UCA の検出、注記と実際の証明の照合） |
| `../Detect/*.lean` | 証明の失敗からハザードを見つける説明用のビルド対象（4つ） |

## `lake build` で分かること

- 長さ5以下の全実行順で見つかったハザードと UCA（警告）
- 未証明の安全主張（`sorry`、警告）
- Lean Atlas の `@[proof_progress]` 注記と、実際の `sorry` への依存（依存先の補題まで）が食い違えばエラー
- 証明済み・`native_decide` 依存・未証明の件数

## Lean Atlas で証明状況を見る

```sh
cd lean
lake exe atlas graph-data --output .lake/packages/lean-atlas/web/public/data/graph.json --pretty
cd .lake/packages/lean-atlas/web
npx pnpm@10.26.0 install --frozen-lockfile   # pnpm 10 が必要
LEAN_PROJECT_ROOT=$PWD/../../../.. npx pnpm@10.26.0 dev --port 5326
# → http://localhost:5326
```

手元の pnpm が 10 系なら `lake exe atlas` だけで生成から起動まで行える。
