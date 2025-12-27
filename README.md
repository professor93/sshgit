# sshgit

SSH Key Manager for Git Repositories

```
                 __          _ __
   __________  / /_  ____ _(_) /_
  / ___/ ___/ / __ \/ __ `/ / __/
 (__  |__  ) / / / / /_/ / / /_
/____/____/ /_/ /_/\__, /_/\__/
                  /____/
```

**sshgit** simplifies SSH key management for Git. Generate keys, configure SSH, test connections, and manage multiple repositories — all in one tool.

## Installation

```bash
# Download latest release
curl -fsSL https://github.com/professor93/sshgit/releases/latest/download/sshgit -o sshgit
chmod +x sshgit
sudo mv sshgit /usr/local/bin/

# Enable shell completion (optional)
echo 'eval "$(sshgit completion bash)"' >> ~/.bashrc
```

<details>
<summary><b>Other installation methods</b></summary>

### From Source
```bash
git clone https://github.com/professor93/sshgit.git
cd sshgit
./build.sh
sudo mv sshgit /usr/local/bin/
```

### Windows (Git Bash)
```bash
curl -fsSL https://github.com/professor93/sshgit/releases/latest/download/sshgit -o ~/bin/sshgit
chmod +x ~/bin/sshgit
```

### Shell Completion
```bash
# Bash
echo 'eval "$(sshgit completion bash)"' >> ~/.bashrc

# Zsh
echo 'eval "$(sshgit completion zsh)"' >> ~/.zshrc

# Fish
echo 'sshgit completion fish | source' >> ~/.config/fish/config.fish

# PowerShell
echo 'Invoke-Expression (sshgit completion powershell)' >> $PROFILE
```
</details>

---

## Quick Start

### Create a Key for a Repository

```bash
# Interactive mode
sshgit

# Or specify the repository directly
sshgit user/repo
```

This will:
1. Generate an SSH key for the repository
2. Show you the public key
3. Offer to add it to SSH config
4. Copy the key to clipboard
5. Open the deploy key settings page

### Common Workflows

```bash
# Create key with all options at once
sshgit user/repo -c -P --clipboard -o
#                 │  │  │           └─ Open browser to add deploy key
#                 │  │  └───────────── Copy public key to clipboard
#                 │  └──────────────── No passphrase
#                 └─────────────────── Auto-add to SSH config

# List your managed keys
sshgit list

# Test a key connection
sshgit test github-user__repo

# Switch a repository to use a specific key
sshgit use github-user__repo

# Run diagnostics
sshgit doctor
```

---

## Commands

### Key Management

| Command | Description |
|---------|-------------|
| `sshgit` | Interactive key creation |
| `sshgit <repo>` | Create key for repository |
| `sshgit list` | List all managed keys |
| `sshgit test <key>` | Test SSH connection |
| `sshgit use <key>` | Use key for current repo |
| `sshgit remove <key>` | Remove a key |
| `sshgit select` | Interactive key picker |
| `sshgit import <path>` | Import existing key |

### Security & Maintenance

| Command | Description |
|---------|-------------|
| `sshgit rotate <key>` | Rotate key (backup + new) |
| `sshgit expire <key> [days]` | Set expiry reminder |
| `sshgit check-expiry` | Check all key expiry status |
| `sshgit doctor` | Health check & diagnostics |
| `sshgit doctor --fix` | Auto-fix issues |

### SSH Agent

| Command | Description |
|---------|-------------|
| `sshgit agent-add <key>` | Add key to agent |
| `sshgit agent-remove <key>` | Remove from agent |
| `sshgit agent-list` | List keys in agent |
| `sshgit agent-add-all` | Add all keys to agent |

### Backup & Restore

| Command | Description |
|---------|-------------|
| `sshgit backup` | Backup all keys |
| `sshgit backup --encrypt` | Encrypted backup (GPG) |
| `sshgit restore <path>` | Restore from backup |

### Team & Profiles

| Command | Description |
|---------|-------------|
| `sshgit profile create <name>` | Save key settings as profile |
| `sshgit profile list` | List profiles |
| `sshgit team init` | Initialize team config |
| `sshgit team sync` | Sync keys from team config |

### Deploy Keys (API)

| Command | Description |
|---------|-------------|
| `sshgit deploy-key push <key>` | Push key via GitHub/GitLab API |
| `sshgit deploy-key list` | List deploy keys |
| `sshgit deploy-key remove <id>` | Remove deploy key |

### Other

| Command | Description |
|---------|-------------|
| `sshgit remotes` | Show remotes & their keys |
| `sshgit hook install` | Install pre-push hook |
| `sshgit config` | Edit configuration |
| `sshgit help` | Show help |

---

## Options

```
-c                  Auto-add to SSH config
-t, --type TYPE     Key type: ed25519 (default), rsa, ecdsa
-e, --email EMAIL   Email for key comment
-p, --passphrase    Prompt for passphrase
-P, --no-passphrase No passphrase
-o, --open          Open deploy key URL in browser
--clipboard         Copy public key to clipboard
--profile NAME      Use saved profile
-q, --quiet         Minimal output
```

---

## Examples

### Key Rotation
```bash
# Rotate a key (automatically backs up the old one)
sshgit rotate github-user__repo

# Set expiry reminder (default: 90 days)
sshgit expire github-user__repo

# Check expiry status
sshgit check-expiry
```

### Profiles
```bash
# Create a reusable profile
sshgit profile create work

# Use it when creating keys
sshgit user/repo --profile work
```

### Team Sync
```bash
# Initialize team config in your repo
sshgit team init

# Team members sync their keys
sshgit team sync
```

### Encrypted Backup
```bash
# Create encrypted backup
sshgit backup --encrypt

# Restore
sshgit restore --decrypt ~/sshgit-backup.tar.gz.gpg
```

---

## How It Works

### Key Naming

sshgit creates consistent key names based on repository:

| Input | Key Name | File |
|-------|----------|------|
| `user/repo` | `github-user__repo` | `~/.ssh/github-user__repo` |
| `gitlab.com/org/project` | `gitlab-org__project` | `~/.ssh/gitlab-org__project` |

### SSH Config

When using `-c`, sshgit adds entries like:

```
# generated by sshgit
Host github-user__repo
    HostName github.com
    User git
    IdentityFile ~/.ssh/github-user__repo
    IdentitiesOnly yes
```

### Smart Input

When run in a git repository, sshgit detects it and offers options:

```
Current directory is a git repository:
  Repository: user/my-project
  Host: github.com

Options:
  1) Use current repository
  2) Enter a different repo
  3) Enter a local path
  4) Enter a remote URL
```

---

## Configuration

Config file: `~/.sshgitrc`

```bash
sshgit config  # View and edit
```

| Setting | Default | Description |
|---------|---------|-------------|
| `DEFAULT_EMAIL` | git config | Email for key comments |
| `DEFAULT_TYPE` | `ed25519` | Default key type |
| `AUTO_CONFIG` | `false` | Auto-add to SSH config |
| `AUTO_CLIPBOARD` | `false` | Auto-copy to clipboard |
| `AUTO_OPEN_BROWSER` | `false` | Auto-open browser |

---

## Platform Support

| Platform | Status |
|----------|--------|
| Linux | Full support |
| macOS | Full support |
| Windows (Git Bash) | Full support |
| Windows (WSL) | Full support |
| Windows (MSYS2/Cygwin) | Full support |

---

## Development

### Project Structure

```
sshgit/
├── src/
│   ├── lib/           # Core modules (13 files)
│   └── commands/      # Command implementations (19 files)
├── .github/workflows/ # CI/CD
├── build.sh           # Build script
└── README.md
```

### Building

```bash
./build.sh                    # Build with default version
./build.sh --version 1.2.0    # Build with specific version
```

### Releases

When a GitHub release is published:
1. GitHub Actions builds the single-file executable
2. Version is injected from the release tag
3. Executable + checksums are uploaded as release assets

---

## License

MIT

## Author

[professor93](https://github.com/professor93)
