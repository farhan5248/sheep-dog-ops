@echo off
echo %time%

set HOST=%1
if "%HOST%"=="" (
    echo Usage: smoke-test.bat [host]
    echo Example: smoke-test.bat qa.sheepdog.io
    exit /b 1
)

REM Resolve sheep-dog-features relative to THIS script, not the caller's CWD.
REM %~dp0 is sheep-dog-ops\sheep-dog\scripts\; three levels up is sheep-dog-main.
pushd "%~dp0..\..\..\sheep-dog-specs\sheep-dog-features"
if %ERRORLEVEL% neq 0 (
    echo Failed to locate sheep-dog-specs\sheep-dog-features at "%~dp0..\..\..\sheep-dog-specs\sheep-dog-features"
    exit /b 1
)
call mvn org.farhan:sheep-dog-svc-maven-plugin:asciidoctor-to-uml -Dtags="svc-maven-plugin" -Dhost="%HOST%"
set FE_RESULT=%ERRORLEVEL%
popd
if %FE_RESULT% neq 0 exit /b %FE_RESULT%

echo %time%
