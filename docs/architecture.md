# Architecture

## One-screen view

```
                          *.cd.percona.com
                                 │
                                 ▼
                       ALB :443 (ACM wildcard)
                ┌─── Ingress group jenkins-cd ───┐
                │                                │
        Mode A (in-cluster)               Mode B (proxy → EC2)
                │                                │
                ▼                                ▼
        StatefulSet jenkins-<host>      Deployment jenkins-proxy-<host>
        (NodePool jenkins-system,                  │
         AZ us-east-1a, gp3 PVC)                   ▼
                                          origin-<host>.cd.percona.com
                                                   │
                                                   ▼
                                          EC2 Jenkins master (other region)
```

## Ownership boundary

- **Terraform / OpenTofu** owns AWS-side state up to "ArgoCD healthy."
- **ArgoCD** owns everything in-cluster from there. App-of-Apps + ApplicationSets reconcile from `resources/`.
- **The cluster Secret** (`argocd.argoproj.io/secret-type: cluster`) carries TF outputs (cluster name, OIDC, role ARNs, ACM ARN, Karpenter SQS) as annotations. ApplicationSets read those annotations as Helm `valuesObject`.

## NodeGroups

| NG | Capacity | AZ | Taint | Hosts |
|---|---|---|---|---|
| `system` | on-demand (`t3.medium × 2`) | multi-AZ | none | kube-system DaemonSets, Karpenter controller, ArgoCD, LB Controller, EDNS, EBS-CSI |
| `prometheus-system` | on-demand (`m6a.large × 1`) | us-east-1a | `workload=prometheus:NoSchedule` | kube-prometheus-stack pods |
| `jenkins-system` | on-demand (`m6a.xlarge × N`) | us-east-1a | `workload=jenkins:NoSchedule` | Jenkins master StatefulSets |
| Karpenter NodePool `default` | spot + on-demand fallback | multi-AZ | (excludes both stateful taints) | Everything else (jenkins-proxy NGINX Deployments, future workloads) |

## Storage

| StorageClass | Default | AZ | Reclaim | Used by |
|---|---|---|---|---|
| `gp3` | yes | multi-AZ | Delete | Generic workloads |
| `gp3-monitoring-1a-retain` | no | us-east-1a | Retain | Prometheus, Alertmanager, Grafana |
| `gp3-jenkins-1a-retain` | no | us-east-1a | Retain | Jenkins master JENKINS_HOME PVCs |

## Sync waves (ArgoCD)

| Wave | Addon | Reason |
|---|---|---|
| 0 | `storageclass-gp3` | Required before any PVC binds |
| 0 | `external-secrets` | Token + secret sync for everything downstream |
| 1 | `aws-load-balancer-controller` | Ingresses need it |
| 2 | `external-dns` | Needs LB Controller to publish ALB endpoints |
| 3 | `karpenter` | After LB controller |
| 4 | `kube-prometheus-stack` | Last — everything it scrapes is up |

`cert-manager` is intentionally not in v1 — see `docs/adr/0007-cert-manager-deferred.md`.

## Detailed docs

- [`connectivity.md`](connectivity.md) — public path vs PrivateLink upgrade
- [`tls-strategy.md`](tls-strategy.md) — ACM wildcard + per-Ingress ssl-policy
- [`pod-identity.md`](pod-identity.md) — five associations + agent addon
- [`argocd-bootstrap.md`](argocd-bootstrap.md) — GitOps Bridge mechanics
- [`karpenter.md`](karpenter.md) — NodePool tuning, spot fallback, taint exclusion
- [`observability.md`](observability.md) — kube-prometheus-stack values, AZ pinning, remote-write upgrade path
- [`jenkins-fleet-scrape.md`](jenkins-fleet-scrape.md) — Probe / additionalScrapeConfigs / bearer-token / Option A→B migration
- [`lgtm-evaluation.md`](lgtm-evaluation.md) — why LGTM is deferred
- [`lessons-from-poc.md`](lessons-from-poc.md) — verbatim lift from the prior PoC

## Runbooks

- [`runbooks/bootstrap-state.md`](runbooks/bootstrap-state.md) — recreate the S3 + DynamoDB state backend from scratch
- [`runbooks/eks-upgrade.md`](runbooks/eks-upgrade.md) — minor version bump procedure
- [`runbooks/migrate-ps3-to-eks.md`](runbooks/migrate-ps3-to-eks.md) — cross-region EBS snapshot lift
- [`runbooks/restore-prometheus.md`](runbooks/restore-prometheus.md) — EBS snapshot restore drill

## ADRs

Decision history lives in [`adr/`](adr/). Each architecture choice has a one-page record.
