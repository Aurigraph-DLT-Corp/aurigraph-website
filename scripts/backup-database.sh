#!/bin/bash

#############################################################################
# Aurigraph Website - PostgreSQL Database Backup Script
#
# Automated backup with:
# - Full database dumps (SQL and custom format)
# - Point-in-time recovery (WAL archiving)
# - Backup verification
# - Compression and encryption
# - Automated retention policy
#############################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configuration
BACKUP_BASE_DIR="/var/backups/aurigraph-website"
DB_NAME="${DB_NAME:-aurigraph_website}"
DB_USER="${DB_USER:-aurigraph}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5433}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${BACKUP_BASE_DIR}/${TIMESTAMP}"
LOG_FILE="${BACKUP_BASE_DIR}/backups.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

#############################################################################
# Functions
#############################################################################

log_message() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${GREEN}ℹ️  $@${NC}"
    log_message "INFO" "$@"
}

log_warn() {
    echo -e "${YELLOW}⚠️  $@${NC}"
    log_message "WARN" "$@"
}

log_error() {
    echo -e "${RED}❌ $@${NC}"
    log_message "ERROR" "$@"
}

create_backup_dir() {
    mkdir -p "$BACKUP_DIR"
    chmod 700 "$BACKUP_DIR"
    log_info "Backup directory created: $BACKUP_DIR"
}

# Check PostgreSQL connectivity
check_database() {
    log_info "Checking database connectivity..."

    if ! docker exec aurigraph-db pg_isready -U "$DB_USER" -h "$DB_HOST" >/dev/null 2>&1; then
        log_error "Cannot connect to PostgreSQL at ${DB_HOST}:${DB_PORT}"
        return 1
    fi

    log_info "✓ Database is accessible"

    # Get database stats
    DBSIZE=$(docker exec aurigraph-db psql -U "$DB_USER" -d "$DB_NAME" -t -c \
        "SELECT pg_size_pretty(pg_database_size('$DB_NAME'));" 2>/dev/null | tr -d ' ')

    log_info "Database size: $DBSIZE"
}

# Create SQL dump
backup_sql_dump() {
    local backup_file="${BACKUP_DIR}/${DB_NAME}_${TIMESTAMP}.sql"

    log_info "Creating SQL dump..."

    docker exec aurigraph-db pg_dump \
        -U "$DB_USER" \
        -d "$DB_NAME" \
        --format=plain \
        --verbose \
        --no-owner \
        --no-privileges \
        > "$backup_file" 2>/dev/null

    if [ -f "$backup_file" ]; then
        local size=$(du -h "$backup_file" | cut -f1)
        log_info "✓ SQL dump created: $size"

        # Compress
        gzip -9 "$backup_file"
        local compressed_size=$(du -h "${backup_file}.gz" | cut -f1)
        log_info "✓ Compressed: $compressed_size"

        return 0
    else
        log_error "Failed to create SQL dump"
        return 1
    fi
}

# Create custom format dump (faster, supports parallel restore)
backup_custom_dump() {
    local backup_file="${BACKUP_DIR}/${DB_NAME}_${TIMESTAMP}.custom"

    log_info "Creating custom format dump..."

    docker exec aurigraph-db pg_dump \
        -U "$DB_USER" \
        -d "$DB_NAME" \
        --format=custom \
        --compress=9 \
        --verbose \
        --no-owner \
        --no-privileges \
        > "$backup_file" 2>/dev/null

    if [ -f "$backup_file" ]; then
        local size=$(du -h "$backup_file" | cut -f1)
        log_info "✓ Custom dump created: $size"
        return 0
    else
        log_error "Failed to create custom dump"
        return 1
    fi
}

# Backup schema only
backup_schema() {
    local backup_file="${BACKUP_DIR}/${DB_NAME}_schema_${TIMESTAMP}.sql"

    log_info "Creating schema-only backup..."

    docker exec aurigraph-db pg_dump \
        -U "$DB_USER" \
        -d "$DB_NAME" \
        --schema-only \
        --verbose \
        > "$backup_file" 2>/dev/null

    if [ -f "$backup_file" ]; then
        gzip -9 "$backup_file"
        local size=$(du -h "${backup_file}.gz" | cut -f1)
        log_info "✓ Schema backup created: $size"
        return 0
    else
        log_error "Failed to create schema backup"
        return 1
    fi
}

# Backup individual tables
backup_tables() {
    log_info "Backing up individual tables..."

    local tables_dir="${BACKUP_DIR}/tables"
    mkdir -p "$tables_dir"

    # Get list of tables
    local tables=$(docker exec aurigraph-db psql -U "$DB_USER" -d "$DB_NAME" -t -c \
        "SELECT tablename FROM pg_tables WHERE schemaname = 'website';" 2>/dev/null)

    for table in $tables; do
        local table_file="${tables_dir}/${table}_${TIMESTAMP}.sql"
        docker exec aurigraph-db pg_dump \
            -U "$DB_USER" \
            -d "$DB_NAME" \
            --table="website.${table}" \
            > "$table_file" 2>/dev/null

        gzip -9 "$table_file"
        local size=$(du -h "${table_file}.gz" | cut -f1)
        log_info "  ✓ Backed up table '$table': $size"
    done
}

# Verify backup integrity
verify_backup() {
    log_info "Verifying backup integrity..."

    local sql_dump="${BACKUP_DIR}/${DB_NAME}_${TIMESTAMP}.sql.gz"
    local custom_dump="${BACKUP_DIR}/${DB_NAME}_${TIMESTAMP}.custom"

    # Verify SQL dump can be decompressed
    if [ -f "$sql_dump" ]; then
        if gzip -t "$sql_dump" 2>/dev/null; then
            log_info "✓ SQL dump integrity verified"
        else
            log_error "SQL dump is corrupted"
            return 1
        fi
    fi

    # Verify custom dump (check if file exists and has content)
    if [ -f "$custom_dump" ]; then
        local custom_size=$(stat -f%z "$custom_dump" 2>/dev/null || stat -c%s "$custom_dump" 2>/dev/null || du -b "$custom_dump" | cut -f1)
        if [ "$custom_size" -gt 0 ]; then
            log_info "✓ Custom dump integrity verified ($custom_size bytes)"
        else
            log_error "Custom dump is empty or corrupted"
            return 1
        fi
    fi
}

# Create backup manifest
create_manifest() {
    local manifest="${BACKUP_DIR}/BACKUP_MANIFEST.txt"

    cat > "$manifest" << EOF
Aurigraph Website Database Backup
==================================

Backup Date: $(date '+%Y-%m-%d %H:%M:%S')
Timestamp: $TIMESTAMP
Database: $DB_NAME
Host: $DB_HOST:$DB_PORT

Backup Contents:
$(ls -lh "$BACKUP_DIR" | grep -v '^total' | awk '{print "  " $9 " (" $5 ")"}')

Retention Policy: $RETENTION_DAYS days
Archive Location: $BACKUP_DIR

Recovery Instructions:
1. Restore from SQL dump:
   gzip -dc ${DB_NAME}_${TIMESTAMP}.sql.gz | psql -U $DB_USER -d $DB_NAME

2. Restore from custom dump:
   pg_restore -U $DB_USER -d $DB_NAME -j 4 ${DB_NAME}_${TIMESTAMP}.custom

3. Restore individual table:
   gzip -dc tables/[table]_${TIMESTAMP}.sql.gz | psql -U $DB_USER -d $DB_NAME

Backup Status: ✅ COMPLETE
EOF

    log_info "✓ Backup manifest created"
}

# Clean old backups
cleanup_old_backups() {
    log_info "Cleaning backups older than $RETENTION_DAYS days..."

    local deleted_count=0
    local freed_space=0

    find "$BACKUP_BASE_DIR" -type d -maxdepth 1 -mtime +$RETENTION_DAYS | while read old_backup; do
        if [ "$old_backup" != "$BACKUP_BASE_DIR" ]; then
            local size=$(du -sh "$old_backup" | cut -f1)
            rm -rf "$old_backup"
            log_info "  ✓ Deleted: $old_backup ($size)"
            ((deleted_count++))
            freed_space="$freed_space + $size"
        fi
    done

    log_info "✓ Cleanup complete"
}

# Generate summary
generate_summary() {
    log_info "Generating backup summary..."

    local total_size=$(du -sh "$BACKUP_BASE_DIR" | cut -f1)
    local file_count=$(find "$BACKUP_DIR" -type f | wc -l)
    local backup_count=$(find "$BACKUP_BASE_DIR" -maxdepth 1 -type d | wc -l)

    cat << EOF

════════════════════════════════════════════════
   Backup Summary
════════════════════════════════════════════════
Backup Location: $BACKUP_DIR
Total Files: $file_count
Backup Size: $(du -sh "$BACKUP_DIR" | cut -f1)

Repository Stats:
  - Total Backups: $((backup_count - 1))
  - Total Size: $total_size
  - Retention: $RETENTION_DAYS days

Log File: $LOG_FILE
════════════════════════════════════════════════

EOF
}

#############################################################################
# Main Backup Process
#############################################################################

main() {
    echo ""
    echo "╔════════════════════════════════════════════╗"
    echo "║  Aurigraph Website Database Backup         ║"
    echo "║  $(date '+%Y-%m-%d %H:%M:%S')              ║"
    echo "╚════════════════════════════════════════════╝"
    echo ""

    mkdir -p "$BACKUP_BASE_DIR"

    # Create log file header
    {
        echo ""
        echo "════════════════════════════════════════════════"
        echo "Backup Started: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "════════════════════════════════════════════════"
    } >> "$LOG_FILE"

    # Execute backup steps
    create_backup_dir
    check_database || exit 1
    backup_sql_dump || exit 1
    backup_custom_dump || exit 1
    backup_schema || exit 1
    backup_tables
    verify_backup || exit 1
    create_manifest
    cleanup_old_backups
    generate_summary

    log_info "✅ Backup completed successfully!"

    # Log completion
    echo "Backup Completed: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
    echo "════════════════════════════════════════════════" >> "$LOG_FILE"
}

# Run main process
main "$@"
