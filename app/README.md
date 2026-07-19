# node-api

FastAPI service exposing health, node listing, and metrics endpoints. See
the repo root `README.md` for the full picture and `../docs/` for design
rationale.

## Endpoints

| Path | Port | Auth | Purpose |
|---|---|---|---|
| `GET /health` | 8000 | none | Minimal public status |
| `GET /health/live` | 8000 | none | Liveness probe |
| `GET /health/ready` | 8000 | none | Readiness probe |
| `GET /nodes` | 8000 | Bearer token | Lists cluster nodes, marks current node |
| `GET /metrics` | 9000 | none (NetworkPolicy-restricted) | Prometheus metrics |

## Local development

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements-dev.txt
API_TOKEN=dev-token NODE_NAME=local .venv/bin/uvicorn node_api.main:app --reload
```

Kubernetes API calls will fail outside a cluster — `/nodes` will return
`503` locally unless `~/.kube/config` points at a real cluster (the
fallback `config.load_kube_config()` path in `node_api/k8s.py` exists for
exactly this case; in-cluster ServiceAccount auth is the normal path).

## Tests

```bash
PYTHONPATH=. .venv/bin/python -m pytest tests/ -v
.venv/bin/ruff check node_api tests
```

## Configuration

All non-secret config comes from environment variables (see
`node_api/config.py`), sourced from a ConfigMap in Kubernetes:
`APP_ENV`, `LOG_LEVEL`, `KUBERNETES_REQUEST_TIMEOUT_SECONDS`,
`NODES_CACHE_TTL_SECONDS`, `METRICS_PORT`. `API_TOKEN` comes from a
Secret, never a ConfigMap — see `../docs/secrets.md`.
