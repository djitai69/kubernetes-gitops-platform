.PHONY: demo demo-observability test teardown lint app-test helm-lint kyverno-test cloud-up cloud-down cloud-down-full cloud-status

demo:
	./scripts/bootstrap-local.sh

demo-observability:
	kubectl apply -f gitops/clusters/local/flux-system/kustomization-observability.yaml
	kubectl -n flux-system wait kustomization/observability --for=condition=Ready --timeout=10m
	kubectl -n monitoring rollout status deployment/monitoring-kube-prometheus-operator --timeout=180s
	@echo "Enabling ServiceMonitor for the demo (patches live HelmReleases, then suspends them so Flux doesn't revert the override; Git itself still says disabled)"
	@for ns in node-api-dev node-api-staging node-api-production; do \
		kubectl -n $$ns patch helmrelease node-api --type merge -p '{"spec":{"values":{"serviceMonitor":{"enabled":true}}}}'; \
		.tools/flux reconcile helmrelease node-api -n $$ns --timeout=2m; \
		.tools/flux suspend helmrelease node-api -n $$ns; \
	done
	@echo "kube-prometheus-stack installed. Port-forward Grafana with:"
	@echo "  kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80"
	@echo "Run 'make demo' again to tear down and rebuild from the committed Git state (also resumes reconciliation)."

test: app-test helm-lint kyverno-test

app-test:
	cd app && .venv/bin/python -m pytest tests/ -v
	cd app && .venv/bin/ruff check node_api tests

helm-lint:
	helm lint helm/node-api
	helm lint helm/node-api -f helm/node-api/values-dev.yaml
	helm lint helm/node-api -f helm/node-api/values-staging.yaml
	helm lint helm/node-api -f helm/node-api/values-production.yaml
	helm lint helm/node-api -f helm/node-api/values-local.yaml

kyverno-test:
	.tools/kyverno test policies/kyverno/tests/pod-security/

teardown:
	./scripts/teardown-local.sh

# --- Real AWS (costs money while it exists) ---------------------------------

cloud-up:
	./scripts/cloud-up.sh

cloud-down:
	./scripts/cloud-down.sh

cloud-down-full:
	./scripts/cloud-down.sh --with-bootstrap

cloud-status:
	@if [ ! -f infra/live/.state-bucket-nonprod ]; then \
		echo "No cloud environment found (infra/live/.state-bucket-nonprod missing)."; \
	else \
		cd infra/live/nonprod && \
		terraform init -input=false -backend-config="bucket=$$(cat ../.state-bucket-nonprod)" -reconfigure >/dev/null && \
		terraform output; \
		.tools/flux get kustomizations -A 2>/dev/null || echo "(flux not reachable — check kubeconfig)"; \
	fi
