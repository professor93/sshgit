#!/bin/bash
#
# sshgit - Interactive Key Selector (TUI)
#

# Simple TUI selector without external dependencies
# Uses arrow keys for navigation

cmd_select() {
    local action="${1:-use}"

    show_logo

    local hosts=()
    local host_details=()

    # Load all managed hosts
    while IFS= read -r host; do
        [[ -z "$host" ]] && continue
        hosts+=("$host")

        local details keyfile hostname status
        details=$(get_host_details "$host")
        hostname=$(echo "$details" | cut -d'|' -f1)
        keyfile=$(echo "$details" | cut -d'|' -f2)

        if [[ -f "$keyfile" ]]; then
            status="exists"
        else
            status="missing"
        fi

        host_details+=("$hostname|$status")
    done <<< "$(get_managed_hosts)"

    if [[ ${#hosts[@]} -eq 0 ]]; then
        log_error "No sshgit-managed keys found"
        echo "Create one with: sshgit <user/repo>"
        return 1
    fi

    echo -e "${BOLD}Select a key:${NC}"
    echo -e "${DIM}Use arrow keys to navigate, Enter to select, q to quit${NC}"
    echo ""

    local selected=0
    local total=${#hosts[@]}

    # Save terminal state
    local old_stty
    old_stty=$(stty -g 2>/dev/null) || true

    # Hide cursor
    tput civis 2>/dev/null || true

    # Enable raw input
    stty -icanon -echo 2>/dev/null || true

    # Draw initial list
    draw_selector_list() {
        # Move cursor up to redraw
        if [[ $1 == "redraw" ]]; then
            for ((i = 0; i < total + 1; i++)); do
                tput cuu1 2>/dev/null || echo -en "\033[1A"
            done
        fi

        for ((i = 0; i < total; i++)); do
            local host="${hosts[$i]}"
            local details="${host_details[$i]}"
            local hostname=$(echo "$details" | cut -d'|' -f1)
            local status=$(echo "$details" | cut -d'|' -f2)

            local status_icon
            if [[ "$status" == "exists" ]]; then
                status_icon="${GREEN}●${NC}"
            else
                status_icon="${RED}●${NC}"
            fi

            if [[ $i -eq $selected ]]; then
                echo -e "  ${CYAN}▶${NC} ${BOLD}$host${NC} ${DIM}($hostname)${NC} $status_icon"
            else
                echo -e "    $host ${DIM}($hostname)${NC} $status_icon"
            fi
        done
        echo ""
    }

    draw_selector_list

    # Handle input
    while true; do
        local char
        IFS= read -r -n1 char

        case "$char" in
            $'\x1b')  # Escape sequence
                read -r -n2 -t 0.1 seq || true
                case "$seq" in
                    '[A')  # Up arrow
                        ((selected--))
                        [[ $selected -lt 0 ]] && selected=$((total - 1))
                        draw_selector_list "redraw"
                        ;;
                    '[B')  # Down arrow
                        ((selected++))
                        [[ $selected -ge $total ]] && selected=0
                        draw_selector_list "redraw"
                        ;;
                esac
                ;;
            'k'|'K')  # Vim up
                ((selected--))
                [[ $selected -lt 0 ]] && selected=$((total - 1))
                draw_selector_list "redraw"
                ;;
            'j'|'J')  # Vim down
                ((selected++))
                [[ $selected -ge $total ]] && selected=0
                draw_selector_list "redraw"
                ;;
            ''|$'\n')  # Enter
                break
                ;;
            'q'|'Q')  # Quit
                selected=-1
                break
                ;;
        esac
    done

    # Restore terminal
    stty "$old_stty" 2>/dev/null || true
    tput cnorm 2>/dev/null || true

    if [[ $selected -lt 0 ]]; then
        echo "Cancelled."
        return 0
    fi

    local chosen_key="${hosts[$selected]}"
    echo ""
    log_info "Selected: $chosen_key"
    echo ""

    # Perform action
    case "$action" in
        use)
            if is_git_repo; then
                cmd_use "$chosen_key"
            else
                log_info "Not in a git repository"
                echo "To use this key, run:"
                echo -e "  ${CYAN}sshgit use $chosen_key${NC}"
            fi
            ;;
        test)
            test_ssh_connection "$chosen_key"
            ;;
        copy)
            local details keyfile
            details=$(get_host_details "$chosen_key")
            keyfile=$(echo "$details" | cut -d'|' -f2)

            if [[ -f "$keyfile.pub" ]]; then
                if copy_to_clipboard "$(cat "$keyfile.pub")"; then
                    log_success "Public key copied to clipboard"
                else
                    echo ""
                    echo -e "${BOLD}Public Key:${NC}"
                    cat "$keyfile.pub"
                fi
            else
                log_error "Public key not found"
            fi
            ;;
        show)
            local details keyfile hostname
            details=$(get_host_details "$chosen_key")
            keyfile=$(echo "$details" | cut -d'|' -f2)
            hostname=$(echo "$details" | cut -d'|' -f1)

            echo -e "${BOLD}Key Details:${NC}"
            echo "  Name:     $chosen_key"
            echo "  Host:     $hostname"
            echo "  File:     $keyfile"

            if [[ -f "$keyfile" ]]; then
                local fingerprint
                fingerprint=$(ssh-keygen -lf "$keyfile" 2>/dev/null | awk '{print $2}')
                echo "  SHA256:   $fingerprint"

                local age
                age=$(get_key_age_days "$keyfile")
                echo "  Age:      $age days"
            fi
            ;;
        agent)
            cmd_agent_add "$chosen_key"
            ;;
        remove)
            cmd_remove "$chosen_key"
            ;;
        *)
            echo "Selected key: $chosen_key"
            ;;
    esac
}

# Fuzzy filter for keys (if user provides a filter)
cmd_select_filter() {
    local filter="$1"
    local action="${2:-use}"

    if [[ -z "$filter" ]]; then
        cmd_select "$action"
        return
    fi

    show_logo

    local matches=()

    while IFS= read -r host; do
        [[ -z "$host" ]] && continue
        if [[ "$host" == *"$filter"* ]]; then
            matches+=("$host")
        fi
    done <<< "$(get_managed_hosts)"

    case ${#matches[@]} in
        0)
            log_error "No keys matching '$filter'"
            return 1
            ;;
        1)
            log_info "Found: ${matches[0]}"
            echo ""
            case "$action" in
                use) cmd_use "${matches[0]}" ;;
                test) test_ssh_connection "${matches[0]}" ;;
                *) echo "Key: ${matches[0]}" ;;
            esac
            ;;
        *)
            echo "Multiple matches for '$filter':"
            echo ""
            for match in "${matches[@]}"; do
                echo "  - $match"
            done
            echo ""
            echo "Be more specific or use: sshgit select"
            ;;
    esac
}
