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
#   On Linux + docker driver, `minikube tunnel` doesn't bind any host
#   port — it only adds a route so the LoadBalancer EXTERNAL-IP is
#   reachable via the docker bridge (gateway 192.168.49.1, cluster node
#   192.168.49.2). The minikube ingress controller's 80/443 land on the
#   cluster node IP. We DNAT <LAN-IP>:80/443 to 192.168.49.2 (paralleling
#   the 8443 apiserver DNAT below) and MASQUERADE the forwarded traffic
#   so replies route back through the host instead of leaking direct to
#   the LAN client. Port 443 is needed now that nexus serves HTTPS
#   (#217); 80 is kept for HTTP redirects.
#
#   Earlier versions of this script DNAT'd to 127.0.0.1 on the assumption
#   that the tunnel binds loopback (the Windows portproxy setup does).
#   That's wrong on Linux — packets landed at 127.0.0.1:80/443 with no
#   listener and got RST. Surfaced 2026-05-08 on #377 when forward-
#   engineer from ubuntu-client to minipc's qa.sheepdog.io timed out.
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
# specific address (not 0.0.0.0) so they only intercept LAN-bound traffic
# and don't shadow other listeners on the same ports.
LAN_IP=$(hostname -I | awk '{print $1}')
if [[ -z "$LAN_IP" ]]; then
    echo "ERROR: could not detect LAN IP via 'hostname -I'."
    exit 1
fi
echo "Detected LAN IP: $LAN_IP"

# DNAT target for ingress 80/443 and apiserver 8443 — minikube's docker-
# driver bridge default. See § "Minikube subnet assumption" in tools.network.md.
MINIKUBE_IP="192.168.49.2"

# Clean up any pre-existing rules from older versions of this script
# (which DNAT'd to 127.0.0.1 — broken on Linux, see header comment).
echo "Removing legacy 127.0.0.1 DNAT rules on ports 80 and 443 (if present)..."
for port in 80 443; do
    while sudo iptables -t nat -C PREROUTING -d "$LAN_IP" -p tcp --dport "$port" -j DNAT --to-destination "127.0.0.1:$port" 2>/dev/null; do
        sudo iptables -t nat -D PREROUTING -d "$LAN_IP" -p tcp --dport "$port" -j DNAT --to-destination "127.0.0.1:$port"
    done
done

# Disable route_localnet (was only needed for the broken 127.0.0.1 path).
echo "Disabling net.ipv4.conf.all.route_localnet (no longer needed)..."
sudo sysctl -w net.ipv4.conf.all.route_localnet=0 >/dev/null

echo "Removing any existing DNAT rules on ports 80 and 443 (current target)..."
for port in 80 443; do
    while sudo iptables -t nat -C PREROUTING -d "$LAN_IP" -p tcp --dport "$port" -j DNAT --to-destination "$MINIKUBE_IP:$port" 2>/dev/null; do
        sudo iptables -t nat -D PREROUTING -d "$LAN_IP" -p tcp --dport "$port" -j DNAT --to-destination "$MINIKUBE_IP:$port"
    done
    while sudo iptables -t nat -C POSTROUTING -p tcp -d "$MINIKUBE_IP" --dport "$port" -j MASQUERADE 2>/dev/null; do
        sudo iptables -t nat -D POSTROUTING -p tcp -d "$MINIKUBE_IP" --dport "$port" -j MASQUERADE
    done
done

echo "Adding DNAT: $LAN_IP:80 -> $MINIKUBE_IP:80..."
sudo iptables -t nat -A PREROUTING -d "$LAN_IP" -p tcp --dport 80 -j DNAT --to-destination "$MINIKUBE_IP:80"
sudo iptables -t nat -A POSTROUTING -p tcp -d "$MINIKUBE_IP" --dport 80 -j MASQUERADE
echo "Adding DNAT: $LAN_IP:443 -> $MINIKUBE_IP:443..."
sudo iptables -t nat -A PREROUTING -d "$LAN_IP" -p tcp --dport 443 -j DNAT --to-destination "$MINIKUBE_IP:443"
sudo iptables -t nat -A POSTROUTING -p tcp -d "$MINIKUBE_IP" --dport 443 -j MASQUERADE

# Apiserver (8443) needed for remote `kubectl` from another LAN machine.
# Same DNAT + MASQUERADE pattern as 80/443 above, just on a different port.
# Pairs with --apiserver-ips=$LAN_IP (passed to setup-cluster-local.sh
# below) so the apiserver TLS cert SAN covers the LAN address — the remote
# client connects to https://$LAN_IP:8443 with no SAN mismatch.

echo "Removing any existing DNAT rule on port 8443..."
while sudo iptables -t nat -C PREROUTING -d "$LAN_IP" -p tcp --dport 8443 -j DNAT --to-destination "$MINIKUBE_IP:8443" 2>/dev/null; do
    sudo iptables -t nat -D PREROUTING -d "$LAN_IP" -p tcp --dport 8443 -j DNAT --to-destination "$MINIKUBE_IP:8443"
done
echo "Adding DNAT: $LAN_IP:8443 -> $MINIKUBE_IP:8443..."
sudo iptables -t nat -A PREROUTING -d "$LAN_IP" -p tcp --dport 8443 -j DNAT --to-destination "$MINIKUBE_IP:8443"

echo "Removing any existing POSTROUTING MASQUERADE for $MINIKUBE_IP:8443..."
while sudo iptables -t nat -C POSTROUTING -p tcp -d "$MINIKUBE_IP" --dport 8443 -j MASQUERADE 2>/dev/null; do
    sudo iptables -t nat -D POSTROUTING -p tcp -d "$MINIKUBE_IP" --dport 8443 -j MASQUERADE
done
echo "Adding POSTROUTING MASQUERADE: -> $MINIKUBE_IP:8443..."
sudo iptables -t nat -A POSTROUTING -p tcp -d "$MINIKUBE_IP" --dport 8443 -j MASQUERADE

# Docker's filter-table DOCKER chain DROPs all forwarded traffic to the
# minikube container's IP except the ports minikube explicitly exposed at
# start (8443, 22, 5000, 2376, 32443). 80 and 443 aren't on that list, so
# our DNAT rewrites would land at the bridge and then get dropped by
# DOCKER without these. Add ACCEPTs to DOCKER-USER (which is processed
# before DOCKER) — Docker preserves DOCKER-USER across daemon and
# container restarts, but it's wiped on host reboot. That's why we
# re-apply here on every cluster setup. Surfaced 2026-05-08 on #377.
echo "Adding DOCKER-USER ACCEPTs for $MINIKUBE_IP:80 and :443..."
for port in 80 443; do
    if ! sudo iptables -C DOCKER-USER -d "$MINIKUBE_IP" -p tcp --dport "$port" -j ACCEPT 2>/dev/null; then
        sudo iptables -I DOCKER-USER 1 -d "$MINIKUBE_IP" -p tcp --dport "$port" -j ACCEPT
    fi
done

# ufw: if active, allow inbound 80/443/8443. The DNAT rules above only
# handle rewriting; without an INPUT allow, ufw drops the SYN before NAT
# applies.
if command -v ufw >/dev/null 2>&1 && sudo ufw status | grep -q "Status: active"; then
    echo "Allowing inbound TCP/80, TCP/443, and TCP/8443 in ufw..."
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp
    sudo ufw allow 8443/tcp
fi

echo "LAN exposure configured. Verify later with:"
echo "    sudo iptables -t nat -L PREROUTING -n -v"
if command -v ufw >/dev/null 2>&1; then
    echo "    sudo ufw status"
fi
echo

echo "=== Starting minikube (base script) ==="
# Forward LAN_IP as the apiserver-ips SAN so remote kubectl from other LAN
# machines doesn't hit a TLS SAN mismatch on https://$LAN_IP:8443.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/setup-cluster-local.sh" "$MEMORY_MB" "$CPUS" "$DISK_SIZE" "$LAN_IP"
