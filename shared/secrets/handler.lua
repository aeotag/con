-- ============================================================================
-- con - Secrets Handler (SSH key passwords, tool install state)
-- shared/secrets/handler.lua
-- ============================================================================

local config_handler = require("shared.config.handler")
local Config = require("config")

local M = {}

--- Load secrets file.
--- @return table
function M.load_secrets()
    return config_handler.load_or_create(Config.Paths.secrets, {
        sshkeys = {},
        tools   = {},
    })
end

--- Save secrets file.
--- @param data table
function M.save_secrets(data)
    config_handler.save_yaml(Config.Paths.secrets, data)
end

--- Get the password for an SSH key file.
--- @param keyfile string  Full path or basename of the key (e.g. "id_ed25519")
--- @return string|nil     Password, or nil if not stored
function M.get_key_password(keyfile)
    local secrets = M.load_secrets()
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
function M.set_key_password(keyfile, password)
    local secrets = M.load_secrets()
    secrets.sshkeys = secrets.sshkeys or {}
    local basename = keyfile:match("([^/\\]+)$") or keyfile
    secrets.sshkeys[basename] = secrets.sshkeys[basename] or {}
    secrets.sshkeys[basename].password = password
    M.save_secrets(secrets)
end

--- Check if a tool install was already asked about.
--- @param tool string
--- @return boolean|nil  true = installed, false = declined, nil = never asked
function M.get_tool_state(tool)
    local secrets = M.load_secrets()
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
function M.set_tool_state(tool, installed)
    local secrets = M.load_secrets()
    secrets.tools = secrets.tools or {}
    secrets.tools[tool] = {
        asked = true,
        installed = installed,
    }
    M.save_secrets(secrets)
end

return M
