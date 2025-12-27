#!/bin/bash
#
# sshgit - Utility Functions
#

# Trim whitespace from string
trim() {
    local var="$1"
    var="${var#"${var%%[![:space:]]*}"}"
    var="${var%"${var##*[![:space:]]}"}"
    echo "$var"
}

# Ask for confirmation
# Usage: confirm "Question?" [default: y/n]
confirm() {
    local prompt="$1"
    local default="${2:-n}"
    local yn

    if [[ "$default" =~ ^[Yy]$ ]]; then
        read -r -p "$prompt [Y/n]: " yn
        [[ ! "$yn" =~ ^[Nn]$ ]]
    else
        read -r -p "$prompt [y/N]: " yn
        [[ "$yn" =~ ^[Yy]$ ]]
    fi
}

# Ensure SSH directory exists
ensure_ssh_dir() {
    if [[ ! -d "$SSH_DIR" ]]; then
        mkdir -p "$SSH_DIR"
        chmod 700 "$SSH_DIR"
        log_info "Created $SSH_DIR directory"
    fi
}

# Ensure SSH config file exists
ensure_ssh_config() {
    if [[ ! -f "$SSH_CONFIG" ]]; then
        touch "$SSH_CONFIG"
        chmod 600 "$SSH_CONFIG"
    fi
}

# Offer to navigate to a directory
# Since child processes can't change parent's directory, we offer options
offer_navigate_to_folder() {
    local folder_path="$1"
    local default="${2:-n}"

    if [[ -z "$folder_path" || ! -d "$folder_path" ]]; then
        return 1
    fi

    echo ""
    if confirm "Go to project folder?" "$default"; then
        echo ""
        echo -e "${BOLD}To navigate to the project folder, run:${NC}"
        echo -e "  ${CYAN}cd \"$folder_path\"${NC}"
        echo ""

        # Copy command to clipboard
        if copy_to_clipboard "cd \"$folder_path\""; then
            log_success "Command copied to clipboard - just paste and press Enter!"
        fi

        # Offer to spawn a new shell in that directory
        if confirm "Open a new shell in the project folder?" "n"; then
            cd "$folder_path" && exec "$SHELL"
        fi
    fi
}

# Expand path (handle ~, make absolute)
expand_path() {
    local path="$1"

    # Expand ~
    path="${path/#\~/$HOME}"

    # Make absolute if relative
    if [[ "$path" != /* ]]; then
        path="$(pwd)/$path"
    fi

    # Remove trailing slash
    path="${path%/}"

    echo "$path"
}
