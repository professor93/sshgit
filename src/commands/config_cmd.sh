#!/bin/bash
#
# sshgit - Config Command
#

cmd_config() {
    show_logo
    echo -e "${BOLD}Current Configuration:${NC}"
    echo ""
    echo "  Email:          $DEFAULT_EMAIL"
    echo "  Key Type:       $DEFAULT_TYPE"
    echo "  Auto Config:    $AUTO_CONFIG"
    echo "  Auto Clipboard: $AUTO_CLIPBOARD"
    echo "  Auto Browser:   $AUTO_OPEN_BROWSER"
    echo ""
    echo -e "${DIM}Config file: $CONFIG_FILE${NC}"
    echo ""

    if confirm "Edit configuration?"; then
        echo ""
        read -r -p "Default email [$DEFAULT_EMAIL]: " new_email
        [[ -n "$new_email" ]] && DEFAULT_EMAIL="$new_email"

        read -r -p "Default key type [$DEFAULT_TYPE]: " new_type
        [[ -n "$new_type" ]] && DEFAULT_TYPE="$new_type"

        if confirm "Auto-add to SSH config?" "$( [[ "$AUTO_CONFIG" == true ]] && echo y || echo n )"; then
            AUTO_CONFIG=true
        else
            AUTO_CONFIG=false
        fi

        if confirm "Auto-copy to clipboard?" "$( [[ "$AUTO_CLIPBOARD" == true ]] && echo y || echo n )"; then
            AUTO_CLIPBOARD=true
        else
            AUTO_CLIPBOARD=false
        fi

        if confirm "Auto-open browser?" "$( [[ "$AUTO_OPEN_BROWSER" == true ]] && echo y || echo n )"; then
            AUTO_OPEN_BROWSER=true
        else
            AUTO_OPEN_BROWSER=false
        fi

        echo ""
        save_config
    fi
}
