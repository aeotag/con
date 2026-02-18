-- ============================================================================
-- con - Main CLI Router
-- main.lua
-- ============================================================================

-- Resolve install directory from this script's location
local script_path = debug.getinfo(1, "S").source:match("^@(.+)/main%.lua$") or "."
local home = os.getenv("HOME") or os.getenv("USERPROFILE") or "~"

-- Set package paths BEFORE any require
package.path = script_path .. "/?.lua"
    .. ";" .. script_path .. "/?/init.lua"
    .. ";" .. home .. "/.luarocks/share/lua/5.4/?.lua"
    .. ";" .. home .. "/.luarocks/share/lua/5.4/?/init.lua"
    .. ";" .. package.path

package.cpath = home .. "/.luarocks/lib/lua/5.4/?.so"
    .. ";" .. home .. "/.luarocks/lib/lua/5.4/?.dll"
    .. ";" .. package.cpath

local Config = require("config")

-- Initialize language system (check for --lang flag early)
local args = { ... }
local lang_override = nil
local filtered_args = {}

-- Extract --lang flag before processing other args
local i = 1
while i <= #args do
    if args[i] == "--lang" and args[i + 1] then
        lang_override = args[i + 1]
        i = i + 2
    else
        table.insert(filtered_args, args[i])
        i = i + 1
    end
end
args = filtered_args

-- Initialize language
local lang = require("shared.lang.handler")
lang.Init(lang_override)

-- Load modules (lazy: only when needed)
local function GetConnectionHandler() return require("shared.connection.handler") end
local function GetConfigEdit()        return require("shared.config.edit") end
local function GetConfigHandler()     return require("shared.config.handler") end
local function GetVpnHandler()        return require("shared.vpn.handler") end
local function GetOneshotHandler()    return require("shared.oneshot.handler") end
local function GetAwsSso()            return require("shared.aws.sso") end
local function GetAwsCodeartifact()   return require("shared.aws.codeartifact") end
local function GetManpages()           return require("shared.manpages") end

--- Helper: parse named args from a position onward.
--- @param from number  Starting index in args
--- @return table       { flag = value } pairs
local function ParseOpts(from)
    local opts = {}
    local j = from
    while j <= #args do
        local key = args[j]:match("^%-%-(.+)")
        if key then
            if args[j + 1] and not args[j + 1]:match("^%-%-") then
                opts[key] = args[j + 1]
                j = j + 2
            else
                opts[key] = true
                j = j + 1
            end
        else
            j = j + 1
        end
    end
    return opts
end

--- Helper: find positional arg (first non-flag).
--- @param from number  Starting index
--- @return string|nil
local function PositionalArg(from)
    for j = from, #args do
        if not args[j]:match("^%-%-") then
            return args[j]
        end
    end
    return nil
end

-- ============================================================================
-- NO ARGS → show help
-- ============================================================================
if #args == 0 then
    GetManpages().ShowMain()
    return
end

local cmd = args[1]

-- ============================================================================
-- HELP
-- ============================================================================
if cmd == "help" or cmd == "--help" or cmd == "man" then
    local topic = args[2]
    GetManpages().Show(topic)

-- ============================================================================
-- VERSION
-- ============================================================================
elseif cmd == "version" or cmd == "--version" then
    print(lang.Get("general.version", Config.Version))

-- ============================================================================
-- INIT — Initialize / reset config
-- ============================================================================
elseif cmd == "init" then
    GetConfigHandler().InitConfigs()
    print(lang.Get("init.setup_complete"))

-- ============================================================================
-- CONFIG — Settings management
-- ============================================================================
elseif cmd == "config" then
    if args[2] == "lang" and args[3] then
        lang.SetLanguage(args[3])
    elseif args[2] == "lang" then
        print(lang.Get("config.lang_current", lang.Current()))
    else
        GetManpages().ShowMain()
    end

-- ============================================================================
-- SHOW — Display connections
-- ============================================================================
elseif cmd == "show" then
    local ch = GetConnectionHandler()
    if args[2] == "--group" and args[3] then
        ch.ShowConnections(args[3])
    elseif args[2] == "--all" or not args[2] then
        ch.ShowConnections()
    else
        GetManpages().ShowMain()
    end

-- ============================================================================
-- --name — Quick-add connection
-- ============================================================================
elseif cmd == "--name" and args[2] then
    local name = args[2]
    -- Find the user@ip (last positional arg that contains @)
    local user_at_ip = nil
    local group = "default"

    for j = 3, #args do
        if args[j] == "--group" and args[j + 1] then
            group = args[j + 1]
        elseif args[j]:find("@") then
            user_at_ip = args[j]
        end
    end

    if user_at_ip then
        GetConnectionHandler().QuickAdd(name, user_at_ip, group)
    else
        print("Usage: con --name <name> [--group <group>] <user@ip>")
    end

-- ============================================================================
-- --modify — Rename / move / set fields / add-remove addresses
-- ============================================================================
elseif cmd == "--modify" then
    local ce = GetConfigEdit()
    if args[2] == "--group" and args[3] and args[4] then
        ce.RenameGroup(args[3], args[4])
    elseif args[2] == "--name" and args[3] and args[4] then
        ce.RenameConnection(args[3], args[4])
    elseif args[2] == "--move" and args[3] and args[4] then
        local name = args[3]
        local to_group = args[4]
        local _, from_group = ce.FindConnection(name)
        if from_group then
            ce.MoveConnection(name, from_group, to_group)
        else
            print(lang.Get("connection.not_found", name))
        end
    elseif args[2] == "--address" and args[3] and args[4] then
        -- con --modify --address <name> <ip> [--vpn <vpn>] [--type <type>] [--network <net>] [--port <port>]
        local name = args[3]
        local ip = args[4]
        local opts = ParseOpts(5)
        ce.AddAddress(name, ip, opts)
    elseif args[2] == "--rm-address" and args[3] and args[4] then
        -- con --modify --rm-address <name> <ip> [--vpn <vpn>]
        local name = args[3]
        local ip = args[4]
        local opts = ParseOpts(5)
        ce.RemoveAddress(name, ip, opts.vpn)
    elseif args[2] == "--set" and args[3] and args[4] and args[5] then
        -- con --modify --set <name> <field> <value>
        ce.SetField(args[3], args[4], args[5])
    else
        GetManpages().ShowMain()
    end

-- ============================================================================
-- EDIT — Interactive edit of a connection
-- ============================================================================
elseif cmd == "edit" then
    if args[2] then
        GetConfigEdit().InteractiveEdit(args[2])
    else
        print("Usage: con edit <name>")
    end

-- ============================================================================
-- --del — Delete group or connection
-- ============================================================================
elseif cmd == "--del" then
    local ce = GetConfigEdit()
    if args[2] == "group" and args[3] then
        ce.DeleteGroup(args[3])
    elseif args[2] == "name" and args[3] then
        local _, group = ce.FindConnection(args[3])
        if group then
            ce.DeleteConnection(group, args[3])
        else
            print(lang.Get("connection.not_found", args[3]))
        end
    else
        GetManpages().ShowMain()
    end

-- ============================================================================
-- VPN — VPN management
-- ============================================================================
elseif cmd == "vpn" then
    local vh = GetVpnHandler()
    local sub = args[2]

    if not sub or sub == "show" then
        vh.Show()
    elseif sub == "up" and args[3] then
        vh.Up(args[3])
    elseif sub == "down" then
        if args[3] == "--all" then
            vh.DownAll()
        elseif args[3] then
            vh.Down(args[3])
        else
            GetManpages().Show("vpn")
        end
    elseif sub == "status" then
        vh.Status()
    elseif sub == "help" or sub == "--help" or sub == "man" then
        GetManpages().Show("vpn")
    else
        GetManpages().Show("vpn")
    end

-- ============================================================================
-- ONS — Oneshot execution
-- ============================================================================
elseif cmd == "ons" then
    if args[2] == "help" or args[2] == "--help" or args[2] == "man" then
        GetManpages().Show("oneshot")
    elseif args[2] then
        local oneshot_name = args[2]
        local opts = ParseOpts(3)
        GetOneshotHandler().RunOneshot(oneshot_name, opts)
    else
        GetManpages().Show("oneshot")
    end

-- ============================================================================
-- AWS — AWS operations
-- ============================================================================
elseif cmd == "aws" then
    local sub = args[2]

    if sub == "sso" then
        local sso = GetAwsSso()
        if args[3] == "login" then
            local profile = nil
            if args[4] == "--profile" and args[5] then
                profile = args[5]
            end
            sso.Login(profile)
        elseif args[3] == "show" then
            sso.ShowProfiles()
        else
            GetManpages().Show("aws")
        end

    elseif sub == "codeartifact" then
        local ca = GetAwsCodeartifact()
        if args[3] == "login" then
            local repo = nil
            if args[4] == "--repo" and args[5] then
                repo = args[5]
            end
            ca.Login(repo)
        elseif args[3] == "show" then
            ca.ShowRepos()
        else
            GetManpages().Show("aws")
        end

    elseif sub == "help" or sub == "--help" or sub == "man" then
        GetManpages().Show("aws")
    else
        GetManpages().Show("aws")
    end

-- ============================================================================
-- DIRECT CONNECTION — `con <name>` connects to a saved device
-- ============================================================================
elseif cmd and not cmd:match("^%-") then
    -- Ensure configs exist (auto-init on first use)
    local ch_mod = GetConfigHandler()
    if not ch_mod.FileExists(Config.Paths.connection) then
        ch_mod.InitConfigs()
    end

    GetConnectionHandler().Connect(cmd)

-- ============================================================================
-- UNKNOWN
-- ============================================================================
else
    print(lang.Get("general.unknown_command"))
    GetManpages().ShowMain()
end
