-- Configuration management for CC:Tweaked Storage & ME System
local config = {}

local CONFIG_FILE = "/storage_config.json"

config.data = {
    protocol = "AETHER_VAULT_NET",
    hostname = "aether_vault_server",
    scanInterval = 15, -- seconds between automatic inventory scans
    autoDeposit = true, -- automatically import items placed in IO chests during scan
    ioChests = {}, -- format: { [peripheralName] = { label = "Main IO", x = 0, y = 64, z = 0, role = "both" } }
    ignoredPeripherals = {}, -- peripheral names to ignore (e.g., drives, turtle inventories, non-storage)
}

local isLoaded = false

function config.load(force)
    if isLoaded and not force then
        return config.data
    end
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
    isLoaded = true
    return config.data
end

function config.save()
    local file = fs.open(CONFIG_FILE, "w")
    if file then
        file.write(textutils.serializeJSON(config.data))
        file.close()
        isLoaded = true
        return true
    end
    return false
end

function config.isPeripheralPresent(peripheralName)
    if not peripheralName then return false, nil end
    if peripheral.isPresent(peripheralName) then
        return true, peripheralName
    end
    local stripped = peripheralName:match("[^:]+:(.+)") or peripheralName
    for _, name in ipairs(peripheral.getNames()) do
        local nStripped = name:match("[^:]+:(.+)") or name
        if nStripped == stripped or name == peripheralName then
            return true, name
        end
    end
    return false, nil
end

function config.isInventoryPresent(peripheralName)
    local present, actual = config.isPeripheralPresent(peripheralName)
    if present and actual and peripheral.hasType(actual, "inventory") then
        return true, actual
    end
    return false, nil
end

-- Automatically sanitize config.data.ioChests to remove invalid side registrations
function config.cleanInvalidIOChests()
    if not config.data or not config.data.ioChests then return end
    local sides = { top = true, bottom = true, left = true, right = true, front = true, back = true }
    local changed = false
    for k, _ in pairs(config.data.ioChests) do
        -- Remove if it's a computer side name that is not a server-attached inventory
        if sides[k] and not (peripheral.isPresent(k) and peripheral.hasType(k, "inventory")) then
            config.data.ioChests[k] = nil
            changed = true
        end
    end
    if changed then
        config.save()
    end
end

function config.setIOChest(peripheralName, label, x, y, z, role)
    if not peripheralName or peripheralName == "" then return end
    config.load()
    
    local present, actualName = config.isPeripheralPresent(peripheralName)
    local targetName = actualName or peripheralName

    config.data.ioChests[targetName] = {
        label = label or targetName,
        x = tonumber(x) or 0,
        y = tonumber(y) or 0,
        z = tonumber(z) or 0,
        role = role or "both"
    }
    config.save()
end

function config.removeIOChest(peripheralName)
    config.load()
    local present, actualName = config.isPeripheralPresent(peripheralName)
    config.data.ioChests[peripheralName] = nil
    if actualName then
        config.data.ioChests[actualName] = nil
    end
    local stripped = peripheralName:match("[^:]+:(.+)") or peripheralName
    for k, _ in pairs(config.data.ioChests) do
        local kStripped = k:match("[^:]+:(.+)") or k
        if kStripped == stripped then
            config.data.ioChests[k] = nil
        end
    end
    config.save()
end

function config.getIOChests()
    config.load()
    return config.data.ioChests
end

function config.isIOChest(peripheralName)
    config.load()
    if not peripheralName then return false end
    if config.data.ioChests[peripheralName] then return true end
    local stripped = peripheralName:match("[^:]+:(.+)") or peripheralName
    for k, _ in pairs(config.data.ioChests) do
        local kStripped = k:match("[^:]+:(.+)") or k
        if kStripped == stripped or k == peripheralName then
            return true
        end
    end
    return false
end

function config.getIOChestInfo(peripheralName)
    config.load()
    if not peripheralName then return nil end
    if config.data.ioChests[peripheralName] then
        return config.data.ioChests[peripheralName]
    end
    local stripped = peripheralName:match("[^:]+:(.+)") or peripheralName
    for k, v in pairs(config.data.ioChests) do
        local kStripped = k:match("[^:]+:(.+)") or k
        if kStripped == stripped or k == peripheralName then
            return v
        end
    end
    return nil
end

-- Initialize default config on load
config.load()
config.cleanInvalidIOChests()

return config
