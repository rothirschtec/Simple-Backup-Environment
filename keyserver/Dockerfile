FROM python:3.11-slim

WORKDIR /app

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    openssl \
    && rm -rf /var/lib/apt/lists/*

# Download wait-for-it.sh into root
RUN curl -L -o /wait-for-it.sh https://raw.githubusercontent.com/vishnubob/wait-for-it/master/wait-for-it.sh && \
    chmod +x /wait-for-it.sh

# Copy requirements first to leverage Docker cache
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Generate self-signed SSL certificate for development
RUN mkdir -p /app/config/certs && \
    openssl req -x509 -newkey rsa:4096 -nodes -out /app/config/certs/cert.pem -keyout /app/config/certs/key.pem -days \
    365 -subj "/CN=sbe.keyserver"

# Create data directory for SQLite fallback
RUN mkdir -p /data

# Expose HTTPS port
EXPOSE 8443

# Command is omitted; Compose will use 'command: ["/wait-for-it.sh", ...]'
