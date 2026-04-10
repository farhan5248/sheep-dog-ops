#!/usr/bin/env bash
# Uninstall the sheep-dog umbrella helm release from a Kubernetes namespace.
#
# Kubernetes-distribution-agnostic: caller must point kubectl at the target
# cluster before running this script.
#
# On EKS, ingress-nginx and its NLB are owned by the EKS layer
# (eks/setup-cluster.bat installs them; eks/teardown-cluster.bat removes
# them). Namespace teardown only removes the sheep-dog helm release, so
# teardown-namespace + setup-namespace is a valid redeploy loop.
#
# Usage: teardown-namespace.sh <namespace>

set -euo pipefail

NAMESPACE="${1:-}"

if [[ -z "$NAMESPACE" ]]; then
    echo "Usage: teardown-namespace.sh <namespace>"
    echo "Example: teardown-namespace.sh qa"
    exit 1
fi

command -v kubectl >/dev/null 2>&1 || { echo "kubectl is not installed."; exit 1; }
command -v helm    >/dev/null 2>&1 || { echo "helm is not installed.";    exit 1; }

echo "Current kubectl context: $(kubectl config current-context)"
echo "Uninstalling sheep-dog umbrella helm release from namespace $NAMESPACE..."
helm uninstall sheep-dog -n "$NAMESPACE" --ignore-not-found

echo "Namespace teardown completed."
