#!/bin/bash
#
# sshgit - Platform Detection
#

detect_platform() {
    local uname_s uname_o
    uname_s="$(uname -s 2>/dev/null || echo "Unknown")"
    uname_o="$(uname -o 2>/dev/null || echo "Unknown")"

    case "$uname_s" in
        Linux*)
            if grep -qi microsoft /proc/version 2>/dev/null; then
                echo "wsl"
            else
                echo "linux"
            fi
            ;;
        Darwin*)
            echo "macos"
            ;;
        CYGWIN*|MINGW*|MSYS*)
            echo "windows"
            ;;
        *)
            case "$uname_o" in
                Cygwin|Msys|Mingw*)
                    echo "windows"
                    ;;
                *)
                    echo "linux"
                    ;;
            esac
            ;;
    esac
}

# Initialize platform - called once at startup
init_platform() {
    PLATFORM="$(detect_platform)"
    readonly PLATFORM
}
