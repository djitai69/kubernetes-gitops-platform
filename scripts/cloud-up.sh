#!/usr/bin/env bash
# Provisions the real AWS non-production stack (Terraform) and wires
# GitOps to it (Flux), end to end, in one command. Mirrors
# bootstrap-local.sh's pattern: terraform apply, then Flux takes over
# everything else — see docs/gitops.md and
# gitops/clusters/aws-nonprod/README.md for the design.
#
# Costs real money while the stack exists (EKS control plane, NAT
# gateway, EC2 nodes, ALBs — roughly a few dollars/hour). Requires
# `terraform apply` confirmation unless AUTO_APPROVE=true is set.
#
# Env vars:
#   STATE_BUCKET   S3 bucket for Terraform state. Auto-generated and
#                  persisted locally (gitignored) on first run if unset.
#   AUTO_APPROVE   "true" to skip the interactive apply confirmation
#                  (for non-interactive/CI use).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_DIR="$ROOT_DIR/.tools"
STATE_FILE="$ROOT_DIR/infra/live/.state-bucket-nonprod"
AUTO_APPROVE="${AUTO_APPROVE:-false}"

export PATH="$TOOLS_DIR:$PATH"

log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$1"; }
fail() { printf '\n\033[1;31mERROR:\033[0m %s\n' "$1" >&2; exit 1; }

confirm() {
  [ "$AUTO_APPROVE" = "true" ] && return 0
  read -r -p "$1 [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

# ---------------------------------------------------------------------------
log "Preflight checks"

for cmd in aws terraform kubectl docker jq openssl; do
  command -v "$cmd" >/dev/null 2>&1 || fail "required command '$cmd' not found on PATH"
done
[ -x "$TOOLS_DIR/flux" ] || fail "flux CLI not found at $TOOLS_DIR/flux"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) \
  || fail "AWS credentials not configured (aws sts get-caller-identity failed)"
log "AWS credentials valid (account ends in ...${ACCOUNT_ID: -4})"

# ---------------------------------------------------------------------------
log "Resolving Terraform state bucket"

if [ -n "${STATE_BUCKET:-}" ]; then
  : # explicit override wins
elif [ -f "$STATE_FILE" ]; then
  STATE_BUCKET="$(cat "$STATE_FILE")"
  log "Reusing state bucket from previous run: $STATE_BUCKET"
else
  STATE_BUCKET="node-api-tfstate-$(openssl rand -hex 4)"
  echo "$STATE_BUCKET" > "$STATE_FILE"
  log "Generated new state bucket name: $STATE_BUCKET"
fi

if aws s3api head-bucket --bucket "$STATE_BUCKET" >/dev/null 2>&1; then
  log "State bucket already exists — skipping bootstrap apply"
else
  log "State bucket does not exist yet — running bootstrap"
  confirm "Create S3 bucket '$STATE_BUCKET' and its KMS key for Terraform state?" \
    || fail "aborted by user"
  (cd "$ROOT_DIR/infra/live/bootstrap" && \
    terraform init -input=false && \
    terraform apply -input=false -auto-approve \
      -var bucket_name="$STATE_BUCKET" -var region=us-east-1)
fi

# ---------------------------------------------------------------------------
log "Planning the non-production stack (VPC, EKS, ECR, IAM, Karpenter prerequisites)"

cd "$ROOT_DIR/infra/live/nonprod"
terraform init -input=false -backend-config="bucket=$STATE_BUCKET" -reconfigure
terraform plan -input=false -out=/tmp/nonprod.tfplan

confirm "Apply the plan above against real AWS? This costs money while it exists." \
  || fail "aborted by user"

log "Applying (this takes 15-20 minutes for a fresh cluster)"
terraform apply -input=false /tmp/nonprod.tfplan

CLUSTER_NAME=$(terraform output -raw cluster_name)
REGION=$(terraform output -raw region)
ECR_URL=$(terraform output -raw ecr_repository_url)
VPC_ID=$(terraform output -raw vpc_id)
cd "$ROOT_DIR"

# ---------------------------------------------------------------------------
log "Pointing kubectl at the new cluster"
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION" --alias "$CLUSTER_NAME"

# ---------------------------------------------------------------------------
log "Building and pushing the node-api image to ECR"
# ECR tag immutability (infra/modules/ecr/main.tf) rejects re-pushing an
# existing tag, even with byte-identical content — so re-running this
# script would fail on the second pass unless the tag is skipped when it
# already exists. Real CI (.github/workflows/ci.yaml) tags by short Git
# SHA precisely to avoid this; "aws-demo" here is a fixed demo
# convenience, not the production tagging strategy — see docs/ci-cd.md.
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$ECR_URL" >/dev/null
if aws ecr describe-images --repository-name node-api --image-ids imageTag=aws-demo --region "$REGION" >/dev/null 2>&1; then
  log "Image tag aws-demo already exists in ECR, skipping push"
else
  docker build -t "${ECR_URL}:aws-demo" "$ROOT_DIR/app"
  docker push "${ECR_URL}:aws-demo"
fi

# ---------------------------------------------------------------------------
log "Ensuring the dev/staging API token secrets exist in Secrets Manager"
for env in dev staging; do
  if aws secretsmanager describe-secret --secret-id "node-api/${env}/api-token" --region "$REGION" >/dev/null 2>&1; then
    log "node-api/${env}/api-token already exists, leaving it alone"
  else
    aws secretsmanager create-secret \
      --name "node-api/${env}/api-token" \
      --secret-string "${env}-$(openssl rand -hex 16)" \
      --region "$REGION" >/dev/null
    log "Created node-api/${env}/api-token"
  fi
done

# ---------------------------------------------------------------------------
log "Installing Flux (imperative bootstrap exception — same as the local demo, see docs/gitops.md)"
# --toleration-keys is required here: until Karpenter is deployed, the
# platform node group (node-role=platform:NoSchedule) is the only node
# group that exists, and flux install's static manifests carry no
# tolerations by default — Flux's own pods would sit Pending forever
# otherwise. Same root cause as the EKS-addon and Helm-chart toleration
# fixes elsewhere in this repo, found the same way (a live cluster).
"$TOOLS_DIR/flux" install --namespace=flux-system --toleration-keys=node-role
kubectl -n flux-system wait --for=condition=Available deployment --all --timeout=180s

# ---------------------------------------------------------------------------
log "Creating cluster-vars Secret for Flux postBuild.substituteFrom"
# Resolves \${AWS_ACCOUNT_ID}, \${AWS_REGION}, \${ECR_REPOSITORY_URL},
# \${VPC_ID} placeholders in the committed GitOps manifests at
# apply-time — none of these values are ever written to Git.
kubectl -n flux-system create secret generic cluster-vars \
  --from-literal=AWS_ACCOUNT_ID="$ACCOUNT_ID" \
  --from-literal=AWS_REGION="$REGION" \
  --from-literal=ECR_REPOSITORY_URL="$ECR_URL" \
  --from-literal=VPC_ID="$VPC_ID" \
  --dry-run=client -o yaml | kubectl apply -f -

# ---------------------------------------------------------------------------
log "Applying Flux GitRepository and Kustomizations"
kubectl apply -f "$ROOT_DIR/gitops/clusters/aws-nonprod/flux-system/gitrepository.yaml"
kubectl apply -f "$ROOT_DIR/gitops/clusters/aws-nonprod/flux-system/kustomization-infrastructure.yaml"
kubectl apply -f "$ROOT_DIR/gitops/clusters/aws-nonprod/flux-system/kustomization-kyverno-policies.yaml"
kubectl apply -f "$ROOT_DIR/gitops/clusters/aws-nonprod/flux-system/kustomization-apps.yaml"

log "Waiting for the GitRepository to reconcile"
"$TOOLS_DIR/flux" reconcile source git node-api-platform -n flux-system --timeout=2m

log "Waiting for infrastructure Kustomization (AWS Load Balancer Controller, Kyverno, metrics-server, ESO, Reloader)"
kubectl -n flux-system wait kustomization/infrastructure --for=condition=Ready --timeout=10m

log "Waiting for Kyverno policies Kustomization"
kubectl -n flux-system wait kustomization/kyverno-policies --for=condition=Ready --timeout=5m

log "Waiting for the apps Kustomization (node-api in dev/staging)"
kubectl -n flux-system wait kustomization/apps --for=condition=Ready --timeout=8m

# ---------------------------------------------------------------------------
log "Waiting for node-api rollouts"
for ns in node-api-dev node-api-staging; do
  kubectl -n "$ns" rollout status deployment/node-api --timeout=300s
done

# ---------------------------------------------------------------------------
log "Waiting for ALB provisioning and smoke-testing"
for ns in node-api-dev node-api-staging; do
  log "Namespace: $ns"
  ALB_HOST=""
  for i in $(seq 1 30); do
    ALB_HOST=$(kubectl -n "$ns" get ingress node-api -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
    [ -n "$ALB_HOST" ] && break
    sleep 10
  done
  if [ -z "$ALB_HOST" ]; then
    log "WARNING: no ALB hostname yet for $ns after 5 minutes — check 'kubectl -n $ns describe ingress node-api'"
    continue
  fi
  log "ALB for $ns: http://$ALB_HOST"
  for i in $(seq 1 12); do
    if curl -sf -m 5 "http://$ALB_HOST/health" >/dev/null 2>&1; then
      curl -s "http://$ALB_HOST/health"; echo
      break
    fi
    sleep 10
  done
done

log "Cloud environment is up."
cat <<EOF

  Cluster:       $CLUSTER_NAME (region $REGION)
  Kubeconfig:    aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION
  AWS Console:   https://${REGION}.console.aws.amazon.com/eks/home?region=${REGION}#/clusters/${CLUSTER_NAME}
  Flux status:   .tools/flux get kustomizations -A
  App pods:      kubectl -n node-api-dev get pods

  Run 'make cloud-down' to destroy everything and stop billing.

EOF
