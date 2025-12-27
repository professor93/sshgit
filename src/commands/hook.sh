#!/bin/bash
#
# sshgit - Git Hook Integration
#

readonly HOOK_NAME="pre-push"
readonly HOOK_MARKER="# sshgit-hook"

# Get git hooks directory
get_hooks_dir() {
    local repo_dir="${1:-.}"

    if ! is_git_repo "$repo_dir"; then
        return 1
    fi

    local git_dir
    git_dir=$(git -C "$repo_dir" rev-parse --git-dir 2>/dev/null)

    echo "$git_dir/hooks"
}

# Check if sshgit hook is installed
is_hook_installed() {
    local repo_dir="${1:-.}"
    local hooks_dir
    hooks_dir=$(get_hooks_dir "$repo_dir")

    if [[ -z "$hooks_dir" ]]; then
        return 1
    fi

    local hook_file="$hooks_dir/$HOOK_NAME"

    [[ -f "$hook_file" ]] && grep -q "$HOOK_MARKER" "$hook_file" 2>/dev/null
}

# Generate hook script
generate_hook_script() {
    cat << 'HOOK_SCRIPT'
#!/bin/bash
# sshgit-hook
# Pre-push hook to verify SSH authentication before pushing
# Installed by sshgit - https://github.com/professor93/sshgit

# Get the remote URL
remote_url=$(git remote get-url "$1" 2>/dev/null)

if [[ -z "$remote_url" ]]; then
    exit 0  # No remote URL, skip check
fi

# Only check SSH URLs
if [[ "$remote_url" != git@* ]]; then
    exit 0  # Not an SSH URL, skip
fi

# Extract host from URL
if [[ "$remote_url" =~ ^git@([^:]+): ]]; then
    host="${BASH_REMATCH[1]}"
else
    exit 0  # Couldn't parse URL
fi

echo "sshgit: Verifying SSH authentication to $host..."

# Test connection
ssh_test=$(ssh -T -o BatchMode=yes -o ConnectTimeout=5 "git@$host" 2>&1)
ssh_exit=$?

# Check for success patterns
if [[ "$ssh_test" == *"successfully authenticated"* ]] || \
   [[ "$ssh_test" == *"Welcome"* ]] || \
   [[ "$ssh_test" == *"You've successfully authenticated"* ]] || \
   [[ "$ssh_test" == *"Hi "* ]] || \
   [[ "$ssh_test" == *"logged in as"* ]]; then
    echo "sshgit: Authentication OK"
    exit 0
fi

# Authentication failed
echo ""
echo "sshgit: SSH authentication failed!"
echo ""
echo "This might be because:"
echo "  1. The deploy key hasn't been added to the repository"
echo "  2. The SSH key requires a passphrase (add to ssh-agent first)"
echo "  3. The SSH config is incorrect"
echo ""
echo "To skip this check, use: git push --no-verify"
echo ""

exit 1
HOOK_SCRIPT
}

# Install hook
cmd_hook_install() {
    local repo_dir="${1:-.}"

    show_logo

    repo_dir=$(expand_path "$repo_dir")

    if ! is_git_repo "$repo_dir"; then
        log_error "Not a git repository: $repo_dir"
        return 1
    fi

    local hooks_dir
    hooks_dir=$(get_hooks_dir "$repo_dir")

    if [[ -z "$hooks_dir" ]]; then
        log_error "Could not find hooks directory"
        return 1
    fi

    local hook_file="$hooks_dir/$HOOK_NAME"

    echo "Repository: $repo_dir"
    echo "Hook:       $hook_file"
    echo ""

    # Check if hook already exists
    if [[ -f "$hook_file" ]]; then
        if grep -q "$HOOK_MARKER" "$hook_file" 2>/dev/null; then
            log_warning "sshgit hook already installed"
            return 0
        else
            echo "A $HOOK_NAME hook already exists."
            if ! confirm "Append sshgit hook to existing script?"; then
                echo "Aborted."
                return 0
            fi

            # Append to existing hook
            echo "" >> "$hook_file"
            echo "# --- sshgit hook start ---" >> "$hook_file"
            generate_hook_script >> "$hook_file"
            echo "# --- sshgit hook end ---" >> "$hook_file"

            log_success "sshgit hook appended to existing $HOOK_NAME hook"
            return 0
        fi
    fi

    # Create hooks directory if needed
    mkdir -p "$hooks_dir"

    # Create new hook
    generate_hook_script > "$hook_file"
    chmod +x "$hook_file"

    log_success "Pre-push hook installed"
    echo ""
    echo "The hook will verify SSH authentication before each push."
    echo "To skip the check: git push --no-verify"
}

# Uninstall hook
cmd_hook_uninstall() {
    local repo_dir="${1:-.}"

    show_logo

    repo_dir=$(expand_path "$repo_dir")

    if ! is_git_repo "$repo_dir"; then
        log_error "Not a git repository: $repo_dir"
        return 1
    fi

    local hooks_dir
    hooks_dir=$(get_hooks_dir "$repo_dir")
    local hook_file="$hooks_dir/$HOOK_NAME"

    if [[ ! -f "$hook_file" ]]; then
        log_info "No $HOOK_NAME hook found"
        return 0
    fi

    if ! grep -q "$HOOK_MARKER" "$hook_file" 2>/dev/null; then
        log_info "sshgit hook not installed in $HOOK_NAME"
        return 0
    fi

    echo "Repository: $repo_dir"
    echo "Hook:       $hook_file"
    echo ""

    if ! confirm "Remove sshgit hook?"; then
        echo "Aborted."
        return 0
    fi

    # Check if it's a standalone sshgit hook or embedded
    if grep -q "^$HOOK_MARKER$" "$hook_file" 2>/dev/null; then
        # First line is our marker - it's standalone
        rm -f "$hook_file"
        log_success "Pre-push hook removed"
    else
        # Embedded in another script - remove our section
        sed -i.bak "/$HOOK_MARKER/,/# --- sshgit hook end ---/d" "$hook_file"
        rm -f "$hook_file.bak"
        log_success "sshgit hook removed from $HOOK_NAME"
    fi
}

# Check hook status
cmd_hook_status() {
    local repo_dir="${1:-.}"

    show_logo

    repo_dir=$(expand_path "$repo_dir")

    if ! is_git_repo "$repo_dir"; then
        log_error "Not a git repository: $repo_dir"
        return 1
    fi

    echo -e "${BOLD}Git Hook Status${NC}"
    echo "Repository: $repo_dir"
    echo ""

    if is_hook_installed "$repo_dir"; then
        echo -e "Pre-push hook: ${GREEN}installed${NC}"

        local hooks_dir
        hooks_dir=$(get_hooks_dir "$repo_dir")
        local hook_file="$hooks_dir/$HOOK_NAME"

        if [[ -x "$hook_file" ]]; then
            echo -e "Executable:    ${GREEN}yes${NC}"
        else
            echo -e "Executable:    ${RED}no${NC} (run: chmod +x $hook_file)"
        fi
    else
        echo -e "Pre-push hook: ${DIM}not installed${NC}"
        echo ""
        echo "Install with: $SCRIPT_NAME hook install"
    fi
}

# Main hook command router
cmd_hook() {
    local subcmd="${1:-status}"
    shift 2>/dev/null || true

    case "$subcmd" in
        install|add)
            cmd_hook_install "$@"
            ;;
        uninstall|remove|rm)
            cmd_hook_uninstall "$@"
            ;;
        status)
            cmd_hook_status "$@"
            ;;
        *)
            log_error "Unknown hook command: $subcmd"
            echo ""
            echo "Usage:"
            echo "  $SCRIPT_NAME hook install [path]     Install pre-push hook"
            echo "  $SCRIPT_NAME hook uninstall [path]   Remove pre-push hook"
            echo "  $SCRIPT_NAME hook status [path]      Check hook status"
            return 1
            ;;
    esac
}
