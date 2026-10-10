-- Network Communication Protocol for CC:Tweaked Wireless Pocket Computers & Storage Server
local config = require("config")

local net = {}

-- Open wireless modem on computer if available
function net.openWirelessModem()
    local modem = peripheral.find("modem", function(name, wrapped)
        return wrapped.isWireless()
    end)
    if modem then
        local modemSide = peripheral.getName(modem)
        rednet.open(modemSide)
        return true, modemSide
    end
    -- Fallback: check all modems
    for _, side in ipairs(rs.getSides()) do
        if peripheral.isPresent(side) and peripheral.getType(side) == "modem" then
            rednet.open(side)
            return true, side
        end
    end
    return false, "No wireless modem found!"
end

-- Find server on wireless network
function net.findServer(timeout)
    timeout = timeout or 2
    local serverId = rednet.lookup(config.data.protocol, config.data.hostname)
    if serverId then
        return serverId
    end
    return nil, "Storage Server not found on Rednet channel " .. config.data.protocol
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
