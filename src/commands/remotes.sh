#!/bin/bash
#
# sshgit - Multiple Remote Support
#

# Get all remotes from a git repository
get_git_remotes() {
    local dir="${1:-.}"
    git -C "$dir" remote 2>/dev/null
}

# Get remote URL
get_remote_url() {
    local dir="${1:-.}"
    local remote="${2:-origin}"
    git -C "$dir" remote get-url "$remote" 2>/dev/null
}

# Set remote URL
set_remote_url() {
    local dir="${1:-.}"
    local remote="${2:-origin}"
    local url="$3"
    git -C "$dir" remote set-url "$remote" "$url" 2>/dev/null
}

# List all remotes with their URLs and key info
cmd_remotes() {
    local repo_dir="."

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -C|--dir)
                repo_dir="$2"
                shift 2
                ;;
            *)
                repo_dir="$1"
                shift
                ;;
        esac
    done

    repo_dir=$(expand_path "$repo_dir")

    show_logo

    if ! is_git_repo "$repo_dir"; then
        log_error "Not a git repository: $repo_dir"
        return 1
    fi

    echo -e "${BOLD}Git Remotes:${NC}"
    echo -e "${DIM}Repository: $repo_dir${NC}"
    echo ""

    local remotes
    remotes=$(get_git_remotes "$repo_dir")

    if [[ -z "$remotes" ]]; then
        echo -e "  ${DIM}No remotes configured${NC}"
        return 0
    fi

    local managed_hosts
    managed_hosts=$(get_managed_hosts)

    while IFS= read -r remote; do
        [[ -z "$remote" ]] && continue

        local url
        url=$(get_remote_url "$repo_dir" "$remote")

        echo -e "  ${CYAN}$remote${NC}"
        echo -e "      URL: $url"

        # Check if using sshgit key
        local key_info="${DIM}not using sshgit key${NC}"

        if [[ "$url" =~ ^git@([^:]+): ]]; then
            local host="${BASH_REMATCH[1]}"

            while IFS= read -r managed_host; do
                if [[ "$host" == "$managed_host" ]]; then
                    local details keyfile
                    details=$(get_host_details "$managed_host")
                    keyfile=$(echo "$details" | cut -d'|' -f2)

                    if [[ -f "$keyfile" ]]; then
                        key_info="${GREEN}$managed_host${NC}"
                    else
                        key_info="${YELLOW}$managed_host (key missing)${NC}"
                    fi
                    break
                fi
            done <<< "$managed_hosts"
        fi

        echo -e "      Key: $key_info"
        echo ""
    done <<< "$remotes"
}

# Use a key for a specific remote
cmd_use_remote() {
    local keyname=""
    local remote="origin"
    local repo_dir="."

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --remote|-r)
                remote="$2"
                shift 2
                ;;
            -C|--dir)
                repo_dir="$2"
                shift 2
                ;;
            *)
                if [[ -z "$keyname" ]]; then
                    keyname="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$keyname" ]]; then
        log_error "Key name required"
        echo "Usage: $SCRIPT_NAME use <keyname> [--remote <remote>] [-C <path>]"
        return 1
    fi

    repo_dir=$(expand_path "$repo_dir")

    show_logo

    if ! host_exists_in_config "$keyname"; then
        log_error "Host '$keyname' not found in SSH config"
        return 1
    fi

    if ! is_git_repo "$repo_dir"; then
        log_error "Not a git repository: $repo_dir"
        return 1
    fi

    local current_url
    current_url=$(get_remote_url "$repo_dir" "$remote")

    if [[ -z "$current_url" ]]; then
        log_error "Remote '$remote' not found"
        echo ""
        echo "Available remotes:"
        get_git_remotes "$repo_dir" | while read -r r; do
            echo "  - $r"
        done
        return 1
    fi

    # Parse current URL to get repo path
    local repo_info repo_path
    repo_info=$(parse_git_remote "$current_url")
    repo_path=$(echo "$repo_info" | cut -d'|' -f2)

    if [[ -z "$repo_path" ]]; then
        log_error "Could not parse remote URL: $current_url"
        return 1
    fi

    local new_url="git@$keyname:$repo_path.git"

    echo "Remote:      $remote"
    echo "Repository:  $repo_dir"
    echo "Current URL: $current_url"
    echo "New URL:     $new_url"
    echo ""

    if confirm "Update remote URL?"; then
        set_remote_url "$repo_dir" "$remote" "$new_url"
        log_success "Remote '$remote' updated to use key: $keyname"
    else
        echo "Aborted."
    fi
}

# Set up multiple remotes with different keys
cmd_setup_remotes() {
    local repo_dir="."

    if [[ -n "$1" && "$1" != -* ]]; then
        repo_dir="$1"
    fi

    repo_dir=$(expand_path "$repo_dir")

    show_logo

    if ! is_git_repo "$repo_dir"; then
        log_error "Not a git repository: $repo_dir"
        return 1
    fi

    echo -e "${BOLD}Setup Remotes with SSH Keys${NC}"
    echo -e "${DIM}Repository: $repo_dir${NC}"
    echo ""

    local remotes
    remotes=$(get_git_remotes "$repo_dir")

    if [[ -z "$remotes" ]]; then
        log_error "No remotes configured"
        return 1
    fi

    local hosts
    hosts=$(get_managed_hosts)

    if [[ -z "$hosts" ]]; then
        log_error "No sshgit-managed keys found"
        echo "Create a key first with: sshgit <user/repo>"
        return 1
    fi

    # Build array of available keys
    local keys=()
    while IFS= read -r host; do
        [[ -n "$host" ]] && keys+=("$host")
    done <<< "$hosts"

    while IFS= read -r remote; do
        [[ -z "$remote" ]] && continue

        local current_url
        current_url=$(get_remote_url "$repo_dir" "$remote")

        echo -e "${CYAN}Remote: $remote${NC}"
        echo "  Current URL: $current_url"
        echo ""

        if ! confirm "  Configure this remote?" "n"; then
            echo ""
            continue
        fi

        echo ""
        echo "  Available keys:"
        local i=1
        for key in "${keys[@]}"; do
            echo "    $i) $key"
            ((i++))
        done
        echo "    0) Skip this remote"
        echo ""

        read -r -p "  Select key [0]: " choice
        choice="${choice:-0}"

        if [[ "$choice" == "0" ]]; then
            echo ""
            continue
        fi

        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#keys[@]} ]]; then
            local selected_key="${keys[$((choice-1))]}"

            local repo_info repo_path
            repo_info=$(parse_git_remote "$current_url")
            repo_path=$(echo "$repo_info" | cut -d'|' -f2)

            if [[ -n "$repo_path" ]]; then
                local new_url="git@$selected_key:$repo_path.git"
                set_remote_url "$repo_dir" "$remote" "$new_url"
                log_success "  Remote '$remote' updated to use: $selected_key"
            else
                log_error "  Could not parse URL"
            fi
        else
            log_error "  Invalid choice"
        fi

        echo ""
    done <<< "$remotes"

    echo ""
    log_success "Remote setup complete"
}
