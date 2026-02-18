-- ============================================================================
-- con - OS Detection
-- shared/os/detect.lua
-- ============================================================================

local M = {}

--- Detect the current operating system.
--- @return string "linux"|"macos"|"windows"|"bsd"|"unknown"
function M.detect_os()
    -- LuaJIT shortcut
    if jit and jit.os then
        local os_name = jit.os:lower()
        if os_name == "osx" then return "macos" end
        return os_name
    end

    local sep = package.config:sub(1, 1)
    if sep == "\\" then return "windows" end

    local pipe = io.popen("uname -s 2>/dev/null")
    if pipe then
        local osname = pipe:read("*l")
        pipe:close()
        if osname then
            osname = osname:lower()
            if osname:find("linux")  then return "linux"   end
            if osname:find("darwin") then return "macos"   end
            if osname:find("bsd")    then return "bsd"     end
            if osname:find("mingw") or osname:find("msys") then return "windows" end
        end
    end
    return "unknown"
end

--- Detect the Linux distribution (if on Linux).
--- @return string|nil distro name (e.g. "arch", "debian", "ubuntu", "fedora", "opensuse", etc.)
function M.detect_linux_distro()
    local f = io.open("/etc/os-release", "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()

    local id = content:match("^ID=(.-)%s*$") or content:match("\nID=(.-)%s*\n")
    if id then
        return id:gsub('"', ''):lower()
    end
    return nil
end

--- Check if WSL is available (Windows).
--- @return boolean
function M.is_wsl()
    local f = io.open("/proc/version", "r")
    if f then
        local content = f:read("*a")
        f:close()
        if content:lower():find("microsoft") then return true end
    end
    return false
end

--- Detect the system language (LANG env variable).
--- @return string two-letter language code (e.g. "en", "de", "fi")
function M.detect_system_language()
    local lang = os.getenv("LANG") or os.getenv("LC_ALL") or os.getenv("LC_MESSAGES") or ""
    local code = lang:match("^(%a%a)")
    if code then return code:lower() end
    return "en"
end

--- Get the current username.
--- @return string
function M.get_username()
    return os.getenv("USER") or os.getenv("USERNAME") or "unknown"
end

--- Get the home directory.
--- @return string
function M.get_home()
    return os.getenv("HOME") or os.getenv("USERPROFILE") or "~"
end

return M
