#!/usr/bin/env bash
# Convenience wrapper for ubuntu-team (windows-minipc post-conversion to
# Ubuntu, 32 GiB RAM). LAN-facing — primary Darmok host, runs
# setup-cluster.sh which sets up iptables DNAT for ports 80/443/8443 plus
# the apiserver-ips SAN so other LAN machines can reach the ingress and
# the apiserver via remote kubectl. Rename per #376.
# Tune values here if the host's resources change.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/setup-cluster.sh" 24576 8 60g
