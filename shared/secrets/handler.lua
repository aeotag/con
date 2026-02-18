-- ============================================================================
-- con - Secrets Handler (SSH key passwords, tool install state)
-- shared/secrets/handler.lua
-- ============================================================================

local config_handler = require("shared.config.handler")
local Config = require("config")

local M = {}

--- Load secrets file.
--- @return table
function M.LoadSecrets()
    return config_handler.LoadOrCreate(Config.Paths.secrets, {
        sshkeys = {},
        tools   = {},
    })
end

--- Save secrets file.
--- @param data table
function M.SaveSecrets(data)
    config_handler.SaveYaml(Config.Paths.secrets, data)
end

--- Get the password for an SSH key file.
--- @param keyfile string  Full path or basename of the key (e.g. "id_ed25519")
--- @return string|nil     Password, or nil if not stored
function M.GetKeyPassword(keyfile)
    local secrets = M.LoadSecrets()
    if not secrets.sshkeys then return nil end

    -- Try exact match first, then basename
    local basename = keyfile:match("([^/\\]+)$") or keyfile
    local entry = secrets.sshkeys[basename] or secrets.sshkeys[keyfile]

    if entry and entry.password then
        return entry.password
    end

    return nil
end

--- Store a password for an SSH key.
--- @param keyfile string   Key basename (e.g. "id_ed25519")
--- @param password string  The password
function M.SetKeyPassword(keyfile, password)
    local secrets = M.LoadSecrets()
    secrets.sshkeys = secrets.sshkeys or {}
    local basename = keyfile:match("([^/\\]+)$") or keyfile
    secrets.sshkeys[basename] = secrets.sshkeys[basename] or {}
    secrets.sshkeys[basename].password = password
    M.SaveSecrets(secrets)
end

--- Check if a tool install was already asked about.
--- @param tool string
--- @return boolean|nil  true = installed, false = declined, nil = never asked
function M.GetToolState(tool)
    local secrets = M.LoadSecrets()
    if not secrets.tools or not secrets.tools[tool] then
        return nil
    end
    if secrets.tools[tool].installed then return true end
    if secrets.tools[tool].asked then return false end
    return nil
end

--- Record tool install state.
--- @param tool string
--- @param installed boolean
function M.SetToolState(tool, installed)
    local secrets = M.LoadSecrets()
    secrets.tools = secrets.tools or {}
    secrets.tools[tool] = {
        asked = true,
        installed = installed,
    }
    M.SaveSecrets(secrets)
end

return M
