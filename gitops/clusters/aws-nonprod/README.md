# AWS non-production cluster

`flux-system/` here is real, not a placeholder — it's what
`scripts/cloud-up.sh` applies against the real EKS cluster Terraform
provisions (`infra/live/nonprod`). See `../local/flux-system/` for the
kind-demo equivalent; the structure is identical (GitRepository +
infrastructure/kyverno-policies/apps Kustomizations), with two real
differences:

- `spec.url` points at the published GitHub repository directly — no
  local Gitea substitute, since real EKS nodes have no network path to a
  container on a developer's laptop.
- `postBuild.substituteFrom` resolves `${AWS_ACCOUNT_ID}` / `${AWS_REGION}`
  placeholders (used in IRSA `ServiceAccount` annotations and the ECR
  image repository) from a `cluster-vars` Secret that `cloud-up.sh`
  creates directly on the cluster via `kubectl`, using real Terraform
  outputs. The account ID is never committed to Git.

Reconciles:
- `gitops/infrastructure/aws-nonprod/` — AWS Load Balancer Controller
  (real IRSA role), Kyverno, metrics-server, External Secrets Operator,
  Reloader. Karpenter and ExternalDNS are documented (`docs/node-provisioning.md`,
  `docs/networking.md`) but not deployed here — Karpenter isn't required
  for this proof, and ExternalDNS has no real hosted zone to manage
  without a domain.
- `gitops/apps/node-api/aws-nonprod/{dev,staging}/` — the same Helm
  chart as everywhere else, pulling from ECR instead of GHCR, with a real
  `aws`-provider ESO `SecretStore`/`ExternalSecret`/IRSA `ServiceAccount`,
  and an ALB `Ingress` (host-optional catch-all, since there's no domain
  to route on — see the comment in `gitops/apps/node-api/aws-nonprod/dev/helmrelease.yaml`
  for why dev and staging each get their own ALB here instead of the
  documented shared one).

See `../../../docs/architecture-aws.md` and `../../../docs/gitops.md`.
