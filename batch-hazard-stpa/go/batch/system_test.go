package batch

import (
	"encoding/json"
	"os"
	"slices"
	"testing"
)

// ---- 単体テスト: 各バッチは単体では仕様どおりに動く（Lean: batchA_spec など） ----

func TestBatchesIndividuallyCorrect(t *testing.T) {
	s := NewSystem(Naive)
	s.BatchA()
	if !slices.Equal(s.TA.Rows, []User{1, 2}) || s.TA.AsOf != 1 {
		t.Fatalf("A: %+v", s.TA)
	}
	s.BatchB()
	if !slices.Equal(s.TB.Rows, []User{1, 2}) {
		t.Fatalf("B: %+v", s.TB)
	}
	if err := s.BatchC(); err != nil || !slices.Equal(s.TC.Rows, []User{1, 2}) {
		t.Fatalf("C: %+v %v", s.TC, err)
	}
	if err := s.BatchD(nil); err != nil || len(s.Sent) != 2 {
		t.Fatalf("D: %+v %v", s.Sent, err)
	}
	if hs := s.Hazards(); len(hs) != 0 {
		t.Fatalf("想定どおりの順序ならハザードは起きないはず: %v", hs)
	}
}

// ---- 組み合わせシナリオ（Lean: Hazards.lean の trace* と同じトレース） ----

type scenario struct {
	name  string
	trace []string
	naive []string // Naive 設計で起きるハザード
	safe  []string // Safe 設計で起きるハザード
}

var scenarios = []scenario{
	{"stale join: AとBより先にCが走る", []string{"C", "A", "B", "D"}, []string{"H1", "H3"}, nil},
	{"TOCTOU: C確定後に利用再開", []string{"A", "B", "C", "use:1", "D"}, []string{"H1"}, nil},
	{"partial failure + retry", []string{"A", "B", "C", "crashD:1", "D"}, []string{"H2"}, nil},
	{"silent completion: ログソース故障", []string{"breakSource", "A", "B", "C", "D"}, []string{"H3"}, []string{"H3"}},
}

func replay(t *testing.T, d Design, trace []string) []string {
	t.Helper()
	s := NewSystem(d)
	for _, a := range trace {
		if err := s.Apply(a); err != nil {
			t.Fatal(err)
		}
	}
	return s.Hazards()
}

func TestScenarios(t *testing.T) {
	for _, sc := range scenarios {
		t.Run(sc.name, func(t *testing.T) {
			if got := replay(t, Naive, sc.trace); !slices.Equal(got, sc.naive) {
				t.Errorf("naive: got %v want %v", got, sc.naive)
			}
			if got := replay(t, Safe, sc.trace); !slices.Equal(got, sc.safe) {
				t.Errorf("safe: got %v want %v", got, sc.safe)
			}
		})
	}
}

// ---- Lean が見つけた反例を実装で再生する（モデルと実装の適合性チェック） ----
//
// lean/ で `lake exe hazards > out/counterexamples.json` を実行すると生成される。
// Lean が「このトレースで設計 d はハザード h を起こす」と言ったものが、
// Go 実装でも本当に起きることを確認する。

type leanCounterexample struct {
	Design string   `json:"design"`
	Hazard string   `json:"hazard"`
	Trace  []string `json:"trace"`
}

func TestLeanCounterexamplesReproduce(t *testing.T) {
	data, err := os.ReadFile("../../lean/out/counterexamples.json")
	if err != nil {
		t.Skip("Leanの出力がありません（lean/ で lake exe hazards > out/counterexamples.json を実行してください）")
	}
	var ces []leanCounterexample
	if err := json.Unmarshal(data, &ces); err != nil {
		t.Fatal(err)
	}
	if len(ces) == 0 {
		t.Fatal("反例が0件です。Leanの出力を確認してください")
	}
	for _, ce := range ces {
		got := replay(t, Design(ce.Design), ce.Trace)
		if !slices.Contains(got, ce.Hazard) {
			t.Errorf("Leanの反例 %s/%s %v が実装で再現しない（got %v）。モデルと実装が乖離しています",
				ce.Design, ce.Hazard, ce.Trace, got)
		}
	}
}

func nonNil(xs []string) []string {
	if xs == nil {
		return []string{}
	}
	return xs
}
