#!/bin/bash
#
# sshgit build script
# Combines modular source files into a single distributable script
#
# Usage:
#   ./build.sh                    # Build with version from constants.sh
#   ./build.sh --version 1.2.0    # Build with specific version
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR/src"
OUTPUT_FILE="$SCRIPT_DIR/sshgit"
CUSTOM_VERSION=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version|-V)
            CUSTOM_VERSION="$2"
            shift 2
            ;;
        --output|-o)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --version, -V <version>   Set version number (e.g., 1.2.0)"
            echo "  --output, -o <file>       Output file path (default: ./sshgit)"
            echo "  --help, -h                Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Get version from constants.sh if not provided
if [[ -z "$CUSTOM_VERSION" ]]; then
    CUSTOM_VERSION=$(grep 'readonly VERSION=' "$SRC_DIR/lib/constants.sh" | cut -d'"' -f2)
fi

echo "Building sshgit v$CUSTOM_VERSION..."

# Start with shebang and header
cat > "$OUTPUT_FILE" << HEADER
#!/bin/bash
#
# sshgit - SSH Key Manager for Git Repositories
# Version: $CUSTOM_VERSION
# Author: https://github.com/professor93
# License: MIT
#
# Supports: Linux, macOS, Windows (Git Bash, WSL, MSYS2, Cygwin)
#
# This file is auto-generated. Do not edit directly.
# Edit the source files in src/ and run build.sh
#

set -o pipefail

HEADER

# Function to extract content from a file (skip shebang and header comments)
extract_content() {
    local file="$1"
    local in_header=true

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip shebang
        if [[ "$line" == "#!/"* ]]; then
            continue
        fi

        # Skip header comments at the beginning
        if [[ "$in_header" == true ]]; then
            if [[ "$line" == "#"* ]] || [[ -z "$line" ]]; then
                continue
            else
                in_header=false
            fi
        fi

        # Replace version in constants.sh if custom version provided
        if [[ "$file" == *"constants.sh" ]] && [[ -n "$CUSTOM_VERSION" ]]; then
            if [[ "$line" =~ ^readonly[[:space:]]+VERSION= ]]; then
                echo "readonly VERSION=\"$CUSTOM_VERSION\""
                continue
            fi
        fi

        echo "$line"
    done < "$file"
}

# Add section separator
add_section() {
    local name="$1"
    echo "" >> "$OUTPUT_FILE"
    echo "# =============================================================================" >> "$OUTPUT_FILE"
    echo "# $name" >> "$OUTPUT_FILE"
    echo "# =============================================================================" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
}

# Include library files in order
LIBS=(
    "lib/constants.sh"
    "lib/platform.sh"
    "lib/colors.sh"
    "lib/logging.sh"
    "lib/utils.sh"
    "lib/config.sh"
    "lib/clipboard.sh"
    "lib/browser.sh"
    "lib/ssh.sh"
    "lib/git.sh"
    "lib/validation.sh"
    "lib/input.sh"
    "lib/completion.sh"
)

for lib in "${LIBS[@]}"; do
    if [[ -f "$SRC_DIR/$lib" ]]; then
        lib_name=$(basename "$lib" .sh | tr '[:lower:]' '[:upper:]')
        add_section "$lib_name"
        extract_content "$SRC_DIR/$lib" >> "$OUTPUT_FILE"
    else
        echo "Warning: $SRC_DIR/$lib not found, skipping"
    fi
done

# Include command files - find all .sh files in commands directory
COMMANDS=()
if [[ -d "$SRC_DIR/commands" ]]; then
    while IFS= read -r -d '' file; do
        COMMANDS+=("commands/$(basename "$file")")
    done < <(find "$SRC_DIR/commands" -name "*.sh" -type f -print0 | sort -z)
fi

for cmd in "${COMMANDS[@]}"; do
    if [[ -f "$SRC_DIR/$cmd" ]]; then
        cmd_name=$(basename "$cmd" .sh | tr '[:lower:]' '[:upper:]')
        add_section "COMMAND: $cmd_name"
        extract_content "$SRC_DIR/$cmd" >> "$OUTPUT_FILE"
    fi
done

# Add main entry point
add_section "MAIN ENTRY POINT"

cat >> "$OUTPUT_FILE" << 'MAIN'
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
        restore)
            shift
            cmd_restore "$@"
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
        # New commands
        rotate)
            shift
            cmd_rotate "$@"
            ;;
        expire)
            shift
            cmd_expire "$@"
            ;;
        check-expiry|expiry)
            cmd_check_expiry
            ;;
        agent-add)
            shift
            cmd_agent_add "$@"
            ;;
        agent-remove)
            shift
            cmd_agent_remove "$@"
            ;;
        agent-list)
            cmd_agent_list
            ;;
        agent-add-all)
            shift
            cmd_agent_add_all "$@"
            ;;
        agent-remove-all)
            cmd_agent_remove_all
            ;;
        remotes)
            shift
            cmd_remotes "$@"
            ;;
        setup-remotes)
            shift
            cmd_setup_remotes "$@"
            ;;
        profile)
            shift
            cmd_profile "$@"
            ;;
        team)
            shift
            cmd_team "$@"
            ;;
        select)
            shift
            cmd_select "$@"
            ;;
        deploy-key)
            shift
            cmd_deploy_key "$@"
            ;;
        doctor)
            shift
            cmd_doctor "$@"
            ;;
        hook)
            shift
            cmd_hook "$@"
            ;;
        *)
            # Assume it's a repo name for create
            cmd_create "$@"
            ;;
    esac
}

main "$@"
MAIN

# Make executable
chmod +x "$OUTPUT_FILE"

# Get line count and size
lines=$(wc -l < "$OUTPUT_FILE")
size=$(du -h "$OUTPUT_FILE" | cut -f1)

echo ""
echo "Build complete!"
echo "  Version: $CUSTOM_VERSION"
echo "  Output:  $OUTPUT_FILE"
echo "  Lines:   $lines"
echo "  Size:    $size"
