#!/usr/bin/env bash
# Convenience wrapper for ubuntu-sandbox (was ubuntu-minipc, 8 GiB RAM).
# LAN-facing — Darmok host candidate, runs setup-cluster.sh which sets up
# iptables DNAT for ports 80/443/8443 plus the apiserver-ips SAN so other
# LAN machines (e.g. ubuntu-client) can reach the ingress and the
# apiserver via remote kubectl. Rename per #376.
# Tune values here if the host's resources change.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/setup-cluster.sh" 5120 4 20g
