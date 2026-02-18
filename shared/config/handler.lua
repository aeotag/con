-- ============================================================================
-- con - YAML Config Handler (load / save / ensure)
-- shared/config/handler.lua
-- ============================================================================

local yaml = require("lyaml")
local Config = require("config")

local M = {}

--- Ensure a directory exists (mkdir -p equivalent).
--- @param path string
function M.ensure_dir(path)
    local os_name = require("shared.os.detect").detect_os()
    if os_name == "windows" then
        os.execute('mkdir "' .. path:gsub("/", "\\") .. '" 2>NUL')
    else
        os.execute("mkdir -p '" .. path .. "' 2>/dev/null")
    end
end

--- Check if a file exists.
--- @param path string
--- @return boolean
function M.file_exists(path)
    local f = io.open(path, "r")
    if f then f:close(); return true end
    return false
end

--- Load a YAML file and return parsed data.
--- @param path string  Path to the YAML file
--- @return table|nil   Parsed data, or nil on error
--- @return string|nil  Error message
function M.load_yaml(path)
    local f, err = io.open(path, "r")
    if not f then
        return nil, "Could not open file: " .. tostring(err)
    end

    local content = f:read("*a")
    f:close()

    if not content or content:match("^%s*$") then
        return {}, nil
    end

    local ok, data = pcall(yaml.load, content)
    if not ok then
        return nil, "YAML parse error: " .. tostring(data)
    end

    if type(data) ~= "table" then
        return {}, nil
    end

    return data, nil
end

--- Save data to a YAML file.
--- @param path string  Path to the YAML file
--- @param data table   Data to serialize
--- @return boolean     Success
--- @return string|nil  Error message
function M.save_yaml(path, data)
    -- Ensure parent directory exists
    local dir = path:match("(.+)/[^/]+$")
    if dir then M.ensure_dir(dir) end

    local ok, content = pcall(yaml.dump, { data })
    if not ok then
        return false, "YAML serialize error: " .. tostring(content)
    end

    local f, err = io.open(path, "w")
    if not f then
        return false, "Could not write file: " .. tostring(err)
    end

    f:write(content)
    f:close()
    return true, nil
end

--- Load a YAML config file, creating it with defaults if missing.
--- @param path string          File path
--- @param defaults table|nil   Default data if file doesn't exist
--- @return table               Loaded data
function M.load_or_create(path, defaults)
    defaults = defaults or {}

    if not M.file_exists(path) then
        M.save_yaml(path, defaults)
        return defaults
    end

    local data, err = M.load_yaml(path)
    if not data then
        print("Warning: " .. tostring(err) .. " — using defaults.")
        return defaults
    end

    return data
end

--- Initialize all config files if they don't exist (first-run / con init).
function M.init_configs()
    M.ensure_dir(Config.Paths.config_dir)
    M.ensure_dir(Config.Paths.logs)

    -- connection.yaml
    if not M.file_exists(Config.Paths.connection) then
        M.save_yaml(Config.Paths.connection, {
            default = {}
        })
    end

    -- vpn.yaml
    if not M.file_exists(Config.Paths.vpn) then
        M.save_yaml(Config.Paths.vpn, {
            mappings = {},
            -- example:
            -- mappings:
            --   office-wg:
            --     type: wireguard
            --     system_name: "wg-office"
            --   company-ovpn:
            --     type: openvpn
            --     system_name: "OpenVPN-Company"
        })
    end

    -- oneshot.yaml
    if not M.file_exists(Config.Paths.oneshot) then
        M.save_yaml(Config.Paths.oneshot, {})
    end

    -- aws.yaml
    if not M.file_exists(Config.Paths.aws) then
        M.save_yaml(Config.Paths.aws, {
            sso = {},
            codeartifact = {},
        })
    end

    -- .secrets
    if not M.file_exists(Config.Paths.secrets) then
        M.save_yaml(Config.Paths.secrets, {
            sshkeys = {},
            tools   = {},
        })
    end

    -- settings.yaml (language, defaults, etc.)
    local settings_path = Config.Paths.config_dir .. "/settings.yaml"
    if not M.file_exists(settings_path) then
        M.save_yaml(settings_path, {
            language = "auto",
            default_protocol = "ssh",
            parallel = true,
        })
    end
end

--- Load user settings (language, defaults).
--- @return table
function M.load_settings()
    local path = Config.Paths.config_dir .. "/settings.yaml"
    return M.load_or_create(path, {
        language = "auto",
        default_protocol = "ssh",
        parallel = true,
    })
end

--- Save user settings.
--- @param settings table
function M.save_settings(settings)
    local path = Config.Paths.config_dir .. "/settings.yaml"
    M.save_yaml(path, settings)
end

return M
