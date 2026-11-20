@echo off
setlocal enabledelayedexpansion

set "PROJECT_NAME=modresorts"
set "IMAGE_NAME=%PROJECT_NAME%"

set /p IMAGE_TAG="Enter image tag [latest]: "
if "!IMAGE_TAG!"=="" set "IMAGE_TAG=latest"
for /f "delims=" %%T in ('powershell -NoProfile -Command "$t=$env:IMAGE_TAG.ToLower(); $t=[regex]::Replace($t,'[^a-z0-9._-]+','-').Trim('-'); if([string]::IsNullOrEmpty($t)){$t='latest'}; Write-Output $t"') do set "IMAGE_TAG=%%T"

echo Select registry:
echo   1. AWS ECR
echo   2. Docker Hub
set /p REGISTRY_CHOICE="Choice [1]: "
if "!REGISTRY_CHOICE!"=="" set "REGISTRY_CHOICE=1"

if "!REGISTRY_CHOICE!"=="1" (
  set /p AWS_REGION="AWS region [us-east-1]: "
  if "!AWS_REGION!"=="" set "AWS_REGION=us-east-1"
  set /p AWS_ACCOUNT_ID="AWS account ID: "
  if "!AWS_ACCOUNT_ID!"=="" (
    echo AWS account ID is required
    exit /b 1
  )
  set /p ECR_REPO="ECR repository name [!IMAGE_NAME!]: "
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
  set /p DOCKER_USERNAME="Docker Hub username: "
  set /p DOCKER_PASSWORD="Docker Hub password/token: "
  if "!DOCKER_USERNAME!"=="" (
    echo Username is required
    exit /b 1
  )
  set "FULL_IMAGE_NAME=!DOCKER_USERNAME!/!IMAGE_NAME!:!IMAGE_TAG!"
  echo Logging in to Docker Hub...
  echo !DOCKER_PASSWORD! | docker login --username !DOCKER_USERNAME! --password-stdin
  if !ERRORLEVEL! neq 0 (
    echo Docker Hub login failed
    exit /b 1
  )
) else (
  echo Invalid choice
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
endlocal
