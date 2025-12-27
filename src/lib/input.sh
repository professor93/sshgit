#!/bin/bash
#
# sshgit - Smart Input with Path Autocomplete
#
# Features:
# - Detects if current directory is a git repo
# - TAB autocomplete for local paths (directories only)
# - No autocomplete for URLs or plain repo names
# - Validates git repos when path is entered
#

# Directory completion function for readline
_sshgit_complete_dirs() {
    local cur="$1"
    local expanded_cur

    # Expand ~ to home directory for completion
    expanded_cur="${cur/#\~/$HOME}"

    # Get directory completions
    local completions=()
    local dir

    # Handle different path patterns
    if [[ "$expanded_cur" == */ ]]; then
        # Path ends with /, list contents of that directory
        if [[ -d "$expanded_cur" ]]; then
            while IFS= read -r -d '' dir; do
                local basename="${dir##*/}"
                completions+=("${cur}${basename}/")
            done < <(find "$expanded_cur" -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null | sort -z)
        fi
    else
        # Path doesn't end with /, complete the partial name
        local parent="${expanded_cur%/*}"
        local partial="${expanded_cur##*/}"

        # Handle root and relative paths
        if [[ "$expanded_cur" == /* && "$parent" == "" ]]; then
            parent="/"
        elif [[ "$parent" == "" ]]; then
            parent="."
        fi

        if [[ -d "$parent" ]]; then
            while IFS= read -r -d '' dir; do
                local basename="${dir##*/}"
                if [[ "$basename" == "$partial"* ]]; then
                    # Reconstruct the path with original prefix (preserving ~)
                    if [[ "$cur" == ~* ]]; then
                        local rel_path="${dir#$HOME}"
                        completions+=("~${rel_path}/")
                    elif [[ "$cur" == /* ]]; then
                        completions+=("${dir}/")
                    else
                        # Relative path
                        local prefix="${cur%/*}"
                        if [[ "$prefix" == "$cur" ]]; then
                            completions+=("${basename}/")
                        else
                            completions+=("${prefix}/${basename}/")
                        fi
                    fi
                fi
            done < <(find "$parent" -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null | sort -z)
        fi
    fi

    printf '%s\n' "${completions[@]}"
}

# Check if input should trigger path autocomplete
should_complete_path() {
    local input="$1"

    # Don't complete URLs
    if [[ "$input" =~ ^https?:// ]] || [[ "$input" =~ ^git@ ]]; then
        return 1
    fi

    # Complete paths starting with these patterns
    [[ "$input" == ~* ]] || \
    [[ "$input" == /* ]] || \
    [[ "$input" == .* ]] || \
    [[ "$input" =~ / ]]
}

# Custom readline input with directory completion
# Only completes directories, not files
read_with_dir_completion() {
    local prompt="$1"
    local varname="$2"
    local input=""
    local char
    local cursor_pos=0

    # Save terminal settings
    local old_stty
    old_stty=$(stty -g 2>/dev/null) || true

    # Print prompt
    echo -n "$prompt"

    # Enable character-by-character reading
    stty -icanon -echo 2>/dev/null || true

    while true; do
        # Read a single character
        IFS= read -r -n1 char

        case "$char" in
            $'\t')  # TAB - autocomplete
                if should_complete_path "$input"; then
                    local completions
                    completions=$(_sshgit_complete_dirs "$input")
                    local count
                    count=$(echo "$completions" | grep -c .)

                    if [[ $count -eq 1 && -n "$completions" ]]; then
                        # Single match - complete it
                        # Clear current input display
                        echo -en "\r\033[K$prompt"
                        input="$completions"
                        echo -n "$input"
                    elif [[ $count -gt 1 ]]; then
                        # Multiple matches - show them
                        echo ""
                        echo "$completions" | while read -r comp; do
                            echo "  $comp"
                        done
                        echo -n "$prompt$input"
                    fi
                fi
                ;;
            $'\177'|$'\b')  # Backspace
                if [[ ${#input} -gt 0 ]]; then
                    input="${input%?}"
                    echo -en "\b \b"
                fi
                ;;
            ''|$'\n')  # Enter
                echo ""
                break
                ;;
            $'\e')  # Escape sequence (arrow keys, etc)
                # Read the rest of the escape sequence
                read -r -n2 -t 0.1 _escape_seq || true
                ;;
            *)
                input+="$char"
                echo -n "$char"
                ;;
        esac
    done

    # Restore terminal settings
    stty "$old_stty" 2>/dev/null || true

    # Return the input
    eval "$varname=\$input"
}

# Simplified fallback using read -e (readline)
# Works on most systems with basic completion
read_with_readline() {
    local prompt="$1"
    local varname="$2"
    local result

    # Temporarily set up completion for directories only
    if [[ -n "$BASH_VERSION" ]]; then
        # Store old completion
        local old_complete
        old_complete=$(complete -p -D 2>/dev/null || true)

        # Set directory-only completion
        complete -o nospace -o dirnames -D 2>/dev/null || true
    fi

    read -e -r -p "$prompt" result

    # Restore old completion
    if [[ -n "$BASH_VERSION" && -n "$old_complete" ]]; then
        eval "$old_complete" 2>/dev/null || true
    fi

    eval "$varname=\$result"
}

# Main smart input function
# Detects context and provides appropriate input method
get_repo_or_path_input() {
    local current_repo_info=""
    local current_repo_name=""
    local current_host=""

    # Check if we're in a git repository
    if is_git_repo; then
        current_repo_info=$(get_current_repo_info)
        if [[ -n "$current_repo_info" ]]; then
            current_host=$(echo "$current_repo_info" | cut -d'|' -f1)
            current_repo_name=$(echo "$current_repo_info" | cut -d'|' -f2)
        fi
    fi

    # Show options if in a git repo
    if [[ -n "$current_repo_name" ]]; then
        echo ""
        echo -e "${BOLD}Current directory is a git repository:${NC}"
        echo -e "  Repository: ${CYAN}$current_repo_name${NC}"
        echo -e "  Host: ${DIM}$current_host${NC}"
        echo ""
        echo "Options:"
        echo "  1) Use current repository ($current_repo_name)"
        echo "  2) Enter a different repo name (user/repo)"
        echo "  3) Enter a local path to another repository"
        echo "  4) Enter a remote URL"
        echo ""

        local choice
        read -r -p "Choice [1]: " choice
        choice="${choice:-1}"

        case "$choice" in
            1)
                SELECTED_INPUT="$current_repo_name"
                SELECTED_HOST="$current_host"
                SELECTED_TYPE="repo"
                return 0
                ;;
            2)
                echo ""
                read -r -p "Enter repo name (user/repo): " SELECTED_INPUT
                SELECTED_INPUT=$(trim "$SELECTED_INPUT")
                SELECTED_TYPE="repo"
                return 0
                ;;
            3)
                echo ""
                prompt_for_local_path
                return $?
                ;;
            4)
                echo ""
                read -r -p "Enter remote URL: " SELECTED_INPUT
                SELECTED_INPUT=$(trim "$SELECTED_INPUT")
                SELECTED_TYPE="url"
                return 0
                ;;
            *)
                log_error "Invalid choice"
                return 1
                ;;
        esac
    else
        # Not in a git repo - show standard prompt with smart completion
        prompt_standard_input
        return $?
    fi
}

# Prompt for local path with validation
prompt_for_local_path() {
    local path_input

    while true; do
        echo -e "${DIM}(TAB for directory completion)${NC}"
        read_with_readline "Enter path to git repository: " path_input
        path_input=$(trim "$path_input")

        if [[ -z "$path_input" ]]; then
            log_error "Path required"
            continue
        fi

        # Expand and validate
        local expanded_path
        expanded_path=$(expand_path "$path_input")

        if [[ ! -d "$expanded_path" ]]; then
            log_error "Directory not found: $expanded_path"
            echo ""
            continue
        fi

        if ! is_git_repo "$expanded_path"; then
            log_error "Git repository not found in: $expanded_path"
            echo "Please enter a path to a directory containing a .git folder."
            echo ""
            continue
        fi

        # Get repo info from the path
        local remote_url repo_info
        remote_url=$(get_git_remote_url "$expanded_path")

        if [[ -z "$remote_url" ]]; then
            log_error "No remote 'origin' found in repository"
            if ! confirm "Continue anyway?" "n"; then
                continue
            fi
            SELECTED_INPUT=""
            SELECTED_PATH="$expanded_path"
            SELECTED_TYPE="local_no_remote"
            return 0
        fi

        repo_info=$(parse_git_remote "$remote_url")
        SELECTED_HOST=$(echo "$repo_info" | cut -d'|' -f1)
        SELECTED_INPUT=$(echo "$repo_info" | cut -d'|' -f2)
        SELECTED_PATH="$expanded_path"
        SELECTED_TYPE="local"
        return 0
    done
}

# Standard input prompt (when not in a git repo)
prompt_standard_input() {
    local input

    echo ""
    echo -e "${DIM}Enter repo (user/repo), URL, or local path (TAB for directories)${NC}"

    while true; do
        read_with_readline "Name or repo: " input
        input=$(trim "$input")

        if [[ -z "$input" ]]; then
            log_error "Input required"
            continue
        fi

        # Determine input type
        if is_url "$input"; then
            # It's a URL
            SELECTED_INPUT="$input"
            SELECTED_TYPE="url"
            return 0
        elif is_local_path "$input"; then
            # It looks like a path - validate it
            local expanded_path
            expanded_path=$(expand_path "$input")

            if [[ ! -d "$expanded_path" ]]; then
                log_error "Directory not found: $expanded_path"
                echo ""
                continue
            fi

            if ! is_git_repo "$expanded_path"; then
                log_error "Git repository not found in: $expanded_path"
                echo "Please enter a path to a directory containing a .git folder."
                echo ""
                continue
            fi

            # Get repo info from the path
            local remote_url repo_info
            remote_url=$(get_git_remote_url "$expanded_path")

            if [[ -z "$remote_url" ]]; then
                log_warning "No remote 'origin' found in repository"
                SELECTED_INPUT=""
                SELECTED_PATH="$expanded_path"
                SELECTED_TYPE="local_no_remote"
                return 0
            fi

            repo_info=$(parse_git_remote "$remote_url")
            SELECTED_HOST=$(echo "$repo_info" | cut -d'|' -f1)
            SELECTED_INPUT=$(echo "$repo_info" | cut -d'|' -f2)
            SELECTED_PATH="$expanded_path"
            SELECTED_TYPE="local"
            return 0
        else
            # Treat as repo name (user/repo)
            SELECTED_INPUT="$input"
            SELECTED_TYPE="repo"
            return 0
        fi
    done
}

# Variables set by input functions
SELECTED_INPUT=""
SELECTED_HOST=""
SELECTED_PATH=""
SELECTED_TYPE=""  # "repo", "url", "local", "local_no_remote"
