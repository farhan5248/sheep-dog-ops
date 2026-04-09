@echo off
REM Configure Nexus for hosting the sheep-dog helm chart as an OCI artifact.
REM
REM Prereqs:
REM   - Nexus reachable at http://nexus.sheepdog.io (hosts file + minikube tunnel)
REM   - Nexus admin password available in env var NEXUS_ADMIN_PW
REM   - A deployment password available in env var NEXUS_DEPLOY_PW
REM
REM What this does (idempotent-ish — Nexus REST returns 4xx if a resource
REM already exists, which we tolerate):
REM   1. Enable the Docker Bearer Token realm (required for `helm registry login`)
REM   2. Create a `helm-hosted` docker-format hosted repo with HTTP connector on 8082
REM   3. Create a `nx-helm-deployer` role with read+edit on the helm-hosted repo
REM   4. Create a `helm-deployer` user with that role
REM
REM Usage:
REM   set NEXUS_ADMIN_PW=...
REM   set NEXUS_DEPLOY_PW=...
REM   configure.bat

setlocal
set NEXUS_URL=http://nexus.sheepdog.io
set ADMIN=admin

if "%NEXUS_ADMIN_PW%"=="" (
    echo ERROR: set NEXUS_ADMIN_PW before running
    exit /b 1
)
if "%NEXUS_DEPLOY_PW%"=="" (
    echo ERROR: set NEXUS_DEPLOY_PW before running
    exit /b 1
)

echo === 1. Enable Docker Bearer Token realm ===
curl -s -u %ADMIN%:%NEXUS_ADMIN_PW% -X PUT "%NEXUS_URL%/service/rest/v1/security/realms/active" ^
    -H "Content-Type: application/json" ^
    -d "[\"NexusAuthenticatingRealm\",\"NexusAuthorizingRealm\",\"DockerToken\"]"
echo.

echo === 2. Create helm-hosted docker repo ===
curl -s -u %ADMIN%:%NEXUS_ADMIN_PW% -X POST "%NEXUS_URL%/service/rest/v1/repositories/docker/hosted" ^
    -H "Content-Type: application/json" ^
    -d "{\"name\":\"helm-hosted\",\"online\":true,\"storage\":{\"blobStoreName\":\"default\",\"strictContentTypeValidation\":true,\"writePolicy\":\"allow\"},\"docker\":{\"v1Enabled\":false,\"forceBasicAuth\":false,\"httpPort\":8082}}"
echo.

echo === 3. Create nx-helm-deployer role ===
curl -s -u %ADMIN%:%NEXUS_ADMIN_PW% -X POST "%NEXUS_URL%/service/rest/v1/security/roles" ^
    -H "Content-Type: application/json" ^
    -d "{\"id\":\"nx-helm-deployer\",\"name\":\"nx-helm-deployer\",\"description\":\"Push/pull OCI helm charts to helm-hosted\",\"privileges\":[\"nx-repository-view-docker-helm-hosted-*\"],\"roles\":[]}"
echo.

echo === 4. Create helm-deployer user ===
curl -s -u %ADMIN%:%NEXUS_ADMIN_PW% -X POST "%NEXUS_URL%/service/rest/v1/security/users" ^
    -H "Content-Type: application/json" ^
    -d "{\"userId\":\"helm-deployer\",\"firstName\":\"Helm\",\"lastName\":\"Deployer\",\"emailAddress\":\"helm-deployer@sheepdog.local\",\"password\":\"%NEXUS_DEPLOY_PW%\",\"status\":\"active\",\"roles\":[\"nx-helm-deployer\"]}"
echo.

echo Done.
endlocal
