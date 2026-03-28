# Jenkins on EKS

Run Jenkins masters on EKS. Workers (EC2 + Hetzner) stay as-is.

## Architecture

```
                     Internet
                         |
                   [ ALB Ingress ]
                    :443 (ACM TLS)
                         |
        +----------------+----------------+
        |                                 |
[ Jenkins Pod A ]                [ Jenkins Pod B ]
   (ps57-k8s)                      (ps57-2)
        |                                 |
[ EBS PVC 100GB ]                [ EBS PVC 100GB ]
  (cloned volume)                  (cloned volume)
        |                                 |
        +----------------+----------------+
                         |
           +-------------+-------------+
           |                           |
   [ EC2 workers ]           [ Hetzner workers ]
   (VPC peered)              nbg1/hel1/fsn1
```

Multiple Jenkins instances share one EKS cluster. Each has its own Helm
release, PVC, ALB ingress, and DNS record.

## How groovy scripts work

Scripts are delivered via ConfigMaps, not kubectl cp.

| Category | Scripts | Lifecycle |
|----------|---------|-----------|
| Persistent | ec2-irsa-credential, fix-connection-strategy, fix-url | ConfigMap -> symlinked by initContainer -> runs every startup |
| One-time | fix-auth (POC), disable-crons | ConfigMap -> copied on first boot -> self-deletes |

The initContainer runs before Jenkins and:
1. Symlinks persistent scripts from ConfigMap into `init.groovy.d/`
2. Copies one-time scripts only if `.clone-initialized` flag is absent
3. Removes `matrix.groovy` on first boot (conflicts with POC auth)

## Prerequisites

- AWS CLI with SSO profile configured
- `eksctl`, `kubectl`, `helm`, `just`, `docker`

## Cluster setup (one-time)

```bash
just image            # Build + push Docker image to ECR
just cluster-setup    # EKS cluster + IRSA + ALB controller + StorageClass
```

## Adding a Jenkins instance

```bash
# 1. Clone the source Jenkins EBS volume
just clone-instance <name> <source_volume_id> <jenkins_home_subpath>
# Example:
just clone-instance ps57-3 vol-07070c2c983c2cc5f ps57.cd.percona.com

# 2. Deploy (creates ConfigMaps, PV/PVC, Helm release, DNS)
just deploy-instance <name> [poc|prod]
# Example:
just deploy-instance ps57-3 poc
```

POC mode: local Jenkins auth (random password printed), disable crons.
Prod mode: keeps existing auth (Google/GitHub OAuth), only disables crons.

## Updating groovy scripts

Edit scripts in `groovy/persistent/` or `groovy/one-time/`, then:

```bash
just update-groovy <name>    # Updates ConfigMaps and restarts pod
```

Persistent scripts re-run on every startup. One-time scripts only run if
`.clone-initialized` flag is absent (first boot).

## Other operations

```bash
just status                  # Show all pods, PVCs, ingresses
just dns <name>              # Create/update DNS record
just port-forward <name>     # Forward localhost:8080 to instance
just delete-instance <name>  # Helm uninstall + cleanup (keeps PVC)
just clean                   # Delete entire EKS cluster
```

## EC2 plugin IRSA support

The stock EC2 plugin uses IMDS (node role) for AWS credentials. On EKS, we
need IRSA (pod role). This requires:

1. Patched EC2 plugin (`fix/eks-irsa-support` branch in `nogueiraanderson/ec2-plugin`)
   which adds `tryCreateWebIdentityProvider()` using the STS SDK
2. `ec2-irsa-credential.groovy` persistent script which flips
   `useInstanceProfileForCredentials=false` after `cloud.groovy` runs
3. `fix-connection-strategy.groovy` which sets `PRIVATE_IP` connection
   (required for VPC peering between EKS and Jenkins worker VPCs)

## Costs (per cluster)

| Component | Monthly |
|-----------|---------|
| EKS control plane | ~$73 |
| 1x t3.xlarge node | ~$120 |
| NAT Gateway | ~$32 |
| ALB (per instance) | ~$16 |
| EBS 100GB gp3 (per instance) | ~$8 |
| **Base** | **~$225** |
| **Per instance** | **~$24** |

A shared cluster amortizes the base cost. 10 instances on one cluster:
~$225 + 10x$24 = ~$465/mo vs 10x$130 = $1,300/mo on EC2 spot.

## Files

```
Dockerfile                           # Jenkins 2.528.3 + 153 plugins + 2 Percona forks
plugins.txt                          # Plugin manifest
percona-plugins/                     # Custom .hpi files (gitignored)
eksctl-cluster.yaml                  # EKS cluster definition
gp3-storageclass.yaml                # EBS CSI StorageClass
iam-policy.json                      # IRSA policy (EC2 + Route53)
groovy/
  persistent/                        # Mounted via ConfigMap, every startup
    ec2-irsa-credential.groovy       # IRSA for EC2 plugin
    fix-connection-strategy.groovy   # PRIVATE_IP for VPC peering
    fix-url.groovy                   # Set Jenkins URL from env var
  one-time/                          # Copied on first boot, self-delete
    fix-auth.groovy                  # Local auth for POC
    disable-crons.groovy             # Remove cron triggers on clones
instances/                           # Generated per-instance manifests
  <name>-pv.yaml                     # PV/PVC
  <name>-values.yaml                 # Helm values
justfile                             # All lifecycle recipes
docs/
  lessons-learned.md                 # POC findings and gotchas
```
