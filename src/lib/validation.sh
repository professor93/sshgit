#!/bin/bash
#
# sshgit - Input Validation
#

# Validate GitHub username via API
validate_github_username() {
    local username="$1"

    if ! command -v curl &>/dev/null; then
        log_warning "curl not found, skipping GitHub validation"
        return 0
    fi

    log_info "Validating username '$username' on GitHub..."
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --connect-timeout 5 \
        "https://api.github.com/users/$username" 2>/dev/null)

    case "$http_code" in
        200)
            log_success "Username '$username' exists"
            return 0
            ;;
        404)
            log_error "No such username '$username' was found"
            return 1
            ;;
        *)
            log_warning "Could not verify username (HTTP $http_code)"
            return 0
            ;;
    esac
}

# Validate Bitbucket username via API
validate_bitbucket_username() {
    local username="$1"

    if ! command -v curl &>/dev/null; then
        log_warning "curl not found, skipping Bitbucket validation"
        return 0
    fi

    log_info "Validating username '$username' on Bitbucket..."
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --connect-timeout 5 \
        "https://api.bitbucket.org/2.0/users/$username" 2>/dev/null)

    case "$http_code" in
        200)
            log_success "Username '$username' exists"
            return 0
            ;;
        404)
            log_error "No such username '$username' was found"
            return 1
            ;;
        *)
            log_warning "Could not verify username (HTTP $http_code)"
            return 0
            ;;
    esac
}

# Validate SSH key type
validate_key_type() {
    local type="$1"

    # Check if it's RSA bits
    if [[ "$type" =~ ^[0-9]+$ ]]; then
        if [[ "$type" -ge 1024 && "$type" -le 16384 ]]; then
            return 0
        fi
        return 1
    fi

    # Check against valid types
    local vt
    for vt in "${VALID_KEY_TYPES[@]}"; do
        [[ "$type" == "$vt" ]] && return 0
    done

    return 1
}

# Check if input looks like a local path
is_local_path() {
    local input="$1"

    # Check for path-like patterns
    [[ "$input" == ~* ]] || \
    [[ "$input" == /* ]] || \
    [[ "$input" == ./* ]] || \
    [[ "$input" == ../* ]] || \
    [[ "$input" =~ ^[a-zA-Z0-9_-]+/ && ! "$input" =~ ^https?:// && ! "$input" =~ ^git@ ]]
}

# Check if input is a URL
is_url() {
    local input="$1"
    [[ "$input" =~ ^https?:// ]] || [[ "$input" =~ ^git@ ]]
}

# Validate that path contains a git repository
validate_git_repo_path() {
    local path="$1"
    path=$(expand_path "$path")

    if [[ ! -d "$path" ]]; then
        log_error "Directory not found: $path"
        return 1
    fi

    if ! is_git_repo "$path"; then
        log_error "Not a git repository: $path"
        return 1
    fi

    return 0
}
