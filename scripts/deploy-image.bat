@echo off & setlocal enabledelayedexpansion
REM Deploy ModResorts to GKE. Run from the repository root.

set "APP_NAME=modresorts"
set "NAMESPACE=modresorts"

where gcloud >nul 2>&1
if !ERRORLEVEL! neq 0 (echo ERROR: gcloud is not installed & exit /b 1)
where kubectl >nul 2>&1
if !ERRORLEVEL! neq 0 (echo ERROR: kubectl is not installed & exit /b 1)

set /p GCP_PROJECT="GCP project ID: "
set /p GCP_ZONE="GKE cluster zone/region (e.g. us-central1-a): "
set /p CLUSTER_NAME="GKE cluster name: "
set /p IMAGE_URI="Docker image URI (registry/path:tag): "
if "!GCP_PROJECT!"=="" (echo ERROR: project is required & exit /b 1)
if "!GCP_ZONE!"=="" (echo ERROR: zone is required & exit /b 1)
if "!CLUSTER_NAME!"=="" (echo ERROR: cluster name is required & exit /b 1)
if "!IMAGE_URI!"=="" (echo ERROR: image URI is required & exit /b 1)

set "WEATHER_API_KEY="
set "REMOTE_SERVICE_GRPC_TARGET="
set "SERVER_NAME="
set /p WEATHER_API_KEY="Enter value for WEATHER_API_KEY (or press Enter to skip): "
set /p REMOTE_SERVICE_GRPC_TARGET="Enter value for REMOTE_SERVICE_GRPC_TARGET (or press Enter to skip): "
set /p SERVER_NAME="Enter value for SERVER_NAME (or press Enter for modresorts): "
if "!SERVER_NAME!"=="" set "SERVER_NAME=modresorts"

REM Work on a temporary copy so the template manifests stay untouched
set "WORK_DIR=%TEMP%\modresorts-k8s-%RANDOM%"
mkdir "!WORK_DIR!"
copy /y kubernetes\*.yaml "!WORK_DIR!\" >nul
if !ERRORLEVEL! neq 0 (echo ERROR: cannot copy manifests & exit /b 1)

REM Values are passed through environment variables to PowerShell to avoid quoting problems
powershell -NoProfile -Command "$f='!WORK_DIR!\deployment.yaml'; $c=Get-Content -Raw $f; $c=$c.Replace('{{IMAGE_URI}}',$env:IMAGE_URI).Replace('{{WEATHER_API_KEY}}',$env:WEATHER_API_KEY).Replace('{{REMOTE_SERVICE_GRPC_TARGET}}',$env:REMOTE_SERVICE_GRPC_TARGET).Replace('{{SERVER_NAME}}',$env:SERVER_NAME).Replace('{{NAMESPACE}}',$env:NAMESPACE); [IO.File]::WriteAllText($f,$c)"
if !ERRORLEVEL! neq 0 (echo ERROR: placeholder replacement failed & exit /b 1)

echo Configuring kubectl...
call gcloud container clusters get-credentials !CLUSTER_NAME! --zone !GCP_ZONE! --project !GCP_PROJECT!
if !ERRORLEVEL! neq 0 (echo ERROR: get-credentials failed & exit /b 1)

echo Verifying cluster connectivity...
call kubectl cluster-info
if !ERRORLEVEL! neq 0 (echo ERROR: cannot reach cluster & exit /b 1)

echo Applying manifests...
call kubectl apply -f "!WORK_DIR!\namespace.yaml"
if !ERRORLEVEL! neq 0 (echo ERROR: namespace apply failed & exit /b 1)
call kubectl apply -f "!WORK_DIR!\deployment.yaml"
if !ERRORLEVEL! neq 0 (echo ERROR: deployment apply failed & exit /b 1)
call kubectl apply -f "!WORK_DIR!\service.yaml"
if !ERRORLEVEL! neq 0 (echo ERROR: service apply failed & exit /b 1)
call kubectl apply -f "!WORK_DIR!\ingress.yaml"
if !ERRORLEVEL! neq 0 (echo ERROR: ingress apply failed & exit /b 1)

echo Waiting for rollout...
call kubectl rollout status deployment/!APP_NAME! -n !NAMESPACE! --timeout=300s
if !ERRORLEVEL! neq 0 (
  echo ERROR: rollout failed. To roll back run:
  echo   kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
  exit /b 1
)

call kubectl get pods,svc,ingress -n !NAMESPACE!

echo Ingress address (may take several minutes to be assigned):
call kubectl get ingress !APP_NAME!-ingress -n !NAMESPACE! -o jsonpath="{.status.loadBalancer.ingress[0].ip}"
echo.
echo Rollback if needed: kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!

rmdir /s /q "!WORK_DIR!"
endlocal
