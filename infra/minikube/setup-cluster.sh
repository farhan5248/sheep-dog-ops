#!/usr/bin/env bash
# Wrapper around setup-cluster-local.sh for machines that host services
# for the whole LAN (e.g. ubuntu-minipc, windows-minipc-converted-to-ubuntu).
# Exposes the ingress ports (80 + 443) via iptables NAT so other machines
# on the LAN can reach them, THEN hands off to the base script (which
# ends with a foreground `minikube tunnel`).
#
# Why iptables setup comes FIRST:
#   setup-cluster-local.sh ends with `minikube tunnel` as a foreground
#   process, so anything after the call never runs. We configure
#   exposure before the call.
#
# Why this is needed at all:
#   `minikube tunnel` only binds to 127.0.0.1, so the minikube ingress is
#   not reachable across the LAN by default. We DNAT <LAN-IP>:80 and :443
#   to 127.0.0.1 on this host. Port 443 is needed now that nexus serves
#   HTTPS (#217). route_localnet=1 is required to allow the kernel to
#   forward externally-arriving traffic to a 127.0.0.0/8 destination.
#
# Requirements:
#   - sudo available (iptables + sysctl + ufw are privileged)
#   - Do NOT run the script itself as root — minikube's docker driver
#     refuses to run as root, so we sudo the privileged commands only.
#   - Only run on machines that intentionally serve the LAN.
#
# Usage: setup-cluster.sh <memory-mb> <cpus> <disk-size>

set -euo pipefail

if [[ -z "${3:-}" ]]; then
    echo "Usage: $(basename "$0") <memory-mb> <cpus> <disk-size>"
    echo "Example: $(basename "$0") 24576 8 60g"
    exit 1
fi
MEMORY_MB="$1"
CPUS="$2"
DISK_SIZE="$3"

if [[ "$EUID" -eq 0 ]]; then
    echo "ERROR: do not run this script as root. Re-run as your normal user."
    echo "Sudo will be invoked for iptables/sysctl/ufw commands only."
    exit 1
fi

echo "=== Configuring LAN exposure ==="

# Detect this machine's LAN IPv4 address. We bind iptables rules to this
# specific address (not 0.0.0.0) for parity with the Windows portproxy
# setup, which is bound to the LAN IP to avoid colliding with the
# 127.0.0.1 listener that `minikube tunnel` creates.
LAN_IP=$(hostname -I | awk '{print $1}')
if [[ -z "$LAN_IP" ]]; then
    echo "ERROR: could not detect LAN IP via 'hostname -I'."
    exit 1
fi
echo "Detected LAN IP: $LAN_IP"

# route_localnet=1 lets the kernel DNAT externally-arriving traffic to a
# 127.0.0.0/8 destination. Without it, the DNAT rule below is silently
# dropped because Linux normally treats loopback addresses on non-loopback
# interfaces as martians.
echo "Enabling net.ipv4.conf.all.route_localnet..."
sudo sysctl -w net.ipv4.conf.all.route_localnet=1

echo "Removing any existing DNAT rules on ports 80 and 443..."
for port in 80 443; do
    while sudo iptables -t nat -C PREROUTING -d "$LAN_IP" -p tcp --dport "$port" -j DNAT --to-destination "127.0.0.1:$port" 2>/dev/null; do
        sudo iptables -t nat -D PREROUTING -d "$LAN_IP" -p tcp --dport "$port" -j DNAT --to-destination "127.0.0.1:$port"
    done
done

echo "Adding DNAT: $LAN_IP:80 -> 127.0.0.1:80..."
sudo iptables -t nat -A PREROUTING -d "$LAN_IP" -p tcp --dport 80 -j DNAT --to-destination 127.0.0.1:80
echo "Adding DNAT: $LAN_IP:443 -> 127.0.0.1:443..."
sudo iptables -t nat -A PREROUTING -d "$LAN_IP" -p tcp --dport 443 -j DNAT --to-destination 127.0.0.1:443

# ufw: if active, allow inbound 80/443. The DNAT rule above only handles
# rewriting; without an INPUT allow, ufw drops the SYN before NAT applies.
if command -v ufw >/dev/null 2>&1 && sudo ufw status | grep -q "Status: active"; then
    echo "Allowing inbound TCP/80 and TCP/443 in ufw..."
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp
fi

echo "LAN exposure configured. Verify later with:"
echo "    sudo iptables -t nat -L PREROUTING -n -v"
if command -v ufw >/dev/null 2>&1; then
    echo "    sudo ufw status"
fi
echo

echo "=== Starting minikube (base script) ==="
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/setup-cluster-local.sh" "$MEMORY_MB" "$CPUS" "$DISK_SIZE"
