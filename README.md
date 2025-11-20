# Restic Automated Backup System

A robust, production-ready backup solution using Restic with S3 storage.

## ⚠️ Important Disclaimer

**USE AT YOUR OWN RISK** - This software comes with NO WARRANTY. You are solely responsible for your data. See [DISCLAIMER.md](DISCLAIMER.md) for important warnings and [LICENSE](LICENSE) for terms.

## Features

- S3-compatible storage (AWS S3, Backblaze B2, MinIO)
- Intelligent retention policy (hourly/daily/weekly/monthly/yearly)
- Encrypted backups with password protection
- Optional Slack notifications for failures
- Automatic repository initialization

## Prerequisites

- Linux system (Ubuntu/Debian/CentOS/RHEL)
- Root or sudo access
- S3-compatible storage (AWS S3, Backblaze B2, or similar)
- Git (for cloning the repository)

## Quick Start

### 1. Clone the Repository

```bash
# Clone the repository
git clone https://github.com/NexGenCloud/restic_backup.git
cd restic_backup
chmod 755 restic_backup.sh
```

### 2. Install Restic

```bash
#RECOMMENDED:
#download latest binary
wget https://github.com/restic/restic/releases/download/v0.18.1/restic_0.18.1_linux_amd64.bz2
bunzip2 restic_0.18.1_linux_amd64.bz2
sudo mv restic_0.18.1_linux_amd64 /usr/local/bin/restic
sudo chmod +x /usr/local/bin/restic

# OR install via package managers (possible outdated versions)
# Ubuntu/Debian
sudo apt-get update && sudo apt-get install -y restic
# CentOS/RHEL
sudo yum install -y restic

# Rocky
sudo dnf install -y restic


## Check version +0.16 RECOMMENDED
restic version 
## restic 0.18.1 compiled with go1.25.1 on linux/amd64

```

### 3. Configure Your Backup

```bash
# Copy the example configuration
sudo cp .env.example .env
sudo chmod 600 .env

# Edit with your settings
sudo nano .env
```

#### Essential Configuration

Edit `.env` with your values:

```bash
# S3 Repository
export RESTIC_REPOSITORY="s3:s3.amazonaws.com/my-bucket/backups"
export RESTIC_PASSWORD="ChooseAStrongPasswordHere"

# AWS Credentials
export AWS_ACCESS_KEY_ID="YOUR_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="YOUR_SECRET_KEY"

# What to backup
export BACKUP_DIRS="/home /etc /var/www"
export BACKUP_TAG="cron-hourly"

# Optional: Slack notifications
export SLACK_WEBHOOK_URL=""  # Leave empty to disable
export SLACK_CHANNEL="yourchannel" #optional

# Optional lock & logging 
export LOG_FILE="/var/log/restic-backup.log"
export LOCKFILE="/var/run/restic-backup-cron.lock"

# Optional BUT USEFUL IF RUNNING IN DOCKER, override hostname
export HOSTNAME=yourhostname
```

### 4. Test Your Configuration

```bash
source .env 
sudo -E touch $LOG_FILE
sudo -E chmod 644 $LOG_FILE

# Test the backup manually
sudo ./restic_backup.sh

# Check the log
cat $LOG_FILE

# List snapshots
sudo -E restic snapshots

# Check repository integrity
sudo -E restic check
```

### 5. Set Up Cron for Automatic Backups

```bash
# Edit root's crontab
sudo crontab -e

# NOTE: change /home/user/restic_backup/restic_backup.sh to the actual path of this repo
# Add one of these schedules or setup yours:
# Every hour at minute 0
0 * * * * /home/user/restic_backup/restic_backup.sh >/dev/null 2>&1
# Every day at 5:00 AM
0 5 * * * /home/user/restic_backup/restic_backup.sh >/dev/null 2>&1
# Every Monday at 4am
0 4 * * MON /home/user/restic_backup/restic_backup.sh >/dev/null 2>&1

# Verify cron entry
sudo crontab -l
```

## Configuration Options

### Retention Policy

Control how many snapshots to keep in `.env`:

```bash
export KEEP_HOURLY="24"   # Keep 24 hourly snapshots
export KEEP_DAILY="7"     # Keep 7 daily snapshots
export KEEP_WEEKLY="4"    # Keep 4 weekly snapshots
export KEEP_MONTHLY="6"   # Keep 6 monthly snapshots
export KEEP_YEARLY="2"    # Keep 2 yearly snapshots
```

### Slack Notifications

To enable Slack alerts:

1. Create a Slack webhook: https://api.slack.com/messaging/webhooks
2. Add to configuration

## Testing and Validation

### 1. Manual Backup Test

```bash
# Run backup manually and watch output
# NOTE: change /home/user/restic_backup/restic_backup.sh to the actual path of this repo
sudo /home/user/restic_backup/restic_backup.sh 2>&1 | tee test-backup.log
```

### 2. Verify Backups

```bash
# Source environment
source .env

# List all snapshots
restic snapshots

# Show detailed snapshot info
restic snapshots --json | jq .

# Check repository integrity
restic check

# Test restore (to temporary directory)
restic restore latest --target /tmp/test-restore --host yourhostname
ls -la /tmp/test-restore
```

### 4. Monitor Cron Execution

```bash
# Check if cron is running backups
grep CRON /var/log/syslog | grep restic

# Monitor backup log
tail -f /var/log/restic-backup.log

# Check last backup time
grep "Backup Job Completed Successfully" /var/log/restic-backup.log | tail -1
```

## Restore Operations

### Restore Latest Backup

```bash
# Source credentials
source .env

# Restore to original location (be careful!)
restic restore latest --target /

# Restore latest backup from a host to different location 
restic restore latest --target /tmp/restore --host yourhostname
```

### Restore Specific File or Directory

```bash
# Find file in snapshots
restic find filename.txt

# Restore specific path from latest
restic restore latest --target /tmp/restore --include /path/to/file

# Restore from specific snapshot
restic restore abc12345 --target /tmp/restore
```

### Browse Backup Contents

```bash
## NOTE requires fuse package 
# Mount repository as filesystem
mkdir /mnt/restic
restic mount /mnt/restic &

# Browse files
ls -la /mnt/restic
cd /mnt/restic/snapshots/latest

# Unmount when done
umount /mnt/restic
```

### Clean Up Repository

```bash
# Remove old snapshots according to policy
source .env
restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune

# Clean up unreferenced data
restic prune

# Full repository check
restic check --read-data
```

## Multiple Backup Jobs

The script defaults to `.env`, although it supports different env files as 1st parameter
To backup different directories on different schedules:

```bash
# Create multiple configs
cp .env .env_db 
cp .env .env_web  
# Edit each config with different BACKUP_DIR and BACKUP_TAG
sudo nano .env_db
sudo nano .env_web
# NOTE: .env files and backup script must be on same directory

# Create wrapper scripts
cat << 'EOF' | sudo tee /home/user/restic_backup/backup_db.sh
#!/bin/bash
# Sample db dump and call for restic
mysqldump --all-databases > /backup/mysql-dump.sql
/home/user/restic_backup/restic_backup.sh .env_db
EOF

sudo chmod +x /home/user/restic_backup/backup*.sh

# Add to cron with different schedules
sudo crontab -e
# Add:
# 0 */2 * * * /home/user/restic_backup/backup_db.sh >/dev/null 2>&1
# 0 */6 * * * /home/user/restic_backup/backup_web.sh >/dev/null 2>&1
```

## Troubleshooting

### Common Issues

#### 1. "Repository not found"
```bash
# Initialize repository
source .env
restic init
```

#### 2. "Permission denied"
```bash
# Check file permissions
ls -la .env  # Should be 600
ls -la restic_backup.sh  # Should be 755

# Run with sudo
sudo /home/user/restic_backup/restic-backup.sh
```

#### 3. "Another backup is running"
```bash
# Check for stuck process
ps aux | grep restic

# Remove stale lock file if needed and no backups are running
sudo rm /var/run/restic-backup-cron.lock
```

#### 4. S3 Connection Issues
```bash
# Test S3 access
source .env
aws s3 ls s3://your-bucket/

# Check credentials
echo $AWS_ACCESS_KEY_ID
echo $AWS_SECRET_ACCESS_KEY
```

### Debug Mode

For detailed debugging:

```bash
# Run with bash debug mode
bash -x ./restic_backup.sh 2>&1 | tee debug.log

```

## License

MIT License - See LICENSE file for details

## Support

- Restic Documentation: https://restic.readthedocs.io/
- Report Issues: https://github.com/NexGenCloud/restic_backup/issues
- Restic Forum: https://forum.restic.net/

## Contributing

Pull requests welcome! Please test your changes thoroughly and update documentation.

## Changelog

### v1.0.0 (2024)
- Initial release
- S3 backend support
- Slack notifications
- Automatic retention management
- Cron integration

