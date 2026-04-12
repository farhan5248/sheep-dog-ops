@echo off
setlocal enabledelayedexpansion
echo %time%
echo Deploying sheep-dog umbrella helm chart to a Kubernetes namespace
echo.
echo Caller must set the kubectl context before running this script:
echo   - minikube: kubectl config use-context minikube
echo   - EKS:      aws eks update-kubeconfig --name ^<cluster^> --region ^<r^>

set NAMESPACE=%1
set CHART_VERSION=%2
set CHART_OCI=oci://nexus-docker.sheepdog.io/helm-hosted/sheep-dog

if "%NAMESPACE%"=="" (
    echo Usage: setup-namespace.bat [namespace] [chart-version]
    echo Example: setup-namespace.bat qa 0.2.2
    echo Example: setup-namespace.bat dev          ^(defaults to latest^)
    exit /b 1
)

REM When CHART_VERSION is empty or "latest", omit helm's --version flag so
REM helm pulls the newest available release. Helm's --version takes a
REM semver constraint (not a docker-style "latest" tag) — passing "latest"
REM literally fails with "improper constraint: latest". Callers (qa, prod,
REM pinned e2e) can still pass an explicit semver like 0.2.2 to lock to a
REM specific release.
set CHART_VERSION_FLAG=
if not "%CHART_VERSION%"=="" if /i not "%CHART_VERSION%"=="latest" set CHART_VERSION_FLAG=--version %CHART_VERSION%

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
helm pull %CHART_OCI% %CHART_VERSION_FLAG% --untar --untardir "%TARGET_DIR%"
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

REM Derive the smoke-test target host in this priority order:
REM   1. spec.rules[0].host on the Ingress — set directly from values-<env>.yaml
REM      `ingress.host` (e.g. dev.sheepdog.io, qa.sheepdog.io). This is the
REM      Host header the nginx ingress matches on, so smoke-test MUST use this
REM      exact string or nginx returns 404 from the default backend.
REM   2. status.loadBalancer.ingress[0].hostname — EKS ELB DNS name, used when
REM      values-<env>.yaml deliberately leaves ingress.host empty (prod today).
REM   3. status.loadBalancer.ingress[0].ip — minikube tunnel IP (127.0.0.1),
REM      final fallback. Only reachable when no Host header rule applies.
REM
REM (1) is synchronous — it's on the spec, not the status, so no wait loop.
REM (2)/(3) need the wait loop because the load balancer address is assigned
REM asynchronously after the ingress is created.
REM
REM `ping` is used as the sleep because `timeout /t` rejects redirected
REM stdin, which happens when the .bat is launched via `cmd /c` from a
REM non-TTY parent (e.g. git-bash).
set SERVICE_URL=
for /f "delims=" %%h in ('kubectl get ingress sheep-dog-ingress -n %NAMESPACE% -o jsonpath^="{.spec.rules[0].host}"') do set SERVICE_URL=%%h
if not "%SERVICE_URL%"=="" (
    echo Using ingress host rule: %SERVICE_URL%
    goto :got_url
)

echo Waiting for Ingress load-balancer address (up to 5 minutes)...
for /l %%i in (1,1,30) do (
    for /f "delims=" %%h in ('kubectl get ingress sheep-dog-ingress -n %NAMESPACE% -o jsonpath^="{.status.loadBalancer.ingress[0].hostname}"') do set SERVICE_URL=%%h
    if "!SERVICE_URL!"=="" (
        for /f "delims=" %%h in ('kubectl get ingress sheep-dog-ingress -n %NAMESPACE% -o jsonpath^="{.status.loadBalancer.ingress[0].ip}"') do set SERVICE_URL=%%h
    )
    if not "!SERVICE_URL!"=="" goto :got_url
    echo Waiting for Ingress address... attempt %%i/30
    ping -n 11 127.0.0.1 >nul
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
