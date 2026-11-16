@echo off
setlocal enabledelayedexpansion

set "PROJECT_NAME=modresorts"
set "IMAGE_NAME=modresorts"
set "SANITIZE_FILE=%TEMP%\modresorts-tag-%RANDOM%.txt"

echo === Build and Push Docker Image (run from repository root) ===

set /p IMAGE_TAG="Enter image tag [latest]: "
if "!IMAGE_TAG!"=="" set "IMAGE_TAG=latest"
set "RAW_TAG=!IMAGE_TAG!"
powershell -NoProfile -Command "$t=('!RAW_TAG!').ToLower() -replace '[^a-z0-9._]+','-'; $t=$t.Trim('-'); if($t){$t}else{'latest'}; Set-Content -Path '!SANITIZE_FILE!' -Value $t -NoNewline"
if !ERRORLEVEL! neq 0 (echo Tag sanitization failed & exit /b 1)
set /p IMAGE_TAG=<"!SANITIZE_FILE!"
del "!SANITIZE_FILE!" >nul 2>&1

echo Select registry:
echo   1. Google Artifact Registry
echo   2. Docker Hub
set /p REGISTRY_CHOICE="Choice [1/2]: "

if "!REGISTRY_CHOICE!"=="1" (
  set /p GCP_PROJECT="GCP project ID: "
  set /p GCP_REGION="Artifact Registry region (e.g. us-central1): "
  set /p AR_REPO="Artifact Registry repository name: "
  if "!GCP_PROJECT!"=="" (echo ERROR: project is required & exit /b 1)
  if "!GCP_REGION!"=="" (echo ERROR: region is required & exit /b 1)
  if "!AR_REPO!"=="" (echo ERROR: repository is required & exit /b 1)
  set "FULL_IMAGE_NAME=!GCP_REGION!-docker.pkg.dev/!GCP_PROJECT!/!AR_REPO!/!IMAGE_NAME!:!IMAGE_TAG!"
  echo Authenticating with Google Cloud...
  call gcloud auth login
  call gcloud config set project !GCP_PROJECT!
  call gcloud auth configure-docker !GCP_REGION!-docker.pkg.dev --quiet
  if !ERRORLEVEL! neq 0 (echo Artifact Registry login failed & exit /b 1)
) else if "!REGISTRY_CHOICE!"=="2" (
  set /p DOCKER_USERNAME="Docker Hub username: "
  set /p DOCKER_PASSWORD="Docker Hub password/token: "
  if "!DOCKER_USERNAME!"=="" (echo ERROR: username is required & exit /b 1)
  if "!DOCKER_PASSWORD!"=="" (echo ERROR: password is required & exit /b 1)
  set "FULL_IMAGE_NAME=!DOCKER_USERNAME!/!IMAGE_NAME!:!IMAGE_TAG!"
  echo Logging in to Docker Hub...
  echo !DOCKER_PASSWORD! | docker login --username !DOCKER_USERNAME! --password-stdin
  if !ERRORLEVEL! neq 0 (echo Docker Hub login failed & exit /b 1)
) else (
  echo ERROR: invalid registry choice
  exit /b 1
)

echo Building image: !FULL_IMAGE_NAME!
docker build -f Dockerfile -t !FULL_IMAGE_NAME! .
if !ERRORLEVEL! neq 0 (echo Docker build failed & exit /b 1)

echo Pushing image: !FULL_IMAGE_NAME!
docker push !FULL_IMAGE_NAME!
if !ERRORLEVEL! neq 0 (echo Docker push failed & exit /b 1)

echo === Done. Image pushed: !FULL_IMAGE_NAME! ===
endlocal
