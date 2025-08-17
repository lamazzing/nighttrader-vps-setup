# NightTrader Setup - Step 2: Install MT5 Terminal
# Downloads and installs MetaTrader 5

param(
    [string]$LogPath = "C:\NightTrader\logs\setup-mt5.log"
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
    Write-Log "Starting MT5 Terminal Installation"
    Write-Log "==============================================="
    
    # Set TLS for downloads
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    
    # Download MT5
    Write-Log "Downloading MT5 Terminal..."
    $mt5Url = "https://download.mql5.com/cdn/web/metaquotes.ltd/mt5/mt5setup.exe"
    $mt5Installer = "C:\temp\mt5setup.exe"
    
    Invoke-WebRequest -Uri $mt5Url -OutFile $mt5Installer -UseBasicParsing
    Write-Log "Download complete"
    
    # Install MT5
    Write-Log "Installing MT5 Terminal (silent mode)..."
    Start-Process -FilePath $mt5Installer -ArgumentList "/auto" -Wait -NoNewWindow
    Remove-Item $mt5Installer -Force
    Write-Log "MT5 Terminal installed"
    
    # Check if MT5 credentials are provided
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
        Write-Log "Auto-login configuration created"
        
        # Start MT5 with auto-login
        $mt5Path = "C:\Program Files\MetaTrader 5\terminal64.exe"
        if (Test-Path $mt5Path) {
            Write-Log "Starting MT5 Terminal with auto-login..."
            Start-Process -FilePath $mt5Path -ArgumentList "/config:$mt5ConfigPath"
        }
    } else {
        Write-Log "No MT5 credentials provided, starting without auto-login..."
        
        # Start MT5 without auto-login
        $mt5Path = "C:\Program Files\MetaTrader 5\terminal64.exe"
        if (Test-Path $mt5Path) {
            Start-Process -FilePath $mt5Path
        }
    }
    
    # Wait for MT5 to initialize
    Write-Log "Waiting for MT5 Terminal to initialize..."
    Start-Sleep -Seconds 30
    
    # Check if MT5 is running
    $mt5Process = Get-Process terminal64 -ErrorAction SilentlyContinue
    if ($mt5Process) {
        Write-Log "MT5 Terminal is running (PID: $($mt5Process.Id), Session: $($mt5Process.SessionId))"
    } else {
        Write-Log "Warning: MT5 Terminal process not detected, but installation completed"
    }
    
    Write-Log ""
    Write-Log "==============================================="
    Write-Log "MT5 Terminal Installation Complete!"
    Write-Log "==============================================="
    
    # Save status for next script
    @{
        Status = "Success"
        MT5Installed = Test-Path "C:\Program Files\MetaTrader 5\terminal64.exe"
        MT5Running = [bool]$mt5Process
        SessionId = if ($mt5Process) { $mt5Process[0].SessionId } else { $null }
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    } | ConvertTo-Json | Out-File "C:\NightTrader\mt5-status.json"
    
    exit 0
    
} catch {
    Write-Log "ERROR: MT5 installation failed"
    Write-Log $_.Exception.Message
    exit 1
}