@echo off
setlocal enabledelayedexpansion

set "APP_NAME=modresorts"
set "NAMESPACE=modresorts"
set "SRC_K8S_DIR=%~dp0..\kubernetes"

set /p AWS_REGION="AWS region [us-east-1]: "
if "!AWS_REGION!"=="" set "AWS_REGION=us-east-1"
set /p CLUSTER_NAME="EKS cluster name: "
if "!CLUSTER_NAME!"=="" (
  echo EKS cluster name is required
  exit /b 1
)
set /p IMAGE_URI="Docker image URI (registry/repo:tag): "
if "!IMAGE_URI!"=="" (
  echo Image URI is required
  exit /b 1
)
set /p INGRESS_HOST="Ingress host [modresorts.example.com]: "
if "!INGRESS_HOST!"=="" set "INGRESS_HOST=modresorts.example.com"

set /p WEATHER_API_KEY="Enter value for WEATHER_API_KEY (or press Enter to skip): "
set /p WEATHER_SERVICE_URL="Enter value for WEATHER_SERVICE_URL (or press Enter to skip): "
set /p SERVER_DISPLAY_NAME="Enter value for SERVER_DISPLAY_NAME (or press Enter to skip): "
set /p JNDI_INITIAL_CONTEXT_FACTORY="Enter value for JNDI_INITIAL_CONTEXT_FACTORY (or press Enter to skip): "
set /p JNDI_PROVIDER_URL="Enter value for JNDI_PROVIDER_URL (or press Enter to skip): "

set "K8S_DIR=%TEMP%\modresorts-k8s-%RANDOM%"
mkdir "!K8S_DIR!"
copy /y "!SRC_K8S_DIR!\*.yaml" "!K8S_DIR!\" >nul
if !ERRORLEVEL! neq 0 (
  echo Failed to copy manifests
  exit /b 1
)

powershell -NoProfile -Command "Get-ChildItem -Path $env:K8S_DIR -Filter *.yaml | ForEach-Object { $c = Get-Content -Raw $_.FullName; $c = $c.Replace('{{IMAGE_URI}}', $env:IMAGE_URI).Replace('{{NAMESPACE}}', $env:NAMESPACE).Replace('{{INGRESS_HOST}}', $env:INGRESS_HOST).Replace('{{WEATHER_API_KEY}}', $env:WEATHER_API_KEY).Replace('{{WEATHER_SERVICE_URL}}', $env:WEATHER_SERVICE_URL).Replace('{{SERVER_DISPLAY_NAME}}', $env:SERVER_DISPLAY_NAME).Replace('{{JNDI_INITIAL_CONTEXT_FACTORY}}', $env:JNDI_INITIAL_CONTEXT_FACTORY).Replace('{{JNDI_PROVIDER_URL}}', $env:JNDI_PROVIDER_URL); [System.IO.File]::WriteAllText($_.FullName, $c) }"
if !ERRORLEVEL! neq 0 (
  echo Failed to update manifests
  exit /b 1
)

echo Configuring kubectl for cluster !CLUSTER_NAME! ...
aws eks update-kubeconfig --region !AWS_REGION! --name !CLUSTER_NAME!
if !ERRORLEVEL! neq 0 (
  echo Failed to configure kubectl
  exit /b 1
)

echo Verifying cluster connectivity ...
kubectl cluster-info
if !ERRORLEVEL! neq 0 (
  echo Cannot reach the cluster
  exit /b 1
)

echo Applying manifests ...
kubectl apply -f "!K8S_DIR!\namespace.yaml"
if !ERRORLEVEL! neq 0 exit /b 1
kubectl apply -f "!K8S_DIR!\deployment.yaml"
if !ERRORLEVEL! neq 0 exit /b 1
kubectl apply -f "!K8S_DIR!\service.yaml"
if !ERRORLEVEL! neq 0 exit /b 1
kubectl apply -f "!K8S_DIR!\ingress.yaml"
if !ERRORLEVEL! neq 0 exit /b 1

echo Waiting for rollout ...
kubectl rollout status deployment/!APP_NAME! -n !NAMESPACE! --timeout=300s
if !ERRORLEVEL! neq 0 (
  echo Rollout failed. To roll back run:
  echo   kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
  exit /b 1
)

kubectl get pods,svc,ingress -n !NAMESPACE!

echo Ingress address:
kubectl get ingress !APP_NAME!-ingress -n !NAMESPACE! -o jsonpath="{.status.loadBalancer.ingress[0].hostname}"
echo.
rmdir /s /q "!K8S_DIR!"
endlocal
