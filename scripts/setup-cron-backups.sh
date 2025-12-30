#!/bin/bash

#############################################################################
# Aurigraph Website - Setup Automated Backups via Cron
#
# Configures automated daily database backups with:
# - Daily full backups at 2 AM
# - Weekly backups with extended retention
# - Health checks and email notifications
#############################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKUP_SCRIPT="${SCRIPT_DIR}/backup-database.sh"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@aurigraph.io}"

echo "🔧 Aurigraph Website - Automated Backup Setup"
echo "=============================================="
echo ""

# Make backup script executable
chmod +x "$BACKUP_SCRIPT"
chmod +x "${SCRIPT_DIR}/monitor-logs.sh"
chmod +x "${SCRIPT_DIR}/analyze-logs.sh"
chmod +x "${SCRIPT_DIR}/archive-logs.sh"

# Create backup directory
sudo mkdir -p /var/backups/aurigraph-website
sudo chmod 750 /var/backups/aurigraph-website
sudo chown -R root:root /var/backups/aurigraph-website

# Create cron job file
echo "⚙️  Setting up cron schedules..."
sudo tee /etc/cron.d/aurigraph-website-backups > /dev/null << 'CRON_EOF'
# Aurigraph Website Backup Schedule
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
MAILTO=admin@aurigraph.io

# Daily backups at 2 AM
0 2 * * * root /home/subbu/aurigraph-website/scripts/backup-database.sh >> /var/log/aurigraph-backups.log 2>&1

# Weekly extended backup on Sunday at 3 AM (retention: 90 days)
0 3 * * 0 root RETENTION_DAYS=90 /home/subbu/aurigraph-website/scripts/backup-database.sh >> /var/log/aurigraph-backups.log 2>&1

# Backup health check - runs daily at 3:30 AM
30 3 * * * root /home/subbu/aurigraph-website/scripts/check-backup-health.sh >> /var/log/aurigraph-backups.log 2>&1

# Log analysis - runs daily at 4 AM
0 4 * * * root /home/subbu/aurigraph-website/scripts/analyze-logs.sh 1 >> /var/log/aurigraph-logs-analysis.log 2>&1

# Archive old logs - runs weekly on Saturday at 4:30 AM
30 4 * * 6 root /home/subbu/aurigraph-website/scripts/archive-logs.sh 30 >> /var/log/aurigraph-logs-archive.log 2>&1
CRON_EOF

echo "✅ Cron jobs configured"

# Create backup health check script
echo "📋 Creating backup health check script..."
sudo tee "${SCRIPT_DIR}/check-backup-health.sh" > /dev/null << 'HEALTH_CHECK_EOF'
#!/bin/bash

# Check backup integrity and health

BACKUP_DIR="/var/backups/aurigraph-website"
ALERT_EMAIL="admin@aurigraph.io"
ALERT_THRESHOLD_HOURS=25

check_last_backup() {
    local last_backup=$(ls -dt "$BACKUP_DIR"/*/ 2>/dev/null | head -1)

    if [ -z "$last_backup" ]; then
        echo "ERROR: No backups found in $BACKUP_DIR"
        send_alert "No backups found"
        return 1
    fi

    local backup_time=$(stat -c %Y "$last_backup")
    local current_time=$(date +%s)
    local hours_old=$(( (current_time - backup_time) / 3600 ))

    if [ $hours_old -gt $ALERT_THRESHOLD_HOURS ]; then
        echo "WARNING: Last backup is $hours_old hours old (threshold: $ALERT_THRESHOLD_HOURS hours)"
        send_alert "Backup is stale: $hours_old hours old"
        return 1
    fi

    echo "✅ Last backup: $hours_old hours ago"
    return 0
}

check_backup_size() {
    local total_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
    echo "Backup repository size: $total_size"
}

check_disk_space() {
    local disk_usage=$(df /var/backups | awk 'NR==2 {print $5}' | sed 's/%//')

    if [ "$disk_usage" -gt 80 ]; then
        echo "WARNING: Disk usage at ${disk_usage}% (alert: >80%)"
        send_alert "Backup disk space critical: ${disk_usage}% used"
        return 1
    fi

    echo "✅ Disk usage: $disk_usage%"
    return 0
}

check_backup_files() {
    local last_backup=$(ls -dt "$BACKUP_DIR"/*/ 2>/dev/null | head -1)
    local file_count=$(find "$last_backup" -type f 2>/dev/null | wc -l)

    if [ "$file_count" -lt 3 ]; then
        echo "ERROR: Incomplete backup - only $file_count files found"
        send_alert "Incomplete backup detected"
        return 1
    fi

    echo "✅ Backup files: $file_count"
    return 0
}

send_alert() {
    local message=$1
    echo "Sending alert: $message"

    # Option 1: Send via mail command if available
    if command -v mail &> /dev/null; then
        echo "$message" | mail -s "⚠️  Aurigraph Backup Alert" "$ALERT_EMAIL"
    fi

    # Option 2: Log to syslog
    logger -t aurigraph-backup-health "ALERT: $message"
}

main() {
    echo "Checking backup health..."
    check_last_backup || true
    check_backup_size
    check_disk_space || true
    check_backup_files || true
    echo "Health check complete"
}

main "$@"
HEALTH_CHECK_EOF

sudo chmod +x "${SCRIPT_DIR}/check-backup-health.sh"

# Create restore instructions
echo "📖 Creating restore procedure documentation..."
sudo tee "${SCRIPT_DIR}/RESTORE_PROCEDURES.md" > /dev/null << 'RESTORE_EOF'
# Aurigraph Website Database Restore Procedures

## Emergency Recovery

### Option 1: Restore from SQL Dump (Recommended)

```bash
# Decompress and restore
cd /var/backups/aurigraph-website/[TIMESTAMP]/
gunzip -c aurigraph_website_[TIMESTAMP].sql.gz | docker exec -i aurigraph-db psql -U aurigraph -d aurigraph_website
```

### Option 2: Restore from Custom Format (Faster for Large Databases)

```bash
# Parallel restore (4 jobs)
docker exec -i aurigraph-db pg_restore \
  -U aurigraph \
  -d aurigraph_website \
  -j 4 \
  /backups/aurigraph_website_[TIMESTAMP].custom
```

### Option 3: Restore Individual Table

```bash
# Restore a single table
cd /var/backups/aurigraph-website/[TIMESTAMP]/tables/
gunzip -c contact_submissions_[TIMESTAMP].sql.gz | docker exec -i aurigraph-db psql -U aurigraph -d aurigraph_website
```

## Point-in-Time Recovery (PITR)

Not yet configured. To enable PITR:

1. Enable WAL archiving in PostgreSQL
2. Archive WAL files to external storage
3. Use `pg_restore` with recovery target timeline

## Backup Listing

```bash
# List all available backups
ls -la /var/backups/aurigraph-website/

# View backup contents
tar -tzf /var/backups/aurigraph-website/[TIMESTAMP]/aurigraph_website_[TIMESTAMP].sql.gz | head -20
```

## Verification Before Restore

```bash
# Check backup integrity
gzip -t /var/backups/aurigraph-website/[TIMESTAMP]/*.gz

# Verify database syntax
psql -U aurigraph < /var/backups/aurigraph-website/[TIMESTAMP]/aurigraph_website_[TIMESTAMP].sql --dry-run
```

## Post-Restore Verification

```bash
# Connect to database
docker exec -it aurigraph-db psql -U aurigraph -d aurigraph_website

# Run verification queries
SELECT COUNT(*) FROM website.contact_submissions;
SELECT COUNT(*) FROM website.form_analytics;
SELECT NOW();
```

## Disaster Recovery Plan

1. **Database Loss**: Restore latest backup
2. **Partial Data Loss**: Restore and run recovery query
3. **Container Failure**: Rebuild from Docker image + restore latest backup
4. **Server Failure**: Rebuild infrastructure and restore from backup

## Support

For recovery assistance, contact: admin@aurigraph.io
RESTORE_EOF

# Create status report
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "✅ Automated Backup Setup Complete!"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "📅 Backup Schedule:"
echo "   • Daily: 2:00 AM UTC"
echo "   • Weekly (extended): 3:00 AM UTC on Sundays"
echo ""
echo "⏰ Other Scheduled Tasks:"
echo "   • Backup health check: 3:30 AM UTC"
echo "   • Log analysis: 4:00 AM UTC"
echo "   • Log archival: 4:30 AM UTC on Saturdays"
echo ""
echo "📂 Backup Location:"
echo "   /var/backups/aurigraph-website/"
echo ""
echo "📋 Available Commands:"
echo "   • Manual backup: bash ${BACKUP_SCRIPT}"
echo "   • Health check: bash ${SCRIPT_DIR}/check-backup-health.sh"
echo "   • Restore: See ${SCRIPT_DIR}/RESTORE_PROCEDURES.md"
echo ""
echo "📊 Cron Log:"
echo "   /var/log/aurigraph-backups.log"
echo ""
echo "🔔 Alerts:"
echo "   Email: $ADMIN_EMAIL"
echo "   Syslog: logger -t aurigraph-backup"
echo ""
echo "════════════════════════════════════════════════════════════════"
