#!/bin/bash
#
# sshgit - Hosts Command
#

cmd_hosts() {
    show_logo
    echo -e "${BOLD}SSH Config Entries (sshgit-managed):${NC}"
    echo ""

    local hosts
    hosts=$(get_managed_hosts)

    if [[ -z "$hosts" ]]; then
        echo -e "  ${DIM}No hosts found${NC}"
        echo ""
        return
    fi

    while IFS= read -r host; do
        [[ -z "$host" ]] && continue

        local details hostname keyfile
        details=$(get_host_details "$host")
        hostname=$(echo "$details" | cut -d'|' -f1)
        keyfile=$(echo "$details" | cut -d'|' -f2)

        echo -e "  ${CYAN}Host${NC} $host"
        echo -e "      ${DIM}HostName${NC} $hostname"
        echo -e "      ${DIM}IdentityFile${NC} $keyfile"
        echo ""
    done <<< "$hosts"
}
