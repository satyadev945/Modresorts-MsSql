@echo off
setlocal enabledelayedexpansion

REM Run from the repository root:  scripts\deploy-image.bat
set "APP_NAME=modresorts"

echo === ModResorts deployment to AWS EKS ===

set "AWS_REGION="
set "CLUSTER_NAME="
set "IMAGE_URI="
set "NAMESPACE="
set /p AWS_REGION="Enter AWS region (e.g. us-east-1): "
set /p CLUSTER_NAME="Enter EKS cluster name: "
set /p IMAGE_URI="Enter Docker image URI (registry/repo:tag): "
set /p NAMESPACE="Enter Kubernetes namespace (default: !APP_NAME!): "
if "!NAMESPACE!"=="" set "NAMESPACE=!APP_NAME!"

if "!AWS_REGION!"=="" (
  echo ERROR: AWS region is required
  exit /b 1
)
if "!CLUSTER_NAME!"=="" (
  echo ERROR: EKS cluster name is required
  exit /b 1
)
if "!IMAGE_URI!"=="" (
  echo ERROR: Image URI is required
  exit /b 1
)

echo Optional application settings, press Enter to skip
set "WEATHER_API_KEY="
set "REDIS_HOST="
set "REDIS_PORT="
set "REDIS_PASSWORD="
set "REDIS_CACHE_TTL_SECONDS="
set "JNDI_INITIAL_CONTEXT_FACTORY="
set "JNDI_PROVIDER_URL="
set /p WEATHER_API_KEY="Enter value for WEATHER_API_KEY (or press Enter to skip): "
set /p REDIS_HOST="Enter value for REDIS_HOST (or press Enter to skip): "
set /p REDIS_PORT="Enter value for REDIS_PORT (default 6379): "
if "!REDIS_PORT!"=="" set "REDIS_PORT=6379"
set /p REDIS_PASSWORD="Enter value for REDIS_PASSWORD (or press Enter to skip): "
set /p REDIS_CACHE_TTL_SECONDS="Enter value for REDIS_CACHE_TTL_SECONDS (default 60): "
if "!REDIS_CACHE_TTL_SECONDS!"=="" set "REDIS_CACHE_TTL_SECONDS=60"
set /p JNDI_INITIAL_CONTEXT_FACTORY="Enter value for JNDI_INITIAL_CONTEXT_FACTORY (or press Enter to skip): "
set /p JNDI_PROVIDER_URL="Enter value for JNDI_PROVIDER_URL (or press Enter to skip): "

REM Work on a temporary copy so the template manifests keep their placeholders
set "WORK_DIR=%TEMP%\modresorts_k8s_%RANDOM%"
mkdir "!WORK_DIR!"
copy /y kubernetes\*.yaml "!WORK_DIR!\" >nul
if !ERRORLEVEL! neq 0 (
  echo Failed to copy Kubernetes manifests. Run this script from the repository root.
  exit /b 1
)

powershell -NoProfile -Command "Get-ChildItem -Path '!WORK_DIR!' -Filter *.yaml | ForEach-Object { $c = [IO.File]::ReadAllText($_.FullName); foreach ($k in 'IMAGE_URI','NAMESPACE','WEATHER_API_KEY','REDIS_HOST','REDIS_PORT','REDIS_PASSWORD','REDIS_CACHE_TTL_SECONDS','JNDI_INITIAL_CONTEXT_FACTORY','JNDI_PROVIDER_URL') { $v = [Environment]::GetEnvironmentVariable($k); if ($v -eq $null) { $v = '' }; $c = $c.Replace('{{' + $k + '}}', $v) }; [IO.File]::WriteAllText($_.FullName, $c) }"
if !ERRORLEVEL! neq 0 (
  echo Failed to update manifests
  exit /b 1
)

echo Configuring kubectl for cluster !CLUSTER_NAME!...
aws eks update-kubeconfig --region !AWS_REGION! --name !CLUSTER_NAME!
if !ERRORLEVEL! neq 0 (
  echo Failed to configure kubectl
  exit /b 1
)

echo Verifying cluster connectivity...
kubectl cluster-info
if !ERRORLEVEL! neq 0 (
  echo ERROR: cannot reach the cluster
  exit /b 1
)

echo Applying Kubernetes manifests...
kubectl apply -f "!WORK_DIR!\namespace.yaml"
if !ERRORLEVEL! neq 0 (
  echo Failed to apply namespace
  exit /b 1
)
kubectl apply -f "!WORK_DIR!\deployment.yaml"
if !ERRORLEVEL! neq 0 (
  echo Failed to apply deployment
  exit /b 1
)
kubectl apply -f "!WORK_DIR!\service.yaml"
if !ERRORLEVEL! neq 0 (
  echo Failed to apply service
  exit /b 1
)
kubectl apply -f "!WORK_DIR!\ingress.yaml"
if !ERRORLEVEL! neq 0 (
  echo Failed to apply ingress
  exit /b 1
)

echo Waiting for rollout...
kubectl rollout status deployment/!APP_NAME! -n !NAMESPACE! --timeout=300s
if !ERRORLEVEL! neq 0 (
  echo ERROR: rollout failed. To roll back run:
  echo   kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
  exit /b 1
)

echo Deployed resources:
kubectl get pods,svc,ingress -n !NAMESPACE!

echo Application URL is the ADDRESS of the ingress shown above, or run:
echo   kubectl get ingress !APP_NAME!-ingress -n !NAMESPACE!
echo Rollback if needed: kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!

rmdir /s /q "!WORK_DIR!" >nul 2>&1
endlocal
