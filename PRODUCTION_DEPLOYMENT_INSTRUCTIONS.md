# Production Deployment Instructions
## HubSpot CRM Integration MVP - dlt.aurigraph.io

**Deployment Date**: December 30, 2025  
**Status**: ✅ Ready for Production  
**Method**: Blue-Green Zero-Downtime Deployment  
**Target**: https://dlt.aurigraph.io  

---

## 🚀 Quick Start

### Execute On Production Server

```bash
# 1. SSH to production server
ssh -p 2235 subbu@dlt.aurigraph.io

# 2. Navigate to application directory
cd /app/aurigraph-website

# 3. Run deployment script (blue-green strategy)
bash scripts/deploy-production.sh

# Or with dry-run first to see what will happen:
bash scripts/deploy-production.sh --dry-run
```

### Expected Output
```
════════════════════════════════════════════════════════════
   Aurigraph HubSpot CRM Integration - Production Deploy
════════════════════════════════════════════════════════════

[INFO] Step 1: Pre-deployment checks...
[✓] SSH connectivity verified
[INFO] Step 2: Checking current deployment status...
[✓] Current active deployment: blue → Next deployment: green
[INFO] Step 3: Pulling latest code from repository...
[INFO] Step 4: Building Docker image on production server...
[✓] Docker image built successfully
[INFO] Step 5: Starting green deployment on port 3001...
[✓] Green deployment started
[INFO] Step 6: Waiting for health checks (timeout: 300s)...
[✓] Health check passed: Application is responding
[INFO] Step 7: Switching NGINX to route to green deployment...
[✓] NGINX switched to green deployment
[INFO] Step 8: Stopping blue deployment...
[✓] blue deployment stopped (kept for rollback)
[INFO] Step 9: Verifying production deployment...
[✓] Production deployment verified - www.dlt.aurigraph.io is healthy

════════════════════════════════════════════════════════════
   ✓ Production Deployment Complete!
════════════════════════════════════════════════════════════

Deployment Summary:
  - Active Deployment: green (port 3001)
  - Standby Deployment: blue (for quick rollback)
  - URL: https://dlt.aurigraph.io
  - API Test: curl https://dlt.aurigraph.io/api/hubspot/test
```

---

## 📋 Pre-Deployment Checklist

Before running the deployment script, verify:

- [ ] SSH access to dlt.aurigraph.io (port 2235) works
- [ ] Repository cloned at `/app/aurigraph-website`
- [ ] Docker installed and daemon running
- [ ] SSL certificates at `/app/aurigraph-website/ssl/`
  - [ ] `cert.pem` exists
  - [ ] `key.pem` exists
- [ ] Disk space available: `df -h` shows >5GB free
- [ ] Environment variables configured:
  - [ ] `HUBSPOT_API_KEY` (valid Personal Access Key)
  - [ ] `DB_PASSWORD`
  - [ ] `DOMAIN=dlt.aurigraph.io`

### Check Environment Variables
```bash
# On production server:
echo $HUBSPOT_API_KEY    # Should show valid key
echo $DB_PASSWORD         # Should show password
```

### Check Disk Space
```bash
df -h /app               # Need >5GB
docker images            # Check available
```

---

## 🔄 Deployment Process Overview

### Step 1: Pre-Deployment Validation
- ✓ SSH connectivity verified
- ✓ Current deployment status checked
- ✓ Determines: blue (current) → green (new)

### Step 2: Code & Image Update
- ✓ Pull latest code from main branch
- ✓ Build new Docker image
- ✓ Image built in ~15 seconds

### Step 3: Green Deployment
- ✓ Start new green container on port 3001
- ✓ Run for ~5 seconds
- ✓ Application ready to serve requests

### Step 4: Health Validation
- ✓ Wait for health checks (max 5 minutes)
- ✓ Tests: `GET /api/hubspot/test`
- ✓ Success when app responds (any status code)

### Step 5: Traffic Switch
- ✓ Update NGINX upstream configuration
- ✓ Reload NGINX (zero downtime)
- ✓ All new requests go to green

### Step 6: Cleanup
- ✓ Stop blue deployment (keep running for rollback)
- ✓ Document final state
- ✓ Ready for monitoring

---

## ✅ Post-Deployment Verification

After deployment completes, verify:

```bash
# 1. Check NGINX routing
curl https://dlt.aurigraph.io/
# Should respond with 200 OK

# 2. Check HubSpot test endpoint
curl https://dlt.aurigraph.io/api/hubspot/test
# Should respond with test contact data (or error if API key expired)

# 3. Check active container
docker ps | grep aurigraph
# Should show: aurigraph-website-green RUNNING on port 3001

# 4. Check blue (standby) status
docker ps -a | grep aurigraph
# Should show: aurigraph-website-blue EXITED (available for rollback)

# 5. Monitor logs
docker logs aurigraph-website-green -f
# Should show Next.js server running, no errors

# 6. Check health check logs
docker logs aurigraph-website-nginx | grep health
# Should show health checks passing
```

---

## 🔄 Rollback (If Needed)

### Automatic Rollback on Health Check Failure
- Script auto-stops on health check timeout (300 seconds)
- Blue deployment remains running
- No traffic switch happens
- You can retry deployment or investigate

### Manual Rollback to Previous Deployment
```bash
# If you need to quickly revert to blue:
ssh -p 2235 subbu@dlt.aurigraph.io
cd /app/aurigraph-website

# Switch NGINX back to blue
sed -i 's/upstream app_green/upstream app_blue/g' nginx.conf

# Reload NGINX
docker-compose -f docker-compose.production.yml exec -T nginx nginx -s reload

# Start blue if needed
docker-compose -f docker-compose.production.yml start blue

# Monitor blue logs
docker logs aurigraph-website-blue -f
```

**Rollback time**: <30 seconds (zero traffic impact)

---

## 📊 Monitoring After Deployment

### Key Metrics to Watch (First 24 Hours)

1. **Application Health**
   ```bash
   # Check every 5 minutes
   curl -s https://dlt.aurigraph.io/health | jq .
   ```

2. **HubSpot Sync Status** (Once valid API key provided)
   ```bash
   curl -s https://dlt.aurigraph.io/api/hubspot/test | jq .
   ```

3. **Resource Usage**
   ```bash
   # Check CPU, memory, disk
   docker stats aurigraph-website-green
   ```

4. **Error Logs**
   ```bash
   # Monitor for errors
   docker logs aurigraph-website-green --tail 100 | grep ERROR
   ```

5. **NGINX Access Logs**
   ```bash
   # Monitor incoming traffic
   docker logs aurigraph-website-nginx --tail 50
   ```

### Alert Conditions
- ❌ App not responding (HTTP 500 errors)
- ❌ High error rate (>1% of requests failing)
- ❌ High CPU usage (>80% for >5 minutes)
- ❌ Disk space critically low (<1GB free)
- ❌ HubSpot sync failures (>5% failure rate)

---

## 🔐 Security Notes

### SSL/TLS Configuration
- ✓ TLS 1.3 enabled (modern security)
- ✓ Strong ciphers only
- ✓ HSTS header (31536000 seconds)
- ✓ Certificate pinning ready

### Environment Variables (Sensitive)
- Never commit `HUBSPOT_API_KEY` to git
- Store in production `.env.production` or system env vars
- Rotate API keys quarterly
- Log API key usage for audit

### Network Security
- ✓ Non-root user execution (nextjs:1001)
- ✓ Container network isolation
- ✓ Health checks via internal network (not exposed)
- ✓ CORS headers configured

---

## 📞 Support & Troubleshooting

### Common Issues & Solutions

**Issue**: "Could not find a production build in the '.next' directory"
- **Cause**: npm build not run in Docker
- **Solution**: Script auto-runs build, ensure Docker has build step

**Issue**: "Health check timeout - Application failed to start"
- **Cause**: App didn't start within 5 minutes
- **Solution**: Check Docker logs, verify node_modules, disk space

**Issue**: "Cannot connect to SSH server"
- **Cause**: SSH key issue or firewall
- **Solution**: Verify SSH key permissions, test direct SSH connection

**Issue**: "NGINX failed to reload"
- **Cause**: Syntax error in nginx.conf
- **Solution**: Check nginx.conf syntax, restore from backup

### Getting Help

1. Check deployment logs: `docker logs aurigraph-website-green`
2. Check NGINX logs: `docker logs aurigraph-website-nginx`
3. Check JIRA Epic AV11-1012 for task context
4. Review DEPLOYMENT_STATUS.md for detailed procedures

---

## 📝 After Successful Deployment

### Update JIRA
- Mark AV11-1022 (Production Deployment) as "Done"
- Add comment with deployment details:
  ```
  ✅ Production deployment completed
  - Deployed version: <git-commit-hash>
  - Active deployment: green on port 3001
  - Rollback point: blue on port 3000
  - Status: Monitoring for 24 hours
  ```

### Update Slack/Team
```
✅ HubSpot CRM Integration deployed to production
- URL: https://dlt.aurigraph.io
- Status: Live and monitoring
- API endpoint: /api/hubspot/test (requires valid HubSpot API key)
- Rollback available within 30 seconds if needed
```

### Schedule Monitoring Handoff
- First 24 hours: Active monitoring (every 1 hour)
- Days 2-7: Regular monitoring (4x daily)
- After 1 week: Standard monitoring (1x daily)

---

## 🎯 Deployment Complete Criteria

Deployment is **successfully complete** when:

- ✅ Script completes without errors
- ✅ Green deployment running on port 3001
- ✅ Health checks passed within timeout
- ✅ NGINX switched to green upstream
- ✅ Blue deployment stopped (available for rollback)
- ✅ https://dlt.aurigraph.io responds with HTTP 200
- ✅ No errors in application logs (docker logs command)
- ✅ HubSpot test endpoint returns data (once valid API key provided)
- ✅ All JIRA tickets marked complete

---

## 📈 Success Metrics (24-Hour Window)

Track these metrics after deployment:

| Metric | Target | Action if Failed |
|--------|--------|------------------|
| **Availability** | >99.9% | Investigate errors, consider rollback |
| **Response Time** | <500ms (p95) | Check resource usage, optimize |
| **Error Rate** | <0.1% | Review error logs, check HubSpot API |
| **HubSpot Sync** | >95% success | Verify API key, check network |
| **CPU Usage** | <50% avg | Normal for containerized app |
| **Memory Usage** | <512MB | Acceptable, monitor for leaks |
| **Disk Space** | >2GB free | Clean up old logs if needed |

---

**Document Generated**: December 30, 2025  
**Deployment Status**: ✅ Ready for Production  
**Next Action**: Execute `bash scripts/deploy-production.sh` on production server

