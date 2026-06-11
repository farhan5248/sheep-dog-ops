#!/usr/bin/env bash
# Deploy the GraphWalker product chart to an existing minikube cluster.
# Installs the local chart into the `graphwalker` namespace and smoke-tests the
# Studio UI through the ingress.
#
# Usage: deploy-to-minikube.sh [namespace] [kubectl-context]
# Defaults: namespace=graphwalker, context=minikube-graphwalker
#
# Unlike the sheep-dog deploy, the chart is referenced locally (low-churn
# third-party product, no OCI publish step). Images are built/pushed by hand
# from the graphwalker repo modules (mvn clean package).

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

echo "--- Smoke test (studio.graphwalker.io) ---"
STUDIO_HOST="$(helm get values graphwalker -n "$NAMESPACE" --all -o json \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["graphwalkerUi"]["host"])')"
code=$(curl -s -o /dev/null -w '%{http_code}' -H "Host: $STUDIO_HOST" \
  http://"$STUDIO_HOST"/studio.html --max-time 20 || true)
echo "studio.html -> HTTP $code"
[ "$code" = "200" ] || { echo "Smoke test failed"; exit 1; }

echo "Deploy completed successfully!"
