@echo off & setlocal enabledelayedexpansion
rem Build and push the ModResorts image. Run from the repository root:  scripts\build-push.bat

if not exist "Dockerfile" (
  echo ERROR: Dockerfile not found. Run this script from the repository root.
  exit /b 1
)

set "SAN_TMP=%TEMP%\modres_sanitize_%RANDOM%.txt"

set "PROJECT_NAME="
set /p PROJECT_NAME="Project/image name [modresorts]: "
if "!PROJECT_NAME!"=="" set "PROJECT_NAME=modresorts"
call :sanitize "!PROJECT_NAME!" IMAGE_NAME
if "!IMAGE_NAME!"=="" set "IMAGE_NAME=modresorts"

set "RAW_TAG="
set /p RAW_TAG="Image tag [latest]: "
call :sanitize "!RAW_TAG!" IMAGE_TAG
if "!IMAGE_TAG!"=="" set "IMAGE_TAG=latest"

echo.
echo Select registry:
echo   1. Google Artifact Registry
echo   2. Docker Hub
set "REGISTRY_CHOICE=1"
set /p REGISTRY_CHOICE="Choice [1]: "
if "!REGISTRY_CHOICE!"=="" set "REGISTRY_CHOICE=1"

if "!REGISTRY_CHOICE!"=="1" (
  set "GCP_PROJECT="
  set /p GCP_PROJECT="GCP project ID: "
  if "!GCP_PROJECT!"=="" (
    echo ERROR: GCP project ID is required.
    exit /b 1
  )
  set "GCP_REGION=us-central1"
  set /p GCP_REGION="Artifact Registry region [us-central1]: "
  if "!GCP_REGION!"=="" set "GCP_REGION=us-central1"
  set "AR_REPO=modresorts"
  set /p AR_REPO="Artifact Registry repository [modresorts]: "
  if "!AR_REPO!"=="" set "AR_REPO=modresorts"
  set "FULL_IMAGE_NAME=!GCP_REGION!-docker.pkg.dev/!GCP_PROJECT!/!AR_REPO!/!IMAGE_NAME!:!IMAGE_TAG!"
  echo Authenticating with Google Cloud...
  call gcloud config set project !GCP_PROJECT!
  if !ERRORLEVEL! neq 0 (
    echo gcloud configuration failed
    exit /b 1
  )
  call gcloud auth configure-docker !GCP_REGION!-docker.pkg.dev --quiet
  if !ERRORLEVEL! neq 0 (
    echo Artifact Registry login failed
    exit /b 1
  )
) else if "!REGISTRY_CHOICE!"=="2" (
  set "DOCKER_USERNAME="
  set /p DOCKER_USERNAME="Docker Hub username: "
  set "DOCKER_PASSWORD="
  set /p DOCKER_PASSWORD="Docker Hub password/token: "
  if "!DOCKER_USERNAME!"=="" (
    echo ERROR: Docker Hub credentials are required.
    exit /b 1
  )
  call :sanitize "!DOCKER_USERNAME!" DOCKER_USER_LC
  set "FULL_IMAGE_NAME=!DOCKER_USER_LC!/!IMAGE_NAME!:!IMAGE_TAG!"
  echo Logging in to Docker Hub...
  echo !DOCKER_PASSWORD! | docker login --username !DOCKER_USERNAME! --password-stdin
  if !ERRORLEVEL! neq 0 (
    echo Docker Hub login failed
    exit /b 1
  )
) else (
  echo ERROR: Invalid choice.
  exit /b 1
)

echo.
echo Building image: !FULL_IMAGE_NAME!
docker build -f Dockerfile -t "!FULL_IMAGE_NAME!" .
if !ERRORLEVEL! neq 0 (
  echo Docker build failed
  exit /b 1
)

echo Pushing image: !FULL_IMAGE_NAME!
docker push "!FULL_IMAGE_NAME!"
if !ERRORLEVEL! neq 0 (
  echo Docker push failed
  exit /b 1
)

echo.
echo SUCCESS: image pushed to !FULL_IMAGE_NAME!
echo Deploy with scripts\deploy-image.bat using the image URI above.
exit /b 0

:sanitize
rem %1 = input text, %2 = output variable name (lowercase, hyphenated, trimmed)
set "SAN_IN=%~1"
powershell -NoProfile -Command "$s=([string]$env:SAN_IN).ToLower() -replace '[^a-z0-9]+','-'; $s=$s.Trim('-'); [IO.File]::WriteAllText($env:SAN_TMP,$s)"
set "%~2="
set /p %~2=<"%SAN_TMP%"
del "%SAN_TMP%" >nul 2>&1
exit /b 0
