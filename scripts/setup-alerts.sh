#!/bin/bash

#############################################################################
# Aurigraph Website - Alert Management & Email Notifications Setup
#
# Configures:
# - Prometheus Alertmanager for alert routing
# - Email notifications (SMTP)
# - Alert thresholds and escalation
# - Slack/Discord integrations (optional)
#############################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MONITORING_DIR="${PROJECT_ROOT}/monitoring"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@aurigraph.io}"
SMTP_SERVER="${SMTP_SERVER:-smtp.gmail.com}"
SMTP_PORT="${SMTP_PORT:-587}"

echo "🚨 Aurigraph Website - Alert Management Setup"
echo "=============================================="
echo ""

# Create Alertmanager configuration
echo "⚙️  Configuring Alertmanager..."
mkdir -p "$MONITORING_DIR/alertmanager"

cat > "$MONITORING_DIR/alertmanager/alertmanager.yml" << 'ALERTMANAGER_EOF'
global:
  resolve_timeout: 5m
  # SMTP configuration for email notifications
  smtp_smarthost: 'smtp.gmail.com:587'
  smtp_auth_username: '${SMTP_USERNAME}'
  smtp_auth_password: '${SMTP_PASSWORD}'
  smtp_require_tls: true
  smtp_from: 'alerts@aurigraph.io'

# Alert routing
route:
  receiver: 'default'
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 12h

  # Nested routes for specific alert types
  routes:
    # Critical alerts - immediate notification
    - match:
        severity: critical
      receiver: 'critical-alerts'
      group_wait: 0s
      group_interval: 2m
      repeat_interval: 1h

    # Warning alerts - less frequent
    - match:
        severity: warning
      receiver: 'warning-alerts'
      group_wait: 5m
      group_interval: 15m
      repeat_interval: 6h

    # Backup alerts - daily digest
    - match:
        alertname: 'BackupFailure'
      receiver: 'backup-alerts'
      group_wait: 1h
      repeat_interval: 24h

# Receivers - notification channels
receivers:
  - name: 'default'
    email_configs:
      - to: 'admin@aurigraph.io'
        headers:
          Subject: '[Aurigraph] {{ .GroupLabels.alertname }}'
        html: |
          {{ range .Alerts }}
          <b>Alert:</b> {{ .Labels.alertname }}<br/>
          <b>Severity:</b> {{ .Labels.severity }}<br/>
          <b>Description:</b> {{ .Annotations.description }}<br/>
          <b>Time:</b> {{ .StartsAt.Format "2006-01-02 15:04:05" }}<br/>
          {{ end }}

  - name: 'critical-alerts'
    email_configs:
      - to: 'admin@aurigraph.io'
        headers:
          Subject: '🚨 [CRITICAL] {{ .GroupLabels.alertname }}'
        html: |
          <h2 style="color: red;">🚨 CRITICAL ALERT</h2>
          {{ range .Alerts }}
          <p>
          <b>Alert:</b> {{ .Labels.alertname }}<br/>
          <b>Description:</b> {{ .Annotations.description }}<br/>
          <b>Details:</b> {{ .Annotations.summary }}<br/>
          <b>Started At:</b> {{ .StartsAt.Format "2006-01-02 15:04:05 MST" }}<br/>
          </p>
          {{ end }}
          <p style="color: red;"><b>Immediate action required!</b></p>

  - name: 'warning-alerts'
    email_configs:
      - to: 'admin@aurigraph.io'
        headers:
          Subject: '⚠️ [WARNING] {{ .GroupLabels.alertname }}'
        html: |
          <h2 style="color: orange;">⚠️ WARNING</h2>
          {{ range .Alerts }}
          <p>
          <b>Alert:</b> {{ .Labels.alertname }}<br/>
          <b>Description:</b> {{ .Annotations.description }}<br/>
          <b>Time:</b> {{ .StartsAt.Format "2006-01-02 15:04:05" }}<br/>
          </p>
          {{ end }}

  - name: 'backup-alerts'
    email_configs:
      - to: 'admin@aurigraph.io'
        headers:
          Subject: '[Aurigraph] Daily Backup Status'
        html: |
          <h2>Daily Backup Status Report</h2>
          {{ range .Alerts }}
          <p>
          <b>{{ .Labels.alertname }}</b><br/>
          {{ .Annotations.description }}<br/>
          Time: {{ .StartsAt.Format "2006-01-02 15:04:05" }}
          </p>
          {{ end }}

# Inhibition rules - suppress certain alerts when others are firing
inhibit_rules:
  # Don't send error alerts if the service is down
  - source_match:
      severity: 'critical'
      alertname: 'WebsiteContainerDown'
    target_match:
      severity: 'warning'
    equal: ['service']

  # Don't send memory alerts if disk is full
  - source_match:
      severity: 'critical'
      alertname: 'LowDiskSpace'
    target_match:
      alertname: 'HighMemoryUsage'
    equal: ['instance']
ALERTMANAGER_EOF

# Create alert webhook configuration
echo "🔗 Creating alert webhook configuration..."
cat > "$MONITORING_DIR/alertmanager/webhook-config.json" << 'WEBHOOK_EOF'
{
  "slack": {
    "webhook_url": "${SLACK_WEBHOOK_URL}",
    "channel": "#alerts",
    "username": "Prometheus Alertmanager",
    "icon_emoji": ":warning:"
  },
  "discord": {
    "webhook_url": "${DISCORD_WEBHOOK_URL}"
  },
  "pagerduty": {
    "integration_key": "${PAGERDUTY_KEY}",
    "severity_mapping": {
      "critical": "critical",
      "warning": "warning"
    }
  }
}
EOF

# Create alert dashboard template
echo "📊 Creating alert dashboard..."
cat > "$MONITORING_DIR/grafana/dashboards/alerts-dashboard.json" << 'ALERTS_DASHBOARD_EOF'
{
  "dashboard": {
    "title": "Aurigraph Alerts & Status",
    "panels": [
      {
        "title": "Active Alerts",
        "targets": [
          {"expr": "ALERTS{severity=\"critical\"}"},
          {"expr": "ALERTS{severity=\"warning\"}"}
        ],
        "type": "table"
      },
      {
        "title": "Alert History (24h)",
        "targets": [{"expr": "changes(ALERTS[24h])"}],
        "type": "graph"
      },
      {
        "title": "Service Status",
        "targets": [
          {"expr": "up{job=\"aurigraph-website\"}"},
          {"expr": "up{job=\"postgres\"}"},
          {"expr": "up{job=\"nginx\"}"}
        ],
        "type": "table"
      },
      {
        "title": "Alert Firing Rate",
        "targets": [{"expr": "rate(alerts_fired_total[5m])"}],
        "type": "stat"
      },
      {
        "title": "Last Alert Time",
        "targets": [{"expr": "time() - max(ALERTS)"}],
        "type": "stat"
      }
    ]
  }
}
EOF

# Create alert escalation policy
echo "📋 Creating alert escalation policy..."
cat > "$MONITORING_DIR/alertmanager/escalation-policy.md" << 'ESCALATION_EOF'
# Aurigraph Alert Escalation Policy

## Severity Levels

### CRITICAL 🚨
- Service unavailable or severe data loss risk
- Immediate action required (< 5 minutes)
- Notifications: Email + SMS + Phone call (if configured)
- Response time: 15 minutes
- Escalation: On-call engineer after 15 minutes

**Examples:**
- Container down (database, website, nginx)
- Backup failure
- Database connection lost
- Disk space critical

### WARNING ⚠️
- Degraded performance or potential issues
- Action required within 1 hour
- Notifications: Email only
- Response time: 1 hour
- Escalation: Team lead after 3 hours

**Examples:**
- High CPU (>80%)
- High memory (>85%)
- High error rate (>5%)
- High response time (p95 >1s)

### INFO ℹ️
- Informational only
- No immediate action
- Notifications: Once per day digest
- Response time: Next business day

**Examples:**
- Backup completed
- Backup retention cleanup
- Log rotation
- Metrics collection

## Notification Channels

### Primary: Email
- Sent immediately for critical alerts
- Batched every 5 minutes for warnings
- Daily digest for info messages

### Secondary: Slack (Optional)
- Real-time alerts in #alerts channel
- Threaded for better organization
- Quick action buttons

### Tertiary: SMS/Phone (Optional)
- Critical alerts only
- Configured via PagerDuty integration
- Escalation path: Email → SMS → Phone

## Response Expectations

| Severity | Response Time | Resolution Time | Retry Interval |
|----------|---------------|-----------------|-----------------|
| Critical | 15 minutes    | 1 hour          | Every 1 minute  |
| Warning  | 1 hour        | 4 hours         | Every 15 min    |
| Info     | Next day      | N/A             | Once daily      |

## Acknowledgement & Resolved

1. **Alert Fires:** Immediate notification sent
2. **Acknowledged:** Engineer acknowledges in monitoring system
3. **Investigating:** Status updated in Slack/Email
4. **Resolved:** Alert condition clears
5. **Post-Mortem:** Team reviews critical alerts

## On-Call Schedule

- **Primary On-Call:** Weekdays 9-5
- **Secondary On-Call:** Evenings & weekends
- **Escalation Path:** Primary → Secondary → Manager

## Alert Tuning

- Review alert threshold quarterly
- Adjust thresholds based on historical trends
- Suppress expected alerts (maintenance windows)
- Test alert routing monthly

## Silence Alerts (Planned Maintenance)

```bash
# Silence via Alertmanager API
curl -XPOST http://localhost:9093/api/v1/silences \
  -H 'Content-Type: application/json' \
  -d '{
    "matchers": [{"name":"alertname","value":"BackupFailure"}],
    "startsAt": "2025-12-31T00:00:00Z",
    "endsAt": "2025-12-31T02:00:00Z"
  }'
```
EOF

# Create monitoring documentation
echo "📖 Creating monitoring documentation..."
cat > "$MONITORING_DIR/MONITORING_GUIDE.md" << 'MONITORING_GUIDE_EOF'
# Aurigraph Website - Monitoring & Alerts Guide

## Overview

The monitoring infrastructure provides:
- **Real-time metrics collection** via Prometheus
- **Automated alerting** via Alertmanager
- **Visual dashboards** via Grafana
- **Email notifications** for critical issues

## Quick Start

### Start Monitoring Stack

```bash
bash scripts/start-monitoring.sh
```

### Access Dashboards

| Service | URL | Credentials |
|---------|-----|-------------|
| Prometheus | http://localhost:9090 | None (read-only) |
| Grafana | http://localhost:3001 | admin/admin |
| Alertmanager | http://localhost:9093 | None (read-only) |

### Check Health Status

```bash
bash scripts/check-monitoring-health.sh
```

## Metrics Collected

### System Metrics (Node Exporter)
- CPU usage (user, system, idle)
- Memory (available, used, cached)
- Disk I/O (reads, writes)
- Network I/O (transmitted, received)
- Load average
- File descriptors

### Container Metrics (cAdvisor)
- Container CPU usage
- Container memory usage
- Container network I/O
- Container disk I/O
- Container status

### Application Metrics
- HTTP requests per second
- Response time (p50, p95, p99)
- Error rate (4xx, 5xx)
- Form submission rate
- Database connections
- Cache hit rate

### Database Metrics
- Connection count
- Query duration
- Transaction count
- Disk usage
- Backup status

## Alerts

### Critical Alerts (Immediate Notification)

1. **Container Down** - Any production container not responding
2. **Backup Failure** - Database backup failed
3. **Disk Space Critical** - Less than 10% disk space
4. **Database Connection Lost** - Cannot connect to PostgreSQL

### Warning Alerts (Email Notification)

1. **High CPU** - >80% for 5 minutes
2. **High Memory** - >85% for 5 minutes
3. **High Error Rate** - >5% error rate for 5 minutes
4. **High Response Time** - 95th percentile > 1 second

## Dashboards

### System Metrics Dashboard
- CPU, memory, disk usage trends
- Network I/O
- Disk I/O
- System load average

### Application Metrics Dashboard
- Requests per second
- Response time distribution
- Error rate trends
- Form submissions
- Database connections
- Cache performance

### Container Metrics Dashboard
- Per-container CPU usage
- Per-container memory usage
- Network activity by container
- Container startup/restart tracking

### Alerts Dashboard
- Currently firing alerts
- Alert history
- Service status
- Alert firing rate

## Alert Management

### Viewing Active Alerts

```
Prometheus: http://localhost:9090/alerts
Alertmanager: http://localhost:9093/#/alerts
```

### Silencing Alerts (Planned Maintenance)

Via Alertmanager UI:
1. Go to http://localhost:9093
2. Click "Silence" button
3. Enter matching criteria
4. Set duration

Via API:
```bash
curl -XPOST http://localhost:9093/api/v1/silences \
  -H 'Content-Type: application/json' \
  -d '{
    "matchers": [{"name":"alertname","value":"BackupFailure"}],
    "startsAt": "2025-12-31T00:00:00Z",
    "endsAt": "2025-12-31T02:00:00Z"
  }'
```

## Customizing Alerts

Edit Prometheus alert rules:
```bash
nano monitoring/prometheus/alerts.yml
```

Then reload Prometheus:
```bash
curl -XPOST http://localhost:9090/-/reload
```

## Performance Tuning

### Prometheus Storage

Default retention: 30 days

Adjust in docker-compose.monitoring.yml:
```yaml
command:
  - '--storage.tsdb.retention.time=60d'
```

### Metric Scraping

Default interval: 15 seconds

Adjust in prometheus.yml:
```yaml
global:
  scrape_interval: 30s  # Increase for less load
  evaluation_interval: 30s
```

### Data Retention

By default, Prometheus keeps 30 days of data.

To keep more data:
```bash
docker-compose -f docker-compose.monitoring.yml stop prometheus

# Edit docker-compose.monitoring.yml, change:
# '--storage.tsdb.retention.time=30d' to '--storage.tsdb.retention.time=90d'

docker-compose -f docker-compose.monitoring.yml start prometheus
```

## Troubleshooting

### Metrics not appearing

1. Check Prometheus targets: http://localhost:9090/targets
2. Check for scrape errors
3. Verify exporter is running: `docker ps | grep exporter`
4. Check network connectivity: `docker network ls`

### Alerts not firing

1. Check alert rules: `http://localhost:9090/rules`
2. Verify metrics are being collected
3. Check Alertmanager: `http://localhost:9093`
4. Review alert.yml syntax

### Emails not sending

1. Check SMTP credentials in alertmanager.yml
2. Verify SMTP server is accessible
3. Check Alertmanager logs: `docker logs aurigraph-alertmanager`
4. Test email configuration manually

## Backup & Restore

### Backup Grafana Dashboards

```bash
# Export all dashboards
curl http://localhost:3000/api/search \
  -H "Authorization: Bearer $GRAFANA_API_TOKEN" \
  | jq '.[] | .uri' \
  | while read uri; do
    curl "http://localhost:3000/api/dashboards/$uri" \
      -H "Authorization: Bearer $GRAFANA_API_TOKEN" \
      > "dashboard-${uri}.json"
  done
```

### Restore Dashboards

```bash
for file in dashboard-*.json; do
  curl -X POST http://localhost:3000/api/dashboards/db \
    -H "Authorization: Bearer $GRAFANA_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d @"$file"
done
```

## Best Practices

1. **Alert Tuning** - Review alert thresholds monthly
2. **Dashboard Updates** - Keep dashboards current with new metrics
3. **Documentation** - Document all custom alert rules
4. **Testing** - Test alert routing quarterly
5. **Escalation** - Follow documented escalation policy
6. **Post-Mortems** - Review critical alerts with team
7. **Retention** - Archive old metrics and alerts
8. **Backup** - Backup Grafana dashboards weekly

MONITORING_GUIDE_EOF

# Summary
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "✅ Alert Management Setup Complete!"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "📧 Email Alert Configuration:"
echo "   SMTP Server: ${SMTP_SERVER}:${SMTP_PORT}"
echo "   Admin Email: ${ADMIN_EMAIL}"
echo "   Notification Routing: Critical (instant) → Warning (5m) → Info (24h)"
echo ""
echo "🚨 Alert Severity Levels:"
echo "   • CRITICAL: Service down, immediate action (< 5 min)"
echo "   • WARNING: Degraded performance, action within 1 hour"
echo "   • INFO: Informational, daily digest"
echo ""
echo "📋 Alert Escalation:"
echo "   • L1: Email notification"
echo "   • L2: Dashboard alert display"
echo "   • L3: Slack/Discord (optional)"
echo "   • L4: SMS/Phone (optional via PagerDuty)"
echo ""
echo "📁 Configuration Files:"
echo "   • Alertmanager: monitoring/alertmanager/alertmanager.yml"
echo "   • Escalation Policy: monitoring/alertmanager/escalation-policy.md"
echo "   • Monitoring Guide: monitoring/MONITORING_GUIDE.md"
echo ""
echo "🔗 Webhook Integrations (optional):"
echo "   • Slack: Set SLACK_WEBHOOK_URL environment variable"
echo "   • Discord: Set DISCORD_WEBHOOK_URL environment variable"
echo "   • PagerDuty: Set PAGERDUTY_KEY environment variable"
echo ""
echo "🚀 Next Steps:"
echo "   1. Set SMTP credentials: export SMTP_USERNAME=... SMTP_PASSWORD=..."
echo "   2. Start monitoring: bash scripts/start-monitoring.sh"
echo "   3. Configure Alertmanager: nano monitoring/alertmanager/alertmanager.yml"
echo "   4. Test alert: curl -XPOST http://localhost:9090/api/v1/query"
echo ""
echo "════════════════════════════════════════════════════════════════"
