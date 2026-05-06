#!/usr/bin/env bash
# Convenience wrapper for ubuntu-mac (16 GiB RAM, 8 vCPU).
# Not LAN-facing — runs setup-cluster-local.sh directly.
# Tune values here if the host's resources change.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/setup-cluster-local.sh" 10240 6 30g
