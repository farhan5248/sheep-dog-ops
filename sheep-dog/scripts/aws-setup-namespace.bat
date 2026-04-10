@echo off
setlocal enabledelayedexpansion
echo %time%
echo Deploying sheep-dog umbrella helm chart into an EKS namespace

set SUFFIX=%1
set NAMESPACE=%2
set BASE_STACK_NAME=sheep-dog-aws
set REGION=us-east-1

if "%SUFFIX%"=="" (
    echo Usage: aws-setup-namespace.bat [suffix] [namespace]
    echo Example: aws-setup-namespace.bat 1 prod
    exit /b 1
)
set STACK_NAME=%BASE_STACK_NAME%-%SUFFIX%

if "%NAMESPACE%"=="" set NAMESPACE=prod

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

echo Getting EKS cluster name from CloudFormation stack...
for /f "tokens=*" %%i in ('aws cloudformation describe-stacks --stack-name %STACK_NAME% --query "Stacks[0].Outputs[?OutputKey=='ClusterName'].OutputValue" --output text --region %REGION%') do set CLUSTER_NAME=%%i

if "%CLUSTER_NAME%"=="" (
    echo Failed to get EKS cluster name from CloudFormation stack.
    echo Make sure the stack %STACK_NAME% exists and has been deployed using aws-setup-eks.bat.
    exit /b 1
)

echo Configuring kubectl to connect to the EKS cluster %CLUSTER_NAME%...
aws eks update-kubeconfig --name %CLUSTER_NAME% --region %REGION%

if %ERRORLEVEL% neq 0 (
    echo Failed to configure kubectl.
    exit /b 1
)

echo Pulling sheep-dog umbrella helm chart from Nexus OCI (#82)...
REM Chart version pinned to 0.1.0 until #32. Chart ships its own env values
REM files under helm-values/, so we pull-untar to target/ and reference
REM the extracted values file by namespace.
REM Prereqs on windows-minipc (where this is run manually):
REM   - hosts file has nexus-docker.sheepdog.io
REM   - `helm registry login nexus-docker.sheepdog.io` already done
REM   - mkcert root CA trusted on this machine (see nexus/import-rootCA.bat)
REM   - minikube_start_server.bat running on windows-desktop
REM
REM Resolve to an absolute path — helm install refuses chart paths containing
REM `..` components (SecureJoin rejects upward traversal).
for %%I in ("%~dp0..\target") do set TARGET_DIR=%%~fI
if not exist "%TARGET_DIR%" mkdir "%TARGET_DIR%"
if exist "%TARGET_DIR%\sheep-dog" rmdir /s /q "%TARGET_DIR%\sheep-dog"
helm pull oci://nexus-docker.sheepdog.io/helm-hosted/sheep-dog --version 0.1.0 --untar --untardir "%TARGET_DIR%"
if %ERRORLEVEL% neq 0 (
    echo Failed to pull helm chart.
    exit /b 1
)

echo Deploying sheep-dog umbrella helm chart to namespace %NAMESPACE%...
helm upgrade --install sheep-dog "%TARGET_DIR%\sheep-dog" -n %NAMESPACE% --create-namespace -f "%TARGET_DIR%\sheep-dog\helm-values\values-%NAMESPACE%.yaml" --wait

if %ERRORLEVEL% neq 0 (
    echo Failed to deploy helm chart.
    exit /b 1
)

echo Restarting deployments to pull the latest images...
kubectl rollout restart deployment -n %NAMESPACE% -l app=sheep-dog

echo Waiting for rollouts to complete...
kubectl rollout status deployment -n %NAMESPACE% -l app=sheep-dog

if %ERRORLEVEL% neq 0 (
    echo Deployment rollout failed.
    exit /b 1
)

echo Waiting for Ingress hostname to be assigned (up to 5 minutes)...
set SERVICE_URL=
for /l %%i in (1,1,30) do (
    for /f "delims=" %%h in ('kubectl get ingress sheep-dog-ingress -n %NAMESPACE% -o jsonpath^="{.status.loadBalancer.ingress[0].hostname}"') do set SERVICE_URL=%%h
    if not "!SERVICE_URL!"=="" goto :got_url
    echo Waiting for Ingress... (attempt %%i/30)
    timeout /t 10 >nul
)
:got_url
echo Service URL: %SERVICE_URL%
if "%SERVICE_URL%"=="" (
    echo Failed to get Ingress URL.
    exit /b 1
)

echo Listing all services...
kubectl get services -n %NAMESPACE%

echo EKS cluster update completed successfully!

echo Restoring kubectl context to minikube...
kubectl config use-context minikube
if %ERRORLEVEL% neq 0 (
    echo WARNING: Failed to switch kubectl context back to minikube. Please restore manually.
)

echo %time%
endlocal & set SERVICE_URL=%SERVICE_URL%
