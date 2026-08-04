package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// healthz is intentionally excluded from the request_count/error_count/
// request_duration_seconds instrumentation, same as /metrics - kubelet's
// own liveness/readiness probe traffic shouldn't skew the app's request
// and error rate.
func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("/", instrument("/", indexHandler))
	mux.HandleFunc("/work", instrument("/work", workHandler))
	mux.HandleFunc("/error", instrument("/error", errorHandler))
	mux.HandleFunc("/healthz", healthzHandler)
	mux.Handle("/metrics", promhttp.Handler())

	srv := &http.Server{
		Addr:         ":5000",
		Handler:      mux,
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	// Kubernetes sends SIGTERM on pod termination and waits out
	// terminationGracePeriodSeconds before SIGKILL - handling it lets
	// in-flight requests finish instead of being dropped mid-response.
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()

	go func() {
		log.Printf("go-metrics-app listening on %s", srv.Addr)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("server error: %v", err)
		}
	}()

	<-ctx.Done()
	log.Println("shutdown signal received, draining in-flight requests")

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Printf("graceful shutdown failed: %v", err)
		os.Exit(1)
	}
	log.Println("shutdown complete")
}
