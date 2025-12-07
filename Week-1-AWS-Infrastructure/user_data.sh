#!/bin/bash

# Web Server Bootstrap Script
# This script runs on first boot to configure the web server

# Variables
REGION=${region}
LOG_FILE="/var/log/user_data.log"

# Function to log with timestamp
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a $LOG_FILE
}

log "Starting web server bootstrap process"

# Update system
log "Updating system packages"
yum update -y

# Install CloudWatch agent
log "Installing CloudWatch agent"
yum install -y amazon-cloudwatch-agent

# Install Apache web server
log "Installing Apache HTTP server"
yum install -y httpd

# Install SSL module
log "Installing SSL module"
yum install -y mod_ssl

# Configure Apache
log "Configuring Apache"
systemctl start httpd
systemctl enable httpd

# Create a simple web page with security headers
log "Creating web content"
cat > /var/www/html/index.html <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Secure Web Server</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 40px;
            background-color: #f5f5f5;
        }
        .container {
            background-color: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            max-width: 600px;
            margin: 0 auto;
        }
        .status {
            color: #28a745;
            font-weight: bold;
        }
        .security-info {
            background-color: #e9f5ff;
            padding: 15px;
            border-radius: 4px;
            margin-top: 20px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🛡️ Secure Web Server</h1>
        <p class="status">✅ Server is running securely!</p>
        <p><strong>Deployment:</strong> Enterprise-grade Terraform Infrastructure</p>
        <p><strong>Instance ID:</strong> <span id="instance-id">Loading...</span></p>
        <p><strong>Region:</strong> $REGION</p>

        <div class="security-info">
            <h3>🔐 Security Features Enabled:</h3>
            <ul>
                <li>Private subnet deployment</li>
                <li>Application Load Balancer</li>
                <li>Security groups with minimal permissions</li>
                <li>EBS encryption</li>
                <li>IMDSv2 required</li>
                <li>VPC Flow Logs</li>
                <li>Auto Scaling Group</li>
            </ul>
        </div>
    </div>

    <script>
        // Fetch instance metadata (IMDSv2)
        fetch('http://169.254.169.254/latest/api/token', {
            method: 'PUT',
            headers: {
                'X-aws-ec2-metadata-token-ttl-seconds': '21600'
            }
        })
        .then(response => response.text())
        .then(token => {
            return fetch('http://169.254.169.254/latest/meta-data/instance-id', {
                headers: {
                    'X-aws-ec2-metadata-token': token
                }
            });
        })
        .then(response => response.text())
        .then(instanceId => {
            document.getElementById('instance-id').textContent = instanceId;
        })
        .catch(() => {
            document.getElementById('instance-id').textContent = 'Not available';
        });
    </script>
</body>
</html>
EOF

# Configure security headers
log "Configuring security headers"
cat > /etc/httpd/conf.d/security.conf <<EOF
# Security Headers
Header always set X-Frame-Options "DENY"
Header always set X-Content-Type-Options "nosniff"
Header always set X-XSS-Protection "1; mode=block"
Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"
Header always set Referrer-Policy "strict-origin-when-cross-origin"
Header always set Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'"

# Server signature
ServerTokens Prod
ServerSignature Off

# Hide Apache version
Header unset Server
Header always set Server "WebServer"
EOF

# Start services
log "Starting services"
systemctl restart httpd

# Configure CloudWatch agent (basic config)
log "Configuring CloudWatch agent"
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<EOF
{
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/httpd/access_log",
                        "log_group_name": "/aws/ec2/apache/access",
                        "log_stream_name": "{instance_id}"
                    },
                    {
                        "file_path": "/var/log/httpd/error_log",
                        "log_group_name": "/aws/ec2/apache/error",
                        "log_stream_name": "{instance_id}"
                    }
                ]
            }
        }
    },
    "metrics": {
        "namespace": "CustomMetrics/WebServer",
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

# Start CloudWatch agent
log "Starting CloudWatch agent"
systemctl start amazon-cloudwatch-agent
systemctl enable amazon-cloudwatch-agent

log "Web server bootstrap completed successfully"