@echo off
setlocal enabledelayedexpansion

REM Run from the repository root:  scripts\deploy-image.bat
set "APP_NAME=modresorts"
set "NAMESPACE=modresorts"
set "RENDER_DIR=.k8s-rendered"

echo === Deploy !APP_NAME! to AWS EKS ===

where aws >nul 2>&1
if !ERRORLEVEL! neq 0 (
  echo ERROR: aws CLI is not installed
  exit /b 1
)
where kubectl >nul 2>&1
if !ERRORLEVEL! neq 0 (
  echo ERROR: kubectl is not installed
  exit /b 1
)

set /p AWS_REGION="AWS region (e.g. us-east-1): "
set /p CLUSTER_NAME="EKS cluster name: "
set /p IMAGE_URI="Docker image URI (registry/repo:tag): "
if "!AWS_REGION!"=="" (
  echo ERROR: AWS region is required
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
set /p WEATHER_API_KEY="Enter value for WEATHER_API_KEY (or press Enter to skip): "
set "ENABLE_JMX_APPINFO="
set /p ENABLE_JMX_APPINFO="Enter value for ENABLE_JMX_APPINFO [false]: "
if "!ENABLE_JMX_APPINFO!"=="" set "ENABLE_JMX_APPINFO=false"
set "INGRESS_HOST="
set /p INGRESS_HOST="Ingress host name [modresorts.example.com]: "
if "!INGRESS_HOST!"=="" set "INGRESS_HOST=modresorts.example.com"

echo Rendering manifests into !RENDER_DIR!\ ...
if exist "!RENDER_DIR!" rmdir /s /q "!RENDER_DIR!"
mkdir "!RENDER_DIR!"
for %%F in (namespace deployment service ingress) do (
  powershell -NoProfile -Command "(Get-Content -Raw 'kubernetes\%%F.yaml').Replace('{{IMAGE_URI}}',$env:IMAGE_URI).Replace('{{NAMESPACE}}',$env:NAMESPACE).Replace('{{WEATHER_API_KEY}}',$env:WEATHER_API_KEY).Replace('{{ENABLE_JMX_APPINFO}}',$env:ENABLE_JMX_APPINFO).Replace('{{INGRESS_HOST}}',$env:INGRESS_HOST) | Set-Content -NoNewline -Encoding ASCII '!RENDER_DIR!\%%F.yaml'"
  if !ERRORLEVEL! neq 0 (
    echo ERROR: failed to render %%F.yaml
    exit /b 1
  )
)

echo Configuring kubectl...
aws eks update-kubeconfig --region !AWS_REGION! --name !CLUSTER_NAME!
if !ERRORLEVEL! neq 0 (
  echo ERROR: failed to update kubeconfig
  exit /b 1
)

echo Verifying cluster connectivity...
kubectl cluster-info
if !ERRORLEVEL! neq 0 (
  echo ERROR: cannot reach cluster
  exit /b 1
)

echo Applying manifests...
for %%F in (namespace deployment service ingress) do (
  kubectl apply -f "!RENDER_DIR!\%%F.yaml"
  if !ERRORLEVEL! neq 0 (
    echo ERROR: failed to apply %%F.yaml
    exit /b 1
  )
)

echo Waiting for rollout...
kubectl rollout status deployment/!APP_NAME! -n !NAMESPACE! --timeout=300s
if !ERRORLEVEL! neq 0 (
  echo ERROR: rollout failed. To roll back run:
  echo   kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
  echo Inspect with: kubectl describe pods -n !NAMESPACE!
  exit /b 1
)

kubectl get pods,svc,ingress -n !NAMESPACE!

echo Application URL: run the command below to get the ALB address (Host header !INGRESS_HOST!)
echo   kubectl get ingress !APP_NAME!-ingress -n !NAMESPACE!
echo Rollback if needed: kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
endlocal
