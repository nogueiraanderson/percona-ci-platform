# percona-ci-platform — Claude Code project instructions

OpenTofu + ArgoCD platform repo. EKS in `us-east-1`, GitOps-bootstrapped. Public, owned by `nogueiraanderson` (will move to `Percona-Lab/`).

Full architecture: see [`README.md`](README.md). Authoritative plan: private at `~/.claude/plans/spicy-prancing-nebula.md`.

## Conventions (carried forward from PoC, hard-won)

- **All changes via code.** No manual `kubectl annotate`, `kubectl patch`, or Script Console mutations. Drift between git and cluster breaks GitOps.
- **Persistent groovy scripts** (`image/groovy/persistent/`) run every Jenkins startup after `cloud.groovy`. Alphabetical order matters — prefix with `e-` to run after `c-cloud.groovy`.
- **One-time groovy scripts** (`image/groovy/one-time/`) self-delete after running, write `.clone-initialized` flag.
- **`persistence.volumes`, not `extraVolumes`** for ConfigMap mounts. Init containers can't see `extraVolumes`.
- **Docker image:** always `docker buildx build --platform linux/amd64 --push`. Build host (m3) is arm64, EKS nodes are amd64.
- **Public repo:** no AWS account IDs / ARNs / secrets in `.tfvars` or values files. All sensitive bits flow via `var.account_id`, cluster-secret annotations, or AWS Secrets Manager → External Secrets Operator.
- **TLS policy:** every ALB Ingress sets `alb.ingress.kubernetes.io/ssl-policy: ELBSecurityPolicy-TLS13-1-2-2021-06`. Defaults allow TLS 1.0/1.1.
- **Shared ALB:** every Jenkins host Ingress carries `alb.ingress.kubernetes.io/group.name: jenkins-cd`.
- **Pre-commit + CI:** `just ci` is the gate. Same set runs on PR.

## Module + chart pins

Source of truth: `terraform/versions.tf` (`local.modules` and `local.charts`).
Verify with `scripts/check_versions.py` before any pin bump.

## Hot-button gotchas

1. **EKS extended support.** Standard support: 1.33 / 1.34 / **1.35 (default)**. Picking 1.32 or below incurs paid extended-support fees.
2. **EBS-CSI volume zonality.** EBS is per-AZ. StatefulSets that need volume-follows-pod must pin to one AZ via `nodeSelector` + StorageClass `allowedTopologies`. Multi-AZ HA needs EFS (slower).
3. **Pod Identity needs the agent.** `eks-pod-identity-agent` managed addon is mandatory; without it every association silently no-ops.
4. **EC2-plugin IRSA classloader bug.** Jenkins EC2 plugin (AWS SDK v1) has classloader isolation that breaks `DefaultCredentialsProvider`. Patched fork `ec2:5.24.percona.2` + `e-ec2-irsa-credential.groovy` are the only working path. Pod Identity *should* fix it transparently — verify on the ps3 PoC before claiming so.
5. **Karpenter taint exclusion.** Stateful NGs (`prometheus-system`, `jenkins-system`) carry `workload=<x>:NoSchedule`. Default Karpenter NodePool must `NotIn` that taint.

## Related repos

| Repo | Purpose |
|---|---|
| `Percona-Lab/jenkins-pipelines` | Jenkins pipeline code, cloud.groovy, job definitions (master + hetzner branches) |
| `nogueiraanderson/hetzner-cloud-plugin` | Patched Hetzner plugin (`v103.percona.7` — DC breakers, type fallback, in-progress Prom metrics for PS-10997) |
| `nogueiraanderson/ec2-plugin` | Patched EC2 plugin (`v5.24.percona.2` — IRSA classloader fix, NPE guards) |

## Skill loading reminders

When working in this repo, prefer:
- `tofu` (not `terraform`) — see global CLAUDE.md OpenTofu rules.
- `paws` for AWS lookups (load `/paws` skill first), not raw `aws` ad-hoc.
- `jenkins` CLI for Jenkins fleet ops (load `/percona-jenkins` first).
