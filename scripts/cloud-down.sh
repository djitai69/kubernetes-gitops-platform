#!/usr/bin/env bash
# Tears down the real AWS non-production stack. Does NOT delete the
# Terraform state bucket (infra/live/bootstrap) by default — pass
# --with-bootstrap to also destroy that (irreversible: deletes state
# history for every environment using this bucket).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_FILE="$ROOT_DIR/infra/live/.state-bucket-nonprod"
AUTO_APPROVE="${AUTO_APPROVE:-false}"
WITH_BOOTSTRAP=false
[ "${1:-}" = "--with-bootstrap" ] && WITH_BOOTSTRAP=true

log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$1"; }
fail() { printf '\n\033[1;31mERROR:\033[0m %s\n' "$1" >&2; exit 1; }

confirm() {
  [ "$AUTO_APPROVE" = "true" ] && return 0
  read -r -p "$1 [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

[ -f "$STATE_FILE" ] || fail "no $STATE_FILE found — nothing to destroy, or STATE_BUCKET was never persisted locally. Set STATE_BUCKET manually if you know it."
STATE_BUCKET="$(cat "$STATE_FILE")"

log "Destroying non-production stack (cluster, VPC, IAM, ECR — the state bucket itself is kept unless --with-bootstrap)"
cd "$ROOT_DIR/infra/live/nonprod"
terraform init -input=false -backend-config="bucket=$STATE_BUCKET" -reconfigure
terraform plan -destroy -input=false -out=/tmp/nonprod-destroy.tfplan

confirm "Destroy the plan above? This deletes real AWS resources." || fail "aborted by user"
terraform apply -input=false /tmp/nonprod-destroy.tfplan

if [ "$WITH_BOOTSTRAP" = "true" ]; then
  log "Destroying the state bucket and KMS key (--with-bootstrap was passed)"
  confirm "Really destroy the Terraform state bucket '$STATE_BUCKET'? This is irreversible." \
    || fail "aborted by user"
  cd "$ROOT_DIR/infra/live/bootstrap"
  # The bucket must be emptied first — S3 buckets with objects can't be destroyed directly.
  aws s3 rm "s3://$STATE_BUCKET" --recursive || true
  terraform destroy -input=false -auto-approve \
    -var bucket_name="$STATE_BUCKET" -var region=us-east-1
  rm -f "$STATE_FILE"
fi

log "Cloud environment torn down."
