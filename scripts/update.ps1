# NightTrader Service Update Script
# Updates the service from Git repository and restarts it

param(
    [switch]$Force,
    [switch]$NoRestart
)

$ErrorActionPreference = "Stop"

function Write-Log {
    param($Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch($Level) {
        "ERROR" { "Red" }
        "WARNING" { "Yellow" }
        "SUCCESS" { "Green" }
        default { "White" }
    }
    Write-Host "$timestamp [$Level] $Message" -ForegroundColor $color
}

try {
    Write-Log "========================================" "INFO"
    Write-Log "NightTrader Service Update Script" "INFO"
    Write-Log "========================================" "INFO"
    
    # Check if service directory exists
    $serviceDir = "C:\NightTrader\service"
    if (-not (Test-Path $serviceDir)) {
        Write-Log "Service directory not found at $serviceDir" "ERROR"
        exit 1
    }
    
    Set-Location $serviceDir
    
    # Check for uncommitted changes
    Write-Log "Checking for uncommitted changes..." "INFO"
    $gitStatus = & git status --porcelain 2>&1
    
    if ($gitStatus) {
        if ($Force) {
            Write-Log "Uncommitted changes detected, but -Force specified. Stashing changes..." "WARNING"
            & git stash push -m "Auto-stash before update $(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')"
        } else {
            Write-Log "Uncommitted changes detected:" "ERROR"
            $gitStatus | ForEach-Object { Write-Log "  $_" "ERROR" }
            Write-Log "Use -Force to stash changes and continue" "ERROR"
            exit 1
        }
    }
    
    # Get current branch and commit
    $currentBranch = & git rev-parse --abbrev-ref HEAD
    $currentCommit = & git rev-parse --short HEAD
    Write-Log "Current branch: $currentBranch" "INFO"
    Write-Log "Current commit: $currentCommit" "INFO"
    
    # Fetch latest changes
    Write-Log "Fetching latest changes from remote..." "INFO"
    & git fetch origin
    
    # Check if there are updates
    $localCommit = & git rev-parse HEAD
    $remoteCommit = & git rev-parse origin/$currentBranch
    
    if ($localCommit -eq $remoteCommit) {
        Write-Log "Already up to date!" "SUCCESS"
        
        if (-not $NoRestart) {
            Write-Log "Checking if service needs restart..." "INFO"
            
            # Check if service is running
            $serviceRunning = Get-Process python -ErrorAction SilentlyContinue | 
                Where-Object { 
                    try {
                        (Get-WmiObject Win32_Process -Filter "ProcessId = $($_.Id)").CommandLine -like "*service.py*"
                    } catch {
                        $false
                    }
                }
            
            if (-not $serviceRunning) {
                Write-Log "Service not running, attempting to start..." "WARNING"
                & powershell.exe -File "$PSScriptRoot\restart-service.ps1"
            } else {
                Write-Log "Service is running, no action needed" "SUCCESS"
            }
        }
        
        exit 0
    }
    
    # Pull latest changes
    Write-Log "Pulling latest changes..." "INFO"
    $pullResult = & git pull origin $currentBranch 2>&1 | Out-String
    Write-Log $pullResult "INFO"
    
    # Get new commit
    $newCommit = & git rev-parse --short HEAD
    Write-Log "Updated to commit: $newCommit" "SUCCESS"
    
    # Show what changed
    Write-Log "Changes in this update:" "INFO"
    $changes = & git log --oneline $currentCommit..$newCommit
    $changes | ForEach-Object { Write-Log "  $_" "INFO" }
    
    # Check if requirements.txt changed
    $requirementsChanged = & git diff $currentCommit $newCommit --name-only | Select-String "requirements.txt"
    
    if ($requirementsChanged) {
        Write-Log "requirements.txt changed, updating Python dependencies..." "INFO"
        Set-Location "$serviceDir\mt5-service"
        
        & python -m pip install --upgrade pip
        & python -m pip install -r requirements.txt --upgrade
        
        Write-Log "Python dependencies updated" "SUCCESS"
    }
    
    # Restart service unless specified otherwise
    if (-not $NoRestart) {
        Write-Log "Restarting NightTrader service..." "INFO"
        
        # Stop existing service processes
        Write-Log "Stopping existing service processes..." "INFO"
        Get-Process python -ErrorAction SilentlyContinue | 
            Where-Object { 
                try {
                    (Get-WmiObject Win32_Process -Filter "ProcessId = $($_.Id)").CommandLine -like "*service.py*"
                } catch {
                    $false
                }
            } | Stop-Process -Force
        
        Start-Sleep -Seconds 2
        
        # Find MT5 Terminal session
        $mt5Process = Get-Process terminal64 -ErrorAction SilentlyContinue
        
        if ($mt5Process) {
            $sessionId = $mt5Process[0].SessionId
            Write-Log "MT5 Terminal found in session $sessionId" "INFO"
            
            # Start service with PsExec in MT5 session
            $pythonPath = "C:\Python313\python.exe"
            if (-not (Test-Path $pythonPath)) {
                $pythonPath = (Get-Command python).Path
            }
            
            $servicePath = "C:\NightTrader\service\mt5-service\service.py"
            
            Write-Log "Starting service in session $sessionId..." "INFO"
            $psexecResult = & psexec -accepteula -i $sessionId -d "$pythonPath" "$servicePath" 2>&1 | Out-String
            
            if ($psexecResult -match "started on|process ID") {
                Write-Log "Service restarted successfully" "SUCCESS"
            } else {
                Write-Log "PsExec output: $psexecResult" "WARNING"
                
                # Try scheduled task as fallback
                Write-Log "Trying scheduled task restart..." "INFO"
                Stop-ScheduledTask -TaskName "NightTrader_MT5_Service" -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 1
                Start-ScheduledTask -TaskName "NightTrader_MT5_Service"
                Write-Log "Service restarted via scheduled task" "SUCCESS"
            }
        } else {
            Write-Log "MT5 Terminal not running, starting via scheduled task..." "WARNING"
            Start-ScheduledTask -TaskName "NightTrader_MT5_Service"
            Write-Log "Service started via scheduled task" "SUCCESS"
        }
        
        # Wait and verify
        Start-Sleep -Seconds 5
        
        $serviceRunning = Get-Process python -ErrorAction SilentlyContinue | 
            Where-Object { 
                try {
                    (Get-WmiObject Win32_Process -Filter "ProcessId = $($_.Id)").CommandLine -like "*service.py*"
                } catch {
                    $false
                }
            }
        
        if ($serviceRunning) {
            Write-Log "Service is running" "SUCCESS"
            
            # Check recent logs
            $logPath = "C:\NightTrader\logs\mt5_service.log"
            if (Test-Path $logPath) {
                Write-Log "Recent service logs:" "INFO"
                Get-Content $logPath -Tail 5 | ForEach-Object {
                    if ($_ -match "ERROR") {
                        Write-Log "  $_" "ERROR"
                    } elseif ($_ -match "connected|ready") {
                        Write-Log "  $_" "SUCCESS"
                    } else {
                        Write-Log "  $_" "INFO"
                    }
                }
            }
        } else {
            Write-Log "Service may not have started properly, check logs" "WARNING"
        }
    } else {
        Write-Log "Skipping service restart (-NoRestart specified)" "INFO"
    }
    
    Write-Log "========================================" "INFO"
    Write-Log "Update completed successfully!" "SUCCESS"
    Write-Log "========================================" "INFO"
    
} catch {
    Write-Log "Update failed: $_" "ERROR"
    Write-Log $_.Exception.Message "ERROR"
    exit 1
}