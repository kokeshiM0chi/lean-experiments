import RenewalNotice.Model
/-!
# Loss / Hazard / Safety Constraint

元記事（https://zenn.dev/maruloop/articles/7ff108e29741b5）の実践例の表を、そのまま Lean の定義に移す。

| Loss（記事） | Hazard（記事） | 安全制約（この形式化） |
|---|---|---|
| L1 誤った退会案内によって、継続を望むユーザーが不要な退会をしてしまう | H1 通知対象外のユーザーが、退会案内の配信対象に含まれている | `sc1` 送った時点で本当に対象のユーザーにだけ送っている |
| L2 重複する退会案内によって、ユーザーに不信感を与える | H2 同じユーザー・契約更新期に対する通知が、重複して発行可能な状態にある | `sc2` 同じユーザーに重複して送っていない |
| L3 通知対象のユーザーが案内を受けられず、意図しない契約更新を迎える | H3 案内が必要な対象者について、通知期限までに送信を開始できない状態にある | `sc3` 全ジョブが正常終了した時点で、対象者全員に送っている |

記事が安全制約として明示しているのは
「同じユーザー・契約更新期に対し、重複する通知指示を発行してはならない」（`sc2`）だけで、
`sc1` と `sc3` は、STPA の手順どおり Hazard を否定して導いた。

H3 の「通知期限」について：このモデルには時刻の進みがないので、
「全ジョブが正常終了した時点（スケジューラーから見てサイクルが完了した時点）」を期限とみなす。
ジョブが失敗していれば監視で気づけるので、ここで扱うのは記事のシナリオDのような
「正常終了に見えるのに届いていない」場合である。

ハザードは「安全制約を満たさない状態に、何らかの実行順で到達できること」として扱う。
-/
namespace RenewalNotice

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

end RenewalNotice
