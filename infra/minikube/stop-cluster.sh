#!/usr/bin/env bash
# Gracefully stop the minikube cluster. Counterpart to the `minikube start`
# inside setup-cluster-local.sh. Second step of the shutdown sequence
# (stop-tunnel -> stop-cluster -> teardown); run it before a host reboot.
#
# This PRESERVES all cluster state (namespaces, deployments, PVs, the Nexus PV)
# — it is NOT a teardown. After the reboot, bring the cluster back with
# setup-cluster-ubuntu-<role>.sh (which re-applies the iptables LAN-exposure
# rules a reboot wipes) then start-tunnel-detached.sh.
#
# `minikube delete` (teardown-cluster.sh) is the destroy step and only matters
# for the AWS/EKS lifecycle or a full local reset — do NOT use it in the reboot
# cycle.
#
# Usage: ./stop-cluster.sh

set -euo pipefail

command -v minikube >/dev/null 2>&1 || { echo "ERROR: minikube is not installed." >&2; exit 1; }

echo "Stopping minikube cluster (state preserved)..."
minikube stop

echo "Cluster stopped. Safe to reboot."
