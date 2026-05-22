#!/usr/bin/bash
set -e

if [[ -z "${3:-}" ]]; then
    echo "Usage: $(basename "$0") <memory-mb> <cpus> <disk-size> [apiserver-ip]"
    echo "Example: $(basename "$0") 10240 6 30g"
    echo "Example: $(basename "$0") 5120 4 20g 192.168.2.253"
    exit 1
fi
MEMORY_MB="$1"
CPUS="$2"
DISK_SIZE="$3"
# Optional 4th arg: a LAN IP to add to the apiserver TLS cert SANs so remote
# kubectl from another machine doesn't hit a SAN mismatch. Only the LAN-facing
# wrapper (setup-cluster.sh) passes this through; local-only callers leave it empty.
APISERVER_IP="${4:-}"

APISERVER_FLAG=()
if [[ -n "$APISERVER_IP" ]]; then
    APISERVER_FLAG=(--apiserver-ips="$APISERVER_IP")
    echo "Adding $APISERVER_IP to apiserver TLS cert SANs."
fi

echo "Starting minikube with --memory=$MEMORY_MB --cpus=$CPUS --disk-size=$DISK_SIZE..."
# Mount the entire $HOME/minikube-data parent dir at /mnt so every per-role
# subdir comes along under a stable in-VM path. minikube's --mount-string is
# single-valued, so a parent-dir mount is the only way to expose more than
# one host directory. Today's consumers:
#   - $HOME/minikube-data/darmok-metrics -> /mnt/darmok-metrics
#     Darmok per-scenario metrics.csv read by the Grafana pod (#252 / #281).
#   - $HOME/minikube-data/nexus -> /mnt/nexus
#     Nexus PV hostPath on the Nexus host (#378). Survives minikube delete.
# Machines that don't host either still get the mount if the parent exists;
# harmless. Machines that have neither subdir skip the mount entirely.
MINIKUBE_DATA_DIR="$HOME/minikube-data"
if [[ -d "$MINIKUBE_DATA_DIR" ]]; then
    echo "Mounting $MINIKUBE_DATA_DIR into minikube at /mnt..."
    minikube start --cpus="$CPUS" --memory="$MEMORY_MB" --disk-size="$DISK_SIZE" --mount --mount-string="$MINIKUBE_DATA_DIR:/mnt" "${APISERVER_FLAG[@]}"
else
    minikube start --cpus="$CPUS" --memory="$MEMORY_MB" --disk-size="$DISK_SIZE" "${APISERVER_FLAG[@]}"
fi

# Import the mkcert root CA into the minikube VM so kubelet/docker can pull
# images from Nexus over HTTPS. `minikube delete` destroys the VM's trust
# store, so this must run on every fresh cluster.
#
# Order matters: import the CA and restart docker BEFORE enabling the
# ingress addon. Restarting docker while ingress-nginx is running breaks
# the admission webhook for ~30s and causes subsequent helm installs to
# fail with "no route to host" on the webhook service.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CA_PEM="$SCRIPT_DIR/../nexus/mkcert-rootCA.pem"

echo "Importing mkcert root CA into minikube VM..."
minikube cp "$CA_PEM" minikube:/tmp/mkcert-rootCA.crt
minikube ssh "sudo cp /tmp/mkcert-rootCA.crt /usr/local/share/ca-certificates/mkcert-rootCA.crt && sudo update-ca-certificates && sudo systemctl restart docker"

echo "Enabling ingress addon..."
minikube addons enable ingress

echo "Waiting for ingress controller to be ready..."
sleep 30

echo "Patching ingress-nginx-controller to LoadBalancer..."
kubectl patch svc ingress-nginx-controller -n ingress-nginx -p '{"spec":{"type":"LoadBalancer"}}'

echo "Done! Ingress controller should now be LoadBalancer type."
kubectl get svc -n ingress-nginx

echo "Starting tunnel (update /etc/hosts with the EXTERNAL-IP from above)"
minikube tunnel
