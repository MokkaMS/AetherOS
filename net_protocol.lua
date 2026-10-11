-- Network Communication Protocol for CC:Tweaked Wireless Pocket Computers & Storage Server
local config = require("config")

local net = {}

-- Open all attached modems (wired and wireless) on local computer sides
function net.openModem()
    local openedCount = 0
    local openedSides = {}

    for _, side in ipairs(rs.getSides()) do
        if peripheral.isPresent(side) and peripheral.getType(side) == "modem" then
            if not rednet.isOpen(side) then
                local ok = pcall(rednet.open, side)
                if ok then
                    openedCount = openedCount + 1
                    table.insert(openedSides, side)
                end
            else
                openedCount = openedCount + 1
                table.insert(openedSides, side)
            end
        end
    end

    if openedCount > 0 then
        return true, table.concat(openedSides, ", ")
    end
    return false, "No modem attached!"
end

-- Backward compatibility alias
net.openWirelessModem = net.openModem

-- Find server on network using lookup, broadcast ping, or direct server ID
function net.findServer(timeout, targetServerId)
    timeout = timeout or 3
    
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
    local startClock = os.clock()
    while (os.clock() - startClock) < timeout do
        local remaining = timeout - (os.clock() - startClock)
        local senderId, res = rednet.receive(config.data.protocol, math.max(0.05, remaining))
        if senderId and type(res) == "table" and res.success then
            return senderId
        elseif not senderId then
            break
        end
    end

    return nil, "Storage Server not found on protocol " .. config.data.protocol
end

-- Send RPC request to server and wait for reply
function net.sendRequest(serverId, command, payload, timeout)
    timeout = timeout or 4
    local req = {
        cmd = command,
        payload = payload or {},
        timestamp = os.epoch("utc")
    }
    rednet.send(serverId, req, config.data.protocol)
    
    local startClock = os.clock()
    while (os.clock() - startClock) < timeout do
        local remaining = timeout - (os.clock() - startClock)
        local senderId, response = rednet.receive(config.data.protocol, math.max(0.05, remaining))
        if senderId == serverId and type(response) == "table" then
            return true, response
        elseif not senderId then
            break
        end
    end
    return false, "Request timed out after " .. tostring(timeout) .. "s"
end

return net
