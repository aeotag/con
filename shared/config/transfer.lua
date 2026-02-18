-- ============================================================================
-- con - Import / Export Handler
-- shared/config/transfer.lua
--
-- Export: Serializes connections, groups, or oneshots to a base64 one-liner.
-- Import: Decodes, remaps VPN names, asks for SSH key, handles collisions.
-- ============================================================================

local config_handler = require("shared.config.handler")
local Config = require("config")
local yaml = require("lyaml")
local lang -- lazy loaded

local M = {}

local function L(key, ...)
    if not lang then lang = require("shared.lang.handler") end
    return lang.Get(key, ...)
end

-- ===========================================================================
-- BASE64 (pure Lua — no external dependency)
-- ===========================================================================

local b64_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function Base64Encode(data)
    local result = {}
    local pad = ""
    local len = #data
    -- Pad input to multiple of 3
    local remainder = len % 3
    if remainder > 0 then
        pad = string.rep("=", 3 - remainder)
        data = data .. string.rep("\0", 3 - remainder)
        len = len + (3 - remainder)
    end
    for i = 1, len, 3 do
        local b1, b2, b3 = data:byte(i, i + 2)
        local n = b1 * 65536 + b2 * 256 + b3
        local c1 = math.floor(n / 262144) % 64
        local c2 = math.floor(n / 4096) % 64
        local c3 = math.floor(n / 64) % 64
        local c4 = n % 64
        table.insert(result, b64_chars:sub(c1 + 1, c1 + 1))
        table.insert(result, b64_chars:sub(c2 + 1, c2 + 1))
        table.insert(result, b64_chars:sub(c3 + 1, c3 + 1))
        table.insert(result, b64_chars:sub(c4 + 1, c4 + 1))
    end
    local encoded = table.concat(result)
    -- Replace trailing characters with padding
    if #pad > 0 then
        encoded = encoded:sub(1, -(#pad + 1)) .. pad
    end
    return encoded
end

local function Base64Decode(data)
    -- Build reverse lookup
    local rev = {}
    for i = 1, #b64_chars do
        rev[b64_chars:sub(i, i)] = i - 1
    end
    rev["="] = 0
    -- Strip whitespace
    data = data:gsub("%s+", "")
    local result = {}
    for i = 1, #data, 4 do
        local c1 = rev[data:sub(i, i)] or 0
        local c2 = rev[data:sub(i + 1, i + 1)] or 0
        local c3 = rev[data:sub(i + 2, i + 2)] or 0
        local c4 = rev[data:sub(i + 3, i + 3)] or 0
        local n = c1 * 262144 + c2 * 4096 + c3 * 64 + c4
        table.insert(result, string.char(math.floor(n / 65536) % 256))
        table.insert(result, string.char(math.floor(n / 256) % 256))
        table.insert(result, string.char(n % 256))
    end
    local decoded = table.concat(result)
    -- Trim padding bytes
    local pad_count = 0
    if data:sub(-1) == "=" then pad_count = pad_count + 1 end
    if data:sub(-2, -2) == "=" then pad_count = pad_count + 1 end
    if pad_count > 0 then
        decoded = decoded:sub(1, -(pad_count + 1))
    end
    return decoded
end

-- ===========================================================================
-- HELPERS
-- ===========================================================================

--- List SSH key files in ~/.ssh/ (private keys only, no .pub).
--- @return table  Array of key filenames (basename only)
local function ListSshKeys()
    local ssh_dir = (os.getenv("HOME") or os.getenv("USERPROFILE") or "~") .. "/.ssh"
    local keys = {}
    local os_name = require("shared.os.detect").DetectOs()
    local cmd
    if os_name == "windows" then
        cmd = 'dir /b "' .. ssh_dir:gsub("/", "\\") .. '" 2>NUL'
    else
        cmd = "ls -1 '" .. ssh_dir .. "' 2>/dev/null"
    end
    local pipe = io.popen(cmd)
    if pipe then
        for line in pipe:lines() do
            -- Skip .pub, known_hosts, config, authorized_keys, agent-*, etc.
            if not line:match("%.pub$")
                and not line:match("^known_hosts")
                and not line:match("^config$")
                and not line:match("^authorized_keys")
                and not line:match("^agent")
                and not line:match("^environment$")
                and line ~= ""
            then
                table.insert(keys, line)
            end
        end
        pipe:close()
    end
    return keys
end

--- Ask the user to pick an SSH key from ~/.ssh/.
--- @param current_key string|nil  The key from the export (shown as reference)
--- @return string|nil  Selected key filename
local function AskSshKey(current_key)
    local keys = ListSshKeys()
    if #keys == 0 then
        print(L("transfer.no_ssh_keys"))
        return current_key
    end

    print(L("transfer.select_ssh_key"))
    if current_key then
        print("  " .. L("transfer.exported_key", current_key))
    end
    for i, k in ipairs(keys) do
        local marker = ""
        if k == current_key then marker = " ← " .. L("transfer.original") end
        print("  " .. i .. ") " .. k .. marker)
    end
    io.write("  " .. L("transfer.enter_number_or_keep") .. " ")
    local input = io.read("*l")
    if not input or input == "" then
        return current_key
    end
    local num = tonumber(input)
    if num and keys[num] then
        return keys[num]
    end
    -- Treat as literal key name
    return input
end

--- Find VPN mappings of a given type (wireguard, openvpn, etc.) in user's vpn.yaml.
--- @param vpn_type string  e.g. "wireguard"
--- @return table  Array of { friendly_name, system_name, type }
local function FindVpnsByType(vpn_type)
    local vpn_data = config_handler.LoadOrCreate(Config.Paths.vpn, { mappings = {} })
    local mappings = vpn_data.mappings or {}
    local matches = {}
    for name, info in pairs(mappings) do
        if type(info) == "table" and info.type and info.type:lower() == vpn_type:lower() then
            table.insert(matches, {
                friendly_name = name,
                system_name = info.system_name or name,
                type = info.type,
            })
        end
    end
    return matches
end

--- Deep-copy a table (to avoid modifying original data).
--- @param t table
--- @return table
local function DeepCopy(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = DeepCopy(v)
    end
    return copy
end

-- ===========================================================================
-- EXPORT
-- ===========================================================================

--- Build an export payload table.
--- @param export_type string  "connection" | "group" | "oneshot"
--- @param name string         Name of the item
--- @return table|nil payload
--- @return string|nil error
local function BuildExportPayload(export_type, name)
    local payload = {
        con_version = Config.Version,
        type = export_type,
    }

    if export_type == "connection" then
        local conn_data = config_handler.LoadOrCreate(Config.Paths.connection, { default = {} })
        local found_conn, found_group = nil, nil
        for group, conns in pairs(conn_data) do
            if type(conns) == "table" and conns[name] then
                found_conn = DeepCopy(conns[name])
                found_group = group
                break
            end
        end
        if not found_conn then
            return nil, L("connection.not_found", name)
        end
        payload.name = name
        payload.group = found_group
        payload.data = found_conn

    elseif export_type == "group" then
        local conn_data = config_handler.LoadOrCreate(Config.Paths.connection, { default = {} })
        if not conn_data[name] then
            return nil, L("group.not_found", name)
        end
        payload.name = name
        payload.data = DeepCopy(conn_data[name])

    elseif export_type == "oneshot" then
        local ons_data = config_handler.LoadOrCreate(Config.Paths.oneshot, {})
        if not ons_data[name] then
            return nil, L("oneshot.not_found", name)
        end
        payload.name = name
        payload.data = DeepCopy(ons_data[name])
    else
        return nil, L("transfer.invalid_type", export_type)
    end

    return payload, nil
end

--- Export a connection, group, or oneshot as a base64 one-liner.
--- @param export_type string  "connection" | "group" | "oneshot"
--- @param name string         Item name
function M.Export(export_type, name)
    if not export_type or not name then
        print(L("transfer.export_usage"))
        return false
    end

    local payload, err = BuildExportPayload(export_type, name)
    if not payload then
        print(err)
        return false
    end

    -- Serialize to YAML, then base64-encode
    local ok, yaml_str = pcall(yaml.dump, { payload })
    if not ok then
        print(L("general.error") .. ": " .. tostring(yaml_str))
        return false
    end

    local encoded = Base64Encode(yaml_str)

    print("")
    print(L("transfer.export_success", export_type, name))
    print(L("transfer.copy_line"))
    print("")
    print("con import " .. encoded)
    print("")
    return true
end

-- ===========================================================================
-- IMPORT
-- ===========================================================================

--- Remap VPN fields in addresses for the importing user.
--- For each address with a vpn + type field, searches user's vpn.yaml for a VPN
--- of the same type. If one found → auto-map. If multiple → ask. If none → warn.
--- @param addresses table  Array of address entries
--- @return table  Remapped addresses
local function RemapVpnAddresses(addresses)
    if not addresses then return {} end
    local remapped = {}

    for _, addr in ipairs(addresses) do
        local new_addr = DeepCopy(addr)
        if addr.vpn and addr.type then
            -- This address needs a VPN of a certain type
            local vpn_type = addr.type
            local candidates = FindVpnsByType(vpn_type)

            if #candidates == 1 then
                -- Auto-map to the only matching VPN
                new_addr.vpn = candidates[1].friendly_name
                print("  " .. L("transfer.vpn_auto_mapped", addr.ip, addr.vpn, candidates[1].friendly_name))
            elseif #candidates > 1 then
                -- Ask user to pick
                print("  " .. L("transfer.vpn_multiple", addr.ip, vpn_type))
                for i, c in ipairs(candidates) do
                    print("    " .. i .. ") " .. c.friendly_name .. " (" .. c.system_name .. ")")
                end
                io.write("    " .. L("transfer.vpn_select") .. " ")
                local input = io.read("*l")
                local num = tonumber(input)
                if num and candidates[num] then
                    new_addr.vpn = candidates[num].friendly_name
                else
                    print("    " .. L("transfer.vpn_kept_original", addr.vpn))
                end
            else
                -- No matching VPN found
                print("  ⚠  " .. L("transfer.vpn_no_match", addr.ip, vpn_type, addr.vpn))
                io.write("    " .. L("transfer.vpn_keep_or_skip") .. " ")
                local input = io.read("*l")
                if input == "s" or input == "S" then
                    new_addr = nil -- skip this address
                    print("    " .. L("transfer.address_skipped", addr.ip))
                else
                    print("    " .. L("transfer.vpn_kept_original", addr.vpn))
                end
            end
        end
        if new_addr then
            table.insert(remapped, new_addr)
        end
    end

    return remapped
end

--- Remap a single connection's VPN addresses and SSH key.
--- @param conn_data table  Connection data
--- @return table  Remapped connection
local function RemapConnection(conn_data)
    local remapped = DeepCopy(conn_data)

    -- Remap VPN addresses
    if remapped.addresses then
        print(L("transfer.remapping_vpn"))
        remapped.addresses = RemapVpnAddresses(remapped.addresses)
    end

    -- Ask for SSH key
    if remapped.key or remapped.protocol == "ssh" then
        remapped.key = AskSshKey(remapped.key)
    end

    return remapped
end

--- Ask which group to import a connection into. Shows existing groups plus
--- the exporter's original group as an option to create.
--- @param export_group string  Group from the export
--- @return string|nil  Selected group name
local function AskImportGroup(export_group)
    local conn_data = config_handler.LoadOrCreate(Config.Paths.connection, { default = {} })
    local groups = {}
    for g, _ in pairs(conn_data) do
        table.insert(groups, g)
    end
    table.sort(groups)

    print(L("transfer.select_import_group"))
    local has_export_group = false
    for i, g in ipairs(groups) do
        local marker = ""
        if g == export_group then
            marker = " ← " .. L("transfer.original_group")
            has_export_group = true
        end
        print("  " .. i .. ") " .. g .. marker)
    end
    if not has_export_group and export_group then
        print("  " .. (#groups + 1) .. ") " .. export_group .. " ← " .. L("transfer.create_new_from_export"))
    end
    io.write("  " .. L("transfer.enter_group_number") .. " ")
    local input = io.read("*l")
    if not input or input == "" then
        return export_group
    end
    local num = tonumber(input)
    if num then
        if num <= #groups and groups[num] then
            return groups[num]
        elseif num == #groups + 1 and not has_export_group then
            return export_group
        end
    end
    -- Treat as literal group name (new group)
    return input
end

--- Handle collision: connection name already exists.
--- @param name string  Connection name
--- @param group string Group name
--- @return string  "overwrite" | "skip" | "rename"
--- @return string|nil  New name (if rename)
local function HandleCollision(name, group)
    print(L("transfer.collision", name, group))
    print("  1) " .. L("transfer.overwrite"))
    print("  2) " .. L("transfer.skip"))
    print("  3) " .. L("transfer.rename"))
    io.write("  " .. L("transfer.select_action") .. " ")
    local input = io.read("*l")
    if input == "1" then
        return "overwrite", nil
    elseif input == "3" then
        io.write("  " .. L("transfer.enter_new_name") .. " ")
        local new_name = io.read("*l")
        if new_name and new_name ~= "" then
            return "rename", new_name
        end
    end
    return "skip", nil
end

--- Import a single connection.
--- @param name string
--- @param conn_data table
--- @param export_group string
--- @return boolean
local function ImportConnection(name, conn_data, export_group)
    print("\n" .. L("transfer.importing_connection", name))

    -- Remap VPN + SSH key
    local remapped = RemapConnection(conn_data)

    -- Ask which group
    local target_group = AskImportGroup(export_group)
    if not target_group then
        print(L("general.cancelled"))
        return false
    end

    -- Load current data and check collision
    local data = config_handler.LoadOrCreate(Config.Paths.connection, { default = {} })
    data[target_group] = data[target_group] or {}

    local final_name = name
    if data[target_group][name] then
        local action, new_name = HandleCollision(name, target_group)
        if action == "skip" then
            print(L("transfer.skipped", name))
            return false
        elseif action == "rename" then
            final_name = new_name
        end
        -- "overwrite" just proceeds
    end

    data[target_group][final_name] = remapped
    config_handler.SaveYaml(Config.Paths.connection, data)
    print(L("transfer.connection_imported", final_name, target_group))
    return true
end

--- Import a group (all connections in it).
--- @param group_name string
--- @param group_data table  { conn_name = conn_data, ... }
--- @return boolean
local function ImportGroup(group_name, group_data)
    print("\n" .. L("transfer.importing_group", group_name))

    -- Ask: use same group name or different?
    local conn_data = config_handler.LoadOrCreate(Config.Paths.connection, { default = {} })
    local target_group = group_name

    if conn_data[group_name] then
        print(L("transfer.group_exists", group_name))
        print("  1) " .. L("transfer.merge_into_existing"))
        print("  2) " .. L("transfer.rename_group"))
        print("  3) " .. L("transfer.skip"))
        io.write("  " .. L("transfer.select_action") .. " ")
        local input = io.read("*l")
        if input == "2" then
            io.write("  " .. L("transfer.enter_new_group_name") .. " ")
            target_group = io.read("*l") or group_name
        elseif input == "3" then
            print(L("transfer.skipped", group_name))
            return false
        end
    end

    local count = 0
    for conn_name, cdata in pairs(group_data) do
        if type(cdata) == "table" then
            if ImportConnection(conn_name, cdata, target_group) then
                count = count + 1
            end
        end
    end

    print(L("transfer.group_imported", target_group, count))
    return true
end

--- Import a oneshot definition.
--- @param ons_name string
--- @param ons_data table
--- @return boolean
local function ImportOneshot(ons_name, ons_data)
    print("\n" .. L("transfer.importing_oneshot", ons_name))

    -- Check if referenced connections/groups exist
    local conn_data = config_handler.LoadOrCreate(Config.Paths.connection, { default = {} })

    if ons_data.group then
        if not conn_data[ons_data.group] then
            print("  ⚠  " .. L("transfer.ons_missing_group", ons_data.group))
            io.write("    " .. L("transfer.ons_create_group") .. " ")
            local input = io.read("*l")
            if input == "y" or input == "Y" or input == "j" or input == "J" or input == "k" or input == "K" then
                conn_data[ons_data.group] = {}
                config_handler.SaveYaml(Config.Paths.connection, conn_data)
                print("    " .. L("group.created", ons_data.group))
            else
                print("    " .. L("transfer.ons_group_warning"))
            end
        end
    end

    if ons_data.connections then
        local missing = {}
        for _, cname in ipairs(ons_data.connections) do
            local found = false
            for _, conns in pairs(conn_data) do
                if type(conns) == "table" and conns[cname] then
                    found = true
                    break
                end
            end
            if not found then
                table.insert(missing, cname)
            end
        end
        if #missing > 0 then
            print("  ⚠  " .. L("transfer.ons_missing_connections", table.concat(missing, ", ")))
        end
    end

    -- Check collision
    local all_ons = config_handler.LoadOrCreate(Config.Paths.oneshot, {})
    local final_name = ons_name

    if all_ons[ons_name] then
        local action, new_name = HandleCollision(ons_name, "oneshot")
        if action == "skip" then
            print(L("transfer.skipped", ons_name))
            return false
        elseif action == "rename" then
            final_name = new_name
        end
    end

    all_ons[final_name] = ons_data
    config_handler.SaveYaml(Config.Paths.oneshot, all_ons)
    print(L("transfer.oneshot_imported", final_name))
    return true
end

--- Import from a base64 one-liner.
--- @param encoded string  Base64-encoded export payload
function M.Import(encoded)
    if not encoded or encoded == "" then
        print(L("transfer.import_usage"))
        return false
    end

    -- Decode base64
    local ok_decode, yaml_str = pcall(Base64Decode, encoded)
    if not ok_decode or not yaml_str or yaml_str == "" then
        print(L("transfer.decode_failed"))
        return false
    end

    -- Parse YAML
    local ok_parse, payload = pcall(yaml.load, yaml_str)
    if not ok_parse or type(payload) ~= "table" then
        print(L("transfer.parse_failed"))
        return false
    end

    -- Validate payload
    if not payload.type or not payload.name or not payload.data then
        print(L("transfer.invalid_payload"))
        return false
    end

    print(L("transfer.import_header", payload.type, payload.name))
    if payload.con_version then
        print(L("transfer.exported_with_version", payload.con_version))
    end

    -- Dispatch by type
    if payload.type == "connection" then
        return ImportConnection(payload.name, payload.data, payload.group or "default")
    elseif payload.type == "group" then
        return ImportGroup(payload.name, payload.data)
    elseif payload.type == "oneshot" then
        return ImportOneshot(payload.name, payload.data)
    else
        print(L("transfer.invalid_type", payload.type))
        return false
    end
end

return M
