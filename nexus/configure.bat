@echo off
REM Configure Nexus for hosting helm charts, Maven artifacts, and Docker images.
REM
REM Prereqs:
REM   - Nexus reachable at https://nexus.sheepdog.io (hosts file + minikube tunnel
REM     + mkcert root CA trusted — see sheep-dog-ops/nexus/import-rootCA.bat)
REM   - Nexus admin password available in env var NEXUS_ADMIN_PW
REM   - A deployment password available in env var NEXUS_DEPLOY_PW
REM
REM What this does (idempotent-ish — Nexus REST returns 4xx if a resource
REM already exists, which we tolerate):
REM   1. Enable the Docker Bearer Token realm (required for `helm registry login`)
REM   2. Create a `helm-hosted` docker-format hosted repo with HTTP connector on 8082
REM      (serves both OCI helm charts and Docker container images)
REM   3. Create a `nx-helm-deployer` role with permissions on helm-hosted repo
REM      and Maven repos (maven-releases, maven-snapshots, maven-public)
REM   4. Create a `helm-deployer` user with that role
REM
REM Maven repos (maven-releases, maven-snapshots, maven-central, maven-public)
REM ship as Nexus defaults and don't need creation here.
REM
REM Usage:
REM   set NEXUS_ADMIN_PW=...
REM   set NEXUS_DEPLOY_PW=...
REM   configure.bat
REM
REM NOTE: avoid cmd metacharacters (^ & < > |) in the passwords — cmd's parser
REM eats them during %VAR% expansion and the script will send a mangled value
REM to Nexus.

setlocal
set NEXUS_URL=https://nexus.sheepdog.io
set ADMIN=admin

if "%NEXUS_ADMIN_PW%"=="" (
    echo ERROR: set NEXUS_ADMIN_PW before running
    exit /b 1
)
if "%NEXUS_DEPLOY_PW%"=="" (
    echo ERROR: set NEXUS_DEPLOY_PW before running
    exit /b 1
)

REM -w prints HTTP status on its own line so we can spot failures.
set CURL_FMT=\n--- HTTP %%{http_code} ---\n

REM --ssl-no-revoke is required because Windows curl uses schannel, which
REM tries to fetch an online CRL/OCSP endpoint that mkcert dev certs don't
REM include, resulting in "0x80092012 The revocation function was unable
REM to check revocation for the certificate". The cert itself is trusted
REM (mkcert root CA is in the machine Root store); this flag just skips
REM the revocation check. Browsers, Java, helm, and docker don't hit this.
set CURL_TLS=--ssl-no-revoke

echo === 1. Enable Docker Bearer Token realm ===
curl %CURL_TLS% -u %ADMIN%:%NEXUS_ADMIN_PW% -X PUT "%NEXUS_URL%/service/rest/v1/security/realms/active" ^
    -H "Content-Type: application/json" ^
    -w "%CURL_FMT%" ^
    -d "[\"NexusAuthenticatingRealm\",\"DockerToken\"]"
echo.

echo === 2. Create helm-hosted docker repo ===
curl %CURL_TLS% -u %ADMIN%:%NEXUS_ADMIN_PW% -X POST "%NEXUS_URL%/service/rest/v1/repositories/docker/hosted" ^
    -H "Content-Type: application/json" ^
    -w "%CURL_FMT%" ^
    -d "{\"name\":\"helm-hosted\",\"online\":true,\"storage\":{\"blobStoreName\":\"default\",\"strictContentTypeValidation\":true,\"writePolicy\":\"allow\"},\"docker\":{\"v1Enabled\":false,\"forceBasicAuth\":false,\"httpPort\":8082}}"
echo.

echo === 3. Create nx-helm-deployer role (helm-hosted + Maven repos) ===
curl %CURL_TLS% -u %ADMIN%:%NEXUS_ADMIN_PW% -X POST "%NEXUS_URL%/service/rest/v1/security/roles" ^
    -H "Content-Type: application/json" ^
    -w "%CURL_FMT%" ^
    -d "{\"id\":\"nx-helm-deployer\",\"name\":\"nx-helm-deployer\",\"description\":\"Deploy to Maven repos and Docker/OCI registry (helm-hosted)\",\"privileges\":[\"nx-repository-view-docker-helm-hosted-*\",\"nx-repository-view-maven2-maven-releases-*\",\"nx-repository-view-maven2-maven-snapshots-*\",\"nx-repository-view-maven2-maven-public-*\"],\"roles\":[]}"
echo.

echo === 4. Create helm-deployer user ===
curl %CURL_TLS% -u %ADMIN%:%NEXUS_ADMIN_PW% -X POST "%NEXUS_URL%/service/rest/v1/security/users" ^
    -H "Content-Type: application/json" ^
    -w "%CURL_FMT%" ^
    -d "{\"userId\":\"helm-deployer\",\"firstName\":\"Helm\",\"lastName\":\"Deployer\",\"emailAddress\":\"helm-deployer@sheepdog.local\",\"password\":\"%NEXUS_DEPLOY_PW%\",\"status\":\"active\",\"roles\":[\"nx-helm-deployer\"]}"
echo.

echo Done.
endlocal
