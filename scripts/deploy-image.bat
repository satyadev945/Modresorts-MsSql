@echo off
setlocal enabledelayedexpansion

set "APP_NAME=modresorts"
set "NAMESPACE=modresorts"

echo === ModResorts - Deploy to AWS EKS ===

set /p AWS_REGION="Enter AWS region (e.g. us-east-1): "
set /p CLUSTER_NAME="Enter EKS cluster name: "
set /p IMAGE_URI="Enter Docker image URI (registry/repo:tag): "
if "!AWS_REGION!"=="" (
  echo ERROR: AWS region is required
  exit /b 1
)
if "!CLUSTER_NAME!"=="" (
  echo ERROR: Cluster name is required
  exit /b 1
)
if "!IMAGE_URI!"=="" (
  echo ERROR: Image URI is required
  exit /b 1
)

set /p REDIS_HOST="Enter value for REDIS_HOST (or press Enter to skip) [redis]: "
set /p REDIS_PORT="Enter value for REDIS_PORT (or press Enter to skip) [6379]: "
set /p REDIS_CACHE_TTL="Enter value for REDIS_CACHE_TTL (or press Enter to skip) [300]: "
set /p WEATHER_API_KEY="Enter value for WEATHER_API_KEY (or press Enter to skip): "
set /p INGRESS_HOST="Enter ingress host name [modresorts.example.com]: "
if "!REDIS_HOST!"=="" set "REDIS_HOST=redis"
if "!REDIS_PORT!"=="" set "REDIS_PORT=6379"
if "!REDIS_CACHE_TTL!"=="" set "REDIS_CACHE_TTL=300"
if "!INGRESS_HOST!"=="" set "INGRESS_HOST=modresorts.example.com"

set "WORK_DIR=%TEMP%\modresorts-k8s-%RANDOM%"
mkdir "!WORK_DIR!"
copy /y kubernetes\*.yaml "!WORK_DIR!\" >nul
if !ERRORLEVEL! neq 0 (
  echo ERROR: could not copy manifests
  exit /b 1
)

powershell -NoProfile -Command "$f=Join-Path $env:WORK_DIR 'deployment.yaml'; (Get-Content $f -Raw).Replace('{{IMAGE_URI}}',$env:IMAGE_URI).Replace('{{REDIS_HOST}}',$env:REDIS_HOST).Replace('{{REDIS_PORT}}',$env:REDIS_PORT).Replace('{{REDIS_CACHE_TTL}}',$env:REDIS_CACHE_TTL).Replace('{{WEATHER_API_KEY}}',$env:WEATHER_API_KEY) | Set-Content $f -NoNewline"
if !ERRORLEVEL! neq 0 (
  echo ERROR: could not update deployment manifest
  exit /b 1
)
powershell -NoProfile -Command "$f=Join-Path $env:WORK_DIR 'ingress.yaml'; (Get-Content $f -Raw).Replace('modresorts.example.com',$env:INGRESS_HOST) | Set-Content $f -NoNewline"
if !ERRORLEVEL! neq 0 (
  echo ERROR: could not update ingress manifest
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
  echo ERROR: Rollout failed. To roll back run:
  echo   kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
  exit /b 1
)

kubectl get pods,svc,ingress -n !NAMESPACE!
echo Ingress address - check with: kubectl get ingress !APP_NAME!-ingress -n !NAMESPACE!
echo Rollback if needed: kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!

rmdir /s /q "!WORK_DIR!" >nul 2>&1
endlocal
