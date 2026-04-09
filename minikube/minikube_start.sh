#!/usr/bin/bash
echo "Starting minikube..."
minikube start

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
