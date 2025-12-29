-- Initialize Aurigraph Website Database
-- This script runs automatically when PostgreSQL container starts

-- Create schema for website data
CREATE SCHEMA IF NOT EXISTS website;

-- Table: Contact Form Submissions
CREATE TABLE IF NOT EXISTS website.contact_submissions (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL,
    company VARCHAR(255),
    use_case TEXT,
    message TEXT NOT NULL,
    status VARCHAR(50) DEFAULT 'new',
    hubspot_synced BOOLEAN DEFAULT FALSE,
    hubspot_contact_id VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    synced_at TIMESTAMP
);

-- Index on email for quick lookups
CREATE INDEX IF NOT EXISTS idx_contact_email ON website.contact_submissions(email);
CREATE INDEX IF NOT EXISTS idx_contact_created_at ON website.contact_submissions(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_contact_hubspot_synced ON website.contact_submissions(hubspot_synced);

-- Table: HubSpot Sync Log (track all sync attempts)
CREATE TABLE IF NOT EXISTS website.hubspot_sync_log (
    id SERIAL PRIMARY KEY,
    contact_id INTEGER REFERENCES website.contact_submissions(id) ON DELETE CASCADE,
    email VARCHAR(255) NOT NULL,
    sync_type VARCHAR(50) NOT NULL, -- 'create', 'update', 'list_add'
    success BOOLEAN DEFAULT FALSE,
    hubspot_response TEXT,
    error_message TEXT,
    attempt_number INTEGER DEFAULT 1,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Index on sync log for tracking
CREATE INDEX IF NOT EXISTS idx_hubspot_sync_email ON website.hubspot_sync_log(email);
CREATE INDEX IF NOT EXISTS idx_hubspot_sync_success ON website.hubspot_sync_log(success);
CREATE INDEX IF NOT EXISTS idx_hubspot_sync_created ON website.hubspot_sync_log(created_at DESC);

-- Table: Form Analytics
CREATE TABLE IF NOT EXISTS website.form_analytics (
    id SERIAL PRIMARY KEY,
    form_name VARCHAR(100) NOT NULL,
    submission_date DATE DEFAULT CURRENT_DATE,
    total_submissions INTEGER DEFAULT 0,
    successful_submissions INTEGER DEFAULT 0,
    failed_submissions INTEGER DEFAULT 0,
    hubspot_synced_count INTEGER DEFAULT 0,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Table: Page Views (optional analytics)
CREATE TABLE IF NOT EXISTS website.page_views (
    id SERIAL PRIMARY KEY,
    page_path VARCHAR(500) NOT NULL,
    visitor_ip VARCHAR(45),
    user_agent TEXT,
    referer VARCHAR(500),
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Index on page views
CREATE INDEX IF NOT EXISTS idx_page_views_path ON website.page_views(page_path);
CREATE INDEX IF NOT EXISTS idx_page_views_timestamp ON website.page_views(timestamp DESC);

-- Table: Newsletter Subscriptions (synced with HubSpot)
CREATE TABLE IF NOT EXISTS website.newsletter_subscribers (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    status VARCHAR(50) DEFAULT 'active',
    hubspot_synced BOOLEAN DEFAULT FALSE,
    hubspot_contact_id VARCHAR(255),
    subscribed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    unsubscribed_at TIMESTAMP
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_newsletter_email ON website.newsletter_subscribers(email);
CREATE INDEX IF NOT EXISTS idx_newsletter_status ON website.newsletter_subscribers(status);
CREATE INDEX IF NOT EXISTS idx_newsletter_hubspot_synced ON website.newsletter_subscribers(hubspot_synced);

-- Grant permissions to application user
GRANT USAGE ON SCHEMA website TO aurigraph;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA website TO aurigraph;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA website TO aurigraph;

-- Log initialization
SELECT 'Aurigraph Website Database with HubSpot Integration Initialized Successfully' AS status;
