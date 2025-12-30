#!/bin/bash

#############################################################################
# Aurigraph Website - Application Performance Monitoring Setup
#
# Deploys:
# - Prometheus for metrics collection and storage
# - Node Exporter for system metrics
# - cAdvisor for container metrics
# - Grafana for visualization and dashboards
#############################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MONITORING_DIR="${PROJECT_ROOT}/monitoring"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "📊 Aurigraph Website - Application Performance Monitoring Setup"
echo "=============================================================="
echo ""

# Create monitoring directory structure
echo "📁 Creating monitoring infrastructure..."
mkdir -p "$MONITORING_DIR"/{prometheus,grafana,exporters}
mkdir -p "$MONITORING_DIR/grafana/dashboards"
mkdir -p "$MONITORING_DIR/grafana/provisioning/{dashboards,datasources}"

# Create Prometheus configuration
echo "⚙️  Configuring Prometheus..."
cat > "$MONITORING_DIR/prometheus/prometheus.yml" << 'PROMETHEUS_EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    monitor: 'aurigraph-website'

# Alert rules (evaluated every 15 seconds)
rule_files:
  - '/etc/prometheus/alerts.yml'

# Scrape configurations
scrape_configs:
  # Prometheus self-monitoring
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  # Node Exporter - System metrics
  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']

  # cAdvisor - Container metrics
  - job_name: 'cadvisor'
    static_configs:
      - targets: ['localhost:8080']

  # PostgreSQL metrics
  - job_name: 'postgres'
    static_configs:
      - targets: ['localhost:9187']

  # NGINX metrics
  - job_name: 'nginx'
    static_configs:
      - targets: ['localhost:9113']

  # Application metrics (Next.js via custom endpoint)
  - job_name: 'aurigraph-website'
    metrics_path: '/api/metrics'
    static_configs:
      - targets: ['aurigraph-website:3000']

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['localhost:9093']
PROMETHEUS_EOF

# Create alert rules
echo "🚨 Configuring alert rules..."
cat > "$MONITORING_DIR/prometheus/alerts.yml" << 'ALERTS_EOF'
groups:
  - name: aurigraph_alerts
    interval: 15s
    rules:
      # High CPU usage
      - alert: HighCPUUsage
        expr: node_cpu_seconds_total{mode="system"} > 0.8
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage detected"
          description: "CPU usage is above 80% for 5 minutes"

      # High memory usage
      - alert: HighMemoryUsage
        expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes > 0.85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage detected"
          description: "Memory usage is above 85%"

      # Disk space low
      - alert: LowDiskSpace
        expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) < 0.1
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Low disk space detected"
          description: "Less than 10% disk space available"

      # Database container down
      - alert: DatabaseContainerDown
        expr: up{job="postgres"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "PostgreSQL container is down"
          description: "PostgreSQL container has been down for 1 minute"

      # Website container down
      - alert: WebsiteContainerDown
        expr: up{job="aurigraph-website"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Website container is down"
          description: "Next.js application container is not responding"

      # NGINX container down
      - alert: NginxContainerDown
        expr: up{job="nginx"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "NGINX container is down"
          description: "NGINX reverse proxy container is not responding"

      # High response time
      - alert: HighResponseTime
        expr: histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m])) > 1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High API response time"
          description: "95th percentile response time is above 1 second"

      # High error rate
      - alert: HighErrorRate
        expr: (rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m])) > 0.05
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High error rate detected"
          description: "Error rate (5xx) is above 5%"

      # Backup failure
      - alert: BackupFailure
        expr: increase(backup_failures_total[24h]) > 0
        labels:
          severity: critical
        annotations:
          summary: "Database backup failed"
          description: "Database backup has failed in the last 24 hours"
ALERTS_EOF

# Create Grafana provisioning configuration
echo "📊 Configuring Grafana datasources..."
cat > "$MONITORING_DIR/grafana/provisioning/datasources/prometheus.yml" << 'GRAFANA_DS_EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: false
    jsonData:
      timeInterval: 15s
GRAFANA_DS_EOF

# Create dashboard provisioning
cat > "$MONITORING_DIR/grafana/provisioning/dashboards/dashboards.yml" << 'GRAFANA_DASH_EOF'
apiVersion: 1

providers:
  - name: 'Aurigraph Dashboards'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    editable: true
    options:
      path: /etc/grafana/provisioning/dashboards
GRAFANA_DASH_EOF

# Create system metrics dashboard
echo "📈 Creating system metrics dashboard..."
cat > "$MONITORING_DIR/grafana/dashboards/system-metrics.json" << 'DASHBOARD_EOF'
{
  "dashboard": {
    "title": "Aurigraph System Metrics",
    "panels": [
      {
        "title": "CPU Usage",
        "targets": [{"expr": "100 - (avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)"}],
        "type": "graph"
      },
      {
        "title": "Memory Usage",
        "targets": [{"expr": "(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100"}],
        "type": "graph"
      },
      {
        "title": "Disk Usage",
        "targets": [{"expr": "(1 - (node_filesystem_avail_bytes / node_filesystem_size_bytes)) * 100"}],
        "type": "graph"
      },
      {
        "title": "Network I/O",
        "targets": [
          {"expr": "rate(node_network_receive_bytes_total[5m])"},
          {"expr": "rate(node_network_transmit_bytes_total[5m])"}
        ],
        "type": "graph"
      },
      {
        "title": "Disk I/O",
        "targets": [
          {"expr": "rate(node_disk_read_bytes_total[5m])"},
          {"expr": "rate(node_disk_written_bytes_total[5m])"}
        ],
        "type": "graph"
      }
    ]
  }
}
EOF

# Create application metrics dashboard
echo "📊 Creating application metrics dashboard..."
cat > "$MONITORING_DIR/grafana/dashboards/application-metrics.json" << 'APP_DASHBOARD_EOF'
{
  "dashboard": {
    "title": "Aurigraph Application Metrics",
    "panels": [
      {
        "title": "HTTP Requests (RPS)",
        "targets": [{"expr": "rate(http_requests_total[5m])"}],
        "type": "graph"
      },
      {
        "title": "Response Time (p95)",
        "targets": [{"expr": "histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))"}],
        "type": "graph"
      },
      {
        "title": "Error Rate",
        "targets": [{"expr": "rate(http_requests_total{status=~\"5..\"}[5m])"}],
        "type": "graph"
      },
      {
        "title": "Contact Form Submissions",
        "targets": [{"expr": "rate(contact_form_submissions_total[5m])"}],
        "type": "graph"
      },
      {
        "title": "Database Connections",
        "targets": [{"expr": "pg_stat_activity_count"}],
        "type": "stat"
      },
      {
        "title": "Cache Hit Rate",
        "targets": [{"expr": "rate(cache_hits_total[5m]) / (rate(cache_hits_total[5m]) + rate(cache_misses_total[5m]))"}],
        "type": "gauge"
      }
    ]
  }
}
EOF

# Create container metrics dashboard
echo "🐳 Creating container metrics dashboard..."
cat > "$MONITORING_DIR/grafana/dashboards/container-metrics.json" << 'CONTAINER_DASHBOARD_EOF'
{
  "dashboard": {
    "title": "Aurigraph Container Metrics",
    "panels": [
      {
        "title": "Container CPU Usage",
        "targets": [{"expr": "rate(container_cpu_usage_seconds_total{name=~\"aurigraph.*\"}[5m]) * 100"}],
        "type": "graph"
      },
      {
        "title": "Container Memory Usage",
        "targets": [{"expr": "container_memory_usage_bytes{name=~\"aurigraph.*\"}"}],
        "type": "graph"
      },
      {
        "title": "Container Network I/O",
        "targets": [
          {"expr": "rate(container_network_receive_bytes_total{name=~\"aurigraph.*\"}[5m])"},
          {"expr": "rate(container_network_transmit_bytes_total{name=~\"aurigraph.*\"}[5m])"}
        ],
        "type": "graph"
      },
      {
        "title": "Container Status",
        "targets": [{"expr": "container_last_seen{name=~\"aurigraph.*\"}"}],
        "type": "table"
      }
    ]
  }
}
EOF

# Create Docker Compose for monitoring stack
echo "🐳 Creating Docker Compose for monitoring..."
cat > "$PROJECT_ROOT/docker-compose.monitoring.yml" << 'DOCKER_COMPOSE_EOF'
version: '3.9'

services:
  prometheus:
    image: prom/prometheus:latest
    container_name: aurigraph-prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./monitoring/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ./monitoring/prometheus/alerts.yml:/etc/prometheus/alerts.yml:ro
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=30d'
      - '--web.console.libraries=/usr/share/prometheus/console_libraries'
      - '--web.console.templates=/usr/share/prometheus/consoles'
    restart: always
    networks:
      - aurigraph-network

  node-exporter:
    image: prom/node-exporter:latest
    container_name: aurigraph-node-exporter
    ports:
      - "9100:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    restart: always
    networks:
      - aurigraph-network

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    container_name: aurigraph-cadvisor
    ports:
      - "8080:8080"
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
      - /dev/disk/:/dev/disk:ro
    privileged: true
    restart: always
    networks:
      - aurigraph-network

  grafana:
    image: grafana/grafana:latest
    container_name: aurigraph-grafana
    ports:
      - "3001:3000"
    environment:
      GF_SECURITY_ADMIN_USER: admin
      GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_PASSWORD:-ChangeMe123!}
      GF_INSTALL_PLUGINS: 'grafana-piechart-panel'
    volumes:
      - ./monitoring/grafana/provisioning:/etc/grafana/provisioning:ro
      - ./monitoring/grafana/dashboards:/etc/grafana/provisioning/dashboards:ro
      - grafana_data:/var/lib/grafana
    restart: always
    networks:
      - aurigraph-network
    depends_on:
      - prometheus

volumes:
  prometheus_data:
  grafana_data:

networks:
  aurigraph-network:
    external: true
DOCKER_COMPOSE_EOF

# Create monitoring startup script
echo "🚀 Creating monitoring startup script..."
cat > "$SCRIPT_DIR/start-monitoring.sh" << 'START_MONITORING_EOF'
#!/bin/bash

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "🚀 Starting monitoring stack..."
echo ""

# Set Grafana password
export GRAFANA_PASSWORD="${GRAFANA_PASSWORD:-admin}"

# Start monitoring containers
docker-compose -f "$PROJECT_ROOT/docker-compose.monitoring.yml" up -d

# Wait for services to start
echo "⏳ Waiting for services to start..."
sleep 10

# Check status
echo ""
echo "✅ Monitoring stack started!"
echo ""
echo "📊 Access URLs:"
echo "   • Prometheus: http://localhost:9090"
echo "   • Grafana: http://localhost:3001"
echo ""
echo "🔐 Grafana Credentials:"
echo "   • Username: admin"
echo "   • Password: $GRAFANA_PASSWORD"
echo ""
echo "📈 Available Dashboards:"
echo "   • System Metrics"
echo "   • Application Metrics"
echo "   • Container Metrics"
echo ""

START_MONITORING_EOF

chmod +x "$SCRIPT_DIR/start-monitoring.sh"

# Create monitoring health check script
echo "🏥 Creating monitoring health check..."
cat > "$SCRIPT_DIR/check-monitoring-health.sh" << 'HEALTH_CHECK_EOF'
#!/bin/bash

echo "🏥 Monitoring Stack Health Check"
echo "=================================="
echo ""

# Check Prometheus
echo "Checking Prometheus..."
if curl -s http://localhost:9090/-/healthy > /dev/null; then
    echo "✅ Prometheus: Healthy"
else
    echo "❌ Prometheus: Down"
fi

# Check Node Exporter
echo "Checking Node Exporter..."
if curl -s http://localhost:9100/metrics > /dev/null; then
    echo "✅ Node Exporter: Healthy"
else
    echo "❌ Node Exporter: Down"
fi

# Check cAdvisor
echo "Checking cAdvisor..."
if curl -s http://localhost:8080/api/v1.3/machine > /dev/null; then
    echo "✅ cAdvisor: Healthy"
else
    echo "❌ cAdvisor: Down"
fi

# Check Grafana
echo "Checking Grafana..."
if curl -s http://localhost:3001/api/health > /dev/null; then
    echo "✅ Grafana: Healthy"
else
    echo "❌ Grafana: Down"
fi

echo ""
echo "=================================="
echo "Health check complete"

HEALTH_CHECK_EOF

chmod +x "$SCRIPT_DIR/check-monitoring-health.sh"

# Create summary
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "✅ Application Performance Monitoring Setup Complete!"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "📊 Monitoring Stack Components:"
echo "   ✅ Prometheus - Metrics collection and storage (30-day retention)"
echo "   ✅ Node Exporter - System metrics (CPU, memory, disk, network)"
echo "   ✅ cAdvisor - Container metrics (resource usage, performance)"
echo "   ✅ Grafana - Visualization and dashboards"
echo ""
echo "🚀 Getting Started:"
echo "   1. Start monitoring: bash $SCRIPT_DIR/start-monitoring.sh"
echo "   2. Check health: bash $SCRIPT_DIR/check-monitoring-health.sh"
echo "   3. Access Prometheus: http://localhost:9090"
echo "   4. Access Grafana: http://localhost:3001 (admin/admin)"
echo ""
echo "📈 Available Dashboards:"
echo "   • System Metrics - CPU, memory, disk, network usage"
echo "   • Application Metrics - RPS, response time, error rate"
echo "   • Container Metrics - Docker container performance"
echo ""
echo "🚨 Alert Rules:"
echo "   • High CPU (>80% for 5m)"
echo "   • High Memory (>85% for 5m)"
echo "   • Low Disk (<10% available)"
echo "   • Container Down (no response for 1m)"
echo "   • High Response Time (p95 >1s)"
echo "   • High Error Rate (>5% for 5m)"
echo ""
echo "📋 Configuration Files:"
echo "   • Prometheus: $MONITORING_DIR/prometheus/prometheus.yml"
echo "   • Alerts: $MONITORING_DIR/prometheus/alerts.yml"
echo "   • Grafana: $MONITORING_DIR/grafana/provisioning/"
echo "   • Docker Compose: $PROJECT_ROOT/docker-compose.monitoring.yml"
echo ""
echo "════════════════════════════════════════════════════════════════"
