# GitOps repository

See `../docs/gitops.md` for the full write-up. Quick reference:

```
gitops/
├── clusters/
│   ├── local/           Flux entry point for the kind demo (what
│   │                    make demo actually bootstraps)
│   ├── aws-nonprod/      Placeholder — production design, not deployed
│   └── aws-production/   Placeholder — production design, not deployed
├── infrastructure/
│   └── local/            Platform HelmReleases: ingress-nginx, Kyverno,
│                          metrics-server, External Secrets Operator,
│                          Reloader, kube-prometheus-stack (observability
│                          profile only)
└── apps/
    └── node-api/
        ├── dev/           Applied to node-api-dev (both the local demo
        │                  and a real non-prod EKS cluster would use this)
        ├── staging/       Applied to node-api-staging
        ├── production/    AWS production target — separate cluster/account
        └── local/          Aggregates dev/ + staging/ + a local-only
                             production simulation, for the kind demo's
                             three-namespace layout
```

`aws-nonprod/` and `aws-production/` are intentionally empty placeholders
documenting where a real non-production/production EKS cluster's own Flux
installation would point (each cluster runs its own Flux, watching only
its own path — see `../docs/gitops.md`). They are not exercised by
`make demo`.
