# HubSpot CRM Integration - Implementation Guide

**Status**: Ready for MVP implementation (2-3 days)
**Target**: Aurigraph.io website + V12 platform + future apps
**Project**: AV11 in JIRA
**Created**: December 30, 2025

---

## Executive Summary

The Aurigraph.io website already has **95% of the HubSpot integration implemented**. We discovered:

✅ **Already Complete**:
- HubSpot library with all API methods (`lib/hubspot.ts`)
- Database schema with `hubspot_sync_log` table
- Contact form API wired to HubSpot sync
- Environment variable placeholders

❌ **Critical Bugs to Fix** (3 items):
1. API payload format uses incorrect v3 structure
2. Contact search is inefficient (loads all contacts)
3. No timeout/retry protection (blocking calls)

**Revised Timeline**: **2-3 days** for production-ready MVP (vs 1-2 weeks estimated)

---

## JIRA Epic Structure

### Epic Details

**Project**: AV11
**Type**: Epic
**Summary**: HubSpot CRM Integration - Unified module for Aurigraph.io, V12, and future applications
**Description**:

```markdown
## Overview
Unified HubSpot CRM integration module enabling contact management, form data syncing, and analytics across all Aurigraph platforms.

## Current Status
95% of implementation already exists in aurigraph.io codebase. Only critical bugs and testing remain.

## Deliverables
- Production-ready MVP (Days 1-3): Bug fixes, retry logic, testing
- Unified TypeScript/Java library (Week 2): Cross-platform architecture
- Analytics dashboard (Week 2): Monitoring and health checks

## Success Criteria
- ✅ 95%+ HubSpot sync success rate
- ✅ <2s average sync time
- ✅ Zero form submission failures
- ✅ All contacts visible in HubSpot
- ✅ Automated retry for failed syncs
- ✅ Production deployment verified

## Technical Scope
- Fix 3 critical HubSpot API bugs
- Add timeout (10s) and retry (exponential backoff) protection
- Create comprehensive test suite (≥80% coverage)
- Implement background sync queue for retries
- Deploy monitoring and alerting

## Dependencies
- HubSpot API key (provided)
- PostgreSQL 16 (existing)
- Next.js 14 (existing)
- Quarkus 3.26+ for V12 (existing)

## Timeline
- Days 1-3: MVP + critical bug fixes
- Week 2: Unified module + testing
- Week 3: Production deployment + monitoring
```

---

## JIRA Tickets to Create

### Phase 1: MVP Implementation (Days 1-3)

**1. Task: Fix HubSpot API Payload Format Bug**
```
Type: Task
Priority: Highest
Estimate: 2 hours
Component: HubSpot Integration

Description:
The HubSpot v3 API requires a different payload structure than currently implemented.

Location: lib/hubspot.ts lines 144-149, 190-196

Current (WRONG):
```typescript
properties: properties.map(p => ({
  objectTypeId: '0-1',
  name: p.property,
  value: p.value,
}))
```

Should be (CORRECT):
```typescript
properties: properties.reduce((acc, p) => ({
  ...acc,
  [p.property]: p.value
}), {})
```

Acceptance Criteria:
- [ ] Fix API payload format in createContact()
- [ ] Fix API payload format in updateContact()
- [ ] Test with sample contact data
- [ ] Verify API responses return 201/200 (not 400)
```

---

**2. Task: Fix HubSpot Contact Search Logic**
```
Type: Task
Priority: Highest
Estimate: 2 hours
Component: HubSpot Integration

Description:
Current contact search loads ALL contacts (inefficient, hits rate limits).
Should use HubSpot v3 search API with email filter.

Location: lib/hubspot.ts lines 95-128

Current approach:
```
GET /crm/v3/objects/contacts?limit=1&after=0&properties=email...
```

Should use (efficient):
```
POST /crm/v3/objects/contacts/search
Body: {
  filterGroups: [{
    filters: [{
      propertyName: "email",
      operator: "EQ",
      value: email
    }]
  }]
}
```

Acceptance Criteria:
- [ ] Implement search API endpoint call
- [ ] Verify single contact found by email
- [ ] Test with non-existent email (returns empty)
- [ ] Add error handling for malformed emails
```

---

**3. Task: Add Timeout and Retry Logic to HubSpot Client**
```
Type: Task
Priority: High
Estimate: 3 hours
Component: HubSpot Integration

Description:
HubSpot API calls can hang indefinitely. Add:
- 10-second timeout for all API calls
- Exponential backoff retry (2s, 4s, 8s)
- Detailed error logging

Create helper function (new file: lib/hubspot-retry.ts):
```typescript
async function retryWithBackoff<T>(
  fn: () => Promise<T>,
  maxAttempts = 3
): Promise<T> {
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await Promise.race([
        fn(),
        new Promise<never>((_, reject) =>
          setTimeout(() => reject(new Error('Timeout after 10s')), 10000)
        )
      ]);
    } catch (error) {
      if (attempt < maxAttempts) {
        const delay = Math.pow(2, attempt) * 1000;
        await new Promise(resolve => setTimeout(resolve, delay));
      } else {
        throw error;
      }
    }
  }
}
```

Acceptance Criteria:
- [ ] Create retry helper function
- [ ] Wrap all HubSpot API calls with retry
- [ ] Test timeout behavior (verify <10s response)
- [ ] Test retry on transient failures
- [ ] Add error logging with HubSpot error codes
```

---

**4. Task: Add HUBSPOT_API_KEY Environment Variable**
```
Type: Task
Priority: Critical
Estimate: 30 minutes
Component: Infrastructure

Description:
HubSpot integration requires API key in environment.

Files to update:
- .env.local: Add HUBSPOT_API_KEY=<provided_key>
- lib/hubspot.ts: Load from process.env.HUBSPOT_API_KEY
- docker-compose.yml: Pass env var to container

Acceptance Criteria:
- [ ] Add HUBSPOT_API_KEY to .env.local
- [ ] Update docker-compose to include env var
- [ ] Verify API key is loaded in lib/hubspot.ts
- [ ] Confirm no API key commits (add to .gitignore if needed)
```

---

**5. Story: Create HubSpot Integration Test Endpoint**
```
Type: Story
Priority: High
Estimate: 2 hours
Component: API

Description:
Create endpoint to validate HubSpot integration works end-to-end.

Endpoint: GET /api/hubspot/test

Response on success (HTTP 200):
```json
{
  "status": "success",
  "message": "HubSpot integration working",
  "testContact": {
    "email": "test-[timestamp]@aurigraph.io",
    "firstName": "Test",
    "lastName": "Contact",
    "hubspotId": "12345",
    "syncedAt": "2025-12-30T12:00:00Z"
  },
  "syncLog": {
    "synced": true,
    "timestamp": "2025-12-30T12:00:00Z",
    "attempts": 1
  }
}
```

Acceptance Criteria:
- [ ] Create /api/hubspot/test endpoint
- [ ] Test creates contact in HubSpot
- [ ] Verify contact syncs to PostgreSQL
- [ ] Return appropriate success response
- [ ] Test with invalid API key (returns 401)
- [ ] Clean up test contacts after test
```

---

**6. Task: Add Environment Variable for HubSpot Setup**
```
Type: Task
Priority: High
Estimate: 1 hour
Component: Infrastructure

Description:
Document and verify all HubSpot-related environment variables are configured.

Required variables:
- HUBSPOT_API_KEY: HubSpot private app key
- HUBSPOT_PORTAL_ID: (optional) Portal ID for analytics
- DATABASE_URL: Already configured
- NODE_ENV: production/development

Acceptance Criteria:
- [ ] Verify HUBSPOT_API_KEY is set in .env.local
- [ ] Verify DATABASE_URL is accessible
- [ ] Test environment variable loading
- [ ] Document all required vars in README
```

---

### Phase 2: Testing & Validation (Days 3-4)

**7. Task: Create HubSpot Unit Test Suite**
```
Type: Task
Priority: High
Estimate: 4 hours
Component: Testing

Description:
Create comprehensive unit tests for HubSpot client (target: ≥80% coverage).

File: __tests__/hubspot.test.ts

Tests to implement:
- createContact: New email, existing email, invalid data
- updateContact: Existing contact, non-existent contact
- searchContact: Found, not found, invalid email
- retryLogic: Success on first try, success after retry, failure after max retries
- errorHandling: Network error, 400 Bad Request, 429 Rate Limited, timeout
- integration: Full form submission → HubSpot sync

Acceptance Criteria:
- [ ] Create test file with all test cases
- [ ] Achieve ≥80% code coverage (npm run test -- --coverage)
- [ ] All tests passing (npm test)
- [ ] Mock HubSpot API responses (don't call real API in tests)
- [ ] Test both success and failure paths
```

---

**8. Task: Create HubSpot Integration Tests**
```
Type: Task
Priority: High
Estimate: 3 hours
Component: Testing

Description:
Integration tests using HubSpot sandbox account.

Tests to implement:
- End-to-end contact form submission
- Verify contact created in HubSpot
- Verify database persistence
- Analytics incrementing properly
- Error recovery on API failure

Acceptance Criteria:
- [ ] Create integration test suite
- [ ] Test against HubSpot sandbox
- [ ] Verify all data fields synced correctly
- [ ] Test error scenarios (API down, invalid key)
- [ ] Document test procedures for manual verification
```

---

**9. Story: Create HubSpot Stats Dashboard**
```
Type: Story
Priority: Medium
Estimate: 3 hours
Component: Monitoring

Description:
Dashboard showing HubSpot sync health.

Endpoint: GET /api/admin/hubspot/stats

Response:
```json
{
  "syncStats": {
    "totalSynced": 150,
    "successRate": "98.5%",
    "failedSyncs": 2,
    "lastSync": "2025-12-30T12:15:00Z",
    "averageTime": "1.2s"
  },
  "queueStats": {
    "pending": 0,
    "failed": 2,
    "retrying": 0
  },
  "errors": [
    {
      "email": "invalid@example.com",
      "error": "Invalid email format",
      "lastAttempt": "2025-12-30T12:00:00Z",
      "attempts": 3
    }
  ]
}
```

Acceptance Criteria:
- [ ] Create stats endpoint
- [ ] Query sync statistics from database
- [ ] Calculate success rate percentage
- [ ] List failed syncs with error details
- [ ] Add admin authentication check
- [ ] Optional: Email alerts for >10% failure rate
```

---

**10. Task: Create HubSpot Background Sync Queue**
```
Type: Task
Priority: Medium
Estimate: 3 hours
Component: Infrastructure

Description:
Retry failed syncs automatically every 15 minutes.

File: lib/hubspot-queue.ts

Implementation:
- Query hubspot_sync_log for failed entries
- Retry with exponential backoff (max 24 hours)
- Update retry count and last attempt timestamp
- Log retry results
- Optional: Alert on >3 failures

Acceptance Criteria:
- [ ] Create queue system
- [ ] Implement retry logic with max attempts
- [ ] Add cron job or background worker (15 minute interval)
- [ ] Test retry with manual failure injection
- [ ] Verify database updates correctly
- [ ] Monitor logs for retry activity
```

---

### Phase 3: Unified Module Architecture (Week 2)

**11-21. Unified TypeScript/Java Module Tickets** (Details in plan document)

---

## Critical Bug Details

### Bug #1: HubSpot v3 API Payload Format

**Current (INCORRECT)**:
```typescript
// lib/hubspot.ts line 144-149
properties: properties.map(p => ({
  objectTypeId: '0-1',
  name: p.property,
  value: p.value,
}))
```

**Why it fails**: HubSpot v3 API expects flat object with property names as keys, not array with objectTypeId.

**Fixed**:
```typescript
properties: properties.reduce((acc, p) => ({
  ...acc,
  [p.property]: p.value
}), {})
```

**Error before fix**: `400 Bad Request - Invalid property format`

---

### Bug #2: Inefficient Contact Search

**Current (INEFFICIENT)**:
```typescript
// lib/hubspot.ts line 95-128
const response = await fetch(
  `https://api.hubapi.com/crm/v3/objects/contacts?limit=1&after=0&properties=email...`
)
```

**Problem**: Loads ALL contacts (even with limit=1, still inefficient), hits rate limits, slow response

**Fixed**:
```typescript
const response = await fetch(
  'https://api.hubapi.com/crm/v3/objects/contacts/search',
  {
    method: 'POST',
    body: JSON.stringify({
      filterGroups: [{
        filters: [{
          propertyName: 'email',
          operator: 'EQ',
          value: email
        }]
      }]
    })
  }
)
```

**Improvement**: Direct search by email, <100ms response

---

### Bug #3: No Timeout/Retry Protection

**Current (BLOCKING)**: API calls can hang indefinitely, single failure loses data

**Fixed**: Add timeout (10s) + exponential backoff retry (2s, 4s, 8s) - see Task #3 above

---

## Deployment Checklist

- [ ] **Pre-Deployment**:
  - [ ] HubSpot API key added to .env.local
  - [ ] All 3 critical bugs fixed
  - [ ] Test suite passing (npm test)
  - [ ] Code reviewed

- [ ] **Deployment**:
  - [ ] Commit and push changes to main
  - [ ] GitHub Actions workflow runs (build + test)
  - [ ] Deploy to production (`docker-compose up -d`)
  - [ ] Test /api/hubspot/test endpoint

- [ ] **Verification**:
  - [ ] Monitor HubSpot sync logs for 24 hours
  - [ ] Verify 95%+ sync success rate
  - [ ] Check average sync time <2s
  - [ ] Confirm all contacts in HubSpot

---

## Rollback Plan

If issues arise:

1. **Immediate** (5 min): Remove HUBSPOT_API_KEY from environment → form works but doesn't sync
2. **Code** (15 min): Revert to previous commit
3. **Data**: Retry failed syncs from `hubspot_sync_log` table once fixed

---

## Success Metrics - Week 1

- ✅ 95%+ sync success rate
- ✅ <2s average sync time
- ✅ Zero form submission failures
- ✅ All contacts visible in HubSpot
- ✅ Automated retry recovering 100% of failures
- ✅ Analytics dashboard showing trends

---

## Next Steps

1. **Create JIRA Epic** with this summary
2. **Create 10 child tickets** (Phases 1-2)
3. **Implement MVP** (Days 1-3)
4. **Run tests** and validate
5. **Deploy to production**
6. **Monitor** sync metrics
7. **Build unified module** (Week 2, if needed)

---

**Document Version**: 1.0
**Last Updated**: December 30, 2025
**Ready for Implementation**: ✅ YES

