@echo off
setlocal enabledelayedexpansion
REM Deploy ModResorts to Azure AKS. Run from the repository root: scripts\deploy-image.bat

set "APP_NAME=modresorts"
set "NAMESPACE=modresorts"

where az >nul 2>&1
if errorlevel 1 (
  echo ERROR: Azure CLI ^(az^) is not installed
  exit /b 1
)
where kubectl >nul 2>&1
if errorlevel 1 (
  echo ERROR: kubectl is not installed
  exit /b 1
)

set "RESOURCE_GROUP="
set /p RESOURCE_GROUP="Enter Azure resource group: "
if "!RESOURCE_GROUP!"=="" (
  echo ERROR: resource group is required
  exit /b 1
)
set "CLUSTER_NAME="
set /p CLUSTER_NAME="Enter AKS cluster name: "
if "!CLUSTER_NAME!"=="" (
  echo ERROR: cluster name is required
  exit /b 1
)
set "IMAGE_URI="
set /p IMAGE_URI="Enter Docker image URI (e.g. myacr.azurecr.io/modresorts:latest): "
if "!IMAGE_URI!"=="" (
  echo ERROR: image URI is required
  exit /b 1
)
set "INGRESS_HOST="
set /p INGRESS_HOST="Enter ingress host [modresorts.example.com]: "
if "!INGRESS_HOST!"=="" set "INGRESS_HOST=modresorts.example.com"

set "WEATHER_API_KEY="
set "WEATHER_API_KEY_FILE="
set "JNDI_INITIAL_CONTEXT_FACTORY="
set "JNDI_PROVIDER_URL="
set /p WEATHER_API_KEY="Enter value for WEATHER_API_KEY (or press Enter to skip): "
set /p WEATHER_API_KEY_FILE="Enter value for WEATHER_API_KEY_FILE (or press Enter to skip): "
set /p JNDI_INITIAL_CONTEXT_FACTORY="Enter value for JNDI_INITIAL_CONTEXT_FACTORY (or press Enter to skip): "
set /p JNDI_PROVIDER_URL="Enter value for JNDI_PROVIDER_URL (or press Enter to skip): "

set "WORK_DIR=%TEMP%\modresorts-k8s-%RANDOM%"
mkdir "!WORK_DIR!"
copy /y kubernetes\*.yaml "!WORK_DIR!\" >nul

echo ^>^>^> Rendering manifests ...
set "PS_IMAGE_URI=!IMAGE_URI!"
set "PS_INGRESS_HOST=!INGRESS_HOST!"
set "PS_NAMESPACE=!NAMESPACE!"
set "PS_WEATHER_API_KEY=!WEATHER_API_KEY!"
set "PS_WEATHER_API_KEY_FILE=!WEATHER_API_KEY_FILE!"
set "PS_JNDI_FACTORY=!JNDI_INITIAL_CONTEXT_FACTORY!"
set "PS_JNDI_URL=!JNDI_PROVIDER_URL!"
powershell -NoProfile -Command "Get-ChildItem '!WORK_DIR!\*.yaml' | ForEach-Object { $c = Get-Content $_.FullName -Raw; $c = $c.Replace('{{IMAGE_URI}}',$env:PS_IMAGE_URI).Replace('{{NAMESPACE}}',$env:PS_NAMESPACE).Replace('{{INGRESS_HOST}}',$env:PS_INGRESS_HOST).Replace('{{WEATHER_API_KEY_FILE}}',$env:PS_WEATHER_API_KEY_FILE).Replace('{{WEATHER_API_KEY}}',$env:PS_WEATHER_API_KEY).Replace('{{JNDI_INITIAL_CONTEXT_FACTORY}}',$env:PS_JNDI_FACTORY).Replace('{{JNDI_PROVIDER_URL}}',$env:PS_JNDI_URL); Set-Content -Path $_.FullName -Value $c -NoNewline }"
if !ERRORLEVEL! neq 0 (
  echo ERROR: failed to render manifests
  exit /b 1
)

echo ^>^>^> Configuring kubectl for !CLUSTER_NAME! ...
az aks get-credentials --resource-group !RESOURCE_GROUP! --name !CLUSTER_NAME! --overwrite-existing
if !ERRORLEVEL! neq 0 (
  echo ERROR: failed to get AKS credentials
  exit /b 1
)
kubectl cluster-info
if !ERRORLEVEL! neq 0 (
  echo ERROR: cannot reach the cluster
  exit /b 1
)

echo ^>^>^> Applying manifests ...
for %%F in (namespace deployment service ingress) do (
  kubectl apply -f "!WORK_DIR!\%%F.yaml"
  if !ERRORLEVEL! neq 0 (
    echo ERROR: failed to apply %%F.yaml
    exit /b 1
  )
)

echo ^>^>^> Waiting for rollout ...
kubectl rollout status deployment/!APP_NAME! -n !NAMESPACE! --timeout=300s
if !ERRORLEVEL! neq 0 (
  echo ERROR: rollout failed. To roll back run:
  echo   kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
  echo Inspect with: kubectl describe pods -n !NAMESPACE!
  exit /b 1
)

kubectl get pods,svc,ingress -n !NAMESPACE!

echo.
echo Deployment complete.
echo Application URL: http://!INGRESS_HOST!/
echo Rollback if needed: kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
rmdir /s /q "!WORK_DIR!"
endlocal
