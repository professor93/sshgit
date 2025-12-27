#!/bin/bash
#
# sshgit - Key Health Check & Diagnostics
#

# Check file permissions
check_permissions() {
    local file="$1"
    local expected="$2"
    local actual

    actual=$(stat -c "%a" "$file" 2>/dev/null || stat -f "%Lp" "$file" 2>/dev/null)

    [[ "$actual" == "$expected" ]]
}

# Verify SSH key format
verify_key_format() {
    local keyfile="$1"

    ssh-keygen -l -f "$keyfile" &>/dev/null
}

# Check SSH config syntax
check_ssh_config_syntax() {
    ssh -G -F "$SSH_CONFIG" localhost &>/dev/null
}

# Run full diagnostics
cmd_doctor() {
    local keyname="${1:-}"
    local verbose=false
    local fix=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--verbose)
                verbose=true
                shift
                ;;
            --fix)
                fix=true
                shift
                ;;
            *)
                keyname="$1"
                shift
                ;;
        esac
    done

    show_logo
    echo -e "${BOLD}sshgit Doctor - System Health Check${NC}"
    echo ""

    local issues=0
    local warnings=0

    # Check SSH directory
    echo -e "${BOLD}[1/6] SSH Directory${NC}"
    if [[ -d "$SSH_DIR" ]]; then
        echo -e "  ${GREEN}✓${NC} $SSH_DIR exists"

        if check_permissions "$SSH_DIR" "700"; then
            echo -e "  ${GREEN}✓${NC} Permissions correct (700)"
        else
            echo -e "  ${RED}✗${NC} Incorrect permissions (should be 700)"
            ((issues++))

            if [[ "$fix" == true ]]; then
                chmod 700 "$SSH_DIR"
                echo -e "  ${GREEN}✓${NC} Fixed permissions"
            fi
        fi
    else
        echo -e "  ${YELLOW}⚠${NC} $SSH_DIR does not exist"
        ((warnings++))

        if [[ "$fix" == true ]]; then
            mkdir -p "$SSH_DIR"
            chmod 700 "$SSH_DIR"
            echo -e "  ${GREEN}✓${NC} Created directory"
        fi
    fi
    echo ""

    # Check SSH config
    echo -e "${BOLD}[2/6] SSH Config${NC}"
    if [[ -f "$SSH_CONFIG" ]]; then
        echo -e "  ${GREEN}✓${NC} $SSH_CONFIG exists"

        if check_permissions "$SSH_CONFIG" "600"; then
            echo -e "  ${GREEN}✓${NC} Permissions correct (600)"
        else
            echo -e "  ${RED}✗${NC} Incorrect permissions (should be 600)"
            ((issues++))

            if [[ "$fix" == true ]]; then
                chmod 600 "$SSH_CONFIG"
                echo -e "  ${GREEN}✓${NC} Fixed permissions"
            fi
        fi

        # Check syntax (basic check)
        local config_errors
        config_errors=$(ssh -G -F "$SSH_CONFIG" localhost 2>&1 >/dev/null)
        if [[ -z "$config_errors" ]]; then
            echo -e "  ${GREEN}✓${NC} Config syntax OK"
        else
            echo -e "  ${RED}✗${NC} Config syntax errors detected"
            [[ "$verbose" == true ]] && echo -e "      ${DIM}$config_errors${NC}"
            ((issues++))
        fi
    else
        echo -e "  ${DIM}○${NC} $SSH_CONFIG does not exist (will be created when needed)"
    fi
    echo ""

    # Check managed keys
    echo -e "${BOLD}[3/6] Managed Keys${NC}"
    local hosts
    hosts=$(get_managed_hosts)

    if [[ -z "$hosts" ]]; then
        echo -e "  ${DIM}○${NC} No sshgit-managed keys found"
    else
        local key_count=0
        local key_issues=0

        while IFS= read -r host; do
            [[ -z "$host" ]] && continue
            ((key_count++))

            # If specific key requested, only check that one
            if [[ -n "$keyname" && "$host" != "$keyname" ]]; then
                continue
            fi

            local details keyfile hostname
            details=$(get_host_details "$host")
            keyfile=$(echo "$details" | cut -d'|' -f2)
            hostname=$(echo "$details" | cut -d'|' -f1)

            [[ "$verbose" == true ]] && echo -e "  ${CYAN}$host${NC} → $hostname"

            # Check private key
            if [[ -f "$keyfile" ]]; then
                [[ "$verbose" == true ]] && echo -e "    ${GREEN}✓${NC} Private key exists"

                if check_permissions "$keyfile" "600"; then
                    [[ "$verbose" == true ]] && echo -e "    ${GREEN}✓${NC} Permissions correct (600)"
                else
                    echo -e "  ${RED}✗${NC} $host: Private key has wrong permissions"
                    ((key_issues++))

                    if [[ "$fix" == true ]]; then
                        chmod 600 "$keyfile"
                        echo -e "    ${GREEN}✓${NC} Fixed permissions"
                    fi
                fi

                if verify_key_format "$keyfile"; then
                    [[ "$verbose" == true ]] && echo -e "    ${GREEN}✓${NC} Key format valid"
                else
                    echo -e "  ${RED}✗${NC} $host: Invalid key format"
                    ((key_issues++))
                fi
            else
                echo -e "  ${RED}✗${NC} $host: Private key missing ($keyfile)"
                ((key_issues++))
            fi

            # Check public key
            if [[ -f "$keyfile.pub" ]]; then
                [[ "$verbose" == true ]] && echo -e "    ${GREEN}✓${NC} Public key exists"
            else
                echo -e "  ${YELLOW}⚠${NC} $host: Public key missing"
                ((warnings++))

                if [[ "$fix" == true && -f "$keyfile" ]]; then
                    if ssh-keygen -y -f "$keyfile" > "$keyfile.pub" 2>/dev/null; then
                        chmod 644 "$keyfile.pub"
                        echo -e "    ${GREEN}✓${NC} Generated public key"
                    fi
                fi
            fi
        done <<< "$hosts"

        if [[ -z "$keyname" ]]; then
            echo -e "  Found $key_count managed key(s)"
            if [[ $key_issues -gt 0 ]]; then
                echo -e "  ${RED}$key_issues issue(s) detected${NC}"
                ((issues += key_issues))
            else
                echo -e "  ${GREEN}All keys OK${NC}"
            fi
        fi
    fi
    echo ""

    # Check for duplicate hosts
    echo -e "${BOLD}[4/6] Duplicate Entries${NC}"
    if [[ -f "$SSH_CONFIG" ]]; then
        local duplicates
        duplicates=$(grep "^Host " "$SSH_CONFIG" | sort | uniq -d)

        if [[ -z "$duplicates" ]]; then
            echo -e "  ${GREEN}✓${NC} No duplicate Host entries"
        else
            echo -e "  ${YELLOW}⚠${NC} Duplicate Host entries found:"
            echo "$duplicates" | while read -r dup; do
                echo -e "      - $dup"
            done
            ((warnings++))
        fi
    else
        echo -e "  ${DIM}○${NC} No config file to check"
    fi
    echo ""

    # Check SSH agent
    echo -e "${BOLD}[5/6] SSH Agent${NC}"
    if [[ -n "$SSH_AUTH_SOCK" ]]; then
        echo -e "  ${GREEN}✓${NC} SSH_AUTH_SOCK is set"

        if ssh-add -l &>/dev/null; then
            local agent_keys
            agent_keys=$(ssh-add -l 2>/dev/null | wc -l)
            echo -e "  ${GREEN}✓${NC} Agent running with $agent_keys key(s)"
        elif [[ $? -eq 1 ]]; then
            echo -e "  ${GREEN}✓${NC} Agent running (no keys loaded)"
        else
            echo -e "  ${YELLOW}⚠${NC} Agent not accessible"
            ((warnings++))
        fi
    else
        echo -e "  ${YELLOW}⚠${NC} SSH_AUTH_SOCK not set (agent not running?)"
        ((warnings++))
    fi
    echo ""

    # Check connectivity (if specific key provided)
    echo -e "${BOLD}[6/6] Connectivity${NC}"
    if [[ -n "$keyname" ]]; then
        if host_exists_in_config "$keyname"; then
            echo -e "  Testing connection to $keyname..."
            if test_ssh_connection "$keyname" true; then
                echo -e "  ${GREEN}✓${NC} SSH connection successful"
            else
                echo -e "  ${RED}✗${NC} SSH connection failed"
                ((issues++))
            fi
        else
            echo -e "  ${DIM}○${NC} Key '$keyname' not found"
        fi
    else
        echo -e "  ${DIM}○${NC} Specify a key to test connectivity"
        echo -e "      ${DIM}sshgit doctor <keyname>${NC}"
    fi
    echo ""

    # Summary
    echo "$(printf '%.0s─' {1..50})"
    echo ""

    if [[ $issues -eq 0 && $warnings -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}All checks passed!${NC}"
    else
        if [[ $issues -gt 0 ]]; then
            echo -e "${RED}${BOLD}$issues issue(s) found${NC}"
        fi
        if [[ $warnings -gt 0 ]]; then
            echo -e "${YELLOW}${BOLD}$warnings warning(s)${NC}"
        fi

        if [[ "$fix" != true && $issues -gt 0 ]]; then
            echo ""
            echo "Run with --fix to automatically fix issues:"
            echo -e "  ${CYAN}sshgit doctor --fix${NC}"
        fi
    fi

    return $issues
}
