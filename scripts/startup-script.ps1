#ps1_sysnative
# NightTrader Complete Windows VPS Setup Script
# This script runs at first boot and installs everything needed for automated trading
# Includes: Python, Git, SSH, PsExec, MT5 Terminal, and NightTrader Service

$ErrorActionPreference = "Stop"
$logFile = "C:\NightTrader\setup.log"

function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $logFile -Append
    Write-Host $Message
}

try {
    # Create base directories
    New-Item -ItemType Directory -Path "C:\NightTrader" -Force | Out-Null
    New-Item -ItemType Directory -Path "C:\NightTrader\logs" -Force | Out-Null
    New-Item -ItemType Directory -Path "C:\temp" -Force | Out-Null
    
    Write-Log "==============================================="
    Write-Log "Starting NightTrader Complete VPS Setup"
    Write-Log "==============================================="
    
    # ============ STAGE 1: Core Infrastructure ============
    Write-Log ""
    Write-Log "STAGE 1: Installing Core Infrastructure"
    Write-Log "----------------------------------------"
    
    # 1. Install Python 3.13
    Write-Log "[1/11] Installing Python 3.13..."
    $pythonUrl = "https://www.python.org/ftp/python/3.13.0/python-3.13.0-amd64.exe"
    $pythonInstaller = "C:\temp\python-installer.exe"
    
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $pythonUrl -OutFile $pythonInstaller -UseBasicParsing
    
    $pythonArgs = @(
        "/quiet",
        "InstallAllUsers=1",
        "PrependPath=1",
        "Include_pip=1",
        "Include_tcltk=0",
        "Include_test=0"
    )
    
    Start-Process -FilePath $pythonInstaller -ArgumentList $pythonArgs -Wait -NoNewWindow
    Remove-Item $pythonInstaller -Force
    
    # Refresh PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    Write-Log "Python installed successfully"
    
    # 2. Install Git
    Write-Log "[2/11] Installing Git for Windows..."
    $gitUrl = "https://github.com/git-for-windows/git/releases/download/v2.43.0.windows.1/Git-2.43.0-64-bit.exe"
    $gitInstaller = "C:\temp\git-installer.exe"
    
    Invoke-WebRequest -Uri $gitUrl -OutFile $gitInstaller -UseBasicParsing
    
    $gitArgs = @(
        "/VERYSILENT",
        "/NORESTART",
        "/NOCANCEL",
        "/SP-",
        "/CLOSEAPPLICATIONS",
        "/RESTARTAPPLICATIONS",
        "/COMPONENTS=icons,ext\reg\shellhere,assoc,assoc_sh"
    )
    
    Start-Process -FilePath $gitInstaller -ArgumentList $gitArgs -Wait -NoNewWindow
    Remove-Item $gitInstaller -Force
    
    # Refresh PATH for Git
    $gitPath = "C:\Program Files\Git\cmd"
    if (Test-Path $gitPath) {
        $env:Path = $env:Path + ";$gitPath"
    }
    Write-Log "Git installed successfully"
    
    # 3. Install OpenSSH Server
    Write-Log "[3/11] Installing OpenSSH Server..."
    try {
        # Try GitHub method first (more reliable)
        Write-Log "Downloading OpenSSH from GitHub..."
        $sshUrl = "https://github.com/PowerShell/Win32-OpenSSH/releases/download/v9.5.0.0p1-Beta/OpenSSH-Win64.zip"
        $sshZip = "C:\temp\openssh.zip"
        
        Invoke-WebRequest -Uri $sshUrl -OutFile $sshZip -UseBasicParsing
        
        # Extract OpenSSH
        Write-Log "Extracting OpenSSH..."
        Expand-Archive -Path $sshZip -DestinationPath "C:\temp" -Force
        
        # Install OpenSSH
        $installPath = "C:\Program Files\OpenSSH"
        if (Test-Path $installPath) {
            Remove-Item $installPath -Recurse -Force
        }
        Move-Item "C:\temp\OpenSSH-Win64" $installPath -Force
        
        # Run installation script
        Set-Location $installPath
        & powershell.exe -ExecutionPolicy Bypass -File install-sshd.ps1
        
        # Add to PATH
        $currentPath = [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::Machine)
        if ($currentPath -notlike "*$installPath*") {
            [Environment]::SetEnvironmentVariable("Path", "$currentPath;$installPath", [EnvironmentVariableTarget]::Machine)
            $env:Path = $env:Path + ";$installPath"
        }
        
        # Configure SSH
        $sshdConfig = @"
PasswordAuthentication yes
PubkeyAuthentication yes
Subsystem sftp sftp-server.exe
"@
        $sshdConfig | Out-File -FilePath "$installPath\sshd_config" -Encoding UTF8
        
        # Start SSH service
        Start-Service sshd -ErrorAction SilentlyContinue
        Set-Service -Name sshd -StartupType Automatic
        
        # Configure firewall
        New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -ErrorAction SilentlyContinue
        
        Remove-Item $sshZip -Force
        Write-Log "OpenSSH installed and configured successfully"
    }
    catch {
        Write-Log "GitHub installation failed, trying Windows capability..."
        Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
        Start-Service sshd
        Set-Service -Name sshd -StartupType Automatic
        Write-Log "OpenSSH installed via Windows capability"
    }
    
    # 4. Install PsExec for session management
    Write-Log "[4/11] Installing PsExec for session management..."
    $psexecUrl = "https://live.sysinternals.com/PsExec64.exe"
    $psexecPath = "C:\Windows\System32\psexec.exe"
    
    Invoke-WebRequest -Uri $psexecUrl -OutFile $psexecPath -UseBasicParsing
    
    # Accept EULA
    & reg add "HKCU\Software\Sysinternals\PsExec" /v EulaAccepted /t REG_DWORD /d 1 /f | Out-Null
    Write-Log "PsExec installed successfully"
    
    # Configure Windows Firewall
    Write-Log "[5/11] Configuring Windows Firewall..."
    New-NetFirewallRule -DisplayName "NightTrader Redis" -Direction Inbound -Protocol TCP -LocalPort 6379 -Action Allow -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName "NightTrader RabbitMQ" -Direction Inbound -Protocol TCP -LocalPort 5672 -Action Allow -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName "MT5 Terminal" -Direction Inbound -Protocol TCP -LocalPort 443 -Action Allow -ErrorAction SilentlyContinue
    Write-Log "Firewall rules configured"
    
    # ============ STAGE 2: MT5 Terminal Installation ============
    Write-Log ""
    Write-Log "STAGE 2: Installing MT5 Terminal"
    Write-Log "--------------------------------"
    
    Write-Log "[6/11] Downloading MT5 Terminal..."
    $mt5Url = "https://download.mql5.com/cdn/web/metaquotes.ltd/mt5/mt5setup.exe"
    $mt5Installer = "C:\temp\mt5setup.exe"
    
    Invoke-WebRequest -Uri $mt5Url -OutFile $mt5Installer -UseBasicParsing
    
    Write-Log "Installing MT5 Terminal (silent mode)..."
    Start-Process -FilePath $mt5Installer -ArgumentList "/auto" -Wait -NoNewWindow
    Remove-Item $mt5Installer -Force
    
    # Create MT5 auto-login configuration if credentials are provided
    if ($env:MT5_LOGIN -and $env:MT5_SERVER -and $env:MT5_PASSWORD) {
        Write-Log "Creating MT5 auto-login configuration..."
        $mt5ConfigPath = "C:\NightTrader\mt5-config.ini"
        $mt5Config = @"
[Server]
$($env:MT5_SERVER)

[Account]
Login=$($env:MT5_LOGIN)
Password=$($env:MT5_PASSWORD)
"@
        $mt5Config | Out-File -FilePath $mt5ConfigPath -Encoding UTF8
        
        # Start MT5 with auto-login
        Write-Log "Starting MT5 Terminal with auto-login..."
        $mt5Path = "C:\Program Files\MetaTrader 5\terminal64.exe"
        if (Test-Path $mt5Path) {
            Start-Process -FilePath $mt5Path -ArgumentList "/config:$mt5ConfigPath"
        }
    } else {
        Write-Log "MT5 credentials not provided, manual login required"
        # Start MT5 without auto-login
        $mt5Path = "C:\Program Files\MetaTrader 5\terminal64.exe"
        if (Test-Path $mt5Path) {
            Start-Process -FilePath $mt5Path
        }
    }
    
    Write-Log "MT5 Terminal installed successfully"
    
    # Wait for MT5 to start
    Write-Log "Waiting for MT5 Terminal to initialize..."
    Start-Sleep -Seconds 30
    
    # ============ STAGE 3: NightTrader Service Setup ============
    Write-Log ""
    Write-Log "STAGE 3: Setting up NightTrader Service"
    Write-Log "---------------------------------------"
    
    # 7. Clone service repository
    Write-Log "[7/11] Cloning NightTrader service repository..."
    Set-Location "C:\NightTrader"
    
    # Use environment variable or default repository
    $repoUrl = if ($env:MT5_SERVICE_REPO) { $env:MT5_SERVICE_REPO } else { "https://github.com/nighttrader/nighttrader-vps-setup.git" }
    
    # Clone repository
    & git clone $repoUrl service 2>&1 | Out-String | Write-Log
    
    if (Test-Path "C:\NightTrader\service") {
        Write-Log "Repository cloned successfully"
    } else {
        Write-Log "ERROR: Failed to clone repository"
        throw "Repository clone failed"
    }
    
    # 8. Install Python dependencies
    Write-Log "[8/11] Installing Python dependencies..."
    Set-Location "C:\NightTrader\service\mt5-service"
    
    # Upgrade pip first
    & python -m pip install --upgrade pip 2>&1 | Out-String | Write-Log
    
    # Install requirements
    if (Test-Path "requirements.txt") {
        & python -m pip install -r requirements.txt 2>&1 | Out-String | Write-Log
    } else {
        # Install manually if requirements.txt doesn't exist
        & python -m pip install MetaTrader5 redis pika python-dotenv 2>&1 | Out-String | Write-Log
    }
    
    Write-Log "Python dependencies installed"
    
    # 9. Create environment configuration
    Write-Log "[9/11] Configuring service environment..."
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
    Write-Log "Environment configured"
    
    # ============ STAGE 4: Service Launch with Session Management ============
    Write-Log ""
    Write-Log "STAGE 4: Starting Service with Session Management"
    Write-Log "------------------------------------------------"
    
    Write-Log "[10/11] Starting MT5 Service..."
    
    # Find MT5 Terminal process and session
    $mt5Process = Get-Process terminal64 -ErrorAction SilentlyContinue
    
    if ($mt5Process) {
        $sessionId = $mt5Process[0].SessionId
        Write-Log "MT5 Terminal found in session $sessionId"
        
        # Use PsExec to start service in MT5's session
        $pythonPath = "C:\Python313\python.exe"
        if (-not (Test-Path $pythonPath)) {
            # Try alternative Python paths
            $pythonPath = (Get-Command python -ErrorAction SilentlyContinue).Path
            if (-not $pythonPath) {
                $pythonPath = "python"
            }
        }
        
        $servicePath = "C:\NightTrader\service\mt5-service\service.py"
        
        Write-Log "Starting service in session $sessionId using PsExec..."
        $psexecCommand = "psexec -accepteula -i $sessionId -d `"$pythonPath`" `"$servicePath`""
        
        # Execute PsExec
        $psexecResult = & cmd /c $psexecCommand 2>&1 | Out-String
        Write-Log "PsExec output: $psexecResult"
        
        if ($psexecResult -match "started on|process ID") {
            Write-Log "Service started successfully with PsExec"
        } else {
            Write-Log "Warning: PsExec may have encountered issues"
        }
        
        # Create backup scheduled task
        Write-Log "Creating backup scheduled task..."
        $taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers>
    <BootTrigger>
      <Enabled>true</Enabled>
    </BootTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>S-1-5-18</UserId>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <Priority>7</Priority>
    <RestartOnFailure>
      <Interval>PT1M</Interval>
      <Count>3</Count>
    </RestartOnFailure>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>$pythonPath</Command>
      <Arguments>$servicePath</Arguments>
      <WorkingDirectory>C:\NightTrader\service\mt5-service</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
"@
        
        $taskXml | Out-File -FilePath "C:\temp\nighttrader-task.xml" -Encoding Unicode
        & schtasks /create /tn "NightTrader_MT5_Service" /xml "C:\temp\nighttrader-task.xml" /f | Out-Null
        Remove-Item "C:\temp\nighttrader-task.xml" -Force
        
        Write-Log "Backup scheduled task created"
        
    } else {
        Write-Log "MT5 Terminal not running, creating scheduled task for startup..."
        
        # Create scheduled task that will run at startup
        $pythonPath = "C:\Python313\python.exe"
        if (-not (Test-Path $pythonPath)) {
            $pythonPath = "python"
        }
        
        $servicePath = "C:\NightTrader\service\mt5-service\service.py"
        
        $action = New-ScheduledTaskAction -Execute $pythonPath -Argument $servicePath -WorkingDirectory "C:\NightTrader\service\mt5-service"
        $trigger = New-ScheduledTaskTrigger -AtStartup
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -StartWhenAvailable -RestartInterval (New-TimeSpan -Minutes 1) -RestartCount 3
        
        Register-ScheduledTask -TaskName "NightTrader_MT5_Service" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force
        Start-ScheduledTask -TaskName "NightTrader_MT5_Service"
        
        Write-Log "Scheduled task created and started"
    }
    
    # ============ STAGE 5: Verification ============
    Write-Log ""
    Write-Log "STAGE 5: Verifying Installation"
    Write-Log "-------------------------------"
    
    Write-Log "[11/11] Running verification checks..."
    Start-Sleep -Seconds 10
    
    # Check Python
    $pythonVersion = & python --version 2>&1
    if ($pythonVersion) {
        Write-Log "✓ Python: $pythonVersion"
    } else {
        Write-Log "✗ Python not found"
    }
    
    # Check Git
    $gitVersion = & git --version 2>&1
    if ($gitVersion) {
        Write-Log "✓ Git: $gitVersion"
    } else {
        Write-Log "✗ Git not found"
    }
    
    # Check SSH
    $sshService = Get-Service sshd -ErrorAction SilentlyContinue
    if ($sshService) {
        Write-Log "✓ SSH Service: $($sshService.Status)"
    } else {
        Write-Log "✗ SSH Service not found"
    }
    
    # Check PsExec
    if (Test-Path "C:\Windows\System32\psexec.exe") {
        Write-Log "✓ PsExec installed"
    } else {
        Write-Log "✗ PsExec not found"
    }
    
    # Check MT5 Terminal
    $mt5Running = Get-Process terminal64 -ErrorAction SilentlyContinue
    if ($mt5Running) {
        Write-Log "✓ MT5 Terminal: Running (Session $($mt5Running[0].SessionId))"
    } else {
        Write-Log "✗ MT5 Terminal not running"
    }
    
    # Check NightTrader Service
    $pythonRunning = Get-Process python -ErrorAction SilentlyContinue | Where-Object { 
        try {
            $_.Path -like "*python*" -and (Get-WmiObject Win32_Process -Filter "ProcessId = $($_.Id)").CommandLine -like "*service.py*"
        } catch {
            $false
        }
    }
    
    if ($pythonRunning) {
        Write-Log "✓ NightTrader Service: Running (Session $($pythonRunning[0].SessionId))"
        
        # Check if in same session as MT5
        if ($mt5Running -and $pythonRunning[0].SessionId -eq $mt5Running[0].SessionId) {
            Write-Log "✓ Service running in same session as MT5 Terminal"
        } elseif ($mt5Running) {
            Write-Log "⚠ Service and MT5 in different sessions"
        }
    } else {
        Write-Log "✗ NightTrader Service not running"
    }
    
    # Check service log
    $logPath = "C:\NightTrader\logs\mt5_service.log"
    if (Test-Path $logPath) {
        Write-Log ""
        Write-Log "Recent service logs:"
        $logContent = Get-Content $logPath -Tail 10 -ErrorAction SilentlyContinue
        if ($logContent) {
            $logContent | ForEach-Object {
                if ($_ -match "ERROR") {
                    Write-Log "  ✗ $_"
                } elseif ($_ -match "connected|ready|success" -and $_ -notmatch "Failed") {
                    Write-Log "  ✓ $_"
                } else {
                    Write-Log "  - $_"
                }
            }
        }
    }
    
    # Report status to dashboard if webhook provided
    if ($env:DASHBOARD_WEBHOOK) {
        Write-Log ""
        Write-Log "Reporting status to dashboard..."
        
        $vpsIp = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notlike "*Loopback*" })[0].IPAddress
        
        $status = @{
            vps_ip = $vpsIp
            status = "ready"
            mt5_running = [bool]$mt5Running
            service_running = [bool]$pythonRunning
            ssh_available = [bool]$sshService
            timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            session_match = if($mt5Running -and $pythonRunning) { $pythonRunning[0].SessionId -eq $mt5Running[0].SessionId } else { $false }
        }
        
        try {
            $jsonBody = $status | ConvertTo-Json
            Invoke-WebRequest -Uri $env:DASHBOARD_WEBHOOK -Method POST -Body $jsonBody -ContentType "application/json" -UseBasicParsing
            Write-Log "Dashboard notified successfully"
        } catch {
            Write-Log "Failed to notify dashboard: $_"
        }
    }
    
    Write-Log ""
    Write-Log "==============================================="
    Write-Log "NightTrader VPS Setup Complete!"
    Write-Log "==============================================="
    Write-Log ""
    Write-Log "Summary:"
    Write-Log "- Python 3.13 installed"
    Write-Log "- Git installed"
    Write-Log "- OpenSSH Server configured"
    Write-Log "- PsExec installed for session management"
    Write-Log "- MT5 Terminal installed"
    Write-Log "- NightTrader service repository cloned"
    Write-Log "- Service configured and started"
    Write-Log ""
    Write-Log "Next steps:"
    Write-Log "1. If MT5 is not logged in, login manually"
    Write-Log "2. Enable Algo Trading in MT5 settings"
    Write-Log "3. Allow DLL imports if required"
    Write-Log "4. Monitor service logs at: C:\NightTrader\logs\mt5_service.log"
    Write-Log ""
    Write-Log "To update the service: cd C:\NightTrader\service && git pull"
    
} catch {
    Write-Log "ERROR: Setup failed - $_"
    Write-Log $_.Exception.Message
    Write-Log $_.ScriptStackTrace
    exit 1
}