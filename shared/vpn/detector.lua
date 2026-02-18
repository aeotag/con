-- ============================================================================
-- con - VPN Detector (OS-specific VPN discovery and status)
-- shared/vpn/detector.lua
-- ============================================================================

local osdetect = require("shared.os.detect")

local M = {}

-- ===========================================================================
-- LINUX (nmcli)
-- ===========================================================================

local function linux_list_vpns()
    local vpns = {}
    local pipe = io.popen("nmcli -t -f NAME,TYPE connection show 2>/dev/null")
    if not pipe then return vpns end
    for line in pipe:lines() do
        local name, ctype = line:match("^(.-):([%w%-]+)$")
        if ctype == "vpn" or ctype == "wireguard" then
            table.insert(vpns, { name = name, type = ctype, system_name = name })
        end
    end
    pipe:close()
    return vpns
end

local function linux_get_active_vpns()
    local active = {}
    local pipe = io.popen("nmcli -t -f NAME,TYPE connection show --active 2>/dev/null")
    if not pipe then return active end
    for line in pipe:lines() do
        local name, ctype = line:match("^(.-):([%w%-]+)$")
        if ctype == "vpn" or ctype == "wireguard" then
            table.insert(active, { name = name, type = ctype })
        end
    end
    pipe:close()
    return active
end

local function linux_is_vpn_active(vpn_name)
    local cmd = "nmcli -t -f NAME connection show --active 2>/dev/null | grep -q '^" .. vpn_name .. "$'"
    local ok = os.execute(cmd)
    return ok == true or ok == 0
end

local function linux_activate_vpn(vpn_name)
    return os.execute("nmcli connection up '" .. vpn_name .. "' 2>/dev/null")
end

local function linux_deactivate_vpn(vpn_name)
    return os.execute("nmcli connection down '" .. vpn_name .. "' 2>/dev/null")
end

-- ===========================================================================
-- macOS (networksetup + scutil)
-- ===========================================================================

local function macos_list_vpns()
    local vpns = {}
    -- List VPN services via scutil
    local pipe = io.popen("scutil --nc list 2>/dev/null")
    if not pipe then return vpns end
    for line in pipe:lines() do
        -- Format: * (Connected)     "VPN Name" [IPSec/L2TP/IKEv2]
        local status, name, vpn_type = line:match('^%s*[%*%-]%s+%((%w+)%)%s+"(.-)"%s+%[(.-)%]')
        if name then
            table.insert(vpns, {
                name = name,
                type = vpn_type:lower(),
                system_name = name,
                connected = (status == "Connected"),
            })
        end
    end
    pipe:close()

    -- Also check for WireGuard (usually runs as wg-quick via brew)
    local wg_pipe = io.popen("wg show interfaces 2>/dev/null")
    if wg_pipe then
        for line in wg_pipe:lines() do
            if line ~= "" then
                table.insert(vpns, { name = line, type = "wireguard", system_name = line })
            end
        end
        wg_pipe:close()
    end

    return vpns
end

local function macos_get_active_vpns()
    local active = {}
    local pipe = io.popen("scutil --nc list 2>/dev/null")
    if not pipe then return active end
    for line in pipe:lines() do
        local status, name, vpn_type = line:match('^%s*[%*%-]%s+%((%w+)%)%s+"(.-)"%s+%[(.-)%]')
        if name and status == "Connected" then
            table.insert(active, { name = name, type = vpn_type:lower() })
        end
    end
    pipe:close()
    return active
end

local function macos_is_vpn_active(vpn_name)
    local pipe = io.popen("scutil --nc status '" .. vpn_name .. "' 2>/dev/null")
    if not pipe then return false end
    local first_line = pipe:read("*l")
    pipe:close()
    return first_line and first_line:lower() == "connected"
end

local function macos_activate_vpn(vpn_name)
    return os.execute("scutil --nc start '" .. vpn_name .. "' 2>/dev/null")
end

local function macos_deactivate_vpn(vpn_name)
    return os.execute("scutil --nc stop '" .. vpn_name .. "' 2>/dev/null")
end

-- ===========================================================================
-- Windows (PowerShell / rasdial)
-- ===========================================================================

local function windows_list_vpns()
    local vpns = {}
    -- Use PowerShell to list VPN connections
    local pipe = io.popen('powershell -NoProfile -Command "Get-VpnConnection | Select-Object -Property Name,ServerAddress,ConnectionStatus,TunnelType | ConvertTo-Csv -NoTypeInformation" 2>NUL')
    if not pipe then return vpns end
    local header = true
    for line in pipe:lines() do
        if header then
            header = false  -- skip CSV header
        else
            -- Parse CSV: "Name","ServerAddress","ConnectionStatus","TunnelType"
            local name, _, status, tunnel = line:match('"(.-)".-"(.-)".-"(.-)".-"(.-)"')
            if name then
                table.insert(vpns, {
                    name = name,
                    type = (tunnel or "vpn"):lower(),
                    system_name = name,
                    connected = (status == "Connected"),
                })
            end
        end
    end
    pipe:close()
    return vpns
end

local function windows_get_active_vpns()
    local active = {}
    local all = windows_list_vpns()
    for _, vpn in ipairs(all) do
        if vpn.connected then
            table.insert(active, { name = vpn.name, type = vpn.type })
        end
    end
    return active
end

local function windows_is_vpn_active(vpn_name)
    local pipe = io.popen('powershell -NoProfile -Command "(Get-VpnConnection -Name \'' .. vpn_name .. '\').ConnectionStatus" 2>NUL')
    if not pipe then return false end
    local status = pipe:read("*l")
    pipe:close()
    return status and status:lower() == "connected"
end

local function windows_activate_vpn(vpn_name)
    return os.execute('rasdial "' .. vpn_name .. '" 2>NUL')
end

local function windows_deactivate_vpn(vpn_name)
    return os.execute('rasdial "' .. vpn_name .. '" /disconnect 2>NUL')
end

-- ===========================================================================
-- PUBLIC API (dispatches to OS-specific implementations)
-- ===========================================================================

local function get_os()
    return osdetect.detect_os()
end

--- List all VPN connections on the system.
--- @return table  Array of { name, type, system_name }
function M.list_system_vpns()
    local os_name = get_os()
    if os_name == "linux"   then return linux_list_vpns()   end
    if os_name == "macos"   then return macos_list_vpns()   end
    if os_name == "windows" then return windows_list_vpns() end
    return {}
end

--- Get currently active VPN connections.
--- @return table  Array of { name, type }
function M.get_active_vpns()
    local os_name = get_os()
    if os_name == "linux"   then return linux_get_active_vpns()   end
    if os_name == "macos"   then return macos_get_active_vpns()   end
    if os_name == "windows" then return windows_get_active_vpns() end
    return {}
end

--- Check if a specific VPN is active.
--- @param vpn_name string  The system VPN name
--- @return boolean
function M.is_active(vpn_name)
    local os_name = get_os()
    if os_name == "linux"   then return linux_is_vpn_active(vpn_name)   end
    if os_name == "macos"   then return macos_is_vpn_active(vpn_name)   end
    if os_name == "windows" then return windows_is_vpn_active(vpn_name) end
    return false
end

--- Activate a VPN connection.
--- @param vpn_name string
--- @return boolean|nil  OS exit status
function M.activate(vpn_name)
    local os_name = get_os()
    if os_name == "linux"   then return linux_activate_vpn(vpn_name)   end
    if os_name == "macos"   then return macos_activate_vpn(vpn_name)   end
    if os_name == "windows" then return windows_activate_vpn(vpn_name) end
    return nil
end

--- Deactivate a VPN connection.
--- @param vpn_name string
--- @return boolean|nil  OS exit status
function M.deactivate(vpn_name)
    local os_name = get_os()
    if os_name == "linux"   then return linux_deactivate_vpn(vpn_name)   end
    if os_name == "macos"   then return macos_deactivate_vpn(vpn_name)   end
    if os_name == "windows" then return windows_deactivate_vpn(vpn_name) end
    return nil
end

--- Deactivate all VPN connections.
function M.deactivate_all()
    local active = M.get_active_vpns()
    for _, vpn in ipairs(active) do
        M.deactivate(vpn.name)
    end
    return #active
end

return M
