# Secrets management (extra credit)

## Where secrets are stored

**Production design:** AWS Secrets Manager, one path per environment
(`node-api/dev/`, `node-api/staging/`, `node-api/production/`), encrypted
with KMS. Secrets are never stored in plaintext in Git — the GitOps
repository only contains `SecretStore`/`ExternalSecret` *references* (paths,
not values).

**Local kind demo:** no AWS dependency is available, so the same
`ExternalSecret` → `SecretStore` → Kubernetes `Secret` flow is exercised
against ESO's `kubernetes` provider instead of the `aws` provider. A
same-namespace bootstrap `Secret` (`node-api-bootstrap-token`) stands in for
Secrets Manager. This is a real ESO reconciliation, not a shortcut — only
the backend differs. See `gitops/apps/node-api/dev/eso-local-backend.yaml`.

## How workloads consume secrets

```
AWS Secrets Manager (or, locally, a same-namespace Secret)
        │  ESO reconciles on refreshInterval
        ▼
Kubernetes Secret "node-api-secret"
        │  secretKeyRef in the Deployment spec
        ▼
API_TOKEN environment variable
        │
        ▼
FastAPI bearer-token check on GET /nodes (fail-closed if unset — see
app/node_api/auth.py)
```

The application never talks to AWS directly and receives no AWS IAM
permissions. It only reads a Kubernetes `Secret`, which is how the
"application does not require direct AWS Secrets Manager access" boundary
(decisions doc §16) is enforced in practice.

## How access is controlled

- One `SecretStore` **per namespace**, not a cluster-wide
  `ClusterSecretStore`. A staging `SecretStore` cannot be pointed at
  production secrets even by a namespace admin with full RBAC in that
  namespace, because the trust boundary is the IAM role, not Kubernetes RBAC.
- One AWS IAM role **per namespace** (IRSA), each scoped by an
  Actions-transferable IAM `Condition` to a single Kubernetes ServiceAccount
  (`system:serviceaccount:<namespace>:node-api-secrets-reader`) — see
  `infra/modules/iam/irsa.tf`. A pod cannot assume another namespace's role
  even if it somehow obtained that role's ARN.
- Each namespace's IAM policy is scoped to a single Secrets Manager path
  prefix (`node-api/<env>/*`), enforced via a resource ARN wildcard, not a
  broad `secretsmanager:*` grant.

## How secrets are separated between environments

| Environment | AWS account       | Secrets Manager path   | IAM role                              |
|-------------|--------------------|--------------------------|----------------------------------------|
| dev         | non-production      | `node-api/dev/*`         | `<cluster>-eso-node-api-dev`           |
| staging     | non-production      | `node-api/staging/*`     | `<cluster>-eso-node-api-staging`       |
| production  | **separate account** | `node-api/production/*`  | `<cluster>-eso-node-api-production`    |

Production's isolation is not just a path prefix — it is a separate AWS
account, so a compromised non-production IAM role has zero path to
production secrets regardless of policy misconfiguration.

## How rotation would work in production

1. A new secret version is written to AWS Secrets Manager (manually, or by
   an automated Lambda rotation function).
2. ESO's `refreshInterval` (15m in production) picks up the new value and
   updates the Kubernetes `Secret`.
3. [Stakater Reloader](https://github.com/stakater/Reloader) watches for
   the `Secret`'s content hash changing (via the
   `reloader.stakater.com/auto: "true"` annotation the Helm chart sets — see
   `helm/node-api/templates/deployment.yaml`) and triggers a rolling
   restart of the Deployment.
4. Multiple replicas, readiness probes, `RollingUpdate` with
   `maxUnavailable: 0`, and a PDB mean the rotation is a zero-downtime
   rolling restart, not a full outage.
5. For credentials where the downstream system supports it (not applicable
   to this app's single static token, but relevant for e.g. database
   credentials), production rotation should support an overlap window where
   both the old and new credential are valid, so in-flight requests signed
   with the old credential don't fail mid-rotation.

## Policy-as-code (Kyverno)

See `policies/kyverno/README` inline comments and `docs/policy.md` for the
full policy list, enforcement modes, and the `kubectl kyverno test` suite
that exercises them against both compliant and non-compliant pods.
