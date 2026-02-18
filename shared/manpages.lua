-- ============================================================================
-- con - Manpages / Help Display
-- shared/manpages.lua
-- ============================================================================

local lang -- lazy load

local M = {}

local function L(key, ...)
    if not lang then lang = require("shared.lang.handler") end
    return lang.Get(key, ...)
end

--- Show main help.
function M.ShowMain()
    print(L("help.main"))
end

--- Show VPN help.
function M.ShowVpn()
    print(L("help.vpn"))
end

--- Show oneshot help.
function M.ShowOneshot()
    print(L("help.oneshot"))
end

--- Show AWS help.
function M.ShowAws()
    print(L("help.aws"))
end

--- Show help for a specific topic.
--- @param topic string|nil
function M.Show(topic)
    if not topic or topic == "main" or topic == "" then
        M.ShowMain()
    elseif topic == "vpn" then
        M.ShowVpn()
    elseif topic == "ons" or topic == "oneshot" then
        M.ShowOneshot()
    elseif topic == "aws" then
        M.ShowAws()
    else
        print("No help available for: " .. topic)
        M.ShowMain()
    end
end

return M
