# Lessons Learned from the POC

Based on the ps57 lift-and-shift (2026-03-28).

## What was easy

**EKS cluster**: one YAML file, `eksctl create cluster`, 15 minutes. Managed
node group, EBS CSI driver, OIDC provider all handled automatically.

**Docker image**: `Dockerfile` + `plugins.txt` generated from the live instance.
Build in minutes. All 155 plugins (including 2 Percona forks) baked in. No more
unmanaged plugins on EBS volumes.

**Data migration**: snapshot the existing EBS volume, create a new volume from
the snapshot, mount as a PVC. Jenkins starts with the exact same jobs,
credentials, and build history. Zero data loss.

**Hetzner workers**: connected back to the EKS-hosted Jenkins via JNLP with no
changes. The Hetzner cloud plugin, templates, and init scripts all worked as-is.
First test build completed in 108 seconds.

**TLS**: ALB + ACM wildcard cert (`*.cd.percona.com`). No OpenResty, no certbot,
no DH params, no renewal cron. Certificate auto-renews. One cert covers all
future Jenkins instances on the cluster.

**Startup time**: ~90 seconds from pod creation to "Jenkins is fully up and
running". Compared to 10+ minutes on EC2 (cloud-init + yum install + chown
100GB + nginx setup + certbot).

## What was painful

### EC2 plugin and IRSA (blocker)

The EC2 plugin (`hudson.plugins.ec2`) with `useInstanceProfileForCredentials=true`
uses `InstanceProfileCredentialsProvider`, which calls EC2 instance metadata
(IMDS). On EKS pods, IMDS resolves to the **node instance role**, not the pod's
IRSA role.

Setting `useInstanceProfileForCredentials=false` with a blank `credentialsId`
does not fall through to `DefaultCredentialsProvider` (which would pick up
IRSA). Instead, the plugin requires a `credentialsId` referencing an
`AWSCredentialsImpl` credential.

`AWSCredentialsImpl` with empty access key/secret throws
`NullPointerException: Credentials must not be null` on startup, causing a crash
loop.

**Workaround options (in order of preference):**

1. **Patch the EC2 plugin** to use `DefaultCredentialsProvider` when no
   credential is specified. We already maintain a fork (`ec2:5.24.percona.2`);
   this would be a small change in `EC2Cloud.java`
2. **Create a dedicated IAM user** with access key/secret, store as a Jenkins
   credential. Works today but requires key rotation
3. **Attach the policy to the EKS node role**. Quick but breaks pod-level
   isolation (all pods on the node get EC2 permissions)

### OAuth callback mismatch

The cloned volume had Google OAuth and GitHub OAuth configured with callback
URLs for `ps57.cd.percona.com`. Jenkins at `ps57-k8s.cd.percona.com` can't
complete the OAuth flow. Had to switch to local Jenkins auth for the POC.

**For production**: add the new domain to the OAuth app's authorized redirect
URIs before cutover.

### init.groovy.d script ordering

Scripts in `init.groovy.d/` run in alphabetical order. The cloned volume's
`matrix.groovy` (GlobalMatrixAuthorizationStrategy) ran after `fix-auth.groovy`,
overwriting the auth changes. Had to remove `matrix.groovy` from the PVC.

**Lesson**: when cloning a volume, audit all `init.groovy.d/` scripts. Some
may conflict with the new environment. Use `z-` prefix for scripts that must
run last, or remove conflicting scripts before first boot.

### Credential crash loop

An `AWSCredentialsImpl` with empty access key was saved to `credentials.xml`
via the Script Console. On the next restart, Jenkins failed to deserialize it
(NPE) and entered a crash loop. The Jenkins container couldn't start, so
Script Console was unavailable.

**Fix**: scaled the StatefulSet to 0, mounted the PVC with a debug pod, edited
`credentials.xml` and `config.xml` directly, scaled back to 1.

**Lesson**: never save credentials via Script Console without testing a restart
first. Have a recovery procedure ready (debug pod + PVC editing).

### Docker image architecture

The remote Docker host (dm3) runs on arm64. The default `docker build` produced
an arm64 image. The EKS node (`t3.xlarge`) is amd64. The image pulled
successfully but failed with "no match for platform in manifest".

**Fix**: `docker buildx build --platform linux/amd64 --push`. Cross-platform
build via QEMU emulation is slow (~5 min for plugin installation under
emulation).

**Lesson**: always specify `--platform` when the build host and target differ.
Or use a multi-arch build.

## Production rollout considerations

### Per-instance migration

Each Jenkins instance needs:
- Its own `jenkins-values.yaml` (hostname, JVM opts, executor count)
- Its own EBS volume clone (snapshot + PVC)
- OAuth callback URLs updated before DNS cutover
- Audit of `init.groovy.d/` scripts for environment-specific assumptions

### EC2 plugin fix (prerequisite)

All 10 instances use EC2 workers. The IRSA credential gap must be resolved
before any production migration. Recommended: patch the Percona EC2 plugin fork
to support `DefaultCredentialsProvider`.

### Shared vs dedicated clusters

The POC uses a dedicated single-node cluster ($250/mo). For production:
- **Shared cluster**: all 10 Jenkins masters on one EKS cluster. EKS control
  plane cost ($73/mo) is amortized. Node group scales based on total resource
  demand. Risk: blast radius (cluster issue affects all instances)
- **Dedicated clusters**: one cluster per instance. Higher cost ($73/mo each)
  but full isolation. Same as current EC2 model

Recommended: start with a shared cluster for low-traffic instances (ps57, pg,
ps3), keep high-traffic ones (ps80, pmm, psmdb) on dedicated clusters or EC2
until validated.

### DNS cutover strategy

1. Deploy Jenkins on EKS with a temporary domain (`ps57-k8s.cd.percona.com`)
2. Validate: auth, workers, builds, credentials, plugins
3. Update OAuth callback URLs for the production domain
4. Switch DNS (`ps57.cd.percona.com`) to the EKS ALB
5. Decommission the EC2 instance and CF stack

### What NOT to change during migration

- Worker configurations (cloud.groovy, htz.cloud.groovy)
- Pipeline code (Jenkinsfiles, shared libraries)
- Job definitions
- Credentials (carry over on the cloned PVC)
- Plugin versions (baked into the Docker image from the live instance)
