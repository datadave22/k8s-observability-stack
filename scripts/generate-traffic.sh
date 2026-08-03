#!/usr/bin/env bash
# Generates sample traffic against the Flask app so the Grafana dashboard
# and alert rules have real data to show. Requires the cluster to be up.
set -euo pipefail

APP_NAMESPACE="${APP_NAMESPACE:-flask-app}"
SERVICE="${SERVICE:-flask-metrics-app}"
LOCAL_PORT="${LOCAL_PORT:-8080}"
DURATION="${DURATION:-120}"

kubectl -n "$APP_NAMESPACE" port-forward "svc/$SERVICE" "$LOCAL_PORT:80" \
  >/tmp/flask-metrics-app-traffic-port-forward.log 2>&1 &
PF_PID=$!
trap 'kill "$PF_PID" 2>/dev/null || true' EXIT

echo "Port-forwarding svc/$SERVICE to localhost:$LOCAL_PORT (pid $PF_PID)"
sleep 3

echo "Generating traffic for ${DURATION}s against http://localhost:${LOCAL_PORT} ..."
end=$((SECONDS + DURATION))
while [ "$SECONDS" -lt "$end" ]; do
  curl -s -o /dev/null "http://localhost:${LOCAL_PORT}/" || true
  curl -s -o /dev/null "http://localhost:${LOCAL_PORT}/work" || true
  if (( RANDOM % 5 == 0 )); then
    curl -s -o /dev/null "http://localhost:${LOCAL_PORT}/error" || true
  fi
  sleep 0.2
done

echo "Done. Check the Grafana dashboard for results."
