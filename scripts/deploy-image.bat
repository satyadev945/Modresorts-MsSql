@echo off
setlocal enabledelayedexpansion

REM Run from the repository root
set "APP_NAME=modresorts"
set "NAMESPACE=modresorts"

echo === Deploy ModResorts to AWS EKS ===
set /p AWS_REGION="Enter AWS region (for example us-east-1): "
set /p CLUSTER_NAME="Enter EKS cluster name: "
set /p IMAGE_URI="Enter Docker image URI (registry/repo:tag): "
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
set "SERVER_NAME="
set /p WEATHER_API_KEY="Enter value for WEATHER_API_KEY (or press Enter to skip): "
set /p SERVER_NAME="Enter value for SERVER_NAME (or press Enter to skip): "

REM Work on a temp copy so templates keep their placeholders
set "WORK_DIR=%TEMP%\modresorts-k8s-%RANDOM%"
mkdir "!WORK_DIR!"
copy /Y kubernetes\*.yaml "!WORK_DIR!\" >nul
if !ERRORLEVEL! neq 0 (
  echo Failed to copy manifests
  exit /b 1
)

powershell -NoProfile -Command "$f='!WORK_DIR!\deployment.yaml'; (Get-Content $f -Raw).Replace('{{IMAGE_URI}}',$env:IMAGE_URI).Replace('{{WEATHER_API_KEY}}',$env:WEATHER_API_KEY).Replace('{{SERVER_NAME}}',$env:SERVER_NAME) | Set-Content -NoNewline $f"
if !ERRORLEVEL! neq 0 (
  echo Failed to update manifests
  exit /b 1
)

echo Configuring kubectl...
aws eks update-kubeconfig --region !AWS_REGION! --name !CLUSTER_NAME!
if !ERRORLEVEL! neq 0 (
  echo Failed to configure kubectl
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
  echo ERROR: rollout failed.
  echo Rollback with: kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
  echo Inspect with: kubectl describe pods -n !NAMESPACE!
  exit /b 1
)

kubectl get pods,svc,ingress -n !NAMESPACE!

echo Ingress address (may be empty for a few minutes):
kubectl get ingress !APP_NAME!-ingress -n !NAMESPACE! -o jsonpath="{.status.loadBalancer.ingress[0].hostname}"
echo.
echo Requires AWS Load Balancer Controller installed in the cluster.

rmdir /S /Q "!WORK_DIR!"
endlocal
