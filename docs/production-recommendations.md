# Production recommendations (beyond this reference implementation)

Things intentionally deferred, and what they'd take:

- **Repository split**: application, GitOps, and infrastructure as three
  repositories with independent access control, once the team is large
  enough that ownership boundaries matter more than clone/review
  simplicity.
- **ALB OIDC / Amazon Cognito** in front of `/nodes`, with the current
  application-level bearer-token check retained as defense in depth rather
  than the sole control.
- **AWS WAF** on the production ALB.
- **Custom-metric autoscaling** (request-rate or latency-based) via
  Prometheus Adapter or KEDA, layered on top of the current CPU-based HPA.
- **Cilium** (or another FQDN-aware CNI) to close the NetworkPolicy FQDN
  gap described in `docs/networking.md`, and optionally CNI-level or
  service-mesh mTLS for pod-to-pod encryption.
- **VPC endpoints** (S3, ECR, STS, Secrets Manager, CloudWatch) once NAT
  data-transfer cost justifies them (see `docs/cost.md`).
- **Warm-standby DR** in a secondary region if the business's RTO tolerance
  is tighter than the ~1–2 hours the current pilot-light model provides.
- **Credential rotation overlap windows** for any future downstream
  credential (e.g., a database) where the target system supports
  accepting old and new credentials simultaneously during rotation.
- **kube-prometheus-stack** as an always-on cluster component rather than
  an opt-in `make demo-observability` profile, once the team is running
  this beyond a local demo.
- **Velero** if/when the platform grows workloads with PersistentVolumes
  or a need for point-in-time cluster-object backups beyond what
  Git+Terraform+Flux already reconstruct.
