#!/bin/bash
#
# sshgit - Import Command
#

cmd_import() {
    local keypath="$1"

    if [[ -z "$keypath" ]]; then
        log_error "Key path required"
        echo "Usage: $SCRIPT_NAME import <keypath>"
        return 1
    fi

    show_logo

    keypath=$(expand_path "$keypath")

    if [[ ! -f "$keypath" ]]; then
        log_error "Key file not found: $keypath"
        return 1
    fi

    local keyname host

    read -r -p "Key name (e.g., github-myproject): " keyname
    keyname=$(trim "$keyname")

    if [[ -z "$keyname" ]]; then
        log_error "Key name required"
        return 1
    fi

    read -r -p "Git host [github.com]: " host
    host=$(trim "$host")
    host="${host:-github.com}"

    local target_path="$SSH_DIR/$keyname"

    if [[ -f "$target_path" ]]; then
        if ! confirm "Key '$keyname' already exists. Overwrite?"; then
            echo "Aborted."
            return 0
        fi
    fi

    ensure_ssh_dir

    cp "$keypath" "$target_path"
    chmod 600 "$target_path"
    log_success "Imported private key"

    if [[ -f "$keypath.pub" ]]; then
        cp "$keypath.pub" "$target_path.pub"
        chmod 644 "$target_path.pub"
        log_success "Imported public key"
    elif [[ -f "${keypath%.pub}.pub" ]]; then
        cp "${keypath%.pub}.pub" "$target_path.pub"
        chmod 644 "$target_path.pub"
        log_success "Imported public key"
    else
        log_warning "Public key not found, generating from private key..."
        if ssh-keygen -y -f "$target_path" > "$target_path.pub" 2>/dev/null; then
            chmod 644 "$target_path.pub"
            log_success "Generated public key"
        else
            log_error "Could not generate public key"
        fi
    fi

    if confirm "Add to SSH config?"; then
        add_to_ssh_config "$keyname" "$host" "$target_path"
    fi

    echo ""
    log_success "Key '$keyname' imported successfully"
}
