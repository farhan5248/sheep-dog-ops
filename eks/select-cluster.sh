#!/usr/bin/env bash
# Point kubectl at the EKS cluster for a sheep-dog namespace. Called by
# deploy*.sh / deploy*.bat before any namespace operation against EKS.
#
# Usage: eks/select-cluster.sh <namespace>

set -euo pipefail

NAMESPACE="${1:-}"
BASE_STACK_NAME="sheep-dog-aws"
REGION="us-east-1"

if [[ -z "$NAMESPACE" ]]; then
    echo "Usage: eks/select-cluster.sh <namespace>"
    echo "Example: eks/select-cluster.sh prod"
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
    --region "$REGION")

if [[ -z "$CLUSTER_NAME" ]]; then
    echo "Failed to get EKS cluster name from CloudFormation stack $STACK_NAME."
    echo "Provision the cluster first with eks/setup-cluster.sh $NAMESPACE."
    exit 1
fi

echo "Configuring kubectl to connect to EKS cluster $CLUSTER_NAME..."
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"

echo "Current kubectl context: $(kubectl config current-context)"
