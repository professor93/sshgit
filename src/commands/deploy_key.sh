#!/bin/bash
#
# sshgit - GitHub/GitLab API Integration for Deploy Keys
#

readonly TOKENS_FILE="$HOME/.sshgit-tokens"

# Load saved tokens
load_token() {
    local provider="$1"
    if [[ -f "$TOKENS_FILE" ]]; then
        grep "^$provider|" "$TOKENS_FILE" | cut -d'|' -f2 | head -1
    fi
}

# Save token
save_token() {
    local provider="$1"
    local token="$2"

    # Remove old entry
    if [[ -f "$TOKENS_FILE" ]]; then
        grep -v "^$provider|" "$TOKENS_FILE" > "$TOKENS_FILE.tmp" 2>/dev/null || true
        mv "$TOKENS_FILE.tmp" "$TOKENS_FILE"
    fi

    echo "$provider|$token" >> "$TOKENS_FILE"
    chmod 600 "$TOKENS_FILE"
}

# Get or prompt for token
get_token() {
    local provider="$1"
    local token

    token=$(load_token "$provider")

    if [[ -z "$token" ]]; then
        echo ""
        case "$provider" in
            github)
                echo "GitHub Personal Access Token required."
                echo "Create one at: https://github.com/settings/tokens"
                echo "Required scope: admin:public_key (or repo for deploy keys)"
                ;;
            gitlab)
                echo "GitLab Personal Access Token required."
                echo "Create one at: https://gitlab.com/-/profile/personal_access_tokens"
                echo "Required scope: api"
                ;;
        esac
        echo ""
        read -r -s -p "Enter token: " token
        echo ""

        if [[ -n "$token" ]]; then
            if confirm "Save token for future use?" "y"; then
                save_token "$provider" "$token"
                log_success "Token saved"
            fi
        fi
    fi

    echo "$token"
}

# Push deploy key to GitHub
github_push_deploy_key() {
    local repo="$1"
    local title="$2"
    local key="$3"
    local readonly="${4:-true}"
    local token="$5"

    local response
    response=$(curl -s -X POST \
        -H "Authorization: token $token" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$repo/keys" \
        -d "{\"title\":\"$title\",\"key\":\"$key\",\"read_only\":$readonly}")

    if echo "$response" | grep -q '"id"'; then
        local key_id
        key_id=$(echo "$response" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
        echo "success|$key_id"
    else
        local error
        error=$(echo "$response" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
        echo "error|$error"
    fi
}

# List deploy keys from GitHub
github_list_deploy_keys() {
    local repo="$1"
    local token="$2"

    curl -s \
        -H "Authorization: token $token" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$repo/keys"
}

# Remove deploy key from GitHub
github_remove_deploy_key() {
    local repo="$1"
    local key_id="$2"
    local token="$3"

    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
        -H "Authorization: token $token" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$repo/keys/$key_id")

    [[ "$status" == "204" ]]
}

# Push deploy key to GitLab
gitlab_push_deploy_key() {
    local project="$1"  # URL-encoded project path
    local title="$2"
    local key="$3"
    local can_push="${4:-false}"
    local token="$5"

    local response
    response=$(curl -s -X POST \
        -H "PRIVATE-TOKEN: $token" \
        "https://gitlab.com/api/v4/projects/$project/deploy_keys" \
        -d "title=$title" \
        -d "key=$key" \
        -d "can_push=$can_push")

    if echo "$response" | grep -q '"id"'; then
        local key_id
        key_id=$(echo "$response" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
        echo "success|$key_id"
    else
        local error
        error=$(echo "$response" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
        echo "error|$error"
    fi
}

# Main deploy-key command
cmd_deploy_key() {
    local subcmd="${1:-help}"
    shift 2>/dev/null || true

    case "$subcmd" in
        push|add)
            cmd_deploy_key_push "$@"
            ;;
        list|ls)
            cmd_deploy_key_list "$@"
            ;;
        remove|rm|delete)
            cmd_deploy_key_remove "$@"
            ;;
        *)
            show_logo
            echo -e "${BOLD}Deploy Key Management via API${NC}"
            echo ""
            echo "Usage:"
            echo "  $SCRIPT_NAME deploy-key push <keyname> [--repo <user/repo>]"
            echo "  $SCRIPT_NAME deploy-key list [--repo <user/repo>]"
            echo "  $SCRIPT_NAME deploy-key remove <key-id> [--repo <user/repo>]"
            echo ""
            echo "Options:"
            echo "  --repo <user/repo>    Repository (default: from current directory)"
            echo "  --write               Allow write access (default: read-only)"
            echo ""
            echo "Supported providers:"
            echo "  - GitHub (github.com)"
            echo "  - GitLab (gitlab.com)"
            ;;
    esac
}

# Push deploy key
cmd_deploy_key_push() {
    local keyname=""
    local repo=""
    local write_access=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --repo|-r)
                repo="$2"
                shift 2
                ;;
            --write|-w)
                write_access=true
                shift
                ;;
            *)
                keyname="$1"
                shift
                ;;
        esac
    done

    show_logo

    if [[ -z "$keyname" ]]; then
        log_error "Key name required"
        echo "Usage: $SCRIPT_NAME deploy-key push <keyname> [--repo <user/repo>]"
        return 1
    fi

    # Get key details
    if ! host_exists_in_config "$keyname"; then
        log_error "Key '$keyname' not found in SSH config"
        return 1
    fi

    local details keyfile
    details=$(get_host_details "$keyname")
    keyfile=$(echo "$details" | cut -d'|' -f2)

    if [[ ! -f "$keyfile.pub" ]]; then
        log_error "Public key not found: $keyfile.pub"
        return 1
    fi

    # Get repo from current directory if not specified
    if [[ -z "$repo" ]]; then
        if is_git_repo; then
            local remote_url repo_info
            remote_url=$(get_git_remote_url)
            repo_info=$(parse_git_remote "$remote_url")
            repo=$(echo "$repo_info" | cut -d'|' -f2)
        fi
    fi

    if [[ -z "$repo" ]]; then
        read -r -p "Repository (user/repo): " repo
        repo=$(trim "$repo")
    fi

    if [[ -z "$repo" ]]; then
        log_error "Repository required"
        return 1
    fi

    # Detect provider from keyname
    local provider="github"
    if [[ "$keyname" == gitlab-* ]]; then
        provider="gitlab"
    elif [[ "$keyname" == bitbucket-* ]]; then
        log_error "Bitbucket API not yet supported"
        return 1
    fi

    echo "Provider:   $provider"
    echo "Repository: $repo"
    echo "Key:        $keyname"
    echo "Access:     $([ "$write_access" == true ] && echo "read/write" || echo "read-only")"
    echo ""

    if ! confirm "Push deploy key to $provider?" "y"; then
        echo "Aborted."
        return 0
    fi

    local token
    token=$(get_token "$provider")

    if [[ -z "$token" ]]; then
        log_error "Token required"
        return 1
    fi

    local pubkey title result
    pubkey=$(cat "$keyfile.pub")
    title="sshgit: $keyname"

    echo ""
    log_info "Pushing deploy key..."

    case "$provider" in
        github)
            local readonly="true"
            [[ "$write_access" == true ]] && readonly="false"
            result=$(github_push_deploy_key "$repo" "$title" "$pubkey" "$readonly" "$token")
            ;;
        gitlab)
            local can_push="false"
            [[ "$write_access" == true ]] && can_push="true"
            local encoded_repo
            encoded_repo=$(echo "$repo" | sed 's/\//%2F/g')
            result=$(gitlab_push_deploy_key "$encoded_repo" "$title" "$pubkey" "$can_push" "$token")
            ;;
    esac

    local status msg
    status=$(echo "$result" | cut -d'|' -f1)
    msg=$(echo "$result" | cut -d'|' -f2)

    if [[ "$status" == "success" ]]; then
        log_success "Deploy key added! (ID: $msg)"
    else
        log_error "Failed to add deploy key: $msg"
        return 1
    fi
}

# List deploy keys
cmd_deploy_key_list() {
    local repo=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --repo|-r)
                repo="$2"
                shift 2
                ;;
            *)
                repo="$1"
                shift
                ;;
        esac
    done

    show_logo

    # Get repo from current directory if not specified
    if [[ -z "$repo" ]]; then
        if is_git_repo; then
            local remote_url repo_info
            remote_url=$(get_git_remote_url)
            repo_info=$(parse_git_remote "$remote_url")
            repo=$(echo "$repo_info" | cut -d'|' -f2)
        fi
    fi

    if [[ -z "$repo" ]]; then
        log_error "Repository required"
        echo "Usage: $SCRIPT_NAME deploy-key list <user/repo>"
        return 1
    fi

    local provider="github"
    local token
    token=$(get_token "$provider")

    if [[ -z "$token" ]]; then
        log_error "Token required"
        return 1
    fi

    echo -e "${BOLD}Deploy Keys for $repo:${NC}"
    echo ""

    local response
    response=$(github_list_deploy_keys "$repo" "$token")

    if echo "$response" | grep -q '"message"'; then
        log_error "Failed to fetch deploy keys"
        echo "$response" | grep -o '"message":"[^"]*"' | cut -d'"' -f4
        return 1
    fi

    # Parse and display keys
    echo "$response" | grep -o '"id":[0-9]*\|"title":"[^"]*"\|"read_only":[^,]*' | \
    while read -r line; do
        case "$line" in
            '"id":'*)
                echo -n "  ID: ${line#*:} "
                ;;
            '"title":'*)
                echo -n "| ${line#*:} "
                ;;
            '"read_only":'*)
                local ro="${line#*:}"
                if [[ "$ro" == "true" ]]; then
                    echo "| read-only"
                else
                    echo "| read/write"
                fi
                ;;
        esac
    done

    echo ""
}

# Remove deploy key
cmd_deploy_key_remove() {
    local key_id=""
    local repo=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --repo|-r)
                repo="$2"
                shift 2
                ;;
            *)
                key_id="$1"
                shift
                ;;
        esac
    done

    show_logo

    if [[ -z "$key_id" ]]; then
        log_error "Key ID required"
        echo "Usage: $SCRIPT_NAME deploy-key remove <key-id> [--repo <user/repo>]"
        echo ""
        echo "Find key IDs with: $SCRIPT_NAME deploy-key list"
        return 1
    fi

    if [[ -z "$repo" ]]; then
        if is_git_repo; then
            local remote_url repo_info
            remote_url=$(get_git_remote_url)
            repo_info=$(parse_git_remote "$remote_url")
            repo=$(echo "$repo_info" | cut -d'|' -f2)
        fi
    fi

    if [[ -z "$repo" ]]; then
        log_error "Repository required"
        return 1
    fi

    local token
    token=$(get_token "github")

    if [[ -z "$token" ]]; then
        log_error "Token required"
        return 1
    fi

    echo "Repository: $repo"
    echo "Key ID:     $key_id"
    echo ""

    if ! confirm "Remove this deploy key?"; then
        echo "Aborted."
        return 0
    fi

    if github_remove_deploy_key "$repo" "$key_id" "$token"; then
        log_success "Deploy key removed"
    else
        log_error "Failed to remove deploy key"
        return 1
    fi
}
