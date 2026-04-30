# 0008 — Managed NodeGroups for stateful system workloads

**Status:** Accepted (2026-04-30)

## Context

Three classes of pods need stable scheduling decisions independent of
Karpenter's spot-default consolidation:

- **kube-system + Karpenter controller + ArgoCD** — chicken-and-egg: Karpenter
  cannot schedule its own controller.
- **Prometheus / Alertmanager / Grafana** — stateful, gp3 EBS is zonal,
  Karpenter consolidation would churn the node and the pod would re-bind every
  time. "Stable, on-demand, not interrupted by spot."
- **Jenkins masters** — same zonality + churn-aversion as Prometheus, plus
  per-master sizing knobs and independent rolling-update cadence.

## Decision

Three EKS **managed NodeGroups**:

| NG | Capacity | AZ | Taint | Hosts |
|---|---|---|---|---|
| `system` | on-demand `t3.medium × 2` | multi-AZ | none | kube-system, Karpenter controller, ArgoCD, LB controller, external-dns, EBS-CSI controller |
| `prometheus-system` | on-demand `m6a.large × 1` | `us-east-1a` only | `workload=prometheus:NoSchedule` | kube-prometheus-stack pods (Prometheus / Alertmanager / Grafana) |
| `jenkins-system` | on-demand `m6a.xlarge × N` | `us-east-1a` only | `workload=jenkins:NoSchedule` | Jenkins master StatefulSets |

Karpenter's `default` NodePool excludes both stateful taints via `taints:
[{ key: workload, operator: NotIn, values: [prometheus, jenkins] }]`.

## Consequences

- Each stateful workload class has its own lifecycle: rolling-update one NG
  doesn't disturb the others. NG drain blast radius is one workload.
- AZ pinning (us-east-1a) for prometheus-system and jenkins-system is an
  accepted SPOF for v1 — gp3 is zonal, so multi-AZ HA needs EFS (slower for
  fsync-heavy Jenkins) or a leader-election pattern (overkill). See
  `docs/observability.md` and `docs/runbooks/restore-prometheus.md` for the AZ-
  outage recovery plan.
- Karpenter's spot fleet still serves everything else (proxy NGINX, future
  workloads). Costs stay bounded.
- Rejected: a Karpenter `system` NodePool. Premature abstraction — the managed
  NG already covers controller bootstrap.
