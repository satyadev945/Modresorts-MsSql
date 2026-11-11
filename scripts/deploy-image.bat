@echo off
setlocal enabledelayedexpansion

rem Run from the repository root:  scripts\deploy-image.bat
set "APP_NAME=modresorts"
set "DEFAULT_NAMESPACE=modresorts"
set "DEFAULT_HOST=modresorts.example.com"

echo === ModResorts: deploy to AWS EKS ===

where aws >nul 2>&1
if !ERRORLEVEL! neq 0 (
  echo ERROR: aws CLI is not installed or not in PATH
  exit /b 1
)
where kubectl >nul 2>&1
if !ERRORLEVEL! neq 0 (
  echo ERROR: kubectl is not installed or not in PATH
  exit /b 1
)

set /p AWS_REGION="Enter AWS region, for example us-east-1: "
if "!AWS_REGION!"=="" (
  echo ERROR: AWS region is required
  exit /b 1
)
set /p CLUSTER_NAME="Enter EKS cluster name: "
if "!CLUSTER_NAME!"=="" (
  echo ERROR: EKS cluster name is required
  exit /b 1
)
set /p IMAGE_URI="Enter Docker image URI, registry/repo:tag: "
if "!IMAGE_URI!"=="" (
  echo ERROR: Image URI is required
  exit /b 1
)
set /p NAMESPACE="Enter Kubernetes namespace [!DEFAULT_NAMESPACE!]: "
if "!NAMESPACE!"=="" set "NAMESPACE=!DEFAULT_NAMESPACE!"
set /p INGRESS_HOST="Enter ingress host name [!DEFAULT_HOST!]: "
if "!INGRESS_HOST!"=="" set "INGRESS_HOST=!DEFAULT_HOST!"
set "WEATHER_API_KEY="
set /p WEATHER_API_KEY="Enter value for WEATHER_API_KEY or press Enter to skip: "

rem Work on a temporary copy so template manifests stay untouched
set "WORK_DIR=%TEMP%\modresorts_k8s_%RANDOM%"
mkdir "!WORK_DIR!"
copy /y kubernetes\*.yaml "!WORK_DIR!\" >nul
if !ERRORLEVEL! neq 0 (
  echo ERROR: could not copy kubernetes manifests. Run from the repository root.
  exit /b 1
)

call :subst IMAGE_URI IMAGE_URI
call :subst NAMESPACE NAMESPACE
call :subst INGRESS_HOST INGRESS_HOST
call :subst WEATHER_API_KEY WEATHER_API_KEY

echo ^>^>^> Configuring kubectl for cluster !CLUSTER_NAME!...
aws eks update-kubeconfig --region !AWS_REGION! --name !CLUSTER_NAME!
if !ERRORLEVEL! neq 0 (
  echo Failed to update kubeconfig
  exit /b 1
)

echo ^>^>^> Verifying cluster connectivity...
kubectl cluster-info
if !ERRORLEVEL! neq 0 (
  echo ERROR: cannot reach the cluster
  exit /b 1
)

echo ^>^>^> Applying manifests...
kubectl apply -f "!WORK_DIR!\namespace.yaml"
if !ERRORLEVEL! neq 0 exit /b 1
kubectl apply -f "!WORK_DIR!\deployment.yaml"
if !ERRORLEVEL! neq 0 exit /b 1
kubectl apply -f "!WORK_DIR!\service.yaml"
if !ERRORLEVEL! neq 0 exit /b 1
kubectl apply -f "!WORK_DIR!\ingress.yaml"
if !ERRORLEVEL! neq 0 exit /b 1

echo ^>^>^> Waiting for rollout...
kubectl rollout status deployment/!APP_NAME! -n !NAMESPACE! --timeout=300s
if !ERRORLEVEL! neq 0 (
  echo ERROR: rollout failed. To roll back run:
  echo   kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
  echo Inspect with: kubectl describe pods -n !NAMESPACE!
  exit /b 1
)

echo ^>^>^> Resources in namespace !NAMESPACE!:
kubectl get pods,svc,ingress -n !NAMESPACE!

echo Get the application address with:
echo   kubectl get ingress !APP_NAME!-ingress -n !NAMESPACE!
echo Use Host header !INGRESS_HOST! or map a DNS record to the ALB hostname.
echo Rollback if needed: kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!

rmdir /s /q "!WORK_DIR!" >nul 2>&1
endlocal
exit /b 0

:subst
rem %1 = placeholder name, %2 = environment variable holding the value
set "SUBST_DIR=!WORK_DIR!"
powershell -NoProfile -Command "Get-ChildItem -Path $env:SUBST_DIR -Filter *.yaml | ForEach-Object { $c=[IO.File]::ReadAllText($_.FullName); $v=[Environment]::GetEnvironmentVariable('%~2'); if($null -eq $v){$v=''}; $c=$c.Replace('{{%~1}}',$v); [IO.File]::WriteAllText($_.FullName,$c) }"
exit /b 0
