-- ============================================================================
-- con - AWS SSO Handler
-- shared/aws/sso.lua
-- ============================================================================

local config_handler = require("shared.config.handler")
local packages = require("shared.os.packages")
local Config = require("config")
local lang -- lazy load

local M = {}

local function L(key, ...)
    if not lang then lang = require("shared.lang.handler") end
    return lang.get(key, ...)
end

--- Check if AWS CLI is available.
--- @return boolean
function M.is_available()
    return packages.is_tool_installed("aws")
end

--- Load AWS config from aws.yaml.
--- @return table
function M.load_aws_config()
    return config_handler.load_or_create(Config.Paths.aws, {
        sso = {},
        codeartifact = {},
    })
end

--- Save AWS config.
--- @param data table
function M.save_aws_config(data)
    config_handler.save_yaml(Config.Paths.aws, data)
end

--- Show configured SSO profiles.
function M.show_profiles()
    local data = M.load_aws_config()
    local profiles = data.sso or {}

    if not next(profiles) then
        print(L("aws.sso_no_profiles"))
        print("")
        print("Add profiles to " .. Config.Paths.aws .. " under 'sso:'")
        print("Example:")
        print("  sso:")
        print("    my-profile:")
        print("      profile_name: my-aws-profile")
        print("      region: eu-central-1")
        return
    end

    print(L("aws.sso_select_profile"))
    print("")
    local names = {}
    for name, _ in pairs(profiles) do
        table.insert(names, name)
    end
    table.sort(names)

    for i, name in ipairs(names) do
        local profile = profiles[name]
        local region = profile.region or "—"
        print(string.format("  %d) %s (region: %s)", i, name, region))
    end
end

--- Login via AWS SSO.
--- @param profile_name string|nil  Profile name (from aws.yaml or direct AWS profile)
function M.login(profile_name)
    if not M.is_available() then
        print("AWS CLI is required. Install it first.")
        return
    end

    -- If no profile given, let user pick from configured profiles
    if not profile_name then
        local data = M.load_aws_config()
        local profiles = data.sso or {}

        if not next(profiles) then
            print(L("aws.sso_no_profiles"))
            return
        end

        local names = {}
        for name, _ in pairs(profiles) do table.insert(names, name) end
        table.sort(names)

        print(L("aws.sso_select_profile"))
        for i, name in ipairs(names) do
            print(string.format("  %d) %s", i, name))
        end
        io.write("> ")
        local sel = tonumber(io.read("*l"))
        if not sel or not names[sel] then
            print(L("general.invalid_selection"))
            return
        end

        local entry = profiles[names[sel]]
        profile_name = entry.profile_name or names[sel]
    end

    print(L("aws.sso_logging_in", profile_name))
    local cmd = "aws sso login --profile " .. profile_name
    local ok = os.execute(cmd)

    if ok == true or ok == 0 then
        print(L("aws.sso_success"))
    else
        print(L("aws.sso_failed"))
    end
end

return M
