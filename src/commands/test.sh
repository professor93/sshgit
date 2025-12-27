#!/bin/bash
#
# sshgit - Test Command
#

cmd_test() {
    local keyname="$1"

    if [[ -z "$keyname" ]]; then
        log_error "Key name required"
        echo "Usage: $SCRIPT_NAME test <keyname>"
        return 1
    fi

    show_logo

    if ! host_exists_in_config "$keyname"; then
        log_error "Host '$keyname' not found in SSH config"
        return 1
    fi

    test_ssh_connection "$keyname"
}
