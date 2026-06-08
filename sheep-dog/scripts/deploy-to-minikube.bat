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
REM   kubectl-context = minikube-<env>  (derived uniformly from env, #456):
REM                       dev -> minikube-dev, int -> minikube-int, qa -> minikube-qa
REM                       (per-machine alias contexts; force local with 3rd arg "minikube")
REM
REM Examples:
REM   deploy-to-minikube.bat                              -- dev ns, latest chart, minikube-dev
REM   deploy-to-minikube.bat qa                           -- qa  ns, latest chart, minikube-qa
REM   deploy-to-minikube.bat qa 0.2.3                     -- qa  ns, pinned 0.2.3, minikube-qa
REM   deploy-to-minikube.bat dev latest minikube          -- dev ns, latest chart, force local minikube
REM
REM The 3rd arg overrides the derived default -- pass "minikube" to
REM force local-fallback (e.g. when both servers are down -- see
REM lcl.sheepdog.io in tools.ubuntu.client.md). See tools.network.md
REM Remote kubectl access for the context naming convention. Issues #389, #456.

set ENV=%1
set CHART_VERSION=%2
set CONTEXT=%3

if "%ENV%"=="" set ENV=dev
if "%CHART_VERSION%"=="" set CHART_VERSION=latest
REM Context derives uniformly from env (#456): dev->minikube-dev,
REM int->minikube-int, qa->minikube-qa (per-machine alias contexts).
if "%CONTEXT%"=="" set CONTEXT=minikube-%ENV%

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
