#!/usr/bin/env bash
# Convenience wrapper for ubuntu-minipc (8 GiB RAM).
# LAN-facing — Darmok host candidate, runs setup-cluster.sh.
# Tune values here if the host's resources change.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/setup-cluster.sh" 5120 4 20g
