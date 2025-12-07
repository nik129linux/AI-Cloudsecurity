#!/bin/bash

# Bastion Host Bootstrap Script
# This script runs on first boot to configure the bastion host

# Variables
REGION=${region}
LOG_FILE="/var/log/user_data.log"

# Function to log with timestamp
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a $LOG_FILE
}

log "Starting bastion host bootstrap process"

# Update system
log "Updating system packages"
yum update -y

# Install essential tools
log "Installing essential tools"
yum install -y \
    htop \
    tree \
    wget \
    curl \
    unzip \
    jq \
    git

# Install AWS CLI v2 (if not present)
log "Installing AWS CLI v2"
if ! command -v aws &> /dev/null; then
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    ./aws/install
    rm -rf aws awscliv2.zip
fi

# Install Session Manager plugin
log "Installing Session Manager plugin"
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm" -o "session-manager-plugin.rpm"
yum install -y session-manager-plugin.rpm
rm -f session-manager-plugin.rpm

# Configure SSH hardening
log "Configuring SSH hardening"
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

cat > /etc/ssh/sshd_config.d/99-hardening.conf <<EOF
# SSH Hardening Configuration
Protocol 2
Port 22

# Authentication
PermitRootLogin no
PasswordAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys

# Security
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
PermitTunnel no
GatewayPorts no

# Logging
LogLevel VERBOSE
SyslogFacility AUTHPRIV

# Session
ClientAliveInterval 300
ClientAliveCountMax 2
MaxAuthTries 3
MaxSessions 2
MaxStartups 2

# Algorithms
KexAlgorithms curve25519-sha256@libssh.org,ecdh-sha2-nistp256,ecdh-sha2-nistp384,ecdh-sha2-nistp521
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,hmac-sha2-256,hmac-sha2-512
EOF

# Restart SSH service
log "Restarting SSH service"
systemctl restart sshd

# Create a welcome banner
log "Creating welcome banner"
cat > /etc/motd <<EOF

🛡️  BASTION HOST - AUTHORIZED ACCESS ONLY 🛡️

This is a secure bastion host for accessing private resources.
All activities are logged and monitored.

Environment: Development
Region: $REGION

Available tools:
- AWS CLI v2
- Session Manager
- Standard debugging tools (htop, curl, jq, etc.)

Use Session Manager for secure shell access to private instances.

EOF

# Configure fail2ban for additional security
log "Installing and configuring fail2ban"
yum install -y fail2ban

cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
backend = systemd

[sshd]
enabled = true
port = ssh
logpath = %(sshd_log)s
backend = %(sshd_backend)s
banaction = iptables-multiport
banaction_allports = iptables-allports
EOF

systemctl start fail2ban
systemctl enable fail2ban

# Install and configure CloudWatch agent
log "Installing CloudWatch agent"
yum install -y amazon-cloudwatch-agent

cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<EOF
{
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/secure",
                        "log_group_name": "/aws/ec2/bastion/auth",
                        "log_stream_name": "{instance_id}"
                    },
                    {
                        "file_path": "/var/log/fail2ban.log",
                        "log_group_name": "/aws/ec2/bastion/fail2ban",
                        "log_stream_name": "{instance_id}"
                    }
                ]
            }
        }
    },
    "metrics": {
        "namespace": "CustomMetrics/Bastion",
        "metrics_collected": {
            "cpu": {
                "measurement": ["cpu_usage_idle", "cpu_usage_iowait"],
                "metrics_collection_interval": 60
            },
            "disk": {
                "measurement": ["used_percent"],
                "metrics_collection_interval": 60,
                "resources": ["*"]
            },
            "mem": {
                "measurement": ["mem_used_percent"],
                "metrics_collection_interval": 60
            }
        }
    }
}
EOF

systemctl start amazon-cloudwatch-agent
systemctl enable amazon-cloudwatch-agent

log "Bastion host bootstrap completed successfully"