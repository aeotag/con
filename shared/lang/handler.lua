-- ============================================================================
-- con - Language / i18n Handler
-- shared/lang/handler.lua
-- ============================================================================

local yaml = require("lyaml")
local Config = require("config")
local osdetect = require("shared.os.detect")

local M = {}

local _strings = nil   -- cached language strings
local _lang    = nil   -- current language code

-- Supported languages
local SUPPORTED = { en = true, de = true, fi = true }

--- Determine the active language.
--- Priority: per-command flag > settings.yaml > system detect > fallback "en"
--- @param cli_override string|nil  Language from --lang flag
--- @return string  Two-letter language code
function M.resolve_language(cli_override)
    if cli_override and SUPPORTED[cli_override] then
        return cli_override
    end

    -- Load from settings
    local config_handler = require("shared.config.handler")
    local settings = config_handler.load_settings()
    local configured = settings.language or "auto"

    if configured ~= "auto" and SUPPORTED[configured] then
        return configured
    end

    -- Auto-detect from system
    local sys_lang = osdetect.detect_system_language()
    if SUPPORTED[sys_lang] then
        return sys_lang
    end

    return Config.Defaults.fallback_lang
end

--- Load language strings from YAML file.
--- @param lang string  Two-letter code (en, de, fi)
--- @return table       Flat key-value table of strings
function M.load_language_file(lang)
    local path = Config.Paths.language_dir .. "/" .. lang .. ".yaml"
    local f = io.open(path, "r")
    if not f then
        -- Fallback to English if requested language file missing
        if lang ~= "en" then
            return M.load_language_file("en")
        end
        return {}
    end

    local content = f:read("*a")
    f:close()

    local ok, data = pcall(yaml.load, content)
    if not ok or type(data) ~= "table" then
        if lang ~= "en" then
            return M.load_language_file("en")
        end
        return {}
    end

    return data
end

--- Initialize the language system.
--- @param cli_override string|nil  Per-command --lang flag
function M.init(cli_override)
    _lang = M.resolve_language(cli_override)
    _strings = M.load_language_file(_lang)
end

--- Get a translated string by key.
--- Supports nested keys via dot notation: "vpn.status.active"
--- Falls back to the key itself if not found.
--- @param key string       Dot-separated key
--- @param ... any          Format arguments (string.format)
--- @return string
function M.get(key, ...)
    if not _strings then M.init() end

    -- Navigate nested tables via dot notation
    local value = _strings
    for part in key:gmatch("[^%.]+") do
        if type(value) ~= "table" then
            -- Key not found, return key name as fallback
            local args = { ... }
            if #args > 0 then
                return string.format(key, ...)
            end
            return key
        end
        value = value[part]
    end

    if type(value) == "string" then
        local args = { ... }
        if #args > 0 then
            local ok, result = pcall(string.format, value, ...)
            if ok then return result end
        end
        return value
    end

    return key
end

--- Get current language code.
--- @return string
function M.current()
    return _lang or M.resolve_language()
end

--- Set language persistently in settings.
--- @param lang string  "en", "de", "fi", or "auto"
function M.set_language(lang)
    if lang ~= "auto" and not SUPPORTED[lang] then
        print("Unsupported language: " .. lang .. ". Supported: en, de, fi, auto")
        return false
    end
    local config_handler = require("shared.config.handler")
    local settings = config_handler.load_settings()
    settings.language = lang
    config_handler.save_settings(settings)
    -- Reload
    _lang = nil
    _strings = nil
    M.init()
    print(M.get("config.lang_set", lang))
    return true
end

return M
