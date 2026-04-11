#!/usr/bin/env bash
# Tear down the AWS EKS cluster for a sheep-dog namespace: delete
# ingress-nginx (releases the NLB), wait for LBs to drain, delete the EBS
# CSI IAM role, OIDC provider, and CloudFormation stack.
#
# Usage: eks/teardown-cluster.sh <namespace>
# Required env:
#   ACCOUNT_ID — AWS account ID (no hardcode; set in shell env or CI job)

set -euo pipefail

NAMESPACE="${1:-}"
BASE_STACK_NAME="sheep-dog-aws"
REGION="us-east-1"
ACCOUNT_ID="${ACCOUNT_ID:?ACCOUNT_ID must be set (AWS account ID for IAM ARNs)}"

if [[ -z "$NAMESPACE" ]]; then
    echo "Usage: eks/teardown-cluster.sh <namespace>"
    echo "Example: eks/teardown-cluster.sh prod"
    exit 1
fi

command -v aws     >/dev/null 2>&1 || { echo "aws CLI is not installed."; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "kubectl is not installed."; exit 1; }
aws sts get-caller-identity >/dev/null || { echo "Not logged in to AWS."; exit 1; }

STACK_NAME="${BASE_STACK_NAME}-${NAMESPACE}"

echo "Getting EKS cluster name from stack $STACK_NAME..."
CLUSTER_NAME=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='ClusterName'].OutputValue" \
    --output text \
    --region "$REGION" 2>/dev/null || true)

# ingress-nginx and its NLB are owned by the cluster layer: setup-cluster
# installs them, teardown-cluster removes them. Namespace teardown only
# removes the sheep-dog helm release, so teardown-namespace + setup-namespace
# is a valid redeploy loop that keeps the NLB alive.
if [[ -n "$CLUSTER_NAME" ]]; then
    echo "Cluster: $CLUSTER_NAME"
    echo "Updating kubeconfig..."
    aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"

    echo "Deleting ingress-nginx namespace (releases the NLB)..."
    kubectl delete namespace ingress-nginx --ignore-not-found=true --timeout=300s

    echo "Waiting for cluster load balancers to be deleted (up to 5 minutes)..."
    LB_DELETED=0
    for i in $(seq 1 30); do
        LB_COUNT=$(aws resourcegroupstaggingapi get-resources \
            --resource-type-filters elasticloadbalancing:loadbalancer \
            --tag-filters "Key=kubernetes.io/cluster/$CLUSTER_NAME,Values=owned" \
            --query "length(ResourceTagMappingList)" \
            --output text \
            --region "$REGION")
        if [[ "$LB_COUNT" == "0" ]]; then
            echo "All cluster load balancers deleted."
            LB_DELETED=1
            break
        fi
        echo "Waiting for $LB_COUNT load balancer(s)... (attempt $i/30)"
        sleep 10
    done
    if [[ "$LB_DELETED" == "0" ]]; then
        echo "ERROR: Timed out waiting for load balancers to be deleted."
        exit 1
    fi
fi

echo "Deleting EBS CSI driver IAM role and policy..."
ROLE_NAME=EBSCSIDriverRole
aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
    || echo "Policy may already be detached, continuing..."
aws iam delete-role --role-name "$ROLE_NAME" \
    || echo "Role may already be deleted, continuing..."

if [[ -n "$CLUSTER_NAME" ]]; then
    OIDC_URL=$(aws eks describe-cluster --name "$CLUSTER_NAME" --query "cluster.identity.oidc.issuer" --output text 2>/dev/null || true)
    if [[ -n "$OIDC_URL" ]]; then
        OIDC_PROVIDER_ID=$(basename "$OIDC_URL")
        echo "Deleting OIDC provider..."
        aws iam delete-open-id-connect-provider \
            --open-id-connect-provider-arn "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/oidc.eks.${REGION}.amazonaws.com/id/${OIDC_PROVIDER_ID}" \
            || echo "OIDC provider may already be deleted, continuing..."
    fi
fi

echo "Deleting CloudFormation stack..."
aws cloudformation delete-stack --stack-name "$STACK_NAME" --region "$REGION"
echo "Waiting for stack deletion to complete..."
aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" --region "$REGION"

echo "Cluster teardown completed."
