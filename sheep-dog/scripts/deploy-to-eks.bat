@echo off
setlocal
echo %time%
echo Running sheep-dog full EKS deploy (cluster setup + deploy + smoke + teardown)

REM Full-lifecycle EKS deploy. Provisions the cluster, installs the umbrella
REM chart into the given namespace, runs smoke tests, then tears the namespace
REM and cluster back down.
REM
REM Usage:
REM   deploy-to-eks.bat [env] [version]
REM
REM Defaults:
REM   env     = dev
REM   version = latest
REM
REM Examples:
REM   deploy-to-eks.bat prod 0.2.3   -- full EKS lifecycle, pinned chart
REM   deploy-to-eks.bat prod         -- full EKS lifecycle, latest chart

set ENV=%1
set CHART_VERSION=%2

if "%ENV%"=="" set ENV=dev
if "%CHART_VERSION%"=="" set CHART_VERSION=latest

set SCRIPTS_DIR=%~dp0
set EKS_DIR=%~dp0..\..\infra\eks\

if not exist "%EKS_DIR%setup-cluster.bat" (
    echo eks/setup-cluster.bat not found under %EKS_DIR%
    exit /b 1
)

echo --- Setup cluster (eks) ---
call "%EKS_DIR%setup-cluster.bat" %ENV%
if %ERRORLEVEL% neq 0 (
    echo Setup cluster failed.
    exit /b 1
)

echo --- Select EKS cluster ---
set STACK_NAME=sheep-dog-aws-%ENV%
for /f "tokens=*" %%i in ('aws cloudformation describe-stacks --stack-name %STACK_NAME% --query "Stacks[0].Outputs[?OutputKey=='ClusterName'].OutputValue" --output text --region us-east-1') do set CLUSTER_NAME=%%i
if "%CLUSTER_NAME%"=="" (
    echo Failed to get EKS cluster name from stack %STACK_NAME%.
    exit /b 1
)
aws eks update-kubeconfig --name %CLUSTER_NAME% --region us-east-1
if %ERRORLEVEL% neq 0 (
    echo Failed to update kubeconfig for EKS cluster.
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

echo --- Teardown cluster (eks) ---
call "%EKS_DIR%teardown-cluster.bat" %ENV%
if %ERRORLEVEL% neq 0 (
    echo Teardown cluster failed.
    exit /b 1
)

echo Full deploy completed successfully!
echo %time%
endlocal
