# Jenkins on EKS POC

Proof of concept: run Jenkins masters on EKS instead of bare EC2 spot instances.

## What this is

A lift-and-shift of the ps57 Jenkins instance to a single-node EKS cluster in eu-central-1. The existing EC2 and Hetzner worker fleets are unchanged; only the master moves to Kubernetes.

## Architecture

```
                     Internet
                         |
                   [ ALB Ingress ]
                    :443 (ACM TLS)
                         |
               [ Jenkins Pod 2.528.3 ]
                         |
                [ EBS PVC 100GB gp3 ]
                  (cloned from ps57)
                         |
           +-------------+-------------+
           |                           |
   [ EC2 workers ]           [ Hetzner workers ]
   eu-central-1b/c           nbg1/hel1/fsn1
```

## What's different from the EC2 setup

| Aspect | EC2 (current) | EKS (this POC) |
|--------|---------------|-----------------|
| TLS | OpenResty + certbot (per-instance) | ALB + ACM wildcard cert |
| Startup time | ~10 min (cloud-init + chown 100GB) | ~90s (pod start + plugin load) |
| Jenkins version | Hardcoded in CF UserData | Baked into Docker image |
| Plugins | Unmanaged (whatever is on EBS) | Pinned in plugins.txt + Dockerfile |
| Config changes | Survive (EBS volume) | Survive (EBS PVC, same model) |
| Workers | EC2 + Hetzner plugins | Same (unchanged) |
| Reverse proxy | OpenResty on the instance | ALB (managed by AWS) |

## Prerequisites

- AWS CLI with `percona-dev-admin` profile configured
- `eksctl`, `kubectl`, `helm`, `just`, `docker` installed
- Access to the `<account-id>` AWS account

## Quick start

```bash
# Full setup (builds image, creates cluster, deploys everything)
just all

# Or step by step:
just ecr-create      # Create ECR repo
just build           # Build Docker image
just push            # Push to ECR
just cluster         # Create EKS cluster (~15 min)
just iam             # Create IRSA service account
just acm             # Request and validate ACM certificate
just alb-controller  # Install AWS Load Balancer Controller
just deploy          # Deploy Jenkins via Helm
just dns             # Create Route53 CNAME
just configure       # Apply groovy init scripts and restart
```

## Data migration

The POC clones the live ps57 EBS volume via snapshot:

```bash
just snapshot-volume  # Snapshot vol, create new vol in eu-central-1b
# Edit ps57-pv.yaml with the output volume ID
kubectl apply -f ps57-pv.yaml
# Then deploy with persistence.existingClaim=ps57-jenkins-home
```

## Groovy init scripts

Scripts in `groovy/` are copied to `init.groovy.d/` on the Jenkins PVC. They run once on startup and self-delete.

| Script | Purpose |
|--------|---------|
| `fix-auth.groovy` | Switch to local Jenkins auth, disable anonymous access |
| `fix-url.groovy` | Set Jenkins URL to `ps57-k8s.cd.percona.com` |
| `disable-crons.groovy` | Remove all cron triggers (prevent conflicts with live ps57) |
| `ec2-irsa-credential.groovy` | Placeholder for EC2 IRSA credential setup (see known issues) |

## Access

- URL: `https://ps57-k8s.cd.percona.com`
- Auth: `admin` / `percona-eks-poc-2026` (local Jenkins auth)
- Jenkins CLI: `JENKINS_INSTANCE=ps57-k8s jenkins admin system`

## Known issues

**EC2 worker provisioning**: The EC2 plugin uses `InstanceProfileCredentialsProvider` which resolves to the EKS node IAM role, not the pod's IRSA role. The plugin's `AWSCredentialsImpl` does not support empty access keys (NPE on startup). Workaround options:

1. Attach the `jenkins-ps57-eks` policy to the EKS node instance role (quick but coarse)
2. Create a Jenkins credential with actual IAM access key/secret
3. Upstream fix: EC2 plugin to support `DefaultCredentialsProvider` (picks up IRSA)

**Hetzner workers**: fully functional, tested and verified.

## Costs

| Component | Monthly |
|-----------|---------|
| EKS control plane | ~$73 |
| 1x t3.xlarge node | ~$120 |
| NAT Gateway | ~$32 |
| ALB | ~$16 |
| EBS 100GB gp3 | ~$8 |
| **Total** | **~$250** |

Production could reduce costs with Spot nodes and a shared cluster for multiple Jenkins instances.

## Teardown

```bash
just clean  # Deletes Jenkins, ALB controller, and EKS cluster
```

## Files

```
Dockerfile              # Jenkins 2.528.3 + 153 plugins + 2 Percona forks
plugins.txt             # Plugin manifest (from live ps57)
percona-plugins/        # Custom .hpi files (gitignored, download from GH releases)
eksctl-cluster.yaml     # EKS cluster definition (single node, eu-central-1b)
cluster-issuer.yaml     # cert-manager ClusterIssuer (DNS-01 via Route53)
gp3-storageclass.yaml   # EBS CSI gp3 StorageClass
iam-policy.json         # IRSA policy (EC2 management + Route53)
jenkins-values.yaml     # Helm values (ALB ingress, ACM TLS, IRSA SA)
ps57-pv.yaml            # PV/PVC for cloned EBS volume
groovy/                 # Init scripts (auth, URL, crons, EC2 credential)
justfile                # All lifecycle recipes
```
