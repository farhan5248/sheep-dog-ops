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
# On the Darmok host, mount $HOME/minikube-data/darmok-metrics so Darmok's
# per-scenario metrics.csv is readable by the Grafana pod (sheep-dog-main#252 / #281).
# Other machines skip the mount (directory doesn't exist).
DARMOK_METRICS_DIR="$HOME/minikube-data/darmok-metrics"
if [[ -d "$DARMOK_METRICS_DIR" ]]; then
    echo "Mounting $DARMOK_METRICS_DIR into minikube at /mnt/darmok-metrics..."
    minikube start --cpus="$CPUS" --memory="$MEMORY_MB" --disk-size="$DISK_SIZE" --mount --mount-string="$DARMOK_METRICS_DIR:/mnt/darmok-metrics" "${APISERVER_FLAG[@]}"
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
