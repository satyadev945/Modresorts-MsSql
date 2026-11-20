@echo off
setlocal enabledelayedexpansion

REM Build and push the ModResorts image. Run from the repository root.
set "PROJECT_NAME=modresorts"

echo === ModResorts: build and push Docker image ===
echo Select registry type:
echo   1. AWS ECR
echo   2. Docker Hub
set /p REGISTRY_CHOICE="Enter choice (1-2): "

set "SAN_TMP=%TEMP%\modresorts-san-%RANDOM%.txt"
powershell -NoProfile -Command "('%PROJECT_NAME%').ToLower() -replace '[^a-z0-9]+','-' -replace '^-+|-+$','' | Set-Content -NoNewline -Path '!SAN_TMP!'"
set /p IMAGE_NAME=<"!SAN_TMP!"

set "IMAGE_TAG="
set /p IMAGE_TAG="Enter image tag (default latest): "
if "!IMAGE_TAG!"=="" set "IMAGE_TAG=latest"
set "RAW_TAG=!IMAGE_TAG!"
powershell -NoProfile -Command "('!RAW_TAG!').ToLower() -replace '[^a-z0-9._]+','-' -replace '^-+|-+$','' | Set-Content -NoNewline -Path '!SAN_TMP!'"
set "IMAGE_TAG="
set /p IMAGE_TAG=<"!SAN_TMP!"
del "!SAN_TMP!" >nul 2>&1
if "!IMAGE_TAG!"=="" set "IMAGE_TAG=latest"

if "!REGISTRY_CHOICE!"=="1" goto ecr
if "!REGISTRY_CHOICE!"=="2" goto dockerhub
echo ERROR: Invalid registry choice.
exit /b 1

:ecr
set /p AWS_REGION="Enter AWS region (e.g. us-east-1): "
set /p AWS_ACCOUNT_ID="Enter AWS account ID: "
set "ECR_REPO=!IMAGE_NAME!"
set /p ECR_REPO="Enter ECR repository name (default !IMAGE_NAME!): "
if "!AWS_REGION!"=="" (
  echo ERROR: AWS region is required.
  exit /b 1
)
if "!AWS_ACCOUNT_ID!"=="" (
  echo ERROR: AWS account ID is required.
  exit /b 1
)
set "REGISTRY_URL=!AWS_ACCOUNT_ID!.dkr.ecr.!AWS_REGION!.amazonaws.com"
set "FULL_IMAGE_NAME=!REGISTRY_URL!/!ECR_REPO!:!IMAGE_TAG!"

echo Logging in to ECR...
aws ecr get-login-password --region !AWS_REGION! | docker login --username AWS --password-stdin !REGISTRY_URL!
if !ERRORLEVEL! neq 0 (
  echo ECR login failed
  exit /b 1
)

echo Ensuring ECR repository exists...
aws ecr describe-repositories --repository-names !ECR_REPO! --region !AWS_REGION! >nul 2>&1
if !ERRORLEVEL! neq 0 (
  echo Creating ECR repository...
  aws ecr create-repository --repository-name !ECR_REPO! --region !AWS_REGION!
  if !ERRORLEVEL! neq 0 (
    echo Failed to create ECR repository
    exit /b 1
  )
)
goto build

:dockerhub
set /p DOCKER_USERNAME="Enter Docker Hub username: "
set /p DOCKER_PASSWORD="Enter Docker Hub password or token: "
if "!DOCKER_USERNAME!"=="" (
  echo ERROR: Docker Hub username is required.
  exit /b 1
)
set "FULL_IMAGE_NAME=!DOCKER_USERNAME!/!IMAGE_NAME!:!IMAGE_TAG!"
echo Logging in to Docker Hub...
echo !DOCKER_PASSWORD! | docker login --username !DOCKER_USERNAME! --password-stdin
if !ERRORLEVEL! neq 0 (
  echo Docker Hub login failed
  exit /b 1
)
goto build

:build
echo Building image: !FULL_IMAGE_NAME!
docker build -f Dockerfile -t !FULL_IMAGE_NAME! .
if !ERRORLEVEL! neq 0 (
  echo Docker build failed
  exit /b 1
)

echo Pushing image: !FULL_IMAGE_NAME!
docker push !FULL_IMAGE_NAME!
if !ERRORLEVEL! neq 0 (
  echo Docker push failed
  exit /b 1
)

echo === Done. Image pushed: !FULL_IMAGE_NAME! ===
echo Use this URI with scripts\deploy-image.bat
endlocal
