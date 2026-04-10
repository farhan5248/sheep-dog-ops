@echo off
setlocal enabledelayedexpansion
echo %time%
echo Uninstalling sheep-dog umbrella helm release from a Kubernetes namespace
echo.
echo This script is Kubernetes-distribution-agnostic. Point kubectl at your
echo target cluster BEFORE running it.

set NAMESPACE=%1

if "%NAMESPACE%"=="" (
    echo Usage: teardown-namespace.bat [namespace]
    echo Example: teardown-namespace.bat qa
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

echo Current kubectl context:
kubectl config current-context

REM On EKS, ingress-nginx and its NLB are owned by the EKS layer
REM (eks/setup-cluster.bat installs them; eks/teardown-cluster.bat removes
REM them). Namespace teardown only removes the sheep-dog helm release, so
REM teardown-namespace + setup-namespace is a valid redeploy loop that keeps
REM the NLB alive. On minikube the same split applies: the cluster scripts
REM own the ingress addon, namespace scripts own the app.
echo Uninstalling sheep-dog umbrella helm release from namespace %NAMESPACE%...
helm uninstall sheep-dog -n %NAMESPACE% --ignore-not-found

echo Namespace teardown completed.
echo %time%
