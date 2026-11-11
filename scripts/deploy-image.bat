@echo off
setlocal enabledelayedexpansion
REM Deploy ModResorts to AWS EKS. Run from the repository root.

set "APP_NAME=modresorts"
set "NAMESPACE=modresorts"

echo === ModResorts deployment to AWS EKS ===
set /p AWS_REGION="Enter AWS region (e.g. us-east-1): "
set /p CLUSTER_NAME="Enter EKS cluster name: "
set /p IMAGE_URI="Enter Docker image URI (registry/repo:tag): "
if "!AWS_REGION!"=="" (
  echo AWS region is required
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
set "WEATHER_SERVICE_URL="
set "WEATHER_API_KEY="
set /p WEATHER_SERVICE_URL="Enter value for WEATHER_SERVICE_URL (or press Enter to skip): "
set /p WEATHER_API_KEY="Enter value for WEATHER_API_KEY (or press Enter to skip): "

where aws >nul 2>&1
if !ERRORLEVEL! neq 0 (
  echo aws cli is required
  exit /b 1
)
where kubectl >nul 2>&1
if !ERRORLEVEL! neq 0 (
  echo kubectl is required
  exit /b 1
)

set "WORK_DIR=%TEMP%\modresorts-k8s-%RANDOM%"
mkdir "!WORK_DIR!"
copy /y kubernetes\*.yaml "!WORK_DIR!\" >nul

set "DEPLOY_FILE=!WORK_DIR!\deployment.yaml"
set "PS_IMAGE_URI=!IMAGE_URI!"
set "PS_WEATHER_URL=!WEATHER_SERVICE_URL!"
set "PS_WEATHER_KEY=!WEATHER_API_KEY!"
set "PS_FILE=!DEPLOY_FILE!"
powershell -NoProfile -Command "$c=Get-Content -Raw $env:PS_FILE; $c=$c.Replace('{{IMAGE_URI}}',$env:PS_IMAGE_URI).Replace('{{WEATHER_SERVICE_URL}}',$env:PS_WEATHER_URL).Replace('{{WEATHER_API_KEY}}',$env:PS_WEATHER_KEY); Set-Content -NoNewline -Path $env:PS_FILE -Value $c"
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
  echo Cannot reach cluster
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
  echo Rollout failed. To roll back run:
  echo   kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
  exit /b 1
)

kubectl get pods,svc,ingress -n !NAMESPACE!

for /f "delims=" %%h in ('kubectl get ingress !APP_NAME!-ingress -n !NAMESPACE! -o jsonpath^="{.status.loadBalancer.ingress[0].hostname}"') do set "INGRESS_HOST=%%h"
if defined INGRESS_HOST (
  echo Application URL: http://!INGRESS_HOST!
) else (
  echo Ingress address not yet assigned. Check: kubectl get ingress -n !NAMESPACE!
)
echo Rollback if needed: kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
rmdir /s /q "!WORK_DIR!"
endlocal
