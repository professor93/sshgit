#!/bin/bash
#
# sshgit - List Command
#

cmd_list() {
    show_logo
    echo -e "${BOLD}SSH Keys managed by sshgit:${NC}"
    echo ""

    local found=false
    local hosts
    hosts=$(get_managed_hosts)

    if [[ -z "$hosts" ]]; then
        echo -e "  ${DIM}No keys found${NC}"
        echo ""
        return
    fi

    printf "  ${BOLD}%-35s %-20s %s${NC}\n" "KEY NAME" "HOST" "STATUS"
    echo "  $(printf '%.0s─' {1..75})"

    while IFS= read -r host; do
        [[ -z "$host" ]] && continue
        found=true

        local details hostname keyfile status
        details=$(get_host_details "$host")
        hostname=$(echo "$details" | cut -d'|' -f1)
        keyfile=$(echo "$details" | cut -d'|' -f2)

        if [[ -f "$keyfile" ]]; then
            status="${GREEN}●${NC} exists"
        else
            status="${RED}●${NC} missing"
        fi

        printf "  %-35s %-20s %b\n" "$host" "$hostname" "$status"
    done <<< "$hosts"

    echo ""
}
