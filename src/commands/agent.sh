#!/bin/bash
#
# sshgit - SSH Agent Integration
#

# Check if ssh-agent is running
is_agent_running() {
    [[ -n "$SSH_AUTH_SOCK" ]] && ssh-add -l &>/dev/null
    local status=$?
    # 0 = has keys, 1 = no keys but agent running, 2 = no agent
    [[ $status -ne 2 ]]
}

# Start ssh-agent if not running
ensure_agent_running() {
    if ! is_agent_running; then
        log_info "Starting ssh-agent..."
        eval "$(ssh-agent -s)" >/dev/null
        log_success "ssh-agent started (PID: $SSH_AGENT_PID)"
    fi
}

# Get list of keys in agent
get_agent_keys() {
    ssh-add -l 2>/dev/null | while read -r bits hash comment type; do
        echo "$comment"
    done
}

# Check if key is in agent
is_key_in_agent() {
    local keypath="$1"
    local pubkey_content

    if [[ -f "$keypath.pub" ]]; then
        pubkey_content=$(cat "$keypath.pub" | awk '{print $2}')
        ssh-add -l 2>/dev/null | grep -q "$pubkey_content"
    else
        return 1
    fi
}

# Add key to ssh-agent
cmd_agent_add() {
    local keyname="$1"
    local timeout=""

    shift 2>/dev/null || true

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -t|--timeout)
                timeout="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    if [[ -z "$keyname" ]]; then
        log_error "Key name required"
        echo "Usage: $SCRIPT_NAME agent-add <keyname> [-t <seconds>]"
        return 1
    fi

    show_logo

    ensure_agent_running

    # Check if it's a managed key
    if host_exists_in_config "$keyname"; then
        local details keyfile
        details=$(get_host_details "$keyname")
        keyfile=$(echo "$details" | cut -d'|' -f2)
    else
        # Assume it's a direct path
        keyfile="$keyname"
        keyfile="${keyfile/#\~/$HOME}"
    fi

    if [[ ! -f "$keyfile" ]]; then
        log_error "Key file not found: $keyfile"
        return 1
    fi

    if is_key_in_agent "$keyfile"; then
        log_warning "Key is already in ssh-agent"
        return 0
    fi

    local add_opts=()
    if [[ -n "$timeout" ]]; then
        add_opts+=(-t "$timeout")
        log_info "Adding key with ${timeout}s timeout..."
    else
        log_info "Adding key to ssh-agent..."
    fi

    if ssh-add "${add_opts[@]}" "$keyfile"; then
        log_success "Key added to ssh-agent"

        if [[ -n "$timeout" ]]; then
            echo -e "${DIM}Key will be removed after ${timeout} seconds of inactivity${NC}"
        fi
    else
        log_error "Failed to add key to ssh-agent"
        return 1
    fi
}

# Remove key from ssh-agent
cmd_agent_remove() {
    local keyname="$1"

    if [[ -z "$keyname" ]]; then
        log_error "Key name required"
        echo "Usage: $SCRIPT_NAME agent-remove <keyname>"
        return 1
    fi

    show_logo

    if ! is_agent_running; then
        log_error "ssh-agent is not running"
        return 1
    fi

    # Check if it's a managed key
    if host_exists_in_config "$keyname"; then
        local details keyfile
        details=$(get_host_details "$keyname")
        keyfile=$(echo "$details" | cut -d'|' -f2)
    else
        keyfile="$keyname"
        keyfile="${keyfile/#\~/$HOME}"
    fi

    if [[ ! -f "$keyfile" ]]; then
        log_error "Key file not found: $keyfile"
        return 1
    fi

    if ! is_key_in_agent "$keyfile"; then
        log_warning "Key is not in ssh-agent"
        return 0
    fi

    if ssh-add -d "$keyfile" 2>/dev/null; then
        log_success "Key removed from ssh-agent"
    else
        log_error "Failed to remove key from ssh-agent"
        return 1
    fi
}

# List keys in ssh-agent
cmd_agent_list() {
    show_logo
    echo -e "${BOLD}Keys in ssh-agent:${NC}"
    echo ""

    if ! is_agent_running; then
        echo -e "  ${DIM}ssh-agent is not running${NC}"
        echo ""
        echo "Start it with: eval \"\$(ssh-agent -s)\""
        return 1
    fi

    local agent_output
    agent_output=$(ssh-add -l 2>/dev/null)

    if [[ $? -eq 1 ]]; then
        echo -e "  ${DIM}No keys in agent${NC}"
        echo ""
        return 0
    fi

    local managed_hosts
    managed_hosts=$(get_managed_hosts)

    printf "  ${BOLD}%-10s %-45s %s${NC}\n" "BITS" "KEY" "MANAGED"
    echo "  $(printf '%.0s─' {1..70})"

    while read -r bits hash comment type; do
        local is_managed="${DIM}no${NC}"

        # Check if this key is managed by sshgit
        while IFS= read -r host; do
            [[ -z "$host" ]] && continue
            local details keyfile
            details=$(get_host_details "$host")
            keyfile=$(echo "$details" | cut -d'|' -f2)

            if [[ -f "$keyfile.pub" ]]; then
                local pubkey
                pubkey=$(cat "$keyfile.pub" | awk '{print $2}')
                if [[ "$hash" == *"$pubkey"* ]] || ssh-add -l 2>/dev/null | grep -q "$pubkey"; then
                    is_managed="${GREEN}yes${NC} ($host)"
                    break
                fi
            fi
        done <<< "$managed_hosts"

        printf "  %-10s %-45s %b\n" "$bits" "${comment:0:45}" "$is_managed"
    done <<< "$agent_output"

    echo ""
}

# Add all managed keys to agent
cmd_agent_add_all() {
    show_logo

    ensure_agent_running

    local hosts
    hosts=$(get_managed_hosts)

    if [[ -z "$hosts" ]]; then
        log_error "No sshgit-managed keys found"
        return 1
    fi

    local timeout=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -t|--timeout)
                timeout="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    echo -e "${BOLD}Adding all managed keys to ssh-agent...${NC}"
    echo ""

    local count=0
    local add_opts=()
    [[ -n "$timeout" ]] && add_opts+=(-t "$timeout")

    while IFS= read -r host; do
        [[ -z "$host" ]] && continue

        local details keyfile
        details=$(get_host_details "$host")
        keyfile=$(echo "$details" | cut -d'|' -f2)

        if [[ ! -f "$keyfile" ]]; then
            log_warning "Key file not found: $keyfile"
            continue
        fi

        if is_key_in_agent "$keyfile"; then
            echo -e "  ${DIM}$host - already in agent${NC}"
            continue
        fi

        if ssh-add "${add_opts[@]}" "$keyfile" 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} $host"
            ((count++))
        else
            echo -e "  ${YELLOW}⚠${NC} $host - requires passphrase (skipped)"
        fi
    done <<< "$hosts"

    echo ""
    log_success "Added $count key(s) to ssh-agent"
}

# Remove all managed keys from agent
cmd_agent_remove_all() {
    show_logo

    if ! is_agent_running; then
        log_error "ssh-agent is not running"
        return 1
    fi

    if ! confirm "Remove all sshgit-managed keys from ssh-agent?"; then
        echo "Aborted."
        return 0
    fi

    local hosts
    hosts=$(get_managed_hosts)

    local count=0

    while IFS= read -r host; do
        [[ -z "$host" ]] && continue

        local details keyfile
        details=$(get_host_details "$host")
        keyfile=$(echo "$details" | cut -d'|' -f2)

        if [[ -f "$keyfile" ]] && is_key_in_agent "$keyfile"; then
            if ssh-add -d "$keyfile" 2>/dev/null; then
                echo -e "  ${GREEN}✓${NC} Removed: $host"
                ((count++))
            fi
        fi
    done <<< "$hosts"

    echo ""
    log_success "Removed $count key(s) from ssh-agent"
}
