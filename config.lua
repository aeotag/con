-- ============================================================================
-- con - Connection Manager
-- config.lua - Core configuration
-- ============================================================================

local Config = {}

-- ---------------------------------------------------------------------------
-- Paths (XDG-style: configs live in ~/.config/con/)
-- ---------------------------------------------------------------------------
local home = os.getenv("HOME") or os.getenv("USERPROFILE") or "~"
local config_dir = home .. "/.config/con"

Config.Paths = {
    config_dir  = config_dir,
    connection  = config_dir .. "/connection.yaml",
    vpn         = config_dir .. "/vpn.yaml",
    oneshot     = config_dir .. "/oneshot.yaml",
    aws         = config_dir .. "/aws.yaml",
    secrets     = config_dir .. "/.secrets",
    logs        = config_dir .. "/logs",
    language_dir = nil, -- set below after we know install_dir
}

-- install_dir is where the lua source lives (~/repos/con)
-- we derive it from the location of this config.lua file
local info = debug.getinfo(1, "S")
local install_dir = info.source:match("^@(.+)/config%.lua$") or "."
Config.Paths.install_dir = install_dir
Config.Paths.language_dir = install_dir .. "/language"

-- ---------------------------------------------------------------------------
-- Lua package paths (luarocks + project modules)
-- ---------------------------------------------------------------------------
package.path = package.path
    .. ";" .. install_dir .. "/?.lua"
    .. ";" .. install_dir .. "/?/init.lua"
    .. ";" .. home .. "/.luarocks/share/lua/5.4/?.lua"
    .. ";" .. home .. "/.luarocks/share/lua/5.4/?/init.lua"

package.cpath = package.cpath
    .. ";" .. home .. "/.luarocks/lib/lua/5.4/?.so"
    .. ";" .. home .. "/.luarocks/lib/lua/5.4/?.dll"

-- ---------------------------------------------------------------------------
-- Defaults
-- ---------------------------------------------------------------------------
Config.Defaults = {
    protocol        = "ssh",        -- ssh | telnet | tunnel
    language        = "auto",       -- auto | en | de | fi
    fallback_lang   = "en",
    parallel        = true,         -- oneshot default execution mode
}

-- ---------------------------------------------------------------------------
-- Debug (future use)
-- ---------------------------------------------------------------------------
Config.Debug = {
    enabled  = false,
    log_dir  = config_dir .. "/logs/debug",
}

-- ---------------------------------------------------------------------------
-- Ask prompts - control interactive behavior
-- ---------------------------------------------------------------------------
Config.Ask = {
    active_vpn      = true,   -- ask if active VPN should be used
    create_missing  = true,   -- ask to create missing connections
}

-- ---------------------------------------------------------------------------
-- Version
-- ---------------------------------------------------------------------------
Config.Version = "0.1.0"
Config.Name    = "con"

return Config
