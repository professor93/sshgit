#!/bin/bash
#
# sshgit - SSH Key Management
#

# Get all sshgit-managed hosts from SSH config
get_managed_hosts() {
    if [[ ! -f "$SSH_CONFIG" ]]; then
        return
    fi

    local in_sshgit_block=false
    local current_host=""

    while IFS= read -r line; do
        if [[ "$line" == "$SSHGIT_MARKER" ]]; then
            in_sshgit_block=true
            continue
        fi

        if [[ "$in_sshgit_block" == true ]]; then
            if [[ "$line" =~ ^Host[[:space:]]+(.+)$ ]]; then
                current_host="${BASH_REMATCH[1]}"
                echo "$current_host"
                in_sshgit_block=false
            fi
        fi
    done < "$SSH_CONFIG"
}

# Get SSH config entry details
# Returns: hostname|identity_file
get_host_details() {
    local target_host="$1"
    local in_host_block=false
    local hostname="" identity_file=""

    if [[ ! -f "$SSH_CONFIG" ]]; then
        return 1
    fi

    while IFS= read -r line; do
        if [[ "$line" =~ ^Host[[:space:]]+(.+)$ ]]; then
            if [[ "${BASH_REMATCH[1]}" == "$target_host" ]]; then
                in_host_block=true
            elif [[ "$in_host_block" == true ]]; then
                break
            fi
            continue
        fi

        if [[ "$in_host_block" == true ]]; then
            if [[ "$line" =~ ^[[:space:]]*HostName[[:space:]]+(.+)$ ]]; then
                hostname="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^[[:space:]]*IdentityFile[[:space:]]+(.+)$ ]]; then
                identity_file="${BASH_REMATCH[1]}"
                identity_file="${identity_file/#\~/$HOME}"
            fi
        fi
    done < "$SSH_CONFIG"

    if [[ -n "$hostname" ]]; then
        echo "$hostname|$identity_file"
        return 0
    fi
    return 1
}

# Check if host exists in SSH config
host_exists_in_config() {
    local host="$1"
    grep -q "^Host $host$" "$SSH_CONFIG" 2>/dev/null
}

# Add host to SSH config
add_to_ssh_config() {
    local keyname="$1"
    local host="$2"
    local keypath="$3"

    ensure_ssh_config

    if host_exists_in_config "$keyname"; then
        log_warning "Host '$keyname' already in config, skipping"
        return 1
    fi

    cat >> "$SSH_CONFIG" << EOF

$SSHGIT_MARKER
Host $keyname
    HostName $host
    User git
    IdentityFile $keypath
    IdentitiesOnly yes
EOF
    chmod 600 "$SSH_CONFIG"
    log_success "Added $keyname to $SSH_CONFIG"
    return 0
}

# Remove host from SSH config
remove_from_ssh_config() {
    local target_host="$1"

    if [[ ! -f "$SSH_CONFIG" ]]; then
        return 1
    fi

    if ! host_exists_in_config "$target_host"; then
        return 1
    fi

    local temp_file
    temp_file=$(mktemp)
    local skip_until_next_host=false
    local skip_marker=false
    local prev_line=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == "$SSHGIT_MARKER" ]]; then
            skip_marker=true
            prev_line="$line"
            continue
        fi

        if [[ "$skip_marker" == true && "$line" =~ ^Host[[:space:]]+(.+)$ ]]; then
            if [[ "${BASH_REMATCH[1]}" == "$target_host" ]]; then
                skip_until_next_host=true
                skip_marker=false
                continue
            else
                echo "$prev_line" >> "$temp_file"
                skip_marker=false
            fi
        elif [[ "$skip_marker" == true ]]; then
            echo "$prev_line" >> "$temp_file"
            skip_marker=false
        fi

        if [[ "$skip_until_next_host" == true ]]; then
            if [[ "$line" =~ ^Host[[:space:]] ]] || [[ "$line" == "$SSHGIT_MARKER" ]]; then
                skip_until_next_host=false
                if [[ "$line" == "$SSHGIT_MARKER" ]]; then
                    skip_marker=true
                    prev_line="$line"
                    continue
                fi
            else
                continue
            fi
        fi

        echo "$line" >> "$temp_file"
    done < "$SSH_CONFIG"

    mv "$temp_file" "$SSH_CONFIG"
    chmod 600 "$SSH_CONFIG"
    return 0
}

# Test SSH connection
test_ssh_connection() {
    local keyname="$1"
    local quiet="${2:-false}"

    [[ "$quiet" != true ]] && log_info "Testing SSH connection to $keyname..."

    local ssh_test ssh_exit
    ssh_test=$(ssh -T -o StrictHostKeyChecking=accept-new \
        -o BatchMode=yes \
        -o ConnectTimeout=10 \
        "git@$keyname" 2>&1)
    ssh_exit=$?

    # Check for success patterns
    if [[ "$ssh_test" == *"successfully authenticated"* ]] || \
       [[ "$ssh_test" == *"Welcome"* ]] || \
       [[ "$ssh_test" == *"You've successfully authenticated"* ]] || \
       [[ "$ssh_test" == *"Hi "* ]] || \
       [[ "$ssh_test" == *"logged in as"* ]] || \
       [[ $ssh_exit -eq 0 ]]; then
        [[ "$quiet" != true ]] && log_success "SSH authentication successful"
        return 0
    else
        [[ "$quiet" != true ]] && log_error "SSH authentication failed"
        [[ "$quiet" != true ]] && echo -e "${DIM}$ssh_test${NC}"
        return 1
    fi
}
