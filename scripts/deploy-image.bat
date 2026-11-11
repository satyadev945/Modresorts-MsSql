@echo off
setlocal enabledelayedexpansion

set "APP_NAME=modresorts"
set "NAMESPACE=modresorts"
set "WORK_DIR=%TEMP%\modresorts-k8s"

echo === Deploy %APP_NAME% to AWS EKS ===
set /p AWS_REGION="Enter AWS region (e.g. us-east-1): "
set /p CLUSTER_NAME="Enter EKS cluster name: "
set /p IMAGE_URI="Enter Docker image URI (registry/repo:tag): "
if "!AWS_REGION!"=="" (
  echo AWS region is required
  exit /b 1
)
if "!CLUSTER_NAME!"=="" (
  echo Cluster name is required
  exit /b 1
)
if "!IMAGE_URI!"=="" (
  echo Image URI is required
  exit /b 1
)

set "WEATHER_API_KEY="
set /p WEATHER_API_KEY="Enter value for WEATHER_API_KEY (or press Enter to skip): "
set "ENABLE_JMX_MBEAN="
set /p ENABLE_JMX_MBEAN="Enter value for ENABLE_JMX_MBEAN [true]: "
if "!ENABLE_JMX_MBEAN!"=="" set "ENABLE_JMX_MBEAN=true"

if exist "!WORK_DIR!" rmdir /s /q "!WORK_DIR!"
mkdir "!WORK_DIR!"
copy /y kubernetes\*.yaml "!WORK_DIR!\" >nul

powershell -NoProfile -Command "$f='!WORK_DIR!\deployment.yaml'; (Get-Content $f -Raw).Replace('{{IMAGE_URI}}','!IMAGE_URI!').Replace('{{WEATHER_API_KEY}}','!WEATHER_API_KEY!').Replace('{{ENABLE_JMX_MBEAN}}','!ENABLE_JMX_MBEAN!').Replace('{{NAMESPACE}}','!NAMESPACE!') | Set-Content $f"
if !ERRORLEVEL! neq 0 (
  echo Failed to update manifests
  exit /b 1
)

echo Configuring kubectl...
aws eks update-kubeconfig --region !AWS_REGION! --name !CLUSTER_NAME!
if !ERRORLEVEL! neq 0 (
  echo Failed to configure kubectl
  exit /b 1
)

echo Verifying cluster connectivity...
kubectl cluster-info
if !ERRORLEVEL! neq 0 (
  echo Cannot connect to cluster
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
  echo Rollout failed. To roll back run:
  echo   kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
  exit /b 1
)

kubectl get pods,svc,ingress -n !NAMESPACE!
echo Get the application URL with: kubectl get ingress !APP_NAME!-ingress -n !NAMESPACE!
echo Rollback if needed: kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
rmdir /s /q "!WORK_DIR!"
endlocal
