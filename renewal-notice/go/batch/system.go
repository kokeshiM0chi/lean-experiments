// Package batch は有料会員への退会案内通知を行う4つのバッチを実装する。
//
// この実装は lean/RenewalNotice/Model.lean の形式モデルと1対1に対応している。
// 型・関数名の対応はコメントの「Lean:」で示す。
package batch

import (
	"errors"
	"slices"
	"sync"
)

type User = int

// JobResult はスケジューラーから見えるジョブの終了状態。Lean: JobResult
type JobResult string

const (
	NotRun JobResult = "notRun"
	OK     JobResult = "ok"
	Failed JobResult = "failed"
)

// Design は設計方式を表す。Lean: Design
//   - Naive: 各バッチは単体仕様どおりに動くが、バッチ間の前提を確認しない
//   - Safe:  STPAで導いた安全制約を実装したもの（鮮度チェック・送信済み参照・送信時再確認）
type Design string

const (
	Naive Design = "naive"
	Safe  Design = "safe"
)

// World は制御対象プロセスの「真の状態」。コントローラー（バッチ）は直接は見えず、
// 利用ログや契約DBなどのソースを通してしか知ることができない。Lean: World
type World struct {
	Users    []User `json:"users"`
	Inactive []User `json:"inactive"` // 現在本当に非アクティブなユーザー
	Renewing []User `json:"renewing"` // 翌月に本当に更新を迎えるユーザー
	LogOK    bool   `json:"logOk"`    // 利用ログのソースが健全か（false = テーブル名変更等で空を返す）
}

// IsTarget は真の通知対象かどうかを返す。Lean: World.isTarget
func (w World) IsTarget(u User) bool {
	return slices.Contains(w.Inactive, u) && slices.Contains(w.Renewing, u)
}

// inactiveLog はバッチAが読む利用ログソース。Lean: World.inactiveLog
func (w World) inactiveLog() []User {
	if w.LogOK {
		return w.Inactive
	}
	return nil
}

// Table は抽出結果テーブル。コントローラーのプロセスモデル（世界に対する認識）にあたる。Lean: Table
type Table struct {
	AsOf int    `json:"asOf"`
	Rows []User `json:"rows"`
}

// SentRecord は配信基盤が受理した通知1件。WasTarget は送信した時点で本当に対象者だったか
// （観測者視点の真値で、バッチ自身は知らない）。Lean: State.sent の要素
type SentRecord struct {
	User      User `json:"user"`
	WasTarget bool `json:"wasTarget"`
}

// System はアプリ全体の状態。Lean: State
type System struct {
	mu     sync.Mutex
	Design Design       `json:"design"`
	Today  int          `json:"today"`
	World  World        `json:"world"`
	TA     Table        `json:"tableA"`
	TB     Table        `json:"tableB"`
	TC     Table        `json:"tableC"`
	Sent   []SentRecord `json:"sent"`
	RA     JobResult    `json:"resultA"`
	RB     JobResult    `json:"resultB"`
	RC     JobResult    `json:"resultC"`
	RD     JobResult    `json:"resultD"`
}

// NewSystem は Lean の init と同じ初期状態を作る。
// 前回サイクル（day 0）の抽出結果が残っている状態から、今日（day 1）のサイクルを始める。
func NewSystem(d Design) *System {
	return &System{
		Design: d,
		Today:  1,
		World:  World{Users: []User{0, 1, 2}, Inactive: []User{1, 2}, Renewing: []User{1, 2}, LogOK: true},
		TA:     Table{AsOf: 0, Rows: []User{0, 1}},
		TB:     Table{AsOf: 0, Rows: []User{0}},
		TC:     Table{AsOf: 0, Rows: []User{0}},
		Sent:   []SentRecord{},
		RA:     NotRun, RB: NotRun, RC: NotRun, RD: NotRun,
	}
}

func filter(xs []User, keep func(User) bool) []User {
	out := []User{}
	for _, x := range xs {
		if keep(x) {
			out = append(out, x)
		}
	}
	return out
}

// BatchA は非アクティブユーザーを抽出する。Lean: batchA
func (s *System) BatchA() {
	s.mu.Lock()
	defer s.mu.Unlock()
	src := s.World.inactiveLog()
	s.TA = Table{AsOf: s.Today, Rows: filter(s.World.Users, func(u User) bool { return slices.Contains(src, u) })}
	s.RA = OK
}

// BatchB は翌月更新の有料会員を抽出する。Lean: batchB
func (s *System) BatchB() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.TB = Table{AsOf: s.Today, Rows: filter(s.World.Users, func(u User) bool { return slices.Contains(s.World.Renewing, u) })}
	s.RB = OK
}

// BatchC は A ∩ B を通知対象として確定する。Lean: batchC
func (s *System) BatchC() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.Design == Safe && (s.TA.AsOf != s.Today || s.TB.AsOf != s.Today) {
		s.RC = Failed
		return errors.New("batchC: 入力テーブルが今日の基準日時ではない")
	}
	// Naive では入力の鮮度を確認せずに AsOf=Today を付ける。
	// プロセスモデルが現実とずれる原因になる。
	s.TC = Table{AsOf: s.Today, Rows: filter(s.TA.Rows, func(u User) bool { return slices.Contains(s.TB.Rows, u) })}
	s.RC = OK
	return nil
}

func (s *System) sentUsers() []User {
	us := make([]User, len(s.Sent))
	for i, r := range s.Sent {
		us[i] = r.User
	}
	return us
}

// ErrCrash は配信の途中で異常終了したことを表す（タイムアウトなど）。
var ErrCrash = errors.New("batchD: 配信途中で異常終了")

// BatchD はプッシュ通知を送る。crashAfter が nil でなければ、その件数だけ送ったところで異常終了する。
// Lean: batchD / batchDNaive / batchDSafe
func (s *System) BatchD(crashAfter *int) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	targets := s.TC.Rows
	if s.Design == Safe {
		if s.TC.AsOf != s.Today {
			s.RD = Failed
			return errors.New("batchD: 通知対象テーブルが古い")
		}
		// フィードバック: 配信基盤の受理記録を参照し、送信済みは除外する（結果不明でも再送しない）。
		// 送信時再確認: 送る直前に真のソースで対象者かを確認する（TOCTOU対策）。
		sent := s.sentUsers()
		targets = filter(targets, func(u User) bool { return !slices.Contains(sent, u) && s.World.IsTarget(u) })
	}
	if crashAfter != nil && *crashAfter < len(targets) {
		targets = targets[:*crashAfter]
	}
	for _, u := range targets {
		s.Sent = append(s.Sent, SentRecord{User: u, WasTarget: s.World.IsTarget(u)})
	}
	if crashAfter != nil {
		s.RD = Failed
		return ErrCrash
	}
	s.RD = OK
	return nil
}

// Use はユーザーが利用を再開する外乱。Lean: Action.use
func (s *System) Use(u User) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.World.Inactive = filter(s.World.Inactive, func(x User) bool { return x != u })
}

// BreakSource は利用ログソースの故障（テーブル名変更などで0件を返す）。Lean: Action.breakSource
func (s *System) BreakSource() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.World.LogOK = false
}
