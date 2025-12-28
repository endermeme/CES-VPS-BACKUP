# Cron Job Setup Guide

Hướng dẫn cấu hình backup tự động với cron.

## Quick Setup

### 1. Mở crontab editor

```bash
crontab -e
```

Lần đầu sẽ hỏi editor, chọn nano (option 1) nếu chưa quen vim.

### 2. Thêm cron job

Thêm dòng này vào cuối file:

```cron
# Backup hàng ngày lúc 2:00 AM
0 2 * * * /opt/backup-script/backup.sh >> /opt/backup-script/logs/cron.log 2>&1
```

**Lưu ý:** Thay `/opt/backup-script` bằng đường dẫn thực tế của script.

### 3. Lưu và thoát

- Nano: `Ctrl+O` (save), `Enter`, `Ctrl+X` (exit)
- Vim: `ESC`, `:wq`, `Enter`

### 4. Verify cron job

```bash
crontab -l
```

## Cron Schedule Examples

```cron
# Hàng ngày lúc 2:00 AM
0 2 * * * /path/to/backup.sh

# Hàng ngày lúc 3:30 AM
30 3 * * * /path/to/backup.sh

# Mỗi 6 giờ
0 */6 * * * /path/to/backup.sh

# Hàng tuần (Chủ nhật lúc 1:00 AM)
0 1 * * 0 /path/to/backup.sh

# Hàng tháng (ngày 1 lúc 2:00 AM)
0 2 1 * * /path/to/backup.sh

# Thứ 2-6 lúc 11:00 PM
0 23 * * 1-5 /path/to/backup.sh
```

### Cron Format

```
* * * * * command
│ │ │ │ │
│ │ │ │ └─── Ngày trong tuần (0-7, 0 và 7 = Chủ nhật)
│ │ │ └───── Tháng (1-12)
│ │ └─────── Ngày trong tháng (1-31)
│ └───────── Giờ (0-23)
└─────────── Phút (0-59)
```

## Advanced Setup

### Run as root (cho system files)

```bash
sudo crontab -e
```

Thêm:

```cron
0 2 * * * /opt/backup-script/backup.sh >> /var/log/backup-cron.log 2>&1
```

### Multiple schedules

```cron
# Backup files hàng ngày lúc 2 AM
0 2 * * * /opt/backup-script/backup.sh >> /opt/backup-script/logs/daily.log 2>&1

# Backup database riêng mỗi 4 giờ
0 */4 * * * /opt/backup-script/backup-db-only.sh >> /opt/backup-script/logs/db.log 2>&1
```

### Email notifications

Cron tự động email output nếu có lỗi. Setup email:

```cron
MAILTO=admin@example.com

0 2 * * * /opt/backup-script/backup.sh
```

### Environment variables

Cron có environment khác với shell. Set PATH:

```cron
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

0 2 * * * /opt/backup-script/backup.sh >> /opt/backup-script/logs/cron.log 2>&1
```

### Logging best practices

**Separate log per run:**

```cron
0 2 * * * /opt/backup-script/backup.sh 2>&1 | tee -a /opt/backup-script/logs/cron-$(date +\%Y\%m\%d).log
```

**Rotate logs:**

```cron
# Backup lúc 2 AM
0 2 * * * /opt/backup-script/backup.sh >> /opt/backup-script/logs/cron.log 2>&1

# Cleanup logs cũ hơn 30 ngày (lúc 3 AM)
0 3 * * * find /opt/backup-script/logs -name "*.log" -mtime +30 -delete
```

## Monitoring Cron Jobs

### Check if cron is running

```bash
systemctl status cron
```

Hoặc:

```bash
service cron status
```

### View cron logs

```bash
# Ubuntu/Debian
grep CRON /var/log/syslog

# Hoặc
journalctl -u cron
```

### Check last run time

```bash
ls -lah /opt/backup-script/logs/
```

### Manual test

Chạy command giống cron sẽ chạy:

```bash
/opt/backup-script/backup.sh >> /opt/backup-script/logs/test.log 2>&1
```

## Troubleshooting

### Cron job không chạy

1. **Check cron service:**

```bash
sudo systemctl status cron
sudo systemctl restart cron
```

2. **Check permissions:**

```bash
chmod +x /opt/backup-script/backup.sh
ls -l /opt/backup-script/backup.sh
```

3. **Check paths:**

Dùng absolute paths trong cron:
- ✅ `/opt/backup-script/backup.sh`
- ❌ `./backup.sh`
- ❌ `~/backup-script/backup.sh`

4. **Test manually:**

```bash
# Run as cron would
env -i /bin/bash -c "/opt/backup-script/backup.sh"
```

### Script chạy manual OK nhưng cron fail

**Environment khác nhau.** Add vào đầu script:

```bash
#!/usr/bin/env bash
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/home/username

# Rest of script...
```

Hoặc thêm vào crontab:

```cron
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
HOME=/home/username

0 2 * * * /opt/backup-script/backup.sh
```

### Permission denied errors

```bash
# Fix ownership
sudo chown -R $USER:$USER /opt/backup-script

# Fix permissions
chmod 700 /opt/backup-script/backup.sh
chmod 700 /opt/backup-script/logs
```

### No email from cron

Install mail utilities:

```bash
sudo apt install mailutils
```

Test:

```bash
echo "Test" | mail -s "Cron test" your@email.com
```

## Remove Cron Job

```bash
crontab -e
```

Xóa dòng cron job, save và exit.

Hoặc xóa toàn bộ:

```bash
crontab -r
```

## Best Practices

1. **Always use absolute paths**
2. **Redirect output:** `>> logfile 2>&1`
3. **Test manually first**
4. **Monitor logs regularly**
5. **Rotate old logs**
6. **Use Telegram notifications** thay vì email
7. **Run at off-peak hours** (2-4 AM)
8. **Don't run too frequently** (databases need rest)

## Alternative: Systemd Timer

Nếu muốn control tốt hơn, xem [systemd-service.md](systemd-service.md)
