# node-api Helm chart

Reusable chart, environment differences are values-only. See
`../../docs/rbac.md`, `../../docs/policy.md`, `../../docs/networking.md`,
and `../../docs/hpa-scaling.md` for what each template does and why.

```bash
helm lint . -f values-production.yaml
helm template node-api . -f values-production.yaml -n node-api-production
```

`values.yaml` holds chart defaults; `values-{dev,staging,production,local}.yaml`
are reference overlays kept in sync with what Flux actually applies from
`../../gitops/apps/node-api/<env>/helmrelease.yaml` — the GitOps repository
is the real source of truth for what's deployed; these files exist so the
chart is independently testable with `helm template`/`helm lint` outside
of Flux.
