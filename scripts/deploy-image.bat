@echo off
setlocal enabledelayedexpansion

set "APP_NAME=modresorts"
set "NAMESPACE=modresorts"
set "WORK_DIR=%TEMP%\modresorts-k8s"

echo === Deploy %APP_NAME% to Azure AKS ===
set /p RESOURCE_GROUP="Azure resource group: "
set /p CLUSTER_NAME="AKS cluster name: "
set /p IMAGE_URI="Docker image URI (e.g. myacr.azurecr.io/modresorts:latest): "
if "!RESOURCE_GROUP!"=="" goto missing
if "!CLUSTER_NAME!"=="" goto missing
if "!IMAGE_URI!"=="" goto missing
set /p WEATHER_API_KEY="Enter value for WEATHER_API_KEY (or press Enter to skip): "

if exist "!WORK_DIR!" rmdir /s /q "!WORK_DIR!"
mkdir "!WORK_DIR!"
copy /y kubernetes\*.yaml "!WORK_DIR!\" >nul
if !ERRORLEVEL! neq 0 (
    echo Failed to copy manifests. Run this script from the repository root.
    exit /b 1
)

set "PS_IMAGE_URI=!IMAGE_URI!"
set "PS_WEATHER_API_KEY=!WEATHER_API_KEY!"
powershell -NoProfile -Command "$f='!WORK_DIR!\deployment.yaml'; (Get-Content $f -Raw).Replace('{{IMAGE_URI}}',$env:PS_IMAGE_URI).Replace('{{WEATHER_API_KEY}}',$env:PS_WEATHER_API_KEY).Replace('{{NAMESPACE}}','!NAMESPACE!') | Set-Content -NoNewline $f"
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
    echo Rollout failed. To roll back: kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
    exit /b 1
)

kubectl get pods,svc,ingress -n !NAMESPACE!
echo Get ingress address: kubectl get ingress !APP_NAME!-ingress -n !NAMESPACE!
echo Rollback: kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
rmdir /s /q "!WORK_DIR!"
endlocal
exit /b 0

:missing
echo Resource group, cluster name and image URI are required
exit /b 1
