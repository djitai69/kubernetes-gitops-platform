# Networking, ingress, DNS, TLS, and encryption (AWS production design)

## Public/private model

```
VPC (3 AZs)
├── Public subnets
│   ├── Internet-facing ALB
│   ├── NAT gateway(s)
│   └── Internet gateway route
└── Private subnets
    ├── EKS managed node group (platform)
    ├── Karpenter-provisioned nodes (application workloads)
    ├── Application pods
    └── Platform controllers (Flux, Kyverno, ESO, ...)
```

- **Non-production**: single NAT gateway (cost trade-off — see
  `docs/cost.md`), one shared ALB for dev+staging (host-based routing), EKS
  private endpoint enabled with the public endpoint optionally and
  temporarily open (CIDR-restricted) for bootstrap only.
- **Production**: one NAT gateway per AZ, one dedicated ALB, **private-only**
  EKS API endpoint. Administrative access is via VPN, a private CI runner,
  or SSM Session Manager — never a public CIDR allowlist.
- Nodes and pods never sit in public subnets in either environment.

## Ingress, DNS, TLS

- AWS Load Balancer Controller provisions ALBs from Ingress resources
  (`ingress.className: alb` in Helm values), `alb.ingress.kubernetes.io/target-type: ip`.
- HTTPS-only listeners; HTTP redirects to HTTPS.
- ACM issues and manages certificates.
- Route 53 hosts the zone (created/referenced by Terraform);
  [ExternalDNS](https://github.com/kubernetes-sigs/external-dns) — deployed
  by Flux, authenticated via IRSA, IAM scoped to only the relevant hosted
  zone — creates/updates records from Ingress resources, keeping DNS
  GitOps-aligned instead of a separate manual step.
- Separate security groups for non-production and production ALBs/nodes.
- AWS WAF in front of the ALB is a documented production recommendation,
  not implemented in this reference (see `docs/production-recommendations.md`).
- Non-production is **not** openly exposed by default — internal ALB where
  private connectivity exists, or IP allowlisting via ALB/security-group
  rules otherwise.

## NetworkPolicy

Default-deny ingress and egress in every application namespace, with
narrow explicit allows (ingress from the ingress controller only, DNS to
CoreDNS, Kubernetes API egress, metrics scraping restricted to the
monitoring namespace). See `helm/node-api/templates/networkpolicy.yaml`.

Standard Kubernetes `NetworkPolicy` cannot target FQDNs or match on the
control-plane endpoint by DNS name — AWS egress uses the VPC/control-plane
CIDR instead, which is a documented limitation. A CNI with FQDN-aware
policy (Cilium) is a production enhancement for tightening this further.

The **local kind demo** hits the same limitation for a different reason:
kind's `kubernetes.default` Service DNATs port 443 to the control-plane
container's port 6443 before policy evaluation, so the local NetworkPolicy
values allow both ports plus a discovered/broad CIDR
(`networkPolicy.kubernetesApi.cidr`), while AWS values set a real
VPC/control-plane CIDR explicitly. See
`helm/node-api/templates/networkpolicy.yaml` for the exact rule and
`scripts/test-network-policies.sh` for the live verification.

Calico's Felix dataplane agent takes a few seconds to program iptables
after a `NetworkPolicy` is created — a probe run immediately after rollout
can observe stale (not-yet-enforced) behavior. `test-network-policies.sh`
retries each assertion (up to 5 attempts, 3s apart) before treating a
result as authoritative, rather than trusting a single immediate probe.

## Encryption

**At rest:**
- Terraform state: S3 bucket with versioning + KMS (customer-managed key)
  server-side encryption, public access blocked.
- EKS: Kubernetes Secrets envelope-encrypted with a dedicated KMS key
  (`infra/modules/eks/main.tf`, `aws_kms_key.eks_secrets`).
- EBS volumes/snapshots: encrypted (EBS CSI driver default + AMI setting).
- ECR: encrypted with a dedicated KMS key.
- Secrets Manager: KMS-encrypted.
- CloudWatch Logs / S3 audit archives: encrypted.

**In transit:**
- TLS from client to ALB (ACM-issued certs, HTTPS-only listeners).
- HTTPS for Git, container registry, AWS API, and EKS API traffic.
- Pod-to-pod traffic is **not** assumed encrypted by default — a service
  mesh (mTLS) or CNI-level encryption (Cilium WireGuard/IPsec) is a
  documented production enhancement, not implemented here.
