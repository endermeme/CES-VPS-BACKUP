# Hướng Dẫn Setup Chi Tiết File .env

## 1. BACKUP_TARGETS - Thư Mục/File Cần Backup

### Cách 1: Nhiều thư mục trên cùng 1 dòng (space-separated)

```bash
BACKUP_TARGETS="/var/www/html /etc/nginx /home/user/app"
```

### Cách 2: Mỗi thư mục 1 dòng (recommended - dễ đọc)

```bash
BACKUP_TARGETS="
/var/www/html
/etc/nginx
/home/user/app
/home/user/documents
/opt/myapp
"
```

### Cách 3: Mix cả file và thư mục

```bash
BACKUP_TARGETS="
/var/www/html
/etc/nginx/nginx.conf
/etc/php/7.4/fpm/php.ini
/home/user/.ssh/config
/opt/myapp
"
```

### Lưu Ý:

1. **Absolute paths** (bắt đầu bằng `/`) - KHÔNG dùng relative paths
   - ✅ `/var/www/html`
   - ❌ `./html`
   - ❌ `../html`

2. **Home directory shortcut** - Dùng `~` cho home directory
   ```bash
   BACKUP_TARGETS="
   ~/myproject
   ~/.config
   ~/.ssh
   "
   ```

3. **Spaces trong path** - Script tự động handle, không cần escape
   ```bash
   BACKUP_TARGETS="
   /var/www/My Website
   /home/user/My Documents
   "
   ```

4. **Thư mục rỗng** - Vẫn backup được
   ```bash
   BACKUP_TARGETS="/empty/directory"
   ```

5. **Symbolic links** - Tar sẽ follow links
   ```bash
   BACKUP_TARGETS="/var/www/current"  # Nếu là symlink → backup nội dung actual
   ```

---

## 2. REMOTE_SERVERS - Danh Sách Máy Chủ Nhận Backup

### Format Chuẩn

```
label:user@host:port:/remote/path|auth
```

**Phần tử:**
- `label` - Tên gọi server (tự đặt, dùng cho logs)
- `user` - Username SSH
- `host` - Hostname hoặc IP address
- `port` - SSH port (thường là 22)
- `/remote/path` - Đường dẫn trên server đích
- `auth` - Phương thức xác thực

### Ví Dụ Thực Tế

#### A. Backup đến 1 server (SSH key)

```bash
REMOTE_SERVERS="
vps1:backup@192.168.1.100:22:/backups/mysite|/home/user/.ssh/id_rsa
"
```

#### B. Backup đến nhiều server khác nhau (multi-server redundancy)

```bash
REMOTE_SERVERS="
vps1:backup@192.168.1.100:22:/backups/mysite|/home/user/.ssh/id_rsa
vps2:root@backup.example.com:22:/data/backups|/home/user/.ssh/backup_key
cloud:backupuser@cloud.provider.com:2222:/storage/backups|/home/user/.ssh/cloud_key
"
```

#### C. Mix SSH key và password auth

```bash
REMOTE_SERVERS="
vps1:backup@192.168.1.100:22:/backups|/home/user/.ssh/id_rsa
vps2:admin@10.0.0.50:22:/backup|password:MySecurePassword123
cloud:backup@remote.com:2222:/data|password:AnotherPass456
"
```

#### D. Cùng 1 server, khác path (ví dụ: daily + weekly)

```bash
REMOTE_SERVERS="
daily:backup@server.com:22:/backups/daily|/home/user/.ssh/id_rsa
weekly:backup@server.com:22:/backups/weekly|/home/user/.ssh/id_rsa
"
```

#### E. Custom SSH port

```bash
REMOTE_SERVERS="
server1:user@example.com:2222:/backup|/home/user/.ssh/id_rsa
server2:root@192.168.1.50:8022:/data|/home/user/.ssh/backup_key
"
```

### Authentication Methods

#### 1. SSH Key Auth (Recommended)

```bash
server1:user@host:22:/backup|/home/user/.ssh/id_rsa
server2:user@host:22:/backup|~/.ssh/backup_key
```

**Setup SSH Key:**

```bash
# 1. Tạo SSH key (nếu chưa có)
ssh-keygen -t ed25519 -f ~/.ssh/backup_key -N ""

# 2. Copy key lên server
ssh-copy-id -i ~/.ssh/backup_key user@your-server.com

# 3. Test connection
ssh -i ~/.ssh/backup_key user@your-server.com

# 4. Dùng trong .env
|/home/user/.ssh/backup_key
```

#### 2. Password Auth (Requires sshpass)

```bash
server1:user@host:22:/backup|password:YourPassword123
```

**Install sshpass:**

```bash
sudo apt install sshpass
```

**Lưu ý bảo mật:**
- Password nằm trong `.env` file (đã gitignore)
- Nên dùng SSH key thay vì password
- Nếu dùng password, đảm bảo `.env` có permission 600

---

## 3. DATABASE BACKUP - Backup Database

### MySQL/MariaDB

```bash
DB_BACKUP_ENABLED=true
DB_TYPE=mysql
DB_HOST=localhost
DB_PORT=3306
DB_USER=root
DB_PASSWORD=your_mysql_password
DB_NAMES="wordpress woocommerce myapp"
```

### PostgreSQL

```bash
DB_BACKUP_ENABLED=true
DB_TYPE=postgres
DB_HOST=localhost
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=your_postgres_password
DB_NAMES="database1 database2 database3"
```

### Disable Database Backup

```bash
DB_BACKUP_ENABLED=false
```

### Lưu Ý:

1. **Multiple databases** - Cách nhau bởi space
   ```bash
   DB_NAMES="db1 db2 db3 db4"
   ```

2. **Remote database**
   ```bash
   DB_HOST=192.168.1.100
   DB_PORT=3306
   ```

3. **Special characters in password** - Không cần escape
   ```bash
   DB_PASSWORD=P@ssw0rd!123
   ```

4. **Test database connection:**
   ```bash
   # MySQL
   mysql -h localhost -u root -p -e "SHOW DATABASES;"

   # PostgreSQL
   PGPASSWORD=password psql -h localhost -U postgres -l
   ```

---

## 4. TELEGRAM NOTIFICATION - Thông Báo Qua Telegram

### Setup Bot

#### Bước 1: Tạo Bot với BotFather

1. Mở Telegram, tìm **@BotFather**
2. Gửi lệnh: `/newbot`
3. Đặt tên bot: `My Backup Bot`
4. Đặt username: `mybackup_bot` (phải kết thúc bằng `_bot`)
5. Nhận token: `123456789:ABCdefGHIjklMNOpqrsTUVwxyz`

#### Bước 2: Lấy Chat ID

**Cách 1 - Personal Chat:**

```bash
# 1. Gửi message bất kỳ cho bot của bạn
# 2. Mở browser:
https://api.telegram.org/bot123456789:ABCdefGHIjklMNOpqrsTUVwxyz/getUpdates

# 3. Tìm "chat":{"id":123456789}
# 4. Chat ID của bạn: 123456789
```

**Cách 2 - Group Chat:**

```bash
# 1. Tạo group mới
# 2. Thêm bot vào group
# 3. Gửi message trong group
# 4. Check getUpdates như trên
# 5. Chat ID sẽ là số âm: -1001234567890
```

**Cách 3 - Dùng curl:**

```bash
# Gửi test message cho bot
curl -X POST "https://api.telegram.org/bot123456789:ABC.../sendMessage" \
  -d "chat_id=YOUR_CHAT_ID" \
  -d "text=Test message"
```

### Config trong .env

```bash
TELEGRAM_BOT_TOKEN="123456789:ABCdefGHIjklMNOpqrsTUVwxyz"
TELEGRAM_CHAT_ID="123456789"
```

**Group chat:**

```bash
TELEGRAM_CHAT_ID="-1001234567890"  # Số âm cho group
```

### Disable Telegram

```bash
# Comment out hoặc xóa 2 dòng này
# TELEGRAM_BOT_TOKEN=""
# TELEGRAM_CHAT_ID=""
```

### Test Telegram

```bash
TOKEN="123456789:ABCdefGHIjklMNOpqrsTUVwxyz"
CHAT_ID="123456789"

curl -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
  -d "chat_id=${CHAT_ID}" \
  -d "text=🔄 Test notification from backup script" \
  -d "parse_mode=Markdown"
```

---

## 5. BEHAVIOR OPTIONS - Tùy Chọn Hành Vi

### KEEP_LOCAL - Giữ Archive Local Sau Khi Transfer

```bash
KEEP_LOCAL=false  # Xóa archive local sau khi backup thành công
KEEP_LOCAL=true   # Giữ archive local (cho debug hoặc backup thêm)
```

**Logic:**
- `false` + tất cả servers fail = Giữ archive (để không mất data)
- `false` + >= 1 server thành công = Xóa archive
- `true` = Luôn giữ archive

### COMPRESSION_LEVEL - Mức Nén

```bash
COMPRESSION_LEVEL=1  # Nhanh nhất, file lớn nhất
COMPRESSION_LEVEL=6  # Cân bằng (default, recommended)
COMPRESSION_LEVEL=9  # Chậm nhất, file nhỏ nhất
```

**Benchmark:**
- Level 1: 10 MB/s, tỷ lệ nén 60%
- Level 6: 5 MB/s, tỷ lệ nén 75%
- Level 9: 2 MB/s, tỷ lệ nén 80%

**Khuyến nghị:**
- Mạng nhanh, CPU yếu → Level 1-3
- Mạng chậm, CPU mạnh → Level 7-9
- Cân bằng → Level 6

### BANDWIDTH_LIMIT - Giới Hạn Băng Thông

```bash
BANDWIDTH_LIMIT=5000   # Giới hạn 5 MB/s
BANDWIDTH_LIMIT=10000  # Giới hạn 10 MB/s
```

**Đơn vị:** KB/s (kilobytes per second)

**Tính toán:**
- 1 MB/s = 1000 KB/s
- 5 MB/s = 5000 KB/s
- 10 MB/s = 10000 KB/s

**Khi nào dùng:**
- Server production đang chạy → Giới hạn để không ảnh hưởng users
- Mạng shared → Giới hạn để không chiếm hết bandwidth
- Unlimited bandwidth → Bỏ trống hoặc comment out

```bash
# Unlimited bandwidth
# BANDWIDTH_LIMIT=""
```

### DEBUG - Debug Logging

```bash
DEBUG=true   # Bật debug logs (chi tiết, verbose)
DEBUG=false  # Tắt debug logs (chỉ INFO, WARN, ERROR)
```

**Debug mode hiển thị:**
- Rsync progress chi tiết
- SSH connection details
- File paths được xử lý
- Config values
- Temp directory paths

**Khuyến nghị:**
- Development/Testing → `DEBUG=true`
- Production → `DEBUG=false`
- Troubleshooting → `DEBUG=true` tạm thời

---

## 6. VÍ DỤ CONFIG HOÀN CHỈNH

### Ví Dụ 1: Website + Database (1 Server)

```bash
# Backup website files
BACKUP_TARGETS="
/var/www/html
/etc/nginx
/etc/letsencrypt
"

# Single server
REMOTE_SERVERS="
vps:backup@192.168.1.100:22:/backups/mywebsite|/home/user/.ssh/id_rsa
"

# MySQL database
DB_BACKUP_ENABLED=true
DB_TYPE=mysql
DB_HOST=localhost
DB_PORT=3306
DB_USER=root
DB_PASSWORD=mysql_password_here
DB_NAMES="wordpress"

# Telegram
TELEGRAM_BOT_TOKEN="123456789:ABCdefGHIjklMNOpqrsTUVwxyz"
TELEGRAM_CHAT_ID="123456789"

# Behavior
KEEP_LOCAL=false
COMPRESSION_LEVEL=6
DEBUG=false
```

### Ví Dụ 2: Multiple Websites + Databases (Multi-Server)

```bash
# Multiple websites
BACKUP_TARGETS="
/var/www/site1
/var/www/site2
/var/www/site3
/etc/nginx
/home/user/scripts
"

# Multi-server for redundancy
REMOTE_SERVERS="
vps1:backup@vps1.example.com:22:/backups/websites|~/.ssh/id_rsa
vps2:root@192.168.1.50:22:/data/backups|~/.ssh/backup_key
cloud:backup@cloud.com:2222:/storage|password:CloudPass123
"

# Multiple MySQL databases
DB_BACKUP_ENABLED=true
DB_TYPE=mysql
DB_HOST=localhost
DB_PORT=3306
DB_USER=backup_user
DB_PASSWORD=db_password
DB_NAMES="site1_db site2_db site3_db"

# Telegram group notification
TELEGRAM_BOT_TOKEN="123456789:ABC..."
TELEGRAM_CHAT_ID="-1001234567890"

# Behavior
KEEP_LOCAL=false
COMPRESSION_LEVEL=6
BANDWIDTH_LIMIT=10000
DEBUG=false
```

### Ví Dụ 3: Developer Project Backup

```bash
# Code projects
BACKUP_TARGETS="
~/projects/myapp
~/projects/client-website
~/.ssh
~/.config
"

# Personal NAS
REMOTE_SERVERS="
nas:admin@192.168.1.200:22:/volume1/backups/dev|~/.ssh/nas_key
"

# No database
DB_BACKUP_ENABLED=false

# Telegram personal chat
TELEGRAM_BOT_TOKEN="123456789:ABC..."
TELEGRAM_CHAT_ID="987654321"

# Keep local copy
KEEP_LOCAL=true
COMPRESSION_LEVEL=9
DEBUG=true
```

### Ví Dụ 4: Production Server (High Security)

```bash
# Critical files
BACKUP_TARGETS="
/var/www/production
/etc/nginx
/etc/php
/etc/ssl
/root/.ssh
"

# Multiple off-site backups
REMOTE_SERVERS="
backup1:backup@backup1.company.com:22:/secure/backups|~/.ssh/backup_primary
backup2:backup@backup2.company.com:22:/secure/backups|~/.ssh/backup_secondary
offsite:backup@offsite.provider.com:2222:/data|~/.ssh/offsite_key
"

# Production database
DB_BACKUP_ENABLED=true
DB_TYPE=postgres
DB_HOST=localhost
DB_PORT=5432
DB_USER=backup_user
DB_PASSWORD=very_secure_password_here
DB_NAMES="production_db"

# Team Telegram group
TELEGRAM_BOT_TOKEN="123456789:ABC..."
TELEGRAM_CHAT_ID="-1001234567890"

# Production settings
KEEP_LOCAL=false
COMPRESSION_LEVEL=6
BANDWIDTH_LIMIT=5000
DEBUG=false
```

---

## 7. CHECKLIST SETUP

### Trước Khi Chạy

- [ ] Copy `.env.example` thành `.env`
- [ ] Set permission: `chmod 600 .env`
- [ ] Điền `BACKUP_TARGETS` (đường dẫn đầy đủ)
- [ ] Điền `REMOTE_SERVERS` (ít nhất 1 server)
- [ ] Setup SSH keys cho từng server
- [ ] Test SSH connection: `ssh -i ~/.ssh/key user@host`
- [ ] Config database (nếu cần)
- [ ] Test database connection
- [ ] Setup Telegram bot (optional)
- [ ] Test Telegram notification
- [ ] Review `KEEP_LOCAL`, `COMPRESSION_LEVEL`, `DEBUG`

### Test Chạy

```bash
# 1. Test với DEBUG=true
./backup.sh

# 2. Kiểm tra logs
tail -f logs/backup-*.log

# 3. Verify archive created
ls -lh backup-*.tar.gz

# 4. Verify archive contents
tar -tzf backup-*.tar.gz | head -20

# 5. Check remote server
ssh user@server "ls -lh /backup/path/"

# 6. Check Telegram (nếu config)
# Should receive notifications

# 7. Turn off DEBUG
# Set DEBUG=false in .env

# 8. Final test
./backup.sh
```

### Production Setup

```bash
# 1. Move script to /opt
sudo mv backup-script /opt/

# 2. Set ownership
sudo chown -R backup:backup /opt/backup-script

# 3. Setup automation (cron hoặc systemd)
# See docs/cron-setup.md or docs/systemd-service.md

# 4. Monitor first few runs
tail -f /opt/backup-script/logs/backup-*.log
```

---

## 8. TROUBLESHOOTING COMMON ISSUES

### "Target does not exist"

```bash
# Check path exists
ls -la /path/to/target

# Check permissions
sudo ls -la /path/to/target
```

### "SSH connection failed"

```bash
# Test SSH manually
ssh -i ~/.ssh/key user@host

# Check SSH key permissions
chmod 600 ~/.ssh/key

# Check server fingerprint
ssh-keyscan host >> ~/.ssh/known_hosts
```

### "Database dump failed"

```bash
# Test MySQL
mysql -h localhost -u root -p -e "SHOW DATABASES;"

# Test PostgreSQL
PGPASSWORD=pass psql -h localhost -U postgres -l
```

### "Telegram notification failed"

```bash
# Test API manually
curl -X POST "https://api.telegram.org/bot<TOKEN>/sendMessage" \
  -d "chat_id=<CHAT_ID>" \
  -d "text=Test"
```

---

## 9. SECURITY BEST PRACTICES

1. **File Permissions**
   ```bash
   chmod 600 .env
   chmod 700 backup.sh
   chmod 700 logs/
   ```

2. **SSH Keys**
   ```bash
   chmod 600 ~/.ssh/id_rsa
   chmod 644 ~/.ssh/id_rsa.pub
   ```

3. **Never Commit .env**
   - Already in `.gitignore`
   - Double-check before `git push`

4. **Use SSH Keys > Passwords**
   - Always prefer SSH keys
   - Only use passwords when absolutely necessary

5. **Secure Database Passwords**
   - Consider using `~/.my.cnf` (MySQL)
   - Consider using `~/.pgpass` (PostgreSQL)

6. **Rotate Backups**
   - Don't keep backups forever on remote
   - Implement retention policy separately

---

## 10. ADVANCED TIPS

### Exclude Files/Directories

Hiện tại script backup toàn bộ directory. Để exclude, dùng trick:

```bash
# Create temp backup directory
BACKUP_TARGETS="/tmp/backup-staging"

# Pre-script: rsync without excluded files
rsync -av --exclude='*.log' --exclude='cache/' /var/www/html/ /tmp/backup-staging/

# Then backup runs on /tmp/backup-staging
```

### Different Schedules

```bash
# backup-daily.sh uses .env.daily
# backup-weekly.sh uses .env.weekly

# Cron:
0 2 * * * /opt/backup-script/backup.sh
0 3 * * 0 /opt/backup-script/backup-weekly.sh
```

### Compression by File Type

```bash
# For already-compressed files (images, videos)
COMPRESSION_LEVEL=1  # Fast, low compression

# For text/code
COMPRESSION_LEVEL=9  # Slow, high compression
```

### Monitor Backup Size

```bash
# Add to cron
du -sh /backup/path/ | mail -s "Backup size" admin@example.com
```
