@echo off
setlocal enabledelayedexpansion

set "APP_NAME=testcomp1"
set "NAMESPACE=testcomp1"
set "SCRIPT_DIR=%~dp0"
set "K8S_SRC=%SCRIPT_DIR%..\kubernetes"
set "WORK_DIR=%TEMP%\testcomp1-k8s-%RANDOM%"

echo === Deploy %APP_NAME% to AWS EKS ===

where aws >nul 2>&1
if !ERRORLEVEL! neq 0 (
  echo Error: aws CLI is not installed or not in PATH.
  exit /b 1
)
where kubectl >nul 2>&1
if !ERRORLEVEL! neq 0 (
  echo Error: kubectl is not installed or not in PATH.
  exit /b 1
)

set /p AWS_REGION="Enter AWS region (e.g. us-east-1): "
set /p CLUSTER_NAME="Enter EKS cluster name: "
set /p IMAGE_URI="Enter Docker image URI (registry/repo:tag): "

if "!AWS_REGION!"=="" (
  echo Error: AWS region is required.
  exit /b 1
)
if "!CLUSTER_NAME!"=="" (
  echo Error: cluster name is required.
  exit /b 1
)
if "!IMAGE_URI!"=="" (
  echo Error: image URI is required.
  exit /b 1
)

echo Enter application environment variables (press Enter to skip)
set "WEATHER_API_KEY="
set "SERVER_NAME="
set "JNDI_INITIAL_CONTEXT_FACTORY="
set "JNDI_PROVIDER_URL="
set /p WEATHER_API_KEY="Enter value for WEATHER_API_KEY (or press Enter to skip): "
set /p SERVER_NAME="Enter value for SERVER_NAME (or press Enter to skip): "
set /p JNDI_INITIAL_CONTEXT_FACTORY="Enter value for JNDI_INITIAL_CONTEXT_FACTORY (or press Enter for default): "
set /p JNDI_PROVIDER_URL="Enter value for JNDI_PROVIDER_URL (or press Enter to skip): "
if "!SERVER_NAME!"=="" set "SERVER_NAME=localhost"
if "!JNDI_INITIAL_CONTEXT_FACTORY!"=="" set "JNDI_INITIAL_CONTEXT_FACTORY=org.apache.naming.java.javaURLContextFactory"

rem Work on a temporary copy so the template manifests keep their placeholders
mkdir "!WORK_DIR!"
copy "!K8S_SRC!\*.yaml" "!WORK_DIR!\" >nul
if !ERRORLEVEL! neq 0 (
  echo Error: could not copy manifests.
  exit /b 1
)

set "P_IMAGE_URI=!IMAGE_URI!"
set "P_NAMESPACE=!NAMESPACE!"
set "P_WEATHER_API_KEY=!WEATHER_API_KEY!"
set "P_SERVER_NAME=!SERVER_NAME!"
set "P_JNDI_ICF=!JNDI_INITIAL_CONTEXT_FACTORY!"
set "P_JNDI_URL=!JNDI_PROVIDER_URL!"

powershell -NoProfile -Command "Get-ChildItem -Path $env:WORK_DIR -Filter *.yaml | ForEach-Object { $c = Get-Content -Raw $_.FullName; $c = $c.Replace('{{IMAGE_URI}}',$env:P_IMAGE_URI).Replace('{{NAMESPACE}}',$env:P_NAMESPACE).Replace('{{WEATHER_API_KEY}}',$env:P_WEATHER_API_KEY).Replace('{{SERVER_NAME}}',$env:P_SERVER_NAME).Replace('{{JNDI_INITIAL_CONTEXT_FACTORY}}',$env:P_JNDI_ICF).Replace('{{JNDI_PROVIDER_URL}}',$env:P_JNDI_URL); [System.IO.File]::WriteAllText($_.FullName, $c, (New-Object System.Text.UTF8Encoding($false))) }"
if !ERRORLEVEL! neq 0 (
  echo Error: failed to update manifests.
  exit /b 1
)

echo Configuring kubectl for cluster !CLUSTER_NAME!...
aws eks update-kubeconfig --region !AWS_REGION! --name !CLUSTER_NAME!
if !ERRORLEVEL! neq 0 (
  echo Error: failed to configure kubectl.
  exit /b 1
)

echo Verifying cluster connectivity...
kubectl cluster-info
if !ERRORLEVEL! neq 0 (
  echo Error: cannot reach the cluster.
  exit /b 1
)

echo Applying manifests...
kubectl apply -f "!WORK_DIR!\namespace.yaml"
if !ERRORLEVEL! neq 0 goto failed
kubectl apply -f "!WORK_DIR!\deployment.yaml"
if !ERRORLEVEL! neq 0 goto failed
kubectl apply -f "!WORK_DIR!\service.yaml"
if !ERRORLEVEL! neq 0 goto failed
kubectl apply -f "!WORK_DIR!\ingress.yaml"
if !ERRORLEVEL! neq 0 goto failed

echo Waiting for rollout...
kubectl rollout status deployment/!APP_NAME! -n !NAMESPACE! --timeout=300s
if !ERRORLEVEL! neq 0 (
  echo Rollout failed. To roll back run:
  echo   kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
  goto failed
)

echo Resources:
kubectl get pods,svc,ingress -n !NAMESPACE!

echo Ingress address - check with: kubectl get ingress !APP_NAME!-ingress -n !NAMESPACE!
echo Health endpoint: /health
rmdir /s /q "!WORK_DIR!" >nul 2>&1
exit /b 0

:failed
echo Deployment failed.
rmdir /s /q "!WORK_DIR!" >nul 2>&1
exit /b 1
