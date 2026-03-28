# Jenkins Platform (EKS POC)

POC for migrating Percona's 10 Jenkins masters from EC2 spot instances to a shared EKS cluster. Production repo name: `Percona-Lab/jenkins-platform`.

## Architecture

- Single EKS cluster in eu-central-1, multiple Jenkins instances as Helm releases
- Shared ALB with host-based routing (`group.name: jenkins-shared`)
- ACM wildcard cert `*.cd.percona.com`, TLS 1.3 (`ELBSecurityPolicy-TLS13-1-2-2021-06`)
- IRSA for EC2 plugin (patched fork with STS `tryCreateWebIdentityProvider`)
- Groovy scripts via ConfigMap + initContainer (persistent: symlinked every startup; one-time: first boot only)
- VPC peering for private IP SSH to EC2 workers (production may use public IP SSH instead)

## Key Files

| File | Purpose |
|------|---------|
| `Dockerfile` | Jenkins 2.528.3 + 249 plugins + 2 Percona forks |
| `plugins.txt` | Union of all 10 prod instances (247 standard plugins) |
| `percona-plugins/` | Custom .hpi files (gitignored; download from GH releases) |
| `eksctl-cluster.yaml` | EKS cluster definition |
| `iam-policy.json` | IRSA policy (EC2 + Route53) |
| `gp3-storageclass.yaml` | EBS CSI StorageClass |
| `groovy/persistent/` | ConfigMap scripts: ec2-irsa, fix-connection-strategy, fix-url |
| `groovy/one-time/` | First-boot scripts: fix-auth (POC), disable-crons |
| `instances/<name>-values.yaml` | Per-instance Helm values |
| `instances/<name>-pv.yaml` | Per-instance PV/PVC |
| `justfile` | All lifecycle recipes |

## Justfile Recipes

Cluster (one-time): `just cluster-setup`, `just image`
Instance: `just clone-instance <name> <vol> <home>`, `just deploy-instance <name> [poc|prod]`
Operations: `just update-groovy <name>`, `just dns <name>`, `just status`, `just delete-instance <name>`

## Conventions

- All changes via code (values files, Helm upgrades, git commits). No manual kubectl annotate/patch.
- Persistent groovy scripts: no self-delete, run every startup after `cloud.groovy` (alphabetical order matters).
- One-time groovy scripts: self-delete after running, write `.clone-initialized` flag.
- `persistence.volumes` for ConfigMap mounts (not `extraVolumes`; init containers can't see extraVolumes).
- Docker image: always `--platform linux/amd64` (build host is arm64 m3, EKS nodes are amd64).
- Instance naming: `<original>-<suffix>.cd.percona.com` for POC, `<original>.cd.percona.com` for prod cutover.

## Related Repos

| Repo | Branch | Purpose |
|------|--------|---------|
| `nogueiraanderson/ec2-plugin` | `fix/eks-irsa-support` | IRSA support (STS dep + tryCreateWebIdentityProvider) |
| `nogueiraanderson/ec2-plugin` | `fix/crw-npe-guard` | NPE guards (v5.24.percona.2, deployed to fleet) |
| `nogueiraanderson/hetzner-cloud-plugin` | `fix/retention-robustness` | CRW fixes (v103.percona.4, deployed to fleet) |
| `Percona-Lab/jenkins-pipelines` | `master` | Pipeline code, cloud.groovy, job definitions |
| `Percona-Lab/jenkins-pipelines` | `hetzner` | Hetzner cloud.groovy templates |

## AWS Resources (POC)

| Resource | ID/Name | Region |
|----------|---------|--------|
| EKS cluster | jenkins-eks-poc | eu-central-1 |
| ECR repo | jenkins-percona | eu-central-1 |
| ACM cert | `*.cd.percona.com` | eu-central-1 |
| VPC peering | pcx-0992ce5143fb8fc72 | eu-central-1 |
| IAM policy | jenkins-eks-poc | global |
| Route53 zone | Z1H0AFAU7N8IMC | global |
| Billing tag | iit-billing-tag=jenkins-eks-poc | all resources |
