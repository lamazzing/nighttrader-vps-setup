# NightTrader Setup - Step 4: Start Service
# Starts the MT5 service using PsExec in the same session as MT5 Terminal

param(
    [string]$LogPath = "C:\NightTrader\logs\start-service.log"
)

$ErrorActionPreference = "Stop"

function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $LogPath -Append
    Write-Host $Message
}

try {
    Write-Log "==============================================="
    Write-Log "Starting NightTrader Service"
    Write-Log "==============================================="
    
    # Find Python executable
    Write-Log "Locating Python executable..."
    $pythonPath = "C:\Python313\python.exe"
    if (-not (Test-Path $pythonPath)) {
        # Try to find Python in PATH
        $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
        if ($pythonCmd) {
            $pythonPath = $pythonCmd.Path
        } else {
            $pythonPath = "python"
        }
    }
    Write-Log "Using Python: $pythonPath"
    
    # Service script path
    $servicePath = "C:\NightTrader\service\mt5-service\service.py"
    
    # Verify service file exists
    if (-not (Test-Path $servicePath)) {
        throw "Service file not found at: $servicePath"
    }
    
    # Ensure PsExec is available
    Write-Log ""
    Write-Log "Checking for PsExec..."
    $psexecPath = "C:\Windows\System32\psexec.exe"
    
    if (-not (Test-Path $psexecPath)) {
        Write-Log "PsExec not found, downloading..."
        try {
            Invoke-WebRequest -Uri "https://live.sysinternals.com/PsExec64.exe" -OutFile $psexecPath -UseBasicParsing
            & reg add "HKCU\Software\Sysinternals\PsExec" /v EulaAccepted /t REG_DWORD /d 1 /f 2>&1 | Out-Null
            Write-Log "PsExec downloaded and configured"
        } catch {
            Write-Log "Warning: Failed to download PsExec, will use scheduled task instead"
        }
    } else {
        Write-Log "PsExec found at: $psexecPath"
    }
    
    # Find MT5 Terminal session
    Write-Log ""
    Write-Log "Finding MT5 Terminal session..."
    $mt5Process = Get-Process terminal64 -ErrorAction SilentlyContinue
    
    $sessionId = 1  # Default to session 1
    if ($mt5Process) {
        $sessionId = $mt5Process[0].SessionId
        Write-Log "MT5 Terminal found in session $sessionId"
    } else {
        Write-Log "MT5 Terminal not found, will use default session 1"
    }
    
    # Kill any existing Python service processes
    Write-Log "Stopping any existing service processes..."
    $existingService = Get-Process python -ErrorAction SilentlyContinue | Where-Object {
        try {
            $_.Path -like "*python*"
        } catch {
            $false
        }
    }
    
    if ($existingService) {
        $existingService | Stop-Process -Force -ErrorAction SilentlyContinue
        Write-Log "Stopped $($existingService.Count) existing Python process(es)"
        Start-Sleep -Seconds 2
    }
    
    # Start service with PsExec if available
    if (Test-Path $psexecPath) {
        Write-Log ""
        Write-Log "Starting service in session $sessionId using PsExec..."
        
        $psexecCommand = "psexec -accepteula -i $sessionId -d `"$pythonPath`" `"$servicePath`""
        Write-Log "Executing: $psexecCommand"
        
        $psexecResult = & cmd /c $psexecCommand 2>&1 | Out-String
        Write-Log "PsExec output: $psexecResult"
        
        if ($psexecResult -match "started on|process ID") {
            Write-Log "Service started successfully with PsExec"
            
            # Wait for service to initialize
            Start-Sleep -Seconds 5
            
            # Verify service is running
            $verifyProcess = Get-Process python -ErrorAction SilentlyContinue | Where-Object {
                $_.SessionId -eq $sessionId
            }
            
            if ($verifyProcess) {
                Write-Log "✓ Service verified running in session $sessionId (PID: $($verifyProcess[0].Id))"
            } else {
                Write-Log "Warning: Could not verify service process"
            }
        } else {
            Write-Log "Warning: PsExec may have encountered issues"
        }
    }
    
    # Create scheduled task as backup/restart mechanism
    Write-Log ""
    Write-Log "Creating scheduled task for automatic restart..."
    
    # Remove existing task if it exists
    $taskName = "NightTrader_MT5_Service"
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Write-Log "Removing existing scheduled task..."
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }
    
    # Create new scheduled task
    Write-Log "Creating new scheduled task..."
    
    # Define task action
    $action = New-ScheduledTaskAction `
        -Execute $pythonPath `
        -Argument $servicePath `
        -WorkingDirectory "C:\NightTrader\service\mt5-service"
    
    # Define task trigger (at startup and every 5 minutes, with proper duration)
    $triggers = @(
        New-ScheduledTaskTrigger -AtStartup
        New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
            -RepetitionInterval (New-TimeSpan -Minutes 5) `
            -RepetitionDuration (New-TimeSpan -Days 365)  # 1 year instead of MaxValue
    )
    
    # Define task principal (run as SYSTEM with highest privileges)
    $principal = New-ScheduledTaskPrincipal `
        -UserId "SYSTEM" `
        -LogonType ServiceAccount `
        -RunLevel Highest
    
    # Define task settings
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -RestartInterval (New-TimeSpan -Minutes 1) `
        -RestartCount 3 `
        -ExecutionTimeLimit (New-TimeSpan -Hours 0)
    
    # Register the task
    $task = Register-ScheduledTask `
        -TaskName $taskName `
        -Action $action `
        -Trigger $triggers `
        -Principal $principal `
        -Settings $settings `
        -Force
    
    Write-Log "Scheduled task created successfully"
    
    # If PsExec wasn't available or didn't work, start via scheduled task
    if (-not (Test-Path $psexecPath)) {
        Write-Log "Starting service via scheduled task (PsExec not available)..."
        Start-ScheduledTask -TaskName $taskName
        Start-Sleep -Seconds 5
    }
    
    # Final verification
    Write-Log ""
    Write-Log "Performing final verification..."
    
    $pythonProcess = Get-Process python -ErrorAction SilentlyContinue
    if ($pythonProcess) {
        Write-Log "✓ Python process running (Count: $($pythonProcess.Count))"
        foreach ($proc in $pythonProcess) {
            Write-Log "  - PID: $($proc.Id), Session: $($proc.SessionId)"
        }
    } else {
        Write-Log "⚠ No Python process found, service may take time to start"
    }
    
    # Check if service can connect to infrastructure
    Write-Log ""
    Write-Log "Checking service log for connection status..."
    $serviceLog = "C:\NightTrader\logs\mt5_service.log"
    if (Test-Path $serviceLog) {
        $recentLogs = Get-Content $serviceLog -Tail 10
        Write-Log "Recent service logs:"
        $recentLogs | ForEach-Object { Write-Log "  $_" }
    }
    
    Write-Log ""
    Write-Log "==============================================="
    Write-Log "Service Start Complete!"
    Write-Log "==============================================="
    Write-Log ""
    Write-Log "IMPORTANT: The service is configured to:"
    Write-Log "  1. Run in the same session as MT5 Terminal (using PsExec)"
    Write-Log "  2. Auto-restart on failure (via scheduled task)"
    Write-Log "  3. Start automatically at system boot"
    Write-Log ""
    Write-Log "Check C:\NightTrader\logs\mt5_service.log for service status"
    
    # Save status
    @{
        Status = "Success"
        PsExecUsed = Test-Path $psexecPath
        SessionId = $sessionId
        ScheduledTask = $true
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    } | ConvertTo-Json | Out-File "C:\NightTrader\service-start-status.json"
    
    exit 0
    
} catch {
    Write-Log "ERROR: Service start failed"
    Write-Log $_.Exception.Message
    
    # Try fallback with scheduled task
    Write-Log "Attempting fallback start with scheduled task..."
    try {
        Start-ScheduledTask -TaskName "NightTrader_MT5_Service" -ErrorAction Stop
        Write-Log "Started via scheduled task (fallback)"
        exit 0
    } catch {
        Write-Log "Fallback also failed: $($_.Exception.Message)"
        exit 1
    }
}