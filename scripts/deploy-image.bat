@echo off
setlocal enabledelayedexpansion

set "APP_NAME=modresorts"
set "NAMESPACE=modresorts"

echo === Deploy %APP_NAME% to AWS EKS ===

where aws >nul 2>&1
if !ERRORLEVEL! neq 0 (
  echo ERROR: aws CLI is required
  exit /b 1
)
where kubectl >nul 2>&1
if !ERRORLEVEL! neq 0 (
  echo ERROR: kubectl is required
  exit /b 1
)

set "AWS_REGION="
set "CLUSTER_NAME="
set "IMAGE_URI="
set "WEATHER_API_KEY="
set "SERVER_NAME="
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

set "WORK_DIR=%TEMP%\modresorts-k8s"
if exist "!WORK_DIR!" rmdir /s /q "!WORK_DIR!"
mkdir "!WORK_DIR!"
copy /y kubernetes\*.yaml "!WORK_DIR!\" >nul
if !ERRORLEVEL! neq 0 (
  echo ERROR: could not copy manifests. Run from the repository root.
  exit /b 1
)

set "TPL_IMAGE_URI=!IMAGE_URI!"
set "TPL_WEATHER_API_KEY=!WEATHER_API_KEY!"
set "TPL_SERVER_NAME=!SERVER_NAME!"
set "TPL_NAMESPACE=!NAMESPACE!"
set "TPL_FILE=!WORK_DIR!\deployment.yaml"

powershell -NoProfile -Command "$f=$env:TPL_FILE; (Get-Content $f -Raw).Replace('{{IMAGE_URI}}',$env:TPL_IMAGE_URI).Replace('{{WEATHER_API_KEY}}',$env:TPL_WEATHER_API_KEY).Replace('{{SERVER_NAME}}',$env:TPL_SERVER_NAME).Replace('{{NAMESPACE}}',$env:TPL_NAMESPACE) | Set-Content -NoNewline $f"
if !ERRORLEVEL! neq 0 (
  echo ERROR: placeholder replacement failed
  exit /b 1
)

echo Configuring kubectl...
aws eks update-kubeconfig --region !AWS_REGION! --name !CLUSTER_NAME!
if !ERRORLEVEL! neq 0 (
  echo ERROR: update-kubeconfig failed
  exit /b 1
)

echo Verifying cluster connectivity...
kubectl cluster-info
if !ERRORLEVEL! neq 0 (
  echo ERROR: cannot reach cluster
  exit /b 1
)

echo Applying manifests...
kubectl apply -f "!WORK_DIR!\namespace.yaml"
if !ERRORLEVEL! neq 0 exit /b 1
kubectl apply -f "!WORK_DIR!\deployment.yaml"
if !ERRORLEVEL! neq 0 exit /b 1
kubectl apply -f "!WORK_DIR!\service.yaml"
if !ERRORLEVEL! neq 0 exit /b 1
kubectl apply -f "!WORK_DIR!\ingress.yaml"
if !ERRORLEVEL! neq 0 exit /b 1

echo Waiting for rollout...
kubectl rollout status deployment/!APP_NAME! -n !NAMESPACE! --timeout=300s
if !ERRORLEVEL! neq 0 (
  echo ERROR: rollout failed. To roll back run:
  echo   kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
  exit /b 1
)

kubectl get pods,svc,ingress -n !NAMESPACE!

echo Get the application address with:
echo   kubectl get ingress !APP_NAME!-ingress -n !NAMESPACE!

rmdir /s /q "!WORK_DIR!"
endlocal
