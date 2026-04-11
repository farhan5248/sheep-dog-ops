#!/usr/bin/env bash
# Deploy the sheep-dog umbrella helm chart to a Kubernetes namespace.
#
# Kubernetes-distribution-agnostic: caller must point kubectl at the target
# cluster before running this script.
#   - minikube: minikube/setup-cluster.sh (or setup-cluster-local.sh)
#   - EKS:      run `aws eks update-kubeconfig --name <cluster> --region <r>`
#               (the eks/setup-cluster.bat equivalent on Windows)
#
# Usage: setup-namespace.sh <namespace> [chart-version]
#
# chart-version defaults to `latest` — the floating tag in the Nexus OCI
# helm registry. Callers (qa, prod, pinned e2e) pass an explicit semver
# like 0.2.2 to lock to a specific release.

set -euo pipefail

NAMESPACE="${1:-}"
CHART_VERSION="${2:-latest}"
CHART_OCI="oci://nexus-docker.sheepdog.io/helm-hosted/sheep-dog"

if [[ -z "$NAMESPACE" ]]; then
    echo "Usage: setup-namespace.sh <namespace> [chart-version]"
    echo "Example: setup-namespace.sh qa 0.2.2"
    echo "Example: setup-namespace.sh dev          (defaults to latest)"
    exit 1
fi

command -v kubectl >/dev/null 2>&1 || { echo "kubectl is not installed."; exit 1; }
command -v helm    >/dev/null 2>&1 || { echo "helm is not installed.";    exit 1; }

echo "Current kubectl context: $(kubectl config current-context)"

# Chart version hardcoded until #32 Phase 3 introduces version-<env>.txt files.
# Prereqs on the host: hosts file has nexus-docker.sheepdog.io,
# `helm registry login nexus-docker.sheepdog.io` already done,
# mkcert root CA trusted.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$SCRIPT_DIR/../target"
mkdir -p "$TARGET_DIR"
rm -rf "$TARGET_DIR/sheep-dog"

echo "Pulling sheep-dog umbrella helm chart from Nexus OCI..."
helm pull "$CHART_OCI" --version "$CHART_VERSION" --untar --untardir "$TARGET_DIR"

echo "Deploying sheep-dog umbrella helm chart to namespace $NAMESPACE..."
# --timeout 15m: cold-start includes image pulls from Nexus, PVC binding,
# MySQL + Artemis init, and service readiness probes. Default (5m) is too
# short; observed first-install times in the 7-10m range on both minikube
# and fresh EKS clusters.
helm upgrade --install sheep-dog "$TARGET_DIR/sheep-dog" \
    -n "$NAMESPACE" --create-namespace \
    -f "$TARGET_DIR/sheep-dog/helm-values/values-$NAMESPACE.yaml" \
    --wait --timeout 15m

echo "Restarting deployments to pull the latest images..."
kubectl rollout restart deployment -n "$NAMESPACE" -l app=sheep-dog
kubectl rollout status  deployment -n "$NAMESPACE" -l app=sheep-dog

echo "Waiting for Ingress hostname to be assigned (up to 5 minutes)..."
SERVICE_URL=""
for i in $(seq 1 30); do
    SERVICE_URL=$(kubectl get ingress sheep-dog-ingress -n "$NAMESPACE" \
        -o jsonpath="{.status.loadBalancer.ingress[0].hostname}" 2>/dev/null || true)
    if [[ -n "$SERVICE_URL" ]]; then
        break
    fi
    echo "Waiting for Ingress... (attempt $i/30)"
    sleep 10
done

if [[ -z "$SERVICE_URL" ]]; then
    echo "Failed to get Ingress URL."
    exit 1
fi
echo "Service URL: $SERVICE_URL"

kubectl get services -n "$NAMESPACE"

# Emit GitHub Actions output if running under Actions.
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "service_url=$SERVICE_URL" >> "$GITHUB_OUTPUT"
fi

echo "Namespace setup completed successfully!"
