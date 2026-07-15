#!/usr/bin/env bash
# Start `minikube tunnel` in the background, detached from the SSH session
# that launches it. Use after setup-cluster-ubuntu-{client,sandbox,team}.sh
# has brought the cluster up — those scripts end with `minikube tunnel`
# foreground, which dies when the SSH session disconnects.
#
# Why the dance:
#   - `minikube tunnel` needs root (it adds routes / manipulates iptables).
#   - `nohup` strips the tty, so a normal `sudo` prompt can't be answered.
#   - `sudo -SE` reads the password from stdin AND preserves the caller's
#     environment — critically HOME, because minikube profiles live in
#     ~/.minikube/ and root's HOME (/root) doesn't have one (#377).
#
# Reads $SUDO_PASSWORD from the environment. On Ubuntu LAN hosts it lives in
# ~/.config/sudo_password (mode 600, sourced from ~/.bashrc) — NOT
# /etc/environment, which is world-readable (see tools-overview.md § env-vars
# and #390). An interactive login shell already has it set; a non-interactive
# SSH session (`ssh host '...'`) does NOT source ~/.bashrc, so run
# `source ~/.config/sudo_password` before this script in that case.
# Fails fast if it isn't set.
#
# Usage: ./start-tunnel-detached.sh
# Idempotent — kills any pre-existing tunnel before launching the new one.

set -euo pipefail

if [[ -z "${SUDO_PASSWORD:-}" ]]; then
    echo "ERROR: \$SUDO_PASSWORD is not set in the environment." >&2
    echo "       Set it in /etc/environment (see tools.ubuntu.md)." >&2
    exit 1
fi

if ! command -v minikube >/dev/null; then
    echo "ERROR: minikube not found in PATH." >&2
    exit 1
fi

if ! minikube profile list 2>/dev/null | grep -q "minikube"; then
    echo "ERROR: no 'minikube' profile found for user $(whoami)." >&2
    echo "       Run setup-cluster-ubuntu-*.sh first to create the cluster." >&2
    exit 1
fi

LOG_FILE="/tmp/tunnel.log"

if pgrep -f "minikube tunnel" >/dev/null; then
    echo "Killing existing minikube tunnel..."
    echo "$SUDO_PASSWORD" | sudo -S pkill -f "minikube tunnel" 2>/dev/null || true
    sleep 1
fi

echo "Launching minikube tunnel detached, log -> $LOG_FILE"
echo "$SUDO_PASSWORD" | sudo -SE nohup minikube tunnel > "$LOG_FILE" 2>&1 &
disown

sleep 3

if ! pgrep -f "minikube tunnel" >/dev/null; then
    echo "ERROR: tunnel did not start. Last log lines:" >&2
    tail -10 "$LOG_FILE" >&2
    exit 1
fi

echo
echo "Tunnel running:"
pgrep -af "minikube tunnel"
echo
echo "Recent log:"
tail -8 "$LOG_FILE"
echo
echo "Safe to disconnect SSH. Tail later with:"
echo "    tail -f $LOG_FILE"
