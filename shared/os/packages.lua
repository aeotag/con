-- ============================================================================
-- con - Package Manager Detection & Tool Installation
-- shared/os/packages.lua
-- ============================================================================

local osdetect = require("shared.os.detect")

local M = {}

-- Package manager commands per distro/OS
local PACKAGE_MANAGERS = {
    -- Linux distros
    arch     = { install = "sudo pacman -S --noconfirm",   check = "pacman -Qi" },
    manjaro  = { install = "sudo pacman -S --noconfirm",   check = "pacman -Qi" },
    endeavouros = { install = "sudo pacman -S --noconfirm", check = "pacman -Qi" },
    debian   = { install = "sudo apt-get install -y",      check = "dpkg -s" },
    ubuntu   = { install = "sudo apt-get install -y",      check = "dpkg -s" },
    linuxmint = { install = "sudo apt-get install -y",     check = "dpkg -s" },
    pop      = { install = "sudo apt-get install -y",      check = "dpkg -s" },
    fedora   = { install = "sudo dnf install -y",          check = "rpm -qi" },
    rhel     = { install = "sudo dnf install -y",          check = "rpm -qi" },
    centos   = { install = "sudo dnf install -y",          check = "rpm -qi" },
    rocky    = { install = "sudo dnf install -y",          check = "rpm -qi" },
    alma     = { install = "sudo dnf install -y",          check = "rpm -qi" },
    opensuse = { install = "sudo zypper install -y",       check = "rpm -qi" },
    ["opensuse-leap"]       = { install = "sudo zypper install -y", check = "rpm -qi" },
    ["opensuse-tumbleweed"] = { install = "sudo zypper install -y", check = "rpm -qi" },
    alpine   = { install = "sudo apk add",                 check = "apk info -e" },
    void     = { install = "sudo xbps-install -y",         check = "xbps-query" },
    gentoo   = { install = "sudo emerge",                  check = "equery list" },
    nixos    = { install = "nix-env -iA nixpkgs.",         check = "nix-env -q" },

    -- macOS
    macos    = { install = "brew install",                 check = "brew list" },

    -- Windows (choco or winget)
    windows  = { install = "choco install -y",             check = "choco list --local-only" },
}

--- Detect the appropriate package manager for this system.
--- @return table|nil  { install = "...", check = "..." }
function M.detect_package_manager()
    local os_name = osdetect.detect_os()

    if os_name == "linux" then
        local distro = osdetect.detect_linux_distro()
        if distro and PACKAGE_MANAGERS[distro] then
            return PACKAGE_MANAGERS[distro], distro
        end
        -- Fallback: try to find a known binary
        if os.execute("which pacman > /dev/null 2>&1") == true or os.execute("which pacman > /dev/null 2>&1") == 0 then
            return PACKAGE_MANAGERS.arch, "arch-like"
        elseif os.execute("which apt-get > /dev/null 2>&1") == true or os.execute("which apt-get > /dev/null 2>&1") == 0 then
            return PACKAGE_MANAGERS.debian, "debian-like"
        elseif os.execute("which dnf > /dev/null 2>&1") == true or os.execute("which dnf > /dev/null 2>&1") == 0 then
            return PACKAGE_MANAGERS.fedora, "fedora-like"
        end
        return nil, "unknown-linux"
    elseif os_name == "macos" then
        return PACKAGE_MANAGERS.macos, "macos"
    elseif os_name == "windows" then
        return PACKAGE_MANAGERS.windows, "windows"
    end

    return nil, os_name
end

--- Check if a command-line tool is installed.
--- @param tool string  The tool name (e.g. "sshpass", "nmcli")
--- @return boolean
function M.is_tool_installed(tool)
    local os_name = osdetect.detect_os()
    local cmd
    if os_name == "windows" then
        cmd = "where " .. tool .. " > NUL 2>&1"
    else
        cmd = "which " .. tool .. " > /dev/null 2>&1"
    end
    local ok = os.execute(cmd)
    return ok == true or ok == 0
end

--- Prompt the user to install a tool, then install it.
--- @param tool string  The tool name
--- @param lang_handler table|nil  Language handler for translated prompts
--- @return boolean  true if tool is now available
function M.prompt_install(tool, lang_handler)
    if M.is_tool_installed(tool) then return true end

    local msg = "Tool '" .. tool .. "' is required but not installed. Install now? (y/n): "
    io.write(msg)
    local answer = io.read("*l")
    if answer ~= "y" and answer ~= "Y" then
        return false
    end

    local pm, distro = M.detect_package_manager()
    if not pm then
        print("Could not detect package manager. Please install '" .. tool .. "' manually.")
        return false
    end

    print("Installing '" .. tool .. "' via " .. distro .. "...")
    local cmd = pm.install .. " " .. tool
    os.execute(cmd)

    return M.is_tool_installed(tool)
end

return M
