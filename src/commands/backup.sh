#!/bin/bash
#
# sshgit - Backup & Restore with Encryption Support
#

# Check if GPG is available
has_gpg() {
    command -v gpg &>/dev/null
}

# Create a tar archive of keys
create_backup_archive() {
    local backup_dir="$1"
    local archive_path="$2"

    tar -czf "$archive_path" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")"
}

# Encrypt a file with GPG
encrypt_file() {
    local input_file="$1"
    local output_file="$2"
    local passphrase="$3"

    if [[ -n "$passphrase" ]]; then
        echo "$passphrase" | gpg --batch --yes --passphrase-fd 0 \
            --symmetric --cipher-algo AES256 \
            -o "$output_file" "$input_file"
    else
        gpg --symmetric --cipher-algo AES256 -o "$output_file" "$input_file"
    fi
}

# Decrypt a file with GPG
decrypt_file() {
    local input_file="$1"
    local output_file="$2"
    local passphrase="$3"

    if [[ -n "$passphrase" ]]; then
        echo "$passphrase" | gpg --batch --yes --passphrase-fd 0 \
            -d -o "$output_file" "$input_file"
    else
        gpg -d -o "$output_file" "$input_file"
    fi
}

# Standard backup command
cmd_backup() {
    local backup_path=""
    local encrypt=false
    local cloud=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --encrypt|-e)
                encrypt=true
                shift
                ;;
            --cloud|-c)
                cloud="$2"
                shift 2
                ;;
            *)
                backup_path="$1"
                shift
                ;;
        esac
    done

    backup_path="${backup_path:-$HOME/sshgit-backup-$(date +%Y%m%d-%H%M%S)}"

    show_logo

    local hosts
    hosts=$(get_managed_hosts)

    if [[ -z "$hosts" ]]; then
        log_error "No sshgit-managed keys found"
        return 1
    fi

    if [[ "$encrypt" == true ]] && ! has_gpg; then
        log_error "GPG not found. Install gnupg for encryption support."
        return 1
    fi

    # Create backup directory
    mkdir -p "$backup_path"
    chmod 700 "$backup_path"

    local count=0

    echo -e "${BOLD}Creating backup...${NC}"
    echo ""

    while IFS= read -r host; do
        [[ -z "$host" ]] && continue

        local details keyfile
        details=$(get_host_details "$host")
        keyfile=$(echo "$details" | cut -d'|' -f2)

        if [[ -f "$keyfile" ]]; then
            cp "$keyfile" "$backup_path/"
            cp "$keyfile.pub" "$backup_path/" 2>/dev/null
            echo -e "  ${GREEN}✓${NC} $host"
            ((count++))
        fi
    done <<< "$hosts"

    # Backup SSH config entries
    if [[ -f "$SSH_CONFIG" ]]; then
        grep -A5 "$SSHGIT_MARKER" "$SSH_CONFIG" > "$backup_path/config.bak" 2>/dev/null
    fi

    # Backup expiry settings
    if [[ -f "$HOME/.sshgit-expiry" ]]; then
        cp "$HOME/.sshgit-expiry" "$backup_path/"
    fi

    # Backup profiles
    if [[ -f "$HOME/.sshgit-profiles" ]]; then
        cp "$HOME/.sshgit-profiles" "$backup_path/"
    fi

    # Create restore script
    cat > "$backup_path/restore.sh" << 'RESTORE_EOF'
#!/bin/bash
# sshgit backup restore script

BACKUP_DIR="$(cd "$(dirname "$0")" && pwd)"
SSH_DIR="$HOME/.ssh"

echo "Restoring sshgit keys from: $BACKUP_DIR"

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

for key in "$BACKUP_DIR"/*; do
    filename=$(basename "$key")
    case "$filename" in
        restore.sh|config.bak|.sshgit-expiry|.sshgit-profiles)
            continue
            ;;
    esac

    cp "$key" "$SSH_DIR/"
    if [[ "$filename" == *.pub ]]; then
        chmod 644 "$SSH_DIR/$filename"
    else
        chmod 600 "$SSH_DIR/$filename"
    fi
    echo "Restored: $filename"
done

if [[ -f "$BACKUP_DIR/config.bak" ]]; then
    cat "$BACKUP_DIR/config.bak" >> "$SSH_DIR/config"
    echo "Restored SSH config entries"
fi

if [[ -f "$BACKUP_DIR/.sshgit-expiry" ]]; then
    cp "$BACKUP_DIR/.sshgit-expiry" "$HOME/"
    echo "Restored expiry settings"
fi

if [[ -f "$BACKUP_DIR/.sshgit-profiles" ]]; then
    cp "$BACKUP_DIR/.sshgit-profiles" "$HOME/"
    echo "Restored profiles"
fi

echo "Done!"
RESTORE_EOF
    chmod +x "$backup_path/restore.sh"

    echo ""
    log_success "Backed up $count key(s) to: $backup_path"

    # Encrypt if requested
    if [[ "$encrypt" == true ]]; then
        echo ""
        log_info "Encrypting backup..."

        local archive_path="${backup_path}.tar.gz"
        local encrypted_path="${backup_path}.tar.gz.gpg"

        create_backup_archive "$backup_path" "$archive_path"

        if encrypt_file "$archive_path" "$encrypted_path"; then
            # Remove unencrypted files
            rm -rf "$backup_path" "$archive_path"
            log_success "Encrypted backup created: $encrypted_path"
            backup_path="$encrypted_path"
        else
            log_error "Encryption failed"
            rm -f "$archive_path"
            return 1
        fi
    fi

    # Upload to cloud if requested
    if [[ -n "$cloud" ]]; then
        echo ""
        upload_to_cloud "$backup_path" "$cloud"
    fi

    echo ""
    if [[ "$encrypt" == true ]]; then
        echo -e "${DIM}To restore: sshgit restore --decrypt $backup_path${NC}"
    else
        echo -e "${DIM}To restore: $backup_path/restore.sh${NC}"
    fi
}

# Upload to cloud storage
upload_to_cloud() {
    local file="$1"
    local destination="$2"

    case "$destination" in
        s3://*)
            if ! command -v aws &>/dev/null; then
                log_error "AWS CLI not found"
                return 1
            fi
            log_info "Uploading to S3..."
            if aws s3 cp "$file" "$destination"; then
                log_success "Uploaded to $destination"
            else
                log_error "Upload failed"
                return 1
            fi
            ;;
        gs://*)
            if ! command -v gsutil &>/dev/null; then
                log_error "gsutil not found"
                return 1
            fi
            log_info "Uploading to Google Cloud Storage..."
            if gsutil cp "$file" "$destination"; then
                log_success "Uploaded to $destination"
            else
                log_error "Upload failed"
                return 1
            fi
            ;;
        *)
            log_error "Unsupported cloud destination: $destination"
            echo "Supported: s3://, gs://"
            return 1
            ;;
    esac
}

# Restore from backup
cmd_restore() {
    local backup_path=""
    local decrypt=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --decrypt|-d)
                decrypt=true
                shift
                ;;
            *)
                backup_path="$1"
                shift
                ;;
        esac
    done

    if [[ -z "$backup_path" ]]; then
        log_error "Backup path required"
        echo "Usage: $SCRIPT_NAME restore <backup-path> [--decrypt]"
        return 1
    fi

    show_logo

    backup_path=$(expand_path "$backup_path")

    if [[ ! -e "$backup_path" ]]; then
        log_error "Backup not found: $backup_path"
        return 1
    fi

    echo -e "${BOLD}Restoring from backup...${NC}"
    echo ""

    # Handle encrypted backup
    if [[ "$decrypt" == true ]] || [[ "$backup_path" == *.gpg ]]; then
        if ! has_gpg; then
            log_error "GPG not found. Install gnupg for decryption."
            return 1
        fi

        log_info "Decrypting backup..."

        local decrypted_path="${backup_path%.gpg}"
        local temp_dir

        if ! decrypt_file "$backup_path" "$decrypted_path"; then
            log_error "Decryption failed"
            return 1
        fi

        # Extract archive
        temp_dir=$(mktemp -d)
        tar -xzf "$decrypted_path" -C "$temp_dir"
        rm -f "$decrypted_path"

        # Find the extracted directory
        local extracted_dir
        extracted_dir=$(find "$temp_dir" -maxdepth 1 -type d | tail -1)

        if [[ -f "$extracted_dir/restore.sh" ]]; then
            bash "$extracted_dir/restore.sh"
        else
            log_error "Invalid backup archive"
            rm -rf "$temp_dir"
            return 1
        fi

        rm -rf "$temp_dir"
        log_success "Restore complete"
    elif [[ -d "$backup_path" ]]; then
        # Directory backup
        if [[ -f "$backup_path/restore.sh" ]]; then
            bash "$backup_path/restore.sh"
        else
            log_error "No restore.sh found in backup directory"
            return 1
        fi
    elif [[ -f "$backup_path" ]] && [[ "$backup_path" == *.tar.gz ]]; then
        # Archive backup
        local temp_dir
        temp_dir=$(mktemp -d)
        tar -xzf "$backup_path" -C "$temp_dir"

        local extracted_dir
        extracted_dir=$(find "$temp_dir" -maxdepth 1 -type d | tail -1)

        if [[ -f "$extracted_dir/restore.sh" ]]; then
            bash "$extracted_dir/restore.sh"
        else
            log_error "Invalid backup archive"
            rm -rf "$temp_dir"
            return 1
        fi

        rm -rf "$temp_dir"
        log_success "Restore complete"
    else
        log_error "Unknown backup format"
        return 1
    fi
}
