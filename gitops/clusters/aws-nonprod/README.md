# AWS non-production cluster (placeholder)

Not deployed for this submission. In the real production design, this
cluster's own Flux installation would bootstrap here with a `GitRepository`
+ `Kustomization` pair identical in shape to
`../local/flux-system/`, pointed at:

- `gitops/infrastructure/aws-nonprod/` (ingress-nginx via AWS Load
  Balancer Controller instead of the local demo's plain ingress-nginx,
  ExternalDNS, Kyverno, metrics-server, ESO configured with the `aws`
  provider, Reloader)
- `gitops/apps/node-api/dev/` and `gitops/apps/node-api/staging/` (these
  already exist and are environment-ready — no AWS-specific changes
  needed, since only the Helm values differ, not the chart)

See `../../../docs/architecture-aws.md` and `../../../docs/gitops.md`.
