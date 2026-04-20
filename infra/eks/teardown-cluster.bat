@echo off
setlocal enabledelayedexpansion
echo %time%
echo Tearing down AWS EKS cluster (ingress-nginx + CloudFormation stack)

set NAMESPACE=%1
set BASE_STACK_NAME=sheep-dog-aws
set REGION=us-east-1

if "%NAMESPACE%"=="" (
    echo Usage: teardown-cluster.bat [namespace]
    echo Example: teardown-cluster.bat prod
    exit /b 1
) else (
    set STACK_NAME=%BASE_STACK_NAME%-%NAMESPACE%
)

REM ACCOUNT_ID must be set as a system environment variable. Mechanical
REM parity with eks/teardown-cluster.sh.
if "%ACCOUNT_ID%"=="" (
    echo ACCOUNT_ID environment variable is not set.
    echo Set it as a persistent Windows env var to your AWS account ID.
    exit /b 1
)

echo Using stack name: %STACK_NAME%

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

REM ingress-nginx and its NLB are owned by the cluster layer (setup-cluster
REM installs them, teardown-cluster removes them). Namespace teardown only removes the
REM sheep-dog helm release, so teardown-namespace + setup-namespace is a
REM valid redeploy loop that keeps the NLB alive.
if not "%CLUSTER_NAME%"=="" (
    echo Configuring kubectl to connect to the EKS cluster...
    aws eks update-kubeconfig --name %CLUSTER_NAME% --region %REGION%

    echo Deleting ingress-nginx namespace ^(releases the NLB^)...
    kubectl delete namespace ingress-nginx --ignore-not-found=true --timeout=300s

    echo Waiting for cluster load balancers to be deleted ^(up to 5 minutes^)...
    set LB_DELETED=0
    for /l %%i in (1,1,30) do (
        if "!LB_DELETED!"=="0" (
            for /f "delims=" %%c in ('aws resourcegroupstaggingapi get-resources --resource-type-filters elasticloadbalancing:loadbalancer --tag-filters "Key=kubernetes.io/cluster/%CLUSTER_NAME%,Values=owned" --query "length(ResourceTagMappingList)" --output text --region %REGION%') do set LB_COUNT=%%c
            if "!LB_COUNT!"=="0" (
                set LB_DELETED=1
                echo All cluster load balancers deleted.
            ) else (
                echo Waiting for !LB_COUNT! load balancer^(s^)... ^(attempt %%i/30^)
                timeout /t 10 >nul
            )
        )
    )
    if "!LB_DELETED!"=="0" (
        echo ERROR: Timed out waiting for load balancers to be deleted.
        exit /b 1
    )
)


REM Set these variables as needed
set ROLE_NAME=EBSCSIDriverRole

echo Deleting EBS policies...

REM Detach the policy from the role
aws iam detach-role-policy --role-name %ROLE_NAME% --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy

REM Delete the IAM role
aws iam delete-role --role-name %ROLE_NAME%

REM Get the OIDC URL from the EKS cluster
for /f "delims=" %%i in ('aws eks describe-cluster --name %CLUSTER_NAME% --query "cluster.identity.oidc.issuer" --output text') do set OIDC_URL=%%i

REM Check if OIDC_URL is empty
if "%OIDC_URL%"=="" (
    echo Failed to get OIDC URL from EKS Cluster.
    exit /b 1
)

echo Deleting OIDC provider...

REM Extract the OIDC provider ID (the last part after the last slash)
for %%A in ("%OIDC_URL%") do set "OIDC_PROVIDER_ID=%%~nxA"

aws iam delete-open-id-connect-provider --open-id-connect-provider-arn arn:aws:iam::%ACCOUNT_ID%:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/%OIDC_PROVIDER_ID%

if %ERRORLEVEL% neq 0 (
    echo Failed to delete OIDC provider.
    exit /b 1
) 

echo Deleting CloudFormation stack...
aws cloudformation delete-stack --stack-name %STACK_NAME% --region %REGION%

echo Waiting for stack deletion to complete...
aws cloudformation wait stack-delete-complete --stack-name %STACK_NAME% --region %REGION%

if %ERRORLEVEL% neq 0 (
    echo Failed to delete CloudFormation stack.
    exit /b 1
) else (
    echo CloudFormation stack deleted successfully!
)

echo Restoring kubectl context to minikube...
kubectl config use-context minikube
if %ERRORLEVEL% neq 0 (
    echo WARNING: Failed to switch kubectl context back to minikube. Please restore manually.
)

echo %time%
