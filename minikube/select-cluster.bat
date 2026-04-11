@echo off
setlocal
echo %time%
echo Selecting minikube cluster for downstream sheep-dog scripts

REM NAMESPACE arg is accepted for signature parity with eks/select-cluster.bat
REM but minikube has a single fixed context regardless of the target namespace.
set NAMESPACE=%1

if "%NAMESPACE%"=="" (
    echo Usage: select-cluster.bat [namespace]
    echo Example: select-cluster.bat dev
    exit /b 1
)

echo Checking if kubectl is installed...
kubectl version --client
if %ERRORLEVEL% neq 0 (
    echo kubectl is not installed. Please install it first.
    exit /b 1
)

echo Switching kubectl context to minikube...
kubectl config use-context minikube
if %ERRORLEVEL% neq 0 (
    echo Failed to switch kubectl context to minikube.
    echo Make sure minikube is running ^(minikube/setup-cluster.bat or
    echo minikube/setup-cluster-local.bat^) before running this script.
    exit /b 1
)

REM `kubectl config use-context` only validates that the context exists in
REM kubeconfig, not that the cluster is actually reachable. A stopped minikube
REM VM leaves the context in place, so downstream scripts (helm install, etc.)
REM would hang deep inside the first kubectl/helm call. Probe minikube status
REM here so callers see a clear error up front.
echo Checking minikube status...
minikube status >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo Minikube is not running. Start it with minikube/setup-cluster.bat or
    echo minikube/setup-cluster-local.bat before running this script.
    exit /b 1
)

echo Current kubectl context:
kubectl config current-context
echo K8S_CLUSTER=minikube
echo %time%
endlocal & set K8S_CLUSTER=minikube
