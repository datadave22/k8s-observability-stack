CLUSTER_NAME          ?= observability-demo
APP_NAMESPACE         ?= go-metrics-app
MONITORING_NAMESPACE  ?= monitoring
HELM_RELEASE          ?= kube-prometheus-stack
IMAGE                 ?= go-metrics-app:local
GRAFANA_LOCAL_PORT    ?= 3000
PROMETHEUS_LOCAL_PORT ?= 9090
APP_LOCAL_PORT        ?= 8080
TRAFFIC_DURATION      ?= 120

.PHONY: up down preflight cluster monitoring build load deploy dashboard alerts \
        wait grafana prometheus-ui app traffic status logs clean

up: preflight cluster monitoring build load deploy dashboard alerts wait
	@echo ""
	@echo "Stack is up."
	@echo "  make grafana         # http://localhost:$(GRAFANA_LOCAL_PORT)  (admin/admin)"
	@echo "  make prometheus-ui   # http://localhost:$(PROMETHEUS_LOCAL_PORT)"
	@echo "  make app             # http://localhost:$(APP_LOCAL_PORT)"
	@echo "  make traffic         # generate sample traffic for the dashboard"

preflight:
	@bash scripts/preflight.sh

cluster:
	@if kind get clusters 2>/dev/null | grep -qx "$(CLUSTER_NAME)"; then \
		echo "kind cluster '$(CLUSTER_NAME)' already exists, skipping create"; \
	else \
		kind create cluster --name $(CLUSTER_NAME) --config kind/kind-config.yaml; \
	fi

monitoring:
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
	helm repo update >/dev/null
	kubectl create namespace $(MONITORING_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	helm upgrade --install $(HELM_RELEASE) prometheus-community/kube-prometheus-stack \
		--namespace $(MONITORING_NAMESPACE) \
		-f prometheus/values.yaml \
		--wait --timeout 5m

build:
	docker build -t $(IMAGE) app/

load:
	kind load docker-image $(IMAGE) --name $(CLUSTER_NAME)

deploy:
	kubectl apply -f k8s/namespace.yaml
	kubectl apply -f k8s/deployment.yaml
	kubectl apply -f k8s/service.yaml
	kubectl apply -f k8s/servicemonitor.yaml
	kubectl rollout status deployment/go-metrics-app -n $(APP_NAMESPACE) --timeout=120s

dashboard:
	kubectl create configmap go-metrics-app-dashboard \
		--from-file=app-dashboard.json=grafana/dashboards/app-dashboard.json \
		-n $(MONITORING_NAMESPACE) \
		--dry-run=client -o yaml | kubectl apply -f -
	kubectl label configmap go-metrics-app-dashboard -n $(MONITORING_NAMESPACE) grafana_dashboard=1 --overwrite

alerts:
	kubectl apply -f prometheus/alerts.yaml

wait:
	kubectl wait --for=condition=Ready pods --all -n $(APP_NAMESPACE) --timeout=120s

grafana:
	@echo "Grafana:    http://localhost:$(GRAFANA_LOCAL_PORT)  (user: admin / pass: admin)"
	@GRAFANA_SVC=$$(kubectl get svc -n $(MONITORING_NAMESPACE) -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}'); \
	kubectl port-forward -n $(MONITORING_NAMESPACE) svc/$$GRAFANA_SVC $(GRAFANA_LOCAL_PORT):80

prometheus-ui:
	@echo "Prometheus: http://localhost:$(PROMETHEUS_LOCAL_PORT)"
	kubectl port-forward -n $(MONITORING_NAMESPACE) svc/prometheus-operated $(PROMETHEUS_LOCAL_PORT):9090

app:
	@echo "Go app:     http://localhost:$(APP_LOCAL_PORT)"
	kubectl port-forward -n $(APP_NAMESPACE) svc/go-metrics-app $(APP_LOCAL_PORT):80

traffic:
	APP_NAMESPACE=$(APP_NAMESPACE) LOCAL_PORT=$(APP_LOCAL_PORT) DURATION=$(TRAFFIC_DURATION) bash scripts/generate-traffic.sh

status:
	kubectl get pods -n $(APP_NAMESPACE) -o wide
	kubectl get pods -n $(MONITORING_NAMESPACE) -o wide

logs:
	kubectl logs -n $(APP_NAMESPACE) -l app=go-metrics-app -f --tail=100

down:
	kind delete cluster --name $(CLUSTER_NAME)

clean: down
