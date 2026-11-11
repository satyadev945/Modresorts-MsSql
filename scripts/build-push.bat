@echo off
setlocal enabledelayedexpansion

rem Run from the repository root:  scripts\build-push.bat
set "PROJECT_NAME=modresorts"
set "IMAGE_NAME=%PROJECT_NAME%"
set "TMPFILE=%TEMP%\modresorts_tag_%RANDOM%.txt"

echo === ModResorts: build and push Docker image ===
echo Select registry:
echo   1. AWS ECR
echo   2. Docker Hub
set /p REGISTRY_CHOICE="Enter choice [1-2]: "

set /p IMAGE_TAG="Enter image tag [latest]: "
if "!IMAGE_TAG!"=="" set "IMAGE_TAG=latest"
powershell -NoProfile -Command "$t=$env:IMAGE_TAG.ToLower(); $t=[regex]::Replace($t,'[^a-z0-9._]+','-').Trim('-'); if([string]::IsNullOrEmpty($t)){$t='latest'}; Write-Output $t" > "!TMPFILE!"
set /p IMAGE_TAG=<"!TMPFILE!"
del "!TMPFILE!" >nul 2>&1

if "!REGISTRY_CHOICE!"=="1" goto ecr
if "!REGISTRY_CHOICE!"=="2" goto dockerhub
echo ERROR: Invalid choice
exit /b 1

:ecr
set /p AWS_REGION="Enter AWS region, for example us-east-1: "
set /p AWS_ACCOUNT_ID="Enter AWS account ID: "
set /p ECR_REPO="Enter ECR repository name [!IMAGE_NAME!]: "
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

echo ^>^>^> Logging in to ECR...
aws ecr get-login-password --region !AWS_REGION! | docker login --username AWS --password-stdin !REGISTRY_URL!
if !ERRORLEVEL! neq 0 (
  echo ECR login failed
  exit /b 1
)

echo ^>^>^> Ensuring ECR repository exists...
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
set /p DOCKER_USERNAME="Enter Docker Hub username: "
set /p DOCKER_PASSWORD="Enter Docker Hub password or access token: "
set /p DOCKER_REPO="Enter repository name [!IMAGE_NAME!]: "
if "!DOCKER_REPO!"=="" set "DOCKER_REPO=!IMAGE_NAME!"
if "!DOCKER_USERNAME!"=="" (
  echo ERROR: Docker Hub username is required
  exit /b 1
)
if "!DOCKER_PASSWORD!"=="" (
  echo ERROR: Docker Hub password is required
  exit /b 1
)
powershell -NoProfile -Command "Write-Output $env:DOCKER_USERNAME.ToLower()" > "!TMPFILE!"
set /p DOCKER_USER_LC=<"!TMPFILE!"
powershell -NoProfile -Command "Write-Output $env:DOCKER_REPO.ToLower()" > "!TMPFILE!"
set /p DOCKER_REPO=<"!TMPFILE!"
del "!TMPFILE!" >nul 2>&1
set "FULL_IMAGE_NAME=!DOCKER_USER_LC!/!DOCKER_REPO!:!IMAGE_TAG!"

echo ^>^>^> Logging in to Docker Hub...
echo !DOCKER_PASSWORD! | docker login --username !DOCKER_USERNAME! --password-stdin
if !ERRORLEVEL! neq 0 (
  echo Docker Hub login failed
  exit /b 1
)
goto build

:build
echo ^>^>^> Building image: !FULL_IMAGE_NAME!
docker build -f Dockerfile -t "!FULL_IMAGE_NAME!" .
if !ERRORLEVEL! neq 0 (
  echo Docker build failed
  exit /b 1
)

echo ^>^>^> Pushing image: !FULL_IMAGE_NAME!
docker push "!FULL_IMAGE_NAME!"
if !ERRORLEVEL! neq 0 (
  echo Docker push failed
  exit /b 1
)

echo === Done. Image pushed: !FULL_IMAGE_NAME! ===
echo Use this URI with scripts\deploy-image.bat
endlocal
exit /b 0
