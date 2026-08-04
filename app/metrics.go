package main

import (
	"net/http"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

var (
	requestCount = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "request_count",
		Help: "Total number of HTTP requests processed, by method and endpoint",
	}, []string{"method", "endpoint"})

	errorCount = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "error_count",
		Help: "Total number of HTTP requests that resulted in a 5xx response",
	}, []string{"method", "endpoint"})

	// Default client_golang buckets (5ms-10s) are kept explicit here rather
	// than implied, since they directly determine histogram_quantile()
	// accuracy in the alert rules and dashboard - changing them changes
	// those queries' meaning.
	requestDuration = promauto.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "request_duration_seconds",
		Help:    "HTTP request latency in seconds",
		Buckets: []float64{0.005, 0.01, 0.025, 0.05, 0.075, 0.1, 0.25, 0.5, 0.75, 1, 2.5, 5, 10},
	}, []string{"endpoint"})

	requestsInProgress = promauto.NewGauge(prometheus.GaugeOpts{
		Name: "requests_in_progress",
		Help: "Number of HTTP requests currently being processed",
	})
)

// statusRecorder wraps http.ResponseWriter to capture the status code a
// handler wrote, since the standard library doesn't expose it after the
// fact and error_count needs to know whether a request resulted in a 5xx.
type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}

// instrument wraps a handler with the four metrics above. endpoint is
// passed explicitly (rather than derived from the request) so metric
// cardinality stays fixed regardless of how routes are registered.
func instrument(endpoint string, next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		requestsInProgress.Inc()
		defer requestsInProgress.Dec()

		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		start := time.Now()

		next(rec, r)

		requestDuration.WithLabelValues(endpoint).Observe(time.Since(start).Seconds())
		requestCount.WithLabelValues(r.Method, endpoint).Inc()
		if rec.status >= 500 {
			errorCount.WithLabelValues(r.Method, endpoint).Inc()
		}
	}
}
