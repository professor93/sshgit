#!/bin/bash
#
# sshgit - Deploy Key Sync for Teams
#

readonly TEAM_CONFIG_FILE=".sshgit-team.yaml"

# Simple YAML parser
parse_yaml_value() {
    local file="$1"
    local key="$2"
    grep "^${key}:" "$file" 2>/dev/null | sed "s/^${key}:[[:space:]]*//" | sed 's/[[:space:]]*$//'
}

# Get nested YAML value
parse_yaml_nested() {
    local file="$1"
    local key="$2"
    grep "^  ${key}:" "$file" 2>/dev/null | sed "s/^  ${key}:[[:space:]]*//" | sed 's/[[:space:]]*$//'
}

# Get team config path
get_team_config_path() {
    local dir="${1:-.}"
    dir=$(expand_path "$dir")

    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/$TEAM_CONFIG_FILE" ]]; then
            echo "$dir/$TEAM_CONFIG_FILE"
            return 0
        fi
        dir=$(dirname "$dir")
    done

    return 1
}

# Initialize team configuration
cmd_team_init() {
    local dir="${1:-.}"
    local config_path="$dir/$TEAM_CONFIG_FILE"

    show_logo

    if [[ -f "$config_path" ]]; then
        if ! confirm "Team config already exists. Overwrite?"; then
            echo "Aborted."
            return 0
        fi
    fi

    echo -e "${BOLD}Initialize Team Configuration${NC}"
    echo ""

    local project_name repo_url key_type
    read -r -p "Project name: " project_name
    project_name=$(trim "$project_name")

    if is_git_repo "$dir"; then
        repo_url=$(get_git_remote_url "$dir")
    fi
    read -r -p "Repository URL [$repo_url]: " input_url
    [[ -n "$input_url" ]] && repo_url="$input_url"

    read -r -p "Key type [ed25519]: " key_type
    key_type="${key_type:-ed25519}"

    local user_email
    user_email=$(git config user.email 2>/dev/null || echo "your@email.com")

    cat > "$config_path" << EOF
# sshgit Team Configuration
# Share this file with your team (DO NOT commit private keys!)

project: $project_name
repository: $repo_url
key_type: $key_type

ssh:
  key_name: ${project_name// /-}
  add_to_config: true

team:
  - $user_email

notes: |
  1. Run 'sshgit team sync' to set up SSH keys
  2. Add your public key to the repository's deploy keys
  3. Test with 'sshgit test <keyname>'
EOF

    log_success "Team config created: $config_path"
    echo ""
    echo "Next steps:"
    echo "  1. Commit the config file"
    echo "  2. Team members run: sshgit team sync"
}

# Sync local setup with team config
cmd_team_sync() {
    local dir="${1:-.}"

    show_logo

    local config_path
    config_path=$(get_team_config_path "$dir")

    if [[ -z "$config_path" ]]; then
        log_error "No team config found"
        echo "Initialize with: sshgit team init"
        return 1
    fi

    echo -e "${BOLD}Syncing with Team Configuration${NC}"
    echo -e "${DIM}Config: $config_path${NC}"
    echo ""

    local project key_name key_type repo_url
    project=$(parse_yaml_value "$config_path" "project")
    key_type=$(parse_yaml_value "$config_path" "key_type")
    repo_url=$(parse_yaml_value "$config_path" "repository")
    key_name=$(parse_yaml_nested "$config_path" "key_name")

    echo "Project:  $project"
    echo "Key Name: $key_name"
    echo "Key Type: $key_type"
    echo ""

    local keypath="$SSH_DIR/$key_name"

    if [[ -f "$keypath" ]]; then
        log_info "Key '$key_name' already exists"

        if host_exists_in_config "$key_name"; then
            log_success "SSH config entry exists"
        else
            if confirm "Add to SSH config?" "y"; then
                local host="github.com"
                if [[ "$repo_url" =~ @([^:]+): ]]; then
                    host="${BASH_REMATCH[1]}"
                elif [[ "$repo_url" =~ ://([^/]+)/ ]]; then
                    host="${BASH_REMATCH[1]}"
                fi
                add_to_ssh_config "$key_name" "$host" "$keypath"
            fi
        fi
    else
        echo "Creating new SSH key..."
        echo ""

        ensure_ssh_dir

        local keygen_opts=(-t "$key_type" -C "$(git config user.email 2>/dev/null || echo "team@$project")" -f "$keypath")

        if confirm "Set passphrase?" "n"; then
            ssh-keygen "${keygen_opts[@]}"
        else
            keygen_opts+=(-N "")
            ssh-keygen "${keygen_opts[@]}"
        fi

        if [[ -f "$keypath.pub" ]]; then
            log_success "Key created: $keypath"

            local host="github.com"
            if [[ "$repo_url" =~ @([^:]+): ]]; then
                host="${BASH_REMATCH[1]}"
            elif [[ "$repo_url" =~ ://([^/]+)/ ]]; then
                host="${BASH_REMATCH[1]}"
            fi
            add_to_ssh_config "$key_name" "$host" "$keypath"
        else
            log_error "Key creation failed"
            return 1
        fi
    fi

    echo ""
    echo -e "${BOLD}=== Your Public Key ===${NC}"
    print_key "$(cat "$keypath.pub")"
    echo ""

    if copy_to_clipboard "$(cat "$keypath.pub")"; then
        log_success "Public key copied to clipboard"
    fi

    echo ""
    log_warning "Add your public key to the repository's deploy keys!"
}

# Add team member
cmd_team_add() {
    local email="$1"
    local dir="${2:-.}"

    if [[ -z "$email" ]]; then
        log_error "Email required"
        echo "Usage: $SCRIPT_NAME team add <email>"
        return 1
    fi

    local config_path
    config_path=$(get_team_config_path "$dir")

    if [[ -z "$config_path" ]]; then
        log_error "No team config found"
        return 1
    fi

    if grep -q "^  - $email$" "$config_path" 2>/dev/null; then
        log_warning "Member '$email' already in team"
        return 0
    fi

    # Add to team section
    sed -i.bak "/^team:/a\\  - $email" "$config_path"
    rm -f "$config_path.bak"

    log_success "Added '$email' to team"
}

# Show team info
cmd_team_info() {
    local dir="${1:-.}"

    show_logo

    local config_path
    config_path=$(get_team_config_path "$dir")

    if [[ -z "$config_path" ]]; then
        log_error "No team config found"
        echo "Initialize with: sshgit team init"
        return 1
    fi

    echo -e "${BOLD}Team Configuration${NC}"
    echo -e "${DIM}$config_path${NC}"
    echo ""

    local project repo_url key_name
    project=$(parse_yaml_value "$config_path" "project")
    repo_url=$(parse_yaml_value "$config_path" "repository")
    key_name=$(parse_yaml_nested "$config_path" "key_name")

    echo "Project:    $project"
    echo "Repository: $repo_url"
    echo "Key Name:   $key_name"
    echo ""

    echo -e "${BOLD}Team Members:${NC}"
    grep "^  - " "$config_path" | sed 's/^  - /  /'
    echo ""

    local keypath="$SSH_DIR/$key_name"
    echo -e "${BOLD}Local Status:${NC}"

    if [[ -f "$keypath" ]]; then
        echo -e "  Key: ${GREEN}exists${NC}"
    else
        echo -e "  Key: ${RED}not found${NC}"
    fi

    if host_exists_in_config "$key_name"; then
        echo -e "  SSH Config: ${GREEN}configured${NC}"
    else
        echo -e "  SSH Config: ${RED}not configured${NC}"
    fi
}

# Main team command router
cmd_team() {
    local subcmd="${1:-info}"
    shift 2>/dev/null || true

    case "$subcmd" in
        init)
            cmd_team_init "$@"
            ;;
        sync)
            cmd_team_sync "$@"
            ;;
        add)
            cmd_team_add "$@"
            ;;
        info|status)
            cmd_team_info "$@"
            ;;
        *)
            log_error "Unknown team command: $subcmd"
            echo ""
            echo "Usage:"
            echo "  $SCRIPT_NAME team init           Initialize team config"
            echo "  $SCRIPT_NAME team sync           Sync local setup"
            echo "  $SCRIPT_NAME team add <email>    Add team member"
            echo "  $SCRIPT_NAME team info           Show team info"
            return 1
            ;;
    esac
}
