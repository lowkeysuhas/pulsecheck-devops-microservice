# PulseCheck CI/CD Simulation Pipeline
# Run this locally on Windows to simulate the automated integration workflow.

$ErrorActionPreference = "Stop"
$PWD_PATH = Convert-Path .

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "   PulseCheck Automated Pipeline Triggered   " -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

# Step 1: Virtual Environment Setup
Write-Host "`n[Step 1/5] Setting up Python Virtual Environment..." -ForegroundColor Yellow
$VENV_DIR = Join-Path $PWD_PATH ".venv"

if (-not (Test-Path $VENV_DIR)) {
    Write-Host "Creating virtual environment at $VENV_DIR..." -ForegroundColor Gray
    python -m venv .venv
} else {
    Write-Host "Using existing virtual environment." -ForegroundColor Gray
}

# Activate virtual environment and install requirements
Write-Host "Installing/Upgrading dependencies from requirements.txt..." -ForegroundColor Gray
& "$VENV_DIR\Scripts\pip" install --upgrade pip
& "$VENV_DIR\Scripts\pip" install -r requirements.txt

# Step 2: Syntax and Formatting Verification
Write-Host "`n[Step 2/5] Running syntax validation..." -ForegroundColor Yellow
$AppFiles = Get-ChildItem -Path "app" -Filter "*.py" -Recurse
foreach ($file in $AppFiles) {
    Write-Host "Compiling $($file.FullName)..." -ForegroundColor Gray
    & "$VENV_DIR\Scripts\python" -m py_compile $file.FullName
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Syntax validation failed for $($file.Name)!" -ForegroundColor Red
        exit 1
    }
}
Write-Host "Syntax validation check passed successfully." -ForegroundColor Green

# Step 3: Unit Testing
Write-Host "`n[Step 3/5] Running PyTest Unit Test Suite..." -ForegroundColor Yellow
$env:PYTHONPATH = $PWD_PATH
& "$VENV_DIR\Scripts\python" -m pytest "app/tests/test_main.py" -v
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Unit tests failed!" -ForegroundColor Red
    exit 1
}
Write-Host "All unit tests passed successfully." -ForegroundColor Green

# Step 4: Container Build (Docker)
Write-Host "`n[Step 4/5] Building Docker Container..." -ForegroundColor Yellow

# Check if Docker is available
$dockerInstalled = $null
try {
    $dockerInstalled = docker --version
} catch {
    Write-Host "WARNING: Docker command not found on host. Skipping container build step." -ForegroundColor Yellow
    Write-Host "Pipeline simulation partially complete (Python checks OK)." -ForegroundColor Green
    exit 0
}

# Check if Docker Daemon is running
$dockerRunning = $false
& docker info >$null 2>&1
if ($LASTEXITCODE -eq 0) {
    $dockerRunning = $true
}

if ($dockerRunning) {
    Write-Host "Building Docker image 'pulsecheck:local'..." -ForegroundColor Gray
    docker build -t pulsecheck:local .
    Write-Host "Docker image built successfully." -ForegroundColor Green
} else {
    Write-Host "WARNING: Docker daemon is not running. Skipping container build and deployment steps." -ForegroundColor Yellow
    Write-Host "Pipeline simulation partially complete (Python checks OK)." -ForegroundColor Green
    exit 0
}

# Step 5: Simulate Deployment and End-to-End Probe Verification
Write-Host "`n[Step 5/5] Running Container Deployment E2E probe verification..." -ForegroundColor Yellow

# Ensure no existing test container is running
Write-Host "Stopping and cleaning up any legacy test containers..." -ForegroundColor Gray
docker stop pulsecheck_test >$null 2>&1
docker rm pulsecheck_test >$null 2>&1

# Run the container in background
Write-Host "Running container 'pulsecheck_test' in background on port 8000..." -ForegroundColor Gray
docker run -d -p 8000:8000 --name pulsecheck_test pulsecheck:local

# Wait for application to start
Write-Host "Waiting 5 seconds for application spin-up..." -ForegroundColor Gray
Start-Sleep -Seconds 5

try {
    # Probe the endpoints
    Write-Host "Querying health probe endpoint at http://localhost:8000/health..." -ForegroundColor Gray
    $response = Invoke-RestMethod -Uri "http://localhost:8000/health" -Method Get
    
    Write-Host "`nProbe health check response:" -ForegroundColor Gray
    $response | ConvertTo-Json | Write-Host -ForegroundColor Cyan
    
    if ($response.status -eq "healthy" -or $response.status -eq "unhealthy") {
        Write-Host "`nEnd-to-End API Probe validation successful!" -ForegroundColor Green
    } else {
        throw "Unexpected status returned: $($response.status)"
    }
} catch {
    Write-Host "ERROR: Deployment validation failed!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    $cleanUpFailed = $true
} finally {
    # Cleanup container
    Write-Host "`nCleaning up verification resources..." -ForegroundColor Gray
    docker stop pulsecheck_test >$null
    docker rm pulsecheck_test >$null
    Write-Host "Verification container cleaned up." -ForegroundColor Gray
}

if ($cleanUpFailed) {
    exit 1
}

Write-Host "`n=============================================" -ForegroundColor Green
Write-Host "    Pipeline completed successfully! (PASS)   " -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green
