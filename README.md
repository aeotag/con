# con

A unified CLI tool for managing SSH, Telnet, and AWS Secure Tunnel connections, VPN control, and batch remote command execution (oneshots).

Written in Lua 5.4. Works on Linux, macOS, and Windows.

## Installation

### Automatic (recommended)

Clone the repo and run the install script. It installs Lua, LuaRocks, LuaJIT, libyaml, and the `lyaml` Lua module, then sets up the shell alias.

```bash
git clone https://github.com/aeotag/con.git
cd con
bash install.sh
```

**Windows (PowerShell as Administrator):**

```powershell
git clone https://github.com/aeotag/con.git
cd con
.\install.ps1
```

**Supported systems:**

| OS | Package Managers |
|----|-----------------|
| **Linux** | pacman (Arch/Manjaro), apt (Debian/Ubuntu), dnf (Fedora/RHEL), zypper (openSUSE), apk (Alpine), xbps (Void), emerge (Gentoo), nix (NixOS) |
| **macOS** | Homebrew |
| **Windows** | Chocolatey, Scoop |

### Manual

```bash
# 1. Install Lua 5.4 and LuaRocks via your package manager
# 2. Install lyaml
luarocks install --local lyaml

# 3. Set up the alias (fish shell)
alias con 'lua ~/repos/con/main.lua'

# 4. Initialize config files
con init
```

## Quick Start

```bash
# Add a connection
con --name stage9 --group stage pi@10.1.40.209

# Connect!
con stage9
```

## Features

| Feature | Description |
|---------|-------------|
| **Connections** | SSH, Telnet, AWS Secure Tunnel (SSM/EC2 IC) |
| **VPN** | Detect, activate, deactivate system VPNs (nmcli/scutil/PowerShell) |
| **Oneshots** | Run batch commands on multiple devices, parallel or sequential |
| **Verification** | Analyze oneshot logs with regex, tail, and pass/fail checks |
| **AWS** | SSO login, CodeArtifact authentication |
| **Multi-Language** | English, German, Finnish — auto-detects system language |
| **Multi-OS** | Linux (all distros), macOS, Windows |

## Usage

```
con [command] [options]

Commands:
  <name>                                  Connect to saved device
  show [--group <group> | --all]          Show saved connections
  --name <name> <user@ip>                 Quick-add and connect
  --name <name> --group <g> <user@ip>     Quick-add to group
  --modify --group <old> <new>            Rename a group
  --modify --name <old> <new>             Rename a connection
  --modify --move <name> <group>          Move connection to group
  --del group <group>                     Delete a group
  --del name <name>                       Delete a connection
  vpn [show|up|down|status]               VPN management
  ons <name> [options]                    Run a oneshot
  aws [sso|codeartifact] [options]        AWS operations
  config lang <en|de|fi|auto>             Set language
  init                                    Initialize config
  help                                    Show help

Options:
  --lang <code>                           Override language for this command
```

## Configuration

All configs are stored in `~/.config/con/`:

| File | Purpose |
|------|---------|
| `connection.yaml` | Devices, groups, addresses, VPN mappings |
| `vpn.yaml` | Friendly VPN name → system VPN name mappings |
| `oneshot.yaml` | Batch command definitions |
| `aws.yaml` | SSO profiles, CodeArtifact repos |
| `settings.yaml` | Language, defaults |
| `.secrets` | SSH key passwords, tool install state |

### Connection Example

```yaml
stage:
  stage9:
    protocol: ssh
    user: pi
    key: id_ed25519
    addresses:
      - ip: 10.1.40.209
        network: local
      - ip: 10.8.0.2
        vpn: office-wg
        type: wireguard
      - ip: 172.16.0.5
        vpn: company-ovpn
        type: openvpn
```

### VPN Example

```yaml
mappings:
  office-wg:
    type: wireguard
    system_name: "wg-office"
  company-ovpn:
    type: openvpn
    system_name: "OpenVPN-Company"
```

### Oneshot Example

```yaml
run-tests:
  group: stage
  connections: [stage9, stage10]
  vpn: office-wg
  parallel: true
  cmd: "cd /var/tests && pytest --tb=short"
  variables:
    test_suite: integration
  verify:
    search: "AssertionError"
    show_after_match: true
    tail: 15
    expect: "passed"
```

### Oneshot Verification Output

```
Verification Results:
──────────────────────────────────────────────────
✅ stage9  — All checks passed
✅ stage10 — All checks passed
❌ stage11 — Check failed
   Error details:
   E       AssertionError: Average latency 41.02 ms exceeded threshold
   E         Highest latency: 66.41 ms
   E       assert 41.02 <= 40.0
──────────────────────────────────────────────────
❌ 1 of 3 device(s) failed.
```

## VPN Commands

```bash
con vpn show                 # List all VPNs with status
con vpn up office-wg         # Activate a VPN
con vpn down office-wg       # Deactivate a VPN
con vpn down --all           # Kill all VPNs
con vpn status               # Show active VPN(s)
```

## AWS Commands

```bash
con aws sso login                       # Interactive SSO login
con aws sso login --profile prod-sso    # Login with specific profile
con aws sso show                        # List configured profiles
con aws codeartifact login              # Interactive CodeArtifact auth
con aws codeartifact login --repo pypi  # Auth specific repo
con aws codeartifact show               # List configured repos
```

## Oneshot Commands

```bash
con ons run-tests                         # Run saved oneshot
con ons run-tests --tail 15               # Override: show last 15 lines
con ons run-tests --search "Error"        # Override: search for pattern
con ons run-tests --cmd "uptime"          # Override: different command
con ons run-tests --parallel              # Force parallel execution
con ons run-tests --sequential            # Force sequential execution
```

### Oneshot Variables

Commands support `{{variable}}` placeholders:

| Variable | Resolved to |
|----------|-------------|
| `{{hostname}}` | Device name |
| `{{ip}}` | Target IP |
| `{{date}}` | Current date (YYYY-MM-DD) |
| `{{group}}` | Group name |
| `{{user}}` | SSH username |
| Custom | Defined in `variables:` section |

## Project Structure

```
con/
├── main.lua                          # CLI router
├── config.lua                        # Core configuration
├── configs/                          # Example YAML configs
│   ├── connection.yaml
│   ├── vpn.yaml
│   ├── oneshot.yaml
│   └── aws.yaml
├── language/                         # i18n strings
│   ├── en.yaml
│   ├── de.yaml
│   └── fi.yaml
└── shared/
    ├── manpages.lua                  # Help display
    ├── os/
    │   ├── detect.lua                # OS/distro detection
    │   └── packages.lua              # Package manager detection
    ├── config/
    │   ├── handler.lua               # YAML load/save/init
    │   └── edit.lua                  # CRUD for connections/groups
    ├── lang/
    │   └── handler.lua               # i18n with auto-detect
    ├── secrets/
    │   └── handler.lua               # SSH key passwords
    ├── vpn/
    │   ├── detector.lua              # OS-specific VPN detection
    │   └── handler.lua               # VPN commands + workflow
    ├── connection/
    │   ├── handler.lua               # Connect workflow orchestrator
    │   ├── ssh.lua                   # SSH connection module
    │   ├── telnet.lua                # Telnet connection module
    │   └── tunnel.lua                # AWS Secure Tunnel module
    ├── oneshot/
    │   ├── handler.lua               # Oneshot execution
    │   └── verify.lua                # Log verification/regex
    └── aws/
        ├── sso.lua                   # AWS SSO login
        └── codeartifact.lua          # CodeArtifact auth
```

## Requirements

- **Lua 5.4** with `lyaml` (`luarocks install lyaml`)
- **Linux**: `nmcli` (NetworkManager) for VPN management
- **macOS**: `scutil`, `networksetup` (built-in), `brew` for packages
- **Windows**: PowerShell, `rasdial` (built-in), `choco` for packages
- **AWS** (optional): AWS CLI v2, SSM Session Manager Plugin

## License

Private project.
