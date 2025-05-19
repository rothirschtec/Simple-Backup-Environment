#!/usr/bin/env python3
"""
SBE Key Server - Encryption key management API for SBE backups
"""

import os
import logging
from flask import Flask, request, jsonify
from flask_restful import Api, Resource
from cryptography.fernet import Fernet
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
import base64
import sqlalchemy as sa
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
import datetime
import time
import jwt
import secrets
from dotenv import load_dotenv
import ssl

# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Flask application
app = Flask(__name__)
api = Api(app)

# Configuration
API_KEY = os.environ.get("API_KEY")
if not API_KEY:
    logger.warning("No API_KEY environment variable found. Generating a random key.")
    API_KEY = secrets.token_hex(32)
    logger.warning(f"Generated API_KEY: {API_KEY}")

# Database setup
POSTGRES_USER = os.environ.get("POSTGRES_USER")
POSTGRES_PASSWORD = os.environ.get("POSTGRES_PASSWORD")
POSTGRES_DB = os.environ.get("POSTGRES_DB")

if POSTGRES_USER and POSTGRES_PASSWORD and POSTGRES_DB:
    DB_URI = f"postgresql://{POSTGRES_USER}:{POSTGRES_PASSWORD}@sbe-keyserver-db/{POSTGRES_DB}"
else:
    logger.warning("PostgreSQL environment variables not found. Using SQLite as fallback.")
    DB_URI = "sqlite:////data/keyserver.db"

# Database model
Base = declarative_base()

class EncryptionKey(Base):
    __tablename__ = 'encryption_keys'
    
    id = sa.Column(sa.Integer, primary_key=True)
    hostname = sa.Column(sa.String, unique=True, nullable=False)
    encrypted_key = sa.Column(sa.String, nullable=False)
    created_at = sa.Column(sa.DateTime, default=datetime.datetime.utcnow)
    updated_at = sa.Column(sa.DateTime, default=datetime.datetime.utcnow, onupdate=datetime.datetime.utcnow)

# Create database engine and session
engine = sa.create_engine(DB_URI)
Base.metadata.create_all(engine)
Session = sessionmaker(bind=engine)

# Encryption helpers
def derive_key(master_key):
    """Derive an encryption key from the master API key"""
    kdf = PBKDF2HMAC(
        algorithm=hashes.SHA256(),
        length=32,
        salt=b'SBE-KeyServer-Static-Salt',  # In production, use a secure random salt
        iterations=100000
    )
    return base64.urlsafe_b64encode(kdf.derive(master_key.encode()))

def encrypt_value(value, key):
    """Encrypt a value using the derived key"""
    f = Fernet(key)
    return f.encrypt(value.encode()).decode()

def decrypt_value(encrypted_value, key):
    """Decrypt a value using the derived key"""
    f = Fernet(key)
    return f.decrypt(encrypted_value.encode()).decode()

# Authentication decorator
def require_api_key(func):
    def wrapper(*args, **kwargs):
        auth_header = request.headers.get('Authorization')
        if not auth_header or not auth_header.startswith('Bearer '):
            return {"error": "Unauthorized: Missing or invalid Authorization header"}, 401
        
        token = auth_header.split(' ')[1]
        if token != API_KEY:
            return {"error": "Unauthorized: Invalid API key"}, 401
        
        return func(*args, **kwargs)
    return wrapper

# API Resources
class KeyResource(Resource):
    @require_api_key
    def post(self):
        """Store an encryption key for a hostname"""
        data = request.get_json()
        
        if not data or 'hostname' not in data or 'key' not in data:
            return {"error": "Missing required fields: hostname and key"}, 400
        
        hostname = data['hostname']
        key_value = data['key']
        
        try:
            derived_key = derive_key(API_KEY)
            encrypted_key = encrypt_value(key_value, derived_key)
            
            session = Session()
            
            # Check if hostname already exists
            existing_key = session.query(EncryptionKey).filter_by(hostname=hostname).first()
            
            if existing_key:
                # Update existing key
                existing_key.encrypted_key = encrypted_key
                existing_key.updated_at = datetime.datetime.utcnow()
                message = "Encryption key updated"
            else:
                # Create new key
                new_key = EncryptionKey(hostname=hostname, encrypted_key=encrypted_key)
                session.add(new_key)
                message = "Encryption key stored"
                
            session.commit()
            
            logger.info(f"{message} for hostname: {hostname}")
            return {"message": message}, 200
            
        except Exception as e:
            logger.error(f"Error storing key: {str(e)}")
            return {"error": f"Internal server error: {str(e)}"}, 500
        finally:
            session.close()
    
    @require_api_key
    def get(self, hostname):
        """Retrieve an encryption key for a hostname"""
        try:
            session = Session()
            key_entry = session.query(EncryptionKey).filter_by(hostname=hostname).first()
            
            if not key_entry:
                logger.warning(f"Key not found for hostname: {hostname}")
                return {"error": "Key not found"}, 404
            
            derived_key = derive_key(API_KEY)
            decrypted_key = decrypt_value(key_entry.encrypted_key, derived_key)
            
            logger.info(f"Key retrieved for hostname: {hostname}")
            return {"hostname": hostname, "key": decrypted_key}, 200
            
        except Exception as e:
            logger.error(f"Error retrieving key: {str(e)}")
            return {"error": f"Internal server error: {str(e)}"}, 500
        finally:
            session.close()
    
    @require_api_key
    def delete(self, hostname):
        """Delete an encryption key for a hostname"""
        try:
            session = Session()
            key_entry = session.query(EncryptionKey).filter_by(hostname=hostname).first()
            
            if not key_entry:
                logger.warning(f"Key not found for hostname: {hostname}")
                return {"error": "Key not found"}, 404
            
            session.delete(key_entry)
            session.commit()
            
            logger.info(f"Key deleted for hostname: {hostname}")
            return {"message": "Encryption key deleted"}, 200
            
        except Exception as e:
            logger.error(f"Error deleting key: {str(e)}")
            return {"error": f"Internal server error: {str(e)}"}, 500
        finally:
            session.close()

class HealthResource(Resource):
    def get(self):
        """Health check endpoint"""
        return {"status": "healthy", "timestamp": time.time()}, 200

# API Routes
api.add_resource(KeyResource, '/api/keys', '/api/keys/<string:hostname>')
api.add_resource(HealthResource, '/health')

# Main application entry point
if __name__ == '__main__':
    # Check for SSL certificate
    cert_path = '/app/config/certs/cert.pem'
    key_path = '/app/config/certs/key.pem'
    
    if os.path.exists(cert_path) and os.path.exists(key_path):
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(cert_path, key_path)
        logger.info("Starting HTTPS server on port 8443")
        app.run(host='0.0.0.0', port=8443, ssl_context=context)
    else:
        logger.warning("SSL certificates not found. Starting in HTTP mode (not recommended for production)")
        app.run(host='0.0.0.0', port=8443)
