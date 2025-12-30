# NGINX Configuration Fix - Deployment Guide

**Status**: CRITICAL - www.aurigraph.io currently not accessible
**Issue**: Docker NGINX container crashing due to invalid directive
**Fix**: Remove invalid `proxy_upgrade` directive from nginx.conf
**Impact**: Restore HTTPS access to aurigraph.io and www.aurigraph.io
**Timeline**: 5-10 minutes to deploy

---

## Problem Summary

The Docker NGINX container is in a restart loop with the error:
```
[emerg] 1#1: unknown directive "proxy_upgrade" in /etc/nginx/nginx.conf:87
```

This prevents the reverse proxy from starting, causing `www.aurigraph.io` to return `ERR_CONNECTION_REFUSED`.

---

## The Fix

**File**: `/tmp/aurigraph-website/nginx.conf`
**Line**: 87
**Change**: Remove invalid `proxy_upgrade` directive

### Before (BROKEN):
```nginx
# WebSocket support
proxy_upgrade $http_upgrade;           # ❌ INVALID - causes container crash
proxy_set_header Connection "upgrade";
```

### After (FIXED):
```nginx
# WebSocket support
proxy_set_header Upgrade $http_upgrade;  # ✅ CORRECT - valid NGINX directive
proxy_set_header Connection "upgrade";
```

---

## How to Deploy

### Option 1: Manual SSH Deployment (Recommended for now)

```bash
# 1. SSH to production server
ssh -p 2235 subbu@dlt.aurigraph.io

# 2. Navigate to website directory
cd /home/subbu/aurigraph-website

# 3. Verify current nginx.conf has the issue (line 87)
cat nginx.conf | sed -n '80,90p'

# 4. Edit nginx.conf (remove invalid directive on line 87)
# Use sed to replace the line
sed -i '87d' nginx.conf  # Delete line 87

# 5. Verify the fix
cat nginx.conf | sed -n '80,90p'
# Should show: proxy_set_header Upgrade $http_upgrade;

# 6. Stop current containers
docker-compose down

# 7. Start containers with fixed config
docker-compose -f docker-compose.production.yml up -d

# 8. Verify NGINX container is running (not crashing)
docker ps | grep nginx

# 9. Test HTTPS access
curl -I https://aurigraph.io
# Should return HTTP/2 200, not connection refused
```

### Option 2: Git Commit + GitHub Actions (Automated)

```bash
# From local machine with /tmp/aurigraph-website repository
cd /tmp/aurigraph-website

# Verify the fix is in place (line 87 should have proxy_set_header)
cat nginx.conf | sed -n '80,90p'

# Commit the fix
git add nginx.conf
git commit -m "fix: Correct NGINX WebSocket support directive

- Remove invalid 'proxy_upgrade' directive (line 87)
- Keep valid 'proxy_set_header Upgrade' directive
- Fixes Docker NGINX container crash
- Restores www.aurigraph.io HTTPS access

This was causing: [emerg] unknown directive 'proxy_upgrade'"

# Push to trigger GitHub Actions deployment
git push origin main

# GitHub Actions will:
# 1. Build Docker image with fixed nginx.conf
# 2. Push to container registry
# 3. Deploy to production server
# 4. Restart NGINX container
```

---

## Verification Steps

### 1. Verify NGINX Container is Running
```bash
docker ps | grep nginx
# Should show: aurigraph-nginx (running, not restarting)
```

### 2. Check NGINX Logs for Errors
```bash
docker logs aurigraph-nginx
# Should NOT contain: "unknown directive"
# Should show: "nginx: configuration file test is successful"
```

### 3. Test HTTPS Connectivity
```bash
# Test HTTP (should redirect to HTTPS)
curl -I http://aurigraph.io
# Expected: HTTP/1.1 301 Moved Permanently
# Location: https://aurigraph.io

# Test HTTPS
curl -I https://aurigraph.io
# Expected: HTTP/2 200 OK

# Test www subdomain
curl -I https://www.aurigraph.io
# Expected: HTTP/2 200 OK
```

### 4. Test Website Content
```bash
curl https://aurigraph.io/ | head -20
# Should return HTML content (not error)

# Test API endpoint
curl https://aurigraph.io/api/contact/status
# Should return valid response (not connection refused)
```

### 5. Check Service Connectivity
```bash
# Verify NGINX can reach Next.js app on port 3000
docker exec aurigraph-nginx curl http://app:3000/
# Should return HTML (internal Docker network)

# Verify database connectivity
docker exec aurigraph-db pg_isready -U aurigraph
# Should return: accepting connections
```

---

## Troubleshooting

### If NGINX Still Won't Start

**Problem**: Container still crashing with same error

**Solution**:
```bash
# 1. Verify the fix was applied
docker exec aurigraph-nginx cat /etc/nginx/nginx.conf | sed -n '80,90p'

# If still shows "proxy_upgrade", the fix wasn't deployed

# 2. Stop and remove containers completely
docker-compose -f docker-compose.production.yml down

# 3. Remove nginx volume (to ensure clean state)
docker volume rm aurigraph-nginx-logs
docker volume rm aurigraph-nginx-cache

# 4. Re-apply fix manually if needed
# Edit /tmp/aurigraph-website/nginx.conf line 87

# 5. Start containers fresh
docker-compose -f docker-compose.production.yml up -d

# 6. Check logs
docker logs aurigraph-nginx
```

### If NGINX Starts but Site Returns Connection Refused

**Problem**: NGINX running but www.aurigraph.io still unreachable

**Solution**:
```bash
# 1. Check if NGINX is listening on ports 80/443
docker ps
# Verify aurigraph-nginx has: 0.0.0.0:80->80, 0.0.0.0:443->443

# 2. Check firewall rules
sudo ufw status
# Ports 80 and 443 should be allowed

# 3. Test from container
docker exec aurigraph-nginx curl http://localhost/health
# Should return 200

# 4. Test DNS resolution
nslookup aurigraph.io
# Should resolve to 151.242.51.51

# 5. Check certificate validity
docker exec aurigraph-nginx openssl s_client -connect localhost:443
# Should show valid certificate
```

### If WebSocket Connections Still Fail

**Problem**: WebSocket (for real-time updates) not working

**Solution**: Verify the correct directives are in place:
```bash
# Must have BOTH lines for WebSocket support:
docker exec aurigraph-nginx grep -A1 "WebSocket support" /etc/nginx/nginx.conf
# Should show:
# proxy_set_header Upgrade $http_upgrade;
# proxy_set_header Connection "upgrade";
```

---

## The Root Cause

The typo `proxy_upgrade` was intended to be `proxy_set_header Upgrade`.

**Why it failed**:
- NGINX uses `proxy_set_header` directive to set headers
- `proxy_upgrade` is not a valid NGINX directive
- NGINX validates configuration on startup and fails if unknown directive found
- Docker container exits with error code, then tries to restart infinitely

**Why the fix works**:
- `proxy_set_header Upgrade $http_upgrade` tells NGINX to pass the Upgrade header to backend
- This is required for WebSocket support (HTTP → WS upgrade)
- It's the proper NGINX syntax for header manipulation

---

## Configuration Context

The full WebSocket support section should look like:

```nginx
location / {
    proxy_pass http://app:3000;
    proxy_http_version 1.1;

    # WebSocket support
    proxy_set_header Upgrade $http_upgrade;        # ✅ Pass Upgrade header
    proxy_set_header Connection "upgrade";         # ✅ Pass Connection header

    # Standard headers for reverse proxy
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-Host $server_name;

    # Timeouts
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;

    # Buffering
    proxy_buffering on;
    proxy_buffer_size 4k;
    proxy_buffers 8 4k;

    # Cache bypass for WebSocket
    proxy_cache_bypass $http_upgrade;
}
```

---

## Rollback Plan

If the fix causes issues:

```bash
# 1. Revert the commit
git revert <commit-hash>
git push origin main

# GitHub Actions will re-deploy previous version

# 2. Or manually restore previous nginx.conf
git checkout HEAD~1 nginx.conf
git commit -m "revert: Restore previous nginx.conf"
git push origin main

# 3. Manual rollback (if needed immediately)
docker-compose down
git checkout HEAD~1 nginx.conf
docker-compose -f docker-compose.production.yml up -d
```

---

## Success Criteria

✅ **Deployment is successful when**:
- NGINX container is running (not restarting)
- `curl -I https://aurigraph.io` returns HTTP 200
- Website loads with all content
- Contact form works and submits to HubSpot
- WebSocket connections (if used) are stable
- No error messages in Docker logs

---

## Timeline

- **5 min**: SSH to server + edit nginx.conf
- **2 min**: Stop/start containers
- **3 min**: Verify connectivity and logs
- **Total**: ~10 minutes to full deployment

---

## Next Steps After Fixing

Once www.aurigraph.io is accessible:

1. ✅ **Deploy NGINX fix** (this document)
2. 🔄 **Create HubSpot JIRA tickets** (HUBSPOT_JIRA_TICKETS.csv)
3. 🔄 **Implement HubSpot MVP** (HUBSPOT_INTEGRATION_GUIDE.md)
4. 🔄 **Deploy HubSpot fixes** to production
5. 🔄 **Monitor sync metrics** for 24 hours

---

**Document Version**: 1.0
**Created**: December 30, 2025
**Deployment Difficulty**: Easy (1/10)
**Estimated Downtime**: <2 minutes
**Risk Level**: Low (simple config fix)
