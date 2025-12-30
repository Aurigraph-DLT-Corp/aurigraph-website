#!/bin/bash

#############################################################################
# Aurigraph Website - Centralized Logging Setup
#
# Configures Docker logging drivers and log rotation for all containers
# Supports JSON logging, syslog, and local file output
#############################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOGS_DIR="/var/log/aurigraph"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "📋 Aurigraph Website - Logging Setup"
echo "===================================="
echo "Timestamp: $TIMESTAMP"
echo "Logs Directory: $LOGS_DIR"
echo ""

# Create logs directory with proper permissions
echo "📁 Creating logs directory..."
sudo mkdir -p "$LOGS_DIR"/{docker,nginx,app,database}
sudo chmod 755 "$LOGS_DIR"
sudo chown -R syslog:syslog "$LOGS_DIR"

# Create log rotation configuration
echo "🔄 Setting up log rotation..."
sudo tee /etc/logrotate.d/aurigraph-website > /dev/null << 'EOF'
/var/log/aurigraph/**/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0640 syslog syslog
    sharedscripts
    postrotate
        systemctl reload rsyslog > /dev/null 2>&1 || true
        docker restart aurigraph-website aurigraph-nginx 2>/dev/null || true
    endscript
}
EOF
echo "✅ Log rotation configured (14 days retention)"

# Configure Docker daemon to use JSON logging driver
echo "⚙️  Configuring Docker logging driver..."
sudo tee /etc/docker/daemon.json > /dev/null << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "5",
    "labels": "service",
    "env": "NODE_ENV"
  },
  "storage-driver": "overlay2"
}
EOF

# Restart Docker to apply changes
echo "🔄 Restarting Docker daemon..."
sudo systemctl daemon-reload
sudo systemctl restart docker
sleep 5

# Configure container-specific logging
echo "📝 Configuring container logging..."

# Next.js Application logging
cat > "$PROJECT_ROOT/docker-compose.logging.yml" << 'DOCKER_EOF'
version: '3.9'

services:
  app:
    logging:
      driver: "json-file"
      options:
        max-size: "100m"
        max-file: "5"
        labels: "service=aurigraph-website,environment=production"
        env: "NODE_ENV,DATABASE_URL"
    volumes:
      - /var/log/aurigraph/app:/app/.next/logs

  db:
    logging:
      driver: "json-file"
      options:
        max-size: "50m"
        max-file: "5"
        labels: "service=aurigraph-db,environment=production"
    environment:
      - POSTGRES_INITDB_ARGS=-c log_statement=all -c log_min_duration_statement=1000

  nginx:
    logging:
      driver: "json-file"
      options:
        max-size: "100m"
        max-file: "5"
        labels: "service=aurigraph-nginx,environment=production"
    volumes:
      - /var/log/aurigraph/nginx:/var/log/nginx
DOCKER_EOF

# Create log monitoring script
echo "📊 Creating log monitoring utility..."
cat > "$PROJECT_ROOT/scripts/monitor-logs.sh" << 'MONITOR_EOF'
#!/bin/bash

# Monitor real-time logs from all containers

echo "🔍 Aurigraph Website - Log Monitor"
echo "=================================="
echo "Press Ctrl+C to exit"
echo ""

# Monitor all containers
docker-compose -f ~/aurigraph-website/docker-compose.production.yml logs -f \
  --timestamps \
  -n 100 \
  aurigraph-website aurigraph-db aurigraph-nginx 2>/dev/null || \
  echo "⚠️  Docker containers not found. Starting monitoring..."

MONITOR_EOF

chmod +x "$PROJECT_ROOT/scripts/monitor-logs.sh"

# Create log analysis script
echo "📈 Creating log analysis utility..."
cat > "$PROJECT_ROOT/scripts/analyze-logs.sh" << 'ANALYZE_EOF'
#!/bin/bash

# Analyze logs for errors and warnings

LOGS_DIR="/var/log/aurigraph"
DAYS=${1:-1}

echo "📊 Aurigraph Website - Log Analysis (Last $DAYS day(s))"
echo "====================================================="
echo ""

# Find logs
echo "🔴 ERRORS:"
find "$LOGS_DIR" -type f -name "*.log" -mtime -$DAYS -exec grep -l "ERROR\|error\|Error" {} \; 2>/dev/null | while read logfile; do
    echo "  File: $logfile"
    grep "ERROR\|error\|Error" "$logfile" | tail -5
done

echo ""
echo "🟡 WARNINGS:"
find "$LOGS_DIR" -type f -name "*.log" -mtime -$DAYS -exec grep -l "WARN\|warn\|Warning" {} \; 2>/dev/null | while read logfile; do
    echo "  File: $logfile"
    grep "WARN\|warn\|Warning" "$logfile" | tail -5
done

echo ""
echo "📝 LOG SIZES:"
du -sh "$LOGS_DIR"/* 2>/dev/null

echo ""
echo "⏰ RECENT ACTIVITY:"
find "$LOGS_DIR" -type f -name "*.log" -mtime -$DAYS -exec ls -lh {} \; | tail -10

ANALYZE_EOF

chmod +x "$PROJECT_ROOT/scripts/analyze-logs.sh"

# Create log export script for archival
echo "💾 Creating log archival utility..."
cat > "$PROJECT_ROOT/scripts/archive-logs.sh" << 'ARCHIVE_EOF'
#!/bin/bash

# Archive and compress old logs

LOGS_DIR="/var/log/aurigraph"
ARCHIVE_DIR="${LOGS_DIR}/archive"
DAYS=${1:-30}

mkdir -p "$ARCHIVE_DIR"

echo "📦 Archiving logs older than $DAYS days..."

find "$LOGS_DIR" -type f -name "*.log" -mtime +$DAYS | while read logfile; do
    gzip "$logfile" 2>/dev/null && \
    mv "${logfile}.gz" "$ARCHIVE_DIR/" && \
    echo "✓ Archived: $(basename $logfile)"
done

echo "✅ Archive complete"
echo "📊 Archive size: $(du -sh $ARCHIVE_DIR)"

ARCHIVE_EOF

chmod +x "$PROJECT_ROOT/scripts/archive-logs.sh"

# Test logging
echo "🧪 Testing container logging..."
docker ps --filter "name=aurigraph" --format "table {{.Names}}\t{{.Status}}" || \
    echo "⚠️  No running containers found"

# Summary
echo ""
echo "✅ Logging Setup Complete!"
echo "===================================="
echo ""
echo "📁 Log Locations:"
echo "  - Docker logs: /var/lib/docker/containers/*/*-json.log"
echo "  - Application logs: $LOGS_DIR/app/"
echo "  - NGINX logs: $LOGS_DIR/nginx/"
echo "  - Database logs: $LOGS_DIR/database/"
echo ""
echo "🔧 Available Commands:"
echo "  - View logs: ./scripts/monitor-logs.sh"
echo "  - Analyze logs: ./scripts/analyze-logs.sh [days]"
echo "  - Archive logs: ./scripts/archive-logs.sh [days]"
echo ""
echo "⚙️  Log Rotation:"
echo "  - Daily rotation with 14-day retention"
echo "  - Max file size: 100MB"
echo "  - Compression enabled"
echo ""
echo "📋 Configuration Files:"
echo "  - Docker: /etc/docker/daemon.json"
echo "  - Rotation: /etc/logrotate.d/aurigraph-website"
echo "  - Compose: $PROJECT_ROOT/docker-compose.logging.yml"
