--[[
    Fast Socket Manager - No subprocess spawning!

    Uses atomic file-based IPC that's sub-millisecond:
    - Read command file (daemon writes, we read)
    - Write response file (we write, daemon reads)

    The daemon runs persistently and bridges to LLM/agents.
    This is 100x faster than spawning Python per call.
]]

local M = {}

-- IPC file paths
local CMD_FILE = "/tmp/tf2_cmd.txt"      -- Daemon -> Game (commands to execute)
local RESP_FILE = "/tmp/tf2_resp.txt"    -- Game -> Daemon (responses/data)
local LOCK_FILE = "/tmp/tf2_cmd.lock"    -- Simple lock mechanism

-- State
local connected = false

function M.connect(host, port)
    -- Signal daemon we're connecting by creating a handshake file
    local f = io.open("/tmp/tf2_game_ready", "w")
    if f then
        f:write(os.time())
        f:close()
    end
    connected = true
    return 1  -- Return dummy socket handle
end

function M.send(sock, data)
    -- Write response/data to response file (daemon will read)
    -- Use atomic write: write to temp, then rename
    local tmpFile = RESP_FILE .. ".tmp"
    local f = io.open(tmpFile, "w")
    if f then
        f:write(data)
        f:close()
        os.rename(tmpFile, RESP_FILE)
        return #data
    end
    return 0
end

function M.receive(sock)
    -- Check if command file exists and has content
    local f = io.open(CMD_FILE, "r")
    if not f then
        return nil  -- No command pending
    end

    local content = f:read("*a")
    f:close()

    -- Immediately delete/clear the file to signal we processed it
    os.remove(CMD_FILE)

    if content and #content > 0 then
        -- Trim whitespace
        content = string.gsub(content, "^%s*(.-)%s*$", "%1")
        if #content > 0 then
            return content
        end
    end

    return nil
end

function M.close(sock)
    -- Signal daemon we're disconnecting
    local f = io.open("/tmp/tf2_game_closing", "w")
    if f then
        f:write(os.time())
        f:close()
    end
    connected = false
end

-- Convenience: Check if daemon is running
function M.is_daemon_running()
    local f = io.open("/tmp/tf2_daemon_pid", "r")
    if f then
        local pid = f:read("*l")
        f:close()
        -- Could check if PID is alive, but file existence is enough
        return pid ~= nil
    end
    return false
end

return M
