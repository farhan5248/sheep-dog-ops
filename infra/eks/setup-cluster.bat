@echo off
setlocal enabledelayedexpansion
echo %time%
echo Creating AWS EKS cluster (CloudFormation + OIDC + EBS CSI + ingress-nginx)

set NAMESPACE=%1
set BASE_STACK_NAME=sheep-dog-aws
set REGION=us-east-1

if "%NAMESPACE%"=="" (
    echo Usage: setup-cluster.bat [namespace]
    echo Example: setup-cluster.bat prod
    exit /b 1
) else (
    set STACK_NAME=%BASE_STACK_NAME%-%NAMESPACE%
)

REM ACCOUNT_ID must be set as a system environment variable (see
REM tools.overview.md env-vars row). Mechanical parity with eks/setup-cluster.sh
REM which uses the same env var — ensures .bat and .sh consume credentials
REM the same way, so drift between the two is easy to spot.
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

echo Checking if you are logged in to AWS...
aws sts get-caller-identity
if %ERRORLEVEL% neq 0 (
    echo You are not logged in to AWS. Please run 'aws configure' first.
    exit /b 1
)

echo Deploying CloudFormation stack for EKS...
aws cloudformation deploy ^
    --template-file "%~dp0eks.yml" ^
    --stack-name %STACK_NAME% ^
    --capabilities CAPABILITY_IAM ^
    --region %REGION%

if %ERRORLEVEL% neq 0 (
    echo Failed to deploy CloudFormation stack.
    exit /b 1
)

echo Getting EKS cluster name...
for /f "tokens=*" %%i in ('aws cloudformation describe-stacks --stack-name %STACK_NAME% --query "Stacks[0].Outputs[?OutputKey=='ClusterName'].OutputValue" --output text --region %REGION%') do set CLUSTER_NAME=%%i

if "%CLUSTER_NAME%"=="" (
    echo Failed to get EKS cluster name from CloudFormation stack.
    echo Make sure the stack %STACK_NAME% exists
    exit /b 1
)

echo Getting OIDC URL from EKS cluster...
for /f "delims=" %%i in ('aws eks describe-cluster --name %CLUSTER_NAME% --query "cluster.identity.oidc.issuer" --output text') do set OIDC_URL=%%i

if "%OIDC_URL%"=="" (
    echo Failed to get OIDC URL from EKS Cluster.
    exit /b 1
)

REM Extract OIDC provider ID (last part after /)
for %%A in ("%OIDC_URL%") do set "OIDC_PROVIDER_ID=%%~nxA"

echo Creating OIDC provider in IAM...
REM Idempotent: reruns against an existing cluster shouldn't fail here. Matches
REM eks/setup-cluster.sh behavior.
aws iam create-open-id-connect-provider --url %OIDC_URL% --client-id-list sts.amazonaws.com --thumbprint-list 9e99a48a9960b14926bb7f3b02e22da2b0ab7280 || echo OIDC provider may already exist, continuing...

echo Updating trust policy file with OIDC provider ID and account ID...
if not exist "%~dp0target" mkdir "%~dp0target"
powershell -Command "(Get-Content '%~dp0oidc-policy.json') -replace 'OIDC_PROVIDER_ID', '%OIDC_PROVIDER_ID%' | Set-Content '%~dp0target\oidc-policy.json'"
powershell -Command "(Get-Content '%~dp0target\oidc-policy.json') -replace 'ACCOUNT_ID', '%ACCOUNT_ID%' | Set-Content '%~dp0target\oidc-policy.json'"

echo Creating IAM role for EBS CSI driver...
aws iam create-role --role-name EBSCSIDriverRole --assume-role-policy-document "file://%~dp0target\oidc-policy.json" || echo Role may already exist, continuing...

echo Attaching AmazonEBSCSIDriverPolicy to the role...
aws iam attach-role-policy --role-name EBSCSIDriverRole --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy || echo Policy may already be attached, continuing...

echo Creating EBS CSI driver add-on in EKS...
aws eks create-addon --cluster-name %CLUSTER_NAME% --addon-name aws-ebs-csi-driver --service-account-role-arn arn:aws:iam::%ACCOUNT_ID%:role/EBSCSIDriverRole --addon-version v1.57.1-eksbuild.1 --resolve-conflicts OVERWRITE || echo Addon may already exist, continuing...

REM Wait for add-on to become active (up to 60 seconds)
echo Waiting for EBS CSI driver add-on to be created (up to 60 seconds)...
set timeout=60
set start=%time%
set addonCreated=0

for /l %%i in (1,1,12) do (
    for /f "delims=" %%s in ('aws eks describe-addon --cluster-name %CLUSTER_NAME% --addon-name aws-ebs-csi-driver --query "addon.status" --output text') do set STATUS=%%s
    echo Current status: !STATUS!
    if /i "!STATUS!"=="ACTIVE" (
        echo EBS CSI driver add-on is now active.
        set addonCreated=1
        goto :done
    )
    echo Waiting for EBS CSI driver add-on to become active... (Status: !STATUS!)
    timeout /t 5 >nul
)

:done
if "!addonCreated!"=="0" (
    echo Warning: Timed out waiting for EBS CSI driver add-on to become active.
    echo The add-on may still be in the process of being created. Check its status manually.
)

echo Configuring kubectl to connect to the EKS cluster...
aws eks update-kubeconfig --name %CLUSTER_NAME% --region %REGION%

echo Installing nginx-ingress-controller...
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.2/deploy/static/provider/aws/deploy.yaml
if %ERRORLEVEL% neq 0 (
    echo Failed to install nginx-ingress-controller.
    exit /b 1
)

echo Waiting for nginx-ingress-controller to be ready...
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=300s

echo Deployment completed successfully!
echo.
echo kubectl context is now pointing at the EKS cluster. Follow-up scripts
echo ^(e.g. sheep-dog/scripts/setup-namespace.bat^) will deploy against this
echo context. Use `kubectl config use-context ^<name^>` to switch back when
echo you are done.

echo %time%
