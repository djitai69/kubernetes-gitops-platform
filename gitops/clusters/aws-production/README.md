# AWS production cluster (placeholder)

Not deployed for this submission. In the real production design, this
cluster's own Flux installation — completely independent of the
non-production cluster's Flux, in a separate AWS account — would
bootstrap here, watching only `gitops/apps/node-api/production/` (already
built, see that directory) and a production-specific
`gitops/infrastructure/aws-production/` path (not yet created — same
components as non-production: AWS Load Balancer Controller, ExternalDNS,
Kyverno in Enforce mode, metrics-server, ESO with the `aws` provider,
Reloader, plus Karpenter, which is production-focused and intentionally
not part of the local demo — see `../../../docs/node-provisioning.md`).

See `../../../docs/architecture-aws.md` and `../../../docs/gitops.md`.
