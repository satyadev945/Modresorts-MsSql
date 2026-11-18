@echo off
setlocal enabledelayedexpansion

REM Run from the repository root:  scripts\build-push.bat
set "PROJECT_NAME=modresorts"
set "IMAGE_NAME=modresorts"

echo === ModResorts image build and push ===
echo Select registry:
echo   1. AWS ECR
echo   2. Docker Hub
set /p REGISTRY_CHOICE="Enter choice [1-2]: "

set "IMAGE_TAG="
set /p IMAGE_TAG="Enter image tag (default: latest): "
if "!IMAGE_TAG!"=="" set "IMAGE_TAG=latest"

set "TAGFILE=%TEMP%\modresorts_tag_%RANDOM%.txt"
powershell -NoProfile -Command "$t = '!IMAGE_TAG!'.ToLower(); $t = [regex]::Replace($t, '[\W_]+', '-'); $t = $t.Trim('-'); if ($t -eq '') { $t = 'latest' }; Set-Content -Path '!TAGFILE!' -Value $t -NoNewline"
set /p IMAGE_TAG=<"!TAGFILE!"
del "!TAGFILE!" >nul 2>&1
if "!IMAGE_TAG!"=="" set "IMAGE_TAG=latest"

if "!REGISTRY_CHOICE!"=="1" goto ecr
if "!REGISTRY_CHOICE!"=="2" goto dockerhub
echo ERROR: Invalid registry choice
exit /b 1

:ecr
set "AWS_REGION="
set "AWS_ACCOUNT_ID="
set "ECR_REPO="
set /p AWS_REGION="Enter AWS region (e.g. us-east-1): "
set /p AWS_ACCOUNT_ID="Enter AWS account ID: "
set /p ECR_REPO="Enter ECR repository name (default: !IMAGE_NAME!): "
if "!ECR_REPO!"=="" set "ECR_REPO=!IMAGE_NAME!"
if "!AWS_REGION!"=="" (
  echo ERROR: AWS region is required
  exit /b 1
)
if "!AWS_ACCOUNT_ID!"=="" (
  echo ERROR: AWS account ID is required
  exit /b 1
)
set "REGISTRY_URL=!AWS_ACCOUNT_ID!.dkr.ecr.!AWS_REGION!.amazonaws.com"
set "FULL_IMAGE_NAME=!REGISTRY_URL!/!ECR_REPO!:!IMAGE_TAG!"

echo Logging in to AWS ECR...
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
goto build

:dockerhub
set "DOCKER_USERNAME="
set "DOCKER_PASSWORD="
set /p DOCKER_USERNAME="Enter Docker Hub username: "
set /p DOCKER_PASSWORD="Enter Docker Hub password or access token: "
if "!DOCKER_USERNAME!"=="" (
  echo ERROR: Docker Hub username is required
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
echo Building Docker image !FULL_IMAGE_NAME!
docker build -f Dockerfile -t !FULL_IMAGE_NAME! .
if !ERRORLEVEL! neq 0 (
  echo Docker build failed
  exit /b 1
)

echo Pushing Docker image !FULL_IMAGE_NAME!
docker push !FULL_IMAGE_NAME!
if !ERRORLEVEL! neq 0 (
  echo Docker push failed
  exit /b 1
)

echo === Done ===
echo Image pushed !FULL_IMAGE_NAME!
echo Use this URI with scripts\deploy-image.bat
endlocal
