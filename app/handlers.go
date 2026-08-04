package main

import (
	"encoding/json"
	"math/rand"
	"net/http"
	"time"
)

func writeJSON(w http.ResponseWriter, status int, payload map[string]string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	// Encoding errors here would mean the response is already partially
	// written; there's nothing meaningful left to do but let it drop, same
	// as the standard library's own json handlers.
	_ = json.NewEncoder(w).Encode(payload)
}

func indexHandler(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{
		"message": "hello from go-metrics-app",
		"status":  "ok",
	})
}

// workHandler simulates variable-latency work (50-500ms) with a ~10%
// failure rate, giving the dashboard and error-rate alert something real
// to react to - mirrors the original Flask /work endpoint's behavior.
func workHandler(w http.ResponseWriter, r *http.Request) {
	latency := time.Duration(50+rand.Intn(451)) * time.Millisecond
	time.Sleep(latency)

	if rand.Intn(10) == 0 {
		writeJSON(w, http.StatusInternalServerError, map[string]string{
			"error": "simulated failure",
		})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{
		"message": "work complete",
	})
}

func errorHandler(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusInternalServerError, map[string]string{
		"error": "forced failure",
	})
}

func healthzHandler(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{
		"status": "healthy",
	})
}
