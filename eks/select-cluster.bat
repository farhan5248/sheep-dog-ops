@echo off
setlocal enabledelayedexpansion
echo %time%
echo Selecting EKS cluster for downstream sheep-dog scripts

set NAMESPACE=%1
set BASE_STACK_NAME=sheep-dog-aws
set REGION=us-east-1

if "%NAMESPACE%"=="" (
    echo Usage: select-cluster.bat [namespace]
    echo Example: select-cluster.bat prod
    exit /b 1
)

set STACK_NAME=%BASE_STACK_NAME%-%NAMESPACE%

echo Checking if AWS CLI is installed...
aws --version
if %ERRORLEVEL% neq 0 (
    echo AWS CLI is not installed. Please install it first.
    exit /b 1
)

echo Checking if kubectl is installed...
kubectl version --client
if %ERRORLEVEL% neq 0 (
    echo kubectl is not installed. Please install it first.
    exit /b 1
)

echo Checking if you are logged in to AWS...
aws sts get-caller-identity
if %ERRORLEVEL% neq 0 (
    echo You are not logged in to AWS. Please run 'aws configure' first.
    exit /b 1
)

echo Getting EKS cluster name from stack %STACK_NAME%...
for /f "tokens=*" %%i in ('aws cloudformation describe-stacks --stack-name %STACK_NAME% --query "Stacks[0].Outputs[?OutputKey=='ClusterName'].OutputValue" --output text --region %REGION%') do set CLUSTER_NAME=%%i

if "!CLUSTER_NAME!"=="" (
    echo Failed to get EKS cluster name from CloudFormation stack %STACK_NAME%.
    echo Provision the cluster first with eks/setup-cluster.bat %NAMESPACE%.
    exit /b 1
)

echo Configuring kubectl to connect to EKS cluster !CLUSTER_NAME!...
aws eks update-kubeconfig --name !CLUSTER_NAME! --region %REGION%
if %ERRORLEVEL% neq 0 (
    echo Failed to update kubeconfig for EKS cluster.
    exit /b 1
)

echo Current kubectl context:
kubectl config current-context
echo %time%
endlocal
