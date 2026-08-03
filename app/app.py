import random
import time

from flask import Flask, Response, request
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    Counter,
    Gauge,
    Histogram,
    generate_latest,
)

app = Flask(__name__)

REQUEST_COUNT = Counter(
    "flask_http_request_total",
    "Total HTTP requests processed",
    ["method", "endpoint", "http_status"],
)
REQUEST_LATENCY = Histogram(
    "flask_http_request_duration_seconds",
    "HTTP request latency in seconds",
    ["endpoint"],
)
IN_PROGRESS = Gauge(
    "flask_http_requests_in_progress",
    "Number of HTTP requests currently in progress",
)

# /metrics itself is excluded so Prometheus's own scrapes don't skew the
# app's request-rate and error-rate numbers.
TRACKED_ENDPOINTS = {"/", "/work", "/error"}


@app.before_request
def start_timer():
    if request.path in TRACKED_ENDPOINTS:
        IN_PROGRESS.inc()
        request.start_time = time.time()


@app.after_request
def record_metrics(response):
    if request.path in TRACKED_ENDPOINTS:
        duration = time.time() - getattr(request, "start_time", time.time())
        REQUEST_LATENCY.labels(endpoint=request.path).observe(duration)
        REQUEST_COUNT.labels(
            method=request.method,
            endpoint=request.path,
            http_status=response.status_code,
        ).inc()
        IN_PROGRESS.dec()
    return response


@app.route("/")
def index():
    return {"message": "hello from flask-metrics-app", "status": "ok"}


@app.route("/work")
def work():
    # Variable latency plus an occasional 500 gives the dashboard and the
    # error-rate alert something real to react to.
    time.sleep(random.uniform(0.05, 0.6))
    if random.random() < 0.1:
        return {"error": "simulated failure"}, 500
    return {"message": "work complete"}


@app.route("/error")
def error():
    return {"error": "forced failure"}, 500


@app.route("/healthz")
def healthz():
    return {"status": "healthy"}


@app.route("/metrics")
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
