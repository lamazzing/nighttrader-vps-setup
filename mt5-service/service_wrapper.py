#!/usr/bin/env python3
"""
Windows Service Wrapper for MT5 Service
This runs as a Windows Service and keeps the MT5 service running
"""

import os
import sys
import time
import subprocess
import logging
from pathlib import Path

# Setup logging
log_dir = Path("C:/NightTrader/logs")
log_dir.mkdir(parents=True, exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(log_dir / 'service_wrapper.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger('ServiceWrapper')

class MT5ServiceWrapper:
    def __init__(self):
        self.service_path = Path("C:/NightTrader/mt5-service")
        self.service_script = self.service_path / "service.py"
        self.process = None
        self.running = True
        
    def start_mt5_terminal(self):
        """Ensure MT5 terminal is running"""
        try:
            # Check if MT5 is already running
            result = subprocess.run(
                ['tasklist', '/FI', 'IMAGENAME eq terminal64.exe'],
                capture_output=True,
                text=True
            )
            
            if 'terminal64.exe' not in result.stdout:
                logger.info("Starting MT5 Terminal...")
                mt5_path = "C:/Program Files/MetaTrader 5/terminal64.exe"
                if Path(mt5_path).exists():
                    subprocess.Popen(
                        [mt5_path, '/portable'],
                        creationflags=subprocess.CREATE_NO_WINDOW
                    )
                    time.sleep(15)  # Give MT5 time to start
                    logger.info("MT5 Terminal started")
                else:
                    logger.warning("MT5 Terminal not found at expected location")
            else:
                logger.info("MT5 Terminal already running")
                
        except Exception as e:
            logger.error(f"Error checking/starting MT5: {e}")
    
    def start_service(self):
        """Start the MT5 service"""
        try:
            logger.info("Starting MT5 service...")
            
            # Ensure we're in the right directory
            os.chdir(self.service_path)
            
            # Start the service
            self.process = subprocess.Popen(
                [sys.executable, str(self.service_script)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                creationflags=subprocess.CREATE_NO_WINDOW,
                cwd=str(self.service_path)
            )
            
            logger.info(f"MT5 service started with PID: {self.process.pid}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to start service: {e}")
            return False
    
    def check_service(self):
        """Check if service is still running"""
        if self.process:
            poll = self.process.poll()
            if poll is None:
                return True  # Still running
            else:
                logger.warning(f"Service exited with code: {poll}")
                # Try to get any error output
                if self.process.stderr:
                    errors = self.process.stderr.read()
                    if errors:
                        logger.error(f"Service errors: {errors.decode('utf-8', errors='ignore')}")
                return False
        return False
    
    def run(self):
        """Main loop - keep service running"""
        logger.info("MT5 Service Wrapper started")
        
        # Start MT5 Terminal first
        self.start_mt5_terminal()
        
        restart_count = 0
        max_restarts = 10
        
        while self.running and restart_count < max_restarts:
            try:
                # Start the service
                if self.start_service():
                    # Monitor the service
                    while self.running and self.check_service():
                        time.sleep(30)  # Check every 30 seconds
                    
                    if self.running:
                        # Service crashed, restart it
                        restart_count += 1
                        logger.warning(f"Service stopped, restarting... (attempt {restart_count}/{max_restarts})")
                        time.sleep(5)  # Wait before restart
                else:
                    # Failed to start
                    restart_count += 1
                    logger.error(f"Failed to start service, retrying... (attempt {restart_count}/{max_restarts})")
                    time.sleep(10)
                    
            except KeyboardInterrupt:
                logger.info("Shutdown requested")
                self.running = False
            except Exception as e:
                logger.error(f"Unexpected error: {e}")
                restart_count += 1
                time.sleep(10)
        
        if restart_count >= max_restarts:
            logger.error(f"Max restarts ({max_restarts}) reached, stopping wrapper")
        
        # Cleanup
        if self.process:
            try:
                self.process.terminate()
                self.process.wait(timeout=5)
            except:
                self.process.kill()
        
        logger.info("MT5 Service Wrapper stopped")

if __name__ == "__main__":
    wrapper = MT5ServiceWrapper()
    wrapper.run()