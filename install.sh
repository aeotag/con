#!/usr/bin/env bash
# ============================================================================
# con - Installation Script
# Installs all dependencies and sets up the 'con' CLI tool.
#
# Usage:
#   curl -fsSL <url>/install.sh | bash
#   OR
#   bash install.sh
#
# Supports: Linux (Arch, Debian/Ubuntu, Fedora/RHEL, openSUSE, Alpine, Void,
#            NixOS, Gentoo), macOS (Homebrew), Windows (WSL/MSYS2)
# ============================================================================

set -euo pipefail

# --- Colors ----------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# --- Helpers ---------------------------------------------------------------
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
step()    { echo -e "\n${CYAN}${BOLD}▶ $*${NC}"; }

# --- Determine script location (install_dir) ------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CON_DIR="${CON_DIR:-$SCRIPT_DIR}"

# If the script was piped (curl | bash), fall back to current dir
if [[ "$CON_DIR" == "/" ]] || [[ ! -f "$CON_DIR/main.lua" ]]; then
    if [[ -f "./main.lua" ]]; then
        CON_DIR="$(pwd)"
    else
        error "Cannot find 'main.lua'. Run this script from the con project directory."
    fi
fi

info "Install directory: ${BOLD}$CON_DIR${NC}"

# ============================================================================
# 1. DETECT OS & PACKAGE MANAGER
# ============================================================================
step "Detecting operating system..."

OS="unknown"
DISTRO="unknown"
PKG_INSTALL=""
PKG_UPDATE=""

detect_os() {
    case "$(uname -s 2>/dev/null)" in
        Linux*)
            OS="linux"
            if [[ -f /etc/os-release ]]; then
                DISTRO=$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"' | tr '[:upper:]' '[:lower:]')
            fi
            # WSL detection
            if grep -qi microsoft /proc/version 2>/dev/null; then
                info "WSL detected (running inside Windows)"
            fi
            ;;
        Darwin*)
            OS="macos"
            DISTRO="macos"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            OS="windows"
            DISTRO="msys2"
            ;;
        *)
            error "Unsupported operating system: $(uname -s)"
            ;;
    esac
}

detect_pkg_manager() {
    case "$DISTRO" in
        arch|manjaro|endeavouros|garuda|artix)
            PKG_INSTALL="sudo pacman -S --noconfirm --needed"
            PKG_UPDATE="sudo pacman -Sy"
            ;;
        debian|ubuntu|linuxmint|pop|raspbian|kali|elementary)
            PKG_INSTALL="sudo apt-get install -y"
            PKG_UPDATE="sudo apt-get update"
            ;;
        fedora|rhel|centos|rocky|alma|nobara)
            PKG_INSTALL="sudo dnf install -y"
            PKG_UPDATE="sudo dnf check-update || true"
            ;;
        opensuse*|suse|sles)
            PKG_INSTALL="sudo zypper install -y"
            PKG_UPDATE="sudo zypper refresh"
            ;;
        alpine)
            PKG_INSTALL="sudo apk add"
            PKG_UPDATE="sudo apk update"
            ;;
        void)
            PKG_INSTALL="sudo xbps-install -y"
            PKG_UPDATE="sudo xbps-install -S"
            ;;
        gentoo)
            PKG_INSTALL="sudo emerge"
            PKG_UPDATE="sudo emerge --sync"
            ;;
        nixos|nix)
            PKG_INSTALL="nix-env -iA nixpkgs."
            PKG_UPDATE=""
            ;;
        macos)
            if ! command -v brew &>/dev/null; then
                warn "Homebrew not found. Installing Homebrew first..."
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            fi
            PKG_INSTALL="brew install"
            PKG_UPDATE="brew update"
            ;;
        msys2)
            PKG_INSTALL="pacman -S --noconfirm --needed"
            PKG_UPDATE="pacman -Sy"
            ;;
        *)
            # Try to auto-detect by available commands
            if command -v pacman &>/dev/null; then
                PKG_INSTALL="sudo pacman -S --noconfirm --needed"
                PKG_UPDATE="sudo pacman -Sy"
                DISTRO="arch-like"
            elif command -v apt-get &>/dev/null; then
                PKG_INSTALL="sudo apt-get install -y"
                PKG_UPDATE="sudo apt-get update"
                DISTRO="debian-like"
            elif command -v dnf &>/dev/null; then
                PKG_INSTALL="sudo dnf install -y"
                PKG_UPDATE="sudo dnf check-update || true"
                DISTRO="fedora-like"
            elif command -v zypper &>/dev/null; then
                PKG_INSTALL="sudo zypper install -y"
                PKG_UPDATE="sudo zypper refresh"
                DISTRO="opensuse-like"
            else
                error "Could not detect package manager. Install lua, luarocks, and libyaml manually."
            fi
            ;;
    esac
}

detect_os
detect_pkg_manager
success "OS: ${BOLD}$OS${NC} | Distro: ${BOLD}$DISTRO${NC}"

# ============================================================================
# 2. INSTALL LUA
# ============================================================================
step "Checking Lua..."

install_lua() {
    if command -v lua &>/dev/null; then
        local lua_ver
        lua_ver=$(lua -v 2>&1 | grep -oP '\d+\.\d+' | head -1)
        success "Lua already installed: $(lua -v 2>&1 | head -1)"
        return 0
    fi

    info "Installing Lua 5.4..."
    if [[ -n "$PKG_UPDATE" ]]; then
        $PKG_UPDATE
    fi

    case "$DISTRO" in
        arch|manjaro|endeavouros|garuda|artix|arch-like)
            $PKG_INSTALL lua
            ;;
        debian|ubuntu|linuxmint|pop|raspbian|kali|elementary|debian-like)
            $PKG_INSTALL lua5.4
            ;;
        fedora|rhel|centos|rocky|alma|nobara|fedora-like)
            $PKG_INSTALL lua lua-devel
            ;;
        opensuse*|suse|sles|opensuse-like)
            $PKG_INSTALL lua54
            ;;
        alpine)
            $PKG_INSTALL lua5.4 lua5.4-dev
            ;;
        void)
            $PKG_INSTALL lua54
            ;;
        gentoo)
            $PKG_INSTALL dev-lang/lua:5.4
            ;;
        nixos|nix)
            ${PKG_INSTALL}lua5_4
            ;;
        macos)
            $PKG_INSTALL lua
            ;;
        msys2)
            $PKG_INSTALL mingw-w64-x86_64-lua
            ;;
        *)
            error "Don't know how to install Lua on '$DISTRO'. Install it manually."
            ;;
    esac

    if command -v lua &>/dev/null; then
        success "Lua installed: $(lua -v 2>&1 | head -1)"
    else
        # Some distros install as lua5.4
        if command -v lua5.4 &>/dev/null; then
            success "Lua installed as lua5.4: $(lua5.4 -v 2>&1 | head -1)"
            warn "You may need to create a symlink: sudo ln -sf \$(which lua5.4) /usr/local/bin/lua"
        else
            error "Lua installation failed."
        fi
    fi
}

install_lua

# ============================================================================
# 3. INSTALL LUAJIT (optional, performance)
# ============================================================================
step "Checking LuaJIT..."

install_luajit() {
    if command -v luajit &>/dev/null; then
        success "LuaJIT already installed: $(luajit -v 2>&1 | head -1)"
        return 0
    fi

    info "Installing LuaJIT..."
    case "$DISTRO" in
        arch|manjaro|endeavouros|garuda|artix|arch-like)
            $PKG_INSTALL luajit
            ;;
        debian|ubuntu|linuxmint|pop|raspbian|kali|elementary|debian-like)
            $PKG_INSTALL luajit
            ;;
        fedora|rhel|centos|rocky|alma|nobara|fedora-like)
            $PKG_INSTALL luajit
            ;;
        opensuse*|suse|sles|opensuse-like)
            $PKG_INSTALL luajit || warn "LuaJIT not available on $DISTRO, skipping."
            ;;
        alpine)
            $PKG_INSTALL luajit || warn "LuaJIT not available on Alpine, skipping."
            ;;
        void)
            $PKG_INSTALL LuaJIT
            ;;
        gentoo)
            $PKG_INSTALL dev-lang/luajit
            ;;
        nixos|nix)
            ${PKG_INSTALL}luajit || warn "LuaJIT not available via nix, skipping."
            ;;
        macos)
            $PKG_INSTALL luajit
            ;;
        msys2)
            $PKG_INSTALL mingw-w64-x86_64-luajit || warn "LuaJIT not available on MSYS2, skipping."
            ;;
        *)
            warn "Don't know how to install LuaJIT on '$DISTRO'. Skipping."
            ;;
    esac

    if command -v luajit &>/dev/null; then
        success "LuaJIT installed: $(luajit -v 2>&1 | head -1)"
    else
        warn "LuaJIT not installed (optional — Lua 5.4 will be used instead)"
    fi
}

install_luajit

# ============================================================================
# 4. INSTALL LUAROCKS
# ============================================================================
step "Checking LuaRocks..."

install_luarocks() {
    if command -v luarocks &>/dev/null; then
        success "LuaRocks already installed: $(luarocks --version 2>&1 | head -1)"
        return 0
    fi

    info "Installing LuaRocks..."
    case "$DISTRO" in
        arch|manjaro|endeavouros|garuda|artix|arch-like)
            $PKG_INSTALL luarocks
            ;;
        debian|ubuntu|linuxmint|pop|raspbian|kali|elementary|debian-like)
            $PKG_INSTALL luarocks
            ;;
        fedora|rhel|centos|rocky|alma|nobara|fedora-like)
            $PKG_INSTALL luarocks
            ;;
        opensuse*|suse|sles|opensuse-like)
            $PKG_INSTALL lua54-luarocks || $PKG_INSTALL luarocks
            ;;
        alpine)
            $PKG_INSTALL luarocks5.4 || $PKG_INSTALL luarocks
            ;;
        void)
            $PKG_INSTALL luarocks
            ;;
        gentoo)
            $PKG_INSTALL dev-lua/luarocks
            ;;
        nixos|nix)
            ${PKG_INSTALL}luarocks-nix || warn "Install luarocks manually."
            ;;
        macos)
            $PKG_INSTALL luarocks
            ;;
        msys2)
            warn "Install luarocks manually on MSYS2: https://github.com/luarocks/luarocks/wiki/Installation-instructions-for-Windows"
            ;;
        *)
            error "Don't know how to install LuaRocks on '$DISTRO'. Install it manually."
            ;;
    esac

    if command -v luarocks &>/dev/null; then
        success "LuaRocks installed: $(luarocks --version 2>&1 | head -1)"
    else
        error "LuaRocks installation failed."
    fi
}

install_luarocks

# ============================================================================
# 5. INSTALL LIBYAML (C library required by lyaml)
# ============================================================================
step "Checking libyaml (C library)..."

install_libyaml() {
    # Check if libyaml is already available
    local already_installed=false
    if ldconfig -p 2>/dev/null | grep -q libyaml; then
        already_installed=true
    elif [[ "$OS" == "macos" ]] && brew list libyaml &>/dev/null 2>&1; then
        already_installed=true
    elif pkg-config --exists yaml-0.1 2>/dev/null; then
        already_installed=true
    fi

    if $already_installed; then
        success "libyaml already installed"
        return 0
    fi

    info "Installing libyaml..."
    case "$DISTRO" in
        arch|manjaro|endeavouros|garuda|artix|arch-like)
            $PKG_INSTALL libyaml
            ;;
        debian|ubuntu|linuxmint|pop|raspbian|kali|elementary|debian-like)
            $PKG_INSTALL libyaml-dev
            ;;
        fedora|rhel|centos|rocky|alma|nobara|fedora-like)
            $PKG_INSTALL libyaml-devel
            ;;
        opensuse*|suse|sles|opensuse-like)
            $PKG_INSTALL libyaml-devel
            ;;
        alpine)
            $PKG_INSTALL yaml-dev
            ;;
        void)
            $PKG_INSTALL libyaml-devel
            ;;
        gentoo)
            $PKG_INSTALL dev-libs/libyaml
            ;;
        nixos|nix)
            ${PKG_INSTALL}libyaml
            ;;
        macos)
            $PKG_INSTALL libyaml
            ;;
        msys2)
            $PKG_INSTALL mingw-w64-x86_64-libyaml
            ;;
        *)
            warn "Don't know how to install libyaml on '$DISTRO'. lyaml may fail to build."
            ;;
    esac
    success "libyaml installed"
}

install_libyaml

# ============================================================================
# 6. INSTALL LYAML (Lua YAML library via LuaRocks)
# ============================================================================
step "Checking lyaml Lua module..."

install_lyaml() {
    # Check if lyaml is already available
    if lua -e "require('lyaml')" 2>/dev/null; then
        success "lyaml already installed"
        return 0
    fi

    info "Installing lyaml via LuaRocks..."

    # Try user-local install first (no sudo needed)
    if luarocks install --local lyaml 2>/dev/null; then
        success "lyaml installed (user-local)"
    elif luarocks install lyaml 2>/dev/null; then
        success "lyaml installed (system)"
    else
        error "Failed to install lyaml. Check that libyaml-dev and a C compiler are installed."
    fi
}

install_lyaml

# ============================================================================
# 7. INSTALL BUILD TOOLS (if missing — needed for luarocks C modules)
# ============================================================================
# This is checked implicitly by lyaml install; if it failed, we help the user.

# ============================================================================
# 8. SET UP SHELL ALIAS
# ============================================================================
step "Setting up shell alias..."

LUA_CMD="lua"
if command -v luajit &>/dev/null; then
    # LuaJIT doesn't support Lua 5.4 features, stick with lua
    LUA_CMD="lua"
fi

ALIAS_LINE="alias con='$LUA_CMD $CON_DIR/main.lua'"

setup_shell_alias() {
    local shell_name
    shell_name=$(basename "${SHELL:-/bin/bash}")
    local alias_added=false

    # Fish shell
    if [[ "$shell_name" == "fish" ]] || [[ -d "$HOME/.config/fish" ]]; then
        local fish_config="$HOME/.config/fish/config.fish"
        mkdir -p "$(dirname "$fish_config")"

        # Fish uses different alias syntax
        local fish_alias="alias con '$LUA_CMD $CON_DIR/main.lua'"

        if [[ -f "$fish_config" ]] && grep -q "alias con " "$fish_config"; then
            # Update existing alias
            sed -i "s|alias con .*|$fish_alias|" "$fish_config"
            success "Updated fish alias in $fish_config"
        else
            echo "$fish_alias" >> "$fish_config"
            success "Added fish alias to $fish_config"
        fi
        alias_added=true
    fi

    # Bash
    local bashrc="$HOME/.bashrc"
    if [[ -f "$bashrc" ]]; then
        if grep -q "alias con=" "$bashrc"; then
            sed -i "s|alias con=.*|$ALIAS_LINE|" "$bashrc"
            success "Updated bash alias in $bashrc"
        else
            echo "$ALIAS_LINE" >> "$bashrc"
            success "Added bash alias to $bashrc"
        fi
        alias_added=true
    fi

    # Zsh
    local zshrc="$HOME/.zshrc"
    if [[ -f "$zshrc" ]]; then
        if grep -q "alias con=" "$zshrc"; then
            sed -i "s|alias con=.*|$ALIAS_LINE|" "$zshrc"
            success "Updated zsh alias in $zshrc"
        else
            echo "$ALIAS_LINE" >> "$zshrc"
            success "Added zsh alias to $zshrc"
        fi
        alias_added=true
    fi

    if ! $alias_added; then
        warn "Could not detect shell config. Add this to your shell profile manually:"
        echo "  $ALIAS_LINE"
    fi
}

setup_shell_alias

# ============================================================================
# 9. INITIALIZE CON CONFIG
# ============================================================================
step "Initializing con configuration..."

$LUA_CMD "$CON_DIR/main.lua" init

# ============================================================================
# 10. SUMMARY
# ============================================================================
echo ""
echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  con installed successfully!${NC}"
echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BOLD}Version:${NC}     $($LUA_CMD "$CON_DIR/main.lua" version 2>/dev/null || echo 'unknown')"
echo -e "  ${BOLD}Install dir:${NC} $CON_DIR"
echo -e "  ${BOLD}Config dir:${NC}  ~/.config/con/"
echo ""
echo -e "  ${BOLD}Installed:${NC}"
echo -e "    ✅ Lua          $(lua -v 2>&1 | head -1)"
if command -v luajit &>/dev/null; then
echo -e "    ✅ LuaJIT       $(luajit -v 2>&1 | head -1)"
else
echo -e "    ⚪ LuaJIT       (not installed — optional)"
fi
echo -e "    ✅ LuaRocks     $(luarocks --version 2>&1 | head -1)"
echo -e "    ✅ lyaml        (Lua YAML parser)"
echo ""
echo -e "  ${BOLD}Next steps:${NC}"
echo -e "    1. Restart your shell or run: ${CYAN}source ~/.config/fish/config.fish${NC}"
echo -e "    2. Try: ${CYAN}con help${NC}"
echo -e "    3. Add a connection: ${CYAN}con --name myserver user@10.0.0.1${NC}"
echo ""
