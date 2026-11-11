@echo off
setlocal enabledelayedexpansion
REM Deploy ModResorts to GKE. Run from the repository root: scripts\deploy-image.bat

set "APP_NAME=modresorts"

echo === ModResorts GKE deployment ===
set /p GCP_PROJECT="Enter GCP project ID: "
set /p GCP_ZONE="Enter GKE cluster zone or region (e.g. us-central1-a): "
set /p CLUSTER_NAME="Enter GKE cluster name: "
set /p IMAGE_URI="Enter full Docker image URI (registry/path:tag): "
set /p NAMESPACE="Enter Kubernetes namespace [modresorts]: "
if "!NAMESPACE!"=="" set "NAMESPACE=modresorts"
set /p INGRESS_HOST="Enter ingress host [modresorts.example.com]: "
if "!INGRESS_HOST!"=="" set "INGRESS_HOST=modresorts.example.com"

if "!GCP_PROJECT!"=="" (echo ERROR: GCP project is required & exit /b 1)
if "!GCP_ZONE!"=="" (echo ERROR: zone is required & exit /b 1)
if "!CLUSTER_NAME!"=="" (echo ERROR: cluster name is required & exit /b 1)
if "!IMAGE_URI!"=="" (echo ERROR: image URI is required & exit /b 1)

echo Optional application settings, press Enter to skip
set /p WEATHER_API_KEY="Enter value for WEATHER_API_KEY (or press Enter to skip): "
set /p JNDI_INITIAL_CONTEXT_FACTORY="Enter value for JNDI_INITIAL_CONTEXT_FACTORY (or press Enter to skip): "
set /p JNDI_PROVIDER_URL="Enter value for JNDI_PROVIDER_URL (or press Enter to skip): "
set /p SERVER_DISPLAY_NAME="Enter value for SERVER_DISPLAY_NAME (or press Enter to skip): "

set "RENDER_DIR=%TEMP%\modresorts-k8s-%RANDOM%"
mkdir "!RENDER_DIR!"
if !ERRORLEVEL! neq 0 (echo Could not create temp directory & exit /b 1)

REM Values are passed to PowerShell via environment variables (no quoting issues)
set "R_IMAGE_URI=!IMAGE_URI!"
set "R_NAMESPACE=!NAMESPACE!"
set "R_INGRESS_HOST=!INGRESS_HOST!"
set "R_WEATHER_API_KEY=!WEATHER_API_KEY!"
set "R_JNDI_INITIAL_CONTEXT_FACTORY=!JNDI_INITIAL_CONTEXT_FACTORY!"
set "R_JNDI_PROVIDER_URL=!JNDI_PROVIDER_URL!"
set "R_SERVER_DISPLAY_NAME=!SERVER_DISPLAY_NAME!"
set "R_OUT=!RENDER_DIR!"

powershell -NoProfile -Command "Get-ChildItem 'kubernetes\*.yaml' | ForEach-Object { $c = [System.IO.File]::ReadAllText($_.FullName); $c = $c.Replace('{{IMAGE_URI}}',$env:R_IMAGE_URI).Replace('{{NAMESPACE}}',$env:R_NAMESPACE).Replace('{{INGRESS_HOST}}',$env:R_INGRESS_HOST).Replace('{{WEATHER_API_KEY}}',$env:R_WEATHER_API_KEY).Replace('{{JNDI_INITIAL_CONTEXT_FACTORY}}',$env:R_JNDI_INITIAL_CONTEXT_FACTORY).Replace('{{JNDI_PROVIDER_URL}}',$env:R_JNDI_PROVIDER_URL).Replace('{{SERVER_DISPLAY_NAME}}',$env:R_SERVER_DISPLAY_NAME); [System.IO.File]::WriteAllText((Join-Path $env:R_OUT $_.Name), $c) }"
if !ERRORLEVEL! neq 0 (echo Manifest rendering failed & exit /b 1)

echo Configuring kubectl...
call gcloud container clusters get-credentials !CLUSTER_NAME! --zone !GCP_ZONE! --project !GCP_PROJECT!
if !ERRORLEVEL! neq 0 (echo Failed to get cluster credentials & exit /b 1)
call kubectl cluster-info
if !ERRORLEVEL! neq 0 (echo Cannot reach cluster & exit /b 1)

echo Applying manifests...
call kubectl apply -f "!RENDER_DIR!\namespace.yaml"
if !ERRORLEVEL! neq 0 (echo Namespace apply failed & exit /b 1)
call kubectl apply -f "!RENDER_DIR!\deployment.yaml"
if !ERRORLEVEL! neq 0 (echo Deployment apply failed & exit /b 1)
call kubectl apply -f "!RENDER_DIR!\service.yaml"
if !ERRORLEVEL! neq 0 (echo Service apply failed & exit /b 1)
call kubectl apply -f "!RENDER_DIR!\ingress.yaml"
if !ERRORLEVEL! neq 0 (echo Ingress apply failed & exit /b 1)

echo Waiting for rollout...
call kubectl rollout status deployment/!APP_NAME! -n !NAMESPACE! --timeout=300s
if !ERRORLEVEL! neq 0 (
  echo ERROR: rollout failed. To roll back run:
  echo   kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
  exit /b 1
)

call kubectl get pods,svc,ingress -n !NAMESPACE!

echo Ingress address, if assigned:
call kubectl get ingress !APP_NAME!-ingress -n !NAMESPACE! -o jsonpath="{.status.loadBalancer.ingress[0].ip}"
echo.
echo Rollback if needed: kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!

rmdir /s /q "!RENDER_DIR!"
endlocal
