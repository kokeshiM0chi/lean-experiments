import BatchHazard.Safety
/-!
# 有界モデル検査: 「証明できない」を反例の探索に置き換える

Lean では、証明に失敗したことを証明の中から検出できない。そこで、全称命題
`∀ t, sc (run d init t) = true` を証明しようとする代わりに、長さ n 以下の全トレースを
列挙して反例を探す。見つかった反例トレースは、STPA の Loss Scenario にあたる。
-/
namespace BatchHazard

/-- スケジューラーと外乱が起こしうる動作。 -/
def alphabet : List Action :=
  [.runA, .runB, .runC, .runD, .crashD 1, .use 1, .breakSource]

/-- ログソース故障を除いた動作。 -/
def alphabetNoSourceFault : List Action :=
  [.runA, .runB, .runC, .runD, .crashD 1, .use 1]

def tracesExact (al : List Action) : Nat → List (List Action)
  | 0     => [[]]
  | n + 1 => (tracesExact al n).flatMap (fun t => al.map (fun a => t ++ [a]))

/-- 長さ n 以下の全トレース。短い順に並ぶ。 -/
def tracesUpTo (al : List Action) (n : Nat) : List (List Action) :=
  (List.range (n + 1)).flatMap (tracesExact al)

/-- 設計 d でハザード h を起こす最短のトレース（Loss Scenario）。 -/
def counterexample (d : Design) (h : Hazard) (al : List Action) (n : Nat) : Option (List Action) :=
  (tracesUpTo al n).find? (fun t => !h.sc (run d init t))

/-- トレース中で、安全制約を初めて破った制御動作とその直前の状態（コンテキスト）を返す。
    STPA の UCA（どんなコンテキストで、どの制御動作が危険だったか）にあたる。 -/
def firstUCA (d : Design) (h : Hazard) : State → List Action → Option (State × Action)
  | _, []     => none
  | s, a :: t =>
    let s' := step d s a
    if h.sc s && !h.sc s' then some (s, a) else firstUCA d h s' t

end BatchHazard
