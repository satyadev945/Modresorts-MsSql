@echo off
setlocal enabledelayedexpansion

REM Run from the repository root: scripts\deploy-image.bat
set "APP_NAME=modresorts"
set "NAMESPACE=modresorts"
set "RENDER_DIR=%TEMP%\modresorts-k8s"

where aws >nul 2>&1
if !ERRORLEVEL! neq 0 (
  echo ERROR: aws CLI is not installed
  exit /b 1
)
where kubectl >nul 2>&1
if !ERRORLEVEL! neq 0 (
  echo ERROR: kubectl is not installed
  exit /b 1
)
if not exist kubernetes (
  echo ERROR: kubernetes directory not found. Run from the repository root.
  exit /b 1
)

set /p AWS_REGION="AWS region (e.g. us-east-1): "
set /p CLUSTER_NAME="EKS cluster name: "
set /p IMAGE_URI="Docker image URI (registry/repo:tag): "
if "!AWS_REGION!"=="" (
  echo ERROR: AWS region is required
  exit /b 1
)
if "!CLUSTER_NAME!"=="" (
  echo ERROR: cluster name is required
  exit /b 1
)
if "!IMAGE_URI!"=="" (
  echo ERROR: image URI is required
  exit /b 1
)
set /p WEATHER_API_KEY="Enter value for WEATHER_API_KEY (or press Enter to skip): "
set /p SERVER_NAME="Enter value for SERVER_NAME (or press Enter to skip): "

if exist "!RENDER_DIR!" rmdir /s /q "!RENDER_DIR!"
mkdir "!RENDER_DIR!"
copy /y kubernetes\*.yaml "!RENDER_DIR!\" >nul

call :replace "!RENDER_DIR!\deployment.yaml" "{{IMAGE_URI}}" IMAGE_URI
call :replace "!RENDER_DIR!\deployment.yaml" "{{WEATHER_API_KEY}}" WEATHER_API_KEY
call :replace "!RENDER_DIR!\deployment.yaml" "{{SERVER_NAME}}" SERVER_NAME

echo Configuring kubectl for cluster !CLUSTER_NAME!...
aws eks update-kubeconfig --region !AWS_REGION! --name !CLUSTER_NAME!
if !ERRORLEVEL! neq 0 (
  echo Failed to configure kubectl
  exit /b 1
)

echo Verifying cluster connectivity...
kubectl cluster-info
if !ERRORLEVEL! neq 0 (
  echo ERROR: cannot reach cluster
  exit /b 1
)

echo Applying manifests...
kubectl apply -f "!RENDER_DIR!\namespace.yaml"
if !ERRORLEVEL! neq 0 exit /b 1
kubectl apply -f "!RENDER_DIR!\deployment.yaml"
if !ERRORLEVEL! neq 0 exit /b 1
kubectl apply -f "!RENDER_DIR!\service.yaml"
if !ERRORLEVEL! neq 0 exit /b 1
kubectl apply -f "!RENDER_DIR!\ingress.yaml"
if !ERRORLEVEL! neq 0 exit /b 1

echo Waiting for rollout...
kubectl rollout status deployment/!APP_NAME! -n !NAMESPACE! --timeout=300s
if !ERRORLEVEL! neq 0 (
  echo ERROR: rollout failed. Roll back with:
  echo   kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
  exit /b 1
)

kubectl get pods,svc,ingress -n !NAMESPACE!

echo Application address (ALB hostname, may take a few minutes to appear):
kubectl get ingress !APP_NAME!-ingress -n !NAMESPACE! -o jsonpath="{.status.loadBalancer.ingress[0].hostname}"
echo.
echo Rollback if needed: kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!

rmdir /s /q "!RENDER_DIR!" >nul 2>&1
endlocal
exit /b 0

:replace
powershell -NoProfile -Command "(Get-Content -Raw '%~1').Replace('%~2', [string]$env:%~3) | Set-Content -NoNewline '%~1'"
exit /b 0
