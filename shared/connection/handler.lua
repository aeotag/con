-- ============================================================================
-- con - Connection Handler (orchestrates connect workflow)
-- shared/connection/handler.lua
-- ============================================================================

local config_handler = require("shared.config.handler")
local config_edit = require("shared.config.edit")
local vpn_handler = require("shared.vpn.handler")
local ssh = require("shared.connection.ssh")
local telnet = require("shared.connection.telnet")
local tunnel = require("shared.connection.tunnel")
local Config = require("config")
local lang -- lazy load

local M = {}

local function L(key, ...)
    if not lang then lang = require("shared.lang.handler") end
    return lang.Get(key, ...)
end

-- ===========================================================================
-- DISPLAY
-- ===========================================================================

--- Pretty-print a single connection entry.
--- @param name string
--- @param conn table
--- @param indent number|nil
local function PrintConnection(name, conn, indent)
    indent = indent or 2
    local pad = string.rep(" ", indent)
    print(pad .. "📌 " .. name)
    print(pad .. "  " .. L("show.protocol") .. ": " .. (conn.protocol or "ssh"))
    print(pad .. "  " .. L("show.user") .. ": " .. (conn.user or "—"))
    if conn.key then
        print(pad .. "  " .. L("show.key") .. ": " .. conn.key)
    end
    if conn.addresses then
        print(pad .. "  " .. L("show.addresses") .. ":")
        for _, addr in ipairs(conn.addresses) do
            local vpn_str = addr.vpn and (" [" .. L("show.vpn") .. ": " .. addr.vpn .. "]") or ""
            local net_str = addr.network and (" (" .. addr.network .. ")") or ""
            print(pad .. "    - " .. addr.ip .. vpn_str .. net_str)
        end
    end
    -- Tunnel-specific fields
    if conn.instance_id then
        print(pad .. "  Instance ID: " .. conn.instance_id)
    end
    if conn.aws_profile then
        print(pad .. "  AWS Profile: " .. conn.aws_profile)
    end
end

--- Show connections: all, by group, or by name.
--- @param group string|nil   Filter by group
function M.ShowConnections(group)
    local data = config_handler.LoadOrCreate(Config.Paths.connection, { default = {} })

    if group then
        -- Show specific group
        if not data[group] then
            print(L("group.not_found", group))
            return
        end
        print(L("show.header_group", group))
        print("")
        local empty = true
        for name, conn in pairs(data[group]) do
            if type(conn) == "table" then
                PrintConnection(name, conn)
                print("")
                empty = false
            end
        end
        if empty then
            print("  " .. L("show.no_connections"))
        end
    else
        -- Show all
        print(L("show.header_all"))
        print("")
        local any = false
        local groups = {}
        for g, _ in pairs(data) do table.insert(groups, g) end
        table.sort(groups)
        for _, g in ipairs(groups) do
            if type(data[g]) == "table" then
                print("━━ " .. g .. " ━━")
                for name, conn in pairs(data[g]) do
                    if type(conn) == "table" then
                        PrintConnection(name, conn)
                        print("")
                        any = true
                    end
                end
            end
        end
        if not any then
            print("  " .. L("show.no_connections"))
        end
    end
end

-- ===========================================================================
-- CONNECT WORKFLOW
-- ===========================================================================

--- Main connect workflow: find connection, resolve VPN, connect.
--- @param name string  Connection alias name
function M.Connect(name)
    local conn_data, group = config_edit.FindConnection(name)

    -- Connection not found → ask to create
    if not conn_data then
        print(L("connection.not_found", name))
        if Config.Ask.create_missing then
            config_edit.AskCreateConnection(name)
            -- Retry after creation
            conn_data, group = config_edit.FindConnection(name)
            if not conn_data then return end
        else
            return
        end
    end

    local protocol = conn_data.protocol or "ssh"

    -- TUNNEL connections (AWS) — different workflow
    if protocol == "tunnel" then
        print(L("connection.connecting", name))
        tunnel.Connect(conn_data)
        return
    end

    -- SSH / TELNET — address-based workflow
    local addresses = conn_data.addresses or {}
    if #addresses == 0 then
        print(L("connection.no_reachable", name))
        return
    end

    -- Find matching addresses (VPN that's currently active or no VPN needed)
    local matches, all_info = vpn_handler.FindMatchingAddresses(addresses)

    local target_addr

    if #matches == 1 then
        -- Exactly one match → auto-connect
        target_addr = matches[1]
        local via = target_addr.vpn or target_addr.network or "direct"
        print(L("connection.auto_connected", name, via))

    elseif #matches > 1 then
        -- Multiple matches → ask user
        print(L("connection.multiple_available"))
        for i, addr in ipairs(matches) do
            local vpn_str = addr.vpn and (" [VPN: " .. addr.vpn .. "]") or ""
            local net_str = addr.network and (" (" .. addr.network .. ")") or ""
            print(string.format("  %d) %s%s%s", i, addr.ip, vpn_str, net_str))
        end
        io.write(L("connection.select_address") .. " ")
        local sel = tonumber(io.read("*l"))
        if sel and matches[sel] then
            target_addr = matches[sel]
        else
            print(L("general.invalid_selection"))
            return
        end

    else
        -- No matches → show all addresses, ask user to pick (may need VPN activation)
        print(L("connection.no_reachable", name))
        print("")
        for i, info in ipairs(all_info) do
            local vpn_str = info.vpn and (" [VPN: " .. info.vpn .. " — inactive]") or ""
            local net_str = info.network and (" (" .. info.network .. ")") or ""
            print(string.format("  %d) %s%s%s", i, info.ip, vpn_str, net_str))
        end
        io.write(L("connection.select_address") .. " ")
        local sel = tonumber(io.read("*l"))
        if sel and addresses[sel] then
            target_addr = addresses[sel]
            -- Activate VPN if needed
            if target_addr.vpn then
                if not vpn_handler.EnsureVpnActive(target_addr.vpn) then
                    print(L("general.cancelled"))
                    return
                end
            end
        else
            print(L("general.invalid_selection"))
            return
        end
    end

    -- Connectivity test
    local ip = target_addr.ip
    local user = conn_data.user or "root"

    if protocol == "ssh" then
        print(L("connection.testing_connectivity", ip))
        if not ssh.Ping(ip) then
            print(L("connection.unreachable", ip))
            io.write("Try anyway? (y/n): ")
            local ans = io.read("*l")
            if ans ~= "y" and ans ~= "Y" then return end
        end
        local keyfile = ssh.FindKey(conn_data.key)
        print(L("connection.connecting", user .. "@" .. ip))
        ssh.Connect(user, ip, keyfile)

    elseif protocol == "telnet" then
        local port = target_addr.port or conn_data.port or 23
        print(L("connection.connecting", ip .. ":" .. tostring(port)))
        telnet.Connect(ip, port)
    end
end

--- Quick-add: create connection from "user@ip" and optionally connect.
--- @param name string
--- @param user_at_ip string  "user@ip" format
--- @param group string|nil   Group name (default: "default")
function M.QuickAdd(name, user_at_ip, group)
    group = group or "default"
    local user, ip = user_at_ip:match("^(.+)@(.+)$")
    if not user or not ip then
        print("Invalid format. Use: user@ip")
        return
    end

    local conn_data = {
        protocol = "ssh",
        user = user,
        addresses = {
            { ip = ip, network = "local" },
        },
    }

    config_edit.AddConnection(group, name, conn_data)
end

return M
