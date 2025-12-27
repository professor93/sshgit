#!/bin/bash
#
# sshgit - Shell Completion Generation
#

generate_bash_completion() {
    cat << 'BASH_COMPLETION'
_sshgit_completions() {
    local cur prev commands
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    commands="list hosts test use remove backup restore import config help version completion rotate expire check-expiry agent-add agent-remove agent-list agent-add-all agent-remove-all remotes setup-remotes profile team select deploy-key doctor hook"

    if [[ ${COMP_CWORD} -eq 1 ]]; then
        COMPREPLY=($(compgen -W "$commands" -- "$cur"))
        return 0
    fi

    case "${COMP_WORDS[1]}" in
        test|use|remove|rotate|expire|agent-add|agent-remove)
            local keys=$(sshgit list 2>/dev/null | awk 'NR>3 && NF>0 {print $1}')
            COMPREPLY=($(compgen -W "$keys" -- "$cur"))
            ;;
        backup|import|restore)
            return 0
            ;;
        completion)
            COMPREPLY=($(compgen -W "bash zsh fish powershell" -- "$cur"))
            ;;
        profile)
            COMPREPLY=($(compgen -W "list create show delete" -- "$cur"))
            ;;
        team)
            COMPREPLY=($(compgen -W "init sync add info" -- "$cur"))
            ;;
        deploy-key)
            COMPREPLY=($(compgen -W "push list remove" -- "$cur"))
            ;;
        hook)
            COMPREPLY=($(compgen -W "install uninstall status" -- "$cur"))
            ;;
        select)
            COMPREPLY=($(compgen -W "use test copy show agent remove" -- "$cur"))
            ;;
    esac
}
complete -o filenames -o default -F _sshgit_completions sshgit
BASH_COMPLETION
}

generate_zsh_completion() {
    cat << 'ZSH_COMPLETION'
#compdef sshgit

_sshgit() {
    local -a commands
    commands=(
        'list:List all sshgit-managed SSH keys'
        'hosts:Show all sshgit-managed hosts'
        'test:Test SSH connection for a key'
        'use:Set SSH key for current git repository'
        'remove:Remove a key and its SSH config entry'
        'backup:Backup all sshgit-managed keys'
        'restore:Restore from backup'
        'import:Import an existing SSH key'
        'config:View and edit configuration'
        'help:Show help message'
        'version:Show version'
        'completion:Generate shell completion'
        'rotate:Rotate a key (backup old, create new)'
        'expire:Set expiry reminder for a key'
        'check-expiry:Show expiry status of all keys'
        'agent-add:Add key to ssh-agent'
        'agent-remove:Remove key from ssh-agent'
        'agent-list:List keys in ssh-agent'
        'agent-add-all:Add all managed keys to agent'
        'agent-remove-all:Remove all managed keys from agent'
        'remotes:Show remotes and their SSH keys'
        'setup-remotes:Configure remotes with SSH keys'
        'profile:Manage key profiles'
        'team:Team sync features'
        'select:Interactive key selector'
        'deploy-key:Deploy key API management'
        'doctor:Run health check and diagnostics'
        'hook:Git hook management'
    )

    _arguments -C \
        '1: :->command' \
        '*: :->args'

    case $state in
        command)
            _describe -t commands 'sshgit commands' commands
            ;;
        args)
            case $words[2] in
                test|use|remove|rotate|expire|agent-add|agent-remove)
                    local keys=($(sshgit list 2>/dev/null | awk 'NR>3 && NF>0 {print $1}'))
                    _describe -t keys 'ssh keys' keys
                    ;;
                backup|import|restore)
                    _files
                    ;;
                completion)
                    _values 'shell' bash zsh fish powershell
                    ;;
                profile)
                    _values 'profile command' list create show delete
                    ;;
                team)
                    _values 'team command' init sync add info
                    ;;
                deploy-key)
                    _values 'deploy-key command' push list remove
                    ;;
                hook)
                    _values 'hook command' install uninstall status
                    ;;
            esac
            ;;
    esac
}

_sshgit "$@"
ZSH_COMPLETION
}

generate_fish_completion() {
    cat << 'FISH_COMPLETION'
# Fish completion for sshgit

complete -c sshgit -f

# Commands
complete -c sshgit -n "__fish_use_subcommand" -a "list" -d "List all sshgit-managed SSH keys"
complete -c sshgit -n "__fish_use_subcommand" -a "hosts" -d "Show all sshgit-managed hosts"
complete -c sshgit -n "__fish_use_subcommand" -a "test" -d "Test SSH connection for a key"
complete -c sshgit -n "__fish_use_subcommand" -a "use" -d "Set SSH key for current git repository"
complete -c sshgit -n "__fish_use_subcommand" -a "remove" -d "Remove a key and its SSH config entry"
complete -c sshgit -n "__fish_use_subcommand" -a "backup" -d "Backup all sshgit-managed keys"
complete -c sshgit -n "__fish_use_subcommand" -a "restore" -d "Restore from backup"
complete -c sshgit -n "__fish_use_subcommand" -a "import" -d "Import an existing SSH key"
complete -c sshgit -n "__fish_use_subcommand" -a "config" -d "View and edit configuration"
complete -c sshgit -n "__fish_use_subcommand" -a "help" -d "Show help message"
complete -c sshgit -n "__fish_use_subcommand" -a "version" -d "Show version"
complete -c sshgit -n "__fish_use_subcommand" -a "completion" -d "Generate shell completion"
complete -c sshgit -n "__fish_use_subcommand" -a "rotate" -d "Rotate a key (backup old, create new)"
complete -c sshgit -n "__fish_use_subcommand" -a "expire" -d "Set expiry reminder for a key"
complete -c sshgit -n "__fish_use_subcommand" -a "check-expiry" -d "Show expiry status of all keys"
complete -c sshgit -n "__fish_use_subcommand" -a "agent-add" -d "Add key to ssh-agent"
complete -c sshgit -n "__fish_use_subcommand" -a "agent-remove" -d "Remove key from ssh-agent"
complete -c sshgit -n "__fish_use_subcommand" -a "agent-list" -d "List keys in ssh-agent"
complete -c sshgit -n "__fish_use_subcommand" -a "agent-add-all" -d "Add all managed keys to agent"
complete -c sshgit -n "__fish_use_subcommand" -a "agent-remove-all" -d "Remove all managed keys from agent"
complete -c sshgit -n "__fish_use_subcommand" -a "remotes" -d "Show remotes and their SSH keys"
complete -c sshgit -n "__fish_use_subcommand" -a "setup-remotes" -d "Configure remotes with SSH keys"
complete -c sshgit -n "__fish_use_subcommand" -a "profile" -d "Manage key profiles"
complete -c sshgit -n "__fish_use_subcommand" -a "team" -d "Team sync features"
complete -c sshgit -n "__fish_use_subcommand" -a "select" -d "Interactive key selector"
complete -c sshgit -n "__fish_use_subcommand" -a "deploy-key" -d "Deploy key API management"
complete -c sshgit -n "__fish_use_subcommand" -a "doctor" -d "Run health check and diagnostics"
complete -c sshgit -n "__fish_use_subcommand" -a "hook" -d "Git hook management"

# Options
complete -c sshgit -s h -l help -d "Show help message"
complete -c sshgit -s v -l version -d "Show version"
complete -c sshgit -s c -d "Auto-add to SSH config"
complete -c sshgit -s t -l type -x -d "Key type (ed25519, rsa, ecdsa)"
complete -c sshgit -s e -l email -x -d "Custom email for key comment"
complete -c sshgit -s p -l passphrase -d "Prompt for passphrase"
complete -c sshgit -s P -l no-passphrase -d "Generate key without passphrase"
complete -c sshgit -s o -l open -d "Open deploy key URL in browser"
complete -c sshgit -l clipboard -d "Copy public key to clipboard"
complete -c sshgit -l profile -x -d "Use a saved profile"
complete -c sshgit -s q -l quiet -d "Quiet mode"

# Completions for subcommands
complete -c sshgit -n "__fish_seen_subcommand_from test use remove rotate expire agent-add agent-remove" -xa "(sshgit list 2>/dev/null | awk 'NR>3 && NF>0 {print \$1}')"
complete -c sshgit -n "__fish_seen_subcommand_from backup import restore" -F
complete -c sshgit -n "__fish_seen_subcommand_from completion" -xa "bash zsh fish powershell"
complete -c sshgit -n "__fish_seen_subcommand_from profile" -xa "list create show delete"
complete -c sshgit -n "__fish_seen_subcommand_from team" -xa "init sync add info"
complete -c sshgit -n "__fish_seen_subcommand_from deploy-key" -xa "push list remove"
complete -c sshgit -n "__fish_seen_subcommand_from hook" -xa "install uninstall status"
FISH_COMPLETION
}

generate_powershell_completion() {
    cat << 'PWSH_COMPLETION'
# PowerShell completion for sshgit

Register-ArgumentCompleter -CommandName sshgit -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $commands = @(
        @{Name='list'; Description='List all sshgit-managed SSH keys'}
        @{Name='hosts'; Description='Show all sshgit-managed hosts'}
        @{Name='test'; Description='Test SSH connection for a key'}
        @{Name='use'; Description='Set SSH key for current git repository'}
        @{Name='remove'; Description='Remove a key and its SSH config entry'}
        @{Name='backup'; Description='Backup all sshgit-managed keys'}
        @{Name='restore'; Description='Restore from backup'}
        @{Name='import'; Description='Import an existing SSH key'}
        @{Name='config'; Description='View and edit configuration'}
        @{Name='help'; Description='Show help message'}
        @{Name='version'; Description='Show version'}
        @{Name='completion'; Description='Generate shell completion'}
        @{Name='rotate'; Description='Rotate a key (backup old, create new)'}
        @{Name='expire'; Description='Set expiry reminder for a key'}
        @{Name='check-expiry'; Description='Show expiry status of all keys'}
        @{Name='agent-add'; Description='Add key to ssh-agent'}
        @{Name='agent-remove'; Description='Remove key from ssh-agent'}
        @{Name='agent-list'; Description='List keys in ssh-agent'}
        @{Name='agent-add-all'; Description='Add all managed keys to agent'}
        @{Name='agent-remove-all'; Description='Remove all managed keys from agent'}
        @{Name='remotes'; Description='Show remotes and their SSH keys'}
        @{Name='setup-remotes'; Description='Configure remotes with SSH keys'}
        @{Name='profile'; Description='Manage key profiles'}
        @{Name='team'; Description='Team sync features'}
        @{Name='select'; Description='Interactive key selector'}
        @{Name='deploy-key'; Description='Deploy key API management'}
        @{Name='doctor'; Description='Run health check and diagnostics'}
        @{Name='hook'; Description='Git hook management'}
    )

    $commands | Where-Object { $_.Name -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_.Name, $_.Name, 'ParameterValue', $_.Description)
    }
}
PWSH_COMPLETION
}

cmd_completion() {
    local shell="${1:-bash}"

    case "$shell" in
        bash)
            generate_bash_completion
            ;;
        zsh)
            generate_zsh_completion
            ;;
        fish)
            generate_fish_completion
            ;;
        powershell|pwsh)
            generate_powershell_completion
            ;;
        *)
            log_error "Unknown shell: $shell (supported: bash, zsh, fish, powershell)"
            return 1
            ;;
    esac

    echo ""
    echo "# Add to your shell config:"
    case "$shell" in
        bash) echo "# eval \"\$(sshgit completion bash)\"" ;;
        zsh) echo "# eval \"\$(sshgit completion zsh)\"" ;;
        fish) echo "# sshgit completion fish | source" ;;
        powershell|pwsh) echo "# Invoke-Expression (sshgit completion powershell)" ;;
    esac
}
