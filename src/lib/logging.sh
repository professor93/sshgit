#!/bin/bash
#
# sshgit - Logging Functions
#

# Show ASCII logo
show_logo() {
    [[ "$QUIET_MODE" == true ]] && return
    cat << 'EOF'
                 __          _ __
   __________  / /_  ____ _(_) /_
  / ___/ ___/ / __ \/ __ `/ / __/
 (__  |__  ) / / / / /_/ / / /_
/____/____/ /_/ /_/\__, /_/\__/
                  /____/
EOF
    echo -e "  ${DIM}Author: https://github.com/professor93${NC}"
    echo -e "  ${DIM}Version: $VERSION | Platform: $PLATFORM${NC}"
    echo ""
}

# Log info message
log_info() {
    [[ "$QUIET_MODE" == true ]] && return
    echo -e "${BLUE}ℹ${NC} $1"
}

# Log success message
log_success() {
    [[ "$QUIET_MODE" == true ]] && return
    echo -e "${GREEN}✓${NC} $1"
}

# Log warning message
log_warning() {
    [[ "$QUIET_MODE" == true ]] && return
    echo -e "${YELLOW}⚠${NC} $1" >&2
}

# Log error message (always shown)
log_error() {
    echo -e "${RED}✗${NC} $1" >&2
}

# Print colored key
print_key() {
    echo -e "${CYAN}$1${NC}"
}
