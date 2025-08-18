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
    
    # Change to service directory
    Set-Location "C:\NightTrader\service\mt5-service"
    Write-Log "Changed to mt5-service directory"
    
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
    
    # Build environment file from environment variables
    $envContent = @"
# MT5 Configuration
MT5_LOGIN=$($env:MT5_LOGIN)
MT5_PASSWORD=$($env:MT5_PASSWORD)
MT5_SERVER=$($env:MT5_SERVER)

# Redis Configuration
REDIS_HOST=$($env:DIGITALOCEAN_IP)
REDIS_PORT=6379
REDIS_PASSWORD=$($env:REDIS_PASSWORD)

# RabbitMQ Configuration
RABBITMQ_HOST=$($env:DIGITALOCEAN_IP)
RABBITMQ_PORT=5672
RABBITMQ_USER=$($env:RABBITMQ_USER)
RABBITMQ_PASSWORD=$($env:RABBITMQ_PASSWORD)

# Service Configuration
SINGLE_TRADE_MODE=true
CLOSE_OPPOSITE_POSITIONS=false
"@
    
    $envContent | Out-File -FilePath $envPath -Encoding UTF8
    Write-Log "Environment configuration created at: $envPath"
    
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
    Write-Log $_.Exception.Message
    exit 1
}