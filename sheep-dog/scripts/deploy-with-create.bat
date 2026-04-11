@echo off
setlocal
echo %time%
echo Running sheep-dog full deploy (cluster setup + deploy + smoke + teardown)

REM Full-lifecycle variant of deploy.bat. Provisions the cluster, installs the
REM umbrella chart into the given namespace, runs smoke tests, then tears the
REM namespace and cluster back down.
REM
REM Usage:
REM   deploy-with-create.bat [env] [version] [cluster]
REM
REM Defaults:
REM   env     = dev
REM   version = latest
REM   cluster = minikube
REM
REM Examples:
REM   deploy-with-create.bat prod 0.2.3 eks   -- full EKS lifecycle, pinned chart
REM   deploy-with-create.bat dev              -- (see caveat below)
REM
REM Minikube caveat:
REM   minikube/setup-cluster.bat on this workstation ends with a foreground
REM   `minikube tunnel` (via setup-cluster-local.bat) that never returns, so
REM   calling it from here would hang this script. In practice minikube on
REM   this workstation is a long-lived cluster that's provisioned once and
REM   left up for months, so the full-lifecycle flow is only useful against
REM   EKS. For minikube, provision the cluster once manually and use
REM   deploy.bat thereafter. A future change could background the tunnel via
REM   `powershell Start-Process -PassThru` and track the PID so this script
REM   can support minikube too; for now it's EKS-only and will still run if
REM   you pass cluster=minikube, but expect it to hang on setup-cluster.

set ENV=%1
set CHART_VERSION=%2
set CLUSTER=%3

if "%ENV%"=="" set ENV=dev
if "%CHART_VERSION%"=="" set CHART_VERSION=latest
if "%CLUSTER%"=="" set CLUSTER=minikube

set SCRIPTS_DIR=%~dp0
set CLUSTER_DIR=%~dp0..\..\%CLUSTER%\

if not exist "%CLUSTER_DIR%setup-cluster.bat" (
    echo Unknown cluster "%CLUSTER%": no setup-cluster.bat under %CLUSTER_DIR%
    echo Expected one of: minikube, eks
    exit /b 1
)

echo --- Setup cluster (%CLUSTER%) ---
call "%CLUSTER_DIR%setup-cluster.bat" %ENV%
if %ERRORLEVEL% neq 0 (
    echo Setup cluster failed.
    exit /b 1
)

echo --- Select cluster (%CLUSTER%) ---
call "%CLUSTER_DIR%select-cluster.bat" %ENV%
if %ERRORLEVEL% neq 0 (
    echo Select cluster failed.
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

echo --- Teardown namespace (%ENV%) ---
call "%SCRIPTS_DIR%teardown-namespace.bat" %ENV%
if %ERRORLEVEL% neq 0 (
    echo Teardown namespace failed.
    exit /b 1
)

echo --- Teardown cluster (%CLUSTER%) ---
call "%CLUSTER_DIR%teardown-cluster.bat" %ENV%
if %ERRORLEVEL% neq 0 (
    echo Teardown cluster failed.
    exit /b 1
)

echo Full deploy completed successfully!
echo %time%
endlocal