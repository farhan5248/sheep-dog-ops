@echo off
setlocal
echo %time%
echo Deploying sheep-dog to minikube

REM Deploy to an existing minikube cluster. Sets the kubectl context to
REM the given name (default "minikube"), installs the umbrella chart into
REM the given namespace, then runs the smoke-test suite against the
REM resulting ingress address.
REM
REM Usage:
REM   deploy-to-minikube.bat [env] [version] [kubectl-context]
REM
REM Defaults:
REM   env             = dev
REM   version         = latest        (resolves to newest chart in Nexus; see setup-namespace.bat)
REM   kubectl-context = minikube
REM
REM Examples:
REM   deploy-to-minikube.bat                              -- dev namespace, latest chart, local minikube
REM   deploy-to-minikube.bat qa                           -- qa  namespace, latest chart, local minikube
REM   deploy-to-minikube.bat qa 0.2.3                     -- qa  namespace, pinned 0.2.3, local minikube
REM   deploy-to-minikube.bat qa latest ubuntu-sandbox     -- qa namespace, latest chart, remote ubuntu-sandbox cluster
REM
REM The context arg lets a -client machine (which has its own local
REM context renamed per #376, e.g. "ubuntu-client") deploy to a remote
REM LAN cluster (e.g. "ubuntu-sandbox") without touching the script.
REM Hosts whose local context is still called "minikube" can omit it.
REM See tools.network.md § Remote kubectl access.

set ENV=%1
set CHART_VERSION=%2
set CONTEXT=%3

if "%ENV%"=="" set ENV=dev
if "%CHART_VERSION%"=="" set CHART_VERSION=latest
if "%CONTEXT%"=="" set CONTEXT=minikube

set SCRIPTS_DIR=%~dp0

echo --- Select kubectl context (%CONTEXT%) ---
kubectl config use-context %CONTEXT%
if %ERRORLEVEL% neq 0 (
    echo Failed to switch kubectl context to %CONTEXT%.
    exit /b 1
)

echo --- Setup namespace (%ENV%, chart %CHART_VERSION%) ---
call "%SCRIPTS_DIR%setup-namespace.bat" %ENV% %CHART_VERSION%
if %ERRORLEVEL% neq 0 (
    echo Setup namespace failed.
    exit /b 1
)

echo --- Smoke test (%SERVICE_URL%) ---
call "%SCRIPTS_DIR%smoke-test.bat" %SERVICE_URL%
if %ERRORLEVEL% neq 0 (
    echo Smoke test failed.
    exit /b 1
)

echo Deploy completed successfully!
echo %time%
endlocal
