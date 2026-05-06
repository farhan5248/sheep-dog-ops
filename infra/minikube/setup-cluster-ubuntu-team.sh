#!/usr/bin/env bash
# Convenience wrapper for windows-minipc post-conversion to Ubuntu (32 GiB RAM).
# LAN-facing — primary Darmok host, runs setup-cluster.sh.
# Tune values here if the host's resources change.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/setup-cluster.sh" 24576 8 60g
