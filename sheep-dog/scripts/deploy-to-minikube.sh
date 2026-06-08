#!/usr/bin/env bash
# Deploy to an existing minikube cluster. Sets the kubectl context to the
# given name (default "minikube"), installs the umbrella chart into the
# given namespace, then runs the smoke-test suite against the resulting
# ingress address.
#
# Usage: deploy-to-minikube.sh [env] [chart-version] [kubectl-context]
# Defaults: env=dev, chart-version=latest, kubectl-context derived from env
#   - dev  → minikube-sandbox  (LAN cluster on ubuntu-sandbox)
#   - qa   → minikube-team     (LAN cluster on ubuntu-team)
#   - int  → minikube-team     (LAN cluster on ubuntu-team — CI/CD integration testing, #455)
#   - else → minikube          (local cluster fallback)
#
# The 3rd arg overrides the derived default — pass "minikube" to force
# local-fallback (e.g. when both servers are down — see lcl.sheepdog.io
# in tools.ubuntu.client.md § /etc/hosts). See tools.network.md § Remote
# kubectl access for the context naming convention. Issue #389.

set -euo pipefail

ENV_NAME="${1:-dev}"
CHART_VERSION="${2:-latest}"
case "$ENV_NAME" in
    dev) DEFAULT_CONTEXT=minikube-sandbox ;;
    qa)  DEFAULT_CONTEXT=minikube-team ;;
    int) DEFAULT_CONTEXT=minikube-team ;;
    *)   DEFAULT_CONTEXT=minikube ;;
esac
CONTEXT="${3:-$DEFAULT_CONTEXT}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "--- Select kubectl context ($CONTEXT) ---"
kubectl config use-context "$CONTEXT"

echo "--- Setup namespace ($ENV_NAME, chart $CHART_VERSION) ---"
bash "$SCRIPT_DIR/setup-namespace.sh" "$ENV_NAME" "$CHART_VERSION"

# setup-namespace.sh writes $TARGET_DIR/service_url.txt so the parent shell
# can recover the ingress URL — child-process env vars don't leak up.
TARGET_DIR="$(cd "$SCRIPT_DIR/../target" && pwd)"
SERVICE_URL=$(cat "$TARGET_DIR/service_url.txt")

echo "--- Smoke test ($SERVICE_URL) ---"
bash "$SCRIPT_DIR/smoke-test.sh" "$SERVICE_URL"

echo "Deploy completed successfully!"
