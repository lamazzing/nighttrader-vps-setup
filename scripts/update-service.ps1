# PowerShell script to update the MT5 service with new reconnection logic
# Run this on the VPS to apply the updates

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "MT5 Service Update - v7 Auto-Reconnect" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$servicePath = "C:\NightTrader\service"

# Check if service directory exists
if (-not (Test-Path $servicePath)) {
    Write-Host "ERROR: Service directory not found at $servicePath" -ForegroundColor Red
    exit 1
}

Write-Host "`n[1/5] Pulling latest code from GitHub..." -ForegroundColor Yellow
Set-Location $servicePath
git pull origin main

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to pull from GitHub" -ForegroundColor Red
    exit 1
}

Write-Host "[2/5] Installing/updating Python dependencies..." -ForegroundColor Yellow
python -m pip install --upgrade pip
pip install --upgrade pika redis python-dotenv MetaTrader5

Write-Host "`n[3/5] Stopping existing MT5 service..." -ForegroundColor Yellow
# Try to stop the Python process gracefully
$pythonProcesses = Get-Process python* -ErrorAction SilentlyContinue | Where-Object {
    $_.CommandLine -like "*service.py*"
}

if ($pythonProcesses) {
    foreach ($proc in $pythonProcesses) {
        Write-Host "  Stopping process $($proc.Id)..." -ForegroundColor Gray
        Stop-Process -Id $proc.Id -Force
    }
    Start-Sleep -Seconds 2
}

Write-Host "[4/5] Starting updated MT5 service..." -ForegroundColor Yellow
$startScript = Join-Path $servicePath "scripts\startup-script.ps1"

if (Test-Path $startScript) {
    # Use the existing startup script
    & $startScript
} else {
    # Fallback: Start service directly
    $mt5ServicePath = Join-Path $servicePath "mt5-service"
    $envFile = Join-Path $mt5ServicePath ".env"
    
    if (-not (Test-Path $envFile)) {
        Write-Host "WARNING: .env file not found. Service may not start correctly." -ForegroundColor Yellow
    }
    
    # Find MT5 Terminal session
    $mt5Session = (Get-Process terminal64 -ErrorAction SilentlyContinue | Select-Object -First 1).SessionId
    if (-not $mt5Session) { $mt5Session = 1 }
    
    # Start with PsExec
    $psexecPath = "C:\tools\psexec64.exe"
    if (Test-Path $psexecPath) {
        Start-Process -FilePath $psexecPath -ArgumentList @(
            "-accepteula",
            "-i", $mt5Session,
            "-d",
            "python",
            "$mt5ServicePath\service.py"
        ) -WorkingDirectory $mt5ServicePath
    } else {
        # Fallback to direct start
        Start-Process python -ArgumentList "$mt5ServicePath\service.py" -WorkingDirectory $mt5ServicePath -WindowStyle Hidden
    }
}

Start-Sleep -Seconds 3

Write-Host "`n[5/5] Verifying service status..." -ForegroundColor Yellow
$newProcess = Get-Process python* -ErrorAction SilentlyContinue | Where-Object {
    $_.CommandLine -like "*service.py*"
}

if ($newProcess) {
    Write-Host "✓ Service is running (PID: $($newProcess.Id))" -ForegroundColor Green
    
    # Check the log file for startup messages
    $logFile = "C:\NightTrader\logs\mt5_service.log"
    if (Test-Path $logFile) {
        Write-Host "`nLatest log entries:" -ForegroundColor Cyan
        Get-Content $logFile -Tail 10 | ForEach-Object {
            if ($_ -match "ERROR") {
                Write-Host $_ -ForegroundColor Red
            } elseif ($_ -match "WARNING") {
                Write-Host $_ -ForegroundColor Yellow
            } elseif ($_ -match "Successfully|connected|started") {
                Write-Host $_ -ForegroundColor Green
            } else {
                Write-Host $_ -ForegroundColor Gray
            }
        }
    }
} else {
    Write-Host "✗ Service is not running" -ForegroundColor Red
    Write-Host "Check the log file at C:\NightTrader\logs\mt5_service.log for errors" -ForegroundColor Yellow
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Update Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "`nNew features in v7:" -ForegroundColor Cyan
Write-Host "  • Automatic reconnection on connection loss" -ForegroundColor Gray
Write-Host "  • Exponential backoff for retry attempts" -ForegroundColor Gray
Write-Host "  • Enhanced heartbeat configuration (60s)" -ForegroundColor Gray
Write-Host "  • TCP keepalive for better connection detection" -ForegroundColor Gray
Write-Host "  • Graceful shutdown handling" -ForegroundColor Gray
Write-Host "`nThe service will now automatically recover from:" -ForegroundColor Cyan
Write-Host "  • Network interruptions" -ForegroundColor Gray
Write-Host "  • RabbitMQ restarts" -ForegroundColor Gray
Write-Host "  • Temporary connection failures" -ForegroundColor Gray