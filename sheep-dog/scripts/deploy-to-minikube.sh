#!/usr/bin/env bash
# Deploy to an existing minikube cluster. Sets the kubectl context to the
# given name (default "minikube"), installs the umbrella chart into the
# given namespace, then runs the smoke-test suite against the resulting
# ingress address.
#
# Usage: deploy-to-minikube.sh [env] [chart-version] [kubectl-context]
# Defaults: env=dev, chart-version=latest, kubectl-context=minikube-<env>
#   Context derives uniformly from the env name (#456):
#   dev → minikube-dev,  int → minikube-int,  qa → minikube-qa
#   These are per-machine alias contexts (tools.network.md § Remote kubectl
#   access), so the physical cluster a role lives on can change without
#   editing this script.
#
# The 3rd arg overrides the derived default — pass "minikube" to force
# local-fallback (e.g. when both servers are down — see lcl.sheepdog.io
# in tools.ubuntu.client.md § /etc/hosts). Issues #389, #456.

set -euo pipefail

ENV_NAME="${1:-dev}"
CHART_VERSION="${2:-latest}"
# Context derives uniformly from the env name (#456): dev→minikube-dev,
# int→minikube-int, qa→minikube-qa (per-machine alias contexts).
CONTEXT="${3:-minikube-$ENV_NAME}"

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
