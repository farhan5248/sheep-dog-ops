#!/usr/bin/env bash
# Deploy to an existing minikube cluster. Sets the kubectl context to the
# given name (default "minikube"), installs the umbrella chart into the
# given namespace, then runs the smoke-test suite against the resulting
# ingress address.
#
# Usage: deploy-to-minikube.sh [env] [chart-version] [kubectl-context]
# Defaults: env=dev, chart-version=latest, kubectl-context=minikube
#
# The context arg lets a -client machine (which has its own local context
# renamed per #376, e.g. "ubuntu-client") deploy to a remote LAN cluster
# (e.g. "ubuntu-sandbox") without touching the script. Hosts whose local
# context is still called "minikube" can omit it. See tools.network.md
# § Remote kubectl access.

set -euo pipefail

ENV_NAME="${1:-dev}"
CHART_VERSION="${2:-latest}"
CONTEXT="${3:-minikube}"

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
