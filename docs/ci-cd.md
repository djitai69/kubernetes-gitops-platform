# CI/CD pipeline

## Build and non-production flow (`.github/workflows/ci.yaml`)

Triggered on push to `main` (and PRs, for the check-only jobs):

1. **`lint-and-test`**: ruff, pytest, `pip-audit` dependency scan.
2. **`policy-checks`**: `helm lint` (all four values files), `helm template`
   sanity render, kube-linter, Kyverno CLI tests
   (`kyverno test policies/kyverno/tests/pod-security/`).
3. **`build-scan-push`** (push to `main` only, after both checks pass):
   Docker Buildx build, push to GHCR tagged with the short Git SHA, Trivy
   scan (fails the build on CRITICAL/HIGH, unfixed CVEs ignored).
4. **`update-dev-gitops`**: bumps the image tag in
   `gitops/apps/node-api/dev/helmrelease.yaml` and commits, using a
   **GitHub App token**, not a personal access token — see
   *"CI write identity"* below. Flux picks up the change and deploys dev.

## Image tagging

- Main-branch builds: short Git SHA (`node-api:a8f2c91`) — every commit to
  `main` gets a unique, traceable tag.
- Approved releases: semantic version (`node-api:v1.4.0`), attached to the
  **already-tested digest** by a Git tag/GitHub release, never a rebuild.
- Production Kubernetes references both: `node-api:v1.4.0@sha256:...` —
  human-readable for operators, immutable for correctness.
- ECR tag immutability and image scanning are enabled (Terraform,
  `infra/modules/ecr/main.tf`).

## Promotion

- **Dev**: automatic, on every merge to `main`.
- **Staging**: a pull request against `gitops/apps/node-api/staging/helmrelease.yaml`.
  The reviewer approving the PR is the promotion gate.
- **Production**: `.github/workflows/release.yaml`, triggered by a
  `vX.Y.Z` Git tag. Copies the exact tested digest from the non-production
  registry to the production registry using `crane copy` (digest-preserving,
  never rebuilds), then opens a **protected** pull request against
  `gitops/apps/node-api/production/helmrelease.yaml` requiring
  environment-protection approval in GitHub.

## CI write identity

CI writes to the GitOps paths using a **GitHub App** installation token,
not a personal access token — scoped, revocable independently of any
individual's account, and attributable to a bot identity in commit
history. Workflow path filters (`paths:` on the trigger, and `[skip ci]`
in the bot's commit message) prevent the bot's own commits from
re-triggering the pipeline recursively.

## Terraform pipeline (`.github/workflows/terraform.yaml`)

Pull request: `terraform fmt -check`, `terraform validate`, Checkov
static analysis, `terraform plan`, plan artifact published for review.

Apply (on merge to `main`): non-production applies with a lighter approval
gate (`environment: nonprod-apply`); production requires a protected
environment approval (`environment: production-apply`) and always applies
from the reviewed, uploaded plan artifact — never an unreviewed branch.
AWS auth is OIDC in both cases; no long-lived AWS access keys are stored in
CI.

## Required repository configuration (not yet set up)

The workflows are verified working — every job was actually run via real
pushes to this repo, and every code-level bug found that way is fixed
(see `git log` for the "fix:" commits). What's left is infrastructure
configuration, not code: two classes of GitHub repo secrets/vars/environments
that were never provisioned, so the jobs that need them fail with
`Input required and not supplied: <name>` — a clean, expected failure
mode, not a bug.

**Secrets** (Settings → Secrets and variables → Actions → Secrets):

| Name | Used by | What it is |
|---|---|---|
| `GITOPS_BOT_TOKEN` | `ci.yaml` (`update-dev-gitops`), `release.yaml` | A GitHub App installation token (not a PAT — see *"CI write identity"* above) scoped to write to this repo. |
| `NONPROD_TERRAFORM_ROLE_ARN` | `terraform.yaml` | The AWS IAM role for OIDC-authenticated `terraform plan`/`apply` against the non-production account. Already created by Terraform tonight — get it locally with `cd infra/live/nonprod && terraform output` (not printed here; it's account-specific and shouldn't be committed). |
| `PROD_TERRAFORM_ROLE_ARN` | `terraform.yaml` | Same, for the production account/root config (not yet applied — see `docs/cost.md`). |
| `PROD_PROMOTION_ROLE_ARN` | `release.yaml` | The `ci-production-promotion` role (`infra/modules/iam/github-oidc.tf`) — ECR read/write scoped to the digest-copy promotion step only. |

**Variables** (same page, Variables tab):

| Name | Used by | What it is |
|---|---|---|
| `AWS_REGION` | `terraform.yaml` | e.g. `us-east-1`. |
| `PROD_ECR_REGISTRY` | `release.yaml` | The production ECR registry hostname (`<account>.dkr.ecr.<region>.amazonaws.com`). |

**Environments** (Settings → Environments), each with its own required
reviewers for the approval gate it's meant to enforce:

| Name | Used by | Gate |
|---|---|---|
| `nonprod-apply` | `terraform.yaml` | Lighter approval for non-production `terraform apply`. |
| `production-apply` | `terraform.yaml` | Protected approval for production `terraform apply`. |
| `production` | `release.yaml` | Protected approval for the production promotion PR. |

Until these exist, `ci.yaml`'s first three jobs (lint/test, policy
checks, build+scan+push) run and pass on their own — verified tonight,
including a real image landing in `ghcr.io/djitai69/node-api`. Only the
GitOps-write and Terraform-apply steps need the above.

## What CI can and can't do

CI has registry push permissions and Git write permissions. It has **no
Kubernetes cluster-admin credentials** — `kubectl` and `helm` are not even
invoked against a live cluster anywhere in these workflows. Flux, running
inside each cluster with its own scoped credentials, is the only
component that ever applies anything to Kubernetes. See `docs/gitops.md`.
