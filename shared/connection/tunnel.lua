-- ============================================================================
-- con - AWS Secure Tunnel (SSM Session Manager / Port Forwarding / EC2 IC)
-- shared/connection/tunnel.lua
-- ============================================================================

local packages = require("shared.os.packages")

local M = {}

-- Tunnel types
M.TYPE_SSM_SESSION   = "ssm-session"
M.TYPE_SSM_PORT_FWD  = "ssm-port-forward"
M.TYPE_EC2_IC        = "ec2-instance-connect"

--- Check if AWS CLI is installed.
--- @return boolean
function M.is_aws_cli_available()
    return packages.is_tool_installed("aws")
end

--- Check if the SSM plugin is installed.
--- @return boolean
function M.is_ssm_plugin_available()
    return packages.is_tool_installed("session-manager-plugin")
end

--- Ensure required tools are available.
--- @return boolean
function M.ensure_available()
    if not M.is_aws_cli_available() then
        print("AWS CLI is required for secure tunnel connections.")
        if not packages.prompt_install("awscli") then
            return false
        end
    end
    if not M.is_ssm_plugin_available() then
        print("AWS SSM Session Manager Plugin is required.")
        print("Install instructions: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html")
        return false
    end
    return true
end

--- Build an SSM Session Manager command.
--- @param instance_id string  EC2 instance ID (e.g. "i-0abc123def456")
--- @param profile string|nil  AWS profile name
--- @param region string|nil   AWS region
--- @return string
function M.build_ssm_session_command(instance_id, profile, region)
    local parts = { "aws", "ssm", "start-session" }
    table.insert(parts, "--target " .. instance_id)
    if profile then table.insert(parts, "--profile " .. profile) end
    if region  then table.insert(parts, "--region " .. region) end
    return table.concat(parts, " ")
end

--- Build an SSM Port Forwarding command (for SSH-over-SSM).
--- @param instance_id string
--- @param remote_port number   Port on the remote instance (usually 22)
--- @param local_port number    Local port to bind
--- @param profile string|nil
--- @param region string|nil
--- @return string
function M.build_ssm_port_forward_command(instance_id, remote_port, local_port, profile, region)
    local parts = { "aws", "ssm", "start-session" }
    table.insert(parts, "--target " .. instance_id)
    table.insert(parts, string.format(
        '--document-name AWS-StartPortForwardingSession --parameters \'{"portNumber":["%d"],"localPortNumber":["%d"]}\'',
        remote_port, local_port
    ))
    if profile then table.insert(parts, "--profile " .. profile) end
    if region  then table.insert(parts, "--region " .. region) end
    return table.concat(parts, " ")
end

--- Build an EC2 Instance Connect command (push SSH key + connect).
--- @param instance_id string
--- @param user string
--- @param profile string|nil
--- @param region string|nil
--- @return string
function M.build_ec2_ic_command(instance_id, user, profile, region)
    local parts = { "aws", "ec2-instance-connect", "ssh" }
    table.insert(parts, "--instance-id " .. instance_id)
    table.insert(parts, "--os-user " .. user)
    if profile then table.insert(parts, "--profile " .. profile) end
    if region  then table.insert(parts, "--region " .. region) end
    return table.concat(parts, " ")
end

--- Build a remote command execution via SSM send-command.
--- @param instance_id string
--- @param remote_cmd string
--- @param profile string|nil
--- @param region string|nil
--- @return string
function M.build_exec_command(instance_id, remote_cmd, profile, region)
    local escaped = remote_cmd:gsub('"', '\\"')
    local parts = { "aws", "ssm", "send-command" }
    table.insert(parts, "--instance-ids " .. instance_id)
    table.insert(parts, string.format(
        '--document-name "AWS-RunShellScript" --parameters \'commands=["%s"]\'',
        escaped
    ))
    table.insert(parts, "--output text")
    if profile then table.insert(parts, "--profile " .. profile) end
    if region  then table.insert(parts, "--region " .. region) end
    return table.concat(parts, " ")
end

--- Connect interactively via the appropriate tunnel method.
--- @param conn_data table  Connection data with tunnel-specific fields
function M.connect(conn_data)
    if not M.ensure_available() then return end

    local tunnel_type = conn_data.tunnel_type or M.TYPE_SSM_SESSION
    local instance_id = conn_data.instance_id
    local profile = conn_data.aws_profile
    local region = conn_data.aws_region
    local user = conn_data.user or "ec2-user"

    if not instance_id then
        print("Error: No instance_id configured for tunnel connection.")
        return
    end

    local cmd
    if tunnel_type == M.TYPE_SSM_SESSION then
        cmd = M.build_ssm_session_command(instance_id, profile, region)
    elseif tunnel_type == M.TYPE_SSM_PORT_FWD then
        local remote_port = conn_data.remote_port or 22
        local local_port = conn_data.local_port or 9999
        cmd = M.build_ssm_port_forward_command(instance_id, remote_port, local_port, profile, region)
    elseif tunnel_type == M.TYPE_EC2_IC then
        cmd = M.build_ec2_ic_command(instance_id, user, profile, region)
    else
        print("Unknown tunnel type: " .. tostring(tunnel_type))
        return
    end

    os.execute(cmd)
end

return M
