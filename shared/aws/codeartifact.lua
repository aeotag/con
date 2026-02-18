-- ============================================================================
-- con - AWS CodeArtifact Handler
-- shared/aws/codeartifact.lua
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

--- Load AWS config.
--- @return table
function M.load_aws_config()
    return config_handler.load_or_create(Config.Paths.aws, {
        sso = {},
        codeartifact = {},
    })
end

--- Show configured CodeArtifact repositories.
function M.show_repos()
    local data = M.load_aws_config()
    local repos = data.codeartifact or {}

    if not next(repos) then
        print(L("aws.ca_no_repos"))
        print("")
        print("Add repos to " .. Config.Paths.aws .. " under 'codeartifact:'")
        print("Example:")
        print("  codeartifact:")
        print("    my-repo:")
        print("      domain: my-domain")
        print("      domain_owner: '123456789012'")
        print("      repository: my-repo")
        print("      region: eu-central-1")
        print("      profile: my-aws-profile")
        print("      tool: pip           # pip | npm | twine | maven | gradle")
        return
    end

    print(L("aws.ca_select_repo"))
    print("")
    local names = {}
    for name, _ in pairs(repos) do
        table.insert(names, name)
    end
    table.sort(names)

    for i, name in ipairs(names) do
        local repo = repos[name]
        print(string.format("  %d) %s (domain: %s, tool: %s)",
            i, name, repo.domain or "—", repo.tool or "pip"))
    end
end

--- Authenticate against a CodeArtifact repository.
--- @param repo_name string|nil  Repository name from aws.yaml
function M.login(repo_name)
    if not packages.is_tool_installed("aws") then
        print("AWS CLI is required. Install it first.")
        return
    end

    local data = M.load_aws_config()
    local repos = data.codeartifact or {}

    -- If no repo given, let user pick
    if not repo_name then
        if not next(repos) then
            print(L("aws.ca_no_repos"))
            return
        end

        local names = {}
        for name, _ in pairs(repos) do table.insert(names, name) end
        table.sort(names)

        print(L("aws.ca_select_repo"))
        for i, name in ipairs(names) do
            print(string.format("  %d) %s", i, name))
        end
        io.write("> ")
        local sel = tonumber(io.read("*l"))
        if not sel or not names[sel] then
            print(L("general.invalid_selection"))
            return
        end
        repo_name = names[sel]
    end

    local entry = repos[repo_name]
    if not entry then
        print("Repository '" .. repo_name .. "' not found in config.")
        return
    end

    -- Build the codeartifact login command
    local tool = entry.tool or "pip"
    local parts = {
        "aws", "codeartifact", "login",
        "--tool", tool,
        "--domain", entry.domain,
        "--repository", entry.repository or repo_name,
    }

    if entry.domain_owner then
        table.insert(parts, "--domain-owner")
        table.insert(parts, entry.domain_owner)
    end
    if entry.region then
        table.insert(parts, "--region")
        table.insert(parts, entry.region)
    end
    if entry.profile then
        table.insert(parts, "--profile")
        table.insert(parts, entry.profile)
    end

    local cmd = table.concat(parts, " ")
    print(L("aws.ca_logging_in", repo_name))

    local ok = os.execute(cmd)
    if ok == true or ok == 0 then
        print(L("aws.ca_success"))
    else
        print(L("aws.ca_failed"))
    end
end

return M
