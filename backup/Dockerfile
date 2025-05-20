FROM python:3.11-slim

# Install required Debian packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gawk \
    git \
    gnupg \
    jq \
    lsof \
    lynx \
    make \
    rsync \
    shellcheck \
    sqlite3 \
    tree \
    unzip \
    vim \
    wget \
    openssh-server \
    pwgen \
    cryptsetup \
    mailutils \
    libxml2-utils \
    msmtp \
    msmtp-mta \
    && rm -rf /var/lib/apt/lists/*

# Create necessary directories
ARG workdir=/opt/SBE
ARG reportdir=/var/SBE/reports
RUN mkdir -p $workdir \
    && mkdir -p $reportdir

# Set working directory
WORKDIR $workdir

# Copy requirements file
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY backup/ ./backup/
COPY keyserver/ ./keyserver/
COPY .env.example ./.env

# Make scripts executable
RUN find ./backup -name "*.py" -exec chmod +x {} \;

# Set default command
CMD ["python", "backup/main.py"]
