package batch

import (
	"fmt"
	"slices"
	"strconv"
	"strings"
)

// 安全制約（Safety Constraint）。それぞれの否定がハザードになる。Lean: Safety.lean

// SC1 は通知を送った時点で本当に対象者だった人にだけ送る、という制約。違反するとH1（L1: 不要な退会）になる。
func (s *System) SC1() bool {
	for _, r := range s.Sent {
		if !r.WasTarget {
			return false
		}
	}
	return true
}

// SC2 は同じユーザーに重複して送らない、という制約。違反するとH2（L2: 不信感）になる。
func (s *System) SC2() bool {
	seen := map[User]bool{}
	for _, r := range s.Sent {
		if seen[r.User] {
			return false
		}
		seen[r.User] = true
	}
	return true
}

func (s *System) allOK() bool {
	return s.RA == OK && s.RB == OK && s.RC == OK && s.RD == OK
}

// SC3 は、全ジョブが正常終了しているなら真の対象者全員に送られている、という制約。
// 違反するとH3（L3: 案内なしの更新）になる。監視上は正常に見えるサイレントな欠落。
func (s *System) SC3() bool {
	if !s.allOK() {
		return true
	}
	sent := s.sentUsers()
	for _, u := range s.World.Users {
		if s.World.IsTarget(u) && !slices.Contains(sent, u) {
			return false
		}
	}
	return true
}

// Hazards は現在の状態で成立しているハザードを返す。
func (s *System) Hazards() []string {
	s.mu.Lock()
	defer s.mu.Unlock()
	hs := []string{}
	if !s.SC1() {
		hs = append(hs, "H1")
	}
	if !s.SC2() {
		hs = append(hs, "H2")
	}
	if !s.SC3() {
		hs = append(hs, "H3")
	}
	return hs
}

// Apply は Lean 側の Action の文字列表現（Main.lean の actionStr）を1件実行する。
// Lean が見つけた反例トレースを実装上で再生するために使う。
func (s *System) Apply(action string) error {
	switch {
	case action == "A":
		s.BatchA()
	case action == "B":
		s.BatchB()
	case action == "C":
		_ = s.BatchC() // ジョブの失敗は状態（RC）に記録される
	case action == "D":
		_ = s.BatchD(nil)
	case strings.HasPrefix(action, "crashD:"):
		k, err := strconv.Atoi(strings.TrimPrefix(action, "crashD:"))
		if err != nil {
			return err
		}
		_ = s.BatchD(&k)
	case strings.HasPrefix(action, "use:"):
		u, err := strconv.Atoi(strings.TrimPrefix(action, "use:"))
		if err != nil {
			return err
		}
		s.Use(u)
	case action == "breakSource":
		s.BreakSource()
	default:
		return fmt.Errorf("unknown action %q", action)
	}
	return nil
}
