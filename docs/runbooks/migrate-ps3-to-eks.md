# Migrate ps3 to EKS

End state: `ps3-k8s.cd.percona.com` runs the production ps3 Jenkins master
in-cluster, seeded as a full replica from EC2 ps3's `JENKINS_HOME` volume.
Production traffic at `ps3.cd.percona.com` only flips after the in-cluster
replica is validated.

## Phases

1. **Snapshot + replicate** — point-in-time copy of EC2 ps3's
   `JENKINS_HOME` EBS volume to `us-east-1a`, restored as the
   `gp3-jenkins-1a-retain` PVC backing the in-cluster StatefulSet.
2. **Run in parallel** — `ps3-k8s.cd.percona.com` boots with the same
   jobs / plugins / credentials / build history as the EC2 ps3.
   Production traffic continues to `ps3.cd.percona.com` (untouched).
3. **Validate** — spot-check jobs, EC2 + Hetzner worker provisioning,
   plugin behaviour, OAuth login, build artefact paths.
4. **Cutover** — flip Route 53 record `ps3.cd.percona.com` from EC2 to
   the in-cluster ALB. Plan a freeze window long enough for one final
   `JENKINS_HOME` rsync + restart on the K8s side, since the snapshot
   from phase 1 is point-in-time and ps3 keeps writing.
5. **Decommission** — once the K8s replica owns production traffic and
   bakes for a few days, terminate the EC2 ps3 instance + CloudFormation
   stack and add a `ps3` entry back to `var.jenkins_hosts` only if a Mode
   B fallback is wanted.

## Phase 1 — snapshot, copy, restore

```bash
# On the source side (eu-west-1 — wherever EC2 ps3 currently lives):
aws ec2 create-snapshot \
  --volume-id <ec2-ps3-jenkins-home-vol-id> \
  --description "ps3 JENKINS_HOME for EKS replica seed"
# Wait for status = completed.

aws ec2 copy-snapshot \
  --source-region <source-region> \
  --source-snapshot-id snap-xxx \
  --destination-region us-east-1 \
  --description "ps3 JENKINS_HOME for ps3-k8s"
# Wait for status = completed.

# In us-east-1, materialise the volume in the StatefulSet AZ:
aws ec2 create-volume \
  --region us-east-1 \
  --availability-zone us-east-1a \
  --snapshot-id snap-yyy \
  --volume-type gp3 \
  --iops 3000 --throughput 125 \
  --tag-specifications "ResourceType=volume,Tags=[{Key=Name,Value=jenkins-ps3-k8s-data}]"
```

Pre-create a `PersistentVolume` referencing the new volume ID and label
it so the StatefulSet's PVC binds to it instead of dynamically
provisioning a fresh disk:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: jenkins-ps3-k8s-data
spec:
  capacity: { storage: 100Gi }
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: gp3-jenkins-1a-retain
  csi:
    driver: ebs.csi.aws.com
    volumeHandle: <new-vol-id>
    fsType: ext4
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: topology.ebs.csi.aws.com/zone
              operator: In
              values: [us-east-1a]
```

Set `storage.preExistingVolumeID` in
`resources/jenkins/master/instances/ps3-k8s/values.yaml` to the same
volume ID and let ArgoCD reconcile.

## Phase 2 — parallel run

Production stays on EC2 ps3 (`ps3.cd.percona.com` unchanged). The
in-cluster replica is reachable at `ps3-k8s.cd.percona.com` only.

Validation checklist:
- `kubectl -n jenkins-ps3-k8s logs -f sts/jenkins-ps3-k8s` shows the
  `Jenkins is fully up` line.
- One EC2 worker + one Hetzner worker provision and connect (validates
  the EC2-plugin IRSA workaround in the image — see ADR 0004).
- OAuth login round-trips (callback URL pre-updated for the new host).
- Three representative jobs run end-to-end (one Hetzner, one EC2, one
  MTR pipeline).
- Build console streams over WebSocket without buffering.

## Phase 3 — DNS cutover

Plan a short freeze window (no new builds for ~30 min). Drain ps3 build
queue. Final `JENKINS_HOME` rsync from EC2 ps3 → ps3-k8s PVC (same-region
EBS isn't directly rsync-able — easiest is over SSH from a temporary
bastion pod, or take a fresh snapshot + replace the PV). Bring ps3-k8s
back up.

Flip Route 53:
- Before: `ps3.cd.percona.com` → EC2 public DNS.
- After: `ps3.cd.percona.com` → ALB alias, with the `ps3` Ingress (or a
  CNAME of `ps3.cd.percona.com` → `ps3-k8s.cd.percona.com`).

## Rollback

If anything fails, revert Route 53 to the EC2 record. Keep the EBS
volume in us-east-1 for forensics. The EC2 master is untouched at this
point and resumes serving on the same hostname.
