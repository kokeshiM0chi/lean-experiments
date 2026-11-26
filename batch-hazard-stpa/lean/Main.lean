import BatchHazard
open BatchHazard

/-! 各設計とハザードの組について最短の反例を探す。
    人間向けのレポートは stderr、Go テスト用の JSON は stdout に出す。
    使い方: lake exe hazards > out/counterexamples.json -/

def actionStr : Action → String
  | .runA        => "A"
  | .runB        => "B"
  | .runC        => "C"
  | .runD        => "D"
  | .crashD k    => s!"crashD:{k}"
  | .use u       => s!"use:{u}"
  | .breakSource => "breakSource"

def designStr : Design → String
  | .naive => "naive"
  | .safe  => "safe"

def quote (s : String) : String := "\"" ++ s ++ "\""

def jsonTrace (t : List Action) : String :=
  "[" ++ ", ".intercalate (t.map (quote ∘ actionStr)) ++ "]"

def ctxStr (s : State) : String :=
  s!"today={s.today} tA(asOf={s.tA.asOf},{s.tA.rows}) tB(asOf={s.tB.asOf},{s.tB.rows}) " ++
  s!"tC(asOf={s.tC.asOf},{s.tC.rows}) inactive={s.world.inactive} sent={sentUsers s}"

def bound : Nat := 5

def main : IO Unit := do
  let mut entries : Array String := #[]
  for d in [Design.naive, Design.safe] do
    for h in [Hazard.H1, Hazard.H2, Hazard.H3] do
      match counterexample d h alphabet bound with
      | none =>
        IO.eprintln s!"[{designStr d}] {h.name}: 長さ{bound}以下の反例なし"
      | some t =>
        IO.eprintln s!"[{designStr d}] {h.name} HAZARD: {h.describe}"
        IO.eprintln s!"    Loss Scenario: {jsonTrace t}"
        match firstUCA d h init t with
        | some (ctx, a) =>
          IO.eprintln s!"    UCA: 制御動作 {actionStr a}, コンテキスト {ctxStr ctx}"
        | none => pure ()
        entries := entries.push
          ("{" ++ quote "design" ++ ": " ++ quote (designStr d) ++ ", " ++
                  quote "hazard" ++ ": " ++ quote h.name ++ ", " ++
                  quote "trace"  ++ ": " ++ jsonTrace t ++ "}")
  IO.println ("[\n  " ++ ",\n  ".intercalate entries.toList ++ "\n]")
