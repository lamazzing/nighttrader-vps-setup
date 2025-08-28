import os
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

class Config:
    # MT5 Settings
    # Handle empty string values gracefully
    _mt5_login_str = os.getenv('MT5_LOGIN', '0').strip()
    MT5_LOGIN = int(_mt5_login_str) if _mt5_login_str and _mt5_login_str.isdigit() else 0
    MT5_PASSWORD = os.getenv('MT5_PASSWORD', '')
    MT5_SERVER = os.getenv('MT5_SERVER', '')
    
    # Connection Settings
    DO_SERVER_IP = os.getenv('DO_SERVER_IP')
    REDIS_URL = os.getenv('REDIS_URL')
    RABBITMQ_URL = os.getenv('RABBITMQ_URL')
    
    # Service Settings
    SERVICE_NAME = os.getenv('SERVICE_NAME', 'NightTrader-MT5')
    LOG_LEVEL = os.getenv('LOG_LEVEL', 'INFO')
    
    # Trading Mode Settings
    SINGLE_TRADE_MODE = os.getenv('SINGLE_TRADE_MODE', 'true').lower() == 'true'  # Default: True
    CLOSE_OPPOSITE_POSITIONS = os.getenv('CLOSE_OPPOSITE_POSITIONS', 'false').lower() == 'true'  # Default: False
    
    # Webhook Configuration
    WEBHOOK_SECRET = os.getenv('WEBHOOK_SECRET')
    WEBHOOK_TOKEN = os.getenv('WEBHOOK_TOKEN')  # VPS-specific webhook token
    
    # Queue Configuration
    RABBITMQ_QUEUE_NAME = os.getenv('RABBITMQ_QUEUE_NAME', 'mt5_signals')  # VPS-specific queue
    
    # Infrastructure Credentials (NEW - for security)
    RABBITMQ_USER = os.getenv('RABBITMQ_USER', 'nighttrader')
    RABBITMQ_PASSWORD = os.getenv('RABBITMQ_PASSWORD')
    REDIS_PASSWORD = os.getenv('REDIS_PASSWORD')
    
    @classmethod
    def validate(cls):
        """Validate required configuration"""
        if not cls.MT5_LOGIN or not cls.MT5_PASSWORD or not cls.MT5_SERVER:
            raise ValueError("MT5_LOGIN, MT5_PASSWORD, and MT5_SERVER must be set in .env file")
        
        if not cls.DO_SERVER_IP:
            raise ValueError("DO_SERVER_IP must be set in .env file")
            
        # Check for new required credentials
        if not cls.RABBITMQ_PASSWORD:
            raise ValueError("RABBITMQ_PASSWORD must be set in .env file (security update required)")
            
        if not cls.REDIS_PASSWORD:
            raise ValueError("REDIS_PASSWORD must be set in .env file (security update required)")
        
        # Legacy check - can be removed once migration is complete
        if cls.REDIS_URL or cls.RABBITMQ_URL:
            print("WARNING: REDIS_URL and RABBITMQ_URL are deprecated. Use individual credential environment variables instead.")
        
        return True