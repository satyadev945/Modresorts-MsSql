@echo off
setlocal enabledelayedexpansion
REM Deploy ModResorts to Azure AKS. Run from the repository root.

set "APP_NAME=modresorts"
set "NAMESPACE=modresorts"

echo === ModResorts AKS deployment ===

set "RESOURCE_GROUP="
set "CLUSTER_NAME="
set "IMAGE_URI="
set /p RESOURCE_GROUP="Azure resource group: "
set /p CLUSTER_NAME="AKS cluster name: "
set /p IMAGE_URI="Docker image URI (registry/image:tag): "

if "!RESOURCE_GROUP!"=="" (
    echo Resource group is required
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
set "ENABLE_JMX_APPINFO="
set "SERVER_NAME="
set /p WEATHER_API_KEY="Enter value for WEATHER_API_KEY (or press Enter to skip): "
set /p ENABLE_JMX_APPINFO="Enter value for ENABLE_JMX_APPINFO [true]: "
if "!ENABLE_JMX_APPINFO!"=="" set "ENABLE_JMX_APPINFO=true"
set /p SERVER_NAME="Enter value for SERVER_NAME (or press Enter to skip): "

set "WORK_DIR=%TEMP%\modresorts-k8s-%RANDOM%"
mkdir "!WORK_DIR!"
copy /y kubernetes\*.yaml "!WORK_DIR!\" >nul
if !ERRORLEVEL! neq 0 (
    echo Failed to copy manifests
    exit /b 1
)

REM Values are passed through environment variables to avoid quoting problems
powershell -NoProfile -Command "$f=Join-Path $env:WORK_DIR 'deployment.yaml'; $c=Get-Content -Raw $f; $c=$c.Replace('{{IMAGE_URI}}',$env:IMAGE_URI).Replace('{{WEATHER_API_KEY}}',[string]$env:WEATHER_API_KEY).Replace('{{ENABLE_JMX_APPINFO}}',$env:ENABLE_JMX_APPINFO).Replace('{{SERVER_NAME}}',[string]$env:SERVER_NAME); Set-Content -NoNewline -Path $f -Value $c"
if !ERRORLEVEL! neq 0 (
    echo Failed to update deployment manifest
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
    echo Cannot reach cluster
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

echo Ingress address: run  kubectl get ingress -n !NAMESPACE!  (host modresorts.example.com)
echo Rollback if needed: kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
rmdir /s /q "!WORK_DIR!"
endlocal
