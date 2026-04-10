@echo off
REM Imports the mkcert root CA (mkcert-rootCA.pem in this folder) into the
REM Windows machine-wide trust store and, if JAVA_HOME is set, into Java's
REM cacerts keystore. Needed on every client machine that will talk HTTPS
REM to nexus.sheepdog.io / nexus-docker.sheepdog.io.
REM
REM Must run from an elevated (Administrator) command prompt.
REM
REM Usage:
REM   set JAVA_HOME=C:\Program Files\Eclipse Adoptium\jdk-21.0.10.7-hotspot
REM   import-rootCA.bat

setlocal
set CA_FILE=%~dp0mkcert-rootCA.pem

if not exist "%CA_FILE%" (
    echo ERROR: %CA_FILE% not found
    exit /b 1
)

net session >nul 2>&1
if errorlevel 1 (
    echo ERROR: must run as Administrator
    exit /b 1
)

echo === 1. Import into Windows machine Root store ===
certutil -addstore -f Root "%CA_FILE%"
if errorlevel 1 (
    echo ERROR: certutil failed
    exit /b 1
)

if "%JAVA_HOME%"=="" (
    echo.
    echo WARNING: JAVA_HOME not set -- skipping Java cacerts import.
    echo          Set JAVA_HOME and re-run before running Maven deploys to
    echo          nexus.sheepdog.io over HTTPS.
    exit /b 0
)

echo.
echo === 2. Import into Java cacerts at %JAVA_HOME%\lib\security\cacerts ===
REM -noprompt + -trustcacerts; default cacerts password is "changeit".
REM If the alias already exists keytool exits non-zero, which we tolerate.
"%JAVA_HOME%\bin\keytool" -importcert -noprompt -trustcacerts ^
    -alias mkcert-sheepdog ^
    -file "%CA_FILE%" ^
    -keystore "%JAVA_HOME%\lib\security\cacerts" ^
    -storepass changeit

echo.
echo Done.
endlocal
