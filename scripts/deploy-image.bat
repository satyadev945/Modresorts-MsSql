@echo off
setlocal enabledelayedexpansion

REM Run from repository root: scripts\deploy-image.bat
set "APP_NAME=modresorts"
set "NAMESPACE=modresorts"
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

mkdir "!WORK_DIR!"
copy /Y kubernetes\*.yaml "!WORK_DIR!\" >nul
if !ERRORLEVEL! neq 0 (
    echo Failed to copy manifests
    exit /b 1
)

echo Updating manifests...
set "PS_IMAGE_URI=!IMAGE_URI!"
set "PS_WEATHER_API_KEY=!WEATHER_API_KEY!"
set "PS_NAMESPACE=!NAMESPACE!"
powershell -NoProfile -Command "Get-ChildItem '!WORK_DIR!\*.yaml' | ForEach-Object { (Get-Content $_.FullName -Raw).Replace('{{IMAGE_URI}}', $env:PS_IMAGE_URI).Replace('{{NAMESPACE}}', $env:PS_NAMESPACE).Replace('{{WEATHER_API_KEY}}', $env:PS_WEATHER_API_KEY) | Set-Content -NoNewline $_.FullName }"
if !ERRORLEVEL! neq 0 (
    echo Failed to update manifests
    exit /b 1
)

echo Configuring kubectl...
az aks get-credentials --resource-group !RESOURCE_GROUP! --name !CLUSTER_NAME! --overwrite-existing
if !ERRORLEVEL! neq 0 (
    echo Failed to get AKS credentials
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

echo Check ingress address: kubectl get ingress !APP_NAME!-ingress -n !NAMESPACE!
echo Rollback: kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!

rmdir /S /Q "!WORK_DIR!"
endlocal
