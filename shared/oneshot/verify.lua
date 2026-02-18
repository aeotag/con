-- ============================================================================
-- con - Oneshot Verify (log analysis / regex check system)
-- shared/oneshot/verify.lua
-- ============================================================================

local lang -- lazy load

local M = {}

local function L(key, ...)
    if not lang then lang = require("shared.lang.handler") end
    return lang.Get(key, ...)
end

--- Read a log file and return its lines.
--- @param path string
--- @return table|nil  Array of lines
function M.ReadLog(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local lines = {}
    for line in f:lines() do
        table.insert(lines, line)
    end
    f:close()
    return lines
end

--- Get the last N lines of a log.
--- @param lines table   Array of lines
--- @param n number      Number of lines
--- @return table
function M.Tail(lines, n)
    if #lines <= n then return lines end
    local result = {}
    for i = #lines - n + 1, #lines do
        table.insert(result, lines[i])
    end
    return result
end

--- Search log lines for a regex pattern and return matching lines + context after match.
--- @param lines table         Array of log lines
--- @param pattern string      Lua pattern to search for
--- @param show_after boolean  If true, show all lines from the first match onward
--- @return table              Array of { line_num, text } for matches
--- @return table              Array of lines from first match onward (if show_after)
function M.Search(lines, pattern, show_after)
    local matches = {}
    local first_match_idx = nil

    for i, line in ipairs(lines) do
        if line:find(pattern) then
            table.insert(matches, { line_num = i, text = line })
            if not first_match_idx then
                first_match_idx = i
            end
        end
    end

    local after_lines = {}
    if show_after and first_match_idx then
        for i = first_match_idx, #lines do
            table.insert(after_lines, lines[i])
        end
    end

    return matches, after_lines
end

--- Verify a single log file against a verify configuration.
--- @param log_path string     Path to the log file
--- @param verify_config table  { search, show_after_match, tail, expect }
--- @return boolean            passed
--- @return table              details = { matched_lines, tail_lines, error_block }
function M.VerifyLog(log_path, verify_config)
    local lines = M.ReadLog(log_path)
    if not lines then
        return false, { error = "Could not read log file: " .. log_path }
    end

    local details = {
        total_lines = #lines,
        matched_lines = {},
        tail_lines = {},
        error_block = {},
    }

    -- Tail: show last N lines
    if verify_config.tail then
        details.tail_lines = M.Tail(lines, verify_config.tail)
    end

    -- Search: find pattern and optionally show everything after
    if verify_config.search then
        local matches, after = M.Search(
            lines,
            verify_config.search,
            verify_config.show_after_match
        )
        details.matched_lines = matches
        details.error_block = after
    end

    -- Expect: check if a keyword appears (pass/fail)
    local passed = true
    if verify_config.expect then
        local found = false
        -- Check in tail lines if we have them, otherwise check all lines
        local check_lines = (#details.tail_lines > 0) and details.tail_lines or lines
        for _, line in ipairs(check_lines) do
            if line:lower():find(verify_config.expect:lower()) then
                found = true
                break
            end
        end
        if not found then passed = false end
    end

    -- If search pattern was found, that usually means failure
    -- (e.g. searching for "AssertionError" means test failed)
    if verify_config.search and #details.matched_lines > 0 then
        -- If expect is also set, we use expect as the pass criteria
        -- If expect is NOT set, finding the search pattern = failure
        if not verify_config.expect then
            passed = false
        end
    end

    return passed, details
end

--- Verify all logs for a oneshot run and print summary.
--- @param log_files table       { device_name = log_path, ... }
--- @param verify_config table   Verify configuration from oneshot YAML
--- @param cli_overrides table|nil  { tail, search } from CLI flags
function M.VerifyAll(log_files, verify_config, cli_overrides)
    -- Merge CLI overrides
    local vc = {}
    for k, v in pairs(verify_config or {}) do vc[k] = v end
    if cli_overrides then
        if cli_overrides.tail   then vc.tail   = cli_overrides.tail end
        if cli_overrides.search then vc.search = cli_overrides.search end
    end

    if not next(log_files) then
        print(L("verify.no_logs"))
        return
    end

    print("")
    print(L("verify.header"))
    print(string.rep("─", 50))

    local total = 0
    local failures = 0

    -- Sort device names for consistent output
    local names = {}
    for name, _ in pairs(log_files) do table.insert(names, name) end
    table.sort(names)

    for _, device_name in ipairs(names) do
        local log_path = log_files[device_name]
        total = total + 1

        local passed, details = M.VerifyLog(log_path, vc)

        if passed then
            print(L("verify.passed", device_name))
        else
            failures = failures + 1
            print(L("verify.failed", device_name))

            -- Show error details
            if details.error then
                print("   " .. details.error)
            end

            -- Show error block (lines from search match onward)
            if details.error_block and #details.error_block > 0 then
                print(L("verify.error_details"))
                for _, line in ipairs(details.error_block) do
                    print("   " .. line)
                end
            end

            -- Show tail lines if no error block
            if (not details.error_block or #details.error_block == 0) and
               details.tail_lines and #details.tail_lines > 0 then
                print(L("verify.error_details"))
                for _, line in ipairs(details.tail_lines) do
                    print("   " .. line)
                end
            end
        end
    end

    print(string.rep("─", 50))
    if failures == 0 then
        print(L("verify.summary_all_pass", total))
    else
        print(L("verify.summary_failures", failures, total))
    end
    print("")
end

return M
