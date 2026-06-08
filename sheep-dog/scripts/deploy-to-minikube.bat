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
REM   kubectl-context = derived from env:
REM                       dev  -> minikube-sandbox  (LAN cluster on ubuntu-sandbox)
REM                       qa   -> minikube-team     (LAN cluster on ubuntu-team)
REM                       int  -> minikube-team     (LAN cluster on ubuntu-team -- CI/CD integration testing, #455)
REM                       else -> minikube          (local cluster fallback)
REM
REM Examples:
REM   deploy-to-minikube.bat                              -- dev ns, latest chart, ubuntu-sandbox
REM   deploy-to-minikube.bat qa                           -- qa  ns, latest chart, ubuntu-team
REM   deploy-to-minikube.bat qa 0.2.3                     -- qa  ns, pinned 0.2.3, ubuntu-team
REM   deploy-to-minikube.bat dev latest minikube          -- dev ns, latest chart, force local minikube
REM
REM The 3rd arg overrides the derived default -- pass "minikube" to
REM force local-fallback (e.g. when both servers are down -- see
REM lcl.sheepdog.io in tools.ubuntu.client.md). See tools.network.md
REM Remote kubectl access for the context naming convention. Issue #389.

set ENV=%1
set CHART_VERSION=%2
set CONTEXT=%3

if "%ENV%"=="" set ENV=dev
if "%CHART_VERSION%"=="" set CHART_VERSION=latest
if "%CONTEXT%"=="" (
    if "%ENV%"=="dev" (
        set CONTEXT=minikube-sandbox
    ) else if "%ENV%"=="qa" (
        set CONTEXT=minikube-team
    ) else if "%ENV%"=="int" (
        set CONTEXT=minikube-team
    ) else (
        set CONTEXT=minikube
    )
)

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
