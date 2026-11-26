import BatchHazard.Model
/-!
# Loss / Hazard / Safety Constraint

| Loss | Hazard | Safety Constraint（Hazard の否定） |
|---|---|---|
| L1 継続したい人が不要な退会をする | H1 対象外のユーザーに送られる | `sc1` 送信時点で真の対象者にだけ送る |
| L2 重複した案内で不信感を与える | H2 同じユーザーに重複して送られる | `sc2` 送信先に重複がない |
| L3 案内を受けずに更新を迎える | H3 全ジョブが正常終了したのに対象者が漏れている | `sc3` 全ジョブ正常終了なら対象者全員に送られている |

ハザードは「安全制約を満たさない到達可能状態が存在すること」として定義する。
-/
namespace BatchHazard

def nodupB : List User → Bool
  | []      => true
  | x :: xs => !xs.contains x && nodupB xs

def sc1 (s : State) : Bool := s.sent.all (fun p => p.2)

def sc2 (s : State) : Bool := nodupB (sentUsers s)

def allOk (s : State) : Bool :=
  s.rA == .ok && s.rB == .ok && s.rC == .ok && s.rD == .ok

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

def Hazard.describe : Hazard → String
  | .H1 => "対象外のユーザーに退会案内が送られる (→L1)"
  | .H2 => "同じユーザーに重複して送られる (→L2)"
  | .H3 => "全ジョブ正常終了なのに対象者が漏れている (→L3)"

def safeAll (s : State) : Bool := sc1 s && sc2 s && sc3 s

end BatchHazard
