# lean-experiments

Lean 4 の実験用プロジェクト集。

| ディレクトリ | 内容 |
|---|---|
| [renewal-notice](renewal-notice/) | 契約更新前の退会案内アプリ（Go）。個々のバッチは正しいのに組み合わせると事故が起きる状況を、STPA のハザードとして Lean で形式化する |

## Zenn

`articles/` と `images/` は Zenn と連携している。

| 記事 | 対応するコード |
|---|---|
| [Leanで安全制約を書くと、ハザード候補がビルドエラーとして見つかる](articles/lean-safety-constraint-build-error.md)（シンプル版） | [renewal-notice](renewal-notice/) |
| [正常に動くバッチの組み合わせで事故が起きる：STPAのハザードをLeanで書いてみた](articles/stpa-lean-renewal-notice.md)（詳しい版） | [renewal-notice](renewal-notice/) |
