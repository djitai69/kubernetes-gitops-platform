# RBAC

## Application ServiceAccount

`node-api` uses a dedicated ServiceAccount (`helm/node-api/templates/serviceaccount.yaml`)
with a `ClusterRole` granting exactly:

```yaml
resources: ["nodes"]
verbs: ["list"]
```

`get` and `watch` are deliberately not granted — `GET /nodes` only ever
calls `list_node()` once per (cache-TTL-bounded) request; it never watches
for changes or fetches a single named node.

A `ClusterRole` is required (not a namespaced `Role`) because `nodes` are
cluster-scoped resources — there is no way to scope node visibility to a
namespace. The `ClusterRoleBinding` targets only the `node-api`
ServiceAccount, not a group or `system:authenticated`.

`ClusterRole`/`ClusterRoleBinding` names are suffixed with the release
namespace (`node-api-<namespace>-nodes-reader`) so the dev, staging, and
production HelmRelease installs — each a separate Helm release in a
separate namespace — don't collide on a shared cluster-scoped resource
name.

`automountServiceAccountToken` remains **enabled** for this ServiceAccount
because `/nodes` genuinely needs to call the Kubernetes API. Workloads that
don't call the Kubernetes API should disable it — this is the default
posture for every other component in this stack (ingress-nginx, Reloader,
etc. don't get a token unless they specifically need one).

## Kyverno

See `docs/policy.md`.

## IRSA (AWS)

See `docs/secrets.md` and `infra/modules/iam/irsa.tf` — one IAM role per
Kubernetes ServiceAccount, scoped by an OIDC trust-policy condition, not a
shared role across controllers.
