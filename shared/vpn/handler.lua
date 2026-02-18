-- ============================================================================
-- con - VPN Handler (user-facing VPN commands + connection workflow helpers)
-- shared/vpn/handler.lua
-- ============================================================================

local detector = require("shared.vpn.detector")
local config_handler = require("shared.config.handler")
local Config = require("config")
local lang -- lazy loaded

local M = {}

local function L(key, ...)
    if not lang then lang = require("shared.lang.handler") end
    return lang.Get(key, ...)
end

--- Load VPN mappings from vpn.yaml.
--- Maps friendly names → system VPN names.
--- @return table  { ["friendly-name"] = { type, system_name } }
function M.LoadVpnConfig()
    local data = config_handler.LoadOrCreate(Config.Paths.vpn, { mappings = {} })
    return data.mappings or {}
end

--- Resolve a VPN name: check vpn.yaml mappings first, then use as system name directly.
--- @param vpn_name string  Friendly name or system name
--- @return string          Resolved system VPN name
--- @return string|nil      VPN type (if known)
function M.ResolveVpnName(vpn_name)
    local mappings = M.LoadVpnConfig()
    if mappings[vpn_name] then
        return mappings[vpn_name].system_name or vpn_name, mappings[vpn_name].type
    end
    return vpn_name, nil
end

--- Show all VPN connections with their status.
function M.Show()
    local vpns = detector.ListSystemVpns()
    if #vpns == 0 then
        print(L("vpn.no_vpns"))
        return
    end

    print(L("vpn.header"))
    print("")
    for i, vpn in ipairs(vpns) do
        local active = detector.IsActive(vpn.system_name or vpn.name)
        local status_icon = active and "🟢" or "⚪"
        local status_text = active and L("vpn.active") or L("vpn.inactive")
        print(string.format("  %d) %s %s [%s] — %s", i, status_icon, vpn.name, vpn.type, status_text))
    end
    print("")
end

--- Activate a VPN by name.
--- @param vpn_name string
function M.Up(vpn_name)
    local sys_name, _ = M.ResolveVpnName(vpn_name)

    if detector.IsActive(sys_name) then
        print(L("vpn.already_active", vpn_name))
        return true
    end

    print(L("vpn.activating", vpn_name))
    local result = detector.Activate(sys_name)
    local ok = result == true or result == 0
    if ok then
        print(L("vpn.activated", vpn_name))
    end
    return ok
end

--- Deactivate a VPN by name.
--- @param vpn_name string
function M.Down(vpn_name)
    local sys_name, _ = M.ResolveVpnName(vpn_name)

    if not detector.IsActive(sys_name) then
        print(L("vpn.not_active", vpn_name))
        return true
    end

    print(L("vpn.deactivating", vpn_name))
    local result = detector.Deactivate(sys_name)
    local ok = result == true or result == 0
    if ok then
        print(L("vpn.deactivated", vpn_name))
    end
    return ok
end

--- Deactivate all VPNs.
function M.DownAll()
    local count = detector.DeactivateAll()
    print(L("vpn.all_deactivated"))
    return count
end

--- Show status of active VPNs.
function M.Status()
    local active = detector.GetActiveVpns()
    print(L("vpn.status_header"))
    print("")
    if #active == 0 then
        print("  " .. L("vpn.no_vpns"))
    else
        for _, vpn in ipairs(active) do
            print(string.format("  🟢 %s [%s]", vpn.name, vpn.type))
        end
    end
    print("")
end

--- Check if a required VPN is active, prompt to activate if not.
--- @param vpn_name string  VPN name required by a connection/oneshot
--- @return boolean         true if VPN is now active (or was already)
function M.EnsureVpnActive(vpn_name)
    if not vpn_name or vpn_name == "" then return true end

    local sys_name, _ = M.ResolveVpnName(vpn_name)

    if detector.IsActive(sys_name) then
        return true
    end

    io.write(L("vpn.required_not_active", vpn_name) .. " ")
    local ans = io.read("*l")
    if ans == "y" or ans == "Y" or ans == "j" or ans == "J" or ans == "k" or ans == "K" then
        return M.Up(vpn_name)
    end

    return false
end

--- Find which VPN is needed for a given address entry.
--- Returns the VPN name from the address if it has one, otherwise nil.
--- @param address_entry table  { ip, vpn, type, network }
--- @return string|nil          VPN name
function M.GetRequiredVpn(address_entry)
    if address_entry.vpn and address_entry.vpn ~= "" then
        return address_entry.vpn
    end
    return nil
end

--- Find addresses from a connection that match a currently active VPN (or need no VPN).
--- @param addresses table  Array of address entries
--- @return table           Matching address entries
--- @return table           All address entries with their VPN match status
function M.FindMatchingAddresses(addresses)
    local active_vpns = detector.GetActiveVpns()
    local active_names = {}
    for _, v in ipairs(active_vpns) do
        active_names[v.name:lower()] = true
    end

    -- Also resolve vpn.yaml mappings
    local mappings = M.LoadVpnConfig()

    local matches = {}
    local all_info = {}

    for _, addr in ipairs(addresses) do
        local needs_vpn = addr.vpn and addr.vpn ~= ""
        local is_match = false

        if not needs_vpn then
            -- No VPN needed → always a candidate (local/direct)
            is_match = true
        else
            -- Check if the required VPN is active
            local sys_name = addr.vpn
            if mappings[addr.vpn] then
                sys_name = mappings[addr.vpn].system_name or addr.vpn
            end
            if active_names[sys_name:lower()] then
                is_match = true
            end
        end

        local info = {
            ip = addr.ip,
            vpn = addr.vpn,
            type = addr.type,
            network = addr.network,
            vpn_active = is_match,
        }
        table.insert(all_info, info)
        if is_match then
            table.insert(matches, addr)
        end
    end

    return matches, all_info
end

return M
