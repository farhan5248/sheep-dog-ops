@echo off
REM Build and push the sheep-dog-dev-db image to the Nexus Docker registry.
REM
REM The umbrella helm chart (sheep-dog-ops/sheep-dog/helm/sheep-dog) pulls
REM this image via images.db.repository / images.db.tag in values.yaml.
REM
REM Prereqs:
REM   - Docker Desktop running
REM   - `docker login nexus-docker.sheepdog.io` already run in this user session
REM   - hosts file has nexus-docker.sheepdog.io
REM   - mkcert root CA trusted on this machine
REM
REM Usage:
REM   build.bat [tag]
REM
REM Default tag is `latest`. Pass a specific version (e.g. `build.bat 1.0.0`)
REM to produce a pinned image, then also push it as `latest`.

setlocal
set IMAGE=nexus-docker.sheepdog.io/sheep-dog-dev-db
set TAG=%1
if "%TAG%"=="" set TAG=latest

echo Building %IMAGE%:%TAG% from %~dp0...
pushd "%~dp0"
docker image build -f mysql.dockerfile -t %IMAGE%:%TAG% .
if errorlevel 1 (
    echo ERROR: docker build failed
    popd
    exit /b 1
)

echo Pushing %IMAGE%:%TAG%...
docker image push %IMAGE%:%TAG%
if errorlevel 1 (
    echo ERROR: docker push failed
    popd
    exit /b 1
)

if not "%TAG%"=="latest" (
    echo Also tagging as latest and pushing...
    docker image tag %IMAGE%:%TAG% %IMAGE%:latest
    docker image push %IMAGE%:latest
    if errorlevel 1 (
        echo ERROR: docker push latest failed
        popd
        exit /b 1
    )
)

popd
echo Done.
endlocal
