@echo off & setlocal enabledelayedexpansion

REM Run from repository root: scripts\deploy-image.bat
set "APP_NAME=modresorts"
set "NAMESPACE=modresorts"
set "WORK_DIR=%TEMP%\modresorts-k8s-%RANDOM%"

where az >nul 2>&1
if !ERRORLEVEL! neq 0 (
    echo ERROR: Azure CLI is required
    exit /b 1
)
where kubectl >nul 2>&1
if !ERRORLEVEL! neq 0 (
    echo ERROR: kubectl is required
    exit /b 1
)

set /p RESOURCE_GROUP="Enter Azure resource group: "
set /p CLUSTER_NAME="Enter AKS cluster name: "
set /p IMAGE_URI="Enter Docker image URI (e.g. myacr.azurecr.io/modresorts:latest): "
if "!RESOURCE_GROUP!"=="" (
    echo ERROR: resource group is required
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

set "WEATHER_API_KEY="
set "SERVER_DISPLAY_NAME="
set "WEATHER_SERVICE_GRPC_ENDPOINT="
set /p WEATHER_API_KEY="Enter value for WEATHER_API_KEY (or press Enter to skip): "
set /p SERVER_DISPLAY_NAME="Enter value for SERVER_DISPLAY_NAME (or press Enter to skip): "
set /p WEATHER_SERVICE_GRPC_ENDPOINT="Enter value for WEATHER_SERVICE_GRPC_ENDPOINT (or press Enter to skip): "

mkdir "!WORK_DIR!"
copy /Y kubernetes\*.yaml "!WORK_DIR!\" >nul
if !ERRORLEVEL! neq 0 (
    echo ERROR: could not copy manifests. Run from the repository root.
    exit /b 1
)

REM Replace placeholders using PowerShell (values passed through environment variables)
powershell -NoProfile -Command "Get-ChildItem -Path $env:WORK_DIR -Filter *.yaml | ForEach-Object { $c = Get-Content -Raw $_.FullName; $c = $c.Replace('{{IMAGE_URI}}',$env:IMAGE_URI).Replace('{{NAMESPACE}}',$env:NAMESPACE).Replace('{{WEATHER_API_KEY}}',[string]$env:WEATHER_API_KEY).Replace('{{SERVER_DISPLAY_NAME}}',[string]$env:SERVER_DISPLAY_NAME).Replace('{{WEATHER_SERVICE_GRPC_ENDPOINT}}',[string]$env:WEATHER_SERVICE_GRPC_ENDPOINT); [IO.File]::WriteAllText($_.FullName,$c) }"
if !ERRORLEVEL! neq 0 (
    echo ERROR: failed to update manifests
    exit /b 1
)

echo Configuring kubectl for !CLUSTER_NAME! ...
call az aks get-credentials --resource-group !RESOURCE_GROUP! --name !CLUSTER_NAME! --overwrite-existing
if !ERRORLEVEL! neq 0 (
    echo ERROR: az aks get-credentials failed
    exit /b 1
)

kubectl cluster-info
if !ERRORLEVEL! neq 0 (
    echo ERROR: cannot reach cluster
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
    echo ERROR: rollout failed. To roll back run:
    echo   kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
    exit /b 1
)

kubectl get pods,svc,ingress -n !NAMESPACE!
echo.
echo Check the ingress address: kubectl get ingress -n !NAMESPACE!
echo Port-forward alternative: kubectl port-forward svc/!APP_NAME!-service 8080:80 -n !NAMESPACE!
echo Rollback if needed: kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!

rmdir /S /Q "!WORK_DIR!" >nul 2>&1
endlocal
