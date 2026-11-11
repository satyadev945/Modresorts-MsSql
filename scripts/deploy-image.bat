@echo off & setlocal enabledelayedexpansion
rem Deploy ModResorts to GCP GKE.  Usage: scripts\deploy-image.bat

set "APP_NAME=modresorts"
set "NAMESPACE=modresorts"
set "K8S_SRC=%~dp0..\kubernetes"

where gcloud >nul 2>&1
if !ERRORLEVEL! neq 0 (
  echo ERROR: gcloud is not installed or not on PATH.
  exit /b 1
)
where kubectl >nul 2>&1
if !ERRORLEVEL! neq 0 (
  echo ERROR: kubectl is not installed or not on PATH.
  exit /b 1
)
if not exist "%K8S_SRC%\deployment.yaml" (
  echo ERROR: kubernetes manifests not found at %K8S_SRC%
  exit /b 1
)

set "GCP_PROJECT="
set /p GCP_PROJECT="GCP project ID: "
if "!GCP_PROJECT!"=="" (
  echo ERROR: GCP project ID is required.
  exit /b 1
)
set "GCP_ZONE="
set /p GCP_ZONE="GKE cluster zone or region (e.g. us-central1-a): "
if "!GCP_ZONE!"=="" (
  echo ERROR: zone is required.
  exit /b 1
)
set "CLUSTER_NAME="
set /p CLUSTER_NAME="GKE cluster name: "
if "!CLUSTER_NAME!"=="" (
  echo ERROR: cluster name is required.
  exit /b 1
)
set "IMAGE_URI="
set /p IMAGE_URI="Docker image URI (e.g. us-central1-docker.pkg.dev/PROJECT/REPO/modresorts:latest): "
if "!IMAGE_URI!"=="" (
  echo ERROR: image URI is required.
  exit /b 1
)
set "WEATHER_API_KEY="
set /p WEATHER_API_KEY="Enter value for WEATHER_API_KEY (or press Enter to skip): "
set "WEATHER_GRPC_TARGET="
set /p WEATHER_GRPC_TARGET="Enter value for WEATHER_GRPC_TARGET (host:port, or press Enter to skip): "

rem Work on a temporary copy so repository manifests keep their placeholders
set "WORK_DIR=%TEMP%\modresorts-k8s-%RANDOM%"
mkdir "!WORK_DIR!"
xcopy /E /I /Y /Q "%K8S_SRC%" "!WORK_DIR!" >nul
if !ERRORLEVEL! neq 0 (
  echo ERROR: could not copy manifests.
  exit /b 1
)

powershell -NoProfile -Command "Get-ChildItem -Path $env:WORK_DIR -Filter *.yaml | ForEach-Object { $c = [IO.File]::ReadAllText($_.FullName); $c = $c.Replace('{{IMAGE_URI}}',$env:IMAGE_URI).Replace('{{NAMESPACE}}',$env:NAMESPACE).Replace('{{WEATHER_GRPC_TARGET}}',$env:WEATHER_GRPC_TARGET); [IO.File]::WriteAllText($_.FullName, $c) }"
if !ERRORLEVEL! neq 0 (
  echo ERROR: placeholder substitution failed.
  goto :fail
)

echo Configuring kubectl for cluster !CLUSTER_NAME!...
call gcloud container clusters get-credentials !CLUSTER_NAME! --zone !GCP_ZONE! --project !GCP_PROJECT!
if !ERRORLEVEL! neq 0 (
  echo ERROR: failed to get cluster credentials.
  goto :fail
)

echo Verifying cluster connectivity...
kubectl cluster-info
if !ERRORLEVEL! neq 0 (
  echo ERROR: cannot reach the cluster.
  goto :fail
)

echo Applying namespace...
kubectl apply -f "!WORK_DIR!\namespace.yaml"
if !ERRORLEVEL! neq 0 goto :fail

if not "!WEATHER_API_KEY!"=="" (
  echo Creating/updating secret modresorts-secrets...
  kubectl create secret generic modresorts-secrets --from-literal=WEATHER_API_KEY="!WEATHER_API_KEY!" -n !NAMESPACE! --dry-run=client -o yaml | kubectl apply -f -
  if !ERRORLEVEL! neq 0 goto :fail
)

echo Applying deployment, service and ingress...
kubectl apply -f "!WORK_DIR!\deployment.yaml"
if !ERRORLEVEL! neq 0 goto :fail
kubectl apply -f "!WORK_DIR!\service.yaml"
if !ERRORLEVEL! neq 0 goto :fail
kubectl apply -f "!WORK_DIR!\ingress.yaml"
if !ERRORLEVEL! neq 0 goto :fail

echo Waiting for rollout...
kubectl rollout status deployment/!APP_NAME! -n !NAMESPACE! --timeout=300s
if !ERRORLEVEL! neq 0 (
  echo.
  echo ERROR: rollout failed. Inspect and roll back with:
  echo   kubectl describe pods -n !NAMESPACE!
  echo   kubectl logs deployment/!APP_NAME! -n !NAMESPACE!
  echo   kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
  goto :fail
)

echo.
kubectl get pods,svc,ingress -n !NAMESPACE!

echo.
echo Ingress IP may take several minutes to be assigned. Check with:
echo   kubectl get ingress modresorts-ingress -n !NAMESPACE!
echo Then open http://INGRESS_IP/resorts/
echo Rollback if needed: kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!

rmdir /S /Q "!WORK_DIR!" >nul 2>&1
exit /b 0

:fail
rmdir /S /Q "!WORK_DIR!" >nul 2>&1
exit /b 1
