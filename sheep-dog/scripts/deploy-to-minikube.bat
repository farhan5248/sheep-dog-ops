@echo off
setlocal
echo %time%
echo Deploying sheep-dog to minikube

REM Deploy to an existing minikube cluster. Sets the kubectl context to
REM minikube, installs the umbrella chart into the given namespace, then
REM runs the smoke-test suite against the resulting ingress address.
REM
REM Usage:
REM   deploy-to-minikube.bat [env] [version]
REM
REM Defaults:
REM   env     = dev
REM   version = latest    (resolves to newest chart in Nexus; see setup-namespace.bat)
REM
REM Examples:
REM   deploy-to-minikube.bat                -- dev namespace, latest chart
REM   deploy-to-minikube.bat qa             -- qa  namespace, latest chart
REM   deploy-to-minikube.bat qa 0.2.3       -- qa  namespace, pinned 0.2.3

set ENV=%1
set CHART_VERSION=%2

if "%ENV%"=="" set ENV=dev
if "%CHART_VERSION%"=="" set CHART_VERSION=latest

set SCRIPTS_DIR=%~dp0

echo --- Select minikube context ---
kubectl config use-context minikube
if %ERRORLEVEL% neq 0 (
    echo Failed to switch kubectl context to minikube.
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
