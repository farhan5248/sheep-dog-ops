#!/usr/bin/env bash
# Create the AWS EKS cluster for a sheep-dog namespace: CloudFormation stack,
# OIDC provider, EBS CSI driver IAM role, ingress-nginx controller.
#
# Distribution-specific counterpart to minikube/setup-cluster.bat. Run once
# per namespace before the first setup-namespace call; teardown via
# eks/teardown-cluster.sh.
#
# Usage: eks/setup-cluster.sh <namespace>
# Required env:
#   ACCOUNT_ID — AWS account ID (no hardcode; set in shell env or CI job)

set -euo pipefail

NAMESPACE="${1:-}"
BASE_STACK_NAME="sheep-dog-aws"
REGION="us-east-1"
ACCOUNT_ID="${ACCOUNT_ID:?ACCOUNT_ID must be set (AWS account ID for IAM ARNs)}"

if [[ -z "$NAMESPACE" ]]; then
    echo "Usage: eks/setup-cluster.sh <namespace>"
    echo "Example: eks/setup-cluster.sh prod"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_NAME="${BASE_STACK_NAME}-${NAMESPACE}"

command -v aws     >/dev/null 2>&1 || { echo "aws CLI is not installed."; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "kubectl is not installed."; exit 1; }
command -v helm    >/dev/null 2>&1 || { echo "helm is not installed.";    exit 1; }
aws sts get-caller-identity >/dev/null || { echo "Not logged in to AWS."; exit 1; }

echo "Using stack name: $STACK_NAME"

echo "Deploying CloudFormation stack for EKS..."
aws cloudformation deploy \
    --template-file "$SCRIPT_DIR/eks.yml" \
    --stack-name "$STACK_NAME" \
    --capabilities CAPABILITY_IAM \
    --region "$REGION"

echo "Getting EKS cluster name from stack..."
CLUSTER_NAME=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='ClusterName'].OutputValue" \
    --output text \
    --region "$REGION")
if [[ -z "$CLUSTER_NAME" ]]; then
    echo "Failed to get EKS cluster name from CloudFormation stack $STACK_NAME."
    exit 1
fi
echo "Cluster: $CLUSTER_NAME"

echo "Getting OIDC URL from EKS cluster..."
OIDC_URL=$(aws eks describe-cluster --name "$CLUSTER_NAME" --query "cluster.identity.oidc.issuer" --output text)
if [[ -z "$OIDC_URL" ]]; then
    echo "Failed to get OIDC URL from EKS cluster."
    exit 1
fi
OIDC_PROVIDER_ID=$(basename "$OIDC_URL")

echo "Creating OIDC provider in IAM..."
aws iam create-open-id-connect-provider \
    --url "$OIDC_URL" \
    --client-id-list sts.amazonaws.com \
    --thumbprint-list 9e99a48a9960b14926bb7f3b02e22da2b0ab7280 \
    || echo "OIDC provider may already exist, continuing..."

echo "Rendering trust policy with OIDC provider ID and account ID..."
mkdir -p "$SCRIPT_DIR/target"
sed "s/OIDC_PROVIDER_ID/$OIDC_PROVIDER_ID/g; s/ACCOUNT_ID/$ACCOUNT_ID/g" \
    "$SCRIPT_DIR/oidc-policy.json" > "$SCRIPT_DIR/target/oidc-policy.json"

echo "Creating IAM role for EBS CSI driver..."
aws iam create-role \
    --role-name EBSCSIDriverRole \
    --assume-role-policy-document "file://$SCRIPT_DIR/target/oidc-policy.json" \
    || echo "Role may already exist, continuing..."

echo "Attaching AmazonEBSCSIDriverPolicy to the role..."
aws iam attach-role-policy \
    --role-name EBSCSIDriverRole \
    --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
    || echo "Policy may already be attached, continuing..."

echo "Creating EBS CSI driver add-on in EKS..."
aws eks create-addon \
    --cluster-name "$CLUSTER_NAME" \
    --addon-name aws-ebs-csi-driver \
    --service-account-role-arn "arn:aws:iam::${ACCOUNT_ID}:role/EBSCSIDriverRole" \
    --addon-version v1.57.1-eksbuild.1 \
    --resolve-conflicts OVERWRITE \
    || echo "Addon may already exist, continuing..."

echo "Waiting for EBS CSI driver add-on to become active (up to 60s)..."
for i in $(seq 1 12); do
    STATUS=$(aws eks describe-addon --cluster-name "$CLUSTER_NAME" --addon-name aws-ebs-csi-driver --query "addon.status" --output text)
    echo "Current status: $STATUS"
    if [[ "$STATUS" == "ACTIVE" ]]; then
        echo "EBS CSI driver add-on is now active."
        break
    fi
    sleep 5
done

echo "Updating kubeconfig..."
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"

echo "Installing nginx-ingress-controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.2/deploy/static/provider/aws/deploy.yaml

echo "Waiting for nginx-ingress-controller to be ready..."
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=300s

echo "Cluster setup completed successfully!"
