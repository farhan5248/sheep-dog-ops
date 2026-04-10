@echo off
REM Package and push the sheep-dog umbrella helm chart to the Nexus OCI helm repo.
REM
REM This is a troubleshooting/recovery tool. In the normal release flow the
REM release workflow in sheep-dog-ops does this automatically (see #32).
REM Use this script when the workflow fails partway through and you need to
REM re-publish the chart manually.
REM
REM Prereqs:
REM   - helm installed and on PATH
REM   - `helm registry login nexus-docker.sheepdog.io` already run
REM     interactively in the current Windows user session
REM   - hosts file on the runner has `127.0.0.1 nexus-docker.sheepdog.io`
REM   - mkcert root CA trusted on this machine (see nexus/import-rootCA.bat)
REM   - minikube tunnel running on windows-desktop
REM
REM Usage:
REM   release.bat

setlocal
set CHART_DIR=%~dp0..\helm\sheep-dog
set WORK_DIR=%~dp0..\helm
set REGISTRY=oci://nexus-docker.sheepdog.io/helm-hosted

echo Packaging chart from %CHART_DIR%...
pushd "%WORK_DIR%"
helm package sheep-dog
if errorlevel 1 (
    echo ERROR: helm package failed
    popd
    exit /b 1
)

for /f "tokens=*" %%f in ('dir /b /o-d sheep-dog-*.tgz 2^>nul') do (
    set CHART_TGZ=%%f
    goto :push
)
echo ERROR: no packaged chart found
popd
exit /b 1

:push
echo Pushing %CHART_TGZ% to %REGISTRY%...
helm push "%CHART_TGZ%" %REGISTRY%
if errorlevel 1 (
    echo ERROR: helm push failed
    popd
    exit /b 1
)

echo Cleaning up %CHART_TGZ%...
del "%CHART_TGZ%"
popd

echo Done.
endlocal
