@echo off
setlocal
echo %time%
echo Installing Grafana to observability namespace...

set SCRIPT_DIR=%~dp0

REM helm upgrade --install is idempotent — creates on first run, upgrades afterward.
helm upgrade --install grafana "%SCRIPT_DIR%helm\grafana" ^
    --namespace observability ^
    --create-namespace
if errorlevel 1 (
    echo ERROR: helm upgrade --install failed.
    exit /b 1
)

echo --- Waiting for Grafana pod to be Ready ---
kubectl -n observability wait --for=condition=Ready pod -l app.kubernetes.io/name=grafana --timeout=180s
if errorlevel 1 (
    echo ERROR: Grafana pod did not become Ready within 180s.
    kubectl -n observability get pods
    exit /b 1
)

echo --- Pods ---
kubectl -n observability get pods

echo.
echo Grafana installed. To access via tunnel + ingress:
echo   - Requires `minikube tunnel` to be running.
echo   - Requires hosts-file entry: 127.0.0.1 grafana.sheepdog.io
echo.
echo   URL:      http://grafana.sheepdog.io
echo   Dashboard: http://grafana.sheepdog.io/d/darmok-spc
echo   User:     admin
echo   Password:
echo      kubectl -n observability get secret grafana -o jsonpath="{.data.admin-password}" ^| base64 -d
echo %time%
endlocal
