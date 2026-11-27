# 2. Loss・Hazard・UCA を定義にする（`Safety.lean`、`Uca.lean`）

ソース：[`lean/RenewalNotice/Safety.lean`](../lean/RenewalNotice/Safety.lean)、[`lean/RenewalNotice/Uca.lean`](../lean/RenewalNotice/Uca.lean)

## この章で言いたいこと

元記事の STPA の分析結果（Loss、Hazard、UCA）を、状態を受け取って Bool を返す関数にする。
関数にしておくと、次の2つができるようになる。

- 定理の中で「安全制約が破れる」「UCA が起きる」と書ける
- 探索プログラムで「破れる実行順」を自動で探せる

ここにも定理はない。

## Loss と Hazard（元記事）

| Loss | Hazard |
|---|---|
| L1 誤った退会案内によって、継続を望むユーザーが不要な退会をしてしまう | H1 通知対象外のユーザーが、退会案内の配信対象に含まれている |
| L2 重複する退会案内によって、ユーザーに不信感を与える | H2 同じユーザー・契約更新期に対する通知が、重複して発行可能な状態にある |
| L3 通知対象のユーザーが案内を受けられず、意図しない契約更新を迎える | H3 案内が必要な対象者について、通知期限までに送信を開始できない状態にある |

STPA では、Hazard を否定したものが安全制約になる。元記事が安全制約として明示しているのは H2 に対応するもの（重複する通知指示を発行してはならない）だけなので、H1 と H3 については Hazard を否定して導いた。

## 安全制約：`sc1`〜`sc3`

```lean
def nodupB : List User → Bool
  | []      => true
  | x :: xs => !xs.contains x && nodupB xs

/-- H1 の否定：送信記録はすべて、送った時点で本当の対象者宛てである。 -/
def sc1 (s : State) : Bool := s.sent.all (fun p => p.2)

/-- H2 の否定（記事が明示した安全制約）：同じユーザーに重複して送っていない。 -/
def sc2 (s : State) : Bool := nodupB (sentUsers s)

def allOk (s : State) : Bool :=
  s.rA == .ok && s.rB == .ok && s.rC == .ok && s.rD == .ok

/-- H3 の否定：全ジョブが正常終了しているなら、対象者全員に送っている。 -/
def sc3 (s : State) : Bool :=
  !allOk s || s.world.users.all (fun u => !s.world.isTarget u || (sentUsers s).contains u)
```

| 関数 | 読み方 | false になる（＝ハザード）とき |
|---|---|---|
| `sc1 s` | 送信記録の第2成分（送った時点で本当に対象だったか）がすべて true | 対象外の人に送った記録がある（H1） |
| `sc2 s` | 送った相手の一覧に重複がない（`nodupB` は「重複がなければ true」） | 同じ人に2回以上送った（H2） |
| `sc3 s` | 全ジョブが正常終了していなければ true。正常終了しているなら、本当の対象者全員が送信済み | 全ジョブ正常終了なのに、送られていない対象者がいる（H3） |

`sc3` の `!allOk s || ...` は、「全ジョブ正常終了 ならば 全員送信済み」を Bool で書いたものである（「P ならば Q」は「P でない、または Q」と同じ）。

### H3 の読み替え

元記事の H3 は「通知期限までに送信を開始できない」である。このモデルには時刻の進みがないので、「全ジョブが正常終了した時点」を期限とみなした。ジョブが失敗していれば監視で気づけるので、ここで捉えたいのは「正常終了に見えるのに届いていない」場合である。

## ハザードを値として扱う：`Hazard`

```lean
inductive Hazard where
  | H1 | H2 | H3
deriving Repr, DecidableEq

/-- ハザード h に対応する安全制約。 -/
def Hazard.sc : Hazard → State → Bool
  | .H1 => sc1
  | .H2 => sc2
  | .H3 => sc3

def Hazard.name : Hazard → String
  | .H1 => "H1"
  | .H2 => "H2"
  | .H3 => "H3"

/-- 記事の Hazard の文言（括弧内はつながる Loss）。 -/
def Hazard.describe : Hazard → String
  | .H1 => "通知対象外のユーザーが、退会案内の配信対象に含まれている (→L1)"
  | .H2 => "同じユーザー・契約更新期に対する通知が、重複して発行可能な状態にある (→L2)"
  | .H3 => "案内が必要な対象者について、通知期限までに送信を開始できない状態にある (→L3)"

def safeAll (s : State) : Bool := sc1 s && sc2 s && sc3 s
```

- `Hazard` を型にしておくと、探索プログラムで「H1〜H3 のそれぞれについて反例を探す」とループで書ける（[6章](06-counterexamples.md)）
- `describe` は、ビルド時の警告に出す文言である
- `safeAll` は「3つの安全制約をすべて満たす」

## UCA（`Uca.lean`）

UCA（Unsafe Control Action）は「どんな状況で、どの制御動作を出すと危険か」である。元記事の UCA 表は、通知制御の制御動作「プッシュ通知の配信指示」を対象にしている。このモデルでは、通知制御をバッチ C と D に分けて実装している。

| 分類 | 元記事の UCA | このファイル |
|---|---|---|
| Not Providing | 対象者の抽出が完了しているのに、期限までに送信を開始しない | `ucaNotProviding` |
| Providing | 通知済みか不明なユーザーに対して、新しい送信を開始する | `ucaProviding` |
| Timing / Order | 対象者抽出の完了前に通知を開始する | `ucaTiming` |
| Duration | N/A（元記事でも挙がっていない） | なし |

### その動作で何が送られたか：`newSends`

```lean
/-- 制御動作 `a` によって、配信基盤が新たに受理した宛先。 -/
def newSends (d : Design) (s : State) (a : Action) : List User :=
  ((step d s a).sent.drop s.sent.length).map (·.1)
```

送信記録は後ろに追加されるだけなので、「動作後の記録から、動作前の件数分を取り除いたもの」が、その動作で新たに送った相手になる。

### Timing / Order：`ucaTiming`

```lean
/-- Timing / Order：今日の抽出（A・B）が終わる前に作られた通知対象で、送信を始める。
    記事の制御構造では C と D をまとめて「通知制御」としているので、
    「C が古い A・B の結果で対象を作り、D がそれで送る」もここに当たる。 -/
def ucaTiming (d : Design) (s : State) (a : Action) : Bool :=
  (s.tCInputsAsOf != s.today) && !(newSends d s a).isEmpty
```

読み方：「今の tC が今日の A・B から作られていない」かつ「この動作で誰かに送った」なら true。

tC の `asOf` ではなく `tCInputsAsOf`（観測者だけが知る、実際に使った表の日付）を見ているのがポイントである。対策なし版の C は、古い表から作った tC にも今日の日付を付けるので、`asOf` を見ると見逃してしまう。

### Providing：`ucaProviding`

```lean
/-- Providing：配信基盤がすでに受理したユーザーに、また送る。 -/
def ucaProviding (d : Design) (s : State) (a : Action) : Bool :=
  (newSends d s a).any (fun u => (sentUsers s).contains u)
```

読み方：「この動作で送った相手の中に、すでに受理済みの人がいる」なら true。

元記事の「通知済みか不明なユーザー」には、タイムアウトで結果が分からない人も含まれる。このモデルでは、タイムアウトしても配信基盤の受理記録（`sent`）には残るので、「受理済みの人にまた送る」で両方を捉えている。

### Not Providing：`ucaNotProviding`

```lean
/-- Not Providing：全ジョブが正常終了した時点で、今日抽出した対象者の中に送られていない人がいる。 -/
def ucaNotProviding (s : State) : Bool :=
  allOk s && (s.tC.asOf == s.today) &&
    s.tC.rows.any (fun u => s.world.isTarget u && !(sentUsers s).contains u)
```

読み方：「全ジョブが正常終了」かつ「tC は今日のもの」かつ「tC の中に、本当の対象者なのに送られていない人がいる」なら true。

「送らなかった」ことは1回の動作では表せないので、状態についての述語にした。

### UCA を値として扱う：`Uca`、`Uca.occurs`、`ucaInTrace`

```lean
inductive Uca where
  | notProviding | providing | timing
deriving Repr, DecidableEq

/-- 状態 `s` で制御動作 `a` を出したとき、UCA `u` に当たるか。 -/
def Uca.occurs (d : Design) (s : State) (a : Action) : Uca → Bool
  | .notProviding => !ucaNotProviding s && ucaNotProviding (step d s a)
  | .providing    => ucaProviding d s a
  | .timing       => ucaTiming d s a

/-- 実行順のどこかで UCA `u` が起きるか。 -/
def ucaInTrace (d : Design) (u : Uca) : State → List Action → Bool
  | _, []     => false
  | s, a :: t => u.occurs d s a || ucaInTrace d u (step d s a) t
```

- `Uca.occurs` は、1つの動作が UCA に当たるかを判定する。Not Providing は「その動作の前は false、後は true になった」ときに、その動作で起きたとみなす
- `ucaInTrace` は、実行順を先頭から1つずつ進めながら、どこかで UCA が起きるかを調べる。`run` と同じ形の再帰になっている

これらは、[4章](04-hazards.md)の「naive では UCA が起きる」と、[5章](05-safe-design.md)の「safe では UCA が起きない」の定理で使う。
