@echo off
echo %time%
echo Running E2E test

set SUFFIX=%1

if "%SUFFIX%"=="" (
    echo Usage: e2e.bat [suffix]
    echo Example: e2e.bat 1
    exit /b 1
)

set SPECS_DIR=..\..\..\sheep-dog-specs\sheep-dog-features

echo --- Setup Stack ---
call aws-setup-stack.bat %SUFFIX%
if %ERRORLEVEL% neq 0 (
    echo Setup stack failed.
    exit /b 1
)

echo --- Setup Cluster ---
call aws-setup-cluster.bat %SUFFIX% prod
if %ERRORLEVEL% neq 0 (
    echo Setup cluster failed.
    exit /b 1
)

echo --- Forward Engineer ---
pushd %SPECS_DIR%
call mvn clean
call mvn org.farhan:sheep-dog-svc-maven-plugin:asciidoctor-to-uml -Dtags="asciidoc-api" -Dhost="%SERVICE_URL%"
call mvn org.farhan:sheep-dog-svc-maven-plugin:asciidoctor-to-uml -Dtags="cucumber-gen" -Dhost="%SERVICE_URL%"
call mvn org.farhan:sheep-dog-svc-maven-plugin:asciidoctor-to-uml -Dtags="grammar" -Dhost="%SERVICE_URL%"
call mvn org.farhan:sheep-dog-svc-maven-plugin:asciidoctor-to-uml -Dtags="svc-maven-plugin" -Dhost="%SERVICE_URL%"
call mvn org.farhan:sheep-dog-svc-maven-plugin:asciidoctor-to-uml -Dtags="asciidoc-api-svc" -Dhost="%SERVICE_URL%"
call mvn org.farhan:sheep-dog-svc-maven-plugin:asciidoctor-to-uml -Dtags="cucumber-gen-svc" -Dhost="%SERVICE_URL%"
call mvn org.farhan:sheep-dog-svc-maven-plugin:asciidoctor-to-uml -Dtags="mcp-svc" -Dhost="%SERVICE_URL%"
set FE_RESULT=%ERRORLEVEL%
popd
if %FE_RESULT% neq 0 (
    echo Forward engineer failed.
    exit /b 1
)

echo --- Teardown Cluster ---
call aws-teardown-cluster.bat %SUFFIX%
if %ERRORLEVEL% neq 0 (
    echo Teardown cluster failed.
    exit /b 1
)

echo --- Teardown Stack ---
call aws-teardown-stack.bat %SUFFIX%
if %ERRORLEVEL% neq 0 (
    echo Teardown stack failed.
    exit /b 1
)

echo E2E test completed successfully!
echo %time%
