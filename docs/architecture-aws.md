# Architecture — AWS production target design

```mermaid
flowchart TB
    subgraph gh["GitHub"]
        repo["kubernetes-gitops-platform"]
        actions["GitHub Actions\n(OIDC, no long-lived keys)"]
    end

    subgraph nonprod["Non-production AWS account"]
        subgraph nonprodvpc["VPC"]
            nonprodalb["Shared ALB\n(dev + staging, host-based routing)"]
            nonprodeks["EKS cluster\n(dev + staging namespaces)"]
        end
        nonprodecr["ECR (non-production)"]
        nonprodsm["Secrets Manager\n(node-api/dev/*, node-api/staging/*)"]
    end

    subgraph prod["Production AWS account (separate)"]
        subgraph prodvpc["VPC"]
            prodalb["Dedicated ALB"]
            prodeks["EKS cluster\n(production namespace)"]
        end
        prodecr["ECR (production)"]
        prodsm["Secrets Manager\n(node-api/production/*)"]
    end

    r53["Route 53"]
    cw["CloudWatch\n(logs, alarms, control-plane)"]
    slack["Slack"]

    repo -- "merge to main" --> actions
    actions -- "build, scan, push (short SHA)" --> nonprodecr
    actions -- "commit dev image ref" --> repo
    repo -- "Flux (non-prod)\nreconciles" --> nonprodeks
    nonprodeks -- "ESO + IRSA" --> nonprodsm

    actions -- "git tag vX.Y.Z\ncopies exact digest\n(crane/skopeo, no rebuild)" --> prodecr
    actions -- "opens protected PR" --> repo
    repo -- "Flux (production)\nreconciles" --> prodeks
    prodeks -- "ESO + IRSA" --> prodsm

    nonprodalb --> r53
    prodalb --> r53

    nonprodeks -- "control-plane logs,\nALB metrics" --> cw
    prodeks -- "control-plane logs,\nALB metrics" --> cw
    cw -- "CloudWatch Alarm -> SNS" --> slack
    nonprodeks -- "Flux notification-controller" --> slack
    prodeks -- "Flux notification-controller" --> slack
```

## Key properties

- **Two EKS clusters, two AWS accounts**: production is fully isolated —
  separate control plane, failure domain, network boundary, IAM boundary.
  Non-production hosts dev and staging as namespaces on one cluster to
  control cost.
- **Each cluster runs its own Flux installation**, watching only its own
  GitOps path (`gitops/apps/node-api/{dev,staging}` for non-prod,
  `gitops/apps/node-api/production` for prod). Production does not depend
  on non-production Flux in any way.
- **CI never has cluster-admin.** GitHub Actions authenticates to AWS via
  OIDC with two narrowly-scoped roles: one for non-production ECR push
  (`ci-nonprod`), one for the production digest-copy promotion step only
  (`ci-prod-promotion`) — see `infra/modules/iam/github-oidc.tf`. Neither
  role can reach the Kubernetes API; only Flux, running inside the
  cluster, deploys anything.
- **Build once, promote by digest**: the image built and scanned for
  non-production is the exact same digest promoted to production —
  `docker/node-api:v1.4.0@sha256:...` — never rebuilt.
- **IRSA everywhere AWS access is needed** (ESO, ExternalDNS, ALB
  controller, Karpenter, EBS CSI driver) — the application pod itself
  receives zero AWS IAM permissions.

See `docs/networking.md`, `docs/secrets.md`, `docs/cost.md`, and
`docs/disaster-recovery.md` for the reasoning behind each piece.
