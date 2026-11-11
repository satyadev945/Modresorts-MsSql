@echo off & setlocal enabledelayedexpansion
REM Build and push the ModResorts image. Run from the repository root.

set "PROJECT_NAME=modresorts"
set "TMP_OUT=%TEMP%\modresorts-sanitize.txt"
powershell -NoProfile -Command "$n=$env:PROJECT_NAME.ToLower() -replace '[^a-z0-9]+','-'; ($n -replace '^-+|-+$','')" > "!TMP_OUT!"
set /p IMAGE_NAME=<"!TMP_OUT!"
if "!IMAGE_NAME!"=="" set "IMAGE_NAME=modresorts"

echo === ModResorts image build and push ===
echo Select registry:
echo   1. Google Artifact Registry
echo   2. Docker Hub
set /p REGISTRY_CHOICE="Choice [1/2]: "

set /p IMAGE_TAG="Image tag [latest]: "
if "!IMAGE_TAG!"=="" set "IMAGE_TAG=latest"
set "TAG_IN=!IMAGE_TAG!"
set "IMAGE_TAG="
powershell -NoProfile -Command "$t=$env:TAG_IN.ToLower() -replace '[^a-z0-9._]+','-'; ($t -replace '^-+|-+$','')" > "!TMP_OUT!"
set /p IMAGE_TAG=<"!TMP_OUT!"
del "!TMP_OUT!" >nul 2>&1
if "!IMAGE_TAG!"=="" set "IMAGE_TAG=latest"

if "!REGISTRY_CHOICE!"=="1" goto ARTIFACT
if "!REGISTRY_CHOICE!"=="2" goto DOCKERHUB
echo ERROR: invalid registry choice
exit /b 1

:ARTIFACT
set /p GCP_PROJECT="GCP project ID: "
set /p GCP_REGION="Artifact Registry region (e.g. us-central1): "
set /p AR_REPO="Artifact Registry repository name: "
if "!GCP_PROJECT!"=="" (echo ERROR: project is required & exit /b 1)
if "!GCP_REGION!"=="" (echo ERROR: region is required & exit /b 1)
if "!AR_REPO!"=="" (echo ERROR: repository is required & exit /b 1)
set "FULL_IMAGE_NAME=!GCP_REGION!-docker.pkg.dev/!GCP_PROJECT!/!AR_REPO!/!IMAGE_NAME!:!IMAGE_TAG!"
echo Authenticating with Google Cloud...
call gcloud config set project !GCP_PROJECT!
if !ERRORLEVEL! neq 0 (echo gcloud config failed & exit /b 1)
call gcloud auth configure-docker !GCP_REGION!-docker.pkg.dev --quiet
if !ERRORLEVEL! neq 0 (echo Artifact Registry login failed & exit /b 1)
goto BUILD

:DOCKERHUB
set /p DOCKER_USERNAME="Docker Hub username: "
set /p DOCKER_PASSWORD="Docker Hub password or access token: "
if "!DOCKER_USERNAME!"=="" (echo ERROR: username is required & exit /b 1)
if "!DOCKER_PASSWORD!"=="" (echo ERROR: password is required & exit /b 1)
set "FULL_IMAGE_NAME=!DOCKER_USERNAME!/!IMAGE_NAME!:!IMAGE_TAG!"
echo Logging in to Docker Hub...
echo !DOCKER_PASSWORD! | docker login --username !DOCKER_USERNAME! --password-stdin
if !ERRORLEVEL! neq 0 (echo Docker Hub login failed & exit /b 1)
goto BUILD

:BUILD
echo Building image: !FULL_IMAGE_NAME!
docker build -f Dockerfile -t "!FULL_IMAGE_NAME!" .
if !ERRORLEVEL! neq 0 (echo Docker build failed & exit /b 1)

echo Pushing image: !FULL_IMAGE_NAME!
docker push "!FULL_IMAGE_NAME!"
if !ERRORLEVEL! neq 0 (echo Docker push failed & exit /b 1)

echo Done. Image pushed: !FULL_IMAGE_NAME!
echo Use this URI with scripts\deploy-image.bat
endlocal
