# Backup, restore, and disaster recovery

## Backup and restore

The application is **stateless** — no persistent business data lives in
the sample app itself. Running pods are never backed up; they're recreated
from Deployment specs. Recovery relies entirely on already-durable,
already-versioned sources:

- Git (application, GitOps, and infrastructure repositories/paths).
- Versioned, KMS-encrypted Terraform state (S3 + native S3 locking).
- AWS Secrets Manager (the source of truth for secrets, separately backed
  by AWS's own durability guarantees).
- Retained, immutable ECR images (tag-immutable, scan-on-push, kept long
  enough to support rollback).

Kubernetes resources are recreated by Terraform (infrastructure) and Flux
(workloads) — there is no separate "restore a Kubernetes backup" step for
this stateless service. [Velero](https://velero.io/) is optional and not
essential for this reference implementation; it would matter for a
workload with PersistentVolumes or cluster-object backup requirements
beyond what Git+Terraform+Flux already reconstruct.

CloudWatch Logs have a defined retention policy per environment; audit
logs may be archived to S3 for longer-term retention if compliance
requires it beyond CloudWatch's own retention window.

## Disaster recovery

**Model: rebuild-from-code / pilot-light.** No permanent warm-standby EKS
cluster is provisioned for this reference implementation — a secondary AWS
region is documented as the recovery target, stood up on demand.

Recovery flow:

1. Run Terraform against the secondary region (same modules, different
   `region`/`azs` variables).
2. Restore or replicate required secrets into that region's Secrets
   Manager.
3. Ensure approved images exist in the secondary region's ECR (cross-region
   replication, or re-push from the retained non-production images).
4. Bootstrap Flux against the new cluster.
5. Reconcile the production GitOps path — Flux rebuilds the entire
   workload state from the same Git commit that was running before the
   incident.
6. Create/validate ALB and TLS in the new region.
7. Switch Route 53 to point at the new region's ALB.
8. Validate application health before restoring production traffic.

**RPO: near zero.** The application stores no persistent business data —
the only state that matters is Secrets Manager (durable, region-agnostic
if replicated) and Git (already distributed).

**RTO: approximately 1–2 hours**, dominated by EKS control-plane
provisioning, node group/Karpenter warm-up, add-on installation, ALB
provisioning, and DNS propagation — not by any data-restore step.

This trades a longer RTO for materially lower standing cost (see
`docs/cost.md`) than a warm-standby cluster would require. If the
business's actual RTO tolerance is tighter than ~1–2 hours, the next step
up is a warm-standby cluster in the secondary region with Flux already
reconciling a scaled-to-zero (or minimal) copy of production, cutting the
RTO to roughly "how long DNS takes to propagate" at the cost of running a
second cluster continuously.
