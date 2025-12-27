#!/bin/bash
#
# sshgit - Cross-Platform Browser Operations
#

# Get the appropriate browser command for current platform
get_browser_cmd() {
    case "$PLATFORM" in
        macos)
            echo "open"
            return 0
            ;;
        wsl)
            if command -v wslview &>/dev/null; then
                echo "wslview"
                return 0
            elif command -v explorer.exe &>/dev/null; then
                echo "explorer.exe"
                return 0
            elif command -v powershell.exe &>/dev/null; then
                echo "powershell.exe -Command Start-Process"
                return 0
            elif command -v cmd.exe &>/dev/null; then
                echo "cmd.exe /c start"
                return 0
            fi
            ;;
        windows)
            if command -v start &>/dev/null; then
                echo "start"
                return 0
            elif command -v cygstart &>/dev/null; then
                echo "cygstart"
                return 0
            elif command -v explorer &>/dev/null; then
                echo "explorer"
                return 0
            elif [[ -f "/c/Windows/explorer.exe" ]]; then
                echo "/c/Windows/explorer.exe"
                return 0
            fi
            ;;
        linux)
            if command -v xdg-open &>/dev/null; then
                echo "xdg-open"
                return 0
            elif command -v gnome-open &>/dev/null; then
                echo "gnome-open"
                return 0
            elif command -v kde-open &>/dev/null; then
                echo "kde-open"
                return 0
            fi
            ;;
    esac

    # Fallback
    for cmd in xdg-open open start cygstart; do
        if command -v "$cmd" &>/dev/null; then
            echo "$cmd"
            return 0
        fi
    done

    echo ""
    return 1
}

# Open URL in browser
open_browser() {
    local url="$1"
    local browser_cmd
    browser_cmd=$(get_browser_cmd)

    if [[ -z "$browser_cmd" ]]; then
        return 1
    fi

    case "$browser_cmd" in
        "powershell.exe -Command Start-Process")
            powershell.exe -Command "Start-Process '$url'" 2>/dev/null &
            return $?
            ;;
        "cmd.exe /c start")
            cmd.exe /c start "" "$url" 2>/dev/null &
            return $?
            ;;
        explorer.exe|/c/Windows/explorer.exe)
            "$browser_cmd" "$url" 2>/dev/null &
            return $?
            ;;
        start)
            start "$url" 2>/dev/null || cmd //c start "" "$url" 2>/dev/null &
            return $?
            ;;
        *)
            $browser_cmd "$url" 2>/dev/null &
            return $?
            ;;
    esac
}
