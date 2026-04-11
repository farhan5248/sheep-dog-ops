@echo off
setlocal
echo %time%
echo Deploying sheep-dog to an existing Kubernetes cluster

REM Cluster-agnostic deploy: assumes the target cluster is ALREADY provisioned.
REM Selects the cluster, installs the umbrella chart into the given namespace,
REM then runs the smoke-test suite against the resulting ingress address.
REM
REM Usage:
REM   deploy.bat [env] [version] [cluster]
REM
REM Defaults:
REM   env     = dev
REM   version = latest    (resolves to newest chart in Nexus; see setup-namespace.bat)
REM   cluster = minikube  (must match a directory under sheep-dog-ops/)
REM
REM Examples:
REM   deploy.bat                    -- dev namespace, latest chart, minikube
REM   deploy.bat qa                 -- qa  namespace, latest chart, minikube
REM   deploy.bat qa 0.2.3           -- qa  namespace, pinned 0.2.3, minikube
REM   deploy.bat prod 0.2.3 eks     -- prod namespace, pinned 0.2.3, eks
REM
REM Companion script deploy-with-create.bat adds cluster setup + teardown
REM around the same middle. Use that for full end-to-end runs against EKS.

set ENV=%1
set CHART_VERSION=%2
set CLUSTER=%3

if "%ENV%"=="" set ENV=dev
if "%CHART_VERSION%"=="" set CHART_VERSION=latest
if "%CLUSTER%"=="" set CLUSTER=minikube

set SCRIPTS_DIR=%~dp0
set CLUSTER_DIR=%~dp0..\..\%CLUSTER%\

if not exist "%CLUSTER_DIR%select-cluster.bat" (
    echo Unknown cluster "%CLUSTER%": no select-cluster.bat under %CLUSTER_DIR%
    echo Expected one of: minikube, eks
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

echo Deploy completed successfully!
echo %time%
endlocal