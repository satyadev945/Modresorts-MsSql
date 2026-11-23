@echo off
setlocal enabledelayedexpansion

set "APP_NAME=modresorts"
set "NAMESPACE=modresorts"
echo === Deploy %APP_NAME% to AWS EKS ===

where aws >nul 2>&1
if !ERRORLEVEL! neq 0 (
  echo ERROR: aws CLI is required
  exit /b 1
)
where kubectl >nul 2>&1
if !ERRORLEVEL! neq 0 (
  echo ERROR: kubectl is required
  exit /b 1
)
if not exist "kubernetes\deployment.yaml" (
  echo ERROR: run this script from the project root
  exit /b 1
)

set /p AWS_REGION="Enter AWS region (e.g. us-east-1): "
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

echo Optional application settings - press Enter to skip
set "WEATHER_SERVICE_URL="
set "WEATHER_API_KEY="
set "JNDI_INITIAL_CONTEXT_FACTORY="
set "JNDI_PROVIDER_URL="
set /p WEATHER_SERVICE_URL="Enter value for WEATHER_SERVICE_URL (or press Enter to skip): "
set /p WEATHER_API_KEY="Enter value for WEATHER_API_KEY (or press Enter to skip): "
set /p JNDI_INITIAL_CONTEXT_FACTORY="Enter value for JNDI_INITIAL_CONTEXT_FACTORY (or press Enter to skip): "
set /p JNDI_PROVIDER_URL="Enter value for JNDI_PROVIDER_URL (or press Enter to skip): "

set "WORK_DIR=%TEMP%\!APP_NAME!-k8s-%RANDOM%"
mkdir "!WORK_DIR!"
copy /y kubernetes\*.yaml "!WORK_DIR!\" >nul
if !ERRORLEVEL! neq 0 (
  echo ERROR: failed to copy manifests
  exit /b 1
)

echo Replacing placeholders...
set "PS_DIR=!WORK_DIR!"
powershell -NoProfile -Command "Get-ChildItem -Path $env:PS_DIR -Filter *.yaml | ForEach-Object { $c = Get-Content -Raw $_.FullName; $c = $c.Replace('{{IMAGE_URI}}', $env:IMAGE_URI).Replace('{{NAMESPACE}}', $env:NAMESPACE).Replace('{{WEATHER_SERVICE_URL}}', [string]$env:WEATHER_SERVICE_URL).Replace('{{WEATHER_API_KEY}}', [string]$env:WEATHER_API_KEY).Replace('{{JNDI_INITIAL_CONTEXT_FACTORY}}', [string]$env:JNDI_INITIAL_CONTEXT_FACTORY).Replace('{{JNDI_PROVIDER_URL}}', [string]$env:JNDI_PROVIDER_URL); [IO.File]::WriteAllText($_.FullName, $c, (New-Object Text.UTF8Encoding($false))) }"
if !ERRORLEVEL! neq 0 (
  echo ERROR: placeholder replacement failed
  exit /b 1
)

echo Configuring kubectl...
aws eks update-kubeconfig --region !AWS_REGION! --name !CLUSTER_NAME!
if !ERRORLEVEL! neq 0 (
  echo ERROR: update-kubeconfig failed
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
if !ERRORLEVEL! neq 0 goto failed
kubectl apply -f "!WORK_DIR!\deployment.yaml"
if !ERRORLEVEL! neq 0 goto failed
kubectl apply -f "!WORK_DIR!\service.yaml"
if !ERRORLEVEL! neq 0 goto failed
kubectl apply -f "!WORK_DIR!\ingress.yaml"
if !ERRORLEVEL! neq 0 goto failed

echo Waiting for rollout...
kubectl rollout status deployment/!APP_NAME! -n !NAMESPACE! --timeout=300s
if !ERRORLEVEL! neq 0 goto failed

kubectl get pods,svc,ingress -n !NAMESPACE!

echo.
echo Ingress address (ALB hostname may take a few minutes to appear):
kubectl get ingress modresorts-ingress -n !NAMESPACE! -o jsonpath="{.status.loadBalancer.ingress[0].hostname}"
echo.
echo Rollback instructions: kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
rmdir /s /q "!WORK_DIR!"
endlocal
exit /b 0

:failed
echo ERROR: deployment failed.
echo Rollback with: kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
if exist "!WORK_DIR!" rmdir /s /q "!WORK_DIR!"
exit /b 1
