# Node provisioning (AWS production design)

## Stable platform node group

A small, on-demand, multi-AZ **managed node group** (`infra/modules/eks/main.tf`,
`aws_eks_node_group.platform`) carries baseline capacity for cluster
controllers that must not be scheduled onto nodes they themselves might
scale away: CoreDNS, Flux, Karpenter, External Secrets Operator, Kyverno.
This group is explicitly not described as "never dying" — it's simply
stable enough that Karpenter (which runs on it) doesn't depend on nodes it
creates itself.

The group is labeled and tainted (`node-role=platform:NoSchedule`);
platform controllers carry a matching toleration so only intended
workloads land there — application pods are excluded by default.

If Karpenter is temporarily unavailable, existing nodes and pods continue
running; only *new* unschedulable workloads may remain pending until it
recovers.

## Karpenter NodePools

Two application-facing NodePools (Kubernetes resources, deployed by Flux —
Terraform only provisions the AWS-side node role, instance profile, and
interruption-handling SQS queue/EventBridge rules, see
`infra/modules/karpenter/main.tf`):

| NodePool | Capacity | Disruption | For |
|---|---|---|---|
| On-demand | On-demand only | Conservative | Critical workloads |
| Flexible | Spot + on-demand | More aggressive consolidation | Stateless, interruption-tolerant workloads |

`node-api` is stateless and selects the flexible pool via node
selector/requirements. Spot-safety is achieved through the combination
already present in the Helm chart, not through any Karpenter-specific
code: multiple replicas, a PDB, readiness probes, graceful termination,
topology spread, and no local persistent state (see `docs/hpa-scaling.md`).
Karpenter's own interruption handling (via the SQS queue Terraform
provisions) drains nodes proactively on a Spot interruption notice rather
than waiting for a hard termination.

## Sizing and scaling philosophy

Karpenter provisions exactly the instance types/sizes a pending pod's
requests actually require, rather than a fixed node pool shape — this is
the practical cost lever alongside Spot eligibility. See `docs/cost.md`.
