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
lang.init(lang_override)

-- Load modules (lazy: only when needed)
local function get_connection_handler() return require("shared.connection.handler") end
local function get_config_edit()        return require("shared.config.edit") end
local function get_config_handler()     return require("shared.config.handler") end
local function get_vpn_handler()        return require("shared.vpn.handler") end
local function get_oneshot_handler()    return require("shared.oneshot.handler") end
local function get_aws_sso()            return require("shared.aws.sso") end
local function get_aws_codeartifact()   return require("shared.aws.codeartifact") end
local function get_manpages()           return require("shared.manpages") end

--- Helper: parse named args from a position onward.
--- @param from number  Starting index in args
--- @return table       { flag = value } pairs
local function parse_opts(from)
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
local function positional_arg(from)
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
    get_manpages().show_main()
    return
end

local cmd = args[1]

-- ============================================================================
-- HELP
-- ============================================================================
if cmd == "help" or cmd == "--help" or cmd == "man" then
    local topic = args[2]
    get_manpages().show(topic)

-- ============================================================================
-- VERSION
-- ============================================================================
elseif cmd == "version" or cmd == "--version" then
    print(lang.get("general.version", Config.Version))

-- ============================================================================
-- INIT — Initialize / reset config
-- ============================================================================
elseif cmd == "init" then
    get_config_handler().init_configs()
    print(lang.get("init.setup_complete"))

-- ============================================================================
-- CONFIG — Settings management
-- ============================================================================
elseif cmd == "config" then
    if args[2] == "lang" and args[3] then
        lang.set_language(args[3])
    elseif args[2] == "lang" then
        print(lang.get("config.lang_current", lang.current()))
    else
        get_manpages().show_main()
    end

-- ============================================================================
-- SHOW — Display connections
-- ============================================================================
elseif cmd == "show" then
    local ch = get_connection_handler()
    if args[2] == "--group" and args[3] then
        ch.show_connections(args[3])
    elseif args[2] == "--all" or not args[2] then
        ch.show_connections()
    else
        get_manpages().show_main()
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
        get_connection_handler().quick_add(name, user_at_ip, group)
    else
        print("Usage: con --name <name> [--group <group>] <user@ip>")
    end

-- ============================================================================
-- --modify — Rename / move / set fields / add-remove addresses
-- ============================================================================
elseif cmd == "--modify" then
    local ce = get_config_edit()
    if args[2] == "--group" and args[3] and args[4] then
        ce.rename_group(args[3], args[4])
    elseif args[2] == "--name" and args[3] and args[4] then
        ce.rename_connection(args[3], args[4])
    elseif args[2] == "--move" and args[3] and args[4] then
        local name = args[3]
        local to_group = args[4]
        local _, from_group = ce.find_connection(name)
        if from_group then
            ce.move_connection(name, from_group, to_group)
        else
            print(lang.get("connection.not_found", name))
        end
    elseif args[2] == "--address" and args[3] and args[4] then
        -- con --modify --address <name> <ip> [--vpn <vpn>] [--type <type>] [--network <net>] [--port <port>]
        local name = args[3]
        local ip = args[4]
        local opts = parse_opts(5)
        ce.add_address(name, ip, opts)
    elseif args[2] == "--rm-address" and args[3] and args[4] then
        -- con --modify --rm-address <name> <ip> [--vpn <vpn>]
        local name = args[3]
        local ip = args[4]
        local opts = parse_opts(5)
        ce.remove_address(name, ip, opts.vpn)
    elseif args[2] == "--set" and args[3] and args[4] and args[5] then
        -- con --modify --set <name> <field> <value>
        ce.set_field(args[3], args[4], args[5])
    else
        get_manpages().show_main()
    end

-- ============================================================================
-- EDIT — Interactive edit of a connection
-- ============================================================================
elseif cmd == "edit" then
    if args[2] then
        get_config_edit().interactive_edit(args[2])
    else
        print("Usage: con edit <name>")
    end

-- ============================================================================
-- --del — Delete group or connection
-- ============================================================================
elseif cmd == "--del" then
    local ce = get_config_edit()
    if args[2] == "group" and args[3] then
        ce.delete_group(args[3])
    elseif args[2] == "name" and args[3] then
        local _, group = ce.find_connection(args[3])
        if group then
            ce.delete_connection(group, args[3])
        else
            print(lang.get("connection.not_found", args[3]))
        end
    else
        get_manpages().show_main()
    end

-- ============================================================================
-- VPN — VPN management
-- ============================================================================
elseif cmd == "vpn" then
    local vh = get_vpn_handler()
    local sub = args[2]

    if not sub or sub == "show" then
        vh.show()
    elseif sub == "up" and args[3] then
        vh.up(args[3])
    elseif sub == "down" then
        if args[3] == "--all" then
            vh.down_all()
        elseif args[3] then
            vh.down(args[3])
        else
            get_manpages().show("vpn")
        end
    elseif sub == "status" then
        vh.status()
    elseif sub == "help" or sub == "--help" or sub == "man" then
        get_manpages().show("vpn")
    else
        get_manpages().show("vpn")
    end

-- ============================================================================
-- ONS — Oneshot execution
-- ============================================================================
elseif cmd == "ons" then
    if args[2] == "help" or args[2] == "--help" or args[2] == "man" then
        get_manpages().show("oneshot")
    elseif args[2] then
        local oneshot_name = args[2]
        local opts = parse_opts(3)
        get_oneshot_handler().run_oneshot(oneshot_name, opts)
    else
        get_manpages().show("oneshot")
    end

-- ============================================================================
-- AWS — AWS operations
-- ============================================================================
elseif cmd == "aws" then
    local sub = args[2]

    if sub == "sso" then
        local sso = get_aws_sso()
        if args[3] == "login" then
            local profile = nil
            if args[4] == "--profile" and args[5] then
                profile = args[5]
            end
            sso.login(profile)
        elseif args[3] == "show" then
            sso.show_profiles()
        else
            get_manpages().show("aws")
        end

    elseif sub == "codeartifact" then
        local ca = get_aws_codeartifact()
        if args[3] == "login" then
            local repo = nil
            if args[4] == "--repo" and args[5] then
                repo = args[5]
            end
            ca.login(repo)
        elseif args[3] == "show" then
            ca.show_repos()
        else
            get_manpages().show("aws")
        end

    elseif sub == "help" or sub == "--help" or sub == "man" then
        get_manpages().show("aws")
    else
        get_manpages().show("aws")
    end

-- ============================================================================
-- DIRECT CONNECTION — `con <name>` connects to a saved device
-- ============================================================================
elseif cmd and not cmd:match("^%-") then
    -- Ensure configs exist (auto-init on first use)
    local ch_mod = get_config_handler()
    if not ch_mod.file_exists(Config.Paths.connection) then
        ch_mod.init_configs()
    end

    get_connection_handler().connect(cmd)

-- ============================================================================
-- UNKNOWN
-- ============================================================================
else
    print(lang.get("general.unknown_command"))
    get_manpages().show_main()
end
