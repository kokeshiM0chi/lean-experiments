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
