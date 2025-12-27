#!/bin/bash
#
# sshgit - Colors and Formatting
#

init_colors() {
    if [[ -t 1 ]]; then
        readonly RED='\033[0;31m'
        readonly GREEN='\033[0;32m'
        readonly YELLOW='\033[0;33m'
        readonly BLUE='\033[0;34m'
        readonly CYAN='\033[0;36m'
        readonly BOLD='\033[1m'
        readonly DIM='\033[2m'
        readonly NC='\033[0m'
    else
        readonly RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' DIM='' NC=''
    fi
}
