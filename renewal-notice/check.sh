#!/bin/sh
# CI（.github/workflows/renewal-notice.yml）と同じ手順を手元で実行する。
#   ./check.sh
# 1. Lean をビルドする（定理の検査・ハザードと UCA の検出・証明状況の照合）
# 2. Lean が見つけた反例を JSON に書き出す
# 3. Go のテストで、Lean の反例と記事のシナリオ A〜D を実装に再生する
set -eu
cd "$(dirname "$0")"

echo "== 1/3 lake build"
(cd lean && lake build)

echo "== 2/3 lake exe explore"
(cd lean && lake exe explore > out/counterexamples.json)
cat lean/out/counterexamples.json

echo "== 3/3 go test"
(cd go && go test ./... -count=1 -v)

echo "== OK: CI と同じ検査がすべて通った"
