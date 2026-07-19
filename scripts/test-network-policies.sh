#!/usr/bin/env bash
# Verifies NetworkPolicy is actually enforced (Calico), not just applied.
# Run after the app is deployed and ingress-nginx is ready.
set -euo pipefail

NS="node-api-dev"
FAIL=0

log() { printf '\n\033[1;34m--\033[0m %s\n' "$1"; }
pass() { printf '  \033[1;32mPASS\033[0m %s\n' "$1"; }
bad()  { printf '  \033[1;31mFAIL\033[0m %s\n' "$1"; FAIL=1; }

# Calico's Felix dataplane agent takes a few seconds to program iptables
# after a NetworkPolicy is created, so a probe run immediately after
# rollout can see a stale (not-yet-enforced) state. Retry a few times
# before treating a single result as authoritative.
retry() {
  local attempts=$1; shift
  local i
  for i in $(seq 1 "$attempts"); do
    if "$@"; then
      return 0
    fi
    [ "$i" -lt "$attempts" ] && sleep 3
  done
  return 1
}

# A curl timeout (the "blocked" case we're testing for) makes `kubectl run
# --rm -i` itself exit non-zero. Under `set -o pipefail`, piping that
# straight into grep would poison the pipeline's exit status with
# kubectl's failure even when grep correctly matches "000" — so output is
# captured into a variable first (with `|| true` to neutralize `set -e`
# for the expected-to-fail case) and matched separately.
probe_blocked() {
  local ns=$1 url=$2 output
  kubectl -n "$ns" delete pod netpol-probe --ignore-not-found --wait=true >/dev/null 2>&1 || true
  output=$(kubectl run netpol-probe -n "$ns" --rm -i --restart=Never --image=curlimages/curl:8.10.1 \
    --command -- curl -s -o /dev/null -m 4 -w '%{http_code}\n' "$url" 2>/dev/null || true)
  [ "$(printf '%s\n' "$output" | grep -x '000')" = "000" ]
}

probe_allowed() {
  local ns=$1 url=$2
  kubectl -n "$ns" delete pod netpol-probe --ignore-not-found --wait=true >/dev/null 2>&1 || true
  kubectl run netpol-probe -n "$ns" --rm -i --restart=Never --image=curlimages/curl:8.10.1 \
    --command -- curl -sf -m 4 "$url" >/dev/null 2>&1
}

log "1. Unauthorized pod (default namespace) cannot reach the app"
if retry 5 probe_blocked default "http://node-api.${NS}.svc.cluster.local"; then
  pass "unauthorized namespace blocked (connection timed out/refused as expected)"
else
  bad "unauthorized namespace could reach the app — default-deny is not working"
fi

log "2. ingress-nginx can reach the app"
if retry 5 probe_allowed ingress-nginx "http://node-api.${NS}.svc.cluster.local/health"; then
  pass "ingress-nginx namespace can reach the app"
else
  bad "ingress-nginx namespace could NOT reach the app — ingress allow rule is broken"
fi

log "3. The app can resolve DNS"
if kubectl -n "$NS" exec deploy/node-api -c node-api -- python3 -c \
    "import socket; socket.gethostbyname('kubernetes.default.svc.cluster.local')" >/dev/null 2>&1; then
  pass "DNS resolution works from the app pod"
else
  bad "DNS resolution failed from the app pod"
fi

log "4. The app can call the Kubernetes API (TCP egress to kubernetes.default:443)"
if kubectl -n "$NS" exec deploy/node-api -c node-api -- python3 -c \
    "import socket; socket.create_connection(('kubernetes.default.svc.cluster.local', 443), timeout=3).close()" >/dev/null 2>&1; then
  pass "app pod can reach the Kubernetes API on 443"
else
  bad "app pod could NOT reach the Kubernetes API — check the kubernetesApi egress rule and kind's 443->6443 DNAT"
fi

log "5. Monitoring namespace can reach the metrics port; other namespaces cannot"
if retry 5 probe_allowed monitoring "http://node-api-metrics.${NS}.svc.cluster.local:9000/metrics"; then
  pass "monitoring namespace can reach the metrics port"
else
  bad "monitoring namespace could NOT reach the metrics port"
fi

if retry 5 probe_blocked default "http://node-api-metrics.${NS}.svc.cluster.local:9000/metrics"; then
  pass "unauthorized namespace blocked from the metrics port"
else
  bad "unauthorized namespace could reach the metrics port — metrics boundary is not enforced"
fi

if [ "$FAIL" -eq 0 ]; then
  echo
  echo "All NetworkPolicy checks passed."
else
  echo
  echo "One or more NetworkPolicy checks failed." >&2
  exit 1
fi
