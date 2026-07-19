# Policy-as-code

See `../docs/policy.md` for the full write-up. Quick reference:

```
policies/
├── kyverno/
│   ├── enforce/    Enforced everywhere in staging/production, audited in dev
│   ├── audit/      Audit-only everywhere (not yet enforced)
│   ├── tests/      Declarative kyverno-test.yaml suites
│   └── kustomization.yaml   Aggregates enforce/+audit/ for the Flux path
└── kube-linter/
    └── config.yaml Second, independently-implemented check on the same manifests
```

Run locally:

```bash
make kyverno-test
kube-linter lint --config policies/kube-linter/config.yaml helm/node-api
```
