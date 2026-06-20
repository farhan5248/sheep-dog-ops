#!/usr/bin/env bash
# Delete (destroy) the minikube cluster. Counterpart to minikube/teardown-cluster.bat
# and the bottom of the lifecycle: setup/start/start-tunnel (up) <->
# stop-tunnel/stop-cluster/teardown (down).
#
# DESTRUCTIVE — wipes all cluster state. NOT part of the reboot cycle: to reboot
# the host, use stop-tunnel.sh + stop-cluster.sh (which preserve state), then
# setup-cluster-ubuntu-<role>.sh afterwards. Teardown only matters for the
# AWS/EKS lifecycle (eks/teardown-cluster.sh) or a deliberate full local reset.
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
