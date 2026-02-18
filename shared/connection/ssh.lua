-- ============================================================================
-- con - SSH Connection Module
-- shared/connection/ssh.lua
-- ============================================================================

local secrets_handler = require("shared.secrets.handler")
local packages = require("shared.os.packages")
local osdetect = require("shared.os.detect")

local M = {}

--- Check if SSH agent is running and has identities loaded.
--- @return boolean
function M.IsAgentReady()
    local sock = os.getenv("SSH_AUTH_SOCK")
    if not sock or sock == "" then return false end

    local pipe = io.popen("ssh-add -l 2>&1")
    if not pipe then return false end
    local out = pipe:read("*a")
    pipe:close()

    if out:find("could not open") or out:find("no identities") or out:find("The agent has no") then
        return false
    end
    return true
end

--- Find the best SSH key for a given connection.
--- Priority: explicit key > auto-detect from ~/.ssh/
--- @param explicit_key string|nil   Key filename from connection config
--- @return string|nil               Full path to key file
function M.FindKey(explicit_key)
    local home = osdetect.GetHome()
    local ssh_dir = home .. "/.ssh"

    if explicit_key then
        -- If it's a full path, use as-is
        if explicit_key:sub(1, 1) == "/" or explicit_key:sub(1, 1) == "~" then
            local path = explicit_key:gsub("^~", home)
            local f = io.open(path, "r")
            if f then f:close(); return path end
        end
        -- Otherwise, look in ~/.ssh/
        local path = ssh_dir .. "/" .. explicit_key
        local f = io.open(path, "r")
        if f then f:close(); return path end
        return nil
    end

    -- Auto-detect: try common key names
    local candidates = {
        "id_ed25519", "id_ecdsa", "id_rsa", "id_dsa",
    }
    for _, name in ipairs(candidates) do
        local path = ssh_dir .. "/" .. name
        local f = io.open(path, "r")
        if f then
            f:close()
            return path
        end
    end

    return nil
end

--- Build the SSH command string.
--- @param user string      Username
--- @param ip string        IP or hostname
--- @param keyfile string|nil  Path to SSH key
--- @param extra_args string|nil  Additional SSH arguments
--- @return string          The full SSH command
function M.BuildCommand(user, ip, keyfile, extra_args)
    local address = user .. "@" .. ip
    local parts = { "ssh" }

    if keyfile then
        local password = secrets_handler.GetKeyPassword(keyfile)
        if password then
            if packages.IsToolInstalled("sshpass") then
                table.insert(parts, 1, "sshpass -p '" .. password .. "'")
            end
        end
        table.insert(parts, "-i " .. keyfile)
    end

    if extra_args then
        table.insert(parts, extra_args)
    end

    table.insert(parts, address)
    return table.concat(parts, " ")
end

--- Build an SSH command for executing a remote command (non-interactive).
--- @param user string
--- @param ip string
--- @param remote_cmd string   Command to run on the remote host
--- @param keyfile string|nil
--- @return string
function M.BuildExecCommand(user, ip, remote_cmd, keyfile)
    local address = user .. "@" .. ip
    local parts = { "ssh" }

    if keyfile then
        table.insert(parts, "-i " .. keyfile)
    end

    -- Non-interactive flags
    table.insert(parts, "-o BatchMode=yes")
    table.insert(parts, "-o StrictHostKeyChecking=accept-new")
    table.insert(parts, address)
    table.insert(parts, "'" .. remote_cmd:gsub("'", "'\\''") .. "'")

    return table.concat(parts, " ")
end

--- Connect interactively via SSH.
--- @param user string
--- @param ip string
--- @param keyfile string|nil
function M.Connect(user, ip, keyfile)
    local cmd = M.BuildCommand(user, ip, keyfile)
    os.execute(cmd)
end

--- Test if a host is reachable via ping.
--- @param ip string
--- @return boolean
function M.Ping(ip)
    local os_name = osdetect.DetectOs()
    local cmd
    if os_name == "windows" then
        cmd = "ping -n 1 -w 2000 " .. ip .. " > NUL 2>&1"
    else
        cmd = "ping -c 1 -W 2 " .. ip .. " > /dev/null 2>&1"
    end
    local ok = os.execute(cmd)
    return ok == true or ok == 0
end

return M
