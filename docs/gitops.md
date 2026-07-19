# GitOps model

## Repository layout

```
kubernetes-gitops-platform/
├── app/            FastAPI source, Dockerfile, tests
├── helm/           Reusable Helm chart (helm/node-api)
├── gitops/         Flux configuration and per-environment values
├── infra/          Terraform (VPC, EKS, ECR, IAM, addons, Karpenter)
├── policies/       Kyverno policies + tests, kube-linter config
├── local/          kind cluster config
├── scripts/        bootstrap-local.sh, test-network-policies.sh, teardown-local.sh
├── docs/           This directory
└── .github/workflows/
```

This is a **monorepo** for the homework submission, chosen to minimize
reviewer friction (one clone, one README, everything cross-referenced with
relative paths). A real production organization would likely split this
into three repositories — application, GitOps, and infrastructure — for
stronger ownership and access-control boundaries between teams. See
`docs/production-recommendations.md`.

## Why Flux is the only deployment actor

CI builds, scans, and pushes images, then writes a new image reference into
`gitops/apps/node-api/<env>/helmrelease.yaml` and opens/merges a commit or
PR. It never runs `kubectl apply` or `helm upgrade` against a cluster. Flux
detects the Git change and reconciles it. This means:

- Every deployed state is traceable to a Git commit.
- A cluster that drifts from Git (someone runs `kubectl edit`) is
  automatically reconciled back to the committed state.
- CI credentials never need cluster-admin — only Git write access and
  registry push access.

Two **documented exceptions** exist, both because of a genuine chicken-and-egg
problem, not convenience:

1. **The CNI (Calico).** No pod can be scheduled with working networking
   until a CNI is installed — including Flux's own pods and CoreDNS. Calico
   is applied imperatively by `scripts/bootstrap-local.sh` before anything
   else. In AWS, the VPC CNI ships as an EKS-managed addon provisioned by
   Terraform for the same reason.
2. **Flux itself.** Flux cannot deploy itself from Git before it exists in
   the cluster. `flux install` (imperative) creates the controllers; from
   that point on, Flux deploys everything else, including its own
   `GitRepository`/`Kustomization` objects, which are just more YAML in Git.

## Flux resource graph (local demo)

```
GitRepository/node-api-platform
        │
        ├── Kustomization/infrastructure  (wait: true)
        │     → ingress-nginx, Kyverno, metrics-server,
        │       External Secrets Operator, Reloader (all HelmReleases)
        │
        ├── Kustomization/kyverno-policies  (dependsOn: infrastructure)
        │     → Kyverno ClusterPolicies (policies/kyverno/)
        │
        └── Kustomization/apps  (dependsOn: infrastructure, kyverno-policies)
              → node-api HelmReleases in node-api-dev/staging/production
```

`kyverno-policies` is a **sibling** of `infrastructure`, not one of its
managed resources. `infrastructure` has `wait: true`, which health-checks
everything it applies — nesting a Kustomization inside it that also
`dependsOn: infrastructure` would deadlock (neither could become Ready
while waiting on the other). This was hit and fixed during development —
see the git history on `gitops/infrastructure/local/kyverno/`.

## Environment promotion

- **Dev**: CI updates the image tag automatically on every merge to `main`.
- **Staging**: promoted via a normal pull request against
  `gitops/apps/node-api/staging/helmrelease.yaml`. The PR reviewer approving
  *is* the promotion gate — no separate workflow needed.
- **Production**: a Git tag (`vX.Y.Z`) triggers `.github/workflows/release.yaml`,
  which copies the exact tested digest from the non-production registry to
  the production registry (never rebuilds) and opens a protected PR against
  `gitops/apps/node-api/production/helmrelease.yaml`. Production requires
  environment-protection approval in GitHub before merge.

## Flux Image Automation — considered and rejected

Flux's Image Automation controllers can update image references in Git
automatically based on new tags/digests appearing in a registry. This was
considered and rejected for the reference implementation: CI-driven Git
updates make the build → scan → promote → approve chain explicit and easy
to demonstrate/audit. Flux remains the only component that performs the
actual Kubernetes deployment either way — this decision only concerns *who
writes the Git commit*, not who applies it to the cluster.

## Drift and reconciliation

Manual `kubectl edit`/`kubectl apply` against a Flux-managed resource is
drift. Flux's next reconciliation (interval: 1m for apps, 5m for
infrastructure) reverts it. Emergency manual changes are an exception, not
the norm — they must be reflected in Git immediately afterward, and if
reconciliation was suspended during an incident it must be resumed
afterward.

Rollback is a Git operation: revert the commit, or commit the previous
known-good image tag/digest. `kubectl rollout undo` is not the standard
path because it fixes the cluster without fixing Git, so the next
reconciliation would undo the undo.

## Local demo vs. the real source

The primary/documented source of truth is a published GitHub repository
(`gitops/clusters/local/flux-system/gitrepository.yaml`). Standing up a
real GitHub remote under a specific account is a deliberate, user-facing
action `scripts/bootstrap-local.sh` does not take on its own. Instead, the
bootstrap script stands up a local [Gitea](https://about.gitea.com/)
container (not a bare-repo/dumb-HTTP static server — Flux's git client only
speaks the smart HTTP protocol) and pushes a snapshot of the working tree
to it, then patches the `GitRepository.spec.url` to point there. This
exercises the *real* Flux reconciliation loop end to end, not a simulation.
Local edits made after the snapshot is pushed are not picked up — commit
and re-run `make demo`, or push to the real GitHub remote and swap the URL.
