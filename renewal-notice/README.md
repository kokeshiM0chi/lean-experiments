# renewal-notice: 契約更新前の退会案内アプリと、そのハザードの Lean による形式化

```
go/    Go の webapp（バッチ A〜D と HTTP API）とテスト
lean/  同じシステムの Lean 4 モデル、定理、反例探索（Mathlib は使わない）
```

## 実行

```sh
# Lean（elan が必要: https://github.com/leanprover/elan）
cd lean
lake build                                  # 定理をすべて検査する
lake exe explore > out/counterexamples.json # 反例を探す（レポートは stderr に出る）

# Go
cd ../go
go test ./... -v     # Lean の反例が実装でも再現するかを検査する
go run ./cmd/server  # :8080
```

## STPA と Lean の対応

| STPA | Lean |
|---|---|
| 制御対象プロセス | `World`（真の状態） |
| コントローラー / 制御動作 | `batchA`〜`batchD` / `Action` |
| プロセスモデル | テーブル `tA` `tB` `tC`（`asOf` 付き） |
| Safety Constraint | `sc1` `sc2` `sc3`（Bool の述語） |
| Hazard | `∃ t, sc (run d init t) = false`（制約を破る到達可能状態がある） |
| Loss Scenario | 反例のトレース `t` |
| UCA | `firstUCA`: 初めて制約を破った（コンテキスト, 制御動作） |
| 「部品は正常」 | `batchA_spec` など、各バッチの単体仕様の全称定理 |

「証明できない」ことは Lean の中からは判定できないので、次のように置き換えている。

* 証明できないかもしれない全称命題 `∀ t, 安全` について、その否定を証明する。
  否定の証人となるトレースがハザードの Loss Scenario になる（`naive_unsafe`、`H1_stale` など）。
* 証明の候補を探す段階では、有界モデル検査（`counterexample`）で反例を自動探索する。
* 対策後の設計は、帰納法による全称証明（`safe_no_H1`）と有界の全数検査（`safe_bounded`）で検証する。
* 検査から外した外乱を戻すと残留ハザードが出る（`safe_residual_H3`）。これが次の安全要求になる。

## Lean Atlas で証明状況を見る

`lean/` は [lean-atlas](https://github.com/kokeshiM0chi/lean-atlas) に依存しており、主要な定理には
`@[formalMeta ... mainTheorem]` と `@[proof_progress ...]` を付けている。
`safe_no_H2` は意図的に `sorry` のまま残してある（未証明の安全主張 = ハザード候補）。

```sh
cd lean
lake build
lake exe atlas graph-data --output .lake/packages/lean-atlas/web/public/data/graph.json --pretty
cd .lake/packages/lean-atlas/web
npx pnpm@10.26.0 install --frozen-lockfile   # pnpm 10 が必要
LEAN_PROJECT_ROOT=$PWD/../../../.. npx pnpm@10.26.0 dev --port 5326
# → http://localhost:5326
```

手元の pnpm が 10 系なら `lake exe atlas` だけで生成から起動まで行える。
