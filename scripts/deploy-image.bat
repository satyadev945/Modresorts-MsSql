@echo off
setlocal enabledelayedexpansion

set "APP_NAME=modresorts"
set "NAMESPACE=modresorts"

echo === ModResorts - Deploy to AWS EKS ===

set "AWS_REGION="
set "CLUSTER_NAME="
set "IMAGE_URI="
set /p AWS_REGION="AWS region (e.g. us-east-1): "
set /p CLUSTER_NAME="EKS cluster name: "
set /p IMAGE_URI="Docker image URI (registry/repo:tag): "
if "!AWS_REGION!"=="" goto missing
if "!CLUSTER_NAME!"=="" goto missing
if "!IMAGE_URI!"=="" goto missing

set "REDIS_HOST="
set "REDIS_PORT="
set "REDIS_CACHE_TTL="
set "WEATHER_API_KEY="
set /p REDIS_HOST="Enter value for REDIS_HOST (or press Enter for localhost): "
set /p REDIS_PORT="Enter value for REDIS_PORT (or press Enter for 6379): "
set /p REDIS_CACHE_TTL="Enter value for REDIS_CACHE_TTL (or press Enter for 300): "
set /p WEATHER_API_KEY="Enter value for WEATHER_API_KEY (or press Enter to skip): "
if "!REDIS_HOST!"=="" set "REDIS_HOST=localhost"
if "!REDIS_PORT!"=="" set "REDIS_PORT=6379"
if "!REDIS_CACHE_TTL!"=="" set "REDIS_CACHE_TTL=300"

set "WORK_DIR=%TEMP%\modresorts-k8s-%RANDOM%"
mkdir "!WORK_DIR!"
copy /y kubernetes\*.yaml "!WORK_DIR!\" >nul
if !ERRORLEVEL! neq 0 (
  echo Failed to copy manifests. Run this script from the repository root.
  exit /b 1
)

powershell -NoProfile -Command "$p=Join-Path $env:WORK_DIR 'deployment.yaml'; (Get-Content $p -Raw).Replace('{{IMAGE_URI}}',$env:IMAGE_URI).Replace('{{REDIS_HOST}}',$env:REDIS_HOST).Replace('{{REDIS_PORT}}',$env:REDIS_PORT).Replace('{{REDIS_CACHE_TTL}}',$env:REDIS_CACHE_TTL).Replace('{{WEATHER_API_KEY}}',$env:WEATHER_API_KEY) | Set-Content -NoNewline $p"
if !ERRORLEVEL! neq 0 (
  echo Failed to render deployment manifest
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
  echo Cannot reach cluster
  exit /b 1
)

echo Applying manifests...
kubectl apply -f "!WORK_DIR!\namespace.yaml"
if !ERRORLEVEL! neq 0 goto failed
kubectl apply -f "!WORK_DIR!\deployment.yaml"
if !ERRORLEVEL! neq 0 goto failed
kubectl apply -f "!WORK_DIR!\service.yaml"
if !ERRORLEVEL! neq 0 goto failed
kubectl apply -f "!WORK_DIR!\ingress.yaml"
if !ERRORLEVEL! neq 0 goto failed

echo Waiting for rollout...
kubectl rollout status deployment/!APP_NAME! -n !NAMESPACE! --timeout=300s
if !ERRORLEVEL! neq 0 goto rollout_failed

kubectl get pods,svc,ingress -n !NAMESPACE!

set "INGRESS_HOST="
kubectl get ingress !APP_NAME!-ingress -n !NAMESPACE! -o jsonpath="{.status.loadBalancer.ingress[0].hostname}" > "!WORK_DIR!\host.txt" 2>nul
set /p INGRESS_HOST=<"!WORK_DIR!\host.txt"
if "!INGRESS_HOST!"=="" (
  echo Ingress address not yet assigned. Check: kubectl get ingress -n !NAMESPACE!
) else (
  echo Application URL: http://!INGRESS_HOST!
)
echo Rollback if needed: kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
rmdir /s /q "!WORK_DIR!" >nul 2>&1
exit /b 0

:missing
echo AWS region, cluster name and image URI are required
exit /b 1

:rollout_failed
echo Rollout failed. To roll back run:
echo   kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
exit /b 1

:failed
echo kubectl apply failed
exit /b 1
