#!/usr/bin/env bash
# Point kubectl at the minikube cluster. Signature-compatible with
# eks/select-cluster.sh so deploy*.sh / deploy*.bat can treat the two
# interchangeably.
#
# Usage: minikube/select-cluster.sh <namespace>
# The namespace arg is accepted for signature parity with
# eks/select-cluster.sh but ignored — minikube has one fixed context
# regardless of the target namespace.

set -euo pipefail

NAMESPACE="${1:-}"

if [[ -z "$NAMESPACE" ]]; then
    echo "Usage: minikube/select-cluster.sh <namespace>"
    echo "Example: minikube/select-cluster.sh dev"
    exit 1
fi

command -v kubectl  >/dev/null 2>&1 || { echo "kubectl is not installed.";  exit 1; }
command -v minikube >/dev/null 2>&1 || { echo "minikube is not installed."; exit 1; }

echo "Switching kubectl context to minikube..."
kubectl config use-context minikube

# `kubectl config use-context` only validates that the context exists in
# kubeconfig, not that the cluster is actually reachable. A stopped minikube
# VM leaves the context in place, so downstream scripts (helm install, etc.)
# would hang deep inside the first kubectl/helm call. Probe minikube status
# here so callers see a clear error up front.
if ! minikube status >/dev/null 2>&1; then
    echo "Minikube is not running. Start it (minikube start or the platform's"
    echo "setup-cluster script) before running this script."
    exit 1
fi

echo "Current kubectl context: $(kubectl config current-context)"
