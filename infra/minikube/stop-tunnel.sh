#!/usr/bin/env bash
# Stop the detached `minikube tunnel`. Counterpart to start-tunnel-detached.sh.
# First step of the shutdown sequence (stop-tunnel -> stop-cluster -> teardown);
# run it before a host reboot.
#
# Why it also removes tunnels.json:
#   `minikube tunnel` runs as root and writes ~/.minikube/tunnels.json owned by
#   root. If the host reboots with the tunnel still running, that file is left
#   root-owned and blocks the next tunnel from starting ("permission denied" /
#   TUNNEL_ALREADY_RUNNING). Killing it cleanly and removing the file avoids
#   that. Surfaced 2026-06-20 recovering ubuntu-team after a reboot.
#
# Reads $SUDO_PASSWORD from the environment (see tools-ubuntu.md
# § Sudo password file). Usage: ./stop-tunnel.sh

set -uo pipefail

if [[ -z "${SUDO_PASSWORD:-}" ]]; then
    echo "ERROR: \$SUDO_PASSWORD is not set (see tools-ubuntu.md § Sudo password file)." >&2
    exit 1
fi

if pgrep -f "minikube tunnel" >/dev/null; then
    echo "Stopping minikube tunnel..."
    echo "$SUDO_PASSWORD" | sudo -S pkill -f "minikube tunnel" 2>/dev/null || true
    sleep 2
else
    echo "No minikube tunnel running."
fi

# Remove the (root-owned) tunnels.json so the next start-tunnel-detached.sh is clean.
echo "$SUDO_PASSWORD" | sudo -S rm -f "$HOME/.minikube/tunnels.json" 2>/dev/null || true

echo "Tunnel stopped."
