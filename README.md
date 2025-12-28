# Ubuntu Backup Script

Bash script tự động backup files/directories, databases (MySQL/PostgreSQL) và gửi đến nhiều remote servers với Telegram notification.

## Tính Năng

- ✅ Backup files/directories thành archive tar.gz
- ✅ Hỗ trợ database dump (MySQL, PostgreSQL)
- ✅ **Multi-server backup** - Gửi đến nhiều servers cùng lúc cho độ an toàn cao
- ✅ Per-server authentication (SSH key hoặc password)
- ✅ Telegram notification với status từng server
- ✅ Resume interrupted transfers (rsync)
- ✅ Tự động cleanup sau khi backup thành công
- ✅ Logging chi tiết

## Yêu Cầu Hệ Thống

**Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install -y rsync tar gzip curl

# Tùy chọn: cho hiệu năng cao (khuyên dùng)
sudo apt install -y zstd pigz

# Tùy chọn: cho password auth
sudo apt install -y sshpass

# Tùy chọn: cho database backup
sudo apt install -y mysql-client    # MySQL/MariaDB
sudo apt install -y postgresql-client  # PostgreSQL
```

## Cài Đặt Nhanh

### 1. Clone hoặc copy project

```bash
cd /opt
git clone <repo-url> backup-script
cd backup-script
```

### 2. Tạo file cấu hình

```bash
cp .env.example .env
chmod 600 .env  # Bảo mật file config
```

### 3. Cấu hình .env

Mở file `.env` và điền thông tin:

```bash
# Các file/thư mục cần backup
BACKUP_TARGETS="
/var/www/html
/etc/nginx
/home/user/myapp
"

# Hoặc dùng file danh sách (khuyên dùng nếu nhiều targets)
# BACKUP_TARGETS_FILE="./backup_targets.list"

# Loại trừ files (không backup)
BACKUP_EXCLUDES="
*.log
node_modules
.git
temp
"

# Danh sách servers (backup đến nhiều nơi)
REMOTE_SERVERS="
vps1:backup@192.168.1.50:22:/backups|/home/user/.ssh/id_rsa
vps2:root@backup.example.com:22:/data/backups|/home/user/.ssh/backup_key
cloud:backup@cloud.com:2222:/storage|password:MyPassword123
"

# Database (nếu cần)
DB_BACKUP_ENABLED=true
DB_TYPE=mysql
DB_HOST=localhost
DB_USER=root
DB_PASSWORD=your_db_password
DB_NAMES="wordpress woocommerce"

# Telegram notification (tùy chọn)
TELEGRAM_BOT_TOKEN="123456:ABC-DEF..."
TELEGRAM_CHAT_ID="-1001234567890"

# Hiệu năng & Nén (auto, zstd, pigz, gzip)
COMPRESSION_ALGO="auto"
COMPRESSION_LEVEL="6"

```

### 4. Setup SSH keys (recommended)

Tạo SSH key nếu chưa có:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/backup_key -N ""
```

Copy key đến remote servers:

```bash
ssh-copy-id -i ~/.ssh/backup_key backup@your-server.com
```

Test connection:

```bash
ssh -i ~/.ssh/backup_key backup@your-server.com
```

### 5. Test chạy thủ công

```bash
./backup.sh
```

Kiểm tra logs:

```bash
tail -f logs/backup-*.log
```

## Cấu Hình Multi-Server

Format cho `REMOTE_SERVERS`:

```
label:user@host:port:/remote/path|auth
```

**Ví dụ:**

```bash
REMOTE_SERVERS="
# Server 1 - SSH key auth
vps1:backup@10.0.0.5:22:/backups/mysite|/home/user/.ssh/id_rsa

# Server 2 - SSH key khác
vps2:root@192.168.1.100:22:/data/backups|/home/user/.ssh/backup_key

# Server 3 - Password auth (cần sshpass)
cloud:backup@cloud.provider.com:2222:/storage/backups|password:MySecurePass123
"
```

**Lưu ý:**
- Script sẽ backup **đồng thời** đến TẤT CẢ servers
- Nếu 1 server fail, vẫn tiếp tục backup đến servers khác
- Local archive chỉ bị xóa nếu ÍT NHẤT 1 server thành công
- Telegram notification hiển thị status của TỪNG server

## Quản Lý Targets & Excludes (Recommended)

Sử dụng file `backup.conf` để quản lý danh sách backup và loại trừ một cách gọn gàng.

**Tạo file `backup.conf`:**

```ini
[TARGETS]
# Web server
/var/www/html
/etc/nginx

# Projects (wildcards supported)
/home/user/projects/*

[EXCLUDES]
# System junk
*.log
*.tmp
.DS_Store

# Dev folders
node_modules
.git
.cache
```

Script sẽ tự động tìm file `backup.conf` cùng thư mục. Nếu muốn đổi tên hoặc đường dẫn, cấu hình trong `.env`:

```bash
BACKUP_CONF_FILE="/path/to/my_backup_config.conf"
```

## Tính Năng Nâng Cao

### 1. Tăng Tốc Độ Nén (Compression)
Script tự động phát hiện và sử dụng công cụ tốt nhất có sẵn:
- **zstd**: Nhanh nhất và nén tốt (Khuyên dùng). Cài đặt: `apt install zstd`
- **pigz**: Nén gzip đa luồng (nhanh hơn gzip thường). Cài đặt: `apt install pigz`
- **gzip**: Mặc định, tương thích cao nhưng chậm hơn.

Cấu hình thủ công:
```bash
COMPRESSION_ALGO="zstd"  # auto, zstd, pigz, gzip
```



## Cấu Hình Database Backup

### MySQL/MariaDB

```bash
DB_BACKUP_ENABLED=true
DB_TYPE=mysql
DB_HOST=localhost
DB_PORT=3306
DB_USER=root
DB_PASSWORD=your_password
DB_NAMES="database1 database2 database3"
```

### PostgreSQL

```bash
DB_BACKUP_ENABLED=true
DB_TYPE=postgres
DB_HOST=localhost
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=your_password
DB_NAMES="database1 database2"
```

**Cách hoạt động:**
1. Script dump từng database thành file `.sql`
2. Lưu vào temp directory
3. Đưa vào archive tar.gz cùng với files khác
4. Cleanup temp directory sau khi nén xong

## Telegram Notification

### Tạo Bot

1. Mở Telegram, tìm [@BotFather](https://t.me/BotFather)
2. Gửi lệnh `/newbot` và làm theo hướng dẫn
3. Copy token: `123456:ABC-DEF...`

### Lấy Chat ID

**Cách 1 - Chat trực tiếp với bot:**

1. Gửi message bất kỳ cho bot của bạn
2. Mở browser: `https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates`
3. Tìm `"chat":{"id":123456789}` - đó là chat ID

**Cách 2 - Group/Channel:**

1. Thêm bot vào group/channel
2. Gửi message trong group
3. Check `getUpdates` như trên
4. Chat ID của group/channel sẽ là số âm: `-1001234567890`

### Cấu hình

```bash
TELEGRAM_BOT_TOKEN="123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11"
TELEGRAM_CHAT_ID="-1001234567890"
```

**Notifications bạn sẽ nhận:**
- 🔄 Backup started (hostname, targets count)
- 📦 Archive created (filename, size MB, duration)
- ✅/❌ Per-server transfer status
- ✅/⚠️/❌ Final summary (success/partial/failed)

## Tự Động Hóa

### Cron Job (Recommended)

Chạy backup hàng ngày lúc 2:00 AM:

```bash
crontab -e
```

Thêm dòng:

```cron
0 2 * * * /opt/backup-script/backup.sh >> /opt/backup-script/logs/cron.log 2>&1
```

Xem thêm: [docs/cron-setup.md](docs/cron-setup.md)

### Systemd Service + Timer

Chạy backup theo schedule với systemd:

```bash
sudo cp docs/backup.service /etc/systemd/system/
sudo cp docs/backup.timer /etc/systemd/system/
sudo systemctl enable backup.timer
sudo systemctl start backup.timer
```

Xem thêm: [docs/systemd-service.md](docs/systemd-service.md)

## Cấu Trúc Project

```
backup-script/
├── backup.sh          # Main script
├── .env               # Config của bạn (gitignored)
├── .env.example       # Template config
├── .gitignore         # Git ignore rules
├── README.md          # File này
├── docs/
│   ├── cron-setup.md
│   └── systemd-service.md
└── logs/              # Backup logs (auto-created)
    └── backup-YYYYMMDD-HHmmss.log
```

## Workflow Script

1. **Load config** từ `.env`
2. **Validate** config và backup targets
3. **Database dump** (nếu enabled) → temp directory
4. **Create archive** tar.gz (includes files + DB dumps)
5. **Parse remote servers** từ config
6. **Loop through servers:**
   - Test SSH connection
   - Transfer với rsync
   - Verify success
   - Send Telegram status
7. **Cleanup:**
   - Xóa temp DB dumps
   - Xóa local archive (nếu ít nhất 1 server OK)
8. **Send final Telegram summary**

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success (ít nhất 1 server OK) |
| 1 | Configuration error |
| 2 | Backup error (tar failed, DB dump failed) |
| 3 | Transfer error (tất cả servers failed) |

## Troubleshooting

### "Permission denied" khi backup

Đảm bảo user chạy script có quyền đọc các files/directories cần backup:

```bash
# Chạy as root nếu backup system files
sudo ./backup.sh
```

### "sshpass not found"

Nếu dùng password auth:

```bash
sudo apt install sshpass
```

Hoặc chuyển sang SSH key (recommended):

```bash
ssh-keygen -t ed25519 -f ~/.ssh/backup_key
ssh-copy-id -i ~/.ssh/backup_key user@server
```

### Telegram notification không hoạt động

1. Check bot token và chat ID có đúng không
2. Test bằng curl:

```bash
curl -X POST "https://api.telegram.org/bot<TOKEN>/sendMessage" \
  -d "chat_id=<CHAT_ID>" \
  -d "text=Test message"
```

3. Đảm bảo bot không bị block và đã start conversation

### Database dump failed

**MySQL:**
```bash
# Test mysqldump manually
mysqldump -h localhost -u root -p database_name > test.sql
```

**PostgreSQL:**
```bash
# Test pg_dump manually
PGPASSWORD=password pg_dump -h localhost -U postgres database_name > test.sql
```

### Transfer quá chậm

Giới hạn bandwidth:

```bash
BANDWIDTH_LIMIT="5000"  # 5 MB/s
```

Hoặc tăng compression level (chậm hơn nhưng file nhỏ hơn):

```bash
COMPRESSION_LEVEL="9"
```

## Security Best Practices

1. **File permissions:**
   ```bash
   chmod 600 .env           # Chỉ owner đọc được
   chmod 700 backup.sh      # Chỉ owner execute được
   chmod 700 logs/          # Chỉ owner access logs
   ```

2. **SSH keys > passwords:**
   - Luôn dùng SSH key nếu có thể
   - Password auth chỉ dùng khi thực sự cần

3. **Database credentials:**
   - MySQL: Dùng `~/.my.cnf` thay vì password trong .env
   - PostgreSQL: Dùng `~/.pgpass` thay vì password trong .env

4. **Git security:**
   - KHÔNG commit file `.env` vào git
   - File `.gitignore` đã config sẵn

## Logs

Logs được lưu tại `logs/backup-YYYYMMDD-HHmmss.log`

Xem log realtime:

```bash
tail -f logs/backup-*.log
```

Tìm errors:

```bash
grep ERROR logs/backup-*.log
```

Log rotation (tự động xóa logs cũ hơn 30 ngày):

```bash
find logs/ -name "backup-*.log" -mtime +30 -delete
```

## License

MIT License - Free to use

## Support

Report issues: [GitHub Issues](https://github.com/yourusername/backup-script/issues)
