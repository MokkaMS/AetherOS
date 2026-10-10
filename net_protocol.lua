-- Network Communication Protocol for CC:Tweaked Wireless Pocket Computers & Storage Server
local config = require("config")

local net = {}

-- Open wireless modem on computer if available
function net.openWirelessModem()
    local openedSide = nil
    local names = peripheral.getNames()
    
    for _, name in ipairs(names) do
        if peripheral.getType(name) == "modem" then
            local p = peripheral.wrap(name)
            if p and p.isWireless and p.isWireless() then
                rednet.open(name)
                openedSide = name
            end
        end
    end
    
    if openedSide then
        return true, openedSide
    end

    -- Fallback check standard sides
    for _, side in ipairs(rs.getSides()) do
        if peripheral.isPresent(side) and peripheral.getType(side) == "modem" then
            local p = peripheral.wrap(side)
            if p and p.isWireless and p.isWireless() then
                rednet.open(side)
                return true, side
            end
        end
    end
    return false, "No wireless modem found!"
end

-- Find server on wireless network using lookup, broadcast ping, or direct server ID
function net.findServer(timeout, targetServerId)
    timeout = timeout or 2
    
    -- If user provided exact Server ID, check it first
    if targetServerId and tonumber(targetServerId) then
        local ok, res = net.sendRequest(tonumber(targetServerId), "PING", {}, timeout)
        if ok and res.success then
            return tonumber(targetServerId)
        end
    end

    -- Method 1: Rednet lookup
    local serverId = rednet.lookup(config.data.protocol, config.data.hostname)
    if serverId then
        return serverId
    end

    -- Method 2: Broadcast PING
    rednet.broadcast({ cmd = "PING" }, config.data.protocol)
    local senderId, res = rednet.receive(config.data.protocol, timeout)
    if senderId and type(res) == "table" and res.success then
        return senderId
    end

    return nil, "Storage Server not found on protocol " .. config.data.protocol
end

-- Send RPC request to server and wait for reply
function net.sendRequest(serverId, command, payload, timeout)
    timeout = timeout or 3
    local req = {
        cmd = command,
        payload = payload or {},
        timestamp = os.epoch("utc")
    }
    rednet.send(serverId, req, config.data.protocol)
    
    local senderId, response = rednet.receive(config.data.protocol, timeout)
    if senderId == serverId and type(response) == "table" then
        return true, response
    end
    return false, "Request timed out or invalid response"
end

return net
