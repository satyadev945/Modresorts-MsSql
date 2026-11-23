@echo off
setlocal enabledelayedexpansion
REM Deploy TestComp1 to AWS EKS. Run from the repository root: scripts\deploy-image.bat

set "APP_NAME=testcomp1"
set "NAMESPACE=testcomp1"

if not exist kubernetes (
  echo ERROR: kubernetes directory not found. Run this script from the repository root.
  exit /b 1
)

where aws >nul 2>&1
if !ERRORLEVEL! neq 0 (
  echo ERROR: aws CLI is required.
  exit /b 1
)
where kubectl >nul 2>&1
if !ERRORLEVEL! neq 0 (
  echo ERROR: kubectl is required.
  exit /b 1
)

echo === TestComp1 - Deploy to AWS EKS ===

set "AWS_REGION="
set "CLUSTER_NAME="
set "IMAGE_URI="
set /p AWS_REGION="AWS region (e.g. us-east-1): "
set /p CLUSTER_NAME="EKS cluster name: "
set /p IMAGE_URI="Docker image URI (registry/repo:tag): "
if "!AWS_REGION!"=="" goto missing
if "!CLUSTER_NAME!"=="" goto missing
if "!IMAGE_URI!"=="" goto missing
goto prompts

:missing
echo ERROR: AWS region, cluster name and image URI are required.
exit /b 1

:prompts
echo --- Application configuration, press Enter to skip ---
set "REDIS_HOST="
set "REDIS_PORT="
set "SERVER_DISPLAY_NAME="
set "WEATHER_API_KEY="
set "INGRESS_HOST="
set /p REDIS_HOST="Enter value for REDIS_HOST (or press Enter to skip): "
set /p REDIS_PORT="Enter value for REDIS_PORT (or press Enter for 6379): "
if "!REDIS_PORT!"=="" set "REDIS_PORT=6379"
set /p SERVER_DISPLAY_NAME="Enter value for SERVER_DISPLAY_NAME (or press Enter for !APP_NAME!): "
if "!SERVER_DISPLAY_NAME!"=="" set "SERVER_DISPLAY_NAME=!APP_NAME!"
set /p WEATHER_API_KEY="Enter value for WEATHER_API_KEY (or press Enter to skip): "
set /p INGRESS_HOST="Enter ingress host (or press Enter for !APP_NAME!.example.com): "
if "!INGRESS_HOST!"=="" set "INGRESS_HOST=!APP_NAME!.example.com"

REM Work on a temporary copy so repository manifests keep their placeholders
set "WORK_DIR=%TEMP%\testcomp1-k8s-%RANDOM%"
mkdir "!WORK_DIR!"
xcopy /E /I /Y /Q kubernetes "!WORK_DIR!\kubernetes" >nul
if !ERRORLEVEL! neq 0 (
  echo ERROR: could not copy manifests.
  exit /b 1
)

powershell -NoProfile -Command "$f=Join-Path $env:WORK_DIR 'kubernetes\deployment.yaml'; (Get-Content -Raw $f).Replace('{{IMAGE_URI}}',$env:IMAGE_URI).Replace('{{REDIS_HOST}}',$env:REDIS_HOST).Replace('{{REDIS_PORT}}',$env:REDIS_PORT).Replace('{{SERVER_DISPLAY_NAME}}',$env:SERVER_DISPLAY_NAME) | Set-Content -NoNewline $f"
if !ERRORLEVEL! neq 0 (
  echo ERROR: could not update deployment.yaml
  exit /b 1
)
powershell -NoProfile -Command "$f=Join-Path $env:WORK_DIR 'kubernetes\ingress.yaml'; (Get-Content -Raw $f).Replace('{{INGRESS_HOST}}',$env:INGRESS_HOST) | Set-Content -NoNewline $f"
if !ERRORLEVEL! neq 0 (
  echo ERROR: could not update ingress.yaml
  exit /b 1
)

echo Configuring kubectl for cluster !CLUSTER_NAME!...
aws eks update-kubeconfig --region !AWS_REGION! --name !CLUSTER_NAME!
if !ERRORLEVEL! neq 0 (
  echo ERROR: aws eks update-kubeconfig failed
  exit /b 1
)

echo Verifying cluster connectivity...
kubectl cluster-info
if !ERRORLEVEL! neq 0 (
  echo ERROR: cannot reach the cluster
  exit /b 1
)

echo Applying manifests...
kubectl apply -f "!WORK_DIR!\kubernetes\namespace.yaml"
if !ERRORLEVEL! neq 0 (
  echo ERROR: namespace apply failed
  exit /b 1
)

if not "!WEATHER_API_KEY!"=="" (
  kubectl create secret generic testcomp1-weather-secret --namespace !NAMESPACE! --from-literal=WEATHER_API_KEY=!WEATHER_API_KEY! --dry-run=client -o yaml > "!WORK_DIR!\secret.yaml"
  kubectl apply -f "!WORK_DIR!\secret.yaml"
  if !ERRORLEVEL! neq 0 (
    echo ERROR: secret apply failed
    exit /b 1
  )
)

kubectl apply -f "!WORK_DIR!\kubernetes\deployment.yaml"
if !ERRORLEVEL! neq 0 (
  echo ERROR: deployment apply failed
  exit /b 1
)
kubectl apply -f "!WORK_DIR!\kubernetes\service.yaml"
if !ERRORLEVEL! neq 0 (
  echo ERROR: service apply failed
  exit /b 1
)
kubectl apply -f "!WORK_DIR!\kubernetes\ingress.yaml"
if !ERRORLEVEL! neq 0 (
  echo ERROR: ingress apply failed
  exit /b 1
)

echo Waiting for rollout...
kubectl rollout status deployment/!APP_NAME! -n !NAMESPACE! --timeout=300s
if !ERRORLEVEL! neq 0 (
  echo ERROR: rollout failed
  echo Inspect:  kubectl describe pods -n !NAMESPACE!
  echo Rollback: kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
  exit /b 1
)

kubectl get pods,svc,ingress -n !NAMESPACE!

echo Load balancer address - may take a minute to appear:
kubectl get ingress !APP_NAME!-ingress -n !NAMESPACE! -o jsonpath="{.status.loadBalancer.ingress[0].hostname}"
echo.
echo Health check path: /health
echo Rollback if needed: kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!

rmdir /S /Q "!WORK_DIR!" >nul 2>&1
endlocal
