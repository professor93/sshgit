#!/bin/bash
#
# sshgit - SSH Key Manager for Git Repositories
# Author: https://github.com/professor93
# License: MIT
#
# Supports: Linux, macOS, Windows (Git Bash, WSL, MSYS2, Cygwin)
#

set -o pipefail

# =============================================================================
# SOURCE LIBRARIES (replaced by build script with actual content)
# =============================================================================

# @include lib/constants.sh
# @include lib/platform.sh
# @include lib/colors.sh
# @include lib/logging.sh
# @include lib/utils.sh
# @include lib/config.sh
# @include lib/clipboard.sh
# @include lib/browser.sh
# @include lib/ssh.sh
# @include lib/git.sh
# @include lib/validation.sh
# @include lib/input.sh
# @include lib/completion.sh

# =============================================================================
# SOURCE COMMANDS (replaced by build script with actual content)
# =============================================================================

# @include commands/help.sh
# @include commands/list.sh
# @include commands/hosts.sh
# @include commands/test.sh
# @include commands/use.sh
# @include commands/remove.sh
# @include commands/backup.sh
# @include commands/import.sh
# @include commands/config_cmd.sh
# @include commands/create.sh

# =============================================================================
# MAIN ENTRY POINT
# =============================================================================

main() {
    # Initialize platform and colors
    init_platform
    init_colors

    # Load configuration
    load_config

    # Handle global flags first
    local args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                cmd_help
                return 0
                ;;
            -v|--version)
                cmd_version
                return 0
                ;;
            -q|--quiet)
                QUIET_MODE=true
                shift
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    set -- "${args[@]}"

    # Route to appropriate command
    local command="${1:-}"

    case "$command" in
        "")
            cmd_create
            ;;
        help)
            cmd_help
            ;;
        version)
            cmd_version
            ;;
        list)
            cmd_list
            ;;
        hosts)
            cmd_hosts
            ;;
        test)
            shift
            cmd_test "$@"
            ;;
        use)
            shift
            cmd_use "$@"
            ;;
        remove|rm|delete)
            shift
            cmd_remove "$@"
            ;;
        backup)
            shift
            cmd_backup "$@"
            ;;
        import)
            shift
            cmd_import "$@"
            ;;
        config)
            cmd_config
            ;;
        completion)
            shift
            cmd_completion "$@"
            ;;
        *)
            # Assume it's a repo name for create
            cmd_create "$@"
            ;;
    esac
}

main "$@"
