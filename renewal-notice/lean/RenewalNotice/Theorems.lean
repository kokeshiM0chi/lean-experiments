import RenewalNotice.ModelCheck
import LeanAtlas
/-!
# 定理

1. 局所的正しさ: 各バッチは単体では仕様どおり（全称命題として証明する）
2. ハザードの存在: naive の組み合わせでは安全制約を破るトレースが存在する（存在命題として証明する）
3. 「naive は安全」は偽: 全称の安全性定理の否定を証明する
4. 対策の検証: safe 設計の SC1 は任意長トレースで成り立つ（帰納法）。SC1〜SC3 は有界に全数検査する
5. 残留ハザード: safe 設計でもログソース故障では H3 が起きる
-/
namespace RenewalNotice

/-! ## 1. 局所的正しさ -/

@[formalMeta "A単体仕様" "バッチAは利用ログどおりに非アクティブ者を抽出する" "STPA: コンポーネントの正しさ", confidence high, proof_progress complete]
theorem batchA_spec (s : State) (u : User) :
    u ∈ (batchA s).tA.rows ↔ u ∈ s.world.users ∧ s.world.inactiveLog.contains u = true := by
  simp [batchA, List.mem_filter]

@[formalMeta "B単体仕様" "バッチBは契約どおりに翌月更新者を抽出する" "STPA: コンポーネントの正しさ", confidence high, proof_progress complete]
theorem batchB_spec (s : State) (u : User) :
    u ∈ (batchB s).tB.rows ↔ u ∈ s.world.users ∧ s.world.renewing.contains u = true := by
  simp [batchB, List.mem_filter]

@[formalMeta "C単体仕様" "バッチCはAとBの積集合を取る" "STPA: コンポーネントの正しさ", confidence high, proof_progress complete]
theorem batchC_spec (s : State) (u : User) :
    u ∈ (batchC .naive s).tC.rows ↔ u ∈ s.tA.rows ∧ s.tB.rows.contains u = true := by
  simp [batchC, intersect, List.mem_filter]

@[formalMeta "D単体仕様" "バッチDは確定した対象者全員に送る" "STPA: コンポーネントの正しさ", confidence high, proof_progress complete]
theorem batchD_spec (s : State) :
    sentUsers (batchD .naive none s) = sentUsers s ++ s.tC.rows ∧
    (batchD .naive none s).rD = .ok := by
  simp [batchD, batchDNaive, sentUsers, record, limit, doneResult, List.map_append, List.map_map,
    Function.comp_def]

/-! ## 2. ハザードの存在（Loss Scenario） -/

/-- C が A・B より先に走り、前回サイクルの表で積集合を取る。 -/
def traceStale : List Action := [.runC, .runA, .runB, .runD]
/-- C が対象を確定した後、D が送る前にユーザーが利用を再開する。 -/
def traceTOCTOU : List Action := [.runA, .runB, .runC, .use 1, .runD]
/-- D が途中で異常終了し、スケジューラーが D 全体を再実行する。 -/
def traceRetry : List Action := [.runA, .runB, .runC, .crashD 1, .runD]
/-- ログソースが壊れて A が 0 件で正常終了する。 -/
def traceSilent : List Action := [.breakSource, .runA, .runB, .runC, .runD]

@[formalMeta "H1: stale join" "Cが古い表で積集合を取り対象外に送る" "STPA: Loss Scenario → H1", proof_progress complete]
theorem H1_stale     : sc1 (run .naive init traceStale)  = false := by decide
@[formalMeta "H3: stale join" "古い表のせいで全ジョブ正常終了なのに対象者が漏れる" "STPA: Loss Scenario → H3", proof_progress complete]
theorem H3_stale     : sc3 (run .naive init traceStale)  = false := by decide
@[formalMeta "H1: TOCTOU" "C確定後の利用再開で対象外に送る" "STPA: Loss Scenario → H1", proof_progress complete]
theorem H1_toctou    : sc1 (run .naive init traceTOCTOU) = false := by decide
@[formalMeta "H2: retry" "部分失敗後の再実行で重複送信" "STPA: Loss Scenario → H2", proof_progress complete]
theorem H2_retry     : sc2 (run .naive init traceRetry)  = false := by decide
@[formalMeta "H3: silent" "ログ故障で0件のまま正常終了" "STPA: Loss Scenario → H3", proof_progress complete]
theorem H3_silent    : sc3 (run .naive init traceSilent) = false := by decide

/-! ## 3. 「各バッチは正しい」から「システムは安全」は導けない -/

@[formalMeta "部品正常でもシステムは危険" "各バッチは単体仕様どおりだが、組み合わせると安全制約を破る" "STPA: Hazard の存在" mainTheorem, confidence high, proof_progress complete]
theorem naive_unsafe :
    ¬ ∀ t : List Action, safeAll (run .naive init t) = true := by
  intro h
  exact absurd (h traceRetry) (by decide)

/-! ## 4. 対策の検証 -/

/-- 送信記録はすべて、送信時点で真の対象者宛てだった。 -/
def SentOk (s : State) : Prop := ∀ p ∈ s.sent, p.2 = true

theorem mem_limit {k : Option Nat} {us : List User} {u : User} (h : u ∈ limit k us) : u ∈ us := by
  cases k with
  | none   => exact h
  | some n => exact List.mem_of_mem_take h

@[proof_progress complete]
theorem batchDSafe_sentOk (k : Option Nat) (s : State) (h : SentOk s) :
    SentOk (batchDSafe k s) := by
  unfold batchDSafe
  split
  · intro p hp
    simp only [List.mem_append, record, List.mem_map] at hp
    rcases hp with hp | ⟨u, hu, rfl⟩
    · exact h p hp
    · have hu' := mem_limit hu
      simp only [pending, List.mem_filter, Bool.and_eq_true] at hu'
      exact hu'.2.2
  · exact h

@[proof_progress complete]
theorem step_safe_sentOk (s : State) (a : Action) (h : SentOk s) :
    SentOk (step .safe s a) := by
  cases a with
  | runA        => exact h
  | runB        => exact h
  | runC        =>
    show SentOk (batchC .safe s)
    simp only [batchC]
    split
    · exact h
    · exact h
  | runD        => exact batchDSafe_sentOk none s h
  | crashD k    => exact batchDSafe_sentOk (some k) s h
  | use u       => exact h
  | breakSource => exact h

/-- safe 設計では、どんな順序・外乱・長さのトレースでも H1 は起きない。 -/
@[formalMeta "対策版にH1なし" "任意の順序・外乱・長さで対象外送信が起きない" "STPA: Safety Constraint SC1" mainTheorem, confidence high, proof_progress complete]
theorem safe_no_H1 (t : List Action) (s : State) (h : SentOk s) :
    SentOk (run .safe s t) := by
  induction t generalizing s with
  | nil => exact h
  | cons a t ih => exact ih _ (step_safe_sentOk s a h)

/-- ログソース故障を除けば、長さ 5 以下の全トレース（9331 本）で SC1〜SC3 が成り立つ。
    `native_decide` はコンパイラを信頼する。カーネルだけで検査したい場合は境界を下げて `decide` を使う。 -/
@[formalMeta "対策版の有界全数検査" "長さ5以下の全トレースでSC1〜SC3が成り立つ" "STPA: SC1〜SC3（有界）" mainTheorem, confidence medium, proof_progress complete]
theorem safe_bounded :
    (tracesUpTo alphabetNoSourceFault 5).all (fun t => safeAll (run .safe init t)) = true := by
  native_decide

/-- 未証明の安全主張: SC2 を任意長トレースで示したいが、まだ証明できていない。
    証明できていない安全主張は、ハザードの候補として扱う。 -/
@[formalMeta "対策版にH2なし（未証明）" "任意長トレースで重複送信が起きない" "STPA: Safety Constraint SC2（未証明＝ハザード候補）" mainTheorem, confidence medium, proof_progress stub]
theorem safe_no_H2 (t : List Action) : sc2 (run .safe init t) = true := by
  sorry

/-! ## 5. 残留ハザード: 対策後も残るもの -/

/-- 抽出結果の完全性を確認していないので、ログソースが故障すると safe 設計でも H3 が起きる。
    これが次の安全要求（0 件や件数急減を検知する）につながる。 -/
@[formalMeta "残留ハザードH3" "対策版でもログ故障で対象者が漏れる" "STPA: 残留 Hazard → 新しい安全要求" mainTheorem, confidence high, proof_progress complete]
theorem safe_residual_H3 : sc3 (run .safe init traceSilent) = false := by decide

end RenewalNotice
