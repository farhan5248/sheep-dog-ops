#!/usr/bin/env bash
# Delete the minikube cluster. Counterpart to minikube/teardown-cluster.bat.
#
# Usage: minikube/teardown-cluster.sh [namespace]
# The namespace arg is accepted for signature parity with
# eks/teardown-cluster.sh but ignored — minikube has one cluster.

set -euo pipefail

NAMESPACE="${1:-}"

if [[ -z "$NAMESPACE" ]]; then
    echo "Usage: minikube/teardown-cluster.sh <namespace>"
    echo "Example: minikube/teardown-cluster.sh dev"
    exit 1
fi

command -v minikube >/dev/null 2>&1 || { echo "minikube is not installed."; exit 1; }

echo "Deleting minikube cluster..."
minikube delete

echo "Minikube teardown completed."
