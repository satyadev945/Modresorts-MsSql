@echo off
setlocal enabledelayedexpansion

set "APP_NAME=modresorts"
set "NAMESPACE=modresorts"

set "RESOURCE_GROUP="
set /p RESOURCE_GROUP="Enter Azure resource group: "
if "!RESOURCE_GROUP!"=="" (
    echo Resource group is required
    exit /b 1
)
set "CLUSTER_NAME="
set /p CLUSTER_NAME="Enter AKS cluster name: "
if "!CLUSTER_NAME!"=="" (
    echo Cluster name is required
    exit /b 1
)
set "IMAGE_URI="
set /p IMAGE_URI="Enter full Docker image URI (registry/name:tag): "
if "!IMAGE_URI!"=="" (
    echo Image URI is required
    exit /b 1
)
set "WEATHER_API_KEY="
set /p WEATHER_API_KEY="Enter value for WEATHER_API_KEY (or press Enter to skip): "
set "SERVER_NAME="
set /p SERVER_NAME="Enter value for SERVER_NAME (or press Enter to skip): "

set "WORK_DIR=%TEMP%\modresorts-k8s"
if exist "!WORK_DIR!" rmdir /s /q "!WORK_DIR!"
mkdir "!WORK_DIR!"
copy /y kubernetes\*.yaml "!WORK_DIR!\" >nul

set "P_IMAGE_URI=!IMAGE_URI!"
set "P_NAMESPACE=!NAMESPACE!"
set "P_WEATHER=!WEATHER_API_KEY!"
set "P_SERVER=!SERVER_NAME!"
powershell -NoProfile -Command "Get-ChildItem '!WORK_DIR!\*.yaml' | ForEach-Object { $c = Get-Content $_.FullName -Raw; $c = $c.Replace('{{IMAGE_URI}}',$env:P_IMAGE_URI).Replace('{{NAMESPACE}}',$env:P_NAMESPACE).Replace('{{WEATHER_API_KEY}}',$env:P_WEATHER).Replace('{{SERVER_NAME}}',$env:P_SERVER); Set-Content -Path $_.FullName -Value $c -NoNewline }"
if !ERRORLEVEL! neq 0 (
    echo Failed to update manifests
    exit /b 1
)

echo Configuring kubectl for !CLUSTER_NAME! ...
az aks get-credentials --resource-group !RESOURCE_GROUP! --name !CLUSTER_NAME! --overwrite-existing
if !ERRORLEVEL! neq 0 (
    echo Failed to get AKS credentials
    exit /b 1
)

kubectl cluster-info
if !ERRORLEVEL! neq 0 (
    echo Cannot reach cluster
    exit /b 1
)

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
    echo Rollout failed. To roll back: kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
    exit /b 1
)

kubectl get pods,svc,ingress -n !NAMESPACE!
echo Application is exposed through ingress modresorts-ingress ^(host modresorts.example.com^).
echo Check address: kubectl get ingress -n !NAMESPACE!
echo Rollback if needed: kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
rmdir /s /q "!WORK_DIR!"
endlocal
