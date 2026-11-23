@echo off & setlocal enabledelayedexpansion
REM Deploy ModResorts to AWS EKS. Run from the repository root.

set "APP_NAME=modresorts"
set "NAMESPACE=modresorts"
set "WORK_DIR=%TEMP%\modresorts-k8s"

where aws >nul 2>&1
if !ERRORLEVEL! neq 0 (
  echo ERROR - aws CLI is not installed
  exit /b 1
)
where kubectl >nul 2>&1
if !ERRORLEVEL! neq 0 (
  echo ERROR - kubectl is not installed
  exit /b 1
)

set /p AWS_REGION="AWS region (e.g. us-east-1): "
set /p CLUSTER_NAME="EKS cluster name: "
set /p IMAGE_URI="Docker image URI (registry/repo:tag): "
if "!AWS_REGION!"=="" (
  echo ERROR - AWS region is required
  exit /b 1
)
if "!CLUSTER_NAME!"=="" (
  echo ERROR - cluster name is required
  exit /b 1
)
if "!IMAGE_URI!"=="" (
  echo ERROR - image URI is required
  exit /b 1
)

set "WEATHER_API_KEY="
set "JNDI_INITIAL_CONTEXT_FACTORY="
set "JNDI_PROVIDER_URL="
set "SERVER_NAME="
set /p WEATHER_API_KEY="Enter value for WEATHER_API_KEY (or press Enter to skip): "
set /p JNDI_INITIAL_CONTEXT_FACTORY="Enter value for JNDI_INITIAL_CONTEXT_FACTORY (or press Enter to skip): "
set /p JNDI_PROVIDER_URL="Enter value for JNDI_PROVIDER_URL (or press Enter to skip): "
set /p SERVER_NAME="Enter value for SERVER_NAME (or press Enter for modresorts): "
if "!SERVER_NAME!"=="" set "SERVER_NAME=!APP_NAME!"

REM Work on a temporary copy so the template manifests remain untouched
if exist "!WORK_DIR!" rmdir /s /q "!WORK_DIR!"
mkdir "!WORK_DIR!"
copy /y kubernetes\*.yaml "!WORK_DIR!\" >nul
if !ERRORLEVEL! neq 0 (
  echo ERROR - could not copy manifests. Run this script from the repository root.
  exit /b 1
)

powershell -NoProfile -Command "Get-ChildItem '!WORK_DIR!\*.yaml' | ForEach-Object { $c = Get-Content $_.FullName -Raw; $c = $c.Replace('{{IMAGE_URI}}', $env:IMAGE_URI).Replace('{{NAMESPACE}}', $env:NAMESPACE).Replace('{{WEATHER_API_KEY}}', $env:WEATHER_API_KEY).Replace('{{JNDI_INITIAL_CONTEXT_FACTORY}}', $env:JNDI_INITIAL_CONTEXT_FACTORY).Replace('{{JNDI_PROVIDER_URL}}', $env:JNDI_PROVIDER_URL).Replace('{{SERVER_NAME}}', $env:SERVER_NAME); Set-Content -Path $_.FullName -Value $c -NoNewline }"
if !ERRORLEVEL! neq 0 (
  echo ERROR - placeholder replacement failed
  exit /b 1
)

echo Configuring kubectl for cluster !CLUSTER_NAME!...
aws eks update-kubeconfig --region !AWS_REGION! --name !CLUSTER_NAME!
if !ERRORLEVEL! neq 0 (
  echo ERROR - failed to update kubeconfig
  exit /b 1
)

echo Verifying cluster connectivity...
kubectl cluster-info
if !ERRORLEVEL! neq 0 (
  echo ERROR - cannot reach cluster
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
  echo ERROR - rollout failed. Roll back with:
  echo   kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
  exit /b 1
)

kubectl get pods,svc,ingress -n !NAMESPACE!
echo.
echo Application URL - run: kubectl get ingress !APP_NAME!-ingress -n !NAMESPACE!
echo Rollback if needed: kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
rmdir /s /q "!WORK_DIR!" >nul 2>&1
endlocal
