@echo off
echo %time%

set HOST=%1
if "%HOST%"=="" (
    echo Usage: forward-engineer.bat [host]
    echo Example: forward-engineer.bat qa.sheepdog.io
    exit /b 1
)

pushd ..\..\..\sheep-dog-specs\sheep-dog-features
call mvn org.farhan:sheep-dog-svc-maven-plugin:asciidoctor-to-uml -Dtags="svc-maven-plugin" -Dhost="%HOST%"
set FE_RESULT=%ERRORLEVEL%
popd
if %FE_RESULT% neq 0 exit /b %FE_RESULT%

echo %time%
