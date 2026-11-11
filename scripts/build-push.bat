@echo off
setlocal enabledelayedexpansion
REM Build and push the ModResorts Docker image. Run from the repository root.

set "PROJECT_NAME=modresorts"
for /f "delims=" %%i in ('powershell -NoProfile -Command "('%PROJECT_NAME%'.ToLower() -replace '[^a-z0-9]+','-').Trim('-')"') do set "IMAGE_NAME=%%i"
if "!IMAGE_NAME!"=="" set "IMAGE_NAME=modresorts"

echo === ModResorts Docker build and push ===
set "IMAGE_TAG="
set /p IMAGE_TAG="Enter image tag [latest]: "
if "!IMAGE_TAG!"=="" set "IMAGE_TAG=latest"
set "RAW_TAG=!IMAGE_TAG!"
set "IMAGE_TAG=latest"
for /f "delims=" %%t in ('powershell -NoProfile -Command "$t=('!RAW_TAG!'.ToLower() -replace '[^a-z0-9._]+','-').Trim('-'); if ($t) { $t } else { 'latest' }"') do set "IMAGE_TAG=%%t"

echo Select registry:
echo   1. AWS ECR
echo   2. Docker Hub
set "REGISTRY_CHOICE="
set /p REGISTRY_CHOICE="Choice [1/2]: "

if "!REGISTRY_CHOICE!"=="1" (
  set /p AWS_REGION="Enter AWS region (e.g. us-east-1): "
  set /p AWS_ACCOUNT_ID="Enter AWS account ID: "
  set "ECR_REPO="
  set /p ECR_REPO="Enter ECR repository name [!IMAGE_NAME!]: "
  if "!ECR_REPO!"=="" set "ECR_REPO=!IMAGE_NAME!"
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
      echo ECR repository creation failed
      exit /b 1
    )
  )
) else if "!REGISTRY_CHOICE!"=="2" (
  set /p DOCKER_USERNAME="Enter Docker Hub username: "
  set /p DOCKER_PASSWORD="Enter Docker Hub password or token: "
  set "DOCKER_REPO="
  set /p DOCKER_REPO="Enter repository name [!IMAGE_NAME!]: "
  if "!DOCKER_REPO!"=="" set "DOCKER_REPO=!IMAGE_NAME!"
  set "FULL_IMAGE_NAME=!DOCKER_USERNAME!/!DOCKER_REPO!:!IMAGE_TAG!"

  echo Logging in to Docker Hub...
  echo !DOCKER_PASSWORD!| docker login --username !DOCKER_USERNAME! --password-stdin
  if !ERRORLEVEL! neq 0 (
    echo Docker Hub login failed
    exit /b 1
  )
) else (
  echo Invalid registry choice
  exit /b 1
)

echo Building image !FULL_IMAGE_NAME! ...
docker build -f Dockerfile -t !FULL_IMAGE_NAME! .
if !ERRORLEVEL! neq 0 (
  echo Docker build failed
  exit /b 1
)

echo Pushing image !FULL_IMAGE_NAME! ...
docker push !FULL_IMAGE_NAME!
if !ERRORLEVEL! neq 0 (
  echo Docker push failed
  exit /b 1
)

echo Done. Image pushed: !FULL_IMAGE_NAME!
echo Use this URI with scripts\deploy-image.bat
endlocal
