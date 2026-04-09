@echo off
setlocal enabledelayedexpansion
echo %time%
echo Uninstalling sheep-dog umbrella helm release from an EKS namespace

set SUFFIX=%1
set BASE_STACK_NAME=sheep-dog-aws
set REGION=us-east-1
set NAMESPACE=prod

if "%SUFFIX%"=="" (
    echo Usage: aws-teardown-namespace.bat [suffix]
    echo Example with suffix: aws-teardown-namespace.bat 1
    exit /b 1
) else (
    set STACK_NAME=%BASE_STACK_NAME%-%SUFFIX%
)

echo Using stack name with suffix: %STACK_NAME%

echo Checking if AWS CLI is installed...
aws --version
if %ERRORLEVEL% neq 0 (
    echo AWS CLI is not installed. Please install it first.
    exit /b 1
)

echo Checking if you are logged in to AWS...
aws sts get-caller-identity
if %ERRORLEVEL% neq 0 (
    echo You are not logged in to AWS. Please run 'aws configure' first.
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

echo Getting EKS cluster name...
for /f "tokens=*" %%i in ('aws cloudformation describe-stacks --stack-name %STACK_NAME% --query "Stacks[0].Outputs[?OutputKey=='ClusterName'].OutputValue" --output text --region %REGION%') do set CLUSTER_NAME=%%i

if "%CLUSTER_NAME%"=="" (
    echo No cluster found in stack %STACK_NAME%, nothing to uninstall.
    goto :done
)

echo Configuring kubectl to connect to the EKS cluster...
aws eks update-kubeconfig --name %CLUSTER_NAME% --region %REGION%

REM The namespace script only owns the sheep-dog helm release. ingress-nginx
REM (and the NLB it holds) is owned by the EKS script, which installs it
REM and is responsible for tearing it down. This split means a namespace can
REM be torn down and redeployed without losing the NLB, so
REM `teardown-namespace` followed by `setup-namespace` is a valid redeploy
REM loop.
echo Uninstalling sheep-dog umbrella helm release...
helm uninstall sheep-dog -n %NAMESPACE% --ignore-not-found

:done
echo Restoring kubectl context to minikube...
kubectl config use-context minikube
if %ERRORLEVEL% neq 0 (
    echo WARNING: Failed to switch kubectl context back to minikube. Please restore manually.
)

echo %time%
