#!/bin/bash
#
# sshgit - Use Command
#

cmd_use() {
    local keyname="$1"

    if [[ -z "$keyname" ]]; then
        log_error "Key name required"
        echo "Usage: $SCRIPT_NAME use <keyname>"
        return 1
    fi

    show_logo

    if ! host_exists_in_config "$keyname"; then
        log_error "Host '$keyname' not found in SSH config"
        return 1
    fi

    local repo_dir=""
    local current_remote=""

    # Check if we're in a git repository
    if is_git_repo; then
        repo_dir="$(pwd)"
        current_remote=$(get_git_remote_url)
    else
        # Ask for the repository folder
        echo "Not currently in a git repository."
        echo ""

        read_with_readline "Enter path to git repository: " repo_dir
        repo_dir=$(trim "$repo_dir")
        repo_dir=$(expand_path "$repo_dir")

        if [[ -z "$repo_dir" ]]; then
            log_error "Repository path required"
            return 1
        fi

        if ! is_git_repo "$repo_dir"; then
            log_error "Not a git repository: $repo_dir"
            return 1
        fi

        current_remote=$(get_git_remote_url "$repo_dir")
    fi

    if [[ -z "$current_remote" ]]; then
        log_error "No 'origin' remote found"
        return 1
    fi

    # Extract repo path from current remote
    local repo_info repo_path
    repo_info=$(parse_git_remote "$current_remote")
    repo_path=$(echo "$repo_info" | cut -d'|' -f2)

    if [[ -z "$repo_path" ]]; then
        log_error "Could not parse remote URL"
        return 1
    fi

    local new_url="git@$keyname:$repo_path.git"

    echo "Repository: $repo_dir"
    echo "Current remote: $current_remote"
    echo "New remote:     $new_url"
    echo ""

    if confirm "Update remote URL?"; then
        git -C "$repo_dir" remote set-url origin "$new_url"
        log_success "Remote URL updated"

        # Offer to navigate to folder if not already there
        if [[ "$(pwd)" != "$repo_dir" ]]; then
            offer_navigate_to_folder "$repo_dir" "n"
        fi
    else
        echo "Aborted."
    fi
}
