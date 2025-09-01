#!/usr/bin/env python3
"""
MT5 Service v6 - Single Trade Mode with configurable opposite position closing
- Default: Only one trade at a time (SINGLE_TRADE_MODE=true)
- Optional: Close opposite positions before new trades (CLOSE_OPPOSITE_POSITIONS=false)
"""

import MetaTrader5 as mt5
import pika
import pika.exceptions
import redis
import json
import time
import logging
from datetime import datetime, timezone
import os
from dotenv import load_dotenv
import uuid
from config import Config
import socket

# Load environment
load_dotenv()

# Setup logging
log_dir = "C:\\NightTrader\\logs"
os.makedirs(log_dir, exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(f'{log_dir}/mt5_service.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger('MT5Service')

class MT5Service:
    def __init__(self):
        self.mt5_connected = False
        self.rabbitmq_connection = None
        self.rabbitmq_channel = None
        self.redis_client = None
        self.symbol_map = {}  # Map requested symbols to tradeable ones
        self.vps_id = os.getenv('VPS_INSTANCE_ID', 'unknown')  # Unique VPS identifier
        self.should_stop = False  # Flag for graceful shutdown
        self.reconnect_delay = Config.RABBITMQ_RETRY_DELAY
        
    def connect_mt5(self):
        """Initialize and login to MT5"""
        try:
            # Check if MT5 credentials are configured
            login_str = os.getenv('MT5_LOGIN', '').strip()
            password = os.getenv('MT5_PASSWORD', '').strip()
            server = os.getenv('MT5_SERVER', '').strip()
            
            if not login_str or login_str == '0' or not password or not server:
                logger.warning("MT5 credentials not configured. Skipping MT5 connection.")
                logger.warning("Please configure MT5_LOGIN, MT5_PASSWORD, and MT5_SERVER in the .env file")
                self.mt5_connected = False
                return False
            
            logger.info("Initializing MT5...")
            if not mt5.initialize():
                logger.error("Failed to initialize MT5")
                return False
                
            login = int(login_str)
            
            if not mt5.login(login, password, server):
                error = mt5.last_error()
                logger.error(f"MT5 login failed: {error}")
                return False
                
            account = mt5.account_info()
            if account:
                logger.info(f"MT5 logged in: {account.login} (Balance: ${account.balance})")
                self.mt5_connected = True
                
                # Build symbol map for PU Prime
                self.build_symbol_map()
                return True
            return False
            
        except Exception as e:
            logger.error(f"MT5 connection error: {e}")
            return False
    
    def build_symbol_map(self):
        """Build mapping of symbols for PU Prime demo"""
        logger.info("Building symbol map...")
        
        # Get all symbols
        symbols = mt5.symbols_get()
        tradeable_count = 0
        
        for symbol in symbols:
            # Only map visible symbols with full trading
            if symbol.visible and symbol.trade_mode == mt5.SYMBOL_TRADE_MODE_FULL:
                tradeable_count += 1
                # Create mappings for common variations
                base_name = symbol.name.replace('.p', '').replace('.s', '').replace('.a', '').replace('m', '')
                self.symbol_map[base_name] = symbol.name
                self.symbol_map[symbol.name] = symbol.name  # Direct mapping
                
                # Log important tradeable symbols
                if any(s in symbol.name for s in ['EUR', 'USD', 'GBP', 'XAU', 'OIL']):
                    logger.info(f"   Tradeable: {symbol.name}")
        
        logger.info(f"Found {tradeable_count} tradeable symbols")
        
        # Log specific mappings
        if 'EURUSD' in self.symbol_map:
            logger.info(f"   EURUSD maps to: {self.symbol_map['EURUSD']}")
        if 'XAUUSD' in self.symbol_map:
            logger.info(f"   XAUUSD maps to: {self.symbol_map['XAUUSD']}")
    
    def get_tradeable_symbol(self, requested_symbol):
        """Get the tradeable version of a symbol"""
        # Return None if MT5 is not connected
        if not self.mt5_connected:
            logger.warning("MT5 not connected - cannot get tradeable symbol")
            return None
            
        # First, check if exact symbol exists and is tradeable
        info = mt5.symbol_info(requested_symbol)
        if info and info.visible and info.trade_mode == mt5.SYMBOL_TRADE_MODE_FULL:
            mt5.symbol_select(requested_symbol, True)
            return requested_symbol
        
        # Check symbol map
        if requested_symbol in self.symbol_map:
            mapped = self.symbol_map[requested_symbol]
            mt5.symbol_select(mapped, True)
            return mapped
        
        # Try removing .p, .s, .a suffixes and check map
        base_symbol = requested_symbol.replace('.p', '').replace('.s', '').replace('.a', '')
        if base_symbol in self.symbol_map:
            mapped = self.symbol_map[base_symbol]
            mt5.symbol_select(mapped, True)
            return mapped
        
        # If still not found, try common suffixes
        for suffix in ['.p', '.s', '.a', 'm', '']:
            test_symbol = base_symbol + suffix
            info = mt5.symbol_info(test_symbol)
            if info and info.visible and info.trade_mode == mt5.SYMBOL_TRADE_MODE_FULL:
                logger.info(f"Found tradeable variant: {test_symbol}")
                mt5.symbol_select(test_symbol, True)
                self.symbol_map[requested_symbol] = test_symbol
                return test_symbol
        
        logger.warning(f"No tradeable version found for {requested_symbol}")
        return None
    
    def has_open_position(self):
        """Check if there are any open positions with our magic number"""
        try:
            # Return False if MT5 is not connected
            if not self.mt5_connected:
                return False
                
            # Get all open positions
            positions = mt5.positions_get()
            
            if not positions:
                return False
            
            # Check for positions with our magic number (234000)
            our_positions = [pos for pos in positions if pos.magic == 234000]
            
            if our_positions:
                logger.info(f"Found {len(our_positions)} open NightTrader position(s)")
                for pos in our_positions:
                    logger.info(f"  - {pos.symbol}: {'BUY' if pos.type == 0 else 'SELL'} {pos.volume} lots")
                return True
            
            return False
            
        except Exception as e:
            logger.error(f"Error checking open positions: {e}")
            return False
    
    def close_opposite_positions(self, symbol, action):
        """Close any open positions that are opposite to the incoming signal"""
        try:
            # Return True if MT5 is not connected (nothing to close)
            if not self.mt5_connected:
                return True
                
            # Get all open positions for this symbol
            positions = mt5.positions_get(symbol=symbol)
            
            if not positions:
                logger.info(f"No open positions for {symbol}")
                return True
            
            # Filter positions by our magic number
            our_positions = [pos for pos in positions if pos.magic == 234000]
            
            if not our_positions:
                logger.info(f"No NightTrader positions for {symbol}")
                return True
            
            # Determine opposite position type
            # If incoming signal is BUY, close SELL positions (type=1)
            # If incoming signal is SELL, close BUY positions (type=0)
            opposite_type = 1 if action == 'BUY' else 0
            
            positions_to_close = [pos for pos in our_positions if pos.type == opposite_type]
            
            if not positions_to_close:
                logger.info(f"No opposite positions to close for {symbol}")
                return True
            
            logger.info(f"Found {len(positions_to_close)} opposite positions to close")
            
            for position in positions_to_close:
                # Prepare close request
                close_type = mt5.ORDER_TYPE_BUY if position.type == 1 else mt5.ORDER_TYPE_SELL
                
                close_request = {
                    "action": mt5.TRADE_ACTION_DEAL,
                    "symbol": symbol,
                    "volume": position.volume,
                    "type": close_type,
                    "position": position.ticket,  # Important: specify the position to close
                    "price": mt5.symbol_info_tick(symbol).ask if close_type == mt5.ORDER_TYPE_BUY else mt5.symbol_info_tick(symbol).bid,
                    "deviation": 20,
                    "magic": 234000,
                    "comment": f"Close opposite position",
                    "type_time": mt5.ORDER_TIME_GTC,
                    "type_filling": mt5.ORDER_FILLING_IOC,
                }
                
                logger.info(f"Closing position {position.ticket} (type: {'SELL' if position.type == 1 else 'BUY'}, volume: {position.volume})")
                
                result = mt5.order_send(close_request)
                
                if result is None:
                    error = mt5.last_error()
                    logger.error(f"Failed to close position {position.ticket}: order_send returned None. Error: {error}")
                elif result.retcode != mt5.TRADE_RETCODE_DONE:
                    logger.error(f"Failed to close position {position.ticket}: {result.comment} (code: {result.retcode})")
                else:
                    logger.info(f"Successfully closed position {position.ticket} with order {result.order}")
                    
                    # Log the closure in Redis
                    try:
                        closure_data = {
                            "closed_position": position.ticket,
                            "close_order": result.order,
                            "symbol": symbol,
                            "volume": position.volume,
                            "timestamp": datetime.now().isoformat(),
                            "reason": "opposite_signal"
                        }
                        self.redis_client.hset(
                            f"position_closure:{result.order}",
                            mapping=closure_data
                        )
                    except Exception as e:
                        logger.warning(f"Failed to log position closure in Redis: {e}")
            
            return True
            
        except Exception as e:
            logger.error(f"Error closing opposite positions: {e}", exc_info=True)
            return False
    
    def close_positions_by_signal(self, signal):
        """Close positions based on a close signal from TradingView"""
        try:
            # Return True if MT5 is not connected (nothing to close)
            if not self.mt5_connected:
                logger.warning("MT5 not connected - cannot close positions")
                return True
            
            # Get symbol from signal
            requested_symbol = signal.get('symbol', 'EURUSD')
            symbol = self.get_tradeable_symbol(requested_symbol)
            
            if not symbol:
                logger.error(f"No tradeable symbol found for {requested_symbol}")
                self.log_trade_attempt(signal, "FAILED", f"No tradeable symbol for {requested_symbol}")
                return True
            
            # Get position type to close from signal (optional)
            close_type = signal.get('type', 'all').lower()  # 'long', 'short', or 'all'
            close_reason = signal.get('reason', 'manual_close')
            
            # Get all open positions for this symbol
            positions = mt5.positions_get(symbol=symbol)
            
            if not positions:
                logger.info(f"No open positions for {symbol}")
                self.log_trade_attempt(signal, "SUCCESS", f"No positions to close for {symbol}")
                return True
            
            # Filter positions by our magic number
            our_positions = [pos for pos in positions if pos.magic == 234000]
            
            if not our_positions:
                logger.info(f"No NightTrader positions for {symbol}")
                self.log_trade_attempt(signal, "SUCCESS", f"No NightTrader positions to close for {symbol}")
                return True
            
            # Filter by position type if specified
            positions_to_close = our_positions
            if close_type == 'long':
                positions_to_close = [pos for pos in our_positions if pos.type == 0]  # BUY positions
            elif close_type == 'short':
                positions_to_close = [pos for pos in our_positions if pos.type == 1]  # SELL positions
            
            if not positions_to_close:
                logger.info(f"No {close_type} positions to close for {symbol}")
                self.log_trade_attempt(signal, "SUCCESS", f"No {close_type} positions to close")
                return True
            
            logger.info(f"Found {len(positions_to_close)} position(s) to close for {symbol} (type: {close_type}, reason: {close_reason})")
            
            closed_count = 0
            failed_count = 0
            
            for position in positions_to_close:
                # Prepare close request
                close_order_type = mt5.ORDER_TYPE_BUY if position.type == 1 else mt5.ORDER_TYPE_SELL
                
                close_request = {
                    "action": mt5.TRADE_ACTION_DEAL,
                    "symbol": symbol,
                    "volume": position.volume,
                    "type": close_order_type,
                    "position": position.ticket,
                    "price": mt5.symbol_info_tick(symbol).ask if close_order_type == mt5.ORDER_TYPE_BUY else mt5.symbol_info_tick(symbol).bid,
                    "deviation": 20,
                    "magic": 234000,
                    "comment": f"Close: {close_reason}",
                    "type_time": mt5.ORDER_TIME_GTC,
                    "type_filling": mt5.ORDER_FILLING_IOC,
                }
                
                position_type_str = 'LONG' if position.type == 0 else 'SHORT'
                logger.info(f"Closing {position_type_str} position {position.ticket} (volume: {position.volume})")
                
                result = mt5.order_send(close_request)
                
                if result is None:
                    error = mt5.last_error()
                    logger.error(f"Failed to close position {position.ticket}: order_send returned None. Error: {error}")
                    failed_count += 1
                elif result.retcode != mt5.TRADE_RETCODE_DONE:
                    logger.error(f"Failed to close position {position.ticket}: {result.comment} (code: {result.retcode})")
                    failed_count += 1
                else:
                    logger.info(f"Successfully closed position {position.ticket} with order {result.order}")
                    closed_count += 1
                    
                    # Log the closure in Redis
                    try:
                        closure_data = {
                            "signal_id": signal.get('id'),
                            "closed_position": position.ticket,
                            "close_order": result.order,
                            "symbol": symbol,
                            "volume": position.volume,
                            "position_type": position_type_str,
                            "timestamp": datetime.now().isoformat(),
                            "reason": close_reason
                        }
                        self.redis_client.hset(
                            f"position_closure:{result.order}",
                            mapping=closure_data
                        )
                    except Exception as e:
                        logger.warning(f"Failed to log position closure in Redis: {e}")
            
            # Log the overall result
            if failed_count == 0:
                self.log_trade_attempt(signal, "SUCCESS", f"Closed {closed_count} position(s)")
            else:
                self.log_trade_attempt(signal, "PARTIAL", f"Closed {closed_count} position(s), {failed_count} failed")
            
            return True
            
        except Exception as e:
            logger.error(f"Error closing positions by signal: {e}", exc_info=True)
            self.log_trade_attempt(signal, "ERROR", str(e))
            return False
    
    def connect_rabbitmq(self):
        """Connect to RabbitMQ with enhanced parameters"""
        try:
            # Get DigitalOcean IP
            digitalocean_ip = os.getenv('DIGITALOCEAN_DROPLET_IP', os.getenv('DIGITALOCEAN_IP', '138.197.3.109'))
            
            # Get queue name from environment (VPS-specific or default)
            self.queue_name = os.getenv('RABBITMQ_QUEUE_NAME', 'mt5_signals')
            logger.info(f"Using queue: {self.queue_name}")
            
            # Get RabbitMQ credentials from environment (read-only consumer)
            rabbitmq_user = os.getenv('RABBITMQ_USER', 'vps_consumer')
            rabbitmq_password = os.getenv('RABBITMQ_PASSWORD')
            if not rabbitmq_password:
                logger.error("RABBITMQ_PASSWORD not set in environment")
                return False
            
            # Create connection parameters with heartbeat and timeout settings
            logger.info(f"Connecting to RabbitMQ at {digitalocean_ip} with heartbeat={Config.RABBITMQ_HEARTBEAT}s...")
            
            # Build connection parameters with enhanced settings
            connection_params = pika.ConnectionParameters(
                host=digitalocean_ip,
                port=5672,
                credentials=pika.PlainCredentials(rabbitmq_user, rabbitmq_password),
                heartbeat=Config.RABBITMQ_HEARTBEAT,
                blocked_connection_timeout=Config.RABBITMQ_BLOCKED_CONNECTION_TIMEOUT,
                socket_timeout=Config.RABBITMQ_SOCKET_TIMEOUT,
                connection_attempts=Config.RABBITMQ_CONNECTION_ATTEMPTS,
                retry_delay=Config.RABBITMQ_RETRY_DELAY,
                # TCP keepalive settings (helps detect broken connections)
                tcp_options={
                    'TCP_KEEPIDLE': 120,  # Start keepalive after 2 minutes of idle
                    'TCP_KEEPINTVL': 30,  # Interval between keepalive probes
                    'TCP_KEEPCNT': 10,    # Number of keepalive probes
                    'TCP_USER_TIMEOUT': 300000  # Total time for unacknowledged data (5 min)
                }
            )
            
            # Create connection
            self.rabbitmq_connection = pika.BlockingConnection(connection_params)
            self.rabbitmq_channel = self.rabbitmq_connection.channel()
            
            # Set QoS
            self.rabbitmq_channel.basic_qos(prefetch_count=1)
            
            # Try to check if queue exists (passive declare)
            try:
                self.rabbitmq_channel.queue_declare(queue=self.queue_name, durable=True, passive=True)
                logger.info(f"Queue {self.queue_name} exists")
            except pika.exceptions.ChannelClosedByBroker as e:
                if "ACCESS_REFUSED" in str(e):
                    logger.info(f"Read-only access confirmed - queue {self.queue_name} should exist")
                    # Recreate channel after ACCESS_REFUSED error
                    self.rabbitmq_channel = self.rabbitmq_connection.channel()
                    self.rabbitmq_channel.basic_qos(prefetch_count=1)
                elif "NOT_FOUND" in str(e):
                    logger.error(f"Queue {self.queue_name} does not exist on server")
                    return False
                else:
                    raise
            
            logger.info(f"RabbitMQ connected successfully to queue: {self.queue_name}")
            return True
            
        except pika.exceptions.AMQPConnectionError as e:
            logger.error(f"RabbitMQ connection failed: {e}")
            return False
        except Exception as e:
            logger.error(f"Unexpected error connecting to RabbitMQ: {e}")
            return False
    
    def connect_redis(self):
        """Connect to Redis with retry logic"""
        try:
            # Get DigitalOcean IP
            digitalocean_ip = os.getenv('DIGITALOCEAN_DROPLET_IP', os.getenv('DIGITALOCEAN_IP', '138.197.3.109'))
            
            # Get Redis password from environment
            redis_password = os.getenv('REDIS_PASSWORD')
            if not redis_password:
                logger.error("REDIS_PASSWORD not set in environment")
                return False
            
            # Connect to Redis
            logger.info(f"Connecting to Redis at {digitalocean_ip}...")
            self.redis_client = redis.Redis(
                host=digitalocean_ip,
                port=6379,
                password=redis_password,
                decode_responses=True,
                socket_connect_timeout=10,
                socket_timeout=5,
                retry_on_timeout=True,
                retry_on_error=[ConnectionError, TimeoutError],
                health_check_interval=30
            )
            self.redis_client.ping()
            logger.info("Redis connected")
            return True
            
        except Exception as e:
            logger.error(f"Redis connection error: {e}")
            return False
    
    def connect_services(self):
        """Connect to RabbitMQ and Redis on DigitalOcean"""
        # Connect to Redis first (less critical)
        if not self.connect_redis():
            logger.warning("Failed to connect to Redis - continuing without Redis logging")
            self.redis_client = None
        
        # Connect to RabbitMQ (critical)
        if not self.connect_rabbitmq():
            return False
        
        return True
    
    def process_signal(self, signal):
        """Process trading signal with improved error handling"""
        webhook_time = None  # Define at function scope
        
        try:
            # Add 'id' if missing
            if 'id' not in signal:
                signal['id'] = str(uuid.uuid4())
            
            logger.info(f"Processing signal: {signal}")
            
            # CRITICAL: Check if MT5 is connected before processing
            if not self.mt5_connected:
                logger.warning("MT5 not connected - cannot process trading signals")
                logger.warning("Configure MT5_LOGIN, MT5_PASSWORD, and MT5_SERVER in .env file")
                self.log_trade_attempt(signal, "SKIPPED", "MT5 not connected")
                return True  # ACK to prevent queue buildup
            
            # CRITICAL: Validate this signal is for THIS VPS
            signal_vps_id = signal.get('vps_id', 'unknown')
            if signal_vps_id != self.vps_id:
                logger.warning(f"Signal VPS ID mismatch: expected {self.vps_id}, got {signal_vps_id}")
                logger.warning("Ignoring signal intended for different VPS")
                self.log_trade_attempt(signal, "REJECTED", f"Wrong VPS: {signal_vps_id}")
                return True  # ACK to prevent redelivery
            
            # Calculate time since webhook received signal
            if 'timestamp' in signal:
                try:
                    webhook_time = datetime.fromisoformat(signal['timestamp'].replace('Z', '+00:00'))
                    current_time = datetime.now(timezone.utc)
                    time_diff = (current_time - webhook_time).total_seconds()
                    logger.info(f"Signal age: {time_diff:.2f} seconds since webhook received it")
                    
                    # Warn if signal is older than 5 seconds (should have expired in queue)
                    if time_diff > 5:
                        logger.warning(f"⚠️ Processing old signal: {time_diff:.2f}s old (>5s TTL)")
                        logger.warning("This signal should have expired - check RabbitMQ TTL settings")
                        # Still process it since it made it through the queue
                        # but this indicates a configuration issue
                except Exception as e:
                    logger.warning(f"Could not parse webhook timestamp: {e}")
            
            # Get tradeable symbol
            requested_symbol = signal.get('symbol', 'EURUSD')
            symbol = self.get_tradeable_symbol(requested_symbol)
            
            if not symbol:
                logger.error(f"No tradeable symbol found for {requested_symbol}")
                self.log_trade_attempt(signal, "FAILED", f"No tradeable symbol for {requested_symbol}")
                return True
            
            action = signal.get('action', 'BUY').upper()
            
            # Handle CLOSE action
            if action == 'CLOSE':
                logger.info(f"Processing CLOSE signal for {requested_symbol}")
                return self.close_positions_by_signal(signal)
            
            quantity = float(signal.get('quantity', 0.01))
            
            logger.info(f"Using tradeable symbol: {symbol} (requested: {requested_symbol})")
            
            # Check if MT5 is still connected (only if we had a connection)
            if self.mt5_connected and not mt5.terminal_info():
                logger.error("MT5 connection lost, reconnecting...")
                if not self.connect_mt5():
                    logger.error("Failed to reconnect to MT5")
                    self.log_trade_attempt(signal, "FAILED", "MT5 connection lost")
                    return True
            
            # Get symbol info
            symbol_info = mt5.symbol_info(symbol)
            if not symbol_info:
                logger.error(f"Symbol {symbol} not found")
                self.log_trade_attempt(signal, "FAILED", f"Symbol {symbol} not found")
                return True
            
            # Check account
            account = mt5.account_info()
            if not account:
                logger.error("Cannot get account info")
                self.log_trade_attempt(signal, "FAILED", "Cannot get account info")
                return True
            
            # Check if in single trade mode
            if Config.SINGLE_TRADE_MODE:
                if self.has_open_position():
                    logger.info(f"[SINGLE TRADE MODE] Skipping signal - already have open position(s)")
                    self.log_trade_attempt(signal, "SKIPPED", "Single trade mode - position already open")
                    return True  # Acknowledge message to prevent queue buildup
            
            # Close opposite positions if enabled
            if Config.CLOSE_OPPOSITE_POSITIONS:
                logger.info(f"Checking for opposite positions to close...")
                if not self.close_opposite_positions(symbol, action):
                    logger.warning("Failed to close some opposite positions, but continuing with new order")
            
            # Prepare order
            order_type = mt5.ORDER_TYPE_BUY if action == 'BUY' else mt5.ORDER_TYPE_SELL
            price = symbol_info.ask if action == 'BUY' else symbol_info.bid
            
            # Adjust volume to symbol requirements
            volume = max(symbol_info.volume_min, min(quantity, symbol_info.volume_max))
            volume = round(volume / symbol_info.volume_step) * symbol_info.volume_step
            
            request = {
                "action": mt5.TRADE_ACTION_DEAL,
                "symbol": symbol,
                "volume": volume,
                "type": order_type,
                "price": price,
                "deviation": 20,
                "magic": 234000,
                "comment": f"NightTrader {action}",
                "type_time": mt5.ORDER_TIME_GTC,
                "type_filling": mt5.ORDER_FILLING_IOC,
            }
            
            # Add SL/TP if provided (as distances from entry)
            if 'sl' in signal:
                sl_distance = float(signal['sl'])
                if action == 'BUY':
                    request['sl'] = price - sl_distance  # For BUY: SL below entry
                else:
                    request['sl'] = price + sl_distance  # For SELL: SL above entry
                    
            if 'tp' in signal:
                tp_distance = float(signal['tp'])
                if action == 'BUY':
                    request['tp'] = price + tp_distance  # For BUY: TP above entry
                else:
                    request['tp'] = price - tp_distance  # For SELL: TP below entry
            
            logger.info(f"Sending order: {request}")
            
            # Send order with error handling
            result = mt5.order_send(request)
            
            if result is None:
                error = mt5.last_error()
                logger.error(f"order_send returned None. Last error: {error}")
                self.log_trade_attempt(signal, "FAILED", f"order_send returned None: {error}")
                return True
                
            elif result.retcode != mt5.TRADE_RETCODE_DONE:
                logger.error(f"Order failed: {result.comment} (code: {result.retcode})")
                self.log_trade_attempt(signal, "FAILED", f"{result.comment} (retcode: {result.retcode})")
                return True
            else:
                logger.info(f"Order placed successfully: {result.order}")
                logger.info(f"   Price: {result.price}")
                logger.info(f"   Volume: {result.volume}")
                
                # Calculate total execution time
                execution_time = None
                if webhook_time:
                    execution_time = (datetime.now(timezone.utc) - webhook_time).total_seconds()
                    logger.info(f"[TIMING] Total execution time: {execution_time:.3f} seconds")
                
                self.log_trade_attempt(signal, "SUCCESS", f"Order #{result.order} - Execution time: {execution_time:.3f}s" if execution_time else f"Order #{result.order}")
                
                # Store in Redis with execution time
                try:
                    trade_data = {
                        "signal_id": signal.get('id'),
                        "symbol": symbol,
                        "requested_symbol": requested_symbol,
                        "action": action,
                        "volume": volume,
                        "price": result.price,
                        "timestamp": datetime.now().isoformat(),
                        "webhook_timestamp": signal.get('timestamp'),
                        "execution_time_seconds": execution_time
                    }
                    self.redis_client.hset(
                        f"trade:{result.order}",
                        mapping=trade_data
                    )
                except Exception as e:
                    logger.warning(f"Failed to store trade in Redis: {e}")
                
                return True
                
        except Exception as e:
            logger.error(f"Error processing signal: {e}", exc_info=True)
            self.log_trade_attempt(signal, "ERROR", str(e))
            return True
    
    def log_trade_attempt(self, signal, status, message):
        """Log trade attempts to file"""
        try:
            log_file = os.path.join(log_dir, "trade_attempts.log")
            with open(log_file, 'a') as f:
                f.write(f"{datetime.now().isoformat()} | {status} | {signal} | {message}\n")
        except:
            pass
    
    def on_message(self, channel, method, properties, body):
        """Handle incoming message from RabbitMQ"""
        try:
            signal = json.loads(body)
            logger.info(f"Received signal: {signal}")
            
            success = self.process_signal(signal)
            channel.basic_ack(delivery_tag=method.delivery_tag)
            
            if success:
                logger.info("Signal processed and acknowledged")
            else:
                logger.warning("Signal processing had issues but acknowledged")
                
        except Exception as e:
            logger.error(f"Message handling error: {e}")
            channel.basic_ack(delivery_tag=method.delivery_tag)
    
    def ensure_rabbitmq_connected(self):
        """Ensure RabbitMQ is connected, reconnect if necessary"""
        try:
            if self.rabbitmq_connection and not self.rabbitmq_connection.is_closed:
                # Try to check connection health
                self.rabbitmq_connection.process_data_events(time_limit=0)
                return True
        except Exception as e:
            logger.warning(f"RabbitMQ connection check failed: {e}")
        
        # Connection is closed or unhealthy, attempt reconnection
        logger.info("RabbitMQ connection lost, attempting to reconnect...")
        
        # Close existing connection cleanly if possible
        try:
            if self.rabbitmq_connection:
                self.rabbitmq_connection.close()
        except:
            pass
        
        self.rabbitmq_connection = None
        self.rabbitmq_channel = None
        
        # Attempt reconnection with exponential backoff
        retry_count = 0
        while not self.should_stop:
            retry_count += 1
            
            if self.connect_rabbitmq():
                logger.info("Successfully reconnected to RabbitMQ")
                self.reconnect_delay = Config.RABBITMQ_RETRY_DELAY  # Reset delay
                return True
            
            # Calculate backoff delay
            self.reconnect_delay = min(self.reconnect_delay * 2, Config.RABBITMQ_MAX_RETRY_DELAY)
            
            logger.warning(f"Reconnection attempt {retry_count} failed. Waiting {self.reconnect_delay} seconds before retry...")
            
            # Wait with ability to stop
            for _ in range(self.reconnect_delay):
                if self.should_stop:
                    return False
                time.sleep(1)
        
        return False
    
    def consume_with_reconnect(self):
        """Consume messages with automatic reconnection on failure"""
        while not self.should_stop:
            try:
                # Ensure we're connected
                if not self.ensure_rabbitmq_connected():
                    if self.should_stop:
                        break
                    continue
                
                # Setup consumer
                logger.info(f"Setting up consumer for queue: {self.queue_name}")
                self.rabbitmq_channel.basic_consume(
                    queue=self.queue_name,
                    on_message_callback=self.on_message,
                    auto_ack=False
                )
                
                logger.info(f"Starting to consume messages from queue: {self.queue_name}")
                
                # Start consuming with connection monitoring
                try:
                    # Process messages until connection fails or stop is requested
                    while not self.should_stop:
                        try:
                            # Process with timeout to allow periodic checks
                            self.rabbitmq_connection.process_data_events(time_limit=1)
                        except pika.exceptions.ConnectionClosed:
                            logger.error("RabbitMQ connection closed unexpectedly")
                            break
                        except pika.exceptions.ChannelClosed:
                            logger.error("RabbitMQ channel closed unexpectedly")
                            break
                        except pika.exceptions.StreamLostError as e:
                            logger.error(f"RabbitMQ stream lost: {e}")
                            break
                        except socket.timeout:
                            # Normal timeout, continue
                            continue
                        except Exception as e:
                            logger.error(f"Unexpected error during message processing: {e}")
                            break
                
                except KeyboardInterrupt:
                    logger.info("Received interrupt signal")
                    self.should_stop = True
                    break
                
            except pika.exceptions.AMQPConnectionError as e:
                logger.error(f"AMQP connection error: {e}")
                time.sleep(1)  # Brief pause before reconnection attempt
            except Exception as e:
                logger.error(f"Unexpected error in consume loop: {e}", exc_info=True)
                time.sleep(1)  # Brief pause before reconnection attempt
        
        logger.info("Message consumption stopped")
    
    def run(self):
        """Main service loop with automatic reconnection"""
        logger.info("Starting MT5 Service v7 (Auto-Reconnect Edition)...")
        logger.info(f"VPS Instance ID: {self.vps_id}")
        logger.info(f"Queue Name: {os.getenv('RABBITMQ_QUEUE_NAME', 'not set')}")
        logger.info(f"Trading Mode Configuration:")
        logger.info(f"  - Single Trade Mode: {'ENABLED' if Config.SINGLE_TRADE_MODE else 'DISABLED'}")
        logger.info(f"  - Close Opposite Positions: {'ENABLED' if Config.CLOSE_OPPOSITE_POSITIONS else 'DISABLED'}")
        logger.info(f"Security: Token-based queue isolation ENABLED")
        logger.info(f"RabbitMQ Configuration:")
        logger.info(f"  - Heartbeat: {Config.RABBITMQ_HEARTBEAT} seconds")
        logger.info(f"  - Connection timeout: {Config.RABBITMQ_BLOCKED_CONNECTION_TIMEOUT} seconds")
        logger.info(f"  - Max retry delay: {Config.RABBITMQ_MAX_RETRY_DELAY} seconds")
        
        # Connect to MT5 (but continue if it fails)
        if not self.connect_mt5():
            logger.warning("Failed to connect to MT5 - service will run in monitoring mode")
            logger.warning("Trading signals will be received but not executed")
            logger.warning("Configure MT5_LOGIN, MT5_PASSWORD, and MT5_SERVER in .env to enable trading")
        
        # Connect to Redis (non-critical)
        if not self.connect_redis():
            logger.warning("Failed to connect to Redis - continuing without Redis logging")
            self.redis_client = None
        
        logger.info("Service started. Ready to process trading signals!")
        
        # Main loop with automatic reconnection
        try:
            self.consume_with_reconnect()
        except KeyboardInterrupt:
            logger.info("Received shutdown signal")
        except Exception as e:
            logger.error(f"Unexpected error in main loop: {e}", exc_info=True)
        finally:
            self.shutdown()
    
    def shutdown(self):
        """Gracefully shutdown the service"""
        logger.info("Shutting down MT5 Service...")
        self.should_stop = True
        
        # Close RabbitMQ connection
        try:
            if self.rabbitmq_channel:
                self.rabbitmq_channel.stop_consuming()
            if self.rabbitmq_connection and not self.rabbitmq_connection.is_closed:
                self.rabbitmq_connection.close()
                logger.info("RabbitMQ connection closed")
        except Exception as e:
            logger.warning(f"Error closing RabbitMQ connection: {e}")
        
        # Close Redis connection
        try:
            if self.redis_client:
                self.redis_client.close()
                logger.info("Redis connection closed")
        except Exception as e:
            logger.warning(f"Error closing Redis connection: {e}")
        
        # Shutdown MT5
        try:
            if self.mt5_connected:
                mt5.shutdown()
                logger.info("MT5 connection closed")
        except Exception as e:
            logger.warning(f"Error closing MT5 connection: {e}")
        
        logger.info("Service shutdown complete")

if __name__ == "__main__":
    service = MT5Service()
    service.run()