# NightTrader Setup - Step 4: Start Service
# Starts the MT5 service using scheduled task (simplified approach)

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
        throw "Service file not found: $servicePath"
    }
    
    # Create scheduled task for service
    Write-Log ""
    Write-Log "Creating scheduled task for NightTrader service..."
    
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
    
    # Define task trigger (at startup and every 5 minutes)
    $triggers = @(
        New-ScheduledTaskTrigger -AtStartup
        New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration ([TimeSpan]::MaxValue)
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
    
    # Start the task immediately
    Write-Log "Starting the service task..."
    Start-ScheduledTask -TaskName $taskName
    
    # Wait a moment for the task to start
    Start-Sleep -Seconds 5
    
    # Check task status
    $taskInfo = Get-ScheduledTaskInfo -TaskName $taskName
    Write-Log "Task last run time: $($taskInfo.LastRunTime)"
    Write-Log "Task last result: $($taskInfo.LastTaskResult)"
    
    # Check if Python process is running
    Start-Sleep -Seconds 5
    $pythonProcess = Get-Process python -ErrorAction SilentlyContinue | 
        Where-Object { $_.Path -like "*python*" }
    
    if ($pythonProcess) {
        Write-Log "Python service process detected (PID: $($pythonProcess[0].Id))"
    } else {
        Write-Log "Warning: Python process not detected yet (may still be starting)"
    }
    
    Write-Log ""
    Write-Log "==============================================="
    Write-Log "NightTrader Service Start Complete!"
    Write-Log "==============================================="
    Write-Log ""
    Write-Log "The service is configured to:"
    Write-Log "- Start automatically at system boot"
    Write-Log "- Restart every 5 minutes if not running"
    Write-Log "- Retry 3 times if it fails"
    
    # Save status for next script
    @{
        Status = "Success"
        TaskCreated = $true
        TaskName = $taskName
        ServiceRunning = [bool]$pythonProcess
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    } | ConvertTo-Json | Out-File "C:\NightTrader\start-status.json"
    
    exit 0
    
} catch {
    Write-Log "ERROR: Service start failed"
    Write-Log $_.Exception.Message
    exit 1
}