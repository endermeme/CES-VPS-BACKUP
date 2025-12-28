# Systemd Service & Timer Setup

Hướng dẫn chạy backup script với systemd (alternative cho cron, modern hơn).

## Why Systemd Timer?

**Advantages vs Cron:**
- ✅ Better logging (journalctl)
- ✅ Retry on failure
- ✅ Run on boot/startup
- ✅ Resource control (CPU, memory limits)
- ✅ Dependencies (chờ network ready)
- ✅ Easy start/stop/status

**Disadvantages:**
- ❌ Phức tạp hơn cron một chút
- ❌ Chỉ có trên systemd-based systems

## Quick Setup

### 1. Tạo service file

```bash
sudo nano /etc/systemd/system/backup.service
```

Nội dung:

```ini
[Unit]
Description=Backup Script Service
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=backup
Group=backup
WorkingDirectory=/opt/backup-script
ExecStart=/opt/backup-script/backup.sh

# Restart on failure
Restart=on-failure
RestartSec=300

# Resource limits
Nice=19
CPUQuota=50%
MemoryLimit=1G

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=backup-script

[Install]
WantedBy=multi-user.target
```

### 2. Tạo timer file

```bash
sudo nano /etc/systemd/system/backup.timer
```

Nội dung:

```ini
[Unit]
Description=Backup Script Timer
Requires=backup.service

[Timer]
# Chạy hàng ngày lúc 2:00 AM
OnCalendar=daily
OnCalendar=*-*-* 02:00:00

# Nếu miss schedule (máy tắt), chạy ngay khi boot
Persistent=true

# Random delay 0-30 phút (tránh nhiều services cùng chạy)
RandomizedDelaySec=30min

[Install]
WantedBy=timers.target
```

### 3. Enable và start

```bash
# Reload systemd
sudo systemctl daemon-reload

# Enable timer (auto-start on boot)
sudo systemctl enable backup.timer

# Start timer
sudo systemctl start backup.timer

# Check status
sudo systemctl status backup.timer
```

### 4. Verify

```bash
# List all timers
systemctl list-timers

# Check next run time
systemctl list-timers backup.timer
```

## Timer Schedule Examples

### Daily at specific time

```ini
# Hàng ngày lúc 2:00 AM
OnCalendar=*-*-* 02:00:00

# Hàng ngày lúc 3:30 AM
OnCalendar=*-*-* 03:30:00
```

### Multiple times per day

```ini
# Mỗi 6 giờ
OnCalendar=00/6:00:00

# Hoặc specify từng thời điểm
OnCalendar=*-*-* 02:00:00
OnCalendar=*-*-* 08:00:00
OnCalendar=*-*-* 14:00:00
OnCalendar=*-*-* 20:00:00
```

### Weekly

```ini
# Chủ nhật lúc 1:00 AM
OnCalendar=Sun *-*-* 01:00:00

# Thứ 2-6 lúc 11:00 PM
OnCalendar=Mon..Fri *-*-* 23:00:00
```

### Monthly

```ini
# Ngày 1 hàng tháng lúc 2:00 AM
OnCalendar=*-*-01 02:00:00

# Ngày 15 hàng tháng
OnCalendar=*-*-15 02:00:00
```

### Relative timers

```ini
# 5 phút sau khi boot
OnBootSec=5min

# 10 phút sau khi systemd starts
OnStartupSec=10min

# Lặp lại mỗi 1 giờ
OnUnitActiveSec=1h
```

## Service File Options

### Run as specific user

```ini
[Service]
User=backupuser
Group=backupuser
```

Tạo user:

```bash
sudo useradd -r -s /bin/false backupuser
sudo chown -R backupuser:backupuser /opt/backup-script
```

### Environment variables

```ini
[Service]
Environment="DEBUG=false"
Environment="COMPRESSION_LEVEL=9"
EnvironmentFile=/opt/backup-script/.env
```

### Resource limits

```ini
[Service]
# Low priority (nice 19)
Nice=19

# Max 50% CPU
CPUQuota=50%

# Max 1GB RAM
MemoryLimit=1G

# Max 2GB disk I/O
IOWeight=100
```

### Retry on failure

```ini
[Service]
Restart=on-failure
RestartSec=300
StartLimitBurst=3
StartLimitIntervalSec=600
```

### Timeout

```ini
[Service]
TimeoutStartSec=60s
TimeoutStopSec=30s

# No timeout for long backups
TimeoutStartSec=infinity
```

### Dependencies

```ini
[Unit]
# Wait for network
After=network-online.target
Wants=network-online.target

# Run after MySQL
After=mysql.service

# Require PostgreSQL running
Requires=postgresql.service
```

## Managing Service

### Manual run

```bash
# Run once manually
sudo systemctl start backup.service

# Check status
sudo systemctl status backup.service
```

### View logs

```bash
# View all logs
sudo journalctl -u backup.service

# Follow logs realtime
sudo journalctl -u backup.service -f

# Logs from today
sudo journalctl -u backup.service --since today

# Last 100 lines
sudo journalctl -u backup.service -n 100

# Last 1 hour
sudo journalctl -u backup.service --since "1 hour ago"
```

### Control timer

```bash
# Start timer
sudo systemctl start backup.timer

# Stop timer
sudo systemctl stop backup.timer

# Restart timer
sudo systemctl restart backup.timer

# Enable (auto-start on boot)
sudo systemctl enable backup.timer

# Disable
sudo systemctl disable backup.timer

# Check status
sudo systemctl status backup.timer

# List all timers
systemctl list-timers
```

## Advanced Configuration

### Run on boot

```ini
[Service]
Type=oneshot
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

Enable:

```bash
sudo systemctl enable backup.service
```

### Email notification on failure

Tạo override:

```bash
sudo systemctl edit backup.service
```

Thêm:

```ini
[Service]
OnFailure=failure-email@%i.service
```

Tạo email service (cần mailutils):

```bash
sudo nano /etc/systemd/system/failure-email@.service
```

```ini
[Unit]
Description=Send email on %i failure

[Service]
Type=oneshot
ExecStart=/usr/bin/bash -c 'echo "Service %i failed" | mail -s "Backup Failed" admin@example.com'
```

### Conditional execution

Chỉ chạy nếu có kết nối mạng:

```ini
[Unit]
ConditionPathExists=/opt/backup-script/.env
ConditionPathExists=/opt/backup-script/backup.sh

[Service]
ExecStartPre=/bin/ping -c 1 backup.example.com
```

### Multiple instances

Template service:

```bash
sudo nano /etc/systemd/system/backup@.service
```

```ini
[Unit]
Description=Backup %i

[Service]
Type=oneshot
ExecStart=/opt/backup-script/backup.sh --profile=%i
```

Usage:

```bash
sudo systemctl start backup@mysql.service
sudo systemctl start backup@files.service
```

## Monitoring

### Check timer schedule

```bash
systemctl list-timers --all
```

Output:

```
NEXT                         LEFT          LAST PASSED UNIT
Thu 2024-12-21 02:00:00 UTC  8h left       n/a  n/a    backup.timer
```

### Check last run

```bash
systemctl status backup.service
```

### Export logs to file

```bash
sudo journalctl -u backup.service --since "2024-12-01" > backup-logs.txt
```

### Log rotation

Systemd auto-rotates logs. Configure:

```bash
sudo nano /etc/systemd/journald.conf
```

```ini
[Journal]
SystemMaxUse=500M
MaxFileSec=1month
```

Restart:

```bash
sudo systemctl restart systemd-journald
```

## Troubleshooting

### Timer not firing

```bash
# Check timer status
sudo systemctl status backup.timer

# Check timer list
systemctl list-timers backup.timer

# Enable if needed
sudo systemctl enable backup.timer
sudo systemctl start backup.timer
```

### Service fails

```bash
# Check logs
sudo journalctl -u backup.service -n 50

# Test manual run
sudo systemctl start backup.service

# Check environment
sudo systemctl show backup.service

# Debug mode
sudo systemd-run --unit=backup-test /opt/backup-script/backup.sh
```

### Permission errors

```bash
# Check service user
sudo systemctl show backup.service | grep User

# Fix ownership
sudo chown -R backup:backup /opt/backup-script
```

## Uninstall

```bash
# Stop and disable
sudo systemctl stop backup.timer
sudo systemctl disable backup.timer
sudo systemctl stop backup.service
sudo systemctl disable backup.service

# Remove files
sudo rm /etc/systemd/system/backup.service
sudo rm /etc/systemd/system/backup.timer

# Reload
sudo systemctl daemon-reload
```

## Best Practices

1. **Use timers, not service Install**
2. **Enable Persistent=true** để chạy missed schedules
3. **Set resource limits** để không ảnh hưởng hệ thống
4. **Use journalctl** thay vì file logs
5. **Monitor with systemctl list-timers**
6. **Test với systemctl start** trước khi enable timer
7. **Combine với Telegram notifications** thay email

## Example: Production Setup

```bash
# /etc/systemd/system/backup.service
[Unit]
Description=Production Backup Service
After=network-online.target mysql.service
Wants=network-online.target

[Service]
Type=oneshot
User=backup
Group=backup
WorkingDirectory=/opt/backup-script
ExecStart=/opt/backup-script/backup.sh

Restart=on-failure
RestartSec=300
StartLimitBurst=2

Nice=19
CPUQuota=30%
MemoryLimit=512M

StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

```bash
# /etc/systemd/system/backup.timer
[Unit]
Description=Production Backup Timer
Requires=backup.service

[Timer]
OnCalendar=*-*-* 02:00:00
Persistent=true
RandomizedDelaySec=10min

[Install]
WantedBy=timers.target
```

Deploy:

```bash
sudo systemctl daemon-reload
sudo systemctl enable backup.timer
sudo systemctl start backup.timer
systemctl list-timers backup.timer
```
