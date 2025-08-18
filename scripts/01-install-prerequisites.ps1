# NightTrader Setup - Step 1: Install Prerequisites
# Installs Python, Git, OpenSSH, and configures firewall

param(
    [string]$LogPath = "C:\NightTrader\logs\setup-prerequisites.log"
)

$ErrorActionPreference = "Stop"

# Ensure log directory exists
New-Item -ItemType Directory -Path (Split-Path $LogPath) -Force | Out-Null

function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $LogPath -Append
    Write-Host $Message
}

try {
    Write-Log "==============================================="
    Write-Log "Starting Prerequisites Installation"
    Write-Log "==============================================="
    
    # Create base directories
    Write-Log "Creating directories..."
    New-Item -ItemType Directory -Path "C:\NightTrader" -Force | Out-Null
    New-Item -ItemType Directory -Path "C:\NightTrader\logs" -Force | Out-Null
    New-Item -ItemType Directory -Path "C:\temp" -Force | Out-Null
    Write-Log "Directories created"
    
    # Set TLS for downloads
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    
    # 1. Install Python 3.13
    Write-Log ""
    Write-Log "Installing Python 3.13..."
    $pythonUrl = "https://www.python.org/ftp/python/3.13.0/python-3.13.0-amd64.exe"
    $pythonInstaller = "C:\temp\python-installer.exe"
    
    Write-Log "Downloading Python..."
    Invoke-WebRequest -Uri $pythonUrl -OutFile $pythonInstaller -UseBasicParsing
    
    Write-Log "Installing Python (this may take a few minutes)..."
    $pythonArgs = "/quiet", "InstallAllUsers=1", "PrependPath=1", "Include_pip=1"
    Start-Process -FilePath $pythonInstaller -ArgumentList $pythonArgs -Wait -NoNewWindow
    Remove-Item $pythonInstaller -Force
    
    # Refresh PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    Write-Log "Python installed successfully"
    
    # 2. Install Git
    Write-Log ""
    Write-Log "Installing Git for Windows..."
    $gitUrl = "https://github.com/git-for-windows/git/releases/download/v2.43.0.windows.1/Git-2.43.0-64-bit.exe"
    $gitInstaller = "C:\temp\git-installer.exe"
    
    Write-Log "Downloading Git..."
    Invoke-WebRequest -Uri $gitUrl -OutFile $gitInstaller -UseBasicParsing
    
    Write-Log "Installing Git (this may take a few minutes)..."
    $gitArgs = "/VERYSILENT", "/NORESTART", "/NOCANCEL", "/SP-", "/CLOSEAPPLICATIONS"
    Start-Process -FilePath $gitInstaller -ArgumentList $gitArgs -Wait -NoNewWindow
    Remove-Item $gitInstaller -Force
    
    # Add Git to PATH
    $gitPath = "C:\Program Files\Git\cmd"
    if (Test-Path $gitPath) {
        $env:Path = $env:Path + ";$gitPath"
    }
    Write-Log "Git installed successfully"
    
    # 3. Install OpenSSH (simplified - use Windows capability)
    Write-Log ""
    Write-Log "Installing OpenSSH Server..."
    try {
        Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 | Out-Null
        Start-Service sshd -ErrorAction SilentlyContinue
        Set-Service -Name sshd -StartupType Automatic
        Write-Log "OpenSSH installed successfully"
    } catch {
        Write-Log "Warning: OpenSSH installation failed, but continuing..."
    }
    
    # 4. Install PsExec for session management
    Write-Log ""
    Write-Log "Installing PsExec for session management..."
    $psexecPath = "C:\Windows\System32\psexec.exe"
    if (-not (Test-Path $psexecPath)) {
        try {
            # Download PsExec64 and rename to psexec.exe
            Invoke-WebRequest -Uri "https://live.sysinternals.com/PsExec64.exe" -OutFile $psexecPath -UseBasicParsing
            
            # Accept EULA automatically
            & reg add "HKCU\Software\Sysinternals\PsExec" /v EulaAccepted /t REG_DWORD /d 1 /f 2>&1 | Out-Null
            Write-Log "PsExec installed successfully"
        } catch {
            Write-Log "Warning: Failed to install PsExec - $($_.Exception.Message)"
        }
    } else {
        Write-Log "PsExec already installed"
    }
    
    # 5. Configure Windows Firewall
    Write-Log ""
    Write-Log "Configuring Windows Firewall..."
    
    $firewallRules = @(
        @{DisplayName="SSH"; Port=22},
        @{DisplayName="NightTrader Redis"; Port=6379},
        @{DisplayName="NightTrader RabbitMQ"; Port=5672},
        @{DisplayName="MT5 Terminal"; Port=443}
    )
    
    foreach ($rule in $firewallRules) {
        try {
            New-NetFirewallRule -DisplayName $rule.DisplayName -Direction Inbound -Protocol TCP -LocalPort $rule.Port -Action Allow -ErrorAction SilentlyContinue | Out-Null
            Write-Log "Firewall rule created: $($rule.DisplayName)"
        } catch {
            Write-Log "Firewall rule may already exist: $($rule.DisplayName)"
        }
    }
    
    Write-Log ""
    Write-Log "==============================================="
    Write-Log "Prerequisites Installation Complete!"
    Write-Log "==============================================="
    
    # Save status for next script
    @{
        Status = "Success"
        Python = Test-Path "C:\Python313\python.exe"
        Git = Test-Path "C:\Program Files\Git\cmd\git.exe"
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    } | ConvertTo-Json | Out-File "C:\NightTrader\prerequisites-status.json"
    
    exit 0
    
} catch {
    Write-Log "ERROR: Prerequisites installation failed"
    Write-Log $_.Exception.Message
    exit 1
}