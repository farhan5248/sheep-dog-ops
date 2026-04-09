@echo off
echo %time%
echo Running E2E test

set SUFFIX=%1

if "%SUFFIX%"=="" (
    echo Usage: e2e.bat [suffix]
    echo Example: e2e.bat 1
    exit /b 1
)

echo --- Setup EKS ---
call aws-setup-eks.bat %SUFFIX%
if %ERRORLEVEL% neq 0 (
    echo Setup eks failed.
    exit /b 1
)

echo --- Setup Namespace ---
call aws-setup-namespace.bat %SUFFIX% prod
if %ERRORLEVEL% neq 0 (
    echo Setup namespace failed.
    exit /b 1
)

echo --- Forward Engineer ---
call aws-forward-engineer.bat %SERVICE_URL%
if %ERRORLEVEL% neq 0 (
    echo Forward engineer failed.
    exit /b 1
)

echo --- Teardown Namespace ---
call aws-teardown-namespace.bat %SUFFIX%
if %ERRORLEVEL% neq 0 (
    echo Teardown namespace failed.
    exit /b 1
)

echo --- Teardown EKS ---
call aws-teardown-eks.bat %SUFFIX%
if %ERRORLEVEL% neq 0 (
    echo Teardown eks failed.
    exit /b 1
)

echo E2E test completed successfully!
echo %time%
