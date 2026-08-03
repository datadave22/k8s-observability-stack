# k8s-observability-stack

A local Kubernetes observability stack: a Python Flask app that exposes
Prometheus metrics, scraped automatically via a `ServiceMonitor`, visualized
in a Grafana dashboard, with a custom alert rule watching error rate and
latency. Everything runs in a `kind` cluster and deploys with one command.

## Architecture

```
                 ┌─────────────────────────────────────────────┐
                 │              kind cluster (Docker)           │
                 │                                               │
                 │  ┌────────────────┐   scrape    ┌──────────┐ │
                 │  │ flask-metrics-  │◄────────────│Prometheus│ │
                 │  │ app (2 replicas)│  /metrics   │          │ │
                 │  └────────────────┘   ServiceMonitor└────┬───┘ │
                 │                                        │     │
                 │                                        ▼     │
                 │                                  ┌──────────┐ │
                 │                                  │ Grafana  │ │
                 │                                  └──────────┘ │
                 │                                        │     │
                 │                                        ▼     │
                 │                                 ┌─────────────┐│
                 │                                 │Alertmanager ││
                 │                                 └─────────────┘│
                 └─────────────────────────────────────────────┘
                    ▲                    ▲                ▲
              kubectl port-forward  kubectl port-forward  kubectl port-forward
                    │                    │                │
                 localhost:8080     localhost:3000    localhost:9090
                 (Flask app)          (Grafana)         (Prometheus)
```

- **Flask app** (`app/`) exposes `/`, `/work`, `/error`, `/healthz`, and
  `/metrics` (via `prometheus_client`). `/work` has randomized latency and a
  ~10% simulated failure rate so the dashboard has something to show.
- **kube-prometheus-stack** (Prometheus + Grafana + Alertmanager + operator)
  is installed via Helm into the `monitoring` namespace.
- **ServiceMonitor** (`k8s/servicemonitor.yaml`) tells Prometheus to scrape
  the Flask app's `/metrics` endpoint every 15s — no manual scrape config.
- **PrometheusRule** (`prometheus/alerts.yaml`) defines two alerts:
  `FlaskHighErrorRate` (5xx rate > 5% for 2m) and `FlaskHighRequestLatency`
  (p95 latency > 1s for 5m).
- **Grafana dashboard** (`grafana/dashboards/app-dashboard.json`) is
  auto-provisioned into Grafana via the chart's dashboard sidecar, and can
  also be imported manually.

## Prerequisites

- Docker (Desktop on Mac, Engine on Linux), running
- `kubectl`
- `kind`
- `helm`

`make up` checks for all of these first and prints install instructions for
whatever's missing, rather than assuming they're present.

## Quickstart

```bash
make up
```

This will:
1. Run a preflight check for docker/kind/kubectl/helm
2. Create a kind cluster (`observability-demo`)
3. Install kube-prometheus-stack via Helm into the `monitoring` namespace
4. Build the Flask app image and load it into the kind cluster
5. Deploy the app, its Service, and the ServiceMonitor
6. Provision the Grafana dashboard and apply the alert rules
7. Wait for everything to be ready

Then, in separate terminals:

```bash
make grafana        # http://localhost:3000  (user: admin / pass: admin)
make prometheus-ui  # http://localhost:9090
make app            # http://localhost:8080
```

Generate some traffic so the dashboard has real data to plot:

```bash
make traffic
```

Tear everything down:

```bash
make down
```

## Viewing the dashboard

The dashboard (`Flask Metrics App - Overview`) is loaded into Grafana
automatically — no manual import needed. If you want to import it into a
different Grafana instance, it's a plain dashboard JSON file:

1. Grafana → Dashboards → New → Import
2. Upload `grafana/dashboards/app-dashboard.json`
3. Select your Prometheus datasource when prompted

Panels: request rate by endpoint, 5xx error rate, p50/p95/p99 latency,
in-progress requests, request count, and pod up/down.

## Alert rules

Defined in `prometheus/alerts.yaml`, viewable in Prometheus under
**Alerts**, or in Grafana under **Alerting → Alert rules**:

- `FlaskHighErrorRate` — fires when 5xx responses exceed 5% of traffic over
  5 minutes, sustained for 2 minutes.
- `FlaskHighRequestLatency` — fires when p95 request latency exceeds 1s,
  sustained for 5 minutes.

Trigger `FlaskHighErrorRate` on demand by hitting the `/error` endpoint
repeatedly, e.g. `for i in {1..50}; do curl localhost:8080/error; done`
(with `make app` running in another terminal).

## Project structure

```
k8s-observability-stack/
├── Makefile                       # make up / down / grafana / traffic / ...
├── app/                           # Flask app + Dockerfile
├── kind/kind-config.yaml          # local cluster definition
├── k8s/                           # namespace, deployment, service, ServiceMonitor
├── prometheus/                    # kube-prometheus-stack Helm values + alert rules
├── grafana/dashboards/            # dashboard JSON (importable)
├── scripts/                       # preflight check, traffic generator
└── screenshots/                   # dashboard screenshots (see below)
```

## Screenshots

_TODO: add screenshots after running `make up` + `make traffic`._

- `screenshots/grafana-dashboard.png` — Grafana dashboard with live traffic
- `screenshots/prometheus-targets.png` — Prometheus Targets page showing
  the Flask app scrape target as UP
- `screenshots/prometheus-alerts.png` — Prometheus Alerts page

## Troubleshooting

- **`make up` hangs on `kubectl wait`**: check pod status with `make status`
  and `kubectl describe pod -n flask-app <pod>`. On first run, Helm has to
  pull several images, which can take a few minutes on a slow connection.
- **`ImagePullBackOff` on the Flask app**: the image is built locally and
  loaded into kind (`imagePullPolicy: Never`) — if you see this, re-run
  `make build load`.
- **Grafana shows "No data"**: run `make traffic` to generate requests, and
  confirm the target is up under Prometheus → Status → Targets.
- **Port already in use**: change `GRAFANA_LOCAL_PORT` / `APP_LOCAL_PORT` /
  `PROMETHEUS_LOCAL_PORT`, e.g. `make grafana GRAFANA_LOCAL_PORT=3001`.

## What this demonstrates

- Deploying a full observability stack (Prometheus, Grafana, Alertmanager)
  via Helm with production-shaped values (resource limits, retention,
  cluster-wide `ServiceMonitor`/`PrometheusRule` discovery)
- Instrumenting an application with custom Prometheus metrics
  (`Counter`, `Histogram`, `Gauge`) via `prometheus_client`
- Automatic service discovery via `ServiceMonitor`, no manual scrape config
- Writing PromQL-based alert rules for error rate and latency SLOs
- Building a Grafana dashboard from PromQL queries
- Wrapping the whole workflow behind a single reproducible `make up`
