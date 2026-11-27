# 6. 反例の探索と JSON 出力（`ModelCheck.lean`、`Main.lean`）

ソース：[`lean/RenewalNotice/ModelCheck.lean`](../lean/RenewalNotice/ModelCheck.lean)、[`lean/Main.lean`](../lean/Main.lean)

## この章で言いたいこと

**安全制約を破る実行順（反例）は、人が考えなくても探せる。** 起こりうる動作を組み合わせた実行順を短い順にすべて試し、最初に安全制約を破ったものを反例とする。

見つけた反例は、次の3か所で使っている。

| 使い道 | どこで | 形 |
|---|---|---|
| Go のテストで実装に再生する | `lake exe explore` | JSON（標準出力） |
| 人が読む | `lake exe explore` | レポート（標準エラー出力） |
| ビルド時に警告として出す | `lake build`（[7章](07-build-audit.md)） | ビルドの警告 |

## 反例の JSON は単体で出力できる

```sh
cd renewal-notice/lean
lake exe explore > out/counterexamples.json
```

`lake exe explore` は、JSON を**標準出力**に、人向けのレポートを**標準エラー出力**に分けて出す。そのため、`>` でリダイレクトすれば JSON だけがファイルに入る。

JSON だけを画面で見たいときは、標準エラー出力を捨てる。

```sh
lake exe explore 2>/dev/null
```

実際の出力：

```json
[
  {"design": "naive", "hazard": "H1", "trace": ["D"]},
  {"design": "naive", "hazard": "H2", "trace": ["D", "D"]},
  {"design": "naive", "hazard": "H3", "trace": ["A", "B", "D", "C"]},
  {"design": "safe", "hazard": "H3", "trace": ["B", "breakSource", "A", "C", "D"]}
]
```

| キー | 意味 |
|---|---|
| `design` | どちらの設計で起きたか（`naive` = 対策なし、`safe` = 対策版） |
| `hazard` | 破れた安全制約に対応するハザード（`H1`〜`H3`） |
| `trace` | 初期状態から実行する動作の順番。これが Loss Scenario |

`trace` の各要素の意味は次のとおり。

| 文字列 | Lean の `Action` | 意味 |
|---|---|---|
| `"A"`〜`"D"` | `runA`〜`runD` | バッチを実行する |
| `"crashD:k"` | `crashD k` | 配信基盤が k 件を受理した後で、D が失敗として終わる |
| `"use:u"` | `use u` | 会員 u が利用を再開する |
| `"breakSource"` | `breakSource` | 利用ログのソースが壊れる |

対策版で見つからなかったハザード（safe の H1・H2）は、JSON に入らない。

レポート（標準エラー出力）だけを見たいときは、JSON のほうを捨てる。ビルドのログが混ざらないよう、ビルド済みの実行ファイルを直接実行するとよい。

```sh
lake build explore
.lake/build/bin/explore 2>&1 >/dev/null
```

実際の出力：

```text
[naive] H1 HAZARD: 通知対象外のユーザーが、退会案内の配信対象に含まれている (→L1)
    Loss Scenario: ["D"]
    安全制約を初めて破った制御動作: D（直前の状態: today=1 tA(asOf=0,[0, 1]) tB(asOf=0,[0]) tC(asOf=0,[0]) inactive=[1, 2] sent=[]）
[naive] H2 HAZARD: 同じユーザー・契約更新期に対する通知が、重複して発行可能な状態にある (→L2)
    Loss Scenario: ["D", "D"]
    安全制約を初めて破った制御動作: D（直前の状態: today=1 tA(asOf=0,[0, 1]) tB(asOf=0,[0]) tC(asOf=0,[0]) inactive=[1, 2] sent=[0]）
[naive] H3 HAZARD: 案内が必要な対象者について、通知期限までに送信を開始できない状態にある (→L3)
    Loss Scenario: ["A", "B", "D", "C"]
    安全制約を初めて破った制御動作: C（直前の状態: today=1 tA(asOf=1,[1, 2]) tB(asOf=1,[0, 1, 2]) tC(asOf=0,[0]) inactive=[1, 2] sent=[0]）
[safe] H1: 長さ5以下の反例なし
[safe] H2: 長さ5以下の反例なし
[safe] H3 HAZARD: 案内が必要な対象者について、通知期限までに送信を開始できない状態にある (→L3)
    Loss Scenario: ["B", "breakSource", "A", "C", "D"]
    安全制約を初めて破った制御動作: D（直前の状態: today=1 tA(asOf=1,[]) tB(asOf=1,[0, 1, 2]) tC(asOf=1,[]) inactive=[1, 2] sent=[]）
```

以下、この出力を作っている Lean のコードを、下の層から順に説明する。

## 1. 起こりうる動作：`alphabet`

```lean
/-- スケジューラーと外乱が起こしうる動作。 -/
def alphabet : List Action :=
  [.runA, .runB, .runC, .runD, .crashD 1, .use 1, .breakSource]

/-- ログソース故障を除いた動作。 -/
def alphabetNoSourceFault : List Action :=
  [.runA, .runB, .runC, .runD, .crashD 1, .use 1]
```

探索で使う動作の一覧である。`crashD` と `use` は引数を取るが、探索が爆発しないよう、`crashD 1`（1件受理後に失敗）と `use 1`（会員1が利用再開）だけに絞っている。

**探索で見つかるのは、ここに入れた動作の組み合わせだけである。** 「配信基盤が受理したのに届かない」のような、ここにない種類の故障は見つからない。自分のアプリに当てはめるときは、STPA のガイドワード（順序、タイミング、提供しない、余分に提供、フィードバックの欠落）から、ここに入れる動作を決める。

## 2. 実行順を全部並べる：`tracesExact`、`tracesUpTo`

```lean
def tracesExact (al : List Action) : Nat → List (List Action)
  | 0     => [[]]
  | n + 1 => (tracesExact al n).flatMap (fun t => al.map (fun a => t ++ [a]))

/-- 長さ n 以下の全トレース。短い順に並ぶ。 -/
def tracesUpTo (al : List Action) (n : Nat) : List (List Action) :=
  (List.range (n + 1)).flatMap (tracesExact al)
```

- `tracesExact al n` は、長さちょうど n の実行順をすべて並べる
  - 長さ0は、空の実行順1つだけ（`[[]]`）
  - 長さ n+1 は、長さ n の各実行順の後ろに、`al` の各動作を1つ付け足したもの
- `tracesUpTo al n` は、長さ0から n までをこの順に連結する。そのため**短い実行順から順に並ぶ**

`#eval` で中身を見ると、次のようになる。

```lean
#eval tracesUpTo alphabet 2
-- [[],
--  [runA], [runB], [runC], [runD], [crashD 1], [use 1], [breakSource],
--  [runA, runA], [runA, runB], [runA, runC], ... , [breakSource, breakSource]]
```

数は次のとおり。

| 長さ | 動作7種類（`alphabet`） | 動作6種類（`alphabetNoSourceFault`） |
|---|---|---|
| 0 | 1 | 1 |
| 1 | 7 | 6 |
| 2 | 49 | 36 |
| 3 | 343 | 216 |
| 4 | 2,401 | 1,296 |
| 5 | 16,807 | 7,776 |
| 合計（長さ5以下） | 19,608 | 9,331 |

```lean
#eval (tracesUpTo alphabet 5).length                -- 19608
#eval (tracesUpTo alphabetNoSourceFault 5).length   -- 9331
```

長さを1増やすごとに7倍になるので、上限（`searchBound`）は5にしている。

```lean
/-- 探索の上限（実行順の長さ）。 -/
def searchBound : Nat := 5
```

## 3. 反例を探す：`counterexample`

```lean
/-- 設計 d でハザード h を起こす最短のトレース（Loss Scenario）。 -/
def counterexample (d : Design) (h : Hazard) (al : List Action) (n : Nat) : Option (List Action) :=
  (tracesUpTo al n).find? (fun t => !h.sc (run d init t))
```

読み方：長さ n 以下の実行順を短い順に1つずつ試し、「初期状態から実行すると、ハザード h の安全制約（`h.sc`）が false になる」最初のものを返す。見つからなければ `none` を返す。

- `h.sc` は、[2章](02-safety-and-uca.md)で定義した、ハザードに対応する安全制約（H1 なら `sc1`）
- `find?` は、条件を満たす最初の要素を `some 要素` で返し、なければ `none` を返す
- 実行順は短い順に並んでいるので、**返ってくるのは最短の反例**である。同じ長さの中では、`alphabet` の順（A, B, C, D, crashD, use, breakSource）で先に来るものが選ばれる

```lean
#eval counterexample .naive .H1 alphabet 5   -- some [RenewalNotice.Action.runD]
#eval counterexample .safe  .H1 alphabet 5   -- none
```

naive の H1 は、長さ1の `[runD]` で見つかる。初期状態では前回分の tC（会員0）が残っているので、D を1回実行するだけで対象外の会員0に送ってしまう。

UCA についても、同じ形の探索を用意している。[7章](07-build-audit.md)のビルド時の検査で使う。

```lean
/-- 設計 d で UCA u が起きる最短の実行順。 -/
def ucaExample (d : Design) (u : Uca) (al : List Action) (n : Nat) : Option (List Action) :=
  (tracesUpTo al n).find? (fun t => ucaInTrace d u init t)
```

## 4. どこで破れたか：`firstViolation`

```lean
/-- 実行順の中で、安全制約を初めて破った制御動作と、その直前の状態を返す。
    「破れた瞬間の操作」であって、根本原因とは限らない。
    記事の UCA の判定は `Uca.lean` の `Uca.occurs` で行う。 -/
def firstViolation (d : Design) (h : Hazard) : State → List Action → Option (State × Action)
  | _, []     => none
  | s, a :: t =>
    let s' := step d s a
    if h.sc s && !h.sc s' then some (s, a) else firstViolation d h s' t
```

読み方：実行順を先頭から1つずつ実行し、「実行前は安全制約が成り立っていて、実行後に破れた」最初の動作と、その直前の状態を返す。

レポートの「安全制約を初めて破った制御動作」は、この関数の結果である。

```lean
#eval (firstViolation .naive .H3 init traceDBeforeC).map (·.2)   -- some (RenewalNotice.Action.runC)
```

これは**破れた瞬間の操作**であって、根本原因とは限らない。上の例（A, B, D, C）では C が指される。C が正常終了した時点で全ジョブが正常になり、「全ジョブ正常なのに対象者に届いていない」が確定するからである。しかし本当の原因は、D が C より先に古い表で送ったことにある。

## 5. 文字列にする：`Design.name`、`Action.str`、`traceStr`

```lean
def Design.name : Design → String
  | .naive => "naive"
  | .safe  => "safe"

def Action.str : Action → String
  | .runA        => "A"
  | .runB        => "B"
  | .runC        => "C"
  | .runD        => "D"
  | .crashD k    => s!"crashD:{k}"
  | .use u       => s!"use:{u}"
  | .breakSource => "breakSource"

/-- JSON の配列としても読める形で、実行順を文字列にする。 -/
def traceStr (t : List Action) : String :=
  "[" ++ ", ".intercalate (t.map (fun a => "\"" ++ a.str ++ "\"")) ++ "]"
```

- `Action.str` は、動作を JSON の文字列にする。この文字列は、Go 側の `Apply` 関数が受け取る形式と同じにしてある
- `traceStr` は、実行順を `["B", "C", "A", "D"]` の形にする。`intercalate` は「間に `, ` を挟んで連結する」

```lean
#eval traceStr scenarioA   -- "[\"B\", \"C\", \"A\", \"D\"]"
```

JSON のライブラリは使わず、文字列を連結して作っている。値に `"` や改行が入らないので、これで足りる。

## 6. 出力する：`Main.lean`

```lean
import RenewalNotice.ModelCheck
open RenewalNotice

/-! 各設計とハザードの組について最短の反例を探す。
    人間向けのレポートは stderr、Go テスト用の JSON は stdout に出す。
    使い方: lake exe explore > out/counterexamples.json
    同じ探索は `lake build` のときにも RenewalNotice/Audit.lean で実行され、警告として出る。 -/

def quote (s : String) : String := "\"" ++ s ++ "\""

def ctxStr (s : State) : String :=
  s!"today={s.today} tA(asOf={s.tA.asOf},{s.tA.rows}) tB(asOf={s.tB.asOf},{s.tB.rows}) " ++
  s!"tC(asOf={s.tC.asOf},{s.tC.rows}) inactive={s.world.inactive} sent={sentUsers s}"

def main : IO Unit := do
  let mut entries : Array String := #[]
  for d in [Design.naive, Design.safe] do
    for h in [Hazard.H1, Hazard.H2, Hazard.H3] do
      match counterexample d h alphabet searchBound with
      | none =>
        IO.eprintln s!"[{d.name}] {h.name}: 長さ{searchBound}以下の反例なし"
      | some t =>
        IO.eprintln s!"[{d.name}] {h.name} HAZARD: {h.describe}"
        IO.eprintln s!"    Loss Scenario: {traceStr t}"
        match firstViolation d h init t with
        | some (ctx, a) =>
          IO.eprintln s!"    安全制約を初めて破った制御動作: {a.str}（直前の状態: {ctxStr ctx}）"
        | none => pure ()
        entries := entries.push
          ("{" ++ quote "design" ++ ": " ++ quote d.name ++ ", " ++
                  quote "hazard" ++ ": " ++ quote h.name ++ ", " ++
                  quote "trace"  ++ ": " ++ traceStr t ++ "}")
  IO.println ("[\n  " ++ ",\n  ".intercalate entries.toList ++ "\n]")
```

`main` は実行ファイル `explore` の入り口である（`lakefile.toml` の `[[lean_exe]]` で `root = "Main"` と指定している）。

処理の流れ：

1. 設計（naive、safe）× ハザード（H1〜H3）の6通りについてループする
2. それぞれ `counterexample` で最短の反例を探す
3. 見つからなければ、レポートに「反例なし」と書く（`IO.eprintln` は標準エラー出力）
4. 見つかれば、
   - レポートにハザードの文言、実行順、`firstViolation` の結果を書く
   - JSON の1件分（`{"design": ..., "hazard": ..., "trace": [...]}`）を `entries` に追加する
5. 最後に、`entries` を `[` と `]` で囲み、`,` でつないで JSON 配列として標準出力に書く（`IO.println`）

ループの順番が「naive の H1、H2、H3、safe の H1、H2、H3」なので、JSON もこの順に並ぶ。

## 7. Go のテストで読む

Go のテスト（[`go/batch/system_test.go`](../go/batch/system_test.go)）は、このファイルを読み、各反例を実装で再生する。

```go
type leanCounterexample struct {
	Design string   `json:"design"`
	Hazard string   `json:"hazard"`
	Trace  []string `json:"trace"`
}

func TestLeanCounterexamplesReproduce(t *testing.T) {
	data, err := os.ReadFile("../../lean/out/counterexamples.json")
	if err != nil {
		t.Skip("Leanの出力がありません（lean/ で lake exe explore > out/counterexamples.json を実行してください）")
	}
	var ces []leanCounterexample
	if err := json.Unmarshal(data, &ces); err != nil {
		t.Fatal(err)
	}
	if len(ces) == 0 {
		t.Fatal("反例が0件です。Leanの出力を確認してください")
	}
	for _, ce := range ces {
		got := replay(t, Design(ce.Design), ce.Trace)
		if !slices.Contains(got, ce.Hazard) {
			t.Errorf("Leanの反例 %s/%s %v が実装で再現しない（got %v）。モデルと実装が乖離しています",
				ce.Design, ce.Hazard, ce.Trace, got)
		}
	}
}
```

- `replay` は、指定した設計で初期状態を作り、`trace` の各文字列を `Apply` で順に実行し、最後に Go 自身の判定関数 `Hazards()` でハザードを調べる
- Lean が言ったハザードが Go の判定結果に含まれていれば合格。含まれなければ、モデルと実装がずれている
- ハザードの判定は Go が自分のコード（`go/batch/safety.go`）で行っている。Lean の結果をそのまま使っているわけではない

## 8. 探索の範囲を変える

自分のアプリに当てはめたり、探索を広げたりするときに変える場所は次のとおり。

| 変えたいこと | 変える場所 |
|---|---|
| 探索する動作の種類 | `alphabet`（例：`.use 2` や `.crashD 0` を追加する） |
| 探索する長さの上限 | `searchBound`（1増やすと実行順の数がおよそ7倍になる） |
| 探索するハザード | `Main.lean` と `Audit.lean` の `[Hazard.H1, Hazard.H2, Hazard.H3]` |
| JSON の項目 | `Main.lean` の `entries.push` の中身と、Go の `leanCounterexample` 構造体の両方 |

`alphabet` や `searchBound` を変えると、`lake build` のハザード検出（[7章](07-build-audit.md)）と `safe_bounded` の検査範囲も同じように変わる。
