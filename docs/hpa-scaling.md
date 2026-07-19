# HPA, resources, PDB, and topology spread

## HPA

CPU-based `autoscaling/v2` HorizontalPodAutoscaler
(`helm/node-api/templates/hpa.yaml`). Production example:
`minReplicas: 3`, `maxReplicas: 10`, target CPU ~70%, with a 300s
scale-down stabilization window to reduce flapping.

CPU **requests are mandatory** — HPA utilization is calculated relative to
requests, not limits, so an unset request makes the target percentage
meaningless.

`Deployment.spec.replicas` is **omitted** from the template whenever
`autoscaling.enabled: true`
(`{{- if not .Values.autoscaling.enabled }} replicas: ... {{- end }}`).
Git defines the autoscaling *policy* (min/max/target); the HPA controller
owns the *live* replica count. If both Git and the HPA tried to own
`replicas`, every HPA scaling event would immediately be fought by the
next Flux reconciliation reverting it back to the Git-defined value.

Request-rate or latency-based autoscaling (Prometheus Adapter or KEDA) is
a documented production enhancement, not implemented — CPU-only is simpler
to demonstrate and sufficient for this workload's actual behavior (a thin
I/O-bound proxy in front of the Kubernetes API).

## Resource requests and limits

Every container defines all four values. Starting point (tune from
observed usage):

```yaml
requests: { cpu: 100m, memory: 128Mi }
limits:   { cpu: 500m, memory: 256Mi }
```

## PodDisruptionBudget — environment-specific, not copy-pasted

A production PDB (`minAvailable: 2`, alongside `HPA minReplicas: 3`) would
silently break a one-replica dev environment: any `minAvailable >= 1` PDB
blocks voluntary node drains and Karpenter consolidation when there's only
one pod to disrupt. So PDB is env-specific
(`helm/node-api/templates/pdb.yaml`, gated by `pdb.enabled`):

| Environment | PDB |
|---|---|
| dev | disabled |
| staging | `maxUnavailable: 1` |
| production | `minAvailable: 2` (with `HPA minReplicas: 3`, this permits one voluntary disruption at baseline while keeping two pods serving) |

## Topology spread

Soft spreading across Availability Zones and Kubernetes nodes
(`whenUnsatisfiable: ScheduleAnyway`) — Kubernetes prefers distribution but
allows co-location when capacity is constrained. Availability (the pod
actually scheduling) is prioritized over perfect spread. Enabled in
staging and production, not dev (single replica makes it moot).

## Deployment update strategy

`RollingUpdate` with `maxSurge: 1, maxUnavailable: 0` — a new pod must
become Ready before an old one is removed, so a rollout never reduces
serving capacity. `terminationGracePeriodSeconds: 30` plus a `preStop`
sleep gives in-flight requests time to complete and lets the endpoint
controller remove the pod from Service routing before Uvicorn stops
accepting connections. See `helm/node-api/templates/deployment.yaml`.

One Uvicorn worker per pod — horizontal scaling happens via HPA replica
count, not multiple in-process workers, which keeps CPU-based HPA behavior
straightforward to reason about (worker count doesn't confound the CPU
metric).
