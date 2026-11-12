@echo off
setlocal enabledelayedexpansion

set "APP_NAME=modresorts"
set "NAMESPACE=modresorts"
set "K8S_SRC=%~dp0..\kubernetes"
set "WORK_DIR=%TEMP%\modresorts-k8s-%RANDOM%"

echo === ModResorts - Deploy to Azure AKS ===

set "RESOURCE_GROUP="
set /p RESOURCE_GROUP="Enter Azure resource group: "
if "!RESOURCE_GROUP!"=="" (
  echo Resource group is required
  exit /b 1
)
set "CLUSTER_NAME="
set /p CLUSTER_NAME="Enter AKS cluster name: "
if "!CLUSTER_NAME!"=="" (
  echo AKS cluster name is required
  exit /b 1
)
set "IMAGE_URI="
set /p IMAGE_URI="Enter Docker image URI (e.g. myacr.azurecr.io/modresorts:latest): "
if "!IMAGE_URI!"=="" (
  echo Image URI is required
  exit /b 1
)
set "WEATHER_API_KEY="
set /p WEATHER_API_KEY="Enter value for WEATHER_API_KEY (or press Enter to skip): "
set "WEATHER_JMX_ENABLED="
set /p WEATHER_JMX_ENABLED="Enter value for WEATHER_JMX_ENABLED [false]: "
if "!WEATHER_JMX_ENABLED!"=="" set "WEATHER_JMX_ENABLED=false"

mkdir "!WORK_DIR!"
xcopy /E /I /Y /Q "!K8S_SRC!" "!WORK_DIR!" >nul
if !ERRORLEVEL! neq 0 (
  echo Failed to copy manifests
  exit /b 1
)

set "DEPLOY_FILE=!WORK_DIR!\deployment.yaml"
powershell -NoProfile -Command "(Get-Content -Raw '!DEPLOY_FILE!').Replace('{{IMAGE_URI}}', $env:IMAGE_URI).Replace('{{WEATHER_API_KEY}}', $env:WEATHER_API_KEY).Replace('{{WEATHER_JMX_ENABLED}}', $env:WEATHER_JMX_ENABLED) | Set-Content '!DEPLOY_FILE!'"
if !ERRORLEVEL! neq 0 (
  echo Failed to update deployment manifest
  exit /b 1
)

echo Configuring kubectl for cluster !CLUSTER_NAME! ...
az aks get-credentials --resource-group !RESOURCE_GROUP! --name !CLUSTER_NAME! --overwrite-existing
if !ERRORLEVEL! neq 0 (
  echo Failed to get AKS credentials
  exit /b 1
)

echo Verifying cluster connectivity ...
kubectl cluster-info
if !ERRORLEVEL! neq 0 (
  echo Cannot reach cluster
  exit /b 1
)

echo Applying manifests ...
kubectl apply -f "!WORK_DIR!\namespace.yaml"
if !ERRORLEVEL! neq 0 exit /b 1
kubectl apply -f "!WORK_DIR!\deployment.yaml"
if !ERRORLEVEL! neq 0 exit /b 1
kubectl apply -f "!WORK_DIR!\service.yaml"
if !ERRORLEVEL! neq 0 exit /b 1
kubectl apply -f "!WORK_DIR!\ingress.yaml"
if !ERRORLEVEL! neq 0 exit /b 1

echo Waiting for rollout ...
kubectl rollout status deployment/!APP_NAME! -n !NAMESPACE! --timeout=300s
if !ERRORLEVEL! neq 0 (
  echo Rollout failed. To roll back run:
  echo   kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
  exit /b 1
)

echo Resources:
kubectl get pods,svc,ingress -n !NAMESPACE!

for /f "delims=" %%I in ('kubectl get ingress !APP_NAME!-ingress -n !NAMESPACE! -o jsonpath^="{.status.loadBalancer.ingress[0].ip}"') do set "INGRESS_IP=%%I"
if defined INGRESS_IP (
  echo Application URL: http://!INGRESS_IP!/ ^(host header: modresorts.example.com^)
) else (
  echo Ingress address not yet assigned. Check: kubectl get ingress -n !NAMESPACE!
)
echo Rollback if needed: kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!

rmdir /S /Q "!WORK_DIR!" 2>nul
endlocal
