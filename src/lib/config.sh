#!/bin/bash
#
# sshgit - Configuration Management
#

# Default configuration values
DEFAULT_EMAIL="someuser@example.com"
DEFAULT_TYPE="ed25519"
AUTO_CONFIG=false
AUTO_CLIPBOARD=false
AUTO_OPEN_BROWSER=false
QUIET_MODE=false

# Load configuration from file
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$CONFIG_FILE" 2>/dev/null
    fi
}

# Save configuration to file
save_config() {
    cat > "$CONFIG_FILE" << EOF
# sshgit configuration file
# Generated on $(date)

DEFAULT_EMAIL="$DEFAULT_EMAIL"
DEFAULT_TYPE="$DEFAULT_TYPE"
AUTO_CONFIG=$AUTO_CONFIG
AUTO_CLIPBOARD=$AUTO_CLIPBOARD
AUTO_OPEN_BROWSER=$AUTO_OPEN_BROWSER
EOF
    chmod 600 "$CONFIG_FILE"
    log_success "Configuration saved to $CONFIG_FILE"
}
