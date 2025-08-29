# NightTrader VPS Setup

Automated Windows VPS setup for NightTrader MT5 trading service. This repository contains everything needed to deploy a fully functional MT5 trading bot on a Windows VPS with a single startup script.

## Features

- **Complete Automation**: Single startup script installs everything
- **Session Management**: Uses PsExec to ensure MT5 service runs in the correct Windows session
- **Git-Based Updates**: Simple `git pull` to update the service
- **Health Monitoring**: Built-in verification and diagnostic scripts
- **Zero Manual Steps**: VPS is trading-ready in ~15 minutes

## Architecture

```
Windows VPS
├── Python 3.13          # Runtime for MT5 service
├── Git for Windows      # Version control
├── OpenSSH Server       # Remote access
├── PsExec               # Session management
├── MT5 Terminal         # Trading platform
└── NightTrader Service  # Automated trading bot
    ├── service.py       # Main service
    ├── config.py        # Configuration
    └── .env            # Environment variables
```

## Quick Start

### 1. Set Environment Variables

When creating your Windows VPS (Vultr, DigitalOcean, etc.), set these environment variables:

```powershell
MT5_LOGIN=819883
MT5_PASSWORD=your_password
MT5_SERVER=PUPrime-Demo
MT5_SERVICE_REPO=https://github.com/your-org/nighttrader-vps-setup.git
DIGITALOCEAN_IP=104.236.86.194
REDIS_PASSWORD=your_redis_password
RABBITMQ_USER=nighttrader
RABBITMQ_PASSWORD=your_rabbitmq_password
DASHBOARD_WEBHOOK=https://your-dashboard.com/api/vps/status  # Optional
```

### 2. Add Startup Script

Copy the contents of `scripts/startup-script.ps1` to your VPS provider's startup script field.

### 3. Create VPS

Create the Windows VPS. The startup script will:
1. Install Python, Git, SSH, PsExec
2. Download and install MT5 Terminal
3. Clone this repository
4. Configure and start the NightTrader service

### 4. Verify Installation

After ~15 minutes, SSH into your VPS and check the logs:

```powershell
Get-Content C:\NightTrader\logs\mt5_service.log -Tail 50
```

## Repository Structure

```
nighttrader-vps-setup/
├── mt5-service/
│   ├── service.py               # Main MT5 service
│   ├── config.py                # Service configuration
│   └── requirements.txt         # Python dependencies
├── scripts/
│   ├── startup-script.ps1       # Complete VPS setup script
│   ├── 01-install-prerequisites.ps1  # Install Python, Git, SSH, PsExec
│   ├── 02-install-mt5.ps1       # Install MT5 Terminal
│   ├── 03-setup-service.ps1     # Clone repo and configure service
│   ├── 04-start-service.ps1     # Start service with session management
│   └── 05-verify-installation.ps1 # Verify installation completeness
└── README.md
```

## Management Commands

### Update Service

```powershell
# Update to latest version from Git
cd C:\NightTrader\service
git pull

# Restart service after update
Get-Process python | Where-Object {$_.CommandLine -like "*service.py*"} | Stop-Process -Force
$mt5Session = (Get-Process terminal64).SessionId
psexec -accepteula -i $mt5Session -d "C:\Python313\python.exe" "C:\NightTrader\service\mt5-service\service.py"
```

### Manual Service Control

```powershell
# Stop service
Get-Process python | Where-Object {$_.CommandLine -like "*service.py*"} | Stop-Process -Force

# Start service in MT5 session
$mt5Session = (Get-Process terminal64).SessionId
psexec -accepteula -i $mt5Session -d "C:\Python313\python.exe" "C:\NightTrader\service\mt5-service\service.py"

# View logs
Get-Content C:\NightTrader\logs\mt5_service.log -Tail 50 -Wait
```

## Troubleshooting

### Service Not Running

1. Check if MT5 Terminal is running:
   ```powershell
   Get-Process terminal64
   ```

2. Check logs for errors:
   ```powershell
   Get-Content C:\NightTrader\logs\mt5_service.log -Tail 100
   ```

3. Restart service in correct session:
   ```powershell
   $mt5Session = (Get-Process terminal64).SessionId
   psexec -accepteula -i $mt5Session -d "C:\Python313\python.exe" "C:\NightTrader\service\mt5-service\service.py"
   ```

### MT5 Connection Issues

1. Ensure MT5 Terminal is logged in
2. Enable Algo Trading in MT5 settings
3. Allow DLL imports if required
4. Check firewall rules

### Network Issues

1. Verify Redis/RabbitMQ connectivity:
   ```powershell
   Test-NetConnection -ComputerName $env:DIGITALOCEAN_IP -Port 6379
   Test-NetConnection -ComputerName $env:DIGITALOCEAN_IP -Port 5672
   ```

2. Check Windows Firewall:
   ```powershell
   Get-NetFirewallRule | Where-Object {$_.DisplayName -like "*NightTrader*"}
   ```

## Session Management

The MT5 service MUST run in the same Windows session as the MT5 Terminal for the API to work. This is handled automatically by:

1. **PsExec**: Launches the service in the correct session
2. **Scheduled Task**: Backup method if PsExec fails
3. **Verification**: The verify script checks session matching

## Environment Configuration

The service reads configuration from `C:\NightTrader\service\mt5-service\.env`:

```env
# MT5 Configuration
MT5_LOGIN=819883
MT5_PASSWORD=your_password
MT5_SERVER=PUPrime-Demo

# Redis Configuration
REDIS_HOST=104.236.86.194
REDIS_PORT=6379
REDIS_PASSWORD=your_password

# RabbitMQ Configuration
RABBITMQ_HOST=104.236.86.194
RABBITMQ_PORT=5672
RABBITMQ_USER=nighttrader
RABBITMQ_PASSWORD=your_password

# Service Configuration
SINGLE_TRADE_MODE=true
CLOSE_OPPOSITE_POSITIONS=false
```

## Security Considerations

1. **Passwords**: Never commit passwords to the repository
2. **Firewall**: Only required ports are opened
3. **SSH**: Password authentication enabled by default (consider key-based auth)
4. **Service Account**: Runs as SYSTEM with appropriate permissions

## Development Workflow

1. **Local Development**: Develop and test changes locally
2. **Push to GitHub**: Commit and push changes to the repository
3. **Update VPS**: Run `.\update.ps1` on each VPS to pull changes
4. **Verify**: Run `.\verify.ps1` to ensure everything is working

## License

[Your License Here]

## Support

For issues or questions, please open an issue on GitHub.