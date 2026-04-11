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
# When empty or "latest", omit helm's --version flag so helm pulls the
# newest release. Helm's --version expects a semver constraint, not a
# docker-style "latest" tag — passing "latest" literally fails with
# "improper constraint: latest".
CHART_VERSION="${2:-}"
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
mkdir -p "$SCRIPT_DIR/../target"
TARGET_DIR="$(cd "$SCRIPT_DIR/../target" && pwd)"
rm -rf "$TARGET_DIR/sheep-dog"

echo "Pulling sheep-dog umbrella helm chart from Nexus OCI..."
VERSION_FLAG=()
if [[ -n "$CHART_VERSION" && "$CHART_VERSION" != "latest" ]]; then
    VERSION_FLAG=(--version "$CHART_VERSION")
fi
helm pull "$CHART_OCI" "${VERSION_FLAG[@]}" --untar --untardir "$TARGET_DIR"

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

# Derive the smoke-test target host in this priority order:
#   1. spec.rules[0].host on the Ingress — set directly from values-<env>.yaml
#      `ingress.host` (e.g. dev.sheepdog.io, qa.sheepdog.io). This is the
#      Host header the nginx ingress matches on, so smoke-test MUST use this
#      exact string or nginx returns 404 from the default backend.
#   2. status.loadBalancer.ingress[0].hostname — EKS ELB DNS name, used when
#      values-<env>.yaml deliberately leaves ingress.host empty (prod today).
#   3. status.loadBalancer.ingress[0].ip — minikube tunnel IP (127.0.0.1),
#      final fallback. Only reachable when no Host header rule applies.
#
# (1) is synchronous — it's on the spec, not the status, so no wait loop.
# (2)/(3) need the wait loop because the load balancer address is assigned
# asynchronously after the ingress is created.
SERVICE_URL=$(kubectl get ingress sheep-dog-ingress -n "$NAMESPACE" \
    -o jsonpath="{.spec.rules[0].host}" 2>/dev/null || true)
if [[ -n "$SERVICE_URL" ]]; then
    echo "Using ingress host rule: $SERVICE_URL"
else
    echo "Waiting for Ingress load-balancer address (up to 5 minutes)..."
    for i in $(seq 1 30); do
        SERVICE_URL=$(kubectl get ingress sheep-dog-ingress -n "$NAMESPACE" \
            -o jsonpath="{.status.loadBalancer.ingress[0].hostname}" 2>/dev/null || true)
        if [[ -z "$SERVICE_URL" ]]; then
            SERVICE_URL=$(kubectl get ingress sheep-dog-ingress -n "$NAMESPACE" \
                -o jsonpath="{.status.loadBalancer.ingress[0].ip}" 2>/dev/null || true)
        fi
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
fi

kubectl get services -n "$NAMESPACE"

# Write SERVICE_URL to a file so parent shells (bash or cmd wrappers that
# invoke this script as a child process) can recover the ingress URL.
# Child env vars don't leak up to the parent, so file-based handoff is the
# portable mechanism.
echo "$SERVICE_URL" > "$TARGET_DIR/service_url.txt"

# Emit GitHub Actions output if running under Actions.
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "service_url=$SERVICE_URL" >> "$GITHUB_OUTPUT"
fi

echo "Namespace setup completed successfully!"
