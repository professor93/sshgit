#!/bin/bash
#
# sshgit - Cross-Platform Clipboard Operations
#

# Get the appropriate clipboard command for current platform
get_clipboard_cmd() {
    case "$PLATFORM" in
        macos)
            if command -v pbcopy &>/dev/null; then
                echo "pbcopy"
                return 0
            fi
            ;;
        wsl)
            if command -v clip.exe &>/dev/null; then
                echo "clip.exe"
                return 0
            elif command -v powershell.exe &>/dev/null; then
                echo "powershell.exe -Command Set-Clipboard -Value"
                return 0
            fi
            ;;
        windows)
            if command -v clip &>/dev/null; then
                echo "clip"
                return 0
            elif command -v /c/Windows/System32/clip.exe &>/dev/null; then
                echo "/c/Windows/System32/clip.exe"
                return 0
            elif [[ -f "/dev/clipboard" ]]; then
                echo "cat > /dev/clipboard"
                return 0
            fi
            ;;
        linux)
            if command -v xclip &>/dev/null; then
                echo "xclip -selection clipboard"
                return 0
            elif command -v xsel &>/dev/null; then
                echo "xsel --clipboard --input"
                return 0
            elif command -v wl-copy &>/dev/null; then
                echo "wl-copy"
                return 0
            fi
            ;;
    esac

    # Fallback: try common commands
    for cmd in pbcopy xclip xsel wl-copy; do
        if command -v "$cmd" &>/dev/null; then
            case "$cmd" in
                xclip) echo "xclip -selection clipboard" ;;
                xsel) echo "xsel --clipboard --input" ;;
                *) echo "$cmd" ;;
            esac
            return 0
        fi
    done

    echo ""
    return 1
}

# Copy content to clipboard
copy_to_clipboard() {
    local content="$1"
    local clip_cmd
    clip_cmd=$(get_clipboard_cmd)

    if [[ -z "$clip_cmd" ]]; then
        return 1
    fi

    case "$clip_cmd" in
        "cat > /dev/clipboard")
            echo -n "$content" > /dev/clipboard 2>/dev/null
            return $?
            ;;
        "powershell.exe -Command Set-Clipboard -Value")
            powershell.exe -Command "Set-Clipboard -Value '$content'" 2>/dev/null
            return $?
            ;;
        *)
            echo -n "$content" | $clip_cmd 2>/dev/null
            return $?
            ;;
    esac
}
