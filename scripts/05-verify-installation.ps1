# NightTrader Setup - Step 5: Verify Installation
# Simple verification of all components (no deep nesting)

param(
    [string]$LogPath = "C:\NightTrader\logs\verify-installation.log"
)

$ErrorActionPreference = "Continue"  # Continue even if checks fail

function Write-Log {
    param($Message, [switch]$Success, [switch]$Warning, [switch]$Error)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - $Message"
    $logMessage | Out-File -FilePath $LogPath -Append
    
    # Color output based on status
    if ($Success) {
        Write-Host $Message -ForegroundColor Green
    } elseif ($Warning) {
        Write-Host $Message -ForegroundColor Yellow
    } elseif ($Error) {
        Write-Host $Message -ForegroundColor Red
    } else {
        Write-Host $Message
    }
}

# Initialize results
$results = @{
    Python = $false
    Git = $false
    SSH = $false
    MT5 = $false
    Service = $false
    Repository = $false
    Configuration = $false
    ScheduledTask = $false
}

Write-Log "==============================================="
Write-Log "NightTrader Installation Verification"
Write-Log "==============================================="
Write-Log ""

# 1. Check Python
Write-Log "Checking Python installation..."
try {
    $pythonVersion = & python --version 2>&1
    if ($pythonVersion) {
        Write-Log "✓ Python installed: $pythonVersion" -Success
        $results.Python = $true
    }
} catch {
    Write-Log "✗ Python not found" -Error
}

# 2. Check Git
Write-Log "Checking Git installation..."
try {
    $gitVersion = & git --version 2>&1
    if ($gitVersion) {
        Write-Log "✓ Git installed: $gitVersion" -Success
        $results.Git = $true
    }
} catch {
    Write-Log "✗ Git not found" -Error
}

# 3. Check SSH Service
Write-Log "Checking SSH service..."
$sshService = Get-Service sshd -ErrorAction SilentlyContinue
if ($sshService) {
    Write-Log "✓ SSH Service: $($sshService.Status)" -Success
    $results.SSH = $true
} else {
    Write-Log "⚠ SSH Service not found (optional)" -Warning
}

# 4. Check MT5 Installation
Write-Log "Checking MT5 Terminal..."
$mt5Path = "C:\Program Files\MetaTrader 5\terminal64.exe"
if (Test-Path $mt5Path) {
    Write-Log "✓ MT5 Terminal installed" -Success
    $results.MT5 = $true
    
    # Check if running
    $mt5Process = Get-Process terminal64 -ErrorAction SilentlyContinue
    if ($mt5Process) {
        Write-Log "  └─ MT5 is running (PID: $($mt5Process[0].Id))" -Success
    } else {
        Write-Log "  └─ MT5 is not currently running" -Warning
    }
} else {
    Write-Log "✗ MT5 Terminal not found" -Error
}

# 5. Check Repository
Write-Log "Checking service repository..."
if (Test-Path "C:\NightTrader\service") {
    Write-Log "✓ Repository cloned" -Success
    $results.Repository = $true
    
    # Check service file
    $serviceFile = "C:\NightTrader\service\mt5-service\service.py"
    if (Test-Path $serviceFile) {
        Write-Log "  └─ Service file exists" -Success
        $results.Service = $true
    } else {
        Write-Log "  └─ Service file missing" -Error
    }
} else {
    Write-Log "✗ Repository not found" -Error
}

# 6. Check Configuration
Write-Log "Checking configuration..."
$envFile = "C:\NightTrader\service\mt5-service\.env"
if (Test-Path $envFile) {
    Write-Log "✓ Configuration file exists" -Success
    $results.Configuration = $true
} else {
    Write-Log "✗ Configuration file missing" -Error
}

# 7. Check Scheduled Task
Write-Log "Checking scheduled task..."
$taskName = "NightTrader_MT5_Service"
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($task) {
    Write-Log "✓ Scheduled task exists" -Success
    $results.ScheduledTask = $true
    
    # Check task status
    $taskInfo = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction SilentlyContinue
    if ($taskInfo) {
        Write-Log "  └─ Last run: $($taskInfo.LastRunTime)" -Success
        if ($taskInfo.LastTaskResult -eq 0) {
            Write-Log "  └─ Last result: Success" -Success
        }
        else {
            Write-Log "  └─ Last result: $($taskInfo.LastTaskResult)" -Warning
        }
    }
}
else {
    Write-Log "✗ Scheduled task not found" -Error
}

# 8. Check Service Process
Write-Log "Checking service process..."
$pythonProcess = Get-Process python -ErrorAction SilentlyContinue | 
    Where-Object { 
        try {
            $_.Path -like "*python*"
        } catch {
            $false
        }
    }

if ($pythonProcess) {
    Write-Log "✓ Python service process running (PID: $($pythonProcess[0].Id))" -Success
} else {
    Write-Log "⚠ Python service process not detected" -Warning
}

# 9. Check Service Log
Write-Log "Checking service logs..."
$serviceLog = "C:\NightTrader\logs\mt5_service.log"
if (Test-Path $serviceLog) {
    Write-Log "✓ Service log file exists" -Success
    
    # Show last few lines
    $lastLines = Get-Content $serviceLog -Tail 5 -ErrorAction SilentlyContinue
    if ($lastLines) {
        Write-Log "  Recent log entries:"
        foreach ($line in $lastLines) {
            Write-Log "    $line"
        }
    }
} else {
    Write-Log "⚠ Service log not found (service may not have started yet)" -Warning
}

# Summary
Write-Log ""
Write-Log "==============================================="
Write-Log "Verification Summary"
Write-Log "==============================================="

$successCount = ($results.Values | Where-Object { $_ -eq $true }).Count
$totalCount = $results.Count

Write-Log "Components verified: $successCount/$totalCount"
Write-Log ""

foreach ($component in $results.Keys) {
    if ($results[$component]) {
        Write-Log "  ✓ $component" -Success
    } else {
        Write-Log "  ✗ $component" -Error
    }
}

# Save verification results
$verificationResults = @{
    Results = $results
    SuccessCount = $successCount
    TotalCount = $totalCount
    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Success = ($successCount -ge 6)  # Consider successful if at least 6/8 components are OK
}

$verificationResults | ConvertTo-Json | Out-File "C:\NightTrader\verification-results.json"

if ($verificationResults.Success) {
    Write-Log ""
    Write-Log "✓ NightTrader installation verified successfully!" -Success
    exit 0
} else {
    Write-Log ""
    Write-Log "⚠ Some components are missing or not configured" -Warning
    exit 1
}