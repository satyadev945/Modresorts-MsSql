@echo off
setlocal enabledelayedexpansion
REM Build and push the ModResorts image to Azure ACR or Docker Hub.
REM Run from the repository root:  scripts\build-push.bat

set "PROJECT_NAME=modresorts"
set "IMAGE_NAME=%PROJECT_NAME%"

set "IMAGE_TAG="
set /p IMAGE_TAG="Enter image tag [latest]: "
if "!IMAGE_TAG!"=="" set "IMAGE_TAG=latest"
for /f "delims=" %%T in ('powershell -NoProfile -Command "$t='!IMAGE_TAG!'.ToLower(); $t=[regex]::Replace($t,'[^a-z0-9._]+','-'); $t=$t.Trim('-'); if([string]::IsNullOrEmpty($t)){$t='latest'}; Write-Output $t"') do set "IMAGE_TAG=%%T"

echo Select container registry:
echo   1. Azure Container Registry (ACR)
echo   2. Docker Hub
set "REGISTRY_CHOICE="
set /p REGISTRY_CHOICE="Choice [1/2]: "

if "!REGISTRY_CHOICE!"=="1" (
  set "ACR_NAME="
  set /p ACR_NAME="Enter ACR name (without .azurecr.io): "
  if "!ACR_NAME!"=="" (
    echo ERROR: ACR name is required
    exit /b 1
  )
  echo ^>^>^> Logging in to ACR !ACR_NAME! ...
  az acr login --name !ACR_NAME!
  if !ERRORLEVEL! neq 0 (
    echo ACR login failed
    exit /b 1
  )
  set "FULL_IMAGE_NAME=!ACR_NAME!.azurecr.io/!IMAGE_NAME!:!IMAGE_TAG!"
) else if "!REGISTRY_CHOICE!"=="2" (
  set "DOCKER_USERNAME="
  set "DOCKER_PASSWORD="
  set /p DOCKER_USERNAME="Enter Docker Hub username: "
  set /p DOCKER_PASSWORD="Enter Docker Hub password/token: "
  if "!DOCKER_USERNAME!"=="" (
    echo ERROR: Docker Hub username is required
    exit /b 1
  )
  echo ^>^>^> Logging in to Docker Hub ...
  echo !DOCKER_PASSWORD! | docker login --username !DOCKER_USERNAME! --password-stdin
  if !ERRORLEVEL! neq 0 (
    echo Docker Hub login failed
    exit /b 1
  )
  set "FULL_IMAGE_NAME=!DOCKER_USERNAME!/!IMAGE_NAME!:!IMAGE_TAG!"
) else (
  echo ERROR: Invalid registry choice
  exit /b 1
)

echo ^>^>^> Building image !FULL_IMAGE_NAME! ...
docker build -f Dockerfile -t !FULL_IMAGE_NAME! .
if !ERRORLEVEL! neq 0 (
  echo Docker build failed
  exit /b 1
)

echo ^>^>^> Pushing image !FULL_IMAGE_NAME! ...
docker push !FULL_IMAGE_NAME!
if !ERRORLEVEL! neq 0 (
  echo Docker push failed
  exit /b 1
)

echo SUCCESS: image pushed - !FULL_IMAGE_NAME!
echo Use this URI with scripts\deploy-image.bat
endlocal
