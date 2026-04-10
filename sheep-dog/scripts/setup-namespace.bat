@echo off
setlocal enabledelayedexpansion
echo %time%
echo Deploying sheep-dog umbrella helm chart to a Kubernetes namespace
echo.
echo This script is Kubernetes-distribution-agnostic. Point kubectl at your
echo target cluster BEFORE running it:
echo   - minikube: minikube/setup-cluster.bat or setup-cluster-local.bat
echo   - EKS:      eks/setup-cluster.bat ^(which runs aws eks update-kubeconfig^)

set NAMESPACE=%1
set CHART_VERSION=0.2.1
set CHART_OCI=oci://nexus-docker.sheepdog.io/helm-hosted/sheep-dog

if "%NAMESPACE%"=="" (
    echo Usage: setup-namespace.bat [namespace]
    echo Example: setup-namespace.bat qa
    exit /b 1
)

echo Checking if kubectl is installed...
kubectl version --client
if %ERRORLEVEL% neq 0 (
    echo kubectl is not installed. Please install it first.
    exit /b 1
)

echo Checking if helm is installed...
helm version --short > nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo Helm is not installed. Install it and retry.
    exit /b 1
)

echo Current kubectl context:
kubectl config current-context

echo Pulling sheep-dog umbrella helm chart from Nexus OCI...
REM Chart version hardcoded to %CHART_VERSION% until #32 Phase 3 introduces
REM version-^<env^>.txt pin files.
REM Prereqs on the host running this script:
REM   - hosts file has nexus-docker.sheepdog.io
REM   - `helm registry login nexus-docker.sheepdog.io` already done
REM   - mkcert root CA trusted on this machine (see nexus/import-rootCA.bat)
REM
REM Resolve to an absolute path — helm install refuses chart paths containing
REM `..` components (SecureJoin rejects upward traversal).
for %%I in ("%~dp0..\target") do set TARGET_DIR=%%~fI
if not exist "%TARGET_DIR%" mkdir "%TARGET_DIR%"
if exist "%TARGET_DIR%\sheep-dog" rmdir /s /q "%TARGET_DIR%\sheep-dog"
helm pull %CHART_OCI% --version %CHART_VERSION% --untar --untardir "%TARGET_DIR%"
if %ERRORLEVEL% neq 0 (
    echo Failed to pull helm chart.
    exit /b 1
)

echo Deploying sheep-dog umbrella helm chart to namespace %NAMESPACE%...
REM --timeout 15m: cold-start includes image pulls from Nexus, PVC binding,
REM MySQL + Artemis init, and service readiness probes. Default (5m) is too
REM short; observed first-install times in the 7-10m range on both minikube
REM and fresh EKS clusters.
helm upgrade --install sheep-dog "%TARGET_DIR%\sheep-dog" -n %NAMESPACE% --create-namespace -f "%TARGET_DIR%\sheep-dog\helm-values\values-%NAMESPACE%.yaml" --wait --timeout 15m
if %ERRORLEVEL% neq 0 (
    echo Failed to deploy helm chart.
    exit /b 1
)

echo Restarting deployments to pull the latest images...
kubectl rollout restart deployment -n %NAMESPACE% -l app=sheep-dog

echo Waiting for rollouts to complete...
kubectl rollout status deployment -n %NAMESPACE% -l app=sheep-dog
if %ERRORLEVEL% neq 0 (
    echo Deployment rollout failed.
    exit /b 1
)

echo Waiting for Ingress address to be assigned (up to 5 minutes)...
REM EKS populates ingress[0].hostname (ELB DNS name); minikube populates
REM ingress[0].ip (127.0.0.1 via tunnel). Check both so the script is
REM distribution-agnostic.
REM
REM Absolute path to timeout.exe because git-bash coreutils `timeout` can
REM shadow the Windows one via PATH when cmd is spawned from bash.
set SERVICE_URL=
for /l %%i in (1,1,30) do (
    for /f "delims=" %%h in ('kubectl get ingress sheep-dog-ingress -n %NAMESPACE% -o jsonpath^="{.status.loadBalancer.ingress[0].hostname}"') do set SERVICE_URL=%%h
    if "!SERVICE_URL!"=="" (
        for /f "delims=" %%h in ('kubectl get ingress sheep-dog-ingress -n %NAMESPACE% -o jsonpath^="{.status.loadBalancer.ingress[0].ip}"') do set SERVICE_URL=%%h
    )
    if not "!SERVICE_URL!"=="" goto :got_url
    echo Waiting for Ingress address... attempt %%i/30
    C:\Windows\System32\timeout.exe /t 10 /nobreak >nul
)
:got_url
echo Service URL: %SERVICE_URL%
if "%SERVICE_URL%"=="" (
    echo Failed to get Ingress address.
    exit /b 1
)

echo Listing all services...
kubectl get services -n %NAMESPACE%

echo Namespace setup completed successfully!
echo %time%
endlocal & set SERVICE_URL=%SERVICE_URL%
