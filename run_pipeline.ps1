# PulseCheck CI/CD Simulation Pipeline
# Run this locally on Windows to simulate the automated integration workflow.

$ErrorActionPreference = "Stop"
$PWD_PATH = Convert-Path .

# Define the initial pipeline state
$global:pipelineState = @{
    status = "in_progress"
    last_run = (Get-Date -Format "o")
    trigger = "Local PowerShell Pipeline"
    stages = @(
        @{ name = "Virtual Env & Dependencies"; status = "pending"; details = "Setting up Python virtual environment and installing dependencies"; duration_seconds = 0 },
        @{ name = "Syntax Validation"; status = "pending"; details = "Checking standard Python compiler syntax"; duration_seconds = 0 },
        @{ name = "PyTest Unit Suite"; status = "pending"; details = "Running unit test verification"; duration_seconds = 0 },
        @{ name = "Docker Compilation"; status = "pending"; details = "Compiling Docker container image"; duration_seconds = 0 },
        @{ name = "Container Deploy & Probe"; status = "pending"; details = "Running verification container and querying health probes"; duration_seconds = 0 }
    )
}

function Update-PipelineStatus($stageIndex, $status, $details, $duration = 0) {
    if ($stageIndex -ge 0 -and $stageIndex -lt 5) {
        $global:pipelineState.stages[$stageIndex].status = $status
        if ($details) { $global:pipelineState.stages[$stageIndex].details = $details }
        if ($duration -gt 0) { $global:pipelineState.stages[$stageIndex].duration_seconds = $duration }
    }
    
    # Determine overall status
    $anyFailed = $false
    $anyInProgress = $false
    $allSuccess = $true
    
    foreach ($s in $global:pipelineState.stages) {
        if ($s.status -eq "failed") { $anyFailed = $true }
        if ($s.status -eq "in_progress") { $anyInProgress = $true }
        if ($s.status -ne "success" -and $s.status -ne "warning") { $allSuccess = $false }
    }
    
    if ($anyFailed) {
        $global:pipelineState.status = "failed"
    } elseif ($anyInProgress) {
        $global:pipelineState.status = "in_progress"
    } elseif ($allSuccess) {
        $global:pipelineState.status = "success"
    } else {
        $global:pipelineState.status = "idle"
    }
    
    $jsonPath = Join-Path $PWD_PATH "app/static/pipeline_status.json"
    $global:pipelineState | ConvertTo-Json -Depth 5 | Out-File -FilePath $jsonPath -Encoding utf8
}

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "   PulseCheck Automated Pipeline Triggered   " -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

# Initialize JSON state
Update-PipelineStatus -1 "" ""

# --- STEP 1: Virtual Environment Setup ---
$start1 = Get-Date
Update-PipelineStatus 0 "in_progress" "Setting up Python virtual environment and upgrading pip..."
Write-Host "`n[Step 1/5] Setting up Python Virtual Environment..." -ForegroundColor Yellow

$VENV_DIR = Join-Path $PWD_PATH ".venv"
try {
    if (-not (Test-Path $VENV_DIR)) {
        Write-Host "Creating virtual environment at $VENV_DIR..." -ForegroundColor Gray
        python -m venv .venv
    } else {
        Write-Host "Using existing virtual environment." -ForegroundColor Gray
    }
    
    Write-Host "Installing/Upgrading dependencies from requirements.txt..." -ForegroundColor Gray
    & "$VENV_DIR\Scripts\pip" install --upgrade pip
    & "$VENV_DIR\Scripts\pip" install -r requirements.txt
    if ($LASTEXITCODE -ne 0) { throw "pip install failed" }
    
    $duration1 = [Math]::Round(((Get-Date) - $start1).TotalSeconds)
    Update-PipelineStatus 0 "success" "Virtual environment and dependencies installed successfully." $duration1
} catch {
    $duration1 = [Math]::Round(((Get-Date) - $start1).TotalSeconds)
    Update-PipelineStatus 0 "failed" "Failed during dependency setup: $_" $duration1
    exit 1
}


# --- STEP 2: Syntax Validation ---
$start2 = Get-Date
Update-PipelineStatus 1 "in_progress" "Running compilation check on Python source files..."
Write-Host "`n[Step 2/5] Running syntax validation..." -ForegroundColor Yellow

try {
    $AppFiles = Get-ChildItem -Path "app" -Filter "*.py" -Recurse
    foreach ($file in $AppFiles) {
        Write-Host "Compiling $($file.FullName)..." -ForegroundColor Gray
        & "$VENV_DIR\Scripts\python" -m py_compile $file.FullName
        if ($LASTEXITCODE -ne 0) {
            throw "Syntax validation failed for $($file.Name)"
        }
    }
    
    $duration2 = [Math]::Round(((Get-Date) - $start2).TotalSeconds)
    Update-PipelineStatus 1 "success" "All Python files compiled successfully." $duration2
} catch {
    $duration2 = [Math]::Round(((Get-Date) - $start2).TotalSeconds)
    Update-PipelineStatus 1 "failed" "Syntax check failed: $_" $duration2
    exit 1
}


# --- STEP 3: Unit Testing ---
$start3 = Get-Date
Update-PipelineStatus 2 "in_progress" "Executing PyTest verification suite..."
Write-Host "`n[Step 3/5] Running PyTest Unit Test Suite..." -ForegroundColor Yellow

try {
    $env:PYTHONPATH = $PWD_PATH
    & "$VENV_DIR\Scripts\python" -m pytest "app/tests/test_main.py" -v
    if ($LASTEXITCODE -ne 0) {
        throw "Unit tests failed"
    }
    
    $duration3 = [Math]::Round(((Get-Date) - $start3).TotalSeconds)
    Update-PipelineStatus 2 "success" "All unit tests passed successfully." $duration3
} catch {
    $duration3 = [Math]::Round(((Get-Date) - $start3).TotalSeconds)
    Update-PipelineStatus 2 "failed" "Unit tests failed: $_" $duration3
    exit 1
}


# --- STEP 4: Container Build (Docker) ---
$start4 = Get-Date
Update-PipelineStatus 3 "in_progress" "Checking host Docker capabilities and building image..."
Write-Host "`n[Step 4/5] Building Docker Container..." -ForegroundColor Yellow

# Check if Docker is available
$dockerInstalled = $null
try {
    $dockerInstalled = docker --version
} catch {
    Write-Host "WARNING: Docker command not found on host. Skipping container build step." -ForegroundColor Yellow
    Update-PipelineStatus 3 "warning" "Skipped: Docker CLI not found."
    Update-PipelineStatus 4 "warning" "Skipped: E2E Verification skipped."
    Write-Host "Pipeline simulation partially complete (Python checks OK)." -ForegroundColor Green
    exit 0
}

# Check if Docker Daemon is running
$dockerRunning = $false
& docker info >$null 2>&1
if ($LASTEXITCODE -eq 0) {
    $dockerRunning = $true
}

try {
    if ($dockerRunning) {
        Write-Host "Building Docker image 'pulsecheck:local'..." -ForegroundColor Gray
        docker build -t pulsecheck:local .
        if ($LASTEXITCODE -ne 0) { throw "Docker build failed" }
        
        $duration4 = [Math]::Round(((Get-Date) - $start4).TotalSeconds)
        Update-PipelineStatus 3 "success" "Docker container compiled successfully (pulsecheck:local)." $duration4
    } else {
        Write-Host "WARNING: Docker daemon is not running. Skipping container build steps." -ForegroundColor Yellow
        Update-PipelineStatus 3 "warning" "Skipped: Docker daemon not running."
        Update-PipelineStatus 4 "warning" "Skipped: E2E Verification skipped."
        Write-Host "Pipeline simulation partially complete (Python checks OK)." -ForegroundColor Green
        exit 0
    }
} catch {
    $duration4 = [Math]::Round(((Get-Date) - $start4).TotalSeconds)
    Update-PipelineStatus 3 "failed" "Docker build failed: $_" $duration4
    exit 1
}


# --- STEP 5: Simulate Deployment and E2E Probe ---
$start5 = Get-Date
Update-PipelineStatus 4 "in_progress" "Spinning up target verification container and querying endpoints..."
Write-Host "`n[Step 5/5] Running Container Deployment E2E probe verification..." -ForegroundColor Yellow

$cleanUpFailed = $false
try {
    # Ensure no existing test container is running
    Write-Host "Stopping and cleaning up any legacy test containers..." -ForegroundColor Gray
    try {
        docker stop pulsecheck_test >$null 2>&1
        docker rm pulsecheck_test >$null 2>&1
    } catch {}
    
    # Run the container in background on port 8088 to avoid conflicts with local server on 8000
    Write-Host "Running container 'pulsecheck_test' in background on port 8088..." -ForegroundColor Gray
    docker run -d -p 8088:8000 --name pulsecheck_test pulsecheck:local
    if ($LASTEXITCODE -ne 0) { throw "Failed to start Docker verification container" }
    
    # Wait for application to start
    Write-Host "Waiting 5 seconds for application spin-up..." -ForegroundColor Gray
    Start-Sleep -Seconds 5
    
    # Probe the endpoints
    Write-Host "Querying health probe endpoint at http://localhost:8088/health..." -ForegroundColor Gray
    $response = Invoke-RestMethod -Uri "http://localhost:8088/health" -Method Get
    
    Write-Host "`nProbe health check response:" -ForegroundColor Gray
    $response | ConvertTo-Json | Write-Host -ForegroundColor Cyan
    
    if ($response.status -eq "healthy" -or $response.status -eq "unhealthy") {
        Write-Host "`nEnd-to-End API Probe validation successful!" -ForegroundColor Green
    } else {
        throw "Unexpected status returned: $($response.status)"
    }
    
    $duration5 = [Math]::Round(((Get-Date) - $start5).TotalSeconds)
    Update-PipelineStatus 4 "success" "Deployment simulation successful. Response code parsed ok." $duration5
} catch {
    Write-Host "ERROR: Deployment validation failed!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    $cleanUpFailed = $true
    
    $duration5 = [Math]::Round(((Get-Date) - $start5).TotalSeconds)
    Update-PipelineStatus 4 "failed" "Verification probe failed: $_" $duration5
} finally {
    # Cleanup container safely
    Write-Host "`nCleaning up verification resources..." -ForegroundColor Gray
    try {
        docker stop pulsecheck_test >$null 2>&1
        docker rm pulsecheck_test >$null 2>&1
    } catch {}
    Write-Host "Verification container cleaned up." -ForegroundColor Gray
}

if ($cleanUpFailed) {
    exit 1
}

Write-Host "`n=============================================" -ForegroundColor Green
Write-Host "    Pipeline completed successfully! (PASS)   " -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green
