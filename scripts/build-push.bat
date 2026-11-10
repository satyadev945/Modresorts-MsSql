@echo off
setlocal enabledelayedexpansion

REM Run from the repository root: scripts\build-push.bat
set "PROJECT_NAME=modresorts"
set "IMAGE_NAME=modresorts"

if not exist Dockerfile (
  echo ERROR: Dockerfile not found. Run this script from the repository root.
  exit /b 1
)

set /p RAW_TAG="Enter image tag [latest]: "
if "!RAW_TAG!"=="" set "RAW_TAG=latest"
powershell -NoProfile -Command "$t=$env:RAW_TAG.ToLower() -replace '[^a-z0-9]+','-'; $t=$t.Trim('-'); if (-not $t) { $t='latest' }; Write-Output $t" > "%TEMP%\modres_tag.txt"
set /p IMAGE_TAG=<"%TEMP%\modres_tag.txt"
del "%TEMP%\modres_tag.txt" >nul 2>&1
if "!IMAGE_TAG!"=="" set "IMAGE_TAG=latest"

echo Select registry:
echo   1. AWS ECR
echo   2. Docker Hub
set /p REGISTRY_CHOICE="Choice [1/2]: "

if "!REGISTRY_CHOICE!"=="1" goto ecr
if "!REGISTRY_CHOICE!"=="2" goto dockerhub
echo ERROR: invalid choice
exit /b 1

:ecr
set /p AWS_REGION="AWS region (e.g. us-east-1): "
set /p AWS_ACCOUNT_ID="AWS account ID: "
if "!AWS_REGION!"=="" (
  echo ERROR: AWS region is required
  exit /b 1
)
if "!AWS_ACCOUNT_ID!"=="" (
  echo ERROR: AWS account ID is required
  exit /b 1
)
set "ECR_REPO=!IMAGE_NAME!"
set "REGISTRY_URL=!AWS_ACCOUNT_ID!.dkr.ecr.!AWS_REGION!.amazonaws.com"
set "FULL_IMAGE_NAME=!REGISTRY_URL!/!ECR_REPO!:!IMAGE_TAG!"

echo Logging in to Amazon ECR...
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
set /p DOCKER_USERNAME="Docker Hub username: "
set /p DOCKER_PASSWORD="Docker Hub password or access token: "
if "!DOCKER_USERNAME!"=="" (
  echo ERROR: username is required
  exit /b 1
)
set "FULL_IMAGE_NAME=!DOCKER_USERNAME!/!IMAGE_NAME!:!IMAGE_TAG!"

echo Logging in to Docker Hub...
echo !DOCKER_PASSWORD!| docker login --username !DOCKER_USERNAME! --password-stdin
if !ERRORLEVEL! neq 0 (
  echo Docker Hub login failed
  exit /b 1
)
goto build

:build
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
endlocal
