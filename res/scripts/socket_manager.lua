--[[
    Socket Manager - File-based IPC (Fallback)
    
    Replaces native socket due to macOS linking issues.
    Uses atomic file I/O to communicate with socket_daemon.py
    
    Protocol: 
    1. Write request to /tmp/tf2_llm_request.json
    2. Wait for response in /tmp/tf2_llm_response.json
]]

local M = {}

-- Paths matching socket_daemon.py file_ipc_watcher
local REQUEST_FILE = "/tmp/tf2_llm_request.json"
local RESPONSE_FILE = "/tmp/tf2_llm_response.json"

-- Logging
local function log(msg)
    local f = io.open("/tmp/tf2_socket_manager_native.log", "a")
    if f then
        f:write(os.date("%H:%M:%S") .. " " .. tostring(msg) .. "\n")
        f:close()
    end
end

-- JSON helper
local json = nil
local function get_json()
    if json then return json end
    local success, mod = pcall(require, "json")
    if success then json = mod end
    return json
end

-- Pending request state for async communication
local pending_request = nil

-- Helper to write a request (non-blocking)
local function write_request(cmd_str)
    log("WRITE_REQ: " .. cmd_str:sub(1,30))

    local f, err1 = io.open(REQUEST_FILE, "w")
    if not f then
        log("Failed to open request file: " .. tostring(err1))
        return false
    end
    f:write(cmd_str)
    f:close()
    pending_request = cmd_str
    return true
end

-- Helper to check for response (non-blocking)
local function check_response()
    local rf = io.open(RESPONSE_FILE, "r")
    if not rf then
        return nil  -- No response yet
    end

    local content = rf:read("*a")
    rf:close()

    if content and #content > 0 then
        os.remove(RESPONSE_FILE)
        log("GOT_RESP: " .. content:sub(1,80))
        pending_request = nil
        return content
    end

    return nil  -- File exists but empty
end

-- Combined send and receive (for single-call API)
local function send_request(cmd_str)
    local ok, err = pcall(function()
        log("SEND_V5: " .. cmd_str:sub(1,30))

        -- Clear any stale response first (ignore errors)
        pcall(os.remove, RESPONSE_FILE)

        -- Write request
        local f = io.open(REQUEST_FILE, "w")
        if not f then
            log("Failed to write request")
            return nil
        end
        f:write(cmd_str)
        f:close()
        log("REQ_WRITTEN")

        -- Quick check loop (limited iterations to stay within frame budget)
        local max_quick_checks = 1000
        log("LOOP_START")
        for i = 1, max_quick_checks do
            local rf = io.open(RESPONSE_FILE, "r")
            if rf then
                local content = rf:read("*a")
                rf:close()
                if content and #content > 0 then
                    pcall(os.remove, RESPONSE_FILE)
                    log("GOT i=" .. i .. ": " .. content:sub(1,80))
                    return content
                end
            end
        end

        log("NO_RESP after " .. max_quick_checks)
        return nil
    end)

    if not ok then
        log("ERROR: " .. tostring(err))
        return nil
    end
    return err  -- 'err' is actually the return value from pcall
end

function M.poll()
    local resp_str = send_request("POLL")
    if not resp_str then return nil end

    local j = get_json()
    if not j then return nil end

    local success, resp = pcall(j.decode, resp_str)
    if success and resp and resp.status == "ok" and resp.command then
        log("Got command via file")
        return resp.command
    end

    return nil
end

function M.send_result(result)
    local j = get_json()
    local content
    if type(result) == "table" and j then
        content = j.encode(result)
    else
        content = tostring(result)
    end

    local req = "RESULT:" .. content
    local resp_str = send_request(req)
    
    if resp_str then
        log("Sent result via file")
        return true
    end
    
    log("Failed to send result")
    return false
end

function M.is_daemon_running()
    local resp_str = send_request("PING")
    return resp_str ~= nil
end

-- Evaluate routes using external LLM (Gemini via socket_daemon)
-- @param payload: table with route candidates and context
-- @return table with selected route index and reasoning
function M.evaluate_routes(payload)
    local j = get_json()
    if not j then
        log("No JSON encoder for evaluate_routes")
        return { selected = "1", reasoning = "JSON not available" }
    end

    -- Encode payload and send as EVALUATE_ROUTES command
    local content = j.encode(payload)
    local cmd = "EVALUATE_ROUTES:" .. content

    log("EVALUATE_ROUTES: sending " .. #content .. " bytes")
    local resp_str = send_request(cmd)

    if not resp_str then
        log("EVALUATE_ROUTES: no response, using default")
        return { selected = "1", reasoning = "No daemon response" }
    end

    local success, resp = pcall(j.decode, resp_str)
    if success and resp and resp.status == "ok" and resp.data then
        log("EVALUATE_ROUTES: got selection = " .. tostring(resp.data.selected))
        return resp.data
    end

    log("EVALUATE_ROUTES: bad response, using default")
    return { selected = "1", reasoning = "Invalid response" }
end

return M
