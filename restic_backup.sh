#!/bin/bash

#############################################
# Restic Backup Script with S3 and Slack
# Executes hourly backups with retention policy
# Sends alerts to Slack on failure if SLACK_WEBHOOK_URL is set
#############################################

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Configuration
source $(dirname $0)/.env

# Ensure PATH includes common binary locations (cron has minimal PATH)
export PATH="${PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}"
HOSTNAME="${HOSTNAME:-$(hostname)}"

#############################################
# Functions
#############################################

# Logging function
log_message() {
    local level=$1
    local message=$2
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${TIMESTAMP}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

# Send Slack notification on failure
send_slack_alert() {
    local level=$1
    local message=$2
    local details=$3

    if [ -z "${SLACK_WEBHOOK_URL}" ]; then
        log_message "DEBUG" "Slack webhook not configured, skipping notification"
        return 0
    fi
    
    if [ ! -z "${SLACK_CHANNEL}" ]; then
        CHANNEL="\"channel\": \"$SLACK_CHANNEL\","
    fi
    
    # Determine color based on level
    local color="good"
    local emoji=":white_check_mark:"
    if [ "$level" = "ERROR" ]; then
        color="danger"
        emoji=":x:"
    elif [ "$level" = "WARNING" ]; then
        color="warning"
        emoji=":warning:"
    fi
    
    # Escape special characters for JSON
    message=$(echo "$message" | sed 's/"/\\"/g')
    details=$(echo "$details" | sed 's/"/\\"/g' | head -c 1000)
    
    # Create payload
    local payload=$(cat <<EOF
{
    "username": "Restic Backup (Cron)",
    "icon_emoji": "${emoji}",
    ${CHANNEL}
    "attachments": [
        {
            "color": "${color}",
            "title": "${level}: ${message}",
            "fields": [
                {
                    "title": "Host",
                    "value": "${HOSTNAME}",
                    "short": true
                },
                {
                    "title": "Time",
                    "value": "${TIMESTAMP}",
                    "short": true
                },
                {
                    "title": "Details",
                    "value": "${details}",
                    "short": false
                },
                {
                    "title": "Path to Backup",
                    "value": "${BACKUP_DIR}",
                    "short": false
                }
            ],
            "footer": "Restic Cron Backup"
        }
    ]
}
EOF
)
    
    # Send to Slack (silent, no output to avoid cron emails)
    curl -X POST -H 'Content-type: application/json' \
        --data "${payload}" \
        "${SLACK_WEBHOOK_URL}" \
        -s -o /dev/null 2>&1 || true
}

# Check if restic repository exists and is properly configured
check_repository() {
    log_message "INFO" "Checking restic repository configuration..."
    
    # Check if repository is initialized
    if ! restic -r $RESTIC_REPOSITORY check --no-lock 2>/dev/null; then
        log_message "WARN" "Repository check failed or not initialized. Attempting to initialize..."
        
        # Try to initialize the repository
        if ! restic -r $RESTIC_REPOSITORY init 2>&1 | tee -a "${LOG_FILE}"; then
            local error_msg="Failed to initialize restic repository"
            log_message "ERROR" "${error_msg}"
            send_slack_alert "ERROR" "${error_msg}" "Could not initialize repository at ${RESTIC_REPOSITORY}"
            return 1
        fi
        
        log_message "INFO" "Repository initialized successfully"
    else
        log_message "INFO" "Repository check passed"
    fi
    
    # Test S3 connectivity
    log_message "INFO" "Testing S3 connectivity..."
    if ! restic -r $RESTIC_REPOSITORY list locks 2>&1 | tee -a "${LOG_FILE}"; then
        local error_msg="S3 connectivity test failed"
        log_message "ERROR" "${error_msg}"
        send_slack_alert "ERROR" "${error_msg}" "Cannot connect to S3 bucket. Check AWS credentials and network."
        return 1
    fi
    
    log_message "INFO" "S3 connectivity test passed"
    return 0
}

# Perform the backup
perform_backup() {
    log_message "INFO" "Starting backup of ${BACKUP_DIR}..."
    
    # Create backup with tags for easier identification
    local backup_output
    backup_output=$(restic -r $RESTIC_REPOSITORY backup \
        --verbose \
        --tag $BACKUP_TAG \
        --host $HOSTNAME \
        "${BACKUP_DIR}" 2>&1)
    
    local backup_status=$?
    
    # Log the output
    echo "${backup_output}" >> "${LOG_FILE}"
    
    if [ ${backup_status} -ne 0 ]; then
        local error_msg="Backup operation failed"
        log_message "ERROR" "${error_msg}"
        send_slack_alert "ERROR" "${error_msg}" "${backup_output}"
        return 1
    fi
    
    # Extract and log backup statistics
    local stats=$(echo "${backup_output}" | grep -E "(Added|processed|snapshot)" | tail -5)
    log_message "INFO" "Backup completed successfully"
    log_message "INFO" "Backup stats: ${stats}"
    
    return 0
}

# Apply retention policy
apply_retention_policy() {
    log_message "INFO" "Applying retention policy..."
    
    local retention_output
    retention_output=$(restic -r $RESTIC_REPOSITORY forget \
        --keep-hourly $KEEP_HOURLY \
        --keep-daily $KEEP_DAILY \
        --keep-weekly $KEEP_WEEKLY \
        --keep-monthly $KEEP_MONTHLY \
        --keep-yearly $KEEP_YEARLY \
        --tag $BACKUP_TAG \
        --host $HOSTNAME \
        --prune \
        --verbose 2>&1)
    
    local retention_status=$?
    
    # Log the output
    echo "${retention_output}" >> "${LOG_FILE}"
    
    if [ ${retention_status} -ne 0 ]; then
        local error_msg="Retention policy application failed"
        log_message "ERROR" "${error_msg}"
        send_slack_alert "ERROR" "${error_msg}" "${retention_output}"
        return 1
    fi
    
    log_message "INFO" "Retention policy applied successfully"
    return 0
}

# Check repository health
check_repository_health() {
    log_message "INFO" "Running repository health check..."
    
    local check_output
    check_output=$(restic -r $RESTIC_REPOSITORY check --read-data-subset=${CHECK_PERCENTAGE} 2>&1)
    local check_status=$?
    
    echo "${check_output}" >> "${LOG_FILE}"
    
    if [ ${check_status} -ne 0 ]; then
        local error_msg="Repository health check failed"
        log_message "ERROR" "${error_msg}"
        send_slack_alert "ERROR" "${error_msg}" "${check_output}"
        return 1
    fi
    
    log_message "INFO" "Repository health check passed"
    return 0
}

# Cleanup function
cleanup() {
    log_message "INFO" "Cleaning up..."
    # Remove any stale locks older than 2 hours
    restic -r $RESTIC_REPOSITORY unlock --remove-all 2>&1 | tee -a "${LOG_FILE}"
}

# Main execution with error tracking
main() {
    local exit_code=0
    
    log_message "INFO" "=== Starting Restic Backup Job ==="
    
    # Check if another instance is running
    LOCKFILE="/var/run/restic-backup.lock"
    if [ -f "${LOCKFILE}" ]; then
        PID=$(cat "${LOCKFILE}")
        if ps -p ${PID} > /dev/null 2>&1; then
            log_message "WARN" "Another backup process is already running (PID: ${PID}). Exiting."
            exit 0
        else
            log_message "INFO" "Removing stale lock file"
            rm -f "${LOCKFILE}"
        fi
    fi
    
    # Create lock file
    echo $$ > "${LOCKFILE}"
    
    # Ensure lock file is removed on exit
    trap "rm -f ${LOCKFILE}; cleanup" EXIT
    
    # Execute backup steps
    if ! check_repository; then
        exit_code=1
    elif ! perform_backup; then
        exit_code=1
    elif ! apply_retention_policy; then
        exit_code=1
    elif ! check_repository_health; then
        # Health check failure is non-critical but should be reported
        log_message "WARN" "Health check failed but backup completed"
    fi
    
    # Log summary
    if [ ${exit_code} -eq 0 ]; then
        log_message "INFO" "=== Backup Job Completed Successfully ==="
        send_slack_alert "INFO" "Backup Job Completed Successfully" "Backup OK"
    else
        log_message "ERROR" "=== Backup Job Failed ==="
        #send_slack_alert "ERROR" "Backup job failed with errors" "Check ${LOG_FILE} for details"
    fi
    
    # Cleanup
    rm -f "${LOCKFILE}"
    
    exit ${exit_code}
}

#############################################
# Script Entry Point
#############################################

# # Error handler for unexpected exits
# error_handler() {
#     local line_no=$1
#     local exit_code=$2
#     log_message "ERROR" "Script failed at line ${line_no} with exit code ${exit_code}"
#     send_slack_alert "ERROR" "Backup Script Crashed" "Line: ${line_no}, Exit Code: ${exit_code}"
#     rm -f "${LOCKFILE}"
#     exit ${exit_code}
# }

# # Set error trap
# trap 'error_handler ${LINENO} $?' ERR

# Check if running as root (recommended for system backups)
if [ "$EUID" -ne 0 ] && [ -z "${ALLOW_NON_ROOT}" ]; then 
    log_message "WARN" "Not running as root. Some files may not be accessible."
fi

# Check required commands
for cmd in restic curl; do
    if ! command -v ${cmd} &> /dev/null; then
        error_msg="Required command '${cmd}' not found"
        log_message "ERROR" "${error_msg}"
        send_slack_alert "ERROR" "${error_msg}" "Please install ${cmd} to continue"
        exit 1
    fi
done

# Check required environment variables
if [ -z "${RESTIC_PASSWORD}" ] && [ -z "${RESTIC_PASSWORD_FILE}" ]; then
    error_msg="RESTIC_PASSWORD or RESTIC_PASSWORD_FILE must be set"
    log_message "ERROR" "${error_msg}"
    send_slack_alert "ERROR" "${error_msg}" "Missing restic password configuration"
    exit 1
fi

# Run main function
main