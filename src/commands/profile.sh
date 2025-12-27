#!/bin/bash
#
# sshgit - Key Templates / Profiles
#

readonly PROFILES_FILE="$HOME/.sshgit-profiles"

# Get a specific profile
get_profile() {
    local name="$1"
    if [[ -f "$PROFILES_FILE" ]]; then
        grep "^$name|" "$PROFILES_FILE" | head -1
    fi
}

# Save a profile
save_profile() {
    local name="$1"
    local email="$2"
    local key_type="$3"
    local bits="$4"
    local auto_config="$5"
    local auto_clipboard="$6"

    # Remove old entry
    if [[ -f "$PROFILES_FILE" ]]; then
        grep -v "^$name|" "$PROFILES_FILE" > "$PROFILES_FILE.tmp" 2>/dev/null || true
        mv "$PROFILES_FILE.tmp" "$PROFILES_FILE"
    fi

    echo "$name|$email|$key_type|$bits|$auto_config|$auto_clipboard" >> "$PROFILES_FILE"
    chmod 600 "$PROFILES_FILE"
}

# Parse profile data
parse_profile() {
    local profile_data="$1"
    local field="$2"

    case "$field" in
        name) echo "$profile_data" | cut -d'|' -f1 ;;
        email) echo "$profile_data" | cut -d'|' -f2 ;;
        type) echo "$profile_data" | cut -d'|' -f3 ;;
        bits) echo "$profile_data" | cut -d'|' -f4 ;;
        auto_config) echo "$profile_data" | cut -d'|' -f5 ;;
        auto_clipboard) echo "$profile_data" | cut -d'|' -f6 ;;
    esac
}

# List all profiles
cmd_profile_list() {
    show_logo
    echo -e "${BOLD}Saved Profiles:${NC}"
    echo ""

    if [[ ! -f "$PROFILES_FILE" ]] || [[ ! -s "$PROFILES_FILE" ]]; then
        echo -e "  ${DIM}No profiles found${NC}"
        echo ""
        echo "Create one with: $SCRIPT_NAME profile create <name>"
        return 0
    fi

    printf "  ${BOLD}%-15s %-30s %-10s %s${NC}\n" "NAME" "EMAIL" "TYPE" "OPTIONS"
    echo "  $(printf '%.0s─' {1..70})"

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        local name email key_type auto_config auto_clipboard options=""
        name=$(parse_profile "$line" "name")
        email=$(parse_profile "$line" "email")
        key_type=$(parse_profile "$line" "type")
        auto_config=$(parse_profile "$line" "auto_config")
        auto_clipboard=$(parse_profile "$line" "auto_clipboard")

        [[ "$auto_config" == "true" ]] && options+="-c "
        [[ "$auto_clipboard" == "true" ]] && options+="--clipboard"

        printf "  %-15s %-30s %-10s %s\n" "$name" "${email:0:30}" "$key_type" "$options"
    done < "$PROFILES_FILE"

    echo ""
}

# Create a new profile
cmd_profile_create() {
    local name="$1"

    if [[ -z "$name" ]]; then
        log_error "Profile name required"
        echo "Usage: $SCRIPT_NAME profile create <name>"
        return 1
    fi

    show_logo

    if [[ -n "$(get_profile "$name")" ]]; then
        if ! confirm "Profile '$name' exists. Overwrite?"; then
            echo "Aborted."
            return 0
        fi
    fi

    echo -e "${BOLD}Create Profile: $name${NC}"
    echo ""

    read -r -p "Email: " email
    email=$(trim "$email")
    if [[ -z "$email" ]]; then
        log_error "Email required"
        return 1
    fi

    read -r -p "Key type [ed25519]: " key_type
    key_type="${key_type:-ed25519}"

    local bits=""
    if [[ "$key_type" == "rsa" ]]; then
        read -r -p "RSA bits [4096]: " bits
        bits="${bits:-4096}"
    fi

    local auto_config="false"
    if confirm "Auto-add to SSH config?" "y"; then
        auto_config="true"
    fi

    local auto_clipboard="false"
    if confirm "Auto-copy to clipboard?" "y"; then
        auto_clipboard="true"
    fi

    save_profile "$name" "$email" "$key_type" "$bits" "$auto_config" "$auto_clipboard"

    echo ""
    log_success "Profile '$name' created"
    echo ""
    echo "Use with: $SCRIPT_NAME <user/repo> --profile $name"
}

# Delete a profile
cmd_profile_delete() {
    local name="$1"

    if [[ -z "$name" ]]; then
        log_error "Profile name required"
        return 1
    fi

    show_logo

    if [[ -z "$(get_profile "$name")" ]]; then
        log_error "Profile '$name' not found"
        return 1
    fi

    if ! confirm "Delete profile '$name'?"; then
        echo "Aborted."
        return 0
    fi

    grep -v "^$name|" "$PROFILES_FILE" > "$PROFILES_FILE.tmp" 2>/dev/null || true
    mv "$PROFILES_FILE.tmp" "$PROFILES_FILE"

    log_success "Profile '$name' deleted"
}

# Show a profile
cmd_profile_show() {
    local name="$1"

    if [[ -z "$name" ]]; then
        log_error "Profile name required"
        return 1
    fi

    show_logo

    local profile_data
    profile_data=$(get_profile "$name")

    if [[ -z "$profile_data" ]]; then
        log_error "Profile '$name' not found"
        return 1
    fi

    echo -e "${BOLD}Profile: $name${NC}"
    echo ""
    echo "  Email:          $(parse_profile "$profile_data" "email")"
    echo "  Key Type:       $(parse_profile "$profile_data" "type")"

    local bits
    bits=$(parse_profile "$profile_data" "bits")
    [[ -n "$bits" ]] && echo "  RSA Bits:       $bits"

    echo "  Auto Config:    $(parse_profile "$profile_data" "auto_config")"
    echo "  Auto Clipboard: $(parse_profile "$profile_data" "auto_clipboard")"
    echo ""
}

# Main profile command router
cmd_profile() {
    local subcmd="${1:-list}"
    shift 2>/dev/null || true

    case "$subcmd" in
        list|ls)
            cmd_profile_list
            ;;
        create|add|new)
            cmd_profile_create "$@"
            ;;
        delete|rm|remove)
            cmd_profile_delete "$@"
            ;;
        show|get)
            cmd_profile_show "$@"
            ;;
        *)
            if [[ -n "$(get_profile "$subcmd")" ]]; then
                cmd_profile_show "$subcmd"
            else
                log_error "Unknown profile command: $subcmd"
                echo ""
                echo "Usage:"
                echo "  $SCRIPT_NAME profile list              List all profiles"
                echo "  $SCRIPT_NAME profile create <name>     Create a new profile"
                echo "  $SCRIPT_NAME profile show <name>       Show profile details"
                echo "  $SCRIPT_NAME profile delete <name>     Delete a profile"
                return 1
            fi
            ;;
    esac
}

# Apply profile settings (called from create command)
apply_profile() {
    local profile_name="$1"

    local profile_data
    profile_data=$(get_profile "$profile_name")

    if [[ -z "$profile_data" ]]; then
        log_error "Profile '$profile_name' not found"
        return 1
    fi

    PROFILE_EMAIL=$(parse_profile "$profile_data" "email")
    PROFILE_TYPE=$(parse_profile "$profile_data" "type")
    PROFILE_BITS=$(parse_profile "$profile_data" "bits")
    PROFILE_AUTO_CONFIG=$(parse_profile "$profile_data" "auto_config")
    PROFILE_AUTO_CLIPBOARD=$(parse_profile "$profile_data" "auto_clipboard")

    return 0
}
