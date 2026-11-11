@echo off
setlocal enabledelayedexpansion

REM Run from repository root: scripts\deploy-image.bat
set "APP_NAME=modresorts"
set "NAMESPACE=modresorts"

echo === ModResorts - Deploy to Azure AKS ===

set /p RESOURCE_GROUP="Enter Azure resource group: "
if "!RESOURCE_GROUP!"=="" (
    echo Resource group is required
    exit /b 1
)
set /p CLUSTER_NAME="Enter AKS cluster name: "
if "!CLUSTER_NAME!"=="" (
    echo AKS cluster name is required
    exit /b 1
)
set /p IMAGE_URI="Enter Docker image URI (e.g. myacr.azurecr.io/modresorts:latest): "
if "!IMAGE_URI!"=="" (
    echo Image URI is required
    exit /b 1
)

set "WEATHER_API_KEY="
set "JMX_APPINFO_ENABLED="
set "SPRING_DATASOURCE_URL="
set "SPRING_DATASOURCE_USERNAME="
set "SPRING_DATASOURCE_PASSWORD="
set /p WEATHER_API_KEY="Enter value for WEATHER_API_KEY (or press Enter to skip): "
set /p JMX_APPINFO_ENABLED="Enter value for JMX_APPINFO_ENABLED [true]: "
if "!JMX_APPINFO_ENABLED!"=="" set "JMX_APPINFO_ENABLED=true"
set /p SPRING_DATASOURCE_URL="Enter value for SPRING_DATASOURCE_URL (or press Enter to skip): "
set /p SPRING_DATASOURCE_USERNAME="Enter value for SPRING_DATASOURCE_USERNAME (or press Enter to skip): "
set /p SPRING_DATASOURCE_PASSWORD="Enter value for SPRING_DATASOURCE_PASSWORD (or press Enter to skip): "

REM Work on a temp copy so the template manifests keep their placeholders
set "WORK_DIR=%TEMP%\modresorts-k8s-%RANDOM%"
mkdir "!WORK_DIR!"
copy /y kubernetes\*.yaml "!WORK_DIR!\" >nul
if !ERRORLEVEL! neq 0 (
    echo Failed to copy manifests. Run this script from the repository root.
    exit /b 1
)

set "DEPLOY_FILE=!WORK_DIR!\deployment.yaml"
powershell -NoProfile -Command "$f=$env:DEPLOY_FILE; $c=Get-Content -Raw $f; $c=$c.Replace('{{IMAGE_URI}}',$env:IMAGE_URI).Replace('{{NAMESPACE}}',$env:NAMESPACE).Replace('{{WEATHER_API_KEY}}',$env:WEATHER_API_KEY).Replace('{{JMX_APPINFO_ENABLED}}',$env:JMX_APPINFO_ENABLED).Replace('{{SPRING_DATASOURCE_URL}}',$env:SPRING_DATASOURCE_URL).Replace('{{SPRING_DATASOURCE_USERNAME}}',$env:SPRING_DATASOURCE_USERNAME).Replace('{{SPRING_DATASOURCE_PASSWORD}}',$env:SPRING_DATASOURCE_PASSWORD); [System.IO.File]::WriteAllText($f,$c)"
if !ERRORLEVEL! neq 0 (
    echo Failed to update manifests
    exit /b 1
)

echo Configuring kubectl for AKS cluster !CLUSTER_NAME!...
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

echo Ingress address - check with: kubectl get ingress -n !NAMESPACE!
echo Or test via: kubectl port-forward svc/!APP_NAME!-service 8080:80 -n !NAMESPACE!
echo === Deployment complete ===
echo Rollback: kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!

rmdir /s /q "!WORK_DIR!"
endlocal
