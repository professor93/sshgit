#!/bin/bash
#
# sshgit - Create Command (Main Key Generation)
#

cmd_create() {
    local name="$1"
    local type="$DEFAULT_TYPE"
    local email="$DEFAULT_EMAIL"
    local add_config="$AUTO_CONFIG"
    local use_clipboard="$AUTO_CLIPBOARD"
    local open_url="$AUTO_OPEN_BROWSER"
    local passphrase_mode=""  # "", "prompt", "empty"

    # Shift only if we have arguments
    if [[ $# -gt 0 ]]; then
        shift
    fi

    # Parse remaining options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c) add_config=true; shift ;;
            -t|--type) type="$2"; shift 2 ;;
            -e|--email) email="$2"; shift 2 ;;
            -p|--passphrase) passphrase_mode="prompt"; shift ;;
            -P|--no-passphrase) passphrase_mode="empty"; shift ;;
            -o|--open) open_url=true; shift ;;
            --clipboard) use_clipboard=true; shift ;;
            *) shift ;;
        esac
    done

    show_logo

    local host repo_name is_repo=false
    local existing_path=""

    # Get name if not provided - use smart input
    if [[ -z "$name" ]]; then
        get_repo_or_path_input

        if [[ -z "$SELECTED_INPUT" && "$SELECTED_TYPE" != "local_no_remote" ]]; then
            log_error "No input provided"
            return 1
        fi

        case "$SELECTED_TYPE" in
            local|local_no_remote)
                existing_path="$SELECTED_PATH"
                name="$SELECTED_INPUT"
                host="$SELECTED_HOST"
                if [[ "$SELECTED_TYPE" == "local" && -n "$name" ]]; then
                    is_repo=true
                fi
                ;;
            *)
                name="$SELECTED_INPUT"
                host="$SELECTED_HOST"
                ;;
        esac
    fi

    # Parse URL/repo if not already set from local path
    if [[ -z "$host" ]]; then
        local parsed
        parsed=$(parse_repo_url "$name")
        host=$(echo "$parsed" | cut -d'|' -f1)
        repo_name=$(echo "$parsed" | cut -d'|' -f2)
    else
        repo_name="$name"
    fi

    local host_short
    host_short=$(get_short_hostname "$host")

    # Check if this is a repo
    if [[ "$is_repo" != true && "$repo_name" == *"/"* ]]; then
        if confirm "Is this a repo?" "y"; then
            is_repo=true
        fi
    fi

    # Validate username for known providers
    if [[ "$is_repo" == true ]]; then
        local username="${repo_name%%/*}"
        local validation_failed=false

        case "$host" in
            github.com)
                if ! validate_github_username "$username"; then
                    validation_failed=true
                fi
                ;;
            bitbucket.org)
                if ! validate_bitbucket_username "$username"; then
                    validation_failed=true
                fi
                ;;
        esac

        if [[ "$validation_failed" == true ]]; then
            read -r -p "Enter correct repo or press Enter to skip: " new_name
            new_name=$(trim "$new_name")
            if [[ -n "$new_name" ]]; then
                local parsed
                parsed=$(parse_repo_url "$new_name")
                repo_name=$(echo "$parsed" | cut -d'|' -f2)
            fi
        fi
    fi

    # Generate key filename
    local filename="$repo_name"
    if [[ "$is_repo" == true ]]; then
        filename="${repo_name//\//__}"
    fi

    local keyname="$host_short-$filename"
    local keypath="$SSH_DIR/$keyname"

    ensure_ssh_dir

    # Check for existing key
    if [[ -f "$keypath" ]]; then
        echo ""
        log_warning "Key '$keyname' already exists!"
        if ! confirm "Overwrite?"; then
            echo "Aborted."
            return 1
        fi
        rm -f "$keypath" "$keypath.pub"
    fi

    # Get key type if interactive
    if [[ "$type" == "$DEFAULT_TYPE" && -t 0 ]]; then
        read -r -p "Key type [$type]: " input_type
        input_type=$(trim "$input_type")
        [[ -n "$input_type" ]] && type="$input_type"
    fi

    # Validate key type
    if ! validate_key_type "$type"; then
        log_warning "Unknown key type '$type', using ed25519"
        type="ed25519"
    fi

    # Ask about SSH config if not set
    if [[ "$add_config" != true && -t 0 ]]; then
        if confirm "Add to SSH config?"; then
            add_config=true
        fi
    fi

    # Generate key
    echo ""
    local keygen_opts=(-C "$email" -f "$keypath")

    if [[ "$type" =~ ^[0-9]+$ ]]; then
        keygen_opts+=(-t rsa -b "$type")
    else
        keygen_opts+=(-t "$type")
    fi

    case "$passphrase_mode" in
        empty)
            keygen_opts+=(-N "")
            ;;
        prompt)
            # Default behavior, ssh-keygen will prompt
            ;;
        *)
            # Ask user
            if [[ -t 0 ]]; then
                if confirm "Set passphrase?"; then
                    passphrase_mode="prompt"
                else
                    keygen_opts+=(-N "")
                fi
            else
                keygen_opts+=(-N "")
            fi
            ;;
    esac

    ssh-keygen "${keygen_opts[@]}"

    if [[ ! -f "$keypath.pub" ]]; then
        log_error "Key generation failed or was cancelled"
        return 1
    fi

    # Add to SSH config
    if [[ "$add_config" == true ]]; then
        add_to_ssh_config "$keyname" "$host" "$keypath"
    fi

    # Show public key
    echo ""
    echo -e "${BOLD}=== Public Key ===${NC}"
    print_key "$(cat "$keypath.pub")"
    echo ""

    # Copy to clipboard
    if [[ "$use_clipboard" == true ]]; then
        if copy_to_clipboard "$(cat "$keypath.pub")"; then
            log_success "Public key copied to clipboard"
        else
            log_warning "Could not copy to clipboard"
            log_info "Install xclip, xsel, or wl-copy for clipboard support"
        fi
    fi

    # Show deploy key URL
    local deploy_url
    deploy_url=$(get_deploy_key_url "$host" "$repo_name")

    if [[ -n "$deploy_url" && "$is_repo" == true ]]; then
        echo -e "Add deploy key here: ${CYAN}$deploy_url${NC}"
        echo ""

        if [[ "$open_url" == true ]]; then
            if open_browser "$deploy_url"; then
                log_success "Opened browser"
            else
                log_warning "Could not open browser"
                log_info "Open the URL manually in your browser"
            fi
        fi
    fi

    # Handle existing local path or current repo
    local update_done=false

    # If we selected a local path, update its remote
    if [[ -n "$existing_path" && "$is_repo" == true ]]; then
        echo ""
        echo "Updating repository at: $existing_path"
        if confirm "Update remote URL to use new SSH key?" "y"; then
            if [[ "$add_config" != true ]]; then
                log_warning "SSH config entry required"
                if confirm "Add to SSH config now?" "y"; then
                    add_to_ssh_config "$keyname" "$host" "$keypath"
                    add_config=true
                fi
            fi

            if [[ "$add_config" == true ]]; then
                git -C "$existing_path" remote set-url origin "git@$keyname:$repo_name.git"
                log_success "Remote URL updated to: git@$keyname:$repo_name.git"
                update_done=true
            fi
        fi
    fi

    # Handle current repo if we're in it
    if [[ "$update_done" != true && "$is_repo" == true ]]; then
        handle_repo_update "$keyname" "$repo_name" "$host" "$keypath" "$add_config" "$deploy_url"
        update_done=$?
    fi

    # Show manual instructions if nothing was updated
    if [[ "$update_done" != true && -z "$existing_path" ]]; then
        echo ""
        echo -e "${BOLD}=== Update your .git/config ===${NC}"
        echo "Change:"
        echo -e "  url = git@$host:$repo_name.git"
        echo "To:"
        echo -e "  url = ${GREEN}git@$keyname:$repo_name.git${NC}"
        echo ""
        echo "Or run:"
        echo -e "  ${CYAN}git remote set-url origin git@$keyname:$repo_name.git${NC}"
    fi
}

# Handle updating existing repos or cloning
handle_repo_update() {
    local keyname="$1"
    local repo_name="$2"
    local host="$3"
    local keypath="$4"
    local add_config="$5"
    local deploy_url="$6"

    local is_matching_repo=false

    # Check if we're in the matching repo
    if is_git_repo; then
        local current_info current_repo
        current_info=$(get_current_repo_info)
        current_repo=$(echo "$current_info" | cut -d'|' -f2)

        if [[ "$current_repo" == "$repo_name" ]]; then
            is_matching_repo=true
            echo "You are in the git project folder for '$repo_name'."
            if confirm "Update remote URL to use new SSH key?"; then
                git remote set-url origin "git@$keyname:$repo_name.git"
                log_success "Remote URL updated to: git@$keyname:$repo_name.git"
                return 0
            fi
        fi
    fi

    # Handle existing project not in current folder
    if [[ "$is_matching_repo" == false ]]; then
        echo ""
        echo "Do you have this repository cloned locally?"
        if confirm "Update an existing local repository?" "n"; then
            echo ""
            read_with_readline "Enter path to repository: " existing_repo_path
            existing_repo_path=$(trim "$existing_repo_path")
            existing_repo_path=$(expand_path "$existing_repo_path")

            if [[ -n "$existing_repo_path" ]] && is_git_repo "$existing_repo_path"; then
                # Ensure SSH config is added
                if [[ "$add_config" != true ]]; then
                    log_warning "SSH config entry required"
                    if confirm "Add to SSH config now?" "y"; then
                        add_to_ssh_config "$keyname" "$host" "$keypath"
                        add_config=true
                    fi
                fi

                if [[ "$add_config" == true ]]; then
                    git -C "$existing_repo_path" remote set-url origin "git@$keyname:$repo_name.git"
                    log_success "Remote URL updated to: git@$keyname:$repo_name.git"

                    # Offer to navigate to folder
                    offer_navigate_to_folder "$existing_repo_path" "n"
                    return 0
                fi
            elif [[ -n "$existing_repo_path" ]]; then
                log_error "Not a git repository: $existing_repo_path"
            fi
        fi
    fi

    # Offer to clone
    if [[ "$is_matching_repo" == false ]]; then
        echo ""
        if confirm "Clone this repo?"; then
            # Ensure SSH config is added for cloning
            if [[ "$add_config" != true ]]; then
                echo ""
                log_warning "SSH config entry required for cloning"
                if confirm "Add to SSH config now?" "y"; then
                    add_to_ssh_config "$keyname" "$host" "$keypath"
                    add_config=true
                else
                    log_error "Cannot clone without SSH config entry"
                    return 1
                fi
            fi

            if [[ "$add_config" == true ]]; then
                local auth_success=false
                local attempts=0
                local max_attempts=3

                while [[ "$auth_success" == false && $attempts -lt $max_attempts ]]; do
                    ((attempts++))

                    if [[ $attempts -eq 1 ]]; then
                        echo ""
                        log_warning "Make sure you've added the public key to your git provider!"
                    fi

                    read -r -p "Press Enter when ready to test connection..." _

                    echo "Testing SSH connection (attempt $attempts/$max_attempts)..."

                    if test_ssh_connection "$keyname" true; then
                        log_success "SSH authentication successful"
                        auth_success=true
                    else
                        log_error "SSH authentication failed"

                        if [[ $attempts -lt $max_attempts ]]; then
                            echo ""
                            echo "It seems like the key hasn't been added yet."
                            echo ""
                            echo -e "${BOLD}=== Public Key ===${NC}"
                            print_key "$(cat "$keypath.pub")"
                            echo ""

                            if [[ -n "$deploy_url" ]]; then
                                echo -e "Add deploy key here: ${CYAN}$deploy_url${NC}"
                                echo ""
                            fi

                            if ! confirm "Try again?" "y"; then
                                break
                            fi
                        fi
                    fi
                done

                if [[ "$auth_success" == true ]]; then
                    clone_repo "$keyname" "$repo_name"
                    return 0
                fi
            fi
        fi
    fi

    return 1
}
