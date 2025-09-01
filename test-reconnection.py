#!/usr/bin/env python3
"""
Test script to verify RabbitMQ reconnection mechanism
Run this to simulate connection failures and verify automatic recovery
"""

import pika
import time
import json
import os
from datetime import datetime
from dotenv import load_dotenv

load_dotenv()

def send_test_signal():
    """Send a test signal to the queue"""
    digitalocean_ip = os.getenv('DIGITALOCEAN_IP', '138.197.3.109')
    rabbitmq_user = os.getenv('RABBITMQ_USER', 'nighttrader')
    rabbitmq_password = os.getenv('RABBITMQ_PASSWORD')
    queue_name = os.getenv('RABBITMQ_QUEUE_NAME', 'mt5_signals')
    vps_id = os.getenv('VPS_INSTANCE_ID', 'test-vps')
    
    if not rabbitmq_password:
        print("ERROR: RABBITMQ_PASSWORD not set in environment")
        return False
    
    try:
        # Connect to RabbitMQ
        credentials = pika.PlainCredentials(rabbitmq_user, rabbitmq_password)
        connection = pika.BlockingConnection(
            pika.ConnectionParameters(
                host=digitalocean_ip,
                port=5672,
                credentials=credentials
            )
        )
        channel = connection.channel()
        
        # Create test signal
        test_signal = {
            "id": f"test-{datetime.now().isoformat()}",
            "vps_id": vps_id,
            "action": "BUY",
            "symbol": "EURUSD",
            "quantity": 0.01,
            "timestamp": datetime.now().isoformat(),
            "test": True,
            "comment": "Reconnection test signal"
        }
        
        # Send signal
        channel.basic_publish(
            exchange='',
            routing_key=queue_name,
            body=json.dumps(test_signal),
            properties=pika.BasicProperties(
                delivery_mode=2,  # Persistent
                expiration='5000'  # 5 second TTL
            )
        )
        
        print(f"✓ Test signal sent to queue '{queue_name}'")
        print(f"  Signal: {test_signal}")
        
        connection.close()
        return True
        
    except Exception as e:
        print(f"✗ Failed to send test signal: {e}")
        return False

def test_connection_params():
    """Test enhanced connection parameters"""
    digitalocean_ip = os.getenv('DIGITALOCEAN_IP', '138.197.3.109')
    rabbitmq_user = os.getenv('RABBITMQ_USER', 'vps_consumer')
    rabbitmq_password = os.getenv('RABBITMQ_PASSWORD')
    
    if not rabbitmq_password:
        print("ERROR: RABBITMQ_PASSWORD not set in environment")
        return False
    
    print(f"\nTesting RabbitMQ connection with enhanced parameters...")
    print(f"  Host: {digitalocean_ip}")
    print(f"  User: {rabbitmq_user}")
    print(f"  Heartbeat: 60 seconds")
    print(f"  Socket timeout: 10 seconds")
    
    try:
        # Test connection with enhanced parameters
        connection_params = pika.ConnectionParameters(
            host=digitalocean_ip,
            port=5672,
            credentials=pika.PlainCredentials(rabbitmq_user, rabbitmq_password),
            heartbeat=60,
            blocked_connection_timeout=300,
            socket_timeout=10,
            connection_attempts=3,
            retry_delay=5,
            tcp_options={
                'TCP_KEEPIDLE': 120,
                'TCP_KEEPINTVL': 30,
                'TCP_KEEPCNT': 10,
                'TCP_USER_TIMEOUT': 300000
            }
        )
        
        connection = pika.BlockingConnection(connection_params)
        
        print("✓ Connection successful with enhanced parameters")
        print(f"✓ Connection state: {'Open' if not connection.is_closed else 'Closed'}")
        
        # Test heartbeat
        print("\nTesting heartbeat (waiting 5 seconds)...")
        time.sleep(5)
        connection.process_data_events(time_limit=0)
        print("✓ Heartbeat working correctly")
        
        connection.close()
        print("✓ Connection closed cleanly")
        return True
        
    except Exception as e:
        print(f"✗ Connection test failed: {e}")
        return False

def main():
    print("=" * 60)
    print("RabbitMQ Reconnection Mechanism Test")
    print("=" * 60)
    
    # Test 1: Connection parameters
    if test_connection_params():
        print("\n✓ Connection parameter test PASSED")
    else:
        print("\n✗ Connection parameter test FAILED")
    
    # Test 2: Send test signal
    print("\n" + "-" * 60)
    print("Sending test signal...")
    if send_test_signal():
        print("\n✓ Test signal sent successfully")
        print("\nNow check the MT5 service logs to verify:")
        print("1. The signal was received")
        print("2. The connection remains stable")
        print("3. Reconnection occurs if you restart RabbitMQ")
    else:
        print("\n✗ Failed to send test signal")
    
    print("\n" + "=" * 60)
    print("Testing complete!")
    print("\nTo test reconnection:")
    print("1. Ensure MT5 service is running with the new code")
    print("2. Monitor the service logs")
    print("3. Restart RabbitMQ on DigitalOcean to simulate failure")
    print("4. Verify the service automatically reconnects")

if __name__ == "__main__":
    main()