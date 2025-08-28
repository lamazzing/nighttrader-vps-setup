# NightTrader Service Verification Script
# Checks the health and status of all NightTrader components

param(
    [switch]$Verbose,
    [switch]$FixIssues
)

$ErrorActionPreference = "Continue"

function Write-Status {
    param(
        [string]$Component,
        [string]$Status,
        [string]$Details = ""
    )
    
    $symbol = switch($Status) {
        "OK" { "✓"; $color = "Green" }
        "WARNING" { "⚠"; $color = "Yellow" }
        "ERROR" { "✗"; $color = "Red" }
        "INFO" { "ℹ"; $color = "Cyan" }
        default { "?"; $color = "Gray" }
    }
    
    Write-Host "[$symbol] $Component" -ForegroundColor $color -NoNewline
    if ($Details) {
        Write-Host " - $Details" -ForegroundColor $color
    } else {
        Write-Host ""
    }
}

function Test-Port {
    param(
        [string]$Host,
        [int]$Port,
        [int]$Timeout = 2
    )
    
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $connect = $tcpClient.BeginConnect($Host, $Port, $null, $null)
        $wait = $connect.AsyncWaitHandle.WaitOne($Timeout * 1000, $false)
        
        if ($wait) {
            $tcpClient.EndConnect($connect)
            $tcpClient.Close()
            return $true
        } else {
            return $false
        }
    } catch {
        return $false
    }
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "NightTrader Service Health Check" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

$issues = @()
$warnings = @()

# 1. Check Python Installation
Write-Host "Core Dependencies:" -ForegroundColor White
Write-Host "------------------" -ForegroundColor Gray

$pythonVersion = & python --version 2>&1
if ($pythonVersion -match "Python 3") {
    Write-Status "Python" "OK" $pythonVersion
} else {
    Write-Status "Python" "ERROR" "Not installed or not in PATH"
    $issues += "Python not found"
}

# 2. Check Git Installation
$gitVersion = & git --version 2>&1
if ($gitVersion -match "git version") {
    Write-Status "Git" "OK" $gitVersion
} else {
    Write-Status "Git" "ERROR" "Not installed or not in PATH"
    $issues += "Git not found"
}

# 3. Check PsExec
if (Test-Path "C:\Windows\System32\psexec.exe" -or Test-Path "C:\Windows\psexec.exe") {
    Write-Status "PsExec" "OK" "Installed for session management"
} else {
    Write-Status "PsExec" "WARNING" "Not found - service may not run in correct session"
    $warnings += "PsExec not installed"
}

Write-Host ""
Write-Host "Services Status:" -ForegroundColor White
Write-Host "----------------" -ForegroundColor Gray

# 4. Check SSH Service
$sshService = Get-Service sshd -ErrorAction SilentlyContinue
if ($sshService) {
    if ($sshService.Status -eq "Running") {
        Write-Status "SSH Service" "OK" "Running"
    } else {
        Write-Status "SSH Service" "WARNING" "Installed but not running (Status: $($sshService.Status))"
        $warnings += "SSH service not running"
        
        if ($FixIssues) {
            Write-Host "  Attempting to start SSH service..." -ForegroundColor Yellow
            Start-Service sshd -ErrorAction SilentlyContinue
        }
    }
} else {
    Write-Status "SSH Service" "ERROR" "Not installed"
    $issues += "SSH service not installed"
}

# 5. Check MT5 Terminal
$mt5Process = Get-Process terminal64 -ErrorAction SilentlyContinue
if ($mt5Process) {
    $sessionId = $mt5Process[0].SessionId
    Write-Status "MT5 Terminal" "OK" "Running in session $sessionId (PID: $($mt5Process[0].Id))"
    $mt5SessionId = $sessionId
} else {
    Write-Status "MT5 Terminal" "ERROR" "Not running"
    $issues += "MT5 Terminal not running"
    $mt5SessionId = $null
    
    if ($FixIssues) {
        Write-Host "  Attempting to start MT5 Terminal..." -ForegroundColor Yellow
        $mt5Path = "C:\Program Files\MetaTrader 5\terminal64.exe"
        if (Test-Path $mt5Path) {
            Start-Process $mt5Path
            Write-Host "  MT5 Terminal started" -ForegroundColor Green
        } else {
            Write-Host "  MT5 Terminal not found at expected location" -ForegroundColor Red
        }
    }
}

# 6. Check NightTrader Service
$pythonProcesses = Get-Process python -ErrorAction SilentlyContinue
$serviceProcess = $null

foreach ($proc in $pythonProcesses) {
    try {
        $cmdLine = (Get-WmiObject Win32_Process -Filter "ProcessId = $($proc.Id)").CommandLine
        if ($cmdLine -like "*service.py*") {
            $serviceProcess = $proc
            break
        }
    } catch {
        continue
    }
}

if ($serviceProcess) {
    $serviceSessionId = $serviceProcess.SessionId
    Write-Status "NightTrader Service" "OK" "Running in session $serviceSessionId (PID: $($serviceProcess.Id))"
    
    # Check if in same session as MT5
    if ($mt5SessionId -and $serviceSessionId -eq $mt5SessionId) {
        Write-Status "Session Match" "OK" "Service and MT5 in same session"
    } elseif ($mt5SessionId) {
        Write-Status "Session Match" "WARNING" "Service and MT5 in different sessions (may cause issues)"
        $warnings += "Session mismatch between service and MT5"
        
        if ($FixIssues) {
            Write-Host "  Attempting to restart service in correct session..." -ForegroundColor Yellow
            Stop-Process $serviceProcess -Force
            Start-Sleep -Seconds 2
            
            $pythonPath = "C:\Python313\python.exe"
            if (-not (Test-Path $pythonPath)) {
                $pythonPath = (Get-Command python).Path
            }
            $servicePath = "C:\NightTrader\service\mt5-service\service.py"
            
            & psexec -accepteula -i $mt5SessionId -d "$pythonPath" "$servicePath" 2>&1 | Out-Null
            Write-Host "  Service restarted in MT5 session" -ForegroundColor Green
        }
    }
} else {
    Write-Status "NightTrader Service" "ERROR" "Not running"
    $issues += "NightTrader service not running"
    
    if ($FixIssues -and $mt5SessionId) {
        Write-Host "  Attempting to start service..." -ForegroundColor Yellow
        
        $pythonPath = "C:\Python313\python.exe"
        if (-not (Test-Path $pythonPath)) {
            $pythonPath = (Get-Command python -ErrorAction SilentlyContinue).Path
            if (-not $pythonPath) {
                $pythonPath = "python"
            }
        }
        
        $servicePath = "C:\NightTrader\service\mt5-service\service.py"
        
        if (Test-Path $servicePath) {
            & psexec -accepteula -i $mt5SessionId -d "$pythonPath" "$servicePath" 2>&1 | Out-Null
            Write-Host "  Service started" -ForegroundColor Green
        } else {
            Write-Host "  Service file not found at $servicePath" -ForegroundColor Red
        }
    }
}

# 7. Check Scheduled Task
$task = Get-ScheduledTask -TaskName "NightTrader_MT5_Service" -ErrorAction SilentlyContinue
if ($task) {
    Write-Status "Scheduled Task" "OK" "Configured (Status: $($task.State))"
} else {
    Write-Status "Scheduled Task" "WARNING" "Not configured (backup startup method)"
    $warnings += "Scheduled task not configured"
}

Write-Host ""
Write-Host "Network Connectivity:" -ForegroundColor White
Write-Host "---------------------" -ForegroundColor Gray

# 8. Check Redis connectivity
$redisHost = if ($env:DIGITALOCEAN_IP) { $env:DIGITALOCEAN_IP } else { "138.197.3.109" }
if (Test-Port -Host $redisHost -Port 6379) {
    Write-Status "Redis" "OK" "Reachable at ${redisHost}:6379"
} else {
    Write-Status "Redis" "ERROR" "Cannot connect to ${redisHost}:6379"
    $issues += "Redis connection failed"
}

# 9. Check RabbitMQ connectivity
if (Test-Port -Host $redisHost -Port 5672) {
    Write-Status "RabbitMQ" "OK" "Reachable at ${redisHost}:5672"
} else {
    Write-Status "RabbitMQ" "ERROR" "Cannot connect to ${redisHost}:5672"
    $issues += "RabbitMQ connection failed"
}

Write-Host ""
Write-Host "File System:" -ForegroundColor White
Write-Host "------------" -ForegroundColor Gray

# 10. Check directory structure
$requiredDirs = @(
    "C:\NightTrader",
    "C:\NightTrader\service",
    "C:\NightTrader\service\mt5-service",
    "C:\NightTrader\logs"
)

$allDirsExist = $true
foreach ($dir in $requiredDirs) {
    if (-not (Test-Path $dir)) {
        $allDirsExist = $false
        break
    }
}

if ($allDirsExist) {
    Write-Status "Directory Structure" "OK" "All required directories exist"
} else {
    Write-Status "Directory Structure" "ERROR" "Missing required directories"
    $issues += "Directory structure incomplete"
    
    if ($FixIssues) {
        Write-Host "  Creating missing directories..." -ForegroundColor Yellow
        foreach ($dir in $requiredDirs) {
            if (-not (Test-Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
        }
        Write-Host "  Directories created" -ForegroundColor Green
    }
}

# 11. Check service files
$serviceFiles = @(
    "C:\NightTrader\service\mt5-service\service.py",
    "C:\NightTrader\service\mt5-service\config.py",
    "C:\NightTrader\service\mt5-service\.env"
)

$allFilesExist = $true
$missingFiles = @()
foreach ($file in $serviceFiles) {
    if (-not (Test-Path $file)) {
        $allFilesExist = $false
        $missingFiles += [System.IO.Path]::GetFileName($file)
    }
}

if ($allFilesExist) {
    Write-Status "Service Files" "OK" "All required files present"
} else {
    Write-Status "Service Files" "ERROR" "Missing files: $($missingFiles -join ', ')"
    $issues += "Service files missing"
}

# 12. Check Python packages
if ($pythonVersion) {
    Write-Host ""
    Write-Host "Python Packages:" -ForegroundColor White
    Write-Host "----------------" -ForegroundColor Gray
    
    $packages = & python -m pip list 2>&1 | Out-String
    
    $requiredPackages = @("MetaTrader5", "redis", "pika", "python-dotenv")
    $missingPackages = @()
    
    foreach ($pkg in $requiredPackages) {
        if ($packages -match $pkg) {
            Write-Status $pkg "OK" "Installed"
        } else {
            Write-Status $pkg "ERROR" "Not installed"
            $missingPackages += $pkg
        }
    }
    
    if ($missingPackages.Count -gt 0) {
        $issues += "Python packages missing: $($missingPackages -join ', ')"
        
        if ($FixIssues) {
            Write-Host "  Installing missing packages..." -ForegroundColor Yellow
            Set-Location "C:\NightTrader\service\mt5-service"
            & python -m pip install $missingPackages
            Write-Host "  Packages installed" -ForegroundColor Green
        }
    }
}

# 13. Check logs
Write-Host ""
Write-Host "Service Logs:" -ForegroundColor White
Write-Host "-------------" -ForegroundColor Gray

$logPath = "C:\NightTrader\logs\mt5_service.log"
if (Test-Path $logPath) {
    $logSize = (Get-Item $logPath).Length / 1MB
    $lastWrite = (Get-Item $logPath).LastWriteTime
    $timeSinceWrite = (Get-Date) - $lastWrite
    
    Write-Status "Log File" "OK" "Size: $([math]::Round($logSize, 2))MB, Last updated: $([math]::Round($timeSinceWrite.TotalMinutes, 0)) minutes ago"
    
    if ($Verbose) {
        Write-Host ""
        Write-Host "Recent log entries:" -ForegroundColor Gray
        Get-Content $logPath -Tail 10 | ForEach-Object {
            if ($_ -match "ERROR") {
                Write-Host "  $_" -ForegroundColor Red
            } elseif ($_ -match "WARNING") {
                Write-Host "  $_" -ForegroundColor Yellow
            } elseif ($_ -match "connected|ready|success") {
                Write-Host "  $_" -ForegroundColor Green
            } else {
                Write-Host "  $_" -ForegroundColor Gray
            }
        }
    }
    
    # Check for recent errors
    $recentLogs = Get-Content $logPath -Tail 50
    $errorCount = ($recentLogs | Select-String "ERROR").Count
    $warningCount = ($recentLogs | Select-String "WARNING").Count
    
    if ($errorCount -gt 0) {
        Write-Status "Recent Errors" "WARNING" "$errorCount errors in last 50 log lines"
        $warnings += "Recent errors in log"
    }
    
    if ($warningCount -gt 5) {
        Write-Status "Recent Warnings" "WARNING" "$warningCount warnings in last 50 log lines"
    }
} else {
    Write-Status "Log File" "WARNING" "Not found"
    $warnings += "Log file not found"
}

# Summary
Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

if ($issues.Count -eq 0 -and $warnings.Count -eq 0) {
    Write-Host "✓ All systems operational!" -ForegroundColor Green
    Write-Host ""
    exit 0
} else {
    if ($issues.Count -gt 0) {
        Write-Host ""
        Write-Host "Critical Issues ($($issues.Count)):" -ForegroundColor Red
        $issues | ForEach-Object { Write-Host "  ✗ $_" -ForegroundColor Red }
    }
    
    if ($warnings.Count -gt 0) {
        Write-Host ""
        Write-Host "Warnings ($($warnings.Count)):" -ForegroundColor Yellow
        $warnings | ForEach-Object { Write-Host "  ⚠ $_" -ForegroundColor Yellow }
    }
    
    Write-Host ""
    
    if ($FixIssues) {
        Write-Host "Attempted to fix issues. Re-run to verify." -ForegroundColor Cyan
    } else {
        Write-Host "Run with -FixIssues to attempt automatic fixes" -ForegroundColor Cyan
    }
    
    Write-Host ""
    
    if ($issues.Count -gt 0) {
        exit 1
    } else {
        exit 0
    }
}