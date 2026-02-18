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
function M.create_group(group_name)
    local data = config_handler.load_or_create(Config.Paths.connection, { default = {} })
    if data[group_name] then
        print("Group '" .. group_name .. "' already exists.")
        return false
    end
    data[group_name] = {}
    config_handler.save_yaml(Config.Paths.connection, data)
    print("Group '" .. group_name .. "' created.")
    return true
end

--- Rename a group.
--- @param old_name string
--- @param new_name string
function M.rename_group(old_name, new_name)
    local data = config_handler.load_or_create(Config.Paths.connection, { default = {} })
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
    config_handler.save_yaml(Config.Paths.connection, data)
    print("Group renamed: '" .. old_name .. "' → '" .. new_name .. "'")
    return true
end

--- Delete a group (with confirmation).
--- @param group_name string
--- @param skip_confirm boolean|nil  Skip y/n prompt
function M.delete_group(group_name, skip_confirm)
    local data = config_handler.load_or_create(Config.Paths.connection, { default = {} })
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
    config_handler.save_yaml(Config.Paths.connection, data)
    print("Group '" .. group_name .. "' deleted.")
    return true
end

--- List all groups.
--- @return table  Array of group names
function M.list_groups()
    local data = config_handler.load_or_create(Config.Paths.connection, { default = {} })
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
function M.add_connection(group, name, conn_data)
    local data = config_handler.load_or_create(Config.Paths.connection, { default = {} })
    data[group] = data[group] or {}
    if data[group][name] then
        print("Connection '" .. name .. "' already exists in group '" .. group .. "'.")
        return false
    end
    data[group][name] = conn_data
    config_handler.save_yaml(Config.Paths.connection, data)
    print("Connection '" .. name .. "' added to group '" .. group .. "'.")
    return true
end

--- Edit/update a connection.
--- @param group string
--- @param name string
--- @param new_data table
function M.edit_connection(group, name, new_data)
    local data = config_handler.load_or_create(Config.Paths.connection, { default = {} })
    if not data[group] or not data[group][name] then
        print("Connection '" .. name .. "' not found in group '" .. group .. "'.")
        return false
    end
    -- Merge: new_data overwrites existing fields
    for k, v in pairs(new_data) do
        data[group][name][k] = v
    end
    config_handler.save_yaml(Config.Paths.connection, data)
    print("Connection '" .. name .. "' updated.")
    return true
end

--- Delete a connection.
--- @param group string
--- @param name string
--- @param skip_confirm boolean|nil
function M.delete_connection(group, name, skip_confirm)
    local data = config_handler.load_or_create(Config.Paths.connection, { default = {} })
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
    config_handler.save_yaml(Config.Paths.connection, data)
    print("Connection '" .. name .. "' deleted from group '" .. group .. "'.")
    return true
end

--- Rename a connection.
--- @param old_name string
--- @param new_name string
function M.rename_connection(old_name, new_name)
    local data = config_handler.load_or_create(Config.Paths.connection, { default = {} })
    for group, conns in pairs(data) do
        if type(conns) == "table" and conns[old_name] then
            if conns[new_name] then
                print("Connection '" .. new_name .. "' already exists in group '" .. group .. "'.")
                return false
            end
            conns[new_name] = conns[old_name]
            conns[old_name] = nil
            config_handler.save_yaml(Config.Paths.connection, data)
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
function M.move_connection(name, from_group, to_group)
    local data = config_handler.load_or_create(Config.Paths.connection, { default = {} })
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
    config_handler.save_yaml(Config.Paths.connection, data)
    print("Connection '" .. name .. "' moved: '" .. from_group .. "' → '" .. to_group .. "'")
    return true
end

--- Find a connection by name across all groups.
--- @param name string
--- @return table|nil conn_data
--- @return string|nil group_name
function M.find_connection(name)
    local data = config_handler.load_or_create(Config.Paths.connection, { default = {} })
    for group, conns in pairs(data) do
        if type(conns) == "table" and conns[name] then
            return conns[name], group
        end
    end
    return nil, nil
end

--- Interactive prompt to create a new connection.
--- @param name string  The connection name to create
function M.ask_create_connection(name)
    print("Connection '" .. name .. "' does not exist. Create it? (y/n): ")
    local ans = io.read("*l")
    if ans ~= "y" and ans ~= "Y" then return false end

    -- Select group
    local groups = M.list_groups()
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

    return M.add_connection(group, name, conn_data)
end

return M
