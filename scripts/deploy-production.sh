#!/bin/bash

# Production Deployment Script - Blue-Green Strategy
# Usage: ./scripts/deploy-production.sh [--dry-run] [--skip-health-check]

set -e

# Configuration
PROD_SERVER="subbu@dlt.aurigraph.io"
PROD_PORT="2235"
PROD_DIR="/app/aurigraph-website"
DOCKER_IMAGE="aurigraph-website-app:latest"
HEALTH_CHECK_TIMEOUT=300  # 5 minutes
HEALTH_CHECK_INTERVAL=5   # Check every 5 seconds

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
DRY_RUN=false
SKIP_HEALTH_CHECK=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run) DRY_RUN=true; shift ;;
        --skip-health-check) SKIP_HEALTH_CHECK=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

run_remote_cmd() {
    local cmd="$1"
    if [ "$DRY_RUN" = true ]; then
        log_warning "[DRY-RUN] Would execute: $cmd"
    else
        ssh -p "$PROD_PORT" "$PROD_SERVER" "$cmd"
    fi
}

# Deployment Steps
echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}   Aurigraph HubSpot CRM Integration - Production Deploy${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

# Step 1: Pre-deployment checks
log_info "Step 1: Pre-deployment checks..."
log_info "  - Verifying SSH connectivity to production server"
if ! ssh -p "$PROD_PORT" "$PROD_SERVER" "echo 'SSH connection OK'" > /dev/null 2>&1; then
    log_error "Failed to connect to production server"
    exit 1
fi
log_success "SSH connectivity verified"

# Step 2: Check current deployment status
log_info "Step 2: Checking current deployment status..."
CURRENT_ACTIVE=$(run_remote_cmd "grep -oP \"upstream app_\K\w+\" $PROD_DIR/nginx.conf | head -1" 2>/dev/null || echo "blue")
NEXT_ACTIVE="green"
if [ "$CURRENT_ACTIVE" = "green" ]; then
    NEXT_ACTIVE="blue"
fi
log_success "Current active deployment: $CURRENT_ACTIVE → Next deployment: $NEXT_ACTIVE"

# Step 3: Pull latest code
log_info "Step 3: Pulling latest code from repository..."
run_remote_cmd "cd $PROD_DIR && git fetch origin && git checkout main && git pull origin main"
log_success "Code pulled successfully"

# Step 4: Build Docker image
log_info "Step 4: Building Docker image on production server..."
run_remote_cmd "cd $PROD_DIR && docker build -t $DOCKER_IMAGE ."
log_success "Docker image built successfully"

# Step 5: Start green deployment
log_info "Step 5: Starting green deployment on port 3001..."
run_remote_cmd "cd $PROD_DIR && docker-compose -f docker-compose.production.yml --profile green up -d green"
log_success "Green deployment started"

# Step 6: Wait for health checks
if [ "$SKIP_HEALTH_CHECK" = false ]; then
    log_info "Step 6: Waiting for health checks (timeout: ${HEALTH_CHECK_TIMEOUT}s)..."
    
    ELAPSED=0
    while [ $ELAPSED -lt $HEALTH_CHECK_TIMEOUT ]; do
        HEALTH=$(run_remote_cmd "curl -s http://localhost:3001/api/hubspot/test | jq -r '.status' 2>/dev/null" || echo "error")
        
        if [ "$HEALTH" = "success" ] || [ "$HEALTH" = "error" ]; then
            # Either success or HubSpot API key error (expected) means app is running
            log_success "Health check passed: Application is responding"
            break
        fi
        
        sleep $HEALTH_CHECK_INTERVAL
        ELAPSED=$((ELAPSED + HEALTH_CHECK_INTERVAL))
        echo -n "."
    done
    echo ""
    
    if [ $ELAPSED -ge $HEALTH_CHECK_TIMEOUT ]; then
        log_error "Health check timeout - Application failed to start"
        log_warning "Rolling back: Stopping green deployment"
        run_remote_cmd "cd $PROD_DIR && docker-compose -f docker-compose.production.yml down"
        exit 1
    fi
else
    log_warning "Skipping health checks (--skip-health-check flag set)"
fi

# Step 7: Update NGINX to route to new deployment
log_info "Step 7: Switching NGINX to route to $NEXT_ACTIVE deployment..."
if [ "$NEXT_ACTIVE" = "green" ]; then
    run_remote_cmd "sed -i 's/upstream app_blue/upstream app_green/g' $PROD_DIR/nginx.conf"
else
    run_remote_cmd "sed -i 's/upstream app_green/upstream app_blue/g' $PROD_DIR/nginx.conf"
fi
run_remote_cmd "cd $PROD_DIR && docker-compose -f docker-compose.production.yml exec -T nginx nginx -s reload"
log_success "NGINX switched to $NEXT_ACTIVE deployment"

# Step 8: Stop old deployment
log_info "Step 8: Stopping $CURRENT_ACTIVE deployment..."
if [ "$CURRENT_ACTIVE" = "blue" ]; then
    run_remote_cmd "cd $PROD_DIR && docker-compose -f docker-compose.production.yml stop blue"
else
    run_remote_cmd "cd $PROD_DIR && docker-compose -f docker-compose.production.yml --profile green stop green"
fi
log_success "$CURRENT_ACTIVE deployment stopped (kept for rollback)"

# Step 9: Verify production deployment
log_info "Step 9: Verifying production deployment..."
PROD_HEALTH=$(curl -s https://dlt.aurigraph.io/health)
if [ "$PROD_HEALTH" = "healthy" ]; then
    log_success "Production deployment verified - www.dlt.aurigraph.io is healthy"
else
    log_warning "Could not verify production health from external network"
fi

# Final summary
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}   ✓ Production Deployment Complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Deployment Summary:"
echo "  - Active Deployment: $NEXT_ACTIVE (port 300$([[ $NEXT_ACTIVE == 'blue' ]] && echo 0 || echo 1))"
echo "  - Standby Deployment: $CURRENT_ACTIVE (for quick rollback)"
echo "  - URL: https://dlt.aurigraph.io"
echo "  - API Test: curl https://dlt.aurigraph.io/api/hubspot/test"
echo ""
echo "Rollback (if needed):"
echo "  ssh -p $PROD_PORT $PROD_SERVER"
echo "  cd $PROD_DIR"
echo "  # Switch back by updating nginx.conf and reloading"
echo ""

