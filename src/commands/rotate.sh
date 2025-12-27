#!/bin/bash
#
# sshgit - Key Rotation & Expiry Management
#

readonly EXPIRY_FILE="$HOME/.sshgit-expiry"

# Get key creation date from file
get_key_creation_date() {
    local keypath="$1"
    if [[ -f "$keypath" ]]; then
        stat -c %Y "$keypath" 2>/dev/null || stat -f %m "$keypath" 2>/dev/null
    fi
}

# Get key age in days
get_key_age_days() {
    local keypath="$1"
    local created
    created=$(get_key_creation_date "$keypath")

    if [[ -n "$created" ]]; then
        local now
        now=$(date +%s)
        echo $(( (now - created) / 86400 ))
    else
        echo "unknown"
    fi
}

# Load expiry settings
load_expiry_settings() {
    if [[ -f "$EXPIRY_FILE" ]]; then
        cat "$EXPIRY_FILE"
    fi
}

# Save expiry setting for a key
save_expiry_setting() {
    local keyname="$1"
    local days="$2"
    local expiry_date
    expiry_date=$(date -d "+${days} days" +%Y-%m-%d 2>/dev/null || date -v+${days}d +%Y-%m-%d 2>/dev/null)

    # Remove old entry if exists
    if [[ -f "$EXPIRY_FILE" ]]; then
        grep -v "^$keyname|" "$EXPIRY_FILE" > "$EXPIRY_FILE.tmp" 2>/dev/null || true
        mv "$EXPIRY_FILE.tmp" "$EXPIRY_FILE"
    fi

    echo "$keyname|$expiry_date|$days" >> "$EXPIRY_FILE"
    chmod 600 "$EXPIRY_FILE"
}

# Get expiry info for a key
get_expiry_info() {
    local keyname="$1"
    if [[ -f "$EXPIRY_FILE" ]]; then
        grep "^$keyname|" "$EXPIRY_FILE" | head -1
    fi
}

# Check if key is expired or near expiry
check_key_expiry_status() {
    local keyname="$1"
    local expiry_info
    expiry_info=$(get_expiry_info "$keyname")

    if [[ -z "$expiry_info" ]]; then
        echo "no_expiry"
        return
    fi

    local expiry_date
    expiry_date=$(echo "$expiry_info" | cut -d'|' -f2)

    local expiry_ts now_ts days_left
    expiry_ts=$(date -d "$expiry_date" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$expiry_date" +%s 2>/dev/null)
    now_ts=$(date +%s)

    if [[ -n "$expiry_ts" ]]; then
        days_left=$(( (expiry_ts - now_ts) / 86400 ))

        if [[ $days_left -lt 0 ]]; then
            echo "expired|$days_left"
        elif [[ $days_left -lt 14 ]]; then
            echo "warning|$days_left"
        else
            echo "ok|$days_left"
        fi
    else
        echo "unknown"
    fi
}

# Rotate a key (create new, backup old)
cmd_rotate() {
    local keyname="$1"

    if [[ -z "$keyname" ]]; then
        log_error "Key name required"
        echo "Usage: $SCRIPT_NAME rotate <keyname>"
        return 1
    fi

    show_logo

    if ! host_exists_in_config "$keyname"; then
        log_error "Host '$keyname' not found in SSH config"
        return 1
    fi

    local details keyfile host
    details=$(get_host_details "$keyname")
    keyfile=$(echo "$details" | cut -d'|' -f2)
    host=$(echo "$details" | cut -d'|' -f1)

    if [[ ! -f "$keyfile" ]]; then
        log_error "Key file not found: $keyfile"
        return 1
    fi

    echo -e "${BOLD}Key Rotation for: $keyname${NC}"
    echo ""
    echo "Current key: $keyfile"

    local age
    age=$(get_key_age_days "$keyfile")
    echo "Key age: $age days"
    echo ""

    if ! confirm "Rotate this key? (old key will be backed up)"; then
        echo "Aborted."
        return 0
    fi

    # Backup old key
    local backup_suffix
    backup_suffix=$(date +%Y%m%d-%H%M%S)
    local backup_path="${keyfile}.backup-${backup_suffix}"

    cp "$keyfile" "$backup_path"
    cp "$keyfile.pub" "$backup_path.pub" 2>/dev/null
    chmod 600 "$backup_path"
    log_success "Old key backed up to: $backup_path"

    # Get key type from old key
    local key_type
    key_type=$(ssh-keygen -l -f "$keyfile" 2>/dev/null | awk '{print $4}' | tr -d '()')
    key_type="${key_type:-ed25519}"

    # Remove old key
    rm -f "$keyfile" "$keyfile.pub"

    # Generate new key
    echo ""
    log_info "Generating new key..."

    local keygen_opts=(-C "$DEFAULT_EMAIL" -f "$keyfile" -t "$key_type" -N "")

    if confirm "Set passphrase for new key?"; then
        keygen_opts=(-C "$DEFAULT_EMAIL" -f "$keyfile" -t "$key_type")
    fi

    ssh-keygen "${keygen_opts[@]}"

    if [[ ! -f "$keyfile.pub" ]]; then
        log_error "Key generation failed"
        # Restore backup
        mv "$backup_path" "$keyfile"
        mv "$backup_path.pub" "$keyfile.pub" 2>/dev/null
        return 1
    fi

    echo ""
    log_success "New key generated successfully!"
    echo ""
    echo -e "${BOLD}=== New Public Key ===${NC}"
    print_key "$(cat "$keyfile.pub")"
    echo ""

    # Copy to clipboard
    if copy_to_clipboard "$(cat "$keyfile.pub")"; then
        log_success "New public key copied to clipboard"
    fi

    echo ""
    log_warning "Remember to update the deploy key in your git provider!"

    # Offer to set expiry
    echo ""
    if confirm "Set expiry reminder for new key?" "y"; then
        read -r -p "Days until expiry [90]: " expiry_days
        expiry_days="${expiry_days:-90}"
        save_expiry_setting "$keyname" "$expiry_days"
        log_success "Expiry reminder set for $expiry_days days"
    fi
}

# Set expiry for a key
cmd_expire() {
    local keyname=""
    local days=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --days|-d)
                days="$2"
                shift 2
                ;;
            *)
                keyname="$1"
                shift
                ;;
        esac
    done

    if [[ -z "$keyname" ]]; then
        log_error "Key name required"
        echo "Usage: $SCRIPT_NAME expire <keyname> --days <days>"
        return 1
    fi

    show_logo

    if ! host_exists_in_config "$keyname"; then
        log_error "Host '$keyname' not found in SSH config"
        return 1
    fi

    if [[ -z "$days" ]]; then
        read -r -p "Days until expiry [90]: " days
        days="${days:-90}"
    fi

    if ! [[ "$days" =~ ^[0-9]+$ ]]; then
        log_error "Invalid number of days"
        return 1
    fi

    save_expiry_setting "$keyname" "$days"

    local expiry_date
    expiry_date=$(date -d "+${days} days" +%Y-%m-%d 2>/dev/null || date -v+${days}d +%Y-%m-%d 2>/dev/null)

    log_success "Expiry set for '$keyname': $expiry_date ($days days)"
}

# Check expiry status of all keys
cmd_check_expiry() {
    show_logo
    echo -e "${BOLD}Key Expiry Status:${NC}"
    echo ""

    local hosts
    hosts=$(get_managed_hosts)

    if [[ -z "$hosts" ]]; then
        echo -e "  ${DIM}No keys found${NC}"
        return
    fi

    local has_issues=false

    printf "  ${BOLD}%-35s %-12s %-15s %s${NC}\n" "KEY NAME" "AGE (days)" "EXPIRY" "STATUS"
    echo "  $(printf '%.0s─' {1..80})"

    while IFS= read -r host; do
        [[ -z "$host" ]] && continue

        local details keyfile age status expiry_status days_left status_text status_color
        details=$(get_host_details "$host")
        keyfile=$(echo "$details" | cut -d'|' -f2)

        age=$(get_key_age_days "$keyfile")
        expiry_status=$(check_key_expiry_status "$host")

        local expiry_info
        expiry_info=$(get_expiry_info "$host")
        local expiry_date="not set"

        if [[ -n "$expiry_info" ]]; then
            expiry_date=$(echo "$expiry_info" | cut -d'|' -f2)
        fi

        case "$expiry_status" in
            expired*)
                days_left=$(echo "$expiry_status" | cut -d'|' -f2)
                status_text="${RED}EXPIRED${NC} (${days_left#-}d ago)"
                has_issues=true
                ;;
            warning*)
                days_left=$(echo "$expiry_status" | cut -d'|' -f2)
                status_text="${YELLOW}WARNING${NC} (${days_left}d left)"
                has_issues=true
                ;;
            ok*)
                days_left=$(echo "$expiry_status" | cut -d'|' -f2)
                status_text="${GREEN}OK${NC} (${days_left}d left)"
                ;;
            *)
                status_text="${DIM}no expiry set${NC}"
                ;;
        esac

        printf "  %-35s %-12s %-15s %b\n" "$host" "$age" "$expiry_date" "$status_text"
    done <<< "$hosts"

    echo ""

    if [[ "$has_issues" == true ]]; then
        echo -e "${YELLOW}⚠${NC}  Some keys need attention. Use '${CYAN}sshgit rotate <keyname>${NC}' to rotate expired keys."
    fi
}
