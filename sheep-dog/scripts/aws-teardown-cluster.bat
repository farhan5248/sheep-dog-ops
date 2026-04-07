@echo off
setlocal enabledelayedexpansion
echo %time%
echo Tearing down AWS CloudFormation stack

set SUFFIX=%1
set BASE_STACK_NAME=sheep-dog-aws
set REGION=us-east-1
set NAMESPACE=prod

if "%SUFFIX%"=="" (
    echo Usage: aws-teardown-stack.bat [suffix]
    echo Example with suffix: aws-teardown-stack.bat 1
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

REM For EKS, we need to clean up Kubernetes resources first
echo Checking if kubectl is installed...
kubectl version --client
if %ERRORLEVEL% neq 0 (
    echo kubectl is not installed. Please install it first.
    exit /b 1
)

echo Getting EKS cluster name...
for /f "tokens=*" %%i in ('aws cloudformation describe-stacks --stack-name %STACK_NAME% --query "Stacks[0].Outputs[?OutputKey=='ClusterName'].OutputValue" --output text --region %REGION%') do set CLUSTER_NAME=%%i

if not "%CLUSTER_NAME%"=="" (
    echo Configuring kubectl to connect to the EKS cluster...
    aws eks update-kubeconfig --name %CLUSTER_NAME% --region %REGION%

    echo Deleting ingress-nginx namespace (releases the NLB)...
    kubectl delete namespace ingress-nginx --ignore-not-found=true --timeout=300s

    echo Waiting for cluster load balancers to be deleted (up to 5 minutes)...
    for /l %%i in (1,1,30) do (
        for /f "delims=" %%c in ('aws resourcegroupstaggingapi get-resources --resource-type-filters elasticloadbalancing:loadbalancer --tag-filters "Key=kubernetes.io/cluster/%CLUSTER_NAME%,Values=owned" --query "length(ResourceTagMappingList)" --output text --region %REGION%') do set LB_COUNT=%%c
        if "!LB_COUNT!"=="0" (
            echo All cluster load balancers deleted.
            goto :lbs_deleted
        )
        echo Waiting for !LB_COUNT! load balancer^(s^)... ^(attempt %%i/30^)
        timeout /t 10 >nul
    )
    echo ERROR: Timed out waiting for load balancers to be deleted.
    exit /b 1
    :lbs_deleted

    echo Deleting Kubernetes app resources...
    kubectl delete -k ../kubernetes/complete/overlays/%NAMESPACE%/ --ignore-not-found=true
)

echo %time%
