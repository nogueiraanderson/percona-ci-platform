# percona-ci-platform

Public OpenTofu + ArgoCD platform repo that provisions an EKS cluster in
`us-east-1` and bootstraps it via GitOps. Initial workload: terminate SSL
for `*.cd.percona.com` on a single shared ALB, reverse-proxy the existing
EC2 Jenkins masters, and run the first in-cluster replica
(`ps3-k8s.cd.percona.com`, seeded from production ps3) alongside them.

The repo lives initially under `nogueiraanderson` and will move to
`Percona-Lab/` once it's stable.

## Architecture

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

- **Terraform/OpenTofu** owns AWS-side state up to "ArgoCD healthy."
- **ArgoCD** owns everything in-cluster from there (App-of-Apps, ApplicationSets, sync waves).
- **Karpenter** scales the spot-default workload NodePool; on-demand managed NGs host stateful workloads (`prometheus-system`, `jenkins-system`).
- **kube-prometheus-stack** scrapes the Jenkins fleet (incl. Hetzner / EC2 plugin metrics, gated on PS-10543/996/997) and exposes Grafana on the same ALB.

## Repo layout

| Path | Owner | What |
|---|---|---|
| `terraform/` | OpenTofu | VPC, EKS, addons, Pod Identity, ACM, ArgoCD bootstrap, AWS Backup |
| `argocd-bootstrap/` | ArgoCD | Root App-of-Apps + ApplicationSets that reconcile `resources/` |
| `resources/` | ArgoCD-driven | Helm umbrella charts for addons + Jenkins masters + fleet monitoring |
| `image/` | Docker build | Jenkins 2.x + 249 plugins + 2 Percona forks |
| `scripts/` | Helpers | `check_versions.py` and other one-shots |
| `docs/` | Markdown | Architecture, runbooks, ADRs, lessons-from-PoC |
| `.github/workflows/` | CI | Lint + validate only — no plan, no deploy |

## Quickstart

Local validation:
```
just ci
```

Plan + apply:
```
export AWS_PROFILE=<your-profile>      # or copy terraform/local.auto.tfvars.example
just tf-plan
just tf-apply
```

State bucket + lock are pre-created — see [`docs/runbooks/bootstrap-state.md`](docs/runbooks/bootstrap-state.md).

## Versions

Source of truth: [`terraform/versions.tf`](terraform/versions.tf). Verify
with [`scripts/check_versions.py`](scripts/check_versions.py) before any
PR that touches a pin.

| Component | Pin | Verified |
|---|---|---|
| OpenTofu | 1.11.6 | 2026-04-08 |
| EKS | 1.35 (default, EOS 2027-03-27) | aws eks describe-cluster-versions |
| terraform-aws-modules/vpc | 6.6.1 | 2026-04-02 |
| terraform-aws-modules/eks | 21.19.0 | 2026-04-27 |
| terraform-aws-modules/iam | 6.6.0 | 2026-04-29 |
| terraform-aws-modules/eks-pod-identity | 2.8.0 | 2026-04-25 |
| terraform-aws-modules/acm | 6.3.0 | 2026-01-08 |
| ArgoCD chart | 9.5.9 | 2026-04-29 |
| AWS LB Controller chart | 3.2.2 | 2026-04-29 |
| external-dns chart | 1.21.1 | 2026-04-30 |
| Karpenter | 1.12.0 | 2026-04-24 |
| kube-prometheus-stack | 84.4.0 | 2026-04-29 |

## Status

`rewrite/percona-ci-platform` branch is the incumbent. The previous private
PoC (single-node eksctl in eu-central-1) lives in this repo's history; key
learnings are in [`docs/lessons-from-poc.md`](docs/lessons-from-poc.md) and
[`docs/poc-history.md`](docs/poc-history.md).

## Contributing

- `just ci` must pass before PR.
- Pre-commit hooks mirror CI ([`.pre-commit-config.yaml`](.pre-commit-config.yaml)).
- ADRs in [`docs/adr/`](docs/adr/) — propose architecture changes there first.
- Commit format: `type(scope): subject` (no AI footers).

## License

Apache-2.0.
