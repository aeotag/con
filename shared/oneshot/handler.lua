-- ============================================================================
-- con - Oneshot Handler (batch remote command execution)
-- shared/oneshot/handler.lua
-- ============================================================================

local config_handler = require("shared.config.handler")
local config_edit    = require("shared.config.edit")
local vpn_handler    = require("shared.vpn.handler")
local ssh            = require("shared.connection.ssh")
local telnet         = require("shared.connection.telnet")
local tunnel_mod     = require("shared.connection.tunnel")
local verify         = require("shared.oneshot.verify")
local Config         = require("config")
local lang -- lazy load

local M = {}

local function L(key, ...)
    if not lang then lang = require("shared.lang.handler") end
    return lang.Get(key, ...)
end

--- Resolve variables in a command string.
--- Supported: {{hostname}}, {{ip}}, {{date}}, {{group}}, {{user}}, and custom variables.
--- @param cmd string          Command template
--- @param vars table          Variable values
--- @return string
function M.ResolveVariables(cmd, vars)
    return cmd:gsub("{{(.-)}}", function(key)
        return vars[key] or ("{{" .. key .. "}}")
    end)
end

--- Build the list of commands from oneshot entry.
--- Supports both `cmd` (single) and `cmds` (array).
--- @param entry table  Oneshot YAML entry
--- @param cli_cmd string|nil  CLI override command
--- @return table  Array of command strings
function M.GetCommands(entry, cli_cmd)
    if cli_cmd then
        return { cli_cmd }
    end
    if entry.cmds and type(entry.cmds) == "table" then
        return entry.cmds
    end
    if entry.cmd then
        return { entry.cmd }
    end
    return {}
end

--- Generate a log file path for a device.
--- @param oneshot_name string
--- @param device_name string
--- @param index number|nil
--- @return string
function M.LogPath(oneshot_name, device_name, index)
    config_handler.EnsureDir(Config.Paths.logs)
    local timestamp = os.date("%Y%m%d_%H%M%S")
    local idx_str = index and ("_" .. tostring(index)) or ""
    return string.format(
        "%s/oneshot_%s_%s%s_%s.log",
        Config.Paths.logs, oneshot_name, device_name, idx_str, timestamp
    )
end

--- Load oneshot definitions.
--- @return table
function M.LoadOneshots()
    return config_handler.LoadOrCreate(Config.Paths.oneshot, {})
end

--- Save oneshot definitions.
--- @param data table
function M.SaveOneshots(data)
    config_handler.SaveYaml(Config.Paths.oneshot, data)
end

--- Interactive creation of a new oneshot.
--- @param name string
--- @return table|nil  Created entry
function M.AskCreateOneshot(name)
    io.write(L("oneshot.ask_create", name) .. " (y/n): ")
    local ans = io.read("*l")
    if ans ~= "y" and ans ~= "Y" then return nil end

    -- Group
    io.write(L("oneshot.enter_group") .. " ")
    local group_input = io.read("*l")
    local group = (group_input ~= "") and group_input or nil

    -- Connections
    io.write(L("oneshot.enter_connections") .. " ")
    local conn_input = io.read("*l")
    local connections = {}
    if conn_input ~= "" then
        for c in conn_input:gmatch("[^,]+") do
            table.insert(connections, c:match("^%s*(.-)%s*$"))
        end
    end

    -- VPN
    io.write(L("oneshot.enter_vpn") .. " ")
    local vpn_input = io.read("*l")
    local vpn = (vpn_input ~= "") and vpn_input or nil

    -- Commands (multi-line input)
    print(L("oneshot.enter_cmd"))
    local cmds = {}
    while true do
        local line = io.read("*l")
        if not line or line == "" then break end
        table.insert(cmds, line)
    end

    if #cmds == 0 then
        print("No commands entered. Cancelled.")
        return nil
    end

    local entry = {
        group = group,
        connections = (#connections > 0) and connections or nil,
        vpn = vpn,
        parallel = Config.Defaults.parallel,
    }

    if #cmds == 1 then
        entry.cmd = cmds[1]
    else
        entry.cmds = cmds
    end

    -- Save
    local data = M.LoadOneshots()
    data[name] = entry
    M.SaveOneshots(data)
    print(L("oneshot.created", name))

    return entry
end

--- Collect all target connections for a oneshot entry.
--- @param entry table              Oneshot definition
--- @return table                   Array of { name, conn_data, group }
function M.CollectTargets(entry)
    local conn_data_all = config_handler.LoadOrCreate(Config.Paths.connection, { default = {} })
    local targets = {}

    -- If specific connections are listed
    if entry.connections and #entry.connections > 0 then
        for _, conn_name in ipairs(entry.connections) do
            -- Search in specified group first, then all groups
            if entry.group and conn_data_all[entry.group] and conn_data_all[entry.group][conn_name] then
                table.insert(targets, {
                    name = conn_name,
                    conn = conn_data_all[entry.group][conn_name],
                    group = entry.group,
                })
            else
                for g, conns in pairs(conn_data_all) do
                    if type(conns) == "table" and conns[conn_name] then
                        table.insert(targets, {
                            name = conn_name,
                            conn = conns[conn_name],
                            group = g,
                        })
                        break
                    end
                end
            end
        end

    -- If only group is specified → all connections in that group
    elseif entry.group and conn_data_all[entry.group] then
        for conn_name, conn in pairs(conn_data_all[entry.group]) do
            if type(conn) == "table" then
                table.insert(targets, {
                    name = conn_name,
                    conn = conn,
                    group = entry.group,
                })
            end
        end
    end

    return targets
end

--- Execute a oneshot.
--- @param name string
--- @param opts table|nil  CLI overrides: { group, vpn, cmd, tail, search, parallel, sequential }
function M.RunOneshot(name, opts)
    opts = opts or {}

    local data = M.LoadOneshots()
    local entry = data[name]

    -- Not found → ask to create
    if not entry then
        entry = M.AskCreateOneshot(name)
        if not entry then return end
    end

    -- Apply CLI overrides
    if opts.group then entry.group = opts.group end
    if opts.vpn   then entry.vpn   = opts.vpn end

    -- Determine parallel mode
    local is_parallel = entry.parallel
    if is_parallel == nil then is_parallel = Config.Defaults.parallel end
    if opts.parallel   then is_parallel = true end
    if opts.sequential then is_parallel = false end

    -- Check SSH agent for parallel mode
    if is_parallel and not ssh.IsAgentReady() then
        print(L("oneshot.no_ssh_agent"))
        is_parallel = false
    end

    -- VPN activation
    if entry.vpn then
        if not vpn_handler.EnsureVpnActive(entry.vpn) then
            print(L("general.cancelled"))
            return
        end
    end

    -- Collect targets
    local targets = M.CollectTargets(entry)
    if #targets == 0 then
        print(L("oneshot.no_connections", name))
        return
    end

    -- Build commands
    local commands = M.GetCommands(entry, opts.cmd)
    if #commands == 0 then
        print("No commands configured for oneshot '" .. name .. "'.")
        return
    end
    local full_cmd = table.concat(commands, " && ")

    print(L("oneshot.running", name))
    print("")

    -- Execute on each target
    local log_files = {} -- device_name → log_path

    for _, target in ipairs(targets) do
        local conn = target.conn
        local device = target.name
        local protocol = conn.protocol or "ssh"
        local user = conn.user or "root"

        -- Find the best address (prefer one matching active VPN)
        local addresses = conn.addresses or {}
        local addr
        if #addresses > 0 then
            local matches = vpn_handler.FindMatchingAddresses(addresses)
            addr = matches[1] or addresses[1]
        end

        if not addr and protocol ~= "tunnel" then
            print("  ⚠ " .. device .. ": No address available.")
        else
            -- Resolve variables
            local vars = {
                hostname = device,
                ip       = addr and addr.ip or "",
                date     = os.date("%Y-%m-%d"),
                group    = target.group,
                user     = user,
            }
            -- Add custom variables from oneshot entry
            if entry.variables then
                for k, v in pairs(entry.variables) do
                    vars[k] = v
                end
            end

            local resolved_cmd = M.ResolveVariables(full_cmd, vars)
            local log_file = M.LogPath(name, device)
            log_files[device] = log_file

            local exec_cmd
            if protocol == "ssh" then
                local keyfile = ssh.FindKey(conn.key)
                exec_cmd = ssh.BuildExecCommand(user, addr.ip, resolved_cmd, keyfile)
            elseif protocol == "telnet" then
                local port = addr.port or conn.port or 23
                exec_cmd = telnet.BuildExecCommand(addr.ip, port, resolved_cmd)
            elseif protocol == "tunnel" then
                exec_cmd = tunnel_mod.BuildExecCommand(
                    conn.instance_id, resolved_cmd, conn.aws_profile, conn.aws_region
                )
            end

            if exec_cmd then
                -- Redirect output to log file
                exec_cmd = exec_cmd .. " > '" .. log_file .. "' 2>&1"

                if is_parallel then
                    exec_cmd = exec_cmd .. " &"
                    print(L("oneshot.running_parallel", device, log_file))
                else
                    print(L("oneshot.running_sequential", device, log_file))
                end

                os.execute(exec_cmd)
            end
        end
    end

    -- Wait for background jobs (if parallel)
    if is_parallel then
        os.execute("wait 2>/dev/null")
        -- Small delay to ensure files are flushed
        os.execute("sleep 1")
    end

    print("")
    print(L("oneshot.complete", name))

    -- Run verification if configured
    if entry.verify or opts.tail or opts.search then
        local cli_overrides = {
            tail   = opts.tail and tonumber(opts.tail) or nil,
            search = opts.search,
        }
        verify.VerifyAll(log_files, entry.verify or {}, cli_overrides)
    end
end

return M
