-- Configuration management for CC:Tweaked Storage & ME System
local config = {}

local CONFIG_FILE = "storage_config.json"

config.data = {
    protocol = "AETHER_VAULT_NET",
    hostname = "aether_vault_server",
    scanInterval = 5, -- seconds between automatic inventory scans
    autoDeposit = true, -- automatically import items placed in IO chests during scan
    ioChests = {}, -- format: { [peripheralName] = { label = "Main IO", x = 0, y = 64, z = 0, role = "both" } }
    ignoredPeripherals = {}, -- peripheral names to ignore (e.g., drives, turtle inventories, non-storage)
}

function config.load()
    if fs.exists(CONFIG_FILE) then
        local file = fs.open(CONFIG_FILE, "r")
        if file then
            local content = file.readAll()
            file.close()
            local parsed = textutils.unserializeJSON(content)
            if parsed then
                for k, v in pairs(parsed) do
                    config.data[k] = v
                end
            end
        end
    else
        config.save()
    end
    return config.data
end

function config.save()
    local file = fs.open(CONFIG_FILE, "w")
    if file then
        file.write(textutils.serializeJSON(config.data))
        file.close()
        return true
    end
    return false
end

function config.setIOChest(peripheralName, label, x, y, z, role)
    config.data.ioChests[peripheralName] = {
        label = label or peripheralName,
        x = tonumber(x) or 0,
        y = tonumber(y) or 0,
        z = tonumber(z) or 0,
        role = role or "both" -- "input", "output", "both"
    }
    config.save()
end

function config.removeIOChest(peripheralName)
    config.data.ioChests[peripheralName] = nil
    config.save()
end

function config.getIOChests()
    config.load()
    return config.data.ioChests
end

function config.isIOChest(peripheralName)
    config.load()
    return config.data.ioChests[peripheralName] ~= nil
end

-- Initialize default config on load
config.load()

return config
