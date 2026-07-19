# Interview presentation flow

A timed walkthrough for presenting this submission, built to mirror the
assignment's evaluation weights rather than treat every doc as an equal
stop. Total: ~20 minutes, adjustable — cut the monitoring section first if
short on time, never cut security/RBAC.

| Section | Time | Evaluation area | Weight |
|---|---|---|---|
| 1. Framing | 1 min | — | — |
| 2. Architecture (both diagrams) | 3 min | Production architecture judgment | 15% |
| 3. Kubernetes implementation (live demo) | 6 min | Kubernetes implementation quality | 25% |
| 4. GitOps and CI/CD | 4 min | GitOps and CI/CD design | 20% |
| 5. Security, secrets, RBAC | 4 min | Security, secrets, and RBAC | 20% |
| 6. Monitoring and logging | 1 min | Monitoring and logging approach | 10% |
| 7. Trade-offs and close | 2 min | Trade-offs and engineering judgment; docs/communication | 5% + 5% |

Time spent roughly tracks grading weight — six minutes on Kubernetes and
four each on GitOps and security is not accidental; monitoring gets one
minute because it's 10% and the working piece (`/metrics` + gated
`ServiceMonitor`) is simple to state.

## 1. Framing (1 min)

One sentence: a FastAPI service (`/health`, `/nodes`, `/metrics`) deployed
via Helm + Flux to a local kind cluster, with the AWS production design
fully specified in Terraform but not applied. State the demo contract up
front: "everything you're about to see is running live, not slides."

## 2. Architecture (3 min)

Open `docs/architecture-local.md` and `docs/architecture-aws.md` side by
side. Walk the local diagram first (what's actually running), then the AWS
diagram, and explicitly name the five things that differ between them
(git source, registry, ingress, secrets backend, node provisioning — see
the comparison table in `architecture-local.md`). This preempts "wait, is
any of this real?" — the answer is: the mechanics are identical, only
AWS-specific infrastructure differs, and that's a values file, not a
different chart.

## 3. Kubernetes implementation — live demo (6 min)

**Primary path:** run `make demo` live (5–10 min build time — start it
*before* framing/architecture if the room allows, so it's ready by the
time you get here).

**Fallback if live demo fails or the room has no Docker/network:** every
verification run was logged. Have `/tmp/bootstrap-final.log` (or
whichever timestamped log survived) open in a second terminal tab, plus
this transcript's own record of clean end-to-end passes — including one
against the *actual* GitHub repo (`GIT_SOURCE=github`), not just the local
Gitea substitute. State this plainly rather than pretending the live run
is the only evidence: "this exact flow passed repeatedly overnight,
here's the log if this run has a hiccup."

While it builds, narrate what's about to happen: Calico installs first
(kindnet doesn't enforce `NetworkPolicy` — the whole security story
depends on a real CNI), then Flux, then Flux takes over everything else.

Once up, show, in order:
1. `kubectl get pods -A` across `node-api-{dev,staging,production}` — one
   Helm chart, three namespaces, different HPA/PDB/replica behavior per
   environment (dev has neither; staging/production do).
2. `./scripts/test-network-policies.sh` — narrate that this *asserts*
   NetworkPolicy is enforced, not just applied; it was the source of two
   real bugs (see section 7's AI-assisted-work note).
3. `curl -H 'Host: dev.node-api.local' .../nodes` without and with a
   bearer token — 401, then real node data with `current_node: true`
   correctly marking the pod's own node via the Downward API.

## 4. GitOps and CI/CD (4 min)

Open `docs/gitops.md`'s Flux resource graph. State the two documented
exceptions to "Flux is the only deployer" (CNI, Flux itself) — an
interviewer will ask why kubectl-apply-in-a-script isn't a contradiction
of the GitOps promise, and the answer needs to be immediate: neither can
exist before pod networking exists, so nothing else could deploy them
either.

Then walk `.github/workflows/ci.yaml` → `release.yaml`: build-once,
promote-by-digest, GitHub App not a PAT, CI never gets cluster-admin. If
asked "why not Flux Image Automation" — considered and rejected
(`docs/gitops.md`), CI-driven updates keep the approval chain explicit.

## 5. Security, secrets, RBAC (4 min)

This is 20% of the grade and the most concrete area to demonstrate — lead
with code, not prose:

- `helm/node-api/templates/rbac.yaml` — `verbs: ["list"]` only, no
  `get`/`watch`, ClusterRoleBinding scoped to one ServiceAccount.
- `helm/node-api/templates/securitycontext` fields in `deployment.yaml` —
  non-root, read-only rootfs, all capabilities dropped, seccomp
  RuntimeDefault. Then `policies/kyverno/enforce/pod-security-baseline.yaml`
  — the same properties, enforced independently by admission control, not
  just requested in the chart. Run `make kyverno-test` live if time
  allows — 9 assertions, both compliant and non-compliant pods.
- `docs/secrets.md`'s flow diagram — ESO, per-namespace `SecretStore`,
  per-namespace IAM role via IRSA, path-scoped Secrets Manager policy.
  Name the local substitution honestly: kind uses ESO's `kubernetes`
  provider (a real Secret standing in for Secrets Manager), production
  manifests use the real `aws` provider — same ESO mechanics either way.

## 6. Monitoring and logging (1 min)

`/metrics` on its own port (9000, not 8000) so NetworkPolicy can restrict
scraping without exposing it publicly — this is the one detail worth
lingering on, since it's a design choice, not a default. Everything else
(`docs/monitoring.md`) is one sentence: gated `ServiceMonitor`,
`make demo-observability` for the full stack, structured JSON logs, seven
documented alert rules including two for Flux's own reconciliation
failures.

## 7. Trade-offs and close (2 min)

State three trade-offs out loud, not just "read the docs" — pick from
`docs/assumptions-and-limitations.md`:
- Monorepo now, three-repo split documented for production.
- Rebuild-from-code DR (lower cost, ~1–2h RTO) over a warm standby.
- CPU-only HPA now, request-rate/latency-based documented as the next step.

### On AI-assisted work

Answer this directly, don't wait to be asked. This was built with Claude
Code overnight, and the honest, defensible framing is:

- **What AI did:** generated the initial implementation across every
  layer (app, Helm, GitOps, Kyverno, CI, Terraform, docs) from a detailed,
  pre-written decisions document.
- **What required actual verification, not trust:** *every* piece was run
  against a live kind cluster repeatedly, and that verification surfaced
  real bugs a code-review-only pass would have missed — a Flux
  Kustomization circular dependency deadlock, a missing `kubectl apply`
  line, a wrong resource name in a wait command, 2GB of Terraform
  binaries accidentally swept into a git push, a missing field on an ESO
  `SecretStore` causing silent auth failure, a timing race between a
  Kustomization reporting Ready and Helm actually finishing, a missing
  namespace, and a `pipefail` bug in a test script that made a *correct*
  NetworkPolicy check report as failing.
- **The takeaway to state plainly:** none of those bugs were guessable
  from reading the YAML — each one only showed up by actually running it,
  which is the same standard this work would be held to if a human wrote
  it. Be ready to walk through any one of them in detail if asked — the
  ESO `caProvider.key` bug and the `pipefail` bug are the best two to have
  ready, since they're genuinely subtle and demonstrate debugging
  methodology, not just "AI wrote it, it worked."

## Anticipated hard questions (have one-liners ready)

| Question | One-liner | Full answer |
|---|---|---|
| Why Kyverno over OPA/Gatekeeper? | Kubernetes-native YAML policies, no separate Rego language to maintain | `docs/policy.md` |
| Why not Kustomize? | Adds a tool with insufficient value for one chart, three environments | decisions doc §6 |
| Why monorepo for the submission? | Reviewer friction; three-repo split is the documented production model | `docs/gitops.md` |
| Why CPU-only HPA? | Simple, demonstrable now; request-rate/latency is a named next step | `docs/hpa-scaling.md` |
| Why rebuild-from-code DR, not warm standby? | Cost vs. ~1–2h RTO trade-off, explicit | `docs/disaster-recovery.md` |
| Isn't "Flux is the only deployer" broken by the bootstrap script? | No — CNI and Flux itself can't be deployed by Flux before they exist; two documented, unavoidable exceptions | `docs/gitops.md` |
| Why GHCR for the demo instead of ECR? | Free, works for both CI and kind without AWS; ECR is the documented AWS target | `docs/ci-cd.md` |
| What's fake vs. real in the local demo? | Git source (Gitea, verified against real GitHub too) and secrets backend (`kubernetes` ESO provider); everything else — RBAC, NetworkPolicy, Kyverno, HPA, PDB — is the real mechanism | `docs/architecture-local.md` |
