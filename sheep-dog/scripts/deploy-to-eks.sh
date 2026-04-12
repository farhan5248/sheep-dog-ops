#!/usr/bin/env bash
# Full-lifecycle EKS deploy: provision cluster, install umbrella chart,
# run smoke test, tear the namespace and cluster back down.
#
# Usage: deploy-to-eks.sh [env] [chart-version]
# Defaults: env=dev, chart-version=latest
# Required env: ACCOUNT_ID

set -euo pipefail

ENV_NAME="${1:-dev}"
CHART_VERSION="${2:-latest}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EKS_DIR="$SCRIPT_DIR/../../eks"

REGION="us-east-1"

echo "--- Setup cluster (eks) ---"
bash "$EKS_DIR/setup-cluster.sh" "$ENV_NAME"

echo "--- Select EKS cluster ---"
STACK_NAME="sheep-dog-aws-${ENV_NAME}"
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

echo "--- Setup namespace ($ENV_NAME, chart $CHART_VERSION) ---"
bash "$SCRIPT_DIR/setup-namespace.sh" "$ENV_NAME" "$CHART_VERSION"

# setup-namespace.sh writes $TARGET_DIR/service_url.txt so the parent shell
# can recover the ingress URL — child-process env vars don't leak up.
TARGET_DIR="$(cd "$SCRIPT_DIR/../target" && pwd)"
SERVICE_URL=$(cat "$TARGET_DIR/service_url.txt")

echo "--- Smoke test ($SERVICE_URL) ---"
bash "$SCRIPT_DIR/smoke-test.sh" "$SERVICE_URL"

echo "--- Teardown namespace ($ENV_NAME) ---"
bash "$SCRIPT_DIR/teardown-namespace.sh" "$ENV_NAME"

echo "--- Teardown cluster (eks) ---"
bash "$EKS_DIR/teardown-cluster.sh" "$ENV_NAME"

echo "Full deploy completed successfully!"
