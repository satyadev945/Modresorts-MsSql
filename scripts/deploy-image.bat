@echo off
setlocal enabledelayedexpansion

set "APP_NAME=modresorts"
set "NAMESPACE=modresorts"

echo === Deploy %APP_NAME% to GCP GKE (run from repository root) ===

set /p GCP_PROJECT="GCP project ID: "
set /p GCP_ZONE="GCP zone (e.g. us-central1-a): "
set /p CLUSTER_NAME="GKE cluster name: "
set /p IMAGE_URI="Docker image URI (full path with tag): "

if "!GCP_PROJECT!"=="" (echo ERROR: project is required & exit /b 1)
if "!GCP_ZONE!"=="" (echo ERROR: zone is required & exit /b 1)
if "!CLUSTER_NAME!"=="" (echo ERROR: cluster is required & exit /b 1)
if "!IMAGE_URI!"=="" (echo ERROR: image URI is required & exit /b 1)

set "WEATHER_API_KEY="
set "GRPC_SERVICE_TARGET="
set "SERVER_NAME="
set /p WEATHER_API_KEY="Enter value for WEATHER_API_KEY (or press Enter to skip): "
set /p GRPC_SERVICE_TARGET="Enter value for GRPC_SERVICE_TARGET (or press Enter to skip): "
set /p SERVER_NAME="Enter value for SERVER_NAME (or press Enter to use modresorts): "
if "!SERVER_NAME!"=="" set "SERVER_NAME=modresorts"

set "WORK_DIR=%TEMP%\%APP_NAME%-k8s-%RANDOM%"
mkdir "!WORK_DIR!"
copy /y kubernetes\*.yaml "!WORK_DIR!\" >nul

set "P_IMAGE=!IMAGE_URI!"
set "P_WEATHER=!WEATHER_API_KEY!"
set "P_GRPC=!GRPC_SERVICE_TARGET!"
set "P_SERVER=!SERVER_NAME!"
powershell -NoProfile -Command "$f='!WORK_DIR!\deployment.yaml'; $c=Get-Content $f -Raw; $c=$c.Replace('{{IMAGE_URI}}',$env:P_IMAGE).Replace('{{WEATHER_API_KEY}}',$env:P_WEATHER).Replace('{{GRPC_SERVICE_TARGET}}',$env:P_GRPC).Replace('{{SERVER_NAME}}',$env:P_SERVER); Set-Content -Path $f -Value $c -NoNewline"
if !ERRORLEVEL! neq 0 (echo Failed to update manifests & exit /b 1)

echo Configuring kubectl...
call gcloud container clusters get-credentials !CLUSTER_NAME! --zone !GCP_ZONE! --project !GCP_PROJECT!
if !ERRORLEVEL! neq 0 (echo Failed to get cluster credentials & exit /b 1)

echo Verifying cluster connectivity...
kubectl cluster-info
if !ERRORLEVEL! neq 0 (echo Cannot reach cluster & exit /b 1)

echo Applying manifests...
kubectl apply -f "!WORK_DIR!\namespace.yaml"
if !ERRORLEVEL! neq 0 (echo Failed applying namespace & exit /b 1)
kubectl apply -f "!WORK_DIR!\deployment.yaml"
if !ERRORLEVEL! neq 0 (echo Failed applying deployment & exit /b 1)
kubectl apply -f "!WORK_DIR!\service.yaml"
if !ERRORLEVEL! neq 0 (echo Failed applying service & exit /b 1)
kubectl apply -f "!WORK_DIR!\ingress.yaml"
if !ERRORLEVEL! neq 0 (echo Failed applying ingress & exit /b 1)

echo Waiting for rollout...
kubectl rollout status deployment/%APP_NAME% -n %NAMESPACE% --timeout=300s
if !ERRORLEVEL! neq 0 (
  echo Rollout failed. To roll back run: kubectl rollout undo deployment/%APP_NAME% -n %NAMESPACE%
  exit /b 1
)

kubectl get pods,svc,ingress -n %NAMESPACE%

echo.
echo Get the application URL once the ingress IP is assigned:
echo   kubectl get ingress %APP_NAME%-ingress -n %NAMESPACE%
echo Rollback if needed: kubectl rollout undo deployment/%APP_NAME% -n %NAMESPACE%

rmdir /s /q "!WORK_DIR!"
endlocal
