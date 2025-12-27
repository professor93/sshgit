#!/bin/bash
#
# sshgit - Remove Command
#

cmd_remove() {
    local keyname="$1"

    if [[ -z "$keyname" ]]; then
        log_error "Key name required"
        echo "Usage: $SCRIPT_NAME remove <keyname>"
        return 1
    fi

    show_logo

    local details keyfile
    details=$(get_host_details "$keyname")
    keyfile=$(echo "$details" | cut -d'|' -f2)

    local found_something=false

    echo -e "${BOLD}Will remove:${NC}"

    if host_exists_in_config "$keyname"; then
        echo "  - SSH config entry: $keyname"
        found_something=true
    fi

    if [[ -n "$keyfile" && -f "$keyfile" ]]; then
        echo "  - Private key: $keyfile"
        found_something=true
    fi

    if [[ -n "$keyfile" && -f "$keyfile.pub" ]]; then
        echo "  - Public key: $keyfile.pub"
        found_something=true
    fi

    if [[ "$found_something" != true ]]; then
        log_error "Key '$keyname' not found"
        return 1
    fi

    echo ""
    if ! confirm "Are you sure?"; then
        echo "Aborted."
        return 0
    fi

    echo ""

    if remove_from_ssh_config "$keyname"; then
        log_success "Removed from SSH config"
    fi

    if [[ -n "$keyfile" && -f "$keyfile" ]]; then
        rm -f "$keyfile"
        log_success "Removed private key"
    fi

    if [[ -n "$keyfile" && -f "$keyfile.pub" ]]; then
        rm -f "$keyfile.pub"
        log_success "Removed public key"
    fi

    echo ""
    log_success "Key '$keyname' removed successfully"
}
