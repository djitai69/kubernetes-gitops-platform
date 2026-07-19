# Cost considerations

- **kind** is the default demo platform — the primary deliverable requires
  no AWS spend at all. AWS Terraform is reviewed code, not a running
  requirement.
- Dev and staging share one non-production EKS cluster and one ALB
  (host-based routing) instead of per-environment clusters/load balancers.
- Production has its own cluster and ALB — isolation is prioritized there,
  cost is not the deciding factor.
- A small **on-demand** managed node group carries only platform
  components (CoreDNS, Flux, Karpenter, ESO, Kyverno); application
  workloads run on Karpenter-provisioned capacity that can use Spot.
- Two Karpenter NodePools: on-demand-only for critical workloads, flexible
  Spot/on-demand for stateless ones (the sample app qualifies as flexible).
- Karpenter consolidation reduces idle capacity automatically.
- **One NAT gateway** in non-production (accepted single point of egress
  failure as a deliberate cost trade-off); **one NAT gateway per AZ** in
  production (availability prioritized).
- Shorter CloudWatch Logs retention in dev, longer in production.
- HPA plus tuned resource requests avoid static over-provisioning.
- **No warm-standby DR cluster** — rebuild-from-code/pilot-light instead
  (see `docs/disaster-recovery.md`), trading a longer RTO for zero idle
  infrastructure cost.
- Any AWS resources stood up to validate this submission beyond the local
  kind demo should be destroyed after validation (`terraform destroy`).
- VPC endpoints (S3, ECR, STS, Secrets Manager, CloudWatch) reduce NAT data
  processing charges at meaningful traffic volumes but add their own hourly
  cost — evaluate against actual NAT gateway data-transfer cost before
  adding them; not included by default in the Terraform modules here.
