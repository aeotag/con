-- ============================================================================
-- con - Manpages / Help Display
-- shared/manpages.lua
-- ============================================================================

local lang -- lazy load

local M = {}

local function L(key, ...)
    if not lang then lang = require("shared.lang.handler") end
    return lang.get(key, ...)
end

--- Show main help.
function M.show_main()
    print(L("help.main"))
end

--- Show VPN help.
function M.show_vpn()
    print(L("help.vpn"))
end

--- Show oneshot help.
function M.show_oneshot()
    print(L("help.oneshot"))
end

--- Show AWS help.
function M.show_aws()
    print(L("help.aws"))
end

--- Show help for a specific topic.
--- @param topic string|nil
function M.show(topic)
    if not topic or topic == "main" or topic == "" then
        M.show_main()
    elseif topic == "vpn" then
        M.show_vpn()
    elseif topic == "ons" or topic == "oneshot" then
        M.show_oneshot()
    elseif topic == "aws" then
        M.show_aws()
    else
        print("No help available for: " .. topic)
        M.show_main()
    end
end

return M
