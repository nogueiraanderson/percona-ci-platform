account_id := "<account-id>"
region := "eu-central-1"
registry := account_id + ".dkr.ecr." + region + ".amazonaws.com"
repo := "jenkins-percona"
tag := "2.528.3-ps57"
image := registry + "/" + repo + ":" + tag
profile := "percona-dev-admin"
cluster_name := "jenkins-eks-poc"
hosted_zone_id := "Z1H0AFAU7N8IMC"
domain := "ps57-k8s.cd.percona.com"

# Show available recipes
default:
    @just --list

# --- Docker image ---

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

# Build the Jenkins Docker image
build:
    docker build -t {{image}} .

# Push image to ECR
push: ecr-login
    docker push {{image}}

# --- EKS cluster ---

# Create the EKS cluster
cluster:
    AWS_PROFILE={{profile}} eksctl create cluster -f eksctl-cluster.yaml

# --- IAM ---

# Create IRSA policy and service account for Jenkins
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
        --attach-policy-arn arn:aws:iam::{{account_id}}:policy/jenkins-ps57-eks \
        --approve --override-existing-serviceaccounts

# --- ACM certificate ---

# Request ACM certificate for the domain
acm:
    #!/usr/bin/env bash
    set -euo pipefail
    CERT_ARN=$(aws acm request-certificate --profile {{profile}} --region {{region}} \
        --domain-name {{domain}} \
        --validation-method DNS \
        --tags Key=iit-billing-tag,Value=jenkins-eks-poc \
        --query 'CertificateArn' --output text)
    echo "Certificate ARN: $CERT_ARN"
    echo "Waiting for DNS validation record..."
    sleep 10
    VALIDATION=$(aws acm describe-certificate --profile {{profile}} --region {{region}} \
        --certificate-arn "$CERT_ARN" \
        --query 'Certificate.DomainValidationOptions[0].ResourceRecord' --output json)
    VNAME=$(echo "$VALIDATION" | python3 -c "import sys,json; print(json.load(sys.stdin)['Name'])")
    VVALUE=$(echo "$VALIDATION" | python3 -c "import sys,json; print(json.load(sys.stdin)['Value'])")
    echo "Creating DNS validation record: $VNAME -> $VVALUE"
    aws route53 change-resource-record-sets --profile {{profile}} \
        --hosted-zone-id {{hosted_zone_id}} \
        --change-batch "{
            \"Changes\": [{
                \"Action\": \"UPSERT\",
                \"ResourceRecordSet\": {
                    \"Name\": \"$VNAME\",
                    \"Type\": \"CNAME\",
                    \"TTL\": 300,
                    \"ResourceRecords\": [{\"Value\": \"$VVALUE\"}]
                }
            }]
        }"
    echo "Waiting for certificate validation..."
    aws acm wait certificate-validated --profile {{profile}} --region {{region}} \
        --certificate-arn "$CERT_ARN"
    echo "Certificate validated: $CERT_ARN"
    echo "Update jenkins-values.yaml: replace \${ACM_CERT_ARN} with $CERT_ARN"

# --- Addons ---

# Install AWS Load Balancer Controller
alb-controller:
    #!/usr/bin/env bash
    set -euo pipefail
    # Create IAM policy for LB controller
    curl -sL -o /tmp/alb-iam-policy.json \
        https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.12.0/docs/install/iam_policy.json
    aws iam create-policy --profile {{profile}} \
        --policy-name AWSLoadBalancerControllerIAMPolicy-jenkins-eks \
        --policy-document file:///tmp/alb-iam-policy.json \
        --tags Key=iit-billing-tag,Value=jenkins-eks-poc 2>/dev/null || true
    # Create service account
    eksctl create iamserviceaccount \
        --cluster={{cluster_name}} \
        --region={{region}} \
        --namespace=kube-system \
        --name=aws-load-balancer-controller \
        --attach-policy-arn=arn:aws:iam::{{account_id}}:policy/AWSLoadBalancerControllerIAMPolicy-jenkins-eks \
        --approve --override-existing-serviceaccounts
    # Install via Helm
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

# --- Data migration ---

# Snapshot ps57 EBS volume and create PV/PVC
snapshot-volume:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Creating snapshot of ps57 data volume..."
    SNAP_ID=$(aws ec2 create-snapshot --profile {{profile}} --region {{region}} \
        --volume-id vol-07070c2c983c2cc5f \
        --description "ps57 EKS POC migration" \
        --tag-specifications 'ResourceType=snapshot,Tags=[{Key=iit-billing-tag,Value=jenkins-eks-poc}]' \
        --query 'SnapshotId' --output text)
    echo "Snapshot: $SNAP_ID"
    echo "Waiting for snapshot to complete..."
    aws ec2 wait snapshot-completed --profile {{profile}} --region {{region}} \
        --snapshot-ids "$SNAP_ID"
    echo "Creating EBS volume from snapshot in eu-central-1b..."
    VOL_ID=$(aws ec2 create-volume --profile {{profile}} --region {{region}} \
        --availability-zone eu-central-1b \
        --snapshot-id "$SNAP_ID" \
        --volume-type gp3 \
        --tag-specifications 'ResourceType=volume,Tags=[{Key=iit-billing-tag,Value=jenkins-eks-poc},{Key=Name,Value=ps57-eks-jenkins-home}]' \
        --query 'VolumeId' --output text)
    echo "Volume: $VOL_ID"
    echo "Update ps57-pv.yaml volumeHandle with: $VOL_ID"

# --- Jenkins ---

# Deploy Jenkins via Helm (fresh PVC)
deploy: storage
    helm repo add jenkinsci https://charts.jenkins.io || true
    helm repo update
    helm install jenkins jenkinsci/jenkins \
        -f jenkins-values.yaml \
        -n jenkins --create-namespace

# Upgrade Jenkins Helm release
upgrade:
    helm upgrade jenkins jenkinsci/jenkins \
        -f jenkins-values.yaml \
        -n jenkins

# --- DNS ---

# Create Route53 CNAME for ps57-k8s.cd.percona.com -> ALB
dns:
    #!/usr/bin/env bash
    set -euo pipefail
    ALB_HOST=$(kubectl -n jenkins get ingress jenkins \
        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    echo "ALB: $ALB_HOST"
    aws route53 change-resource-record-sets --profile {{profile}} \
        --hosted-zone-id {{hosted_zone_id}} \
        --change-batch "{
            \"Changes\": [{
                \"Action\": \"UPSERT\",
                \"ResourceRecordSet\": {
                    \"Name\": \"{{domain}}\",
                    \"Type\": \"CNAME\",
                    \"TTL\": 300,
                    \"ResourceRecords\": [{\"Value\": \"$ALB_HOST\"}]
                }
            }]
        }"
    echo "DNS updated: {{domain}} -> $ALB_HOST"

# --- Configure ---

# Copy groovy init scripts to the Jenkins pod and restart
configure:
    #!/usr/bin/env bash
    set -euo pipefail
    POD=$(kubectl -n jenkins get pods -l app.kubernetes.io/name=jenkins -o jsonpath='{.items[0].metadata.name}')
    echo "Pod: $POD"
    # Remove cloned matrix.groovy (overrides auth)
    kubectl -n jenkins exec "$POD" -c jenkins -- rm -f /var/jenkins_home/init.groovy.d/matrix.groovy
    # Copy all groovy scripts
    for f in groovy/*.groovy; do
      name=$(basename "$f")
      echo "  Copying $name"
      kubectl cp "$f" "jenkins/$POD:/var/jenkins_home/init.groovy.d/$name" -c jenkins
    done
    echo "Restarting pod..."
    kubectl -n jenkins delete pod "$POD"
    echo "Waiting for pod to come back..."
    kubectl -n jenkins wait --for=condition=ready pod -l app.kubernetes.io/name=jenkins --timeout=300s
    echo "Done. Scripts will self-delete after running."

# Apply a single groovy script via Script Console (no restart needed)
run-groovy script:
    #!/usr/bin/env bash
    set -euo pipefail
    COOKIES=$(mktemp)
    CRUMB=$(curl -s -c "$COOKIES" -u "admin:percona-eks-poc-2026" \
      "https://{{domain}}/crumbIssuer/api/json" | \
      python3 -c "import sys,json;d=json.load(sys.stdin);print(d['crumbRequestField']+':'+d['crumb'])")
    curl -s -b "$COOKIES" -u "admin:percona-eks-poc-2026" \
      -H "$CRUMB" \
      -X POST "https://{{domain}}/scriptText" \
      --data-urlencode "script@{{script}}"
    rm -f "$COOKIES"

# --- Full setup ---

# Run all steps in order
all: ecr-create build push cluster iam acm alb-controller storage deploy dns configure

# --- Verify ---

# Show cluster status
status:
    kubectl -n jenkins get pods
    kubectl -n jenkins get pvc
    kubectl -n jenkins get ingress
    kubectl -n kube-system get deployment aws-load-balancer-controller

# Get the admin password
admin-password:
    @kubectl -n jenkins get secret jenkins -o jsonpath='{.data.jenkins-admin-password}' | base64 -d && echo

# Port-forward Jenkins to localhost:8080
port-forward:
    kubectl -n jenkins port-forward svc/jenkins 8080:8080

# --- Teardown ---

# Delete everything
clean:
    helm uninstall jenkins -n jenkins || true
    helm uninstall aws-load-balancer-controller -n kube-system || true
    eksctl delete cluster --name {{cluster_name}} --region {{region}}
