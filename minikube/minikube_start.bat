@echo off
echo Starting minikube...
REM On windows-desktop, mount D:\minikube-data\nexus so the Nexus PVC survives `minikube delete`.
REM Other machines skip the mount (directory won't exist).
if exist D:\minikube-data\nexus (
    echo Mounting D:\minikube-data\nexus into minikube at /mnt/nexus...
    minikube start --mount --mount-string="D:\minikube-data\nexus:/mnt/nexus"
) else (
    minikube start
)

echo Enabling ingress addon...
minikube addons enable ingress

echo Waiting for ingress controller to be ready...
timeout /t 30 /nobreak >nul

echo Patching ingress-nginx-controller to LoadBalancer...
kubectl patch svc ingress-nginx-controller -n ingress-nginx -p "{\"spec\":{\"type\":\"LoadBalancer\"}}"

echo Done! Ingress controller should now be LoadBalancer type.
kubectl get svc -n ingress-nginx

echo Starting tunnel (update hosts file with the EXTERNAL-IP from above)
minikube tunnel
