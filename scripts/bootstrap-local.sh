#!/usr/bin/env bash
# Bootstraps the local kind demo end to end. See docs/gitops.md for the
# rationale behind each step, especially the two documented exceptions to
# "Flux is the only deployment actor": the CNI (Calico) and Flux itself
# must be installed imperatively because nothing can run before a CNI
# exists, and Flux cannot deploy itself before it exists.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_DIR="$ROOT_DIR/.tools"
CLUSTER_NAME="node-api-demo"
GHCR_OWNER="${GHCR_OWNER:-local-demo}"
IMAGE_REPO="ghcr.io/${GHCR_OWNER}/node-api"
IMAGE_TAG="local"
GIT_SERVER_NAME="node-api-git-server"
GIT_SCRATCH_DIR="$(mktemp -d /tmp/node-api-gitops-demo.XXXXXX)"
# GIT_SOURCE=local (default): stands up a throwaway Gitea container and
# pushes a snapshot of the working tree, substituting REPLACE_WITH_OWNER
# with GHCR_OWNER on the fly — so the demo works fully offline, picks up
# uncommitted local edits, and always matches the image just built/loaded.
# GIT_SOURCE=github: skips Gitea entirely and points Flux straight at the
# committed gitops/clusters/local/flux-system/gitrepository.yaml URL (must
# already be pushed to that real, public repo). No substitution happens in
# this mode — the committed manifests are used as-is, so GHCR_OWNER here
# MUST match whatever owner is already baked into the committed YAML (i.e.
# the real GitHub username), or the built/loaded image tag won't match
# what the Deployment references and pods will sit in ImagePullBackOff.
GIT_SOURCE="${GIT_SOURCE:-local}"

export PATH="$TOOLS_DIR:$PATH"

log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$1"; }
fail() { printf '\n\033[1;31mERROR:\033[0m %s\n' "$1" >&2; exit 1; }

cleanup_scratch() { rm -rf "$GIT_SCRATCH_DIR"; }
trap cleanup_scratch EXIT

# ---------------------------------------------------------------------------
log "Preflight checks"

for cmd in docker kind kubectl helm curl jq git; do
  command -v "$cmd" >/dev/null 2>&1 || fail "required command '$cmd' not found on PATH"
done
[ -x "$TOOLS_DIR/flux" ] || fail "flux CLI not found at $TOOLS_DIR/flux"

docker info >/dev/null 2>&1 || fail "Docker daemon is not running"

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  log "kind cluster '$CLUSTER_NAME' already exists, deleting it for a clean run"
  kind delete cluster --name "$CLUSTER_NAME"
fi
docker rm -f "$GIT_SERVER_NAME" >/dev/null 2>&1 || true

for port in 80 443; do
  if command -v ss >/dev/null 2>&1 && ss -ltn "( sport = :$port )" | grep -q LISTEN; then
    fail "host port $port is already in use — stop whatever is listening on it and re-run"
  fi
done

# ---------------------------------------------------------------------------
log "Building and preparing the node-api image (${IMAGE_REPO}:${IMAGE_TAG})"

docker build -t "${IMAGE_REPO}:${IMAGE_TAG}" "$ROOT_DIR/app"

# ---------------------------------------------------------------------------
log "Creating kind cluster '$CLUSTER_NAME' (default CNI disabled)"

kind create cluster --name "$CLUSTER_NAME" --config "$ROOT_DIR/local/kind-config.yaml"
kubectl cluster-info --context "kind-${CLUSTER_NAME}"

DOCKER_NETWORK=$(docker network ls --filter "name=^kind$" --format '{{.Name}}')
[ -n "$DOCKER_NETWORK" ] || fail "could not find kind's docker network"

log "Loading the node-api image into kind (no registry pull required)"
kind load docker-image "${IMAGE_REPO}:${IMAGE_TAG}" --name "$CLUSTER_NAME"

# ---------------------------------------------------------------------------
log "Installing Calico (imperative bootstrap exception: no CNI, no pods)"

kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml

log "Waiting for Calico to become ready"
kubectl -n kube-system rollout status deployment/calico-kube-controllers --timeout=180s
kubectl -n kube-system rollout status daemonset/calico-node --timeout=180s

log "Waiting for CoreDNS and the API server"
kubectl -n kube-system rollout status deployment/coredns --timeout=120s
kubectl wait --for=condition=Ready nodes --all --timeout=120s

# ---------------------------------------------------------------------------
log "Installing Flux controllers (imperative bootstrap exception: Flux can't deploy itself)"

"$TOOLS_DIR/flux" install --namespace=flux-system
kubectl -n flux-system wait --for=condition=Available deployment --all --timeout=180s

# Placeholder Slack webhook so the notification-controller Provider/Alert
# reconcile cleanly; replace with a real webhook to receive alerts.
kubectl -n flux-system create secret generic slack-webhook \
  --from-literal=address="https://hooks.slack.com/services/PLACEHOLDER" \
  --dry-run=client -o yaml | kubectl apply -f -

# ---------------------------------------------------------------------------
if [ "$GIT_SOURCE" = "local" ]; then
  log "Standing up a local Gitea server for Flux to reconcile from"
  # The primary/documented source is the published GitHub repository (see
  # gitops/clusters/local/flux-system/gitrepository.yaml). Standing up a real
  # GitHub remote is a deliberate, user-facing action this script does not
  # take on its own by default — see docs/gitops.md and GIT_SOURCE=github
  # above. Flux's git client (go-git) only speaks the smart HTTP protocol,
  # so a real git-http-backend implementation is required; Gitea is used
  # here (not a bare-repo dumb-HTTP static server) because it implements
  # smart HTTP correctly.

  GITEA_USER="demo"
  GITEA_PASS="demo-password-1234"
  GITEA_REPO="kubernetes-gitops-platform"

  docker rm -f "$GIT_SERVER_NAME" >/dev/null 2>&1 || true
  docker run -d --name "$GIT_SERVER_NAME" \
    --network "$DOCKER_NETWORK" \
    -p 127.0.0.1:3000:3000 \
    -e GITEA__security__INSTALL_LOCK=true \
    -e GITEA__database__DB_TYPE=sqlite3 \
    -e GITEA__server__DISABLE_SSH=true \
    gitea/gitea:1.22 >/dev/null

  log "Waiting for Gitea to become ready"
  for i in $(seq 1 30); do
    curl -sf http://127.0.0.1:3000/api/healthz >/dev/null 2>&1 && break
    sleep 2
    [ "$i" -eq 30 ] && fail "Gitea did not become ready in time"
  done

  docker exec -u git "$GIT_SERVER_NAME" gitea admin user create \
    --username "$GITEA_USER" --password "$GITEA_PASS" \
    --email demo@example.com --admin --must-change-password=false >/dev/null

  curl -sf -u "${GITEA_USER}:${GITEA_PASS}" -X POST \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"${GITEA_REPO}\",\"private\":false}" \
    http://127.0.0.1:3000/api/v1/user/repos >/dev/null

  REPO_COPY="$GIT_SCRATCH_DIR/kubernetes-gitops-platform"
  mkdir -p "$REPO_COPY"
  # --filter=':- .gitignore' skips everything .gitignore excludes (Terraform
  # provider caches, .venv, .tools, ...) so the pushed snapshot stays small
  # and doesn't drift out of sync with .gitignore over time.
  rsync -a --filter=':- .gitignore' --exclude='.git' "$ROOT_DIR/" "$REPO_COPY/"
  find "$REPO_COPY" -type f -name '*.yaml' -exec sed -i "s#REPLACE_WITH_OWNER#${GHCR_OWNER}#g" {} +

  git -C "$REPO_COPY" init -q -b main
  git -C "$REPO_COPY" -c user.email=demo@example.com -c user.name="Local Demo" \
    add -A
  git -C "$REPO_COPY" -c user.email=demo@example.com -c user.name="Local Demo" \
    commit -q -m "local demo snapshot"
  git -C "$REPO_COPY" push -q \
    "http://${GITEA_USER}:${GITEA_PASS}@127.0.0.1:3000/${GITEA_USER}/${GITEA_REPO}.git" main

  log "Local git server '$GIT_SERVER_NAME' (Gitea) serving the repo snapshot to the kind cluster"

  kubectl -n flux-system create secret generic node-api-platform-auth \
    --from-literal=username="$GITEA_USER" \
    --from-literal=password="$GITEA_PASS" \
    --dry-run=client -o yaml | kubectl apply -f -
else
  log "GIT_SOURCE=github: skipping Gitea, pointing Flux at the real GitHub repo"
fi

# ---------------------------------------------------------------------------
log "Applying Flux GitRepository and Kustomizations"

kubectl apply -f "$ROOT_DIR/gitops/clusters/local/flux-system/gitrepository.yaml"
if [ "$GIT_SOURCE" = "local" ]; then
  kubectl -n flux-system patch gitrepository node-api-platform --type merge -p \
    "{\"spec\":{\"url\":\"http://${GIT_SERVER_NAME}:3000/${GITEA_USER}/${GITEA_REPO}.git\",\"secretRef\":{\"name\":\"node-api-platform-auth\"}}}"
fi

kubectl apply -f "$ROOT_DIR/gitops/clusters/local/flux-system/kustomization-infrastructure.yaml"
kubectl apply -f "$ROOT_DIR/gitops/clusters/local/flux-system/kustomization-kyverno-policies.yaml"
kubectl apply -f "$ROOT_DIR/gitops/clusters/local/flux-system/kustomization-apps.yaml"
kubectl apply -f "$ROOT_DIR/gitops/clusters/local/flux-system/alert-provider.yaml"
kubectl apply -f "$ROOT_DIR/gitops/clusters/local/flux-system/alert.yaml"

log "Waiting for the GitRepository to reconcile"
"$TOOLS_DIR/flux" reconcile source git node-api-platform -n flux-system --timeout=2m

log "Waiting for infrastructure Kustomization (Calico is already up; this installs ingress-nginx, Kyverno, metrics-server, ESO, Reloader)"
kubectl -n flux-system wait kustomization/infrastructure --for=condition=Ready --timeout=8m

log "Waiting for Kyverno policies Kustomization"
kubectl -n flux-system wait kustomization/kyverno-policies --for=condition=Ready --timeout=3m

log "Waiting for the apps Kustomization (node-api in dev/staging/production namespaces)"
kubectl -n flux-system wait kustomization/apps --for=condition=Ready --timeout=6m

# ---------------------------------------------------------------------------
log "Waiting for node-api rollouts in all three namespaces"
for ns in node-api-dev node-api-staging node-api-production; do
  kubectl -n "$ns" rollout status deployment/node-api --timeout=180s
done

log "Waiting for ingress-nginx admission webhook"
kubectl -n ingress-nginx rollout status deployment/ingress-nginx-ingress-nginx-controller --timeout=180s

# ---------------------------------------------------------------------------
log "Running NetworkPolicy verification"
"$ROOT_DIR/scripts/test-network-policies.sh"

# ---------------------------------------------------------------------------
log "Smoke-testing the application through ingress-nginx"

TOKEN=$(kubectl -n node-api-dev get secret node-api-secret -o jsonpath='{.data.API_TOKEN}' | base64 -d)

echo "--- /health (dev, via ingress) ---"
curl -s -H "Host: dev.node-api.local" http://127.0.0.1/health; echo

echo "--- /nodes without token (expect 401) ---"
curl -s -o /dev/null -w '%{http_code}\n' -H "Host: dev.node-api.local" http://127.0.0.1/nodes

echo "--- /nodes with token ---"
curl -s -H "Host: dev.node-api.local" -H "Authorization: Bearer ${TOKEN}" http://127.0.0.1/nodes; echo

log "Demo is up."
cat <<EOF

  Namespaces:    kubectl get ns | grep node-api
  Flux status:   .tools/flux get kustomizations -A
  App pods:      kubectl -n node-api-dev get pods
  Hosts to curl (via ingress-nginx on 127.0.0.1):
    curl -H 'Host: dev.node-api.local'     http://127.0.0.1/health
    curl -H 'Host: staging.node-api.local' http://127.0.0.1/health
    curl -H 'Host: prod.node-api.local'    http://127.0.0.1/health

  Run 'make demo-observability' to add kube-prometheus-stack + ServiceMonitor.
  Run 'make teardown' to delete the cluster and local git server.

EOF
