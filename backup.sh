#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Ubuntu Backup Script with Multi-Server & DB Support
# ============================================================
# Features:
# - Backup files/directories to tar.gz
# - Database dump (MySQL/PostgreSQL)
# - Multi-server transfer via rsync
# - Telegram notifications
# - Per-server auth (SSH key or password)
# ============================================================

# Resolve script directory for portability
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Global variables
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="${SCRIPT_DIR}/logs/backup-${TIMESTAMP}.log"
ARCHIVE_FILE=""
DB_DUMP_DIR=""
TARGETS=()
EXCLUDES=()

# Status tracking
SUCCESS_COUNT=0
FAIL_COUNT=0
TOTAL_SERVERS=0

# Exit codes
EXIT_CONFIG_ERROR=1
EXIT_BACKUP_ERROR=2
EXIT_TRANSFER_ERROR=3

# ============================================================
# LOGGING FUNCTIONS
# ============================================================

log_info() {
  local msg="[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"
  echo "$msg" | tee -a "$LOG_FILE"
}

log_warn() {
  local msg="[WARN] $(date '+%Y-%m-%d %H:%M:%S') - $*"
  echo "$msg" | tee -a "$LOG_FILE" >&2
}

log_error() {
  local msg="[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*"
  echo "$msg" | tee -a "$LOG_FILE" >&2
}

log_debug() {
  if [[ "${DEBUG:-false}" == "true" ]]; then
    local msg="[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') - $*"
    echo "$msg" >> "$LOG_FILE"
  fi
}

# ============================================================
# TELEGRAM NOTIFICATION
# ============================================================

telegram_notify() {
  # Skip if not configured
  if [[ -z "${TELEGRAM_BOT_TOKEN:-}" ]] || [[ -z "${TELEGRAM_CHAT_ID:-}" ]]; then
    return 0
  fi

  local message="$1"
  local api_url="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"

  # Escape message for JSON (simple approach)
  message=$(echo -n "$message" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed 's/$/\\n/' | tr -d '\n')

  # Send with curl
  local response
  response=$(curl -s -X POST "$api_url" \
    -H "Content-Type: application/json" \
    -d "{\"chat_id\":\"${TELEGRAM_CHAT_ID}\",\"text\":\"${message}\",\"parse_mode\":\"Markdown\"}" \
    --max-time 10 2>&1) || true

  if echo "$response" | grep -q '"ok":true'; then
    log_debug "Telegram notification sent"
  else
    log_warn "Telegram notification failed: $response"
  fi
}

notify_backup_start() {
  local targets_count=$(echo "${BACKUP_TARGETS:-}" | wc -w)
  local db_status="disabled"
  [[ "${DB_BACKUP_ENABLED:-false}" == "true" ]] && db_status="enabled"

  telegram_notify "🔄 *Backup Started*

*Host:* \`$(hostname)\`
*Time:* $(date '+%Y-%m-%d %H:%M:%S')
*Targets:* ${targets_count} paths
*Database:* ${db_status}
*Servers:* ${TOTAL_SERVERS}
"
}

notify_archive_created() {
  local archive="$1"
  local size_mb=$(du -m "$archive" 2>/dev/null | cut -f1 || echo "0")
  local duration="$2"

  telegram_notify "📦 *Archive Created*

*File:* \`$(basename "$archive")\`
*Size:* ${size_mb} MB
*Time:* ${duration}s
"
}

notify_server_status() {
  local label="$1"
  local status="$2"
  local duration="$3"
  local error="${4:-}"

  if [[ "$status" == "success" ]]; then
    telegram_notify "✅ *Transfer Success: ${label}*

*Duration:* ${duration}s
*Status:* Completed
"
  else
    telegram_notify "❌ *Transfer Failed: ${label}*

*Duration:* ${duration}s
*Error:* \`${error}\`
"
  fi
}

notify_backup_complete() {
  local total_duration="$1"
  local success_count="$2"
  local total_count="$3"
  local cleanup_status="$4"

  local status_icon="✅"
  local status_text="Success"

  if [[ $success_count -eq 0 ]]; then
    status_icon="❌"
    status_text="Failed"
  elif [[ $success_count -lt $total_count ]]; then
    status_icon="⚠️"
    status_text="Partial Success"
  fi

  telegram_notify "${status_icon} *Backup ${status_text}*

*Total Duration:* ${total_duration}s
*Servers:* ${success_count}/${total_count} succeeded
*Cleanup:* ${cleanup_status}
*Host:* \`$(hostname)\`
*Time:* $(date '+%Y-%m-%d %H:%M:%S')
"
}

# ============================================================
# CONFIGURATION
# ============================================================

load_config() {
  local env_file="${SCRIPT_DIR}/.env"

  if [[ ! -f "$env_file" ]]; then
    log_error ".env not found. Copy .env.example to .env and configure."
    log_error "  cp ${SCRIPT_DIR}/.env.example ${SCRIPT_DIR}/.env"
    exit $EXIT_CONFIG_ERROR
  fi

  # Check permissions - warn if world readable
  local perms=$(stat -c %a "$env_file" 2>/dev/null || stat -f %Lp "$env_file" 2>/dev/null || echo "000")
  if [[ "${perms: -1}" != "0" ]]; then
    log_warn ".env is world readable. Consider: chmod 600 $env_file"
  fi

  # Source the config
  set -a
  # shellcheck source=/dev/null
  source "$env_file"
  set +a

  log_info "Configuration loaded"
}

validate_config() {
  local errors=0

  # Required variables (either TARGETS or TARGETS_FILE)
  # Default to backup.conf if not specified
  BACKUP_CONF_FILE="${BACKUP_CONF_FILE:-${SCRIPT_DIR}/backup.conf}"
  
  if [[ ! -f "$BACKUP_CONF_FILE" ]] && [[ -z "${BACKUP_TARGETS:-}" ]]; then
    log_warn "BACKUP_CONF_FILE not found: $BACKUP_CONF_FILE"
    log_warn "And BACKUP_TARGETS variable is empty"
    # We don't error here immediately, we let parse_targets check if we found anything
  fi

  if [[ -z "${REMOTE_SERVERS:-}" ]]; then
    log_error "Missing required: REMOTE_SERVERS"
    ((errors++))
  fi

  # Apply defaults
  KEEP_LOCAL="${KEEP_LOCAL:-false}"
  COMPRESSION_LEVEL="${COMPRESSION_LEVEL:-6}"
  DEBUG="${DEBUG:-false}"
  DB_BACKUP_ENABLED="${DB_BACKUP_ENABLED:-false}"

  # Validate compression level
  if [[ ! "$COMPRESSION_LEVEL" =~ ^[1-9]$ ]]; then
    log_warn "Invalid COMPRESSION_LEVEL ($COMPRESSION_LEVEL), using default 6"
    COMPRESSION_LEVEL=6
  fi

  # Validate compression algo
  COMPRESSION_ALGO="${COMPRESSION_ALGO:-auto}"
  if [[ "$COMPRESSION_ALGO" != "auto" && "$COMPRESSION_ALGO" != "zstd" && "$COMPRESSION_ALGO" != "pigz" && "$COMPRESSION_ALGO" != "gzip" ]]; then
    log_warn "Invalid COMPRESSION_ALGO ($COMPRESSION_ALGO), using auto"
    COMPRESSION_ALGO="auto"
  fi

  # Validate database config if enabled
  if [[ "${DB_BACKUP_ENABLED}" == "true" ]]; then
    if [[ -z "${DB_TYPE:-}" ]] || [[ -z "${DB_NAMES:-}" ]]; then
      log_error "DB_BACKUP_ENABLED=true but missing DB_TYPE or DB_NAMES"
      ((errors++))
    fi

    if [[ "${DB_TYPE}" != "mysql" ]] && [[ "${DB_TYPE}" != "postgres" ]]; then
      log_error "Invalid DB_TYPE: ${DB_TYPE} (must be mysql or postgres)"
      ((errors++))
    fi
  fi

  if [[ $errors -gt 0 ]]; then
    exit $EXIT_CONFIG_ERROR
  fi

  log_info "Configuration validated"
}

# ============================================================
# BACKUP TARGET PARSING
# ============================================================

parse_targets() {
  log_info "Parsing backup targets..."

  # 1. Parse from variable (Legacy support)
  if [[ -n "${BACKUP_TARGETS:-}" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
      line="${line/#\~/$HOME}"
      
      # Enable globbing
      local expanded=()
      if compgen -G "$line" > /dev/null; then
        while IFS= read -r match; do expanded+=("$match"); done < <(compgen -G "$line")
      else
        expanded+=("$line")
      fi

      for target in "${expanded[@]}"; do [[ -n "$target" ]] && TARGETS+=("$target"); done
    done <<< "$BACKUP_TARGETS"
  fi

  # 2. Parse from Unified Config File
  BACKUP_CONF_FILE="${BACKUP_CONF_FILE:-${SCRIPT_DIR}/backup.conf}"
  
  if [[ -f "$BACKUP_CONF_FILE" ]]; then
    log_info "Reading config from: $BACKUP_CONF_FILE"
    
    local current_section=""
    
    while IFS= read -r line || [[ -n "$line" ]]; do
      # Trim whitespace
      line=$(echo "$line" | xargs)
      
      # Skip empty lines and comments
      [[ -z "$line" || "$line" =~ ^# ]] && continue
      
      # Check for section headers
      if [[ "$line" =~ ^\[(.*)\]$ ]]; then
        current_section="${BASH_REMATCH[1]}"
        continue
      fi
      
      # Process based on section
      if [[ "$current_section" == "TARGETS" ]]; then
        line="${line/#\~/$HOME}"
        # Globbing support
        if compgen -G "$line" > /dev/null; then
          while IFS= read -r match; do TARGETS+=("$match"); done < <(compgen -G "$line")
        else
          TARGETS+=("$line")
        fi
        
      elif [[ "$current_section" == "EXCLUDES" ]]; then
        EXCLUDES+=("--exclude=$line")
      fi
      
    done < "$BACKUP_CONF_FILE"
  else
    if [[ -n "${BACKUP_TARGETS_FILE:-}" ]] && [[ -f "${BACKUP_TARGETS_FILE}" ]]; then
       # Legacy file support
       log_warn "Using legacy BACKUP_TARGETS_FILE. Consider migrating to backup.conf"
       while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        line="${line/#\~/$HOME}"
        if compgen -G "$line" > /dev/null; then
          while IFS= read -r match; do TARGETS+=("$match"); done < <(compgen -G "$line")
        else
          TARGETS+=("$line")
        fi
      done < "$BACKUP_TARGETS_FILE"
    fi
  fi

  # Parse legacy excludes variable
  if [[ -n "${BACKUP_EXCLUDES:-}" ]]; then
    log_info "Parsing legacy exclude patterns..."
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
      EXCLUDES+=("--exclude=$line")
    done <<< "$BACKUP_EXCLUDES"
  fi
}

validate_targets() {
  log_info "Validating backup targets..."
  local invalid=0

  for target in "${TARGETS[@]}"; do
    if [[ ! -e "$target" ]]; then
      log_error "Target does not exist: $target"
      ((invalid++))
    else
      log_debug "Target OK: $target"
    fi
  done

  if [[ $invalid -gt 0 ]]; then
    log_error "$invalid target(s) not found"
    exit $EXIT_BACKUP_ERROR
  fi

  log_info "All targets validated"
}

# ============================================================
# DATABASE BACKUP
# ============================================================

dump_databases() {
  if [[ "${DB_BACKUP_ENABLED:-false}" != "true" ]]; then
    log_debug "Database backup disabled"
    return 0
  fi

  log_info "Starting database backup..."

  # Create temp directory
  DB_DUMP_DIR=$(mktemp -d -t backup-db-XXXXXX)
  log_debug "DB dump directory: $DB_DUMP_DIR"

  # Apply defaults
  DB_HOST="${DB_HOST:-localhost}"
  DB_PORT="${DB_PORT:-3306}"
  [[ "${DB_TYPE}" == "postgres" ]] && DB_PORT="${DB_PORT:-5432}"

  # Split DB_NAMES by space
  local databases=($DB_NAMES)

  for db_name in "${databases[@]}"; do
    local dump_file="${DB_DUMP_DIR}/${db_name}_${TIMESTAMP}.sql"
    log_info "Dumping database: $db_name"

    if [[ "$DB_TYPE" == "mysql" ]]; then
      # MySQL dump
      if mysqldump \
        --host="${DB_HOST}" \
        --port="${DB_PORT}" \
        --user="${DB_USER}" \
        --password="${DB_PASSWORD}" \
        --single-transaction \
        --quick \
        --lock-tables=false \
        "$db_name" > "$dump_file" 2>&1; then
        local size=$(du -h "$dump_file" | cut -f1)
        log_info "Database dumped: $db_name ($size)"
      else
        log_error "Failed to dump database: $db_name"
        exit $EXIT_BACKUP_ERROR
      fi

    elif [[ "$DB_TYPE" == "postgres" ]]; then
      # PostgreSQL dump
      if PGPASSWORD="${DB_PASSWORD}" pg_dump \
        --host="${DB_HOST}" \
        --port="${DB_PORT}" \
        --username="${DB_USER}" \
        --no-password \
        --format=plain \
        "$db_name" > "$dump_file" 2>&1; then
        local size=$(du -h "$dump_file" | cut -f1)
        log_info "Database dumped: $db_name ($size)"
      else
        log_error "Failed to dump database: $db_name"
        exit $EXIT_BACKUP_ERROR
      fi
    fi
  done

  # Add dump directory to targets
  TARGETS+=("$DB_DUMP_DIR")
  log_info "Database backup complete (${#databases[@]} databases)"
}

# ============================================================
# ARCHIVE CREATION
# ============================================================

create_archive() {
  local start_time=$(date +%s)
  
  # Determine compression tool
  local tar_compress_flag="-z"
  local compress_ext="gz"
  local compressor="gzip"
  
  if [[ "$COMPRESSION_ALGO" == "auto" ]]; then
    if command -v zstd &>/dev/null; then
      compressor="zstd"
    elif command -v pigz &>/dev/null; then
      compressor="pigz"
    fi
  else
    compressor="$COMPRESSION_ALGO"
  fi

  # Verify compressor exists
  if ! command -v "$compressor" &>/dev/null; then
    log_warn "$compressor not found, falling back to gzip"
    compressor="gzip"
  fi

  # Set flags based on compressor
  case "$compressor" in
    zstd)
      tar_compress_flag="-I 'zstd -T0 -${COMPRESSION_LEVEL}'"
      compress_ext="zst"
      ;;
    pigz)
      tar_compress_flag="-I 'pigz -p $(nproc) -${COMPRESSION_LEVEL}'"
      compress_ext="gz"
      ;;
    gzip)
      tar_compress_flag="-z"
      compress_ext="gz"
      ;;
  esac

  local archive_name="backup-${TIMESTAMP}.tar.${compress_ext}"
  
  ARCHIVE_FILE="${SCRIPT_DIR}/${archive_name}"

  log_info "Creating archive: $archive_name"
  log_info "Compression: $compressor"
  log_info "Targets: ${TARGETS[*]}"

  # Build tar command
  # We use eval to handle complex flags like -I 'cmd args' correctly
  local tar_cmd="tar -cf - ${EXCLUDES[@]} ${TARGETS[@]}"
  
  # Pipe chain construction
  local pipe_cmd="$tar_cmd"
  
  # Add compression
  case "$compressor" in
    zstd) pipe_cmd="$pipe_cmd | zstd -T0 -${COMPRESSION_LEVEL}" ;;
    pigz) pipe_cmd="$pipe_cmd | pigz -p $(nproc) -${COMPRESSION_LEVEL}" ;;
    gzip) pipe_cmd="$pipe_cmd | gzip -${COMPRESSION_LEVEL}" ;;
  esac

  # Output to file
  pipe_cmd="$pipe_cmd > '$ARCHIVE_FILE'"

  log_debug "Executing: $pipe_cmd"

  if eval "$pipe_cmd"; then
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local size=$(du -h "$ARCHIVE_FILE" | cut -f1)
    log_info "Archive created: $archive_name ($size) in ${duration}s"

    notify_archive_created "$ARCHIVE_FILE" "$duration"
  else
    log_error "Failed to create archive"
    exit $EXIT_BACKUP_ERROR
  fi
}

# ============================================================
# MULTI-SERVER TRANSFER
# ============================================================

parse_remote_servers() {
  log_info "Parsing remote servers configuration..."

  TOTAL_SERVERS=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    TOTAL_SERVERS=$((TOTAL_SERVERS + 1))
  done <<< "$REMOTE_SERVERS"

  log_info "Found ${TOTAL_SERVERS} remote servers"
}

transfer_to_servers() {
  log_info "Starting multi-server transfer..."

  SUCCESS_COUNT=0
  FAIL_COUNT=0

  while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

    # Parse: label:user@host:port:/path|auth
    local label=$(echo "$line" | cut -d: -f1)
    local rest=$(echo "$line" | cut -d: -f2-)

    # Extract user@host
    local user_host=$(echo "$rest" | cut -d: -f1)
    local user=$(echo "$user_host" | cut -d@ -f1)
    local host=$(echo "$user_host" | cut -d@ -f2)

    # Extract port
    local port=$(echo "$rest" | cut -d: -f2)

    # Extract path and auth
    local path_and_auth=$(echo "$rest" | cut -d: -f3-)
    local remote_path=$(echo "$path_and_auth" | cut -d'|' -f1)
    local auth=$(echo "$path_and_auth" | cut -d'|' -f2)

    log_info "Transferring to: $label ($user@$host:$port)"

    # Transfer to this server
    transfer_to_server "$label" "$user" "$host" "$port" "$remote_path" "$auth"

  done <<< "$REMOTE_SERVERS"

  log_info "Transfer complete: ${SUCCESS_COUNT}/${TOTAL_SERVERS} succeeded"
}

transfer_to_server() {
  local label="$1"
  local user="$2"
  local host="$3"
  local port="$4"
  local remote_path="$5"
  local auth="$6"

  local start_time=$(date +%s)
  local rsync_ssh=""

  # Build SSH command based on auth type
  if [[ "$auth" =~ ^password: ]]; then
    # Password auth - DO NOT use BatchMode (it disables password prompts)
    local password="${auth#password:}"
    if ! command -v sshpass &>/dev/null; then
      log_error "[$label] sshpass not installed (required for password auth)"
      ((FAIL_COUNT++))
      notify_server_status "$label" "failed" "0" "sshpass not installed"
      return 1
    fi
    local ssh_opts="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=30 -p $port"
    rsync_ssh="sshpass -p '$password' ssh $ssh_opts"
    log_debug "[$label] Using password auth"
  else
    # SSH key auth - use BatchMode to prevent password prompts
    local key_path="$auth"
    key_path="${key_path/#\~/$HOME}"
    if [[ ! -f "$key_path" ]]; then
      log_error "[$label] SSH key not found: $key_path"
      ((FAIL_COUNT++))
      notify_server_status "$label" "failed" "0" "SSH key not found: $key_path"
      return 1
    fi
    local ssh_opts="-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=30 -p $port"
    rsync_ssh="ssh -i $key_path $ssh_opts"
    log_debug "[$label] Using SSH key: $key_path"
  fi

  # Test connection
  log_debug "[$label] Testing connection..."
  if ! eval "$rsync_ssh ${user}@${host} 'echo ok'" &>/dev/null; then
    log_error "[$label] Connection failed"
    ((FAIL_COUNT++))
    local end_time=$(date +%s)
    notify_server_status "$label" "failed" "$((end_time - start_time))" "Connection failed"
    return 1
  fi

  # Ensure remote directory exists
  log_debug "[$label] Creating remote directory..."
  eval "$rsync_ssh ${user}@${host} 'mkdir -p ${remote_path}'" &>/dev/null || true

  # Transfer with rsync
  log_info "[$label] Transferring archive..."
  local rsync_opts="-avz --progress --partial"

  # Add bandwidth limit if configured
  if [[ -n "${BANDWIDTH_LIMIT:-}" ]]; then
    rsync_opts="$rsync_opts --bwlimit=${BANDWIDTH_LIMIT}"
  fi

  if rsync $rsync_opts -e "$rsync_ssh" "$ARCHIVE_FILE" "${user}@${host}:${remote_path}/" 2>&1 | while read -r line; do
    log_debug "[$label] rsync: $line"
  done; then
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    log_info "[$label] Transfer successful (${duration}s)"
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    notify_server_status "$label" "success" "$duration"
  else
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    log_error "[$label] Transfer failed"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    notify_server_status "$label" "failed" "$duration" "rsync failed"
  fi
}

# ============================================================
# CLEANUP
# ============================================================

cleanup() {
  log_info "Starting cleanup..."

  # Remove DB dumps
  if [[ -n "$DB_DUMP_DIR" ]] && [[ -d "$DB_DUMP_DIR" ]]; then
    log_debug "Removing DB dump directory: $DB_DUMP_DIR"
    rm -rf "$DB_DUMP_DIR"
  fi

  # Remove local archive based on config and transfer status
  if [[ "${KEEP_LOCAL}" == "false" ]]; then
    if [[ $SUCCESS_COUNT -gt 0 ]]; then
      log_info "Deleting local archive (transferred to $SUCCESS_COUNT servers)"
      rm -f "$ARCHIVE_FILE"
    else
      log_warn "Keeping local archive (all transfers failed)"
    fi
  else
    log_info "Keeping local archive (KEEP_LOCAL=true)"
  fi
}

# ============================================================
# MAIN FUNCTION
# ============================================================

init() {
  # Create logs directory
  mkdir -p "${SCRIPT_DIR}/logs"

  log_info "=== Backup Script Started ==="
  log_info "Timestamp: ${TIMESTAMP}"
  log_info "Script directory: ${SCRIPT_DIR}"
}

main() {
  local start_time=$(date +%s)

  init
  load_config
  validate_config
  parse_remote_servers

  notify_backup_start

  parse_targets
  validate_targets
  dump_databases
  create_archive
  transfer_to_servers
  cleanup

  local end_time=$(date +%s)
  local total_duration=$((end_time - start_time))

  local cleanup_msg="Local archive removed"
  [[ "${KEEP_LOCAL}" == "true" ]] && cleanup_msg="Local archive kept"
  [[ $SUCCESS_COUNT -eq 0 ]] && cleanup_msg="Local archive kept (all transfers failed)"

  notify_backup_complete "$total_duration" "$SUCCESS_COUNT" "$TOTAL_SERVERS" "$cleanup_msg"

  log_info "=== Backup Completed ==="
  log_info "Duration: ${total_duration}s"
  log_info "Servers: ${SUCCESS_COUNT}/${TOTAL_SERVERS} succeeded"

  # Exit with appropriate code
  if [[ $SUCCESS_COUNT -eq 0 ]]; then
    log_error "All transfers failed"
    exit $EXIT_TRANSFER_ERROR
  fi

  exit 0
}

# Run main function
# Run main function only if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
