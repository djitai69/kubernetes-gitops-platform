# Monitoring, logging, and alerting

## Application metrics

`GET /metrics` on a **dedicated port (9000)**, separate from the
application port (8000) — see `app/node_api/metrics.py` and
`docs/networking.md` for why this is a separate port rather than a path on
the public listener (NetworkPolicy can't filter by HTTP path, only by
port). Built with `prometheus-fastapi-instrumentator` plus a custom
counter for Kubernetes API failures observed by `/nodes`. Exposed via a
Helm-chart-gated `ServiceMonitor`
(`serviceMonitor.enabled`, default `false`) so the core demo never depends
on Prometheus Operator CRDs being installed — see `make demo` vs.
`make demo-observability` in the README.

Metrics: HTTP request count, status code, latency histogram, in-progress
requests, and `node_api_kubernetes_api_failures_total{reason=...}`.

## Kubernetes workload monitoring

`kube-prometheus-stack` (Prometheus, Alertmanager, Grafana,
kube-state-metrics) — installed only by `make demo-observability`, not the
core demo, and only as a **documented production-suitable approach** per
the assignment; the working minimum is the `/metrics` endpoint and gated
`ServiceMonitor` above.

## Cluster-level monitoring (AWS)

- EKS control-plane logs (api, audit, authenticator, controllerManager,
  scheduler) to CloudWatch Logs — enabled in
  `infra/modules/eks/main.tf`.
- ALB metrics and CloudTrail via CloudWatch.
- AWS infrastructure metrics (CloudWatch).

## Centralized logging

- The application emits structured JSON logs to stdout/stderr (see
  `app/node_api/logging_setup.py`): `timestamp`, `level`, `message`,
  `request_id`, `path`, `status_code`, `environment`, `latency_ms`. Secrets,
  tokens, Authorization headers, and stack traces are never logged.
- Fluent Bit (AWS production target) forwards container logs to CloudWatch
  Logs with an environment-appropriate retention policy (shorter in dev,
  longer in production).
- `jq` is useful locally for filtering JSON logs; not required inside the
  container.

## Alerting

Documented rules (`gitops/infrastructure/local/kube-prometheus-stack/alert-rules.yaml`,
applied as part of `make demo-observability`):

- `NodeApiHighErrorRate` — 5xx rate > 5% over 5m.
- `NodeApiHighCpu` — CPU usage > 90% of requests for 10m.
- `NodeApiDeploymentUnavailable` — zero available replicas for 5m.
- `NodeApiCrashLooping` — > 3 restarts in 15m.
- `NodeApiHpaAtMaxReplicas` — HPA pinned at `maxReplicas` for 10m while
  still above target CPU.
- `FluxKustomizationFailed` / `FluxHelmReleaseFailed` — Flux reconciliation
  failures, using the `gotk_reconcile_condition` metric Flux's
  controllers expose natively.

Notification routing:
- Application/Kubernetes alerts: Prometheus → Alertmanager → Slack.
- Flux reconciliation failures: Flux's own `notification-controller` →
  Slack (`gitops/clusters/local/flux-system/alert-provider.yaml` +
  `alert.yaml`) — a second, independent path from Alertmanager, so a
  broken Prometheus stack doesn't also silence Flux failure alerts.
- AWS infrastructure alarms: CloudWatch Alarm → SNS → Slack/chat
  integration.

Slack webhook credentials are always stored in a Kubernetes `Secret` (see
`slack-webhook` in `scripts/bootstrap-local.sh`), never committed to Git.

## Incident investigation: `/nodes` returning 503

1. Check application logs and classify the failure (structured JSON, one
   line per request).
2. Check pod status, readiness, restart count, and node placement.
3. Test Kubernetes API access from the pod directly (see
   `scripts/test-network-policies.sh` check #4 for the exact command).
4. Verify ServiceAccount, ClusterRole, and ClusterRoleBinding.
5. Check NetworkPolicy and DNS.
6. Check Kubernetes events (`kubectl get events`).
7. Check Flux and HelmRelease status for a recent failed change
   (`flux get kustomizations -A`, `flux get helmreleases -A`).
8. Check EKS API/control-plane health if evidence points to a cluster-wide
   issue (multiple unrelated workloads affected).

Failure-code interpretation baked into this runbook:

| Symptom               | Likely cause                                   |
|------------------------|-------------------------------------------------|
| 403 Forbidden           | RBAC or identity issue                          |
| Timeout                 | NetworkPolicy, routing, or API reachability     |
| DNS error                | CoreDNS or DNS egress                           |
| TLS/token error          | ServiceAccount token, CA bundle, client config  |
| Multiple workloads affected | Possible EKS control-plane issue            |
