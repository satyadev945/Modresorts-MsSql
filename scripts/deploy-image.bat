@echo off
setlocal enabledelayedexpansion

set "APP_NAME=modresorts"
set "NAMESPACE=modresorts"

echo === Deploy %APP_NAME% to AWS EKS ===
set /p AWS_REGION="AWS region (for example us-east-1): "
set /p CLUSTER_NAME="EKS cluster name: "
set /p IMAGE_URI="Docker image URI (registry/repo:tag): "

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

set "REDIS_HOST="
set "REDIS_PORT="
set "REDIS_PASSWORD="
set "WEATHER_API_KEY="
set /p REDIS_HOST="Enter value for REDIS_HOST (or press Enter to skip): "
set /p REDIS_PORT="Enter value for REDIS_PORT (or press Enter for 6379): "
if "!REDIS_PORT!"=="" set "REDIS_PORT=6379"
set /p REDIS_PASSWORD="Enter value for REDIS_PASSWORD (or press Enter to skip): "
set /p WEATHER_API_KEY="Enter value for WEATHER_API_KEY (or press Enter to skip): "

set "WORK_DIR=%TEMP%\%APP_NAME%-k8s-%RANDOM%"
mkdir "!WORK_DIR!"
copy /y kubernetes\*.yaml "!WORK_DIR!\" >nul

set "DEPLOY_FILE=!WORK_DIR!\deployment.yaml"
powershell -NoProfile -Command "$f=$env:DEPLOY_FILE; (Get-Content $f) -replace '\{\{IMAGE_URI\}\}',$env:IMAGE_URI -replace '\{\{REDIS_HOST\}\}',$env:REDIS_HOST -replace '\{\{REDIS_PORT\}\}',$env:REDIS_PORT -replace '\{\{REDIS_PASSWORD\}\}',$env:REDIS_PASSWORD -replace '\{\{WEATHER_API_KEY\}\}',$env:WEATHER_API_KEY | Set-Content $f"
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
    echo Cannot reach the cluster
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
echo Get the application address with: kubectl get ingress -n !NAMESPACE!

rmdir /s /q "!WORK_DIR!"
endlocal
