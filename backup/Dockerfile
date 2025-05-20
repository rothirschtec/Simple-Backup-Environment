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
RUN mkdir -p /opt/SBE \
    && mkdir -p /var/SBE/reports

# Set working directory
WORKDIR /opt/SBE

# Copy requirements file
COPY requirements.txt /opt/SBE/

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Create separate wrapper script files
RUN mkdir -p /tmp/wrapper_scripts

# add_host wrapper
RUN echo '#!/bin/bash' > /tmp/wrapper_scripts/add_host && \
    echo 'python3 /opt/SBE/backup/tools/add_host.py "$@"' >> /tmp/wrapper_scripts/add_host

# mount_backup wrapper
RUN echo '#!/bin/bash' > /tmp/wrapper_scripts/mount_backup && \
    echo 'python3 /opt/SBE/backup/tools/mount.py "$@"' >> /tmp/wrapper_scripts/mount_backup

# backup_status wrapper
RUN echo '#!/bin/bash' > /tmp/wrapper_scripts/backup_status && \
    echo 'python3 /opt/SBE/backup/status.py "$@"' >> /tmp/wrapper_scripts/backup_status

# backup_scheduler wrapper
RUN echo '#!/bin/bash' > /tmp/wrapper_scripts/backup_scheduler && \
    echo 'python3 /opt/SBE/backup/main.py "$@"' >> /tmp/wrapper_scripts/backup_scheduler

# Move scripts to /usr/local/bin and make executable
RUN mv /tmp/wrapper_scripts/* /usr/local/bin/ && \
    chmod +x /usr/local/bin/add_host \
             /usr/local/bin/mount_backup \
             /usr/local/bin/backup_status \
             /usr/local/bin/backup_scheduler && \
    rmdir /tmp/wrapper_scripts

# Set default command
CMD ["python3", "/opt/SBE/backup/main.py"]
