# Kubernetes GitOps Platform — node-api

A reference implementation of a Kubernetes GitOps delivery platform: a
small FastAPI service, deployed via Helm + Flux, with RBAC, NetworkPolicy,
Kyverno policy-as-code, External Secrets Operator, and a CI/CD pipeline
that never talks to the cluster directly.

Built for a DevOps take-home assignment. See `docs/` for the full design
rationale, and `kubernetes_gitops_consolidated_final_decisions.txt` (repo
root's sibling, outside this repo) for the complete locked-decisions log
this implementation follows.

## Quick start

```bash
git clone <this-repo>
cd kubernetes-gitops-platform
make demo
```

That's it — no AWS account required. `make demo`:

1. Builds the `node-api` image locally.
2. Creates a kind cluster with Calico as the CNI (kindnet does not enforce
   `NetworkPolicy` — see `docs/networking.md`).
3. Installs Flux (imperative bootstrap step — Flux can't deploy itself).
4. Stands up a local Gitea server as a stand-in Git source (see
   *"Why a local git server?"* below) and pushes this repo to it.
5. Lets Flux take over: ingress-nginx, Kyverno, metrics-server, External
   Secrets Operator, Reloader, then `node-api` in three namespaces
   (`node-api-dev`, `node-api-staging`, `node-api-production`).
6. Runs `scripts/test-network-policies.sh` to prove NetworkPolicy is
   actually enforced, not just applied.
7. Smoke-tests `/health` and `/nodes` (with and without a bearer token)
   through ingress-nginx.

```bash
make test               # unit tests, ruff, helm lint (all envs), kyverno test
make demo-observability # adds kube-prometheus-stack + enables ServiceMonitor
make teardown           # deletes the kind cluster and the local git server
```

## Resource requirements

- Docker: 6GB memory minimum, 8GB+ recommended; 4 CPUs recommended.
- 10GB free disk.
- Host ports 80 and 443 must be free (kind maps them for ingress-nginx).
- Expect **5–10 minutes** for the core demo, another 5–10 for
  `make demo-observability`.
- Required on PATH: `docker`, `kind`, `kubectl`, `helm`, `make`, `curl`,
  `jq`, `git`. `flux` and `kyverno` CLIs are vendored into `.tools/` by
  the setup — no separate install needed.

## Why a local git server?

Flux needs a real Git remote to reconcile from. The documented,
production-shaped source is a published GitHub repository
(`gitops/clusters/local/flux-system/gitrepository.yaml`) — but pushing to
a real GitHub repo under a specific account is a user-facing action this
automation deliberately doesn't take on its own. Instead, `make demo`
stands up a throwaway [Gitea](https://about.gitea.com/) container (Flux's
git client only speaks the smart HTTP protocol, so a plain static
file server won't work) and pushes a snapshot there. This is a real Flux
reconciliation loop, not a simulation — only the git *host* differs from
production. Full reasoning in `docs/gitops.md`.

**To use a real GitHub repo instead:** push this repository, replace
`REPLACE_WITH_OWNER` in the YAML files under `gitops/` and `infra/`, and
update `gitops/clusters/local/flux-system/gitrepository.yaml`'s
`spec.url`. The bootstrap script's Gitea step becomes unnecessary at that
point.

## Repository layout

See `docs/gitops.md#repository-layout`.

## Documentation index

| Topic | File |
|---|---|
| GitOps model, Flux graph, promotion flow | `docs/gitops.md` |
| RBAC | `docs/rbac.md` |
| Secrets management (extra credit) | `docs/secrets.md` |
| Policy-as-code (Kyverno) | `docs/policy.md` |
| Networking, ingress, DNS, TLS, encryption | `docs/networking.md` |
| Monitoring, logging, alerting | `docs/monitoring.md` |
| Cost considerations | `docs/cost.md` |
| Backup and disaster recovery | `docs/disaster-recovery.md` |
| Local architecture diagram | `docs/architecture-local.md` |
| AWS production architecture diagram | `docs/architecture-aws.md` |
| Assumptions, trade-offs, known limitations | `docs/assumptions-and-limitations.md` |
| Production recommendations | `docs/production-recommendations.md` |
| Interview presentation flow | `docs/interview-presentation.md` |

## Application

FastAPI service exposing:

- `GET /health` — minimal public status.
- `GET /health/live` — liveness (process alive).
- `GET /health/ready` — readiness (startup + init complete; a Kubernetes
  API outage does **not** flip this to unready).
- `GET /nodes` — lists cluster nodes, marks the current one (via the
  Downward API's `spec.nodeName`), requires a bearer token, returns a
  controlled `503` if the Kubernetes API is temporarily unreachable.
- `GET /metrics` — Prometheus metrics, on a **separate port (9000)** from
  the application port (8000) so NetworkPolicy can restrict scraping to
  the monitoring namespace.

Run locally without Kubernetes:

```bash
cd app
python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt
API_TOKEN=dev-token .venv/bin/uvicorn node_api.main:app --reload
```

Run the test suite:

```bash
cd app && PYTHONPATH=. .venv/bin/python -m pytest tests/ -v
```

## Helm chart

`helm/node-api` — one reusable chart, environment differences are values
only (`values-dev.yaml`, `values-staging.yaml`, `values-production.yaml`,
`values-local.yaml`). See `docs/rbac.md`, `docs/policy.md`, and
`docs/networking.md` for what each template enforces.

## CI/CD

`.github/workflows/ci.yaml` — lint, test, dependency scan, Helm lint,
kube-linter, Kyverno CLI tests, build, Trivy image scan, push to GHCR,
update the dev GitOps reference. `.github/workflows/release.yaml` —
tag-triggered production promotion (digest copy, never rebuilds).
`.github/workflows/terraform.yaml` — `fmt`/`validate`/`plan` on PRs,
protected-environment `apply` on merge. Full flow in `docs/gitops.md`.

## Infrastructure

`infra/` — Terraform modules (VPC, EKS, ECR, IAM/IRSA, EKS addons,
Karpenter prerequisites) and two root configs (`infra/live/nonprod`,
`infra/live/production`). Validated with `terraform fmt -check` and
`terraform validate` against all three root configs (`bootstrap`,
`nonprod`, `production`); not applied against real AWS as part of this
submission. See `docs/cost.md` for why, and `docs/architecture-aws.md`
for the target design.

## Presenting this submission

See `docs/interview-presentation.md` — a timed walkthrough (~20 min)
mapped to the assignment's evaluation weights, with a live-demo fallback
plan, prepared talking points on the AI-assisted build process, and
anticipated hard questions with one-liners.
