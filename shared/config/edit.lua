-- ============================================================================
-- con - Config CRUD Operations (connections, groups, oneshots)
-- shared/config/edit.lua
-- ============================================================================

local config_handler = require("shared.config.handler")
local Config = require("config")

local M = {}

-- ===========================================================================
-- GROUP OPERATIONS
-- ===========================================================================

--- Create a new group in connection.yaml.
--- @param group_name string
function M.CreateGroup(group_name)
    local data = config_handler.LoadOrCreate(Config.Paths.connection, { default = {} })
    if data[group_name] then
        print("Group '" .. group_name .. "' already exists.")
        return false
    end
    data[group_name] = {}
    config_handler.SaveYaml(Config.Paths.connection, data)
    print("Group '" .. group_name .. "' created.")
    return true
end

--- Rename a group.
--- @param old_name string
--- @param new_name string
function M.RenameGroup(old_name, new_name)
    local data = config_handler.LoadOrCreate(Config.Paths.connection, { default = {} })
    if not data[old_name] then
        print("Group '" .. old_name .. "' not found.")
        return false
    end
    if data[new_name] then
        print("Group '" .. new_name .. "' already exists.")
        return false
    end
    data[new_name] = data[old_name]
    data[old_name] = nil
    config_handler.SaveYaml(Config.Paths.connection, data)
    print("Group renamed: '" .. old_name .. "' → '" .. new_name .. "'")
    return true
end

--- Delete a group (with confirmation).
--- @param group_name string
--- @param skip_confirm boolean|nil  Skip y/n prompt
function M.DeleteGroup(group_name, skip_confirm)
    local data = config_handler.LoadOrCreate(Config.Paths.connection, { default = {} })
    if not data[group_name] then
        print("Group '" .. group_name .. "' not found.")
        return false
    end

    if not skip_confirm then
        io.write("Delete group '" .. group_name .. "' and all its connections? (y/n): ")
        local ans = io.read("*l")
        if ans ~= "y" and ans ~= "Y" then
            print("Cancelled.")
            return false
        end
    end

    data[group_name] = nil
    config_handler.SaveYaml(Config.Paths.connection, data)
    print("Group '" .. group_name .. "' deleted.")
    return true
end

--- List all groups.
--- @return table  Array of group names
function M.ListGroups()
    local data = config_handler.LoadOrCreate(Config.Paths.connection, { default = {} })
    local groups = {}
    for group, _ in pairs(data) do
        table.insert(groups, group)
    end
    table.sort(groups)
    return groups
end

-- ===========================================================================
-- CONNECTION OPERATIONS
-- ===========================================================================

--- Add a connection to a group.
--- @param group string
--- @param name string
--- @param conn_data table  { protocol, user, key, addresses = { {ip, vpn, type, network} } }
function M.AddConnection(group, name, conn_data)
    local data = config_handler.LoadOrCreate(Config.Paths.connection, { default = {} })
    data[group] = data[group] or {}
    if data[group][name] then
        print("Connection '" .. name .. "' already exists in group '" .. group .. "'.")
        return false
    end
    data[group][name] = conn_data
    config_handler.SaveYaml(Config.Paths.connection, data)
    print("Connection '" .. name .. "' added to group '" .. group .. "'.")
    return true
end

--- Edit/update a connection.
--- @param group string
--- @param name string
--- @param new_data table
function M.EditConnection(group, name, new_data)
    local data = config_handler.LoadOrCreate(Config.Paths.connection, { default = {} })
    if not data[group] or not data[group][name] then
        print("Connection '" .. name .. "' not found in group '" .. group .. "'.")
        return false
    end
    -- Merge: new_data overwrites existing fields
    for k, v in pairs(new_data) do
        data[group][name][k] = v
    end
    config_handler.SaveYaml(Config.Paths.connection, data)
    print("Connection '" .. name .. "' updated.")
    return true
end

--- Delete a connection.
--- @param group string
--- @param name string
--- @param skip_confirm boolean|nil
function M.DeleteConnection(group, name, skip_confirm)
    local data = config_handler.LoadOrCreate(Config.Paths.connection, { default = {} })
    if not data[group] or not data[group][name] then
        print("Connection '" .. name .. "' not found in group '" .. group .. "'.")
        return false
    end

    if not skip_confirm then
        io.write("Delete connection '" .. name .. "' from group '" .. group .. "'? (y/n): ")
        local ans = io.read("*l")
        if ans ~= "y" and ans ~= "Y" then
            print("Cancelled.")
            return false
        end
    end

    data[group][name] = nil
    config_handler.SaveYaml(Config.Paths.connection, data)
    print("Connection '" .. name .. "' deleted from group '" .. group .. "'.")
    return true
end

--- Rename a connection.
--- @param old_name string
--- @param new_name string
function M.RenameConnection(old_name, new_name)
    local data = config_handler.LoadOrCreate(Config.Paths.connection, { default = {} })
    for group, conns in pairs(data) do
        if type(conns) == "table" and conns[old_name] then
            if conns[new_name] then
                print("Connection '" .. new_name .. "' already exists in group '" .. group .. "'.")
                return false
            end
            conns[new_name] = conns[old_name]
            conns[old_name] = nil
            config_handler.SaveYaml(Config.Paths.connection, data)
            print("Connection renamed: '" .. old_name .. "' → '" .. new_name .. "' (group: " .. group .. ")")
            return true
        end
    end
    print("Connection '" .. old_name .. "' not found.")
    return false
end

--- Move a connection to a different group.
--- @param name string
--- @param from_group string
--- @param to_group string
function M.MoveConnection(name, from_group, to_group)
    local data = config_handler.LoadOrCreate(Config.Paths.connection, { default = {} })
    if not data[from_group] or not data[from_group][name] then
        print("Connection '" .. name .. "' not found in group '" .. from_group .. "'.")
        return false
    end

    if not data[to_group] then
        io.write("Group '" .. to_group .. "' does not exist. Create it? (y/n): ")
        local ans = io.read("*l")
        if ans ~= "y" and ans ~= "Y" then
            print("Cancelled.")
            return false
        end
        data[to_group] = {}
    end

    data[to_group][name] = data[from_group][name]
    data[from_group][name] = nil
    config_handler.SaveYaml(Config.Paths.connection, data)
    print("Connection '" .. name .. "' moved: '" .. from_group .. "' → '" .. to_group .. "'")
    return true
end

--- Find a connection by name across all groups.
--- @param name string
--- @return table|nil conn_data
--- @return string|nil group_name
function M.FindConnection(name)
    local data = config_handler.LoadOrCreate(Config.Paths.connection, { default = {} })
    for group, conns in pairs(data) do
        if type(conns) == "table" and conns[name] then
            return conns[name], group
        end
    end
    return nil, nil
end

--- Interactive prompt to create a new connection.
--- @param name string  The connection name to create
function M.AskCreateConnection(name)
    print("Connection '" .. name .. "' does not exist. Create it? (y/n): ")
    local ans = io.read("*l")
    if ans ~= "y" and ans ~= "Y" then return false end

    -- Select group
    local groups = M.ListGroups()
    print("Available groups:")
    for i, g in ipairs(groups) do
        print("  " .. i .. ") " .. g)
    end
    io.write("Select group number (or type a new group name): ")
    local sel = io.read("*l")
    local group
    local num = tonumber(sel)
    if num and groups[num] then
        group = groups[num]
    elseif sel and sel ~= "" then
        group = sel
    else
        group = "default"
    end

    -- Protocol
    io.write("Protocol [ssh/telnet/tunnel] (default: ssh): ")
    local proto = io.read("*l")
    if not proto or proto == "" then proto = "ssh" end

    -- User
    io.write("User: ")
    local user = io.read("*l")

    -- Address
    io.write("IP or hostname: ")
    local ip = io.read("*l")

    -- VPN
    io.write("VPN name (leave blank for none): ")
    local vpn_input = io.read("*l")

    -- Key
    io.write("SSH key filename (leave blank for auto): ")
    local key_input = io.read("*l")

    local address_entry = { ip = ip }
    if vpn_input and vpn_input ~= "" then
        address_entry.vpn = vpn_input
    else
        address_entry.network = "local"
    end

    local conn_data = {
        protocol = proto,
        user     = user,
        addresses = { address_entry },
    }
    if key_input and key_input ~= "" then
        conn_data.key = key_input
    end

    return M.AddConnection(group, name, conn_data)
end

-- ===========================================================================
-- MODIFY CONNECTION FIELDS (one-liner commands)
-- ===========================================================================

--- Add an address entry to an existing connection.
--- @param name string  Connection name
--- @param ip string    IP or hostname
--- @param opts table   { vpn, type, network, port }
function M.AddAddress(name, ip, opts)
    local data = config_handler.LoadOrCreate(Config.Paths.connection, { default = {} })
    for group, conns in pairs(data) do
        if type(conns) == "table" and conns[name] then
            conns[name].addresses = conns[name].addresses or {}
            local entry = { ip = ip }
            if opts.vpn then
                entry.vpn = opts.vpn
                if opts.type then entry.type = opts.type end
            else
                entry.network = opts.network or "local"
            end
            if opts.port then entry.port = tonumber(opts.port) end
            table.insert(conns[name].addresses, entry)
            config_handler.SaveYaml(Config.Paths.connection, data)
            if entry.vpn then
                print("Address added to '" .. name .. "': " .. ip .. " [VPN: " .. entry.vpn .. "]")
            else
                print("Address added to '" .. name .. "': " .. ip .. " (" .. (entry.network or "local") .. ")")
            end
            return true
        end
    end
    print("Connection '" .. name .. "' not found.")
    return false
end

--- Remove an address entry from a connection.
--- @param name string  Connection name
--- @param ip string    IP to remove
--- @param vpn string|nil  Optional VPN to disambiguate
function M.RemoveAddress(name, ip, vpn)
    local data = config_handler.LoadOrCreate(Config.Paths.connection, { default = {} })
    for group, conns in pairs(data) do
        if type(conns) == "table" and conns[name] then
            local addrs = conns[name].addresses or {}
            for i, addr in ipairs(addrs) do
                if addr.ip == ip and (not vpn or addr.vpn == vpn) then
                    table.remove(addrs, i)
                    config_handler.SaveYaml(Config.Paths.connection, data)
                    print("Address removed from '" .. name .. "': " .. ip)
                    return true
                end
            end
            print("Address '" .. ip .. "' not found in connection '" .. name .. "'.")
            return false
        end
    end
    print("Connection '" .. name .. "' not found.")
    return false
end

--- Set a field on an existing connection (user, protocol, key, port).
--- @param name string   Connection name
--- @param field string  Field to set
--- @param value string  New value
function M.SetField(name, field, value)
    local allowed = { user = true, protocol = true, key = true, port = true,
                      instance_id = true, tunnel_type = true, aws_profile = true, aws_region = true }
    if not allowed[field] then
        print("Cannot set field '" .. field .. "'. Allowed: user, protocol, key, port, instance_id, tunnel_type, aws_profile, aws_region")
        return false
    end

    local data = config_handler.LoadOrCreate(Config.Paths.connection, { default = {} })
    for group, conns in pairs(data) do
        if type(conns) == "table" and conns[name] then
            if field == "port" then
                conns[name][field] = tonumber(value)
            else
                conns[name][field] = value
            end
            config_handler.SaveYaml(Config.Paths.connection, data)
            print("Connection '" .. name .. "': " .. field .. " set to '" .. value .. "'")
            return true
        end
    end
    print("Connection '" .. name .. "' not found.")
    return false
end

-- ===========================================================================
-- INTERACTIVE EDIT (con edit <name>)
-- ===========================================================================

--- Interactive edit flow for a connection — walks through all fields.
--- @param name string  Connection name to edit
function M.InteractiveEdit(name)
    local data = config_handler.LoadOrCreate(Config.Paths.connection, { default = {} })
    local conn, found_group = nil, nil
    for group, conns in pairs(data) do
        if type(conns) == "table" and conns[name] then
            conn = conns[name]
            found_group = group
            break
        end
    end

    if not conn then
        print("Connection '" .. name .. "' not found.")
        return false
    end

    print("Editing connection '" .. name .. "' (group: " .. found_group .. ")")
    print("Press Enter to keep current value, type new value to change.\n")

    -- Protocol
    io.write("  Protocol [" .. (conn.protocol or "ssh") .. "]: ")
    local input = io.read("*l")
    if input and input ~= "" then conn.protocol = input end

    -- User
    io.write("  User [" .. (conn.user or "") .. "]: ")
    input = io.read("*l")
    if input and input ~= "" then conn.user = input end

    -- Key
    io.write("  SSH key [" .. (conn.key or "auto") .. "]: ")
    input = io.read("*l")
    if input and input ~= "" then
        if input == "none" or input == "-" then
            conn.key = nil
        else
            conn.key = input
        end
    end

    -- Port (for telnet / tunnel)
    if conn.protocol == "telnet" or conn.port then
        io.write("  Port [" .. (conn.port or 23) .. "]: ")
        input = io.read("*l")
        if input and input ~= "" then conn.port = tonumber(input) end
    end

    -- Tunnel fields
    if conn.protocol == "tunnel" then
        io.write("  Tunnel type [" .. (conn.tunnel_type or "ssm-session") .. "]: ")
        input = io.read("*l")
        if input and input ~= "" then conn.tunnel_type = input end

        io.write("  Instance ID [" .. (conn.instance_id or "") .. "]: ")
        input = io.read("*l")
        if input and input ~= "" then conn.instance_id = input end

        io.write("  AWS Profile [" .. (conn.aws_profile or "") .. "]: ")
        input = io.read("*l")
        if input and input ~= "" then conn.aws_profile = input end

        io.write("  AWS Region [" .. (conn.aws_region or "") .. "]: ")
        input = io.read("*l")
        if input and input ~= "" then conn.aws_region = input end
    end

    -- Addresses
    print("\n  Current addresses:")
    local addrs = conn.addresses or {}
    for i, addr in ipairs(addrs) do
        local label = addr.ip
        if addr.vpn then
            label = label .. " [VPN: " .. addr.vpn .. "]"
        else
            label = label .. " (" .. (addr.network or "local") .. ")"
        end
        print("    " .. i .. ") " .. label)
    end

    -- Edit existing addresses
    for i, addr in ipairs(addrs) do
        print("\n  Address " .. i .. ":")
        io.write("    IP [" .. addr.ip .. "]: ")
        input = io.read("*l")
        if input and input ~= "" then addr.ip = input end

        if addr.vpn then
            io.write("    VPN [" .. addr.vpn .. "]: ")
            input = io.read("*l")
            if input and input ~= "" then
                if input == "none" or input == "-" then
                    addr.vpn = nil
                    addr.type = nil
                    addr.network = "local"
                else
                    addr.vpn = input
                end
            end
            if addr.vpn then
                io.write("    VPN type [" .. (addr.type or "") .. "]: ")
                input = io.read("*l")
                if input and input ~= "" then addr.type = input end
            end
        else
            io.write("    Network [" .. (addr.network or "local") .. "]: ")
            input = io.read("*l")
            if input and input ~= "" then addr.network = input end

            io.write("    Convert to VPN address? (y/n) [n]: ")
            input = io.read("*l")
            if input == "y" or input == "Y" then
                io.write("    VPN name: ")
                local vpn_name = io.read("*l")
                if vpn_name and vpn_name ~= "" then
                    addr.vpn = vpn_name
                    addr.network = nil
                    io.write("    VPN type (wireguard/openvpn): ")
                    local vtype = io.read("*l")
                    if vtype and vtype ~= "" then addr.type = vtype end
                end
            end
        end
    end

    -- Add more addresses?
    while true do
        io.write("\n  Add another address? (y/n) [n]: ")
        input = io.read("*l")
        if input ~= "y" and input ~= "Y" then break end

        io.write("    IP: ")
        local new_ip = io.read("*l")
        if not new_ip or new_ip == "" then break end

        io.write("    VPN name (leave blank for local): ")
        local vpn_name = io.read("*l")

        local new_addr = { ip = new_ip }
        if vpn_name and vpn_name ~= "" then
            new_addr.vpn = vpn_name
            io.write("    VPN type (wireguard/openvpn): ")
            local vtype = io.read("*l")
            if vtype and vtype ~= "" then new_addr.type = vtype end
        else
            new_addr.network = "local"
        end
        table.insert(addrs, new_addr)
    end

    -- Remove addresses?
    if #addrs > 1 then
        io.write("\n  Remove any address? Enter number to remove (or Enter to skip): ")
        input = io.read("*l")
        local rm_idx = tonumber(input)
        if rm_idx and addrs[rm_idx] then
            print("  Removed: " .. addrs[rm_idx].ip)
            table.remove(addrs, rm_idx)
        end
    end

    conn.addresses = addrs

    -- Move to another group?
    io.write("\n  Move to different group? [" .. found_group .. "]: ")
    input = io.read("*l")
    local new_group = found_group
    if input and input ~= "" then
        new_group = input
    end

    -- Save
    if new_group ~= found_group then
        data[found_group][name] = nil
        data[new_group] = data[new_group] or {}
        data[new_group][name] = conn
        print("\nConnection '" .. name .. "' updated and moved to group '" .. new_group .. "'.")
    else
        data[found_group][name] = conn
        print("\nConnection '" .. name .. "' updated.")
    end

    config_handler.SaveYaml(Config.Paths.connection, data)
    return true
end

return M
