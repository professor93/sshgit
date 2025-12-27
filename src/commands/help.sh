#!/bin/bash
#
# sshgit - Help Command
#

cmd_help() {
    show_logo
    cat << EOF
${BOLD}Usage:${NC} $SCRIPT_NAME <command> [options] [arguments]

${BOLD}Key Management:${NC}
  (default)              Create a new SSH key for a git repository
  list                   List all sshgit-managed SSH keys
  hosts                  Show all sshgit-managed hosts from SSH config
  test <keyname>         Test SSH connection for a key
  use <keyname>          Set SSH key for current git repository
  remove <keyname>       Remove a key and its SSH config entry
  select                 Interactive key selector (TUI)
  import <keypath>       Import an existing SSH key

${BOLD}Key Rotation & Security:${NC}
  rotate <keyname>       Rotate a key (backup old, create new)
  expire <keyname>       Set expiry reminder for a key
  check-expiry           Show expiry status of all keys
  doctor [keyname]       Run health check and diagnostics

${BOLD}SSH Agent:${NC}
  agent-add <keyname>    Add key to ssh-agent
  agent-remove <keyname> Remove key from ssh-agent
  agent-list             List keys in ssh-agent
  agent-add-all          Add all managed keys to agent
  agent-remove-all       Remove all managed keys from agent

${BOLD}Remote Management:${NC}
  remotes                Show remotes and their SSH keys
  setup-remotes          Configure remotes with SSH keys

${BOLD}Profiles & Teams:${NC}
  profile <cmd>          Manage key profiles (list|create|show|delete)
  team <cmd>             Team sync features (init|sync|add|info)

${BOLD}Deploy Keys (API):${NC}
  deploy-key push        Push deploy key via GitHub/GitLab API
  deploy-key list        List deploy keys from repository
  deploy-key remove      Remove deploy key via API

${BOLD}Backup & Restore:${NC}
  backup [path]          Backup all keys (--encrypt for GPG encryption)
  restore <path>         Restore from backup (--decrypt for encrypted)

${BOLD}Other:${NC}
  hook <cmd>             Git hook management (install|uninstall|status)
  config                 View and edit configuration
  completion <shell>     Generate shell completion
  help                   Show this help message
  version                Show version

${BOLD}Options:${NC}
  -h, --help             Show help message
  -v, --version          Show version
  -c                     Auto-add to SSH config
  -t, --type TYPE        Key type (ed25519, rsa, ecdsa) or RSA bits
  -e, --email EMAIL      Custom email for key comment
  -p, --passphrase       Prompt for passphrase
  -P, --no-passphrase    Generate key without passphrase
  -o, --open             Open deploy key URL in browser
  --clipboard            Copy public key to clipboard
  --profile <name>       Use a saved profile
  -q, --quiet            Quiet mode (minimal output)

${BOLD}Examples:${NC}
  $SCRIPT_NAME                                # Interactive mode
  $SCRIPT_NAME user/repo                      # Create key for GitHub repo
  $SCRIPT_NAME user/repo --profile work       # Use profile
  $SCRIPT_NAME select                         # Interactive key picker
  $SCRIPT_NAME rotate github-user__repo       # Rotate a key
  $SCRIPT_NAME doctor --fix                   # Fix permission issues
  $SCRIPT_NAME backup --encrypt               # Encrypted backup
  $SCRIPT_NAME team sync                      # Sync team config

${BOLD}Documentation:${NC}
  https://github.com/professor93/sshgit

EOF
}

cmd_version() {
    echo "$SCRIPT_NAME version $VERSION (platform: $PLATFORM)"
}
