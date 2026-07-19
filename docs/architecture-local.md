# Architecture — local kind demo

```mermaid
flowchart TB
    subgraph host["Developer machine"]
        gitea["Gitea container\n(local git source,\nsubstitutes GitHub)"]
        browser["curl / browser"]
    end

    subgraph kind["kind cluster (Calico CNI)"]
        subgraph fluxsys["flux-system"]
            src["source-controller"]
            kust["kustomize-controller"]
            helmc["helm-controller"]
            notif["notification-controller"]
        end

        subgraph platform["Platform (Flux-managed)"]
            ingress["ingress-nginx"]
            kyverno["Kyverno"]
            ms["metrics-server"]
            eso["External Secrets Operator"]
            reloader["Stakater Reloader"]
        end

        subgraph devns["node-api-dev"]
            appdev["node-api pod(s)"]
            secdev["Secret (from ESO)"]
        end
        subgraph stgns["node-api-staging"]
            appstg["node-api pod(s) + HPA + PDB"]
        end
        subgraph prodns["node-api-production (local sim)"]
            appprod["node-api pod(s) + HPA + PDB"]
        end
    end

    gitea -- "git clone/pull (smart HTTP)" --> src
    src --> kust
    kust --> helmc
    helmc --> platform
    helmc --> devns
    helmc --> stgns
    helmc --> prodns
    browser -- "Host: dev/staging/prod.node-api.local\nport 80/443" --> ingress
    ingress --> appdev
    ingress --> appstg
    ingress --> appprod
    eso -- "reconciles" --> secdev
    kust -.->|Ready condition\nalerts| notif
    notif -- "Slack (placeholder webhook)" --> host
```

## What's real vs. simulated

| Component            | Local demo                                   | AWS production target                        |
|-----------------------|-----------------------------------------------|------------------------------------------------|
| Git source             | Gitea container (smart HTTP)                   | Published GitHub repository                    |
| Container registry      | GHCR (or `kind load docker-image` for offline) | GHCR (non-prod) + private ECR (production)    |
| Ingress                 | ingress-nginx, host-mapped ports 80/443         | AWS Load Balancer Controller, ALB              |
| Secrets backend          | Kubernetes `Secret` (ESO `kubernetes` provider) | AWS Secrets Manager (ESO `aws` provider, IRSA) |
| Node provisioning         | Single kind node                                | Managed node group + Karpenter                 |
| CNI                       | Calico (installed imperatively, see docs/gitops.md) | VPC CNI (EKS-managed addon)                |
| Namespaces                 | All three (dev/staging/production) on one cluster | dev+staging on non-prod cluster, production on its own cluster/account |

The Flux reconciliation graph, Helm chart, Kyverno policies, RBAC,
SecurityContext, HPA, PDB, and NetworkPolicy are identical in both — only
the pieces above differ, and each difference is a Helm values override,
not a different chart or different Flux mechanics.
