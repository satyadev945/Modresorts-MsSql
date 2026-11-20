@echo off
setlocal enabledelayedexpansion

REM Deploy ModResorts to AWS EKS. Run from the repository root.
set "APP_NAME=modresorts"
set "NAMESPACE=modresorts"

echo === ModResorts: deploy to AWS EKS ===

set /p AWS_REGION="Enter AWS region (e.g. us-east-1): "
set /p CLUSTER_NAME="Enter EKS cluster name: "
set /p IMAGE_URI="Enter Docker image URI (registry/repo:tag): "

if "!AWS_REGION!"=="" (
  echo ERROR: AWS region is required.
  exit /b 1
)
if "!CLUSTER_NAME!"=="" (
  echo ERROR: EKS cluster name is required.
  exit /b 1
)
if "!IMAGE_URI!"=="" (
  echo ERROR: Image URI is required.
  exit /b 1
)

echo Optional application settings (press Enter to skip)
set "WEATHER_API_KEY="
set "SERVER_NAME="
set "JNDI_INITIAL_CONTEXT_FACTORY="
set "JNDI_PROVIDER_URL="
set /p WEATHER_API_KEY="Enter value for WEATHER_API_KEY (or press Enter to skip): "
set /p SERVER_NAME="Enter value for SERVER_NAME (or press Enter to skip): "
set /p JNDI_INITIAL_CONTEXT_FACTORY="Enter value for JNDI_INITIAL_CONTEXT_FACTORY (or press Enter to skip): "
set /p JNDI_PROVIDER_URL="Enter value for JNDI_PROVIDER_URL (or press Enter to skip): "

REM Work on a temporary copy so the template manifests stay untouched
set "WORK_DIR=%TEMP%\modresorts-k8s-%RANDOM%"
mkdir "!WORK_DIR!"
copy /y kubernetes\*.yaml "!WORK_DIR!\" >nul
if !ERRORLEVEL! neq 0 (
  echo ERROR: could not copy manifests. Run this script from the repository root.
  exit /b 1
)

for %%F in ("!WORK_DIR!\*.yaml") do (
  powershell -NoProfile -Command "$p='%%~fF'; $c=Get-Content -Raw $p; $c=$c.Replace('{{IMAGE_URI}}',$env:IMAGE_URI).Replace('{{NAMESPACE}}',$env:NAMESPACE).Replace('{{WEATHER_API_KEY}}',$env:WEATHER_API_KEY).Replace('{{SERVER_NAME}}',$env:SERVER_NAME).Replace('{{JNDI_INITIAL_CONTEXT_FACTORY}}',$env:JNDI_INITIAL_CONTEXT_FACTORY).Replace('{{JNDI_PROVIDER_URL}}',$env:JNDI_PROVIDER_URL); [System.IO.File]::WriteAllText($p,$c)"
  if !ERRORLEVEL! neq 0 (
    echo ERROR: failed to update manifest %%F
    exit /b 1
  )
)

echo Configuring kubectl...
aws eks update-kubeconfig --region !AWS_REGION! --name !CLUSTER_NAME!
if !ERRORLEVEL! neq 0 (
  echo ERROR: failed to configure kubectl
  exit /b 1
)

echo Verifying cluster connectivity...
kubectl cluster-info
if !ERRORLEVEL! neq 0 (
  echo ERROR: cannot reach cluster
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
  echo ERROR: rollout failed. To roll back run:
  echo   kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
  exit /b 1
)

kubectl get pods,svc,ingress -n !NAMESPACE!

echo Ingress address:
kubectl get ingress !APP_NAME!-ingress -n !NAMESPACE! -o jsonpath="{.status.loadBalancer.ingress[0].hostname}"
echo.
echo Rollback if needed: kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!

rmdir /s /q "!WORK_DIR!"
endlocal
