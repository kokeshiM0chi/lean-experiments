import RenewalNotice.Safety
/-!
# UCA（Unsafe Control Action）

元記事の UCA 表は、通知制御（このモデルではバッチ C と D）の制御動作「プッシュ通知の配信指示」を対象にしている。
その4分類を、「どんな状況（状態 `s`）で、どの制御動作（`a`）を出すと危険か」という述語にする。

| 分類 | 記事の UCA | この形式化 |
|---|---|---|
| Not Providing | 対象者の抽出が完了しているのに、期限までに送信を開始しない | `ucaNotProviding`：全ジョブ正常終了の時点で、今日抽出した対象者の中に、送られていない人がいる |
| Providing | 通知済みか不明なユーザーに対して、新しい送信を開始する | `ucaProviding`：配信基盤がすでに受理した（タイムアウトで結果不明のものを含む）ユーザーに、また送る |
| Timing / Order | 対象者抽出の完了前に通知を開始する | `ucaTiming`：今日の抽出（A・B）の結果から作られていない通知対象で、送信を始める |
| Duration | N/A（記事でも挙がっていない） | なし |

Not Providing は「送らなかった」ことなので、1回の制御動作ではなく、サイクル完了時点の状態の述語にした。
-/
namespace RenewalNotice

/-- 制御動作 `a` によって、配信基盤が新たに受理した宛先。 -/
def newSends (d : Design) (s : State) (a : Action) : List User :=
  ((step d s a).sent.drop s.sent.length).map (·.1)

/-- Timing / Order：今日の抽出（A・B）が終わる前に作られた通知対象で、送信を始める。
    記事の制御構造では C と D をまとめて「通知制御」としているので、
    「C が古い A・B の結果で対象を作り、D がそれで送る」もここに当たる。 -/
def ucaTiming (d : Design) (s : State) (a : Action) : Bool :=
  (s.tCInputsAsOf != s.today) && !(newSends d s a).isEmpty

/-- Providing：配信基盤がすでに受理したユーザーに、また送る。 -/
def ucaProviding (d : Design) (s : State) (a : Action) : Bool :=
  (newSends d s a).any (fun u => (sentUsers s).contains u)

/-- Not Providing：全ジョブが正常終了した時点で、今日抽出した対象者の中に送られていない人がいる。 -/
def ucaNotProviding (s : State) : Bool :=
  allOk s && (s.tC.asOf == s.today) &&
    s.tC.rows.any (fun u => s.world.isTarget u && !(sentUsers s).contains u)

inductive Uca where
  | notProviding | providing | timing
deriving Repr, DecidableEq

def Uca.name : Uca → String
  | .notProviding => "Not Providing"
  | .providing    => "Providing"
  | .timing       => "Timing / Order"

/-- 記事の UCA の文言。 -/
def Uca.describe : Uca → String
  | .notProviding => "対象者の抽出が完了しているのに、期限までに送信を開始しない"
  | .providing    => "通知済みか不明なユーザーに対して、新しい送信を開始する"
  | .timing       => "対象者抽出の完了前に通知を開始する"

/-- 状態 `s` で制御動作 `a` を出したとき、UCA `u` に当たるか。 -/
def Uca.occurs (d : Design) (s : State) (a : Action) : Uca → Bool
  | .notProviding => !ucaNotProviding s && ucaNotProviding (step d s a)
  | .providing    => ucaProviding d s a
  | .timing       => ucaTiming d s a

/-- 実行順のどこかで UCA `u` が起きるか。 -/
def ucaInTrace (d : Design) (u : Uca) : State → List Action → Bool
  | _, []     => false
  | s, a :: t => u.occurs d s a || ucaInTrace d u (step d s a) t

end RenewalNotice
