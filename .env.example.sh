#!/bin/bash
# Restic Cron Environment File
# Source this file in your cron script
# chmod 600 /etc/restic/restic-cron.env
# chown root:root /etc/restic/restic-cron.env

export HOSTNAME=$(hostname)

# Repository Configuration
export RESTIC_REPOSITORY="s3:s3.amazonaws.com/your-bucket/backup-repo"
export RESTIC_PASSWORD="your-secure-restic-password"

# AWS S3 Credentials
export AWS_ACCESS_KEY_ID="your-aws-access-key"
export AWS_SECRET_ACCESS_KEY="your-aws-secret-key"

# Backup Settings
export BACKUP_DIR="/path/to/backup/directory"
export LOG_FILE="/var/log/restic-backup.log"
export LOCKFILE="/var/run/restic-backup-cron.lock"

# Optional: Slack Notifications (leave empty or comment out to disable)
# export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
export SLACK_WEBHOOK_URL=""

# Retention Policy Settings
export KEEP_HOURLY="24"
export KEEP_DAILY="7"
export KEEP_WEEKLY="4"
export KEEP_MONTHLY="6"
export KEEP_YEARLY="2"

# Backup Tags
export BACKUP_TAG="cron-hourly"

# Repository Check Settings
export CHECK_PERCENTAGE="5"  # Percentage of data to verify during integrity check

# Ensure proper PATH for cron
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"