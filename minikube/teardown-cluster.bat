@echo off
echo %time%
echo Tearing down minikube cluster

echo Checking if minikube is installed...
minikube version >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo minikube is not installed. Please install it first.
    exit /b 1
)

echo Deleting minikube cluster...
minikube delete

echo Minikube teardown completed.
echo %time%
