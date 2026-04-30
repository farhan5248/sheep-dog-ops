#!/usr/bin/bash
set -e

echo "Starting minikube..."
minikube start --cpus=4

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
