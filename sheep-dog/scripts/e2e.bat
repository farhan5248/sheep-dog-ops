@echo off
setlocal
echo %time%
echo Running sheep-dog E2E test against EKS

set SUFFIX=%1
set NAMESPACE=prod
set SCRIPTS_DIR=%~dp0
set EKS_DIR=%~dp0..\..\eks\

if "%SUFFIX%"=="" (
    echo Usage: e2e.bat [suffix]
    echo Example: e2e.bat 1
    exit /b 1
)

echo --- Setup cluster (EKS) ---
call "%EKS_DIR%setup-cluster.bat" %SUFFIX%
if %ERRORLEVEL% neq 0 (
    echo Setup cluster failed.
    exit /b 1
)

echo --- Setup namespace ---
call "%SCRIPTS_DIR%setup-namespace.bat" %NAMESPACE%
if %ERRORLEVEL% neq 0 (
    echo Setup namespace failed.
    exit /b 1
)

echo --- Smoke test ---
call "%SCRIPTS_DIR%smoke-test.bat" %SERVICE_URL%
if %ERRORLEVEL% neq 0 (
    echo Smoke test failed.
    exit /b 1
)

echo --- Teardown namespace ---
call "%SCRIPTS_DIR%teardown-namespace.bat" %NAMESPACE%
if %ERRORLEVEL% neq 0 (
    echo Teardown namespace failed.
    exit /b 1
)

echo --- Teardown cluster (EKS) ---
call "%EKS_DIR%teardown-cluster.bat" %SUFFIX%
if %ERRORLEVEL% neq 0 (
    echo Teardown cluster failed.
    exit /b 1
)

echo E2E test completed successfully!
echo %time%
endlocal
