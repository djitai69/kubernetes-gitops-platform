# Assumptions, trade-offs, and known limitations

## Assumptions

- The reviewer runs the local kind demo (`make demo`) rather than a real
  AWS deployment; AWS Terraform is reviewed as code.
- Docker Desktop/Engine, kind, kubectl, and Helm are available locally; the
  bootstrap script vendors its own `flux` and `kyverno` CLIs into
  `.tools/` so no global install of those two is required.
- A single-container pod is sufficient for `node-api` — the Kyverno
  `image-policy` rules (`anyPattern` over the whole `containers` array)
  assume this and would need a `foreach`-based rewrite for multi-container
  pods.
- The reviewer's machine has ~6–8GB of spare Docker memory and can bind
  host ports 80/443 (see the README's resource-requirements section).

## Key trade-offs (see individual docs for full reasoning)

- Monorepo over three repositories — reviewer simplicity now, documented
  split for production (`docs/gitops.md`).
- kind over a required AWS deployment — reproducibility and zero cost for
  the primary demo (`docs/cost.md`).
- Calico over kindnet — kindnet does not enforce `NetworkPolicy` at all;
  Calico is required for the NetworkPolicy requirement to mean anything
  (`docs/networking.md`).
- CI-driven GitOps updates over Flux Image Automation — explicit,
  auditable promotion steps over automatic tag detection
  (`docs/gitops.md`).
- Rebuild-from-code DR over a warm standby — lower cost, longer RTO
  (`docs/disaster-recovery.md`).
- CPU-only HPA over request-rate/latency-based autoscaling — simple and
  demonstrable now; documented as a near-term enhancement
  (`docs/production-recommendations.md`).

## Known limitations

- **Local ESO uses the `kubernetes` provider, not `aws`.** The
  `SecretStore`/`ExternalSecret` reconciliation is real, but the backend is
  a same-namespace bootstrap `Secret` standing in for Secrets Manager. The
  production manifests (`gitops/apps/node-api/production/`) use the real
  `aws` provider with IRSA.
- **Standard `NetworkPolicy` cannot target FQDNs.** Kubernetes API egress
  is allowed by CIDR (broad locally, VPC/control-plane-scoped in AWS), not
  by hostname. See `docs/networking.md`.
- **`make demo-observability` patches live HelmReleases and suspends Flux
  reconciliation on them** to make the `ServiceMonitor` toggle stick for
  the duration of the demo; this is an intentional, documented departure
  from "Git is the only source of truth" for that one demo convenience.
  Running `make demo` again rebuilds from the committed Git state and
  resumes normal reconciliation.
- **Terraform is not applied against real AWS** as part of this
  submission — it is validated with `terraform fmt`, `terraform validate`,
  and `terraform plan` semantics only (see the README for what was
  actually run).
- **The local Gitea git server is ephemeral** and specific to `make demo` —
  it is not the documented production source of truth (a real GitHub
  repository) and does not persist reviewer edits automatically; see
  `docs/gitops.md`.
- **Single-replica dev/staging in the local demo** by design (dev has HPA
  disabled and PDB disabled so Karpenter-style node consolidation isn't
  blocked by a one-replica PDB) — production values enable both.
