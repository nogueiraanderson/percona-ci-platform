# Jenkins on EKS - Build, Deploy, and Manage
#
# Cluster-level recipes (run once):
#   just cluster        just iam        just alb-controller
#
# Instance-level recipes (run per Jenkins instance):
#   just clone-instance name=ps57-2 source_vol=vol-xxx jenkins_home=ps57.cd.percona.com
#   just deploy-instance name=ps57-2
#   just delete-instance name=ps57-2

# --- Global config ---
account_id := "<account-id>"
region := "eu-central-1"
az := "eu-central-1b"
registry := account_id + ".dkr.ecr." + region + ".amazonaws.com"
repo := "jenkins-percona"
tag := "2.528.3"
image := registry + "/" + repo + ":" + tag
profile := "percona-dev-admin"
cluster_name := "jenkins-eks-poc"
hosted_zone_id := "Z1H0AFAU7N8IMC"
acm_cert_arn := "arn:aws:acm:eu-central-1:<account-id>:certificate/1ec6590a-0529-4af0-81e9-ec59ec71aab2"
iam_policy_arn := "arn:aws:iam::<account-id>:policy/jenkins-ps57-eks"

# Show available recipes
default:
    @just --list

# ============================================================
# Docker image (shared across all instances)
# ============================================================

# Login to ECR
ecr-login:
    aws ecr get-login-password --region {{region}} --profile {{profile}} \
        | docker login --username AWS --password-stdin {{registry}}

# Create ECR repository
ecr-create:
    aws ecr create-repository --repository-name {{repo}} \
        --region {{region}} --profile {{profile}} \
        --tags Key=iit-billing-tag,Value=jenkins-eks-poc \
        --image-scanning-configuration scanOnPush=true || true

# Build the Jenkins Docker image (amd64 for EKS t3.xlarge nodes)
build:
    docker buildx build --platform linux/amd64 -t {{image}} --load .

# Push image to ECR
push: ecr-login
    docker push {{image}}

# Build and push in one step
image: ecr-create build push

# ============================================================
# EKS cluster (one-time setup)
# ============================================================

# Create the EKS cluster
cluster:
    AWS_PROFILE={{profile}} eksctl create cluster -f eksctl-cluster.yaml

# Create IRSA service account for Jenkins pods
iam:
    aws iam create-policy --profile {{profile}} \
        --policy-name jenkins-ps57-eks \
        --policy-document file://iam-policy.json \
        --tags Key=iit-billing-tag,Value=jenkins-eks-poc || true
    eksctl create iamserviceaccount \
        --name jenkins \
        --namespace jenkins \
        --cluster {{cluster_name}} \
        --region {{region}} \
        --attach-policy-arn {{iam_policy_arn}} \
        --approve --override-existing-serviceaccounts

# Install AWS Load Balancer Controller
alb-controller:
    #!/usr/bin/env bash
    set -euo pipefail
    curl -sL -o /tmp/alb-iam-policy.json \
        https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.12.0/docs/install/iam_policy.json
    aws iam create-policy --profile {{profile}} \
        --policy-name AWSLoadBalancerControllerIAMPolicy-jenkins-eks \
        --policy-document file:///tmp/alb-iam-policy.json \
        --tags Key=iit-billing-tag,Value=jenkins-eks-poc 2>/dev/null || true
    eksctl create iamserviceaccount \
        --cluster={{cluster_name}} --region={{region}} \
        --namespace=kube-system --name=aws-load-balancer-controller \
        --attach-policy-arn=arn:aws:iam::{{account_id}}:policy/AWSLoadBalancerControllerIAMPolicy-jenkins-eks \
        --approve --override-existing-serviceaccounts
    helm repo add eks https://aws.github.io/eks-charts || true
    helm repo update
    helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
        -n kube-system \
        --set clusterName={{cluster_name}} \
        --set serviceAccount.create=false \
        --set serviceAccount.name=aws-load-balancer-controller \
        --set region={{region}} \
        --set vpcId=$(aws eks describe-cluster --profile {{profile}} --region {{region}} \
            --name {{cluster_name}} --query 'cluster.resourcesVpcConfig.vpcId' --output text)

# Create gp3 StorageClass
storage:
    kubectl apply -f gp3-storageclass.yaml

# Full cluster setup (run once)
cluster-setup: cluster iam alb-controller storage

# ============================================================
# Instance lifecycle (per Jenkins instance)
# ============================================================

# Clone an EBS volume for a new instance
# Usage: just clone-instance name=ps57-2 source_vol=vol-07070c2c983c2cc5f jenkins_home=ps57.cd.percona.com
clone-instance name source_vol jenkins_home:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "=== Cloning {{source_vol}} for instance {{name}} ==="
    SNAP_ID=$(aws ec2 create-snapshot --profile {{profile}} --region {{region}} \
        --volume-id {{source_vol}} \
        --description "Jenkins EKS clone for {{name}}" \
        --tag-specifications 'ResourceType=snapshot,Tags=[{Key=iit-billing-tag,Value=jenkins-eks-poc},{Key=Name,Value={{name}}-snapshot}]' \
        --query 'SnapshotId' --output text)
    echo "Snapshot: $SNAP_ID (waiting...)"
    aws ec2 wait snapshot-completed --profile {{profile}} --region {{region}} --snapshot-ids "$SNAP_ID"
    VOL_ID=$(aws ec2 create-volume --profile {{profile}} --region {{region}} \
        --availability-zone {{az}} --snapshot-id "$SNAP_ID" --volume-type gp3 \
        --tag-specifications "ResourceType=volume,Tags=[{Key=iit-billing-tag,Value=jenkins-eks-poc},{Key=Name,Value={{name}}-jenkins-home}]" \
        --query 'VolumeId' --output text)
    echo "Volume: $VOL_ID"
    # Generate PV/PVC manifest
    cat > instances/{{name}}-pv.yaml << EOF
    apiVersion: v1
    kind: PersistentVolume
    metadata:
      name: {{name}}-jenkins-home
      labels:
        iit-billing-tag: jenkins-eks-poc
    spec:
      capacity:
        storage: 100Gi
      accessModes:
        - ReadWriteOnce
      persistentVolumeReclaimPolicy: Retain
      storageClassName: ""
      csi:
        driver: ebs.csi.aws.com
        volumeHandle: $VOL_ID
        fsType: xfs
      nodeAffinity:
        required:
          nodeSelectorTerms:
            - matchExpressions:
                - key: topology.kubernetes.io/zone
                  operator: In
                  values:
                    - {{az}}
    ---
    apiVersion: v1
    kind: PersistentVolumeClaim
    metadata:
      name: {{name}}-jenkins-home
      namespace: jenkins
    spec:
      accessModes:
        - ReadWriteOnce
      storageClassName: ""
      resources:
        requests:
          storage: 100Gi
      volumeName: {{name}}-jenkins-home
    EOF
    # Generate Helm values
    DOMAIN="{{name}}.cd.percona.com"
    cat > instances/{{name}}-values.yaml << EOF
    controller:
      image:
        registry: "{{registry}}"
        repository: {{repo}}
        tag: "{{tag}}"
        pullPolicy: IfNotPresent
      installPlugins: false
      overwritePluginsFromImage: false
      initializeOnce: true
      javaOpts: >-
        -Xms3072m -Xmx4096m -Xss4m -server
        -Djava.awt.headless=true
        -Dorg.jenkinsci.plugins.durabletask.BourneShellScript.HEARTBEAT_CHECK_INTERVAL=600
      resources:
        requests:
          cpu: "1000m"
          memory: "4Gi"
        limits:
          cpu: "4000m"
          memory: "6Gi"
      serviceType: ClusterIP
      agentListenerPort: 50000
      agentListenerServiceType: LoadBalancer
      agentListenerServiceAnnotations:
        service.beta.kubernetes.io/aws-load-balancer-type: nlb
        service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
        service.beta.kubernetes.io/aws-load-balancer-additional-resource-tags: "iit-billing-tag=jenkins-eks-poc"
      numExecutors: 1
      executorMode: "EXCLUSIVE"
      ingress:
        enabled: true
        ingressClassName: alb
        hostName: $DOMAIN
        annotations:
          alb.ingress.kubernetes.io/scheme: internet-facing
          alb.ingress.kubernetes.io/target-type: ip
          alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
          alb.ingress.kubernetes.io/ssl-redirect: "443"
          alb.ingress.kubernetes.io/certificate-arn: "{{acm_cert_arn}}"
          alb.ingress.kubernetes.io/healthcheck-path: /login
          alb.ingress.kubernetes.io/tags: "iit-billing-tag=jenkins-eks-poc"
        tls:
          - hosts:
              - $DOMAIN
      JCasC:
        defaultConfig: false
        overwriteConfiguration: false
      podLabels:
        iit-billing-tag: jenkins-eks-poc
      containerEnv:
        - name: JENKINS_URL
          value: "https://$DOMAIN/"
        - name: JENKINS_ADMIN_PASSWORD
          valueFrom:
            secretKeyRef:
              name: {{name}}-admin
              key: password
              optional: true
    persistence:
      enabled: true
      existingClaim: {{name}}-jenkins-home
      subPath: "{{jenkins_home}}"
    serviceAccount:
      create: false
      name: jenkins
    agent:
      enabled: false
    EOF
    echo "Generated: instances/{{name}}-pv.yaml, instances/{{name}}-values.yaml"
    echo "Next: just deploy-instance name={{name}}"

# Deploy a Jenkins instance (after clone-instance)
# Usage: just deploy-instance name=ps57-2
deploy-instance name mode="poc":
    #!/usr/bin/env bash
    set -euo pipefail
    echo "=== Deploying {{name}} (mode={{mode}}) ==="
    # Apply PV/PVC
    kubectl apply -f instances/{{name}}-pv.yaml
    # Create admin password secret (POC mode)
    if [ "{{mode}}" = "poc" ]; then
      PASS=$(openssl rand -base64 12)
      kubectl -n jenkins create secret generic {{name}}-admin \
        --from-literal=password="$PASS" --dry-run=client -o yaml | kubectl apply -f -
      echo "Admin password: $PASS"
    fi
    # Deploy via Helm
    helm repo add jenkinsci https://charts.jenkins.io 2>/dev/null || true
    helm install {{name}} jenkinsci/jenkins \
        -f instances/{{name}}-values.yaml \
        -n jenkins
    echo "Waiting for pod..."
    sleep 10
    kubectl -n jenkins wait --for=condition=ready pod -l app.kubernetes.io/instance={{name}} --timeout=300s || true
    # Configure (POC: local auth + disable crons; prod: keep existing auth)
    POD=$(kubectl -n jenkins get pods -l app.kubernetes.io/instance={{name}} -o jsonpath='{.items[0].metadata.name}')
    if [ "{{mode}}" = "poc" ]; then
      kubectl -n jenkins exec "$POD" -c jenkins -- rm -f /var/jenkins_home/init.groovy.d/matrix.groovy
      for f in groovy/*.groovy; do
        kubectl cp "$f" "jenkins/$POD:/var/jenkins_home/init.groovy.d/$(basename $f)" -c jenkins
      done
      echo "Restarting with init scripts..."
      kubectl -n jenkins delete pod "$POD"
      kubectl -n jenkins wait --for=condition=ready pod -l app.kubernetes.io/instance={{name}} --timeout=300s
    else
      # Prod: only apply URL fix and IRSA credential, keep existing auth
      kubectl cp groovy/fix-url.groovy "jenkins/$POD:/var/jenkins_home/init.groovy.d/" -c jenkins
      kubectl cp groovy/ec2-irsa-credential.groovy "jenkins/$POD:/var/jenkins_home/init.groovy.d/" -c jenkins
      kubectl cp groovy/disable-crons.groovy "jenkins/$POD:/var/jenkins_home/init.groovy.d/" -c jenkins
      echo "Restarting with URL fix + IRSA + cron disable..."
      kubectl -n jenkins delete pod "$POD"
      kubectl -n jenkins wait --for=condition=ready pod -l app.kubernetes.io/instance={{name}} --timeout=300s
    fi
    # DNS
    DOMAIN="{{name}}.cd.percona.com"
    ALB_HOST=$(kubectl -n jenkins get ingress {{name}} \
        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")
    if [ "$ALB_HOST" != "pending" ] && [ -n "$ALB_HOST" ]; then
      aws route53 change-resource-record-sets --profile {{profile}} \
          --hosted-zone-id {{hosted_zone_id}} \
          --change-batch "{
              \"Changes\": [{\"Action\":\"UPSERT\",\"ResourceRecordSet\":{
                  \"Name\":\"$DOMAIN\",\"Type\":\"CNAME\",\"TTL\":300,
                  \"ResourceRecords\":[{\"Value\":\"$ALB_HOST\"}]}}]}"
      echo "DNS: $DOMAIN -> $ALB_HOST"
    else
      echo "ALB not ready yet. Run: just dns name={{name}}"
    fi
    echo "=== {{name}} deployed ==="
    echo "URL: https://$DOMAIN"

# Create DNS record for an instance
dns name:
    #!/usr/bin/env bash
    set -euo pipefail
    DOMAIN="{{name}}.cd.percona.com"
    ALB_HOST=$(kubectl -n jenkins get ingress {{name}} \
        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    echo "ALB: $ALB_HOST"
    aws route53 change-resource-record-sets --profile {{profile}} \
        --hosted-zone-id {{hosted_zone_id}} \
        --change-batch "{
            \"Changes\": [{\"Action\":\"UPSERT\",\"ResourceRecordSet\":{
                \"Name\":\"$DOMAIN\",\"Type\":\"CNAME\",\"TTL\":300,
                \"ResourceRecords\":[{\"Value\":\"$ALB_HOST\"}]}}]}"
    echo "DNS: $DOMAIN -> $ALB_HOST"

# Delete a Jenkins instance (keeps PVC for safety)
delete-instance name:
    helm uninstall {{name}} -n jenkins || true
    kubectl -n jenkins delete ingress {{name}} 2>/dev/null || true
    echo "PVC {{name}}-jenkins-home preserved (delete manually if needed)"

# ============================================================
# Status and debugging
# ============================================================

# Show all Jenkins instances on the cluster
status:
    @echo "=== Pods ===" && kubectl -n jenkins get pods -o wide
    @echo "=== PVCs ===" && kubectl -n jenkins get pvc
    @echo "=== Ingress ===" && kubectl -n jenkins get ingress
    @echo "=== ALB Controller ===" && kubectl -n kube-system get deployment aws-load-balancer-controller

# Port-forward a specific instance
port-forward name="jenkins":
    kubectl -n jenkins port-forward svc/{{name}} 8080:8080

# ============================================================
# Teardown
# ============================================================

# Delete the entire EKS cluster
clean:
    helm list -n jenkins -q | xargs -r -I{} helm uninstall {} -n jenkins || true
    helm uninstall aws-load-balancer-controller -n kube-system || true
    eksctl delete cluster --name {{cluster_name}} --region {{region}}
