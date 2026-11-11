@echo off
setlocal enabledelayedexpansion
REM Build and push the ModResorts image. Run from the repository root: scripts\build-push.bat

set "PROJECT_NAME=modresorts"
set "IMAGE_NAME=modresorts"

echo === ModResorts image build and push ===
echo Select registry:
echo   1. Google Artifact Registry
echo   2. Docker Hub
set /p REGISTRY_CHOICE="Enter choice [1-2]: "

set /p IMAGE_TAG="Enter image tag [latest]: "
if "!IMAGE_TAG!"=="" set "IMAGE_TAG=latest"
set "RAW_TAG=!IMAGE_TAG!"
set "IMAGE_TAG="
for /f "delims=" %%T in ('powershell -NoProfile -Command "$t=$env:RAW_TAG.ToLower(); $t=[regex]::Replace($t,'[^a-z0-9._]+','-').Trim('-'); Write-Output $t"') do set "IMAGE_TAG=%%T"
if "!IMAGE_TAG!"=="" set "IMAGE_TAG=latest"

if "!REGISTRY_CHOICE!"=="1" goto ARTIFACT
if "!REGISTRY_CHOICE!"=="2" goto DOCKERHUB
echo ERROR: invalid choice
exit /b 1

:ARTIFACT
set /p GCP_PROJECT="Enter GCP project ID: "
set /p GCP_REGION="Enter Artifact Registry region (e.g. us-central1): "
set /p AR_REPO="Enter Artifact Registry repository name: "
if "!GCP_PROJECT!"=="" (echo ERROR: project is required & exit /b 1)
if "!GCP_REGION!"=="" (echo ERROR: region is required & exit /b 1)
if "!AR_REPO!"=="" (echo ERROR: repository is required & exit /b 1)
set "FULL_IMAGE_NAME=!GCP_REGION!-docker.pkg.dev/!GCP_PROJECT!/!AR_REPO!/!IMAGE_NAME!:!IMAGE_TAG!"
echo Configuring gcloud...
call gcloud config set project !GCP_PROJECT!
if !ERRORLEVEL! neq 0 (echo gcloud project configuration failed & exit /b 1)
call gcloud auth configure-docker !GCP_REGION!-docker.pkg.dev --quiet
if !ERRORLEVEL! neq 0 (echo Artifact Registry login failed & exit /b 1)
goto BUILD

:DOCKERHUB
set /p DOCKER_USERNAME="Enter Docker Hub username: "
set /p DOCKER_PASSWORD="Enter Docker Hub password or token: "
if "!DOCKER_USERNAME!"=="" (echo ERROR: username is required & exit /b 1)
if "!DOCKER_PASSWORD!"=="" (echo ERROR: password is required & exit /b 1)
set "FULL_IMAGE_NAME=!DOCKER_USERNAME!/!IMAGE_NAME!:!IMAGE_TAG!"
echo !DOCKER_PASSWORD!| docker login --username !DOCKER_USERNAME! --password-stdin
if !ERRORLEVEL! neq 0 (echo Docker Hub login failed & exit /b 1)
goto BUILD

:BUILD
echo Building image !FULL_IMAGE_NAME!
docker build -f Dockerfile -t !FULL_IMAGE_NAME! .
if !ERRORLEVEL! neq 0 (echo Docker build failed & exit /b 1)

echo Pushing image !FULL_IMAGE_NAME!
docker push !FULL_IMAGE_NAME!
if !ERRORLEVEL! neq 0 (echo Docker push failed & exit /b 1)

echo SUCCESS: pushed !FULL_IMAGE_NAME!
echo Use this URI with scripts\deploy-image.bat
endlocal
