import os
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

class Config:
    # MT5 Settings
    MT5_LOGIN = int(os.getenv('MT5_LOGIN', '0'))
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
    
    @classmethod
    def validate(cls):
        """Validate required configuration"""
        if not cls.MT5_LOGIN or not cls.MT5_PASSWORD or not cls.MT5_SERVER:
            raise ValueError("MT5_LOGIN, MT5_PASSWORD, and MT5_SERVER must be set in .env file")
        
        if not cls.DO_SERVER_IP:
            raise ValueError("DO_SERVER_IP must be set in .env file")
            
        if not cls.REDIS_URL or not cls.RABBITMQ_URL:
            raise ValueError("REDIS_URL and RABBITMQ_URL must be set in .env file")
        
        return True