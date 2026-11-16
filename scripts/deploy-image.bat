@echo off & setlocal enabledelayedexpansion

REM Run from repository root: scripts\deploy-image.bat
set "APP_NAME=modresorts"
set "DEFAULT_NAMESPACE=modresorts"

where az >nul 2>nul
if !ERRORLEVEL! neq 0 (
  echo Azure CLI - az - is required
  exit /b 1
)
where kubectl >nul 2>nul
if !ERRORLEVEL! neq 0 (
  echo kubectl is required
  exit /b 1
)

set /p RESOURCE_GROUP="Enter Azure resource group: "
set /p CLUSTER_NAME="Enter AKS cluster name: "
set /p IMAGE_URI="Enter Docker image URI (full path with tag): "
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
set /p NAMESPACE="Enter Kubernetes namespace [modresorts]: "
if "!NAMESPACE!"=="" set "NAMESPACE=!DEFAULT_NAMESPACE!"
set /p INGRESS_HOST="Enter ingress host [modresorts.example.com]: "
if "!INGRESS_HOST!"=="" set "INGRESS_HOST=modresorts.example.com"
set /p WEATHER_API_KEY="Enter value for WEATHER_API_KEY (or press Enter to skip): "

set "WORK_DIR=%TEMP%\modresorts-k8s-%RANDOM%"
mkdir "!WORK_DIR!"
copy /y kubernetes\*.yaml "!WORK_DIR!\" >nul
if !ERRORLEVEL! neq 0 (
  echo Failed to copy manifests
  exit /b 1
)

set "PS_IMAGE_URI=!IMAGE_URI!"
set "PS_NAMESPACE=!NAMESPACE!"
set "PS_INGRESS_HOST=!INGRESS_HOST!"
set "PS_WEATHER_API_KEY=!WEATHER_API_KEY!"
set "PS_WORK_DIR=!WORK_DIR!"
powershell -NoProfile -Command "Get-ChildItem -Path $env:PS_WORK_DIR -Filter *.yaml | ForEach-Object { $c = Get-Content -Raw $_.FullName; $c = $c.Replace('{{IMAGE_URI}}',$env:PS_IMAGE_URI).Replace('{{NAMESPACE}}',$env:PS_NAMESPACE).Replace('{{INGRESS_HOST}}',$env:PS_INGRESS_HOST).Replace('{{WEATHER_API_KEY}}',$env:PS_WEATHER_API_KEY); Set-Content -NoNewline -Path $_.FullName -Value $c }"
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

kubectl get pods,svc,ingress -n !NAMESPACE!

echo.
echo Deployment complete.
echo Application URL: http://!INGRESS_HOST!/
echo Check ingress address: kubectl get ingress -n !NAMESPACE!
echo Rollback: kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!

rmdir /s /q "!WORK_DIR!"
endlocal
