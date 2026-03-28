# Jenkins on EKS

Migrate Percona's 10 Jenkins masters from EC2 spot instances to a shared EKS cluster.

## Current state

3 Jenkins instances running on 1 EKS cluster in eu-central-1:

| Instance | Type | Storage | Status |
|----------|------|---------|--------|
| ps57-k8s | Cloned from live ps57 EBS | 100GB PV | Running, EC2 + Hetzner builds verified |
| ps57-2 | Cloned from live ps57 EBS | 100GB PV | Running |
| ps57-3 | Fresh (no cloned volume) | 20GB dynamic PVC | Running, all plugins from image |

Both EC2 and Hetzner worker builds succeed from EKS-hosted masters.

## Architecture

```
                     Internet
                         |
                   [ Shared ALB ]
              host-based routing, TLS 1.3
              *.cd.percona.com (ACM wildcard)
                         |
        +--------+-------+--------+
        |        |                |
    ps57-k8s   ps57-2          ps57-3
     (clone)   (clone)        (fresh)
        |        |                |
    100GB PV  100GB PV        20GB PVC
        |        |                |
        +--------+-------+--------+
                         |
           +-------------+-------------+
           |                           |
   [ EC2 workers ]           [ Hetzner workers ]
   (VPC peered to EKS)      nbg1/hel1/fsn1
```

All instances share one ALB (`group.name: jenkins-shared`), one EKS node, and one
IRSA service account. Each has its own Helm release, PVC, ConfigMaps, and DNS record.

## Docker image

Unified image: Jenkins 2.528.3 + 249 plugins (union of all 10 prod instances) + 2 Percona forks:

- `ec2:5.24.percona.2` (IRSA support via `fix/eks-irsa-support` branch, STS `tryCreateWebIdentityProvider`)
- `hetzner-cloud:103.percona.4` (retention robustness)

Built as `plugins.txt` + `percona-plugins/*.hpi` via Dockerfile. One image for all instances.

## Groovy scripts

Delivered via ConfigMap + initContainer. Persistent scripts are symlinked (run every startup),
one-time scripts are copied on first boot only (`.clone-initialized` flag).

| Category | Scripts | Lifecycle |
|----------|---------|-----------|
| Persistent | ec2-irsa-credential, fix-connection-strategy, fix-url | Symlinked, every startup |
| One-time | fix-auth (POC only), disable-crons | Copied on first boot, self-deletes |

## Deployment modes

- **POC mode** (default): local Jenkins auth with random password, disables crons. For testing.
- **Prod mode**: keeps existing Google/GitHub OAuth from cloned volume, only disables crons.

## Prerequisites

- AWS CLI with `percona-dev-admin` SSO profile
- `eksctl`, `kubectl`, `helm`, `just`, `docker`

## Usage

### Cluster (one-time)

```bash
just cluster-setup    # EKS cluster + IRSA + ALB controller + StorageClass
just image            # Build + push unified Docker image to ECR
```

### Cloned instance (from live Jenkins EBS volume)

```bash
just clone-instance <name> <source_vol_id> <jenkins_home_subpath>
just deploy-instance <name> [poc|prod]
```

### Fresh instance (no cloned volume)

Create a dynamic PVC manually, then:

```bash
just deploy-instance <name>
```

### Day-to-day operations

```bash
just update-groovy <name> [poc|prod]   # Update ConfigMaps + restart pod
just dns <name>                        # Create/update Route53 CNAME
just port-forward <name>               # Forward localhost:8080
just status                            # Show pods, PVCs, ingresses
just delete-instance <name>            # Helm uninstall (keeps PVC)
just clean                             # Delete entire EKS cluster
```

## EC2 plugin IRSA

The stock EC2 plugin uses IMDS (node role) for AWS credentials. On EKS, pods use IRSA
(web identity). The patched EC2 plugin (`fix/eks-irsa-support` branch) adds STS
`tryCreateWebIdentityProvider`. The `ec2-irsa-credential.groovy` persistent script flips
`useInstanceProfileForCredentials=false` after `cloud.groovy` runs at startup.

VPC peering between EKS VPC and the Jenkins worker VPC enables private IP SSH to workers
(set by `fix-connection-strategy.groovy`).

## Costs

| Component | Monthly |
|-----------|---------|
| EKS control plane | ~$73 |
| 1x t3.xlarge node | ~$120 |
| NAT Gateway | ~$32 |
| **Base (shared)** | **~$225** |
| ALB (shared, amortized) | ~$16 total |
| EBS per instance | ~$8 |
| **Per instance** | **~$8** |

10 instances on one cluster: ~$225 + 10x$8 = ~$305/mo vs ~$1,300/mo on EC2 spot.

## Medium-term vision

- Single EKS cluster per region (or single global cluster with public IP SSH)
- All 10 Jenkins masters migrated from EC2 spot to EKS on-demand
- One unified Docker image, one plugin set, no more snowflake configs
- Groovy scripts as ConfigMaps (persistent + one-time), managed via git
- ArgoCD for continuous delivery (Application per instance)
- Workers spawn in EKS VPC subnets directly (no more VPC peering)
- No more CloudFormation, no more 10 copies of UserData scripts
- Plugin changes via PR to `plugins.txt`, not manual UI installs

## Files

```
Dockerfile                           # Jenkins 2.528.3 + 249 plugins + 2 Percona forks
plugins.txt                          # Plugin manifest (249 plugins)
percona-plugins/                     # Custom .hpi files (gitignored)
eksctl-cluster.yaml                  # EKS cluster definition
gp3-storageclass.yaml                # EBS CSI StorageClass
iam-policy.json                      # IRSA policy (EC2 + Route53)
groovy/
  persistent/                        # Mounted via ConfigMap, every startup
    ec2-irsa-credential.groovy
    fix-connection-strategy.groovy
    fix-url.groovy
  one-time/                          # Copied on first boot, self-delete
    fix-auth.groovy
    disable-crons.groovy
instances/                           # Per-instance manifests
  <name>-pv.yaml
  <name>-values.yaml
justfile                             # All lifecycle recipes
docs/
  lessons-learned.md                 # POC findings and gotchas
```
