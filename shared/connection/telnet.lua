-- ============================================================================
-- con - Telnet Connection Module
-- shared/connection/telnet.lua
-- ============================================================================

local packages = require("shared.os.packages")
local osdetect = require("shared.os.detect")

local M = {}

--- Check if telnet is installed.
--- @return boolean
function M.IsAvailable()
    return packages.IsToolInstalled("telnet")
end

--- Ensure telnet is installed, prompt to install if not.
--- @return boolean  true if telnet is now available
function M.EnsureAvailable()
    if M.IsAvailable() then return true end
    return packages.PromptInstall("telnet")
end

--- Build a telnet command string.
--- @param ip string     IP or hostname
--- @param port number|nil   Port (default 23)
--- @return string
function M.BuildCommand(ip, port)
    port = port or 23
    return "telnet " .. ip .. " " .. tostring(port)
end

--- Build a telnet command for sending a command (via expect-style or echo pipe).
--- Note: Telnet automation is limited — for oneshot use, we pipe commands via stdin.
--- @param ip string
--- @param port number|nil
--- @param remote_cmd string
--- @return string
function M.BuildExecCommand(ip, port, remote_cmd)
    port = port or 23
    -- Use a simple echo-pipe approach. For complex telnet automation,
    -- users should use expect scripts configured as oneshot commands.
    local escaped_cmd = remote_cmd:gsub('"', '\\"')
    return string.format(
        '(echo "%s"; sleep 2; echo "exit") | telnet %s %d',
        escaped_cmd, ip, tostring(port)
    )
end

--- Connect interactively via telnet.
--- @param ip string
--- @param port number|nil
function M.Connect(ip, port)
    if not M.EnsureAvailable() then
        print("Telnet is not available.")
        return
    end
    local cmd = M.BuildCommand(ip, port)
    os.execute(cmd)
end

--- Test if a host:port is reachable (TCP connect test).
--- @param ip string
--- @param port number|nil
--- @return boolean
function M.Ping(ip, port)
    port = port or 23
    local os_name = osdetect.DetectOs()
    local cmd
    if os_name == "windows" then
        cmd = string.format(
            'powershell -NoProfile -Command "Test-NetConnection -ComputerName %s -Port %d -InformationLevel Quiet" 2>NUL',
            ip, port
        )
    else
        -- Use bash /dev/tcp or nc for TCP check
        cmd = string.format(
            "nc -z -w 2 %s %d > /dev/null 2>&1",
            ip, port
        )
    end
    local ok = os.execute(cmd)
    return ok == true or ok == 0
end

return M
