// 退会案内通知バッチを HTTP から操作できるようにした webapp。
// スケジューラーの代わりに、各ジョブや外乱をHTTPで1件ずつ実行できる。
//
//	POST /reset?design=naive|safe
//	POST /jobs/{A|B|C|D}            D は ?crashAfter=k で途中異常終了
//	POST /events/use?user=1         ユーザーが利用を再開
//	POST /events/break-source       利用ログソースの故障
//	GET  /state                     状態と成立中のハザード
package main

import (
	"encoding/json"
	"log"
	"net/http"
	"strconv"
	"sync"

	"batchnotify/batch"
)

type server struct {
	mu  sync.Mutex
	sys *batch.System
}

func (sv *server) current() *batch.System {
	sv.mu.Lock()
	defer sv.mu.Unlock()
	return sv.sys
}

func (sv *server) writeState(w http.ResponseWriter, jobErr error) {
	s := sv.current()
	resp := map[string]any{"hazards": s.Hazards(), "state": s}
	if jobErr != nil {
		resp["jobError"] = jobErr.Error()
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(resp)
}

func main() {
	sv := &server{sys: batch.NewSystem(batch.Naive)}
	mux := http.NewServeMux()

	mux.HandleFunc("POST /reset", func(w http.ResponseWriter, r *http.Request) {
		d := batch.Design(r.URL.Query().Get("design"))
		if d != batch.Safe {
			d = batch.Naive
		}
		sv.mu.Lock()
		sv.sys = batch.NewSystem(d)
		sv.mu.Unlock()
		sv.writeState(w, nil)
	})

	mux.HandleFunc("POST /jobs/{name}", func(w http.ResponseWriter, r *http.Request) {
		s := sv.current()
		var err error
		switch r.PathValue("name") {
		case "A":
			s.BatchA()
		case "B":
			s.BatchB()
		case "C":
			err = s.BatchC()
		case "D":
			var crash *int
			if v := r.URL.Query().Get("crashAfter"); v != "" {
				k, perr := strconv.Atoi(v)
				if perr != nil {
					http.Error(w, "crashAfter must be int", http.StatusBadRequest)
					return
				}
				crash = &k
			}
			err = s.BatchD(crash)
		default:
			http.NotFound(w, r)
			return
		}
		sv.writeState(w, err)
	})

	mux.HandleFunc("POST /events/use", func(w http.ResponseWriter, r *http.Request) {
		u, err := strconv.Atoi(r.URL.Query().Get("user"))
		if err != nil {
			http.Error(w, "user must be int", http.StatusBadRequest)
			return
		}
		sv.current().Use(u)
		sv.writeState(w, nil)
	})

	mux.HandleFunc("POST /events/break-source", func(w http.ResponseWriter, r *http.Request) {
		sv.current().BreakSource()
		sv.writeState(w, nil)
	})

	mux.HandleFunc("GET /state", func(w http.ResponseWriter, r *http.Request) {
		sv.writeState(w, nil)
	})

	log.Println("listening on :8080")
	log.Fatal(http.ListenAndServe(":8080", mux))
}
