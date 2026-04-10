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
if errorlevel 1 (
    echo ERROR: minikube start failed.
    exit /b 1
)

REM Import the mkcert root CA into the minikube VM so kubelet/docker can pull
REM images from Nexus over HTTPS. `minikube delete` destroys the VM's trust
REM store, so this must run on every fresh cluster.
REM
REM Order matters: import the CA and restart docker BEFORE enabling the
REM ingress addon. Restarting docker while ingress-nginx is running breaks
REM the admission webhook for ~30s and causes subsequent helm installs to
REM fail with "no route to host" on the webhook service.
echo Importing mkcert root CA into minikube VM...
minikube cp "%~dp0..\nexus\mkcert-rootCA.pem" minikube:/tmp/mkcert-rootCA.crt
if errorlevel 1 (
    echo ERROR: failed to copy mkcert-rootCA.pem into minikube.
    exit /b 1
)
minikube ssh "sudo cp /tmp/mkcert-rootCA.crt /usr/local/share/ca-certificates/mkcert-rootCA.crt && sudo update-ca-certificates && sudo systemctl restart docker"
if errorlevel 1 (
    echo ERROR: failed to install CA inside minikube VM.
    exit /b 1
)

echo Enabling ingress addon...
minikube addons enable ingress

echo Waiting for ingress controller to be ready...
C:\Windows\System32\timeout.exe /t 30 /nobreak >nul

echo Patching ingress-nginx-controller to LoadBalancer...
kubectl patch svc ingress-nginx-controller -n ingress-nginx -p "{\"spec\":{\"type\":\"LoadBalancer\"}}"

echo Done! Ingress controller should now be LoadBalancer type.
kubectl get svc -n ingress-nginx

echo Starting tunnel (update hosts file with the EXTERNAL-IP from above)
minikube tunnel
