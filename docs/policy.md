# Policy-as-code (Kyverno)

## Enforcement modes

| Environment | Mode      |
|-------------|-----------|
| dev         | Audit     |
| staging     | Enforce   |
| production  | Enforce   |

Implemented as a single set of `ClusterPolicy` resources per policy (not
duplicated per environment) using Kyverno's
`validationFailureActionOverrides`, scoped by namespace pattern:

```yaml
spec:
  validationFailureAction: Audit          # fallback (dev)
  validationFailureActionOverrides:
    - action: Enforce
      namespaces: [node-api-staging, node-api-production]
    - action: Audit
      namespaces: [node-api-dev]
```

Every policy's `match` block is also scoped to `namespaces: ["node-api-*"]`
so platform namespaces (`flux-system`, `kyverno`, `ingress-nginx`,
`calico-system`, `external-secrets`, `monitoring`) are never evaluated —
third-party controllers in those namespaces don't need to satisfy this
application's pod-security baseline, and enforcing there would break
cluster bootstrap.

## Enforced policies (`policies/kyverno/enforce/`)

- `require-resource-requirements` — every container defines CPU/memory
  requests and limits.
- `require-probes` — every container defines `livenessProbe.httpGet` and
  `readinessProbe.httpGet`.
- `pod-security-baseline` — bundles the restricted Pod Security Standard
  equivalent: `runAsNonRoot`, `allowPrivilegeEscalation: false`,
  `readOnlyRootFilesystem: true`, `seccompProfile.type: RuntimeDefault`,
  `capabilities.drop: [ALL]`, no privileged containers, no
  hostNetwork/hostPID/hostIPC.
- `image-policy` — requires a tag (rejects untagged images), rejects
  `:latest`, and restricts images to an approved registry allowlist
  (`ghcr.io/*` for the demo, `*.dkr.ecr.*.amazonaws.com/*` for AWS
  production).

## Audited-only policies (`policies/kyverno/audit/`)

Not yet enforced anywhere — surfaced for visibility while the practice
matures, per the decisions doc's "initially audited" list:

- `require-standard-labels`
- `require-topology-spread` (staging/production only)
- `require-pdb` — uses a Kyverno `context.apiCall` to check a matching
  `PodDisruptionBudget` actually exists in the namespace, since "does a
  companion resource exist" can't be expressed as a field pattern.
- `require-networkpolicy` — same technique, checks at least one
  `NetworkPolicy` exists in each `node-api-*` namespace.
- `warn-broad-rbac` — flags `ClusterRole`/`Role` rules using wildcard verbs
  or resources.

## Testing

`policies/kyverno/tests/pod-security/` is a declarative Kyverno CLI test
suite (`kyverno-test.yaml`) with one compliant pod and two non-compliant
pods (privileged/host-networked, and missing resources/probes), asserting
pass/fail per rule:

```
make kyverno-test
# or directly:
.tools/kyverno test policies/kyverno/tests/pod-security/
```

This is also wired into CI (`.github/workflows/ci.yaml`, `policy-checks`
job), alongside `helm lint`, `helm template`, and `kube-linter`
(`policies/kube-linter/config.yaml`) as a second, independently-implemented
check on the same manifests.
