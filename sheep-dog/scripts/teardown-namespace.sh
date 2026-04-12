#!/usr/bin/env bash
# Uninstall the sheep-dog umbrella helm release from a Kubernetes namespace.
#
# Sets the kubectl context to the EKS cluster for the given namespace
# (derived from CloudFormation stack sheep-dog-aws-<namespace>).
# Requires AWS CLI configured with valid credentials.
#
# On EKS, ingress-nginx and its NLB are owned by the EKS layer
# (eks/setup-cluster.sh installs them; eks/teardown-cluster.sh removes
# them). Namespace teardown only removes the sheep-dog helm release, so
# teardown-namespace + setup-namespace is a valid redeploy loop.
#
# Usage: teardown-namespace.sh <namespace>

set -euo pipefail

NAMESPACE="${1:-}"
REGION="us-east-1"

if [[ -z "$NAMESPACE" ]]; then
    echo "Usage: teardown-namespace.sh <namespace>"
    echo "Example: teardown-namespace.sh qa"
    exit 1
fi

command -v aws     >/dev/null 2>&1 || { echo "aws CLI is not installed."; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "kubectl is not installed."; exit 1; }
command -v helm    >/dev/null 2>&1 || { echo "helm is not installed.";    exit 1; }

echo "Selecting EKS cluster for namespace $NAMESPACE..."
STACK_NAME="sheep-dog-aws-${NAMESPACE}"
CLUSTER_NAME=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='ClusterName'].OutputValue" \
    --output text \
    --region "$REGION")
if [[ -z "$CLUSTER_NAME" ]]; then
    echo "Failed to get EKS cluster name from stack $STACK_NAME."
    exit 1
fi
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"
echo "Current kubectl context: $(kubectl config current-context)"
echo "Uninstalling sheep-dog umbrella helm release from namespace $NAMESPACE..."
helm uninstall sheep-dog -n "$NAMESPACE" --ignore-not-found

echo "Namespace teardown completed."
