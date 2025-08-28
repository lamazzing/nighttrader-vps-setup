# NightTrader Setup - Step 3: Setup Service
# Clones repository, installs dependencies, creates configuration

param(
    [string]$LogPath = "C:\NightTrader\logs\setup-service.log"
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
    Write-Log "Starting NightTrader Service Setup"
    Write-Log "==============================================="
    
    # Change to NightTrader directory
    Set-Location "C:\NightTrader"
    
    # Clean up any existing service directory
    if (Test-Path "C:\NightTrader\service") {
        Write-Log "Found existing service directory, removing it..."
        try {
            Remove-Item -Path "C:\NightTrader\service" -Recurse -Force -ErrorAction Stop
            Write-Log "Existing service directory removed"
        } catch {
            Write-Log "Warning: Could not remove existing service directory: $_"
            # Try to rename it instead
            $backupName = "service_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
            try {
                Rename-Item -Path "C:\NightTrader\service" -NewName $backupName -Force
                Write-Log "Renamed existing service directory to $backupName"
            } catch {
                Write-Log "ERROR: Cannot remove or rename existing service directory"
                throw "Service directory exists and cannot be cleaned up"
            }
        }
    }
    
    # Clone service repository
    Write-Log "Cloning NightTrader service repository..."
    $repoUrl = if ($env:MT5_SERVICE_REPO) { 
        $env:MT5_SERVICE_REPO 
    } else { 
        "https://github.com/lamazzing/nighttrader-vps-setup.git" 
    }
    
    Write-Log "Repository URL: $repoUrl"
    
    # Refresh PATH to ensure Git is available
    $gitPath = "C:\Program Files\Git\cmd"
    if (Test-Path $gitPath) {
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        Write-Log "PATH refreshed to include Git"
    }
    
    # Try to use git with full path first, then fall back to git command
    $gitExe = "C:\Program Files\Git\cmd\git.exe"
    if (Test-Path $gitExe) {
        Write-Log "Using Git at: $gitExe"
        $cloneOutput = & $gitExe clone $repoUrl service 2>&1
    } else {
        Write-Log "Using git from PATH"
        $cloneOutput = & git clone $repoUrl service 2>&1
    }
    Write-Log "Git output: $cloneOutput"
    
    # Verify clone was successful by checking for actual files
    if ((Test-Path "C:\NightTrader\service\mt5-service\service.py") -or 
        (Test-Path "C:\NightTrader\service\mt5-service")) {
        Write-Log "Repository cloned successfully"
    } else {
        # Sometimes git clone output doesn't indicate failure properly
        # Check if directory exists but is empty
        if (Test-Path "C:\NightTrader\service") {
            $files = Get-ChildItem "C:\NightTrader\service" -Recurse -File
            if ($files.Count -gt 0) {
                Write-Log "Repository cloned successfully (found $($files.Count) files)"
            } else {
                throw "Repository directory exists but is empty"
            }
        } else {
            throw "Failed to clone repository - directory not created"
        }
    }
    
    # Wait a moment for filesystem to settle
    Start-Sleep -Seconds 2
    
    # List what we actually have
    Write-Log "Contents of C:\NightTrader\service:"
    $serviceContents = Get-ChildItem "C:\NightTrader\service" -Name
    foreach ($item in $serviceContents) {
        Write-Log "  - $item"
    }
    
    # Change to service directory
    $mt5ServicePath = "C:\NightTrader\service\mt5-service"
    if (Test-Path $mt5ServicePath) {
        Set-Location $mt5ServicePath
        Write-Log "Changed to mt5-service directory"
    } else {
        Write-Log "ERROR: mt5-service directory not found at: $mt5ServicePath"
        Write-Log "Available directories:"
        Get-ChildItem "C:\NightTrader\service" -Directory | ForEach-Object {
            Write-Log "  - $($_.FullName)"
        }
        throw "mt5-service directory not found"
    }
    
    # Ensure Python is in PATH
    Write-Log ""
    Write-Log "Checking Python availability..."
    $pythonPath = Get-Command python -ErrorAction SilentlyContinue
    if (-not $pythonPath) {
        Write-Log "Python not found in PATH, searching common locations..."
        $pythonLocations = @(
            "C:\Python313\python.exe",
            "C:\Python312\python.exe", 
            "C:\Python311\python.exe",
            "C:\Python310\python.exe",
            "$env:LOCALAPPDATA\Programs\Python\Python313\python.exe",
            "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe"
        )
        
        $foundPython = $false
        foreach ($location in $pythonLocations) {
            if (Test-Path $location) {
                Write-Log "Found Python at: $location"
                # Add to PATH for this session
                $pythonDir = Split-Path $location -Parent
                $env:Path = "$pythonDir;$env:Path"
                $foundPython = $true
                break
            }
        }
        
        if (-not $foundPython) {
            throw "Python not found! Please ensure Python is installed."
        }
    } else {
        Write-Log "Python found at: $($pythonPath.Source)"
    }
    
    # Verify Python works
    $pythonVersion = & python --version 2>&1
    Write-Log "Python version: $pythonVersion"
    
    # Upgrade pip
    Write-Log ""
    Write-Log "Upgrading pip..."
    $pipOutput = & python -m pip install --upgrade pip 2>&1
    Write-Log "Pip upgrade complete"
    
    # Install Python dependencies
    Write-Log "Installing Python dependencies..."
    if (Test-Path "requirements.txt") {
        Write-Log "Found requirements.txt, installing..."
        $reqOutput = & python -m pip install -r requirements.txt 2>&1
        Write-Log "Dependencies installed from requirements.txt"
    } else {
        Write-Log "No requirements.txt found, installing packages manually..."
        $packages = "MetaTrader5", "redis", "pika", "python-dotenv"
        foreach ($package in $packages) {
            Write-Log "Installing $package..."
            & python -m pip install $package 2>&1 | Out-Null
        }
        Write-Log "Manual package installation complete"
    }
    
    # Create environment configuration
    Write-Log ""
    Write-Log "Creating environment configuration..."
    $envPath = "C:\NightTrader\service\mt5-service\.env"
    
    # Build environment file with secure credentials
    # Check if environment variables are set
    $rabbitmqPassword = if ($env:RABBITMQ_PASSWORD) { $env:RABBITMQ_PASSWORD } else { "" }
    $redisPassword = if ($env:REDIS_PASSWORD) { $env:REDIS_PASSWORD } else { "" }
    $rabbitmqUser = if ($env:RABBITMQ_USER) { $env:RABBITMQ_USER } else { "nighttrader" }
    $queueName = if ($env:RABBITMQ_QUEUE_NAME) { $env:RABBITMQ_QUEUE_NAME } else { "mt5_signals" }
    $webhookToken = if ($env:WEBHOOK_TOKEN) { $env:WEBHOOK_TOKEN } else { "" }
    $digitalOceanIP = if ($env:DIGITALOCEAN_IP) { $env:DIGITALOCEAN_IP } else { "138.197.3.109" }
    
    $envContent = @"
# MT5 Configuration (configure manually in MT5 terminal)
MT5_LOGIN=
MT5_PASSWORD=
MT5_SERVER=

# Service Configuration
DIGITALOCEAN_DROPLET_IP=$digitalOceanIP
SINGLE_TRADE_MODE=true
CLOSE_OPPOSITE_POSITIONS=false

# Queue Configuration (VPS-specific)
RABBITMQ_QUEUE_NAME=$queueName
WEBHOOK_TOKEN=$webhookToken

# Infrastructure Credentials (KEEP SECURE!)
# WARNING: If these are empty, set them before starting the service
RABBITMQ_USER=$rabbitmqUser
RABBITMQ_PASSWORD=$rabbitmqPassword
REDIS_PASSWORD=$redisPassword
"@
    
    $envContent | Out-File -FilePath $envPath -Encoding UTF8
    Write-Log "Environment configuration created at: $envPath"
    
    if (-not $rabbitmqPassword -or -not $redisPassword) {
        Write-Log "WARNING: RABBITMQ_PASSWORD and REDIS_PASSWORD must be set in the .env file before starting the service!"
    }
    
    # Verify service files exist
    $serviceFile = "C:\NightTrader\service\mt5-service\service.py"
    if (Test-Path $serviceFile) {
        Write-Log "Service file verified: $serviceFile"
    } else {
        Write-Log "Warning: Service file not found at expected location"
    }
    
    Write-Log ""
    Write-Log "==============================================="
    Write-Log "NightTrader Service Setup Complete!"
    Write-Log "==============================================="
    
    # Save status for next script
    @{
        Status = "Success"
        RepositoryCloned = Test-Path "C:\NightTrader\service"
        ServiceFileExists = Test-Path $serviceFile
        EnvFileCreated = Test-Path $envPath
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    } | ConvertTo-Json | Out-File "C:\NightTrader\service-status.json"
    
    exit 0
    
} catch {
    Write-Log "ERROR: Service setup failed"
    Write-Log "Exception Message: $($_.Exception.Message)"
    Write-Log "Exception Type: $($_.Exception.GetType().FullName)"
    Write-Log "Stack Trace:"
    Write-Log $_.Exception.StackTrace
    Write-Log "Script Line: $($_.InvocationInfo.ScriptLineNumber)"
    Write-Log "Command: $($_.InvocationInfo.Line)"
    
    # Also write to console for immediate visibility
    Write-Host "ERROR DETAILS:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "At line: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
    
    exit 1
}