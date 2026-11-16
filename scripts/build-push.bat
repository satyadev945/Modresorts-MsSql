@echo off & setlocal enabledelayedexpansion

REM Run from repository root: scripts\build-push.bat
set "PROJECT_NAME=modresorts"
set "IMAGE_NAME=modresorts"

echo === Build and push Docker image: !IMAGE_NAME! ===
echo Select registry:
echo   1. Azure Container Registry (ACR)
echo   2. Docker Hub
set /p REGISTRY_CHOICE="Enter choice [1-2]: "

set /p IMAGE_TAG="Enter image tag [latest]: "
if "!IMAGE_TAG!"=="" set "IMAGE_TAG=latest"
set "RAW_TAG=!IMAGE_TAG!"
set "TAGFILE=%TEMP%\modresorts_tag.txt"
powershell -NoProfile -Command "$t=$env:RAW_TAG.ToLower() -replace '[^a-z0-9._-]+','-'; $t=$t.Trim('-'); if([string]::IsNullOrEmpty($t)){$t='latest'}; Set-Content -Path $env:TAGFILE -Value $t -NoNewline"
set /p IMAGE_TAG=<"!TAGFILE!"
del "!TAGFILE!" >nul 2>&1
if "!IMAGE_TAG!"=="" set "IMAGE_TAG=latest"

if "!REGISTRY_CHOICE!"=="1" (
    set /p ACR_NAME="Enter ACR name (without .azurecr.io): "
    if "!ACR_NAME!"=="" (
        echo ACR name is required
        exit /b 1
    )
    echo Logging in to ACR !ACR_NAME! ...
    call az acr login --name !ACR_NAME!
    if !ERRORLEVEL! neq 0 (
        echo ACR login failed
        exit /b 1
    )
    set "FULL_IMAGE_NAME=!ACR_NAME!.azurecr.io/!IMAGE_NAME!:!IMAGE_TAG!"
) else if "!REGISTRY_CHOICE!"=="2" (
    set /p DOCKER_USERNAME="Enter Docker Hub username: "
    set /p DOCKER_PASSWORD="Enter Docker Hub password/token: "
    if "!DOCKER_USERNAME!"=="" (
        echo Credentials are required
        exit /b 1
    )
    echo !DOCKER_PASSWORD!| docker login --username !DOCKER_USERNAME! --password-stdin
    if !ERRORLEVEL! neq 0 (
        echo Docker login failed
        exit /b 1
    )
    set "FULL_IMAGE_NAME=!DOCKER_USERNAME!/!IMAGE_NAME!:!IMAGE_TAG!"
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
echo Use this URI with scripts\deploy-image.bat
endlocal
