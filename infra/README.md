# Infrastructure (Terraform)

Not applied against real AWS as part of this submission — validated with
`terraform fmt -check`, `terraform validate`, and structurally reviewed.
See `docs/cost.md` in the repo root for why the primary demo runs on kind
instead.

## Layout

```
infra/
├── modules/
│   ├── vpc/          Public/private subnets, NAT, route tables
│   ├── eks/          Control plane, OIDC provider, stable platform node group
│   ├── ecr/          Repository, KMS encryption, lifecycle policy
│   ├── iam/          IRSA roles (per-namespace ESO, ExternalDNS, ALB
│   │                 controller, Karpenter, EBS CSI driver), GitHub
│   │                 Actions OIDC roles
│   ├── addons/       EKS-managed addons (vpc-cni, coredns, kube-proxy,
│   │                 aws-ebs-csi-driver) — only what must exist before
│   │                 Flux can run; everything else is a Flux HelmRelease
│   └── karpenter/    Node IAM role/instance profile + Spot interruption
│                     handling (SQS + EventBridge); NodePool/EC2NodeClass
│                     themselves are Kubernetes resources, deployed by Flux
└── live/
    ├── bootstrap/    One-time: creates the S3 state bucket + KMS key
    │                 (local state — can't use the backend it creates)
    ├── nonprod/      Root config: one EKS cluster, dev + staging
    └── production/   Root config: separate EKS cluster, separate account
```

## Why Terraform doesn't deploy Karpenter, ALB controller, ExternalDNS, ESO, Kyverno, or Reloader

Flux is the only normal deployment actor (see `docs/gitops.md`). Terraform's
job here is limited to what genuinely has to exist before Flux can even
run (the VPC, the EKS control plane, the CNI addon, the OIDC provider so
IRSA roles can be created) and the AWS-side IAM roles those Flux-deployed
controllers will assume. The controllers themselves are HelmReleases in
`gitops/infrastructure/` — same mechanism, same audit trail, same
promotion story as the application.

## Backend

S3 with native S3 locking (`use_lockfile = true`, requires Terraform
≥1.10 — not DynamoDB), versioning enabled, KMS server-side encryption,
public access blocked. Separate backend buckets/accounts preferred for
non-production and production; separate state keys regardless. Created by
`infra/live/bootstrap` (local state, applied once per account, before
anything else).

## Running it for real

```bash
cd infra/live/bootstrap
terraform init
terraform apply -var bucket_name=<your-bucket> -var region=us-east-1

# Update infra/live/{nonprod,production}/versions.tf backend block with
# the bucket name above, then:
cd ../nonprod
terraform init
terraform plan
terraform apply
```

Replace `REPLACE_WITH_OWNER` (GitHub org/user) and
`REPLACE_WITH_{NONPROD,PRODUCTION}_STATE_BUCKET` before applying for real.
