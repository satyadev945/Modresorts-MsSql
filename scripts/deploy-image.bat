@echo off
setlocal enabledelayedexpansion

REM Deploy TestComp1 to AWS EKS. Run from the repository root.
set "APP_NAME=testcomp1"
set "NAMESPACE=testcomp1"
set "MANIFEST_DIR=kubernetes"
set "WORK_DIR=%TEMP%\testcomp1-manifests"

if not exist "!MANIFEST_DIR!" (
  echo ERROR: kubernetes directory not found. Run this script from the repository root.
  exit /b 1
)

where aws >nul 2>&1
if !ERRORLEVEL! neq 0 (
  echo ERROR: aws CLI is not installed or not in PATH.
  exit /b 1
)
where kubectl >nul 2>&1
if !ERRORLEVEL! neq 0 (
  echo ERROR: kubectl is not installed or not in PATH.
  exit /b 1
)

set /p AWS_REGION="Enter AWS region, for example us-east-1: "
set /p CLUSTER_NAME="Enter EKS cluster name: "
set /p IMAGE_URI="Enter Docker image URI, registry/repo:tag: "

if "!AWS_REGION!"=="" (
  echo ERROR: AWS region is required.
  exit /b 1
)
if "!CLUSTER_NAME!"=="" (
  echo ERROR: Cluster name is required.
  exit /b 1
)
if "!IMAGE_URI!"=="" (
  echo ERROR: Image URI is required.
  exit /b 1
)

echo Optional application settings, press Enter to skip
set "WEATHER_API_KEY="
set "WEATHER_SERVICE_URL="
set /p WEATHER_API_KEY="Enter value for WEATHER_API_KEY or press Enter to skip: "
set /p WEATHER_SERVICE_URL="Enter value for WEATHER_SERVICE_URL or press Enter to skip: "

REM Render manifests into a temp directory
if exist "!WORK_DIR!" rmdir /s /q "!WORK_DIR!"
mkdir "!WORK_DIR!"
copy /y "!MANIFEST_DIR!\*.yaml" "!WORK_DIR!\" >nul

set "ENV_IMAGE_URI=!IMAGE_URI!"
set "ENV_NAMESPACE=!NAMESPACE!"
set "ENV_WEATHER_API_KEY=!WEATHER_API_KEY!"
set "ENV_WEATHER_SERVICE_URL=!WEATHER_SERVICE_URL!"
powershell -NoProfile -Command "Get-ChildItem -Path $env:WORK_DIR -Filter *.yaml | ForEach-Object { $c = [System.IO.File]::ReadAllText($_.FullName); $c = $c.Replace('{{IMAGE_URI}}', $env:ENV_IMAGE_URI).Replace('{{NAMESPACE}}', $env:ENV_NAMESPACE).Replace('{{WEATHER_API_KEY}}', $env:ENV_WEATHER_API_KEY).Replace('{{WEATHER_SERVICE_URL}}', $env:ENV_WEATHER_SERVICE_URL); [System.IO.File]::WriteAllText($_.FullName, $c, (New-Object System.Text.UTF8Encoding $false)) }"
if !ERRORLEVEL! neq 0 (
  echo ERROR: Failed to render manifests.
  exit /b 1
)

echo Configuring kubectl for cluster !CLUSTER_NAME!...
aws eks update-kubeconfig --region !AWS_REGION! --name !CLUSTER_NAME!
if !ERRORLEVEL! neq 0 (
  echo ERROR: Failed to configure kubectl.
  exit /b 1
)

echo Verifying cluster connectivity...
kubectl cluster-info
if !ERRORLEVEL! neq 0 (
  echo ERROR: Cannot reach the cluster.
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
  echo ERROR: Rollout failed. To roll back run:
  echo   kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
  exit /b 1
)

kubectl get pods,svc,ingress -n !NAMESPACE!

echo Application URL: run the following to get the load balancer address
echo   kubectl get ingress !APP_NAME!-ingress -n !NAMESPACE!
echo Rollback instructions: kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!

rmdir /s /q "!WORK_DIR!" >nul 2>&1
endlocal
