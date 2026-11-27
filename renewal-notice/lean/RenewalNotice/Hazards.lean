import RenewalNotice.Spec
/-!
# 対策なし（naive）のハザード

各バッチは単体仕様どおり（`Spec.lean`）なのに、組み合わせると安全制約を破る実行順がある。
ここでは、元記事の Loss Scenario A〜D と UCA を、それぞれ定理として示す。

`by decide` は「実際にモデルを動かして確かめよ」という指示で、
Lean のカーネルが実行順どおりに計算し、安全制約が破れることを検査する。
-/
namespace RenewalNotice

/-! ## 元記事の Loss Scenario A〜D -/

@[formalMeta "シナリオA：依存関係が守られない" "Aが遅延中にCが時刻どおり起動し、前回のAの結果で対象を作るので、対象外の会員0に届く" "記事 Loss Scenario A → H1 → L1",
  confidence high, proof_progress complete]
theorem scenarioA_H1 : sc1 (run .naive init scenarioA) = false := by decide

@[formalMeta "シナリオB：部分失敗後のリトライ" "Dが1人に送った時点で異常終了し、D全体の再実行でその人にまた送る" "記事 Loss Scenario B → H2 → L2",
  confidence high, proof_progress complete]
theorem scenarioB_H2 : sc2 (run .naive init scenarioB) = false := by decide

@[formalMeta "シナリオC：送信状態を認識できない" "配信基盤は全員分を受理したがタイムアウトし、Dの再実行で全員にまた送る" "記事 Loss Scenario C → H2 → L2",
  confidence high, proof_progress complete]
theorem scenarioC_H2 : sc2 (run .naive init scenarioC) = false := by decide

@[formalMeta "シナリオD：正常終了なのに届かない" "ログ故障でAが0件のまま正常終了し、全ジョブ正常なのに対象者に届かない" "記事 Loss Scenario D → H3 → L3",
  confidence high, proof_progress complete]
theorem scenarioD_H3 : sc3 (run .naive init scenarioD) = false := by decide

/-! ## 元記事の UCA が naive で起きること

UCA は「どんな状況で、どの制御動作を出すと危険か」。naive ではどれも実際に起き、ハザードにつながる。 -/

@[formalMeta "UCA Timing：抽出完了前に通知" "シナリオAの最後のDは、今日のAの結果から作られていない対象で送信を始め、H1になる" "記事 UCA Timing/Order → H1",
  confidence high, proof_progress complete]
theorem uca_timing_naive :
    ucaTiming .naive (run .naive init [.runB, .runC, .runA]) .runD = true ∧
    sc1 (run .naive init scenarioA) = false := by decide

@[formalMeta "UCA Providing：通知済みの人に再送" "シナリオCで、配信基盤が受理済みの人に、Dの再実行でまた送り、H2になる" "記事 UCA Providing → H2",
  confidence high, proof_progress complete]
theorem uca_providing_naive :
    ucaProviding .naive (run .naive init [.runA, .runB, .runC, .crashD 2]) .runD = true ∧
    sc2 (run .naive init scenarioC) = false := by decide

@[formalMeta "UCA Not Providing：抽出済みなのに送らない" "DがCより先に古い表で送り、最後にCが終わると、今日の対象者に送られないまま全ジョブ正常になり、H3になる" "記事 UCA Not Providing → H3",
  confidence high, proof_progress complete]
theorem uca_notProviding_naive :
    ucaNotProviding (run .naive init traceDBeforeC) = true ∧
    sc3 (run .naive init traceDBeforeC) = false := by decide

@[formalMeta "シナリオDは通知制御のUCAではない" "シナリオDでは通知制御のUCAは起きていない。H3の原因は、A（抽出）の出力が不完全なこと" "記事 Loss Scenario D の分析",
  confidence high, proof_progress complete]
theorem scenarioD_no_notification_uca :
    ucaInTrace .naive .timing init scenarioD = false ∧
    ucaInTrace .naive .providing init scenarioD = false ∧
    ucaInTrace .naive .notProviding init scenarioD = false := by decide

/-! ## 記事にないシナリオ（自動探索・追加） -/

@[formalMeta "追加：Dだけで起きるH1" "前回分の表tCのままDが送る（自動探索で見つかった最短の反例）" "Loss Scenario → H1",
  confidence high, proof_progress complete]
theorem H1_onlyD : sc1 (run .naive init traceOnlyD) = false := by decide

@[formalMeta "追加：Dを2回でH2" "送信済みを確かめずにDを再実行する（自動探索で見つかった最短の反例）" "Loss Scenario → H2",
  confidence high, proof_progress complete]
theorem H2_DTwice : sc2 (run .naive init traceDTwice) = false := by decide

@[formalMeta "追加：TOCTOU" "Cが対象を確定した後、Dが送る前に会員が利用を再開し、対象外に送る" "Loss Scenario → H1",
  confidence high, proof_progress complete]
theorem H1_toctou : sc1 (run .naive init traceTOCTOU) = false := by decide

/-! ## 各バッチは正しいのに、システムは安全ではない -/

@[formalMeta "部品は正常でもシステムは危険" "各バッチは単体仕様どおりだが、組み合わせると安全制約を破る実行順が存在する" "STPA: Hazard の存在" mainTheorem,
  confidence high, proof_progress complete]
theorem naive_unsafe :
    ¬ ∀ t : List Action, safeAll (run .naive init t) = true := by
  intro h
  exact absurd (h scenarioB) (by decide)

/-! ## 対策後も残るハザード -/

@[formalMeta "残留ハザード：シナリオD" "対策版でも、ログ故障でAが0件になると対象者に届かない" "記事 Loss Scenario D → 新しい安全要求（対象者集合の完全性）" mainTheorem,
  confidence high, proof_progress complete]
theorem safe_residual_scenarioD : sc3 (run .safe init scenarioD) = false := by decide

end RenewalNotice
