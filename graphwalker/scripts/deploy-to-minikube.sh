#!/usr/bin/env bash
# Deploy the GraphWalker product chart to an existing minikube cluster.
# Installs the local chart into the `graphwalker` namespace.
#
# Usage: deploy-to-minikube.sh [namespace] [kubectl-context]
# Defaults: namespace=graphwalker, context=minikube-graphwalker
#
# This script deploys the chart straight from the local working tree. The chart
# is also published to Nexus OCI by this repo's pom (`mvn clean deploy`, locally —
# no GitHub runners); graphwalker-svc's build pulls that published chart. Images
# are built/pushed from the graphwalker repo modules (mvn clean package / install).
#
# Nothing runs permanently in this namespace (sheep-dog-main#494): Studio (ui) is
# retired and runs locally via the graphwalker repo's scripts/run-studio-local.sh,
# and graphwalker-svc is scaled to 0 except during its own failsafe ITs (its pom
# scales it up/down). So this only deploys the chart manifests + ingress; there is
# no always-on pod to smoke-test here. The release-deployed check below confirms
# the chart applied.

set -euo pipefail

NAMESPACE="${1:-graphwalker}"
CONTEXT="${2:-minikube-$NAMESPACE}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$(cd "$SCRIPT_DIR/../helm/graphwalker" && pwd)"

echo "--- Select kubectl context ($CONTEXT) ---"
kubectl config use-context "$CONTEXT"

echo "--- Deploy graphwalker chart into namespace $NAMESPACE ---"
helm upgrade --install graphwalker "$CHART_DIR" \
  -n "$NAMESPACE" --create-namespace \
  --wait --timeout 5m

echo "--- Verify release deployed ---"
STATUS="$(helm status graphwalker -n "$NAMESPACE" -o json \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["info"]["status"])')"
echo "release status -> $STATUS"
[ "$STATUS" = "deployed" ] || { echo "Release not deployed"; exit 1; }

echo "Deploy completed successfully!"
