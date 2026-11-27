import RenewalNotice.Scenarios
import LeanAtlas
/-!
# 各バッチの単体仕様

各バッチが単体では仕様どおりに動くことを、すべての入力について証明する。
A と B は設計（naive / safe）によらず同じ定義なので、1つの定理で両方を覆う。
C と D は設計ごとに定義が違うので、設計ごとに仕様を書く。
-/
namespace RenewalNotice

/-! ## A・B（両設計で共通） -/

@[formalMeta "A単体仕様" "Aは利用ログどおりに非アクティブ者を抽出し、正常終了する（両設計共通）" "STPA: コンポーネントの正しさ",
  confidence high, proof_progress complete]
theorem batchA_spec (s : State) (u : User) :
    (u ∈ (batchA s).tA.rows ↔ u ∈ s.world.users ∧ s.world.inactiveLog.contains u = true) ∧
    (batchA s).tA.asOf = s.today ∧ (batchA s).rA = .ok := by
  simp [batchA, List.mem_filter]

@[formalMeta "B単体仕様" "Bは契約どおりに翌月更新者を抽出し、正常終了する（両設計共通）" "STPA: コンポーネントの正しさ",
  confidence high, proof_progress complete]
theorem batchB_spec (s : State) (u : User) :
    (u ∈ (batchB s).tB.rows ↔ u ∈ s.world.users ∧ s.world.renewing.contains u = true) ∧
    (batchB s).tB.asOf = s.today ∧ (batchB s).rB = .ok := by
  simp [batchB, List.mem_filter]

/-! ## C -/

@[formalMeta "C単体仕様（naive）" "CはtAとtBの積集合を取り、正常終了する" "STPA: コンポーネントの正しさ",
  confidence high, proof_progress complete]
theorem batchC_naive_spec (s : State) (u : User) :
    (u ∈ (batchC .naive s).tC.rows ↔ u ∈ s.tA.rows ∧ s.tB.rows.contains u = true) ∧
    (batchC .naive s).rC = .ok := by
  simp [batchC, intersect, List.mem_filter]

@[formalMeta "C単体仕様（safe・入力が新しい）" "tAとtBの基準日が今日なら、積集合を取り正常終了する" "STPA: コンポーネントの正しさ",
  confidence high, proof_progress complete]
theorem batchC_safe_spec_fresh (s : State) (h : s.tA.asOf = s.today ∧ s.tB.asOf = s.today) :
    (batchC .safe s).tC = intersect s.tA s.tB s.today ∧ (batchC .safe s).rC = .ok := by
  simp [batchC, h]

@[formalMeta "C単体仕様（safe・入力が古い）" "tAかtBの基準日が今日でなければ、tCを変えずに失敗で終わる" "STPA: コンポーネントの正しさ",
  confidence high, proof_progress complete]
theorem batchC_safe_spec_stale (s : State) (h : ¬ (s.tA.asOf = s.today ∧ s.tB.asOf = s.today)) :
    (batchC .safe s).tC = s.tC ∧ (batchC .safe s).rC = .failed := by
  simp [batchC, h]

/-! ## D -/

@[formalMeta "D単体仕様（naive）" "DはtCの全員に送り、正常終了する" "STPA: コンポーネントの正しさ",
  confidence high, proof_progress complete]
theorem batchD_naive_spec (s : State) :
    sentUsers (batchD .naive none s) = sentUsers s ++ s.tC.rows ∧
    (batchD .naive none s).rD = .ok := by
  simp [batchD, batchDNaive, sentUsers, record, limit, doneResult, List.map_append, List.map_map,
    Function.comp_def]

@[formalMeta "D単体仕様（safe・入力が新しい）" "tCの基準日が今日なら、未送信かつ今も対象の人全員に送り、正常終了する" "STPA: コンポーネントの正しさ",
  confidence high, proof_progress complete]
theorem batchD_safe_spec_fresh (s : State) (h : s.tC.asOf = s.today) :
    sentUsers (batchD .safe none s) = sentUsers s ++ pending s ∧
    (batchD .safe none s).rD = .ok := by
  simp [batchD, batchDSafe, h, sentUsers, record, limit, doneResult, List.map_append, List.map_map,
    Function.comp_def]

@[formalMeta "D単体仕様（safe・入力が古い）" "tCの基準日が今日でなければ、何も送らずに失敗で終わる" "STPA: コンポーネントの正しさ",
  confidence high, proof_progress complete]
theorem batchD_safe_spec_stale (s : State) (k : Option Nat) (h : s.tC.asOf ≠ s.today) :
    (batchD .safe k s).sent = s.sent ∧ (batchD .safe k s).rD = .failed := by
  simp [batchD, batchDSafe, h]

@[formalMeta "D単体仕様（safe・送信済みは除く）" "safeのDが送る相手には、送信済みの人が含まれない" "STPA: フィードバックの利用",
  confidence high, proof_progress complete]
theorem pending_not_sent (s : State) (u : User) (hu : u ∈ pending s) :
    (sentUsers s).contains u = false := by
  simp only [pending, List.mem_filter, Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true] at hu
  exact hu.2.1

@[formalMeta "D単体仕様（safe・対象者だけ）" "safeのDは、送る時点で本当に対象の人にだけ送る" "STPA: Safety Constraint SC1 の局所版",
  confidence high, proof_progress complete]
theorem batchDSafe_sentOk (k : Option Nat) (s : State) (h : SentOk s) :
    SentOk (batchDSafe k s) := by
  unfold batchDSafe
  split
  · intro p hp
    simp only [List.mem_append, record, List.mem_map] at hp
    rcases hp with hp | ⟨u, hu, rfl⟩
    · exact h p hp
    · have hu' : u ∈ pending s := by
        cases k with
        | none   => exact hu
        | some n => exact List.mem_of_mem_take hu
      simp only [pending, List.mem_filter, Bool.and_eq_true] at hu'
      exact hu'.2.2
  · exact h

end RenewalNotice
