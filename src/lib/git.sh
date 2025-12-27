#!/bin/bash
#
# sshgit - Git Repository Operations
#

# Check if directory is a git repository
is_git_repo() {
    local dir="${1:-.}"
    [[ -d "$dir/.git" ]] || git -C "$dir" rev-parse --git-dir &>/dev/null
}

# Get remote URL from git repository
get_git_remote_url() {
    local dir="${1:-.}"
    git -C "$dir" remote get-url origin 2>/dev/null
}

# Parse repo info from remote URL
# Returns: host|repo_path
parse_git_remote() {
    local remote_url="$1"
    local host="" repo_path=""

    if [[ "$remote_url" =~ ^https?://([^/]+)/(.+)$ ]]; then
        host="${BASH_REMATCH[1]}"
        repo_path="${BASH_REMATCH[2]}"
    elif [[ "$remote_url" =~ ^git@([^:]+):(.+)$ ]]; then
        host="${BASH_REMATCH[1]}"
        repo_path="${BASH_REMATCH[2]}"
    fi

    repo_path="${repo_path%.git}"
    repo_path="${repo_path%/}"

    echo "$host|$repo_path"
}

# Get current repo info from current directory
# Returns: host|repo_path or empty if not a git repo
get_current_repo_info() {
    if ! is_git_repo; then
        return 1
    fi

    local remote_url
    remote_url=$(get_git_remote_url)

    if [[ -z "$remote_url" ]]; then
        return 1
    fi

    parse_git_remote "$remote_url"
}

# Parse repository URL/name
# Returns: host|repo_name
parse_repo_url() {
    local input="$1"
    local host="github.com"
    local name="$input"

    # Extract host from URL if present
    if [[ "$name" =~ ^https?://([^/]+)/(.+)$ ]]; then
        host="${BASH_REMATCH[1]}"
        name="${BASH_REMATCH[2]}"
    elif [[ "$name" =~ ^git@([^:]+):(.+)$ ]]; then
        host="${BASH_REMATCH[1]}"
        name="${BASH_REMATCH[2]}"
    elif [[ "$name" =~ ^([a-zA-Z0-9][-a-zA-Z0-9]*(\.[a-zA-Z0-9][-a-zA-Z0-9]*)+)/(.+)$ ]]; then
        host="${BASH_REMATCH[1]}"
        name="${BASH_REMATCH[3]}"
    fi

    name="${name%.git}"
    name="${name%/}"

    echo "$host|$name"
}

# Get short hostname (remove common TLDs)
get_short_hostname() {
    local host="$1"
    local short="${host%.com}"
    short="${short%.org}"
    short="${short%.io}"
    short="${short%.net}"
    echo "$short"
}

# Get deploy key URL for known providers
get_deploy_key_url() {
    local host="$1"
    local name="$2"

    case "$host" in
        github.com)
            echo "https://github.com/$name/settings/keys/new"
            ;;
        gitlab.com)
            echo "https://gitlab.com/$name/-/settings/repository#js-deploy-keys-settings"
            ;;
        bitbucket.org)
            echo "https://bitbucket.org/$name/admin/access-keys/"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Clone repository
clone_repo() {
    local keyname="$1"
    local repo_name="$2"

    local dir_name="${repo_name##*/}"
    local default_path="$(pwd)/$dir_name"

    echo ""
    read -e -r -p "Clone path [$default_path]: " clone_path
    clone_path=$(trim "$clone_path")
    clone_path="${clone_path:-$default_path}"
    clone_path=$(expand_path "$clone_path")

    local final_path="$clone_path"

    if [[ -d "$clone_path" ]]; then
        if [[ -z "$(ls -A "$clone_path" 2>/dev/null)" ]]; then
            echo ""
            echo "Directory '$clone_path' exists and is empty."
            echo "1) Clone into: $clone_path"
            echo "2) Clone into: $clone_path/$dir_name"
            read -r -p "Choose [1]: " choice
            choice="${choice:-1}"
            [[ "$choice" == "2" ]] && final_path="$clone_path/$dir_name"
        else
            echo ""
            echo "Directory '$clone_path' is not empty."
            if ! confirm "Clone into '$clone_path/$dir_name' instead?" "y"; then
                echo "Aborted."
                return 1
            fi
            final_path="$clone_path/$dir_name"
        fi
    else
        echo ""
        echo "Directory '$clone_path' does not exist."
        echo "1) Create and clone into: $clone_path"
        echo "2) Create and clone into: $clone_path/$dir_name"
        read -r -p "Choose [1]: " choice
        choice="${choice:-1}"
        [[ "$choice" == "2" ]] && final_path="$clone_path/$dir_name"
    fi

    echo ""
    if ! confirm "Clone '$repo_name' to '$final_path'?" "y"; then
        echo "Aborted."
        return 0
    fi

    # Create parent directory
    local parent_dir="${final_path%/*}"
    [[ ! -d "$parent_dir" ]] && mkdir -p "$parent_dir"

    echo ""
    if git clone "git@$keyname:$repo_name.git" "$final_path"; then
        echo ""
        log_success "Successfully cloned to $final_path"

        # Offer to navigate to folder
        offer_navigate_to_folder "$final_path" "n"

        return 0
    else
        echo ""
        log_error "Clone failed"
        return 1
    fi
}
