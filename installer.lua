-- Complete Auto-Installer for AetherVault OS (CC:Tweaked)
-- Repository: https://github.com/MokkaMS/AetherOS

local GITHUB_REPO_RAW = "https://raw.githubusercontent.com/MokkaMS/AetherOS/main/"
local BASALT_RAW_URL = "https://raw.githubusercontent.com/Pyroxenium/Basalt2/refs/heads/basalt2.5/bundle/basalt.min.lua"

term.clear()
term.setCursorPos(1, 1)

local function drawTitle()
    term.setTextColor(colors.yellow)
    print("========================================")
    print("   AetherVault OS Installer v2.5       ")
    print("========================================")
    term.setTextColor(colors.white)
    print()
end

drawTitle()

-- Check HTTP API
if not http then
    term.setTextColor(colors.red)
    print("Error: HTTP API is disabled in ComputerCraft config!")
    print("Please enable http_enable=true in minecraft config.")
    return
end

local function writeFile(filename, code)
    local file = fs.open(filename, "w")
    if file then
        file.write(code)
        file.close()
        return true
    end
    return false
end

-- Embedded System Files Backup
local embeddedFiles = {}

embeddedFiles["config.lua"] = [=[
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

return config

]=]

embeddedFiles["db.lua"] = [=[
-- Database and Storage Engine for CC:Tweaked ME System
local config = require("config")

local db = {}

db.items = {}           -- Aggregated item catalog: { [itemName] = { name, displayName, total, maxCount, locations = {...} } }
db.itemIndex = {}       -- Array list of items for Basalt UI lists: { { name, displayName, total, maxCount }, ... }
db.storageChests = {}   -- List of peripheral names categorized as storage
db.ioChests = {}        -- Cached IO chest peripherals
db.logs = {}            -- Activity log entries for GUI display: { { timestamp, text, type } }
db.isScanning = false
db.isDefragging = false

local MAX_LOGS = 100

function db.addLog(text, logType)
    logType = logType or "info"
    local timestamp = os.date("%H:%M:%S")
    table.insert(db.logs, 1, { timestamp = timestamp, text = text, type = logType })
    if #db.logs > MAX_LOGS then
        table.remove(db.logs)
    end
end

local typeCache = {}
db.wrappedChests = {}

function db.getPeripheral(name)
    if not name then return nil end
    local p = db.wrappedChests[name]
    if not p then
        if peripheral.isPresent(name) then
            p = peripheral.wrap(name)
            db.wrappedChests[name] = p
        end
    end
    return p
end

-- Check if peripheral is an inventory and not ignored
local function isValidInventory(name)
    if config.data.ignoredPeripherals[name] then
        return false
    end
    -- Ignore computer/pocket peripherals if they act as inventories
    if name:find("computer") or name:find("turtle") or name:find("drive") then
        return false
    end
    if typeCache[name] ~= nil then
        return typeCache[name]
    end
    local isInv = peripheral.hasType(name, "inventory")
    typeCache[name] = isInv
    return isInv
end

local lastPeripheralCount = 0

-- Find all connected inventory peripherals on wired modem network
function db.discoverPeripherals(force)
    local names = peripheral.getNames()
    if not force and #db.storageChests > 0 and #names == lastPeripheralCount then
        return db.storageChests, db.ioChests
    end
    lastPeripheralCount = #names
    local storage = {}
    local io = {}

    for _, name in ipairs(names) do
        if isValidInventory(name) then
            if config.isIOChest(name) then
                table.insert(io, name)
            else
                table.insert(storage, name)
            end
        end
    end

    db.storageChests = storage
    db.ioChests = io
    return storage, io
end

local nameCache = {}

-- Format technical ID to readable display name (e.g. minecraft:iron_ingot -> Iron Ingot)
local function formatDisplayName(technicalName, itemDetail)
    if itemDetail and itemDetail.displayName then
        return itemDetail.displayName
    end
    if nameCache[technicalName] then
        return nameCache[technicalName]
    end
    local id = technicalName:match("[^:]+:(.+)") or technicalName
    id = id:gsub("_", " ")
    local formatted = id:gsub("(%a)([%w_']*)", function(first, rest)
        return first:upper() .. rest:lower()
    end)
    nameCache[technicalName] = formatted
    return formatted
end

-- Complete scan of all storage chests and item indexing (internal implementation)
local function doScanStorage()
    db.discoverPeripherals()

    local newItems = {}
    local totalItemCount = 0
    local lastYield = os.clock()

    for _, chestName in ipairs(db.storageChests) do
        -- Yield every 0.25s to prevent CC runtime timeout
        if (os.clock() - lastYield) > 0.25 then
            os.sleep(0)
            lastYield = os.clock()
        end

        local p = db.getPeripheral(chestName)
        if p and p.list then
            local ok, list = pcall(p.list)
            if ok and list then
                for slot, item in pairs(list) do
                    if item and item.name and item.count and item.count > 0 then
                        local key = item.name
                        local entry = newItems[key]
                        if not entry then
                            entry = {
                                name = key,
                                displayName = formatDisplayName(key, nil),
                                total = 0,
                                maxCount = 64,
                                locations = {}
                            }
                            newItems[key] = entry
                        end

                        entry.total = entry.total + item.count
                        table.insert(entry.locations, {
                            chest = chestName,
                            slot = slot,
                            count = item.count
                        })
                        totalItemCount = totalItemCount + item.count
                    end
                end
            else
                db.wrappedChests[chestName] = nil
            end
        end
    end

    db.items = newItems

    -- Rebuild flat array list for Basalt UI, sorted by quantity descending
    local indexArray = {}
    for _, itemData in pairs(db.items) do
        table.insert(indexArray, {
            name = itemData.name,
            displayName = itemData.displayName or itemData.name,
            total = itemData.total or 0,
            maxCount = itemData.maxCount or 64
        })
    end

    table.sort(indexArray, function(a, b)
        if a.total == b.total then
            return (a.displayName or ""):lower() < (b.displayName or ""):lower()
        end
        return (a.total or 0) > (b.total or 0)
    end)

    db.itemIndex = indexArray
    return true, #indexArray, totalItemCount
end

-- Public scanStorage with pcall concurrency protection
function db.scanStorage()
    if db.isScanning or db.isDefragging then return false end
    db.isScanning = true

    local success, res1, res2, res3 = pcall(doScanStorage)
    db.isScanning = false

    if not success then
        db.addLog("Scan error: " .. tostring(res1), "error")
        return false, res1
    end

    return res1, res2, res3
end

-- Calculate Euclidean distance between two 3D coordinates
local function calculateDistance(pos1, pos2)
    local dx = (pos1.x or 0) - (pos2.x or 0)
    local dy = (pos1.y or 0) - (pos2.y or 0)
    local dz = (pos1.z or 0) - (pos2.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Find nearest registered IO chest based on player's GPS position
function db.findNearestIOChest(playerPos, requiredRole)
    requiredRole = requiredRole or "both"
    local ioConfig = config.getIOChests()
    
    local candidates = {}

    -- Filter connected & registered IO chests
    for pName, info in pairs(ioConfig) do
        local isPresent, actualName = config.isPeripheralPresent(pName)
        if isPresent then
            if info.role == "both" or info.role == requiredRole or requiredRole == "both" then
                table.insert(candidates, {
                    name = actualName or pName,
                    info = info
                })
            end
        end
    end

    -- Fallback: If no registered IO chest matches, check any connected IO chest
    if #candidates == 0 then
        if #db.ioChests > 0 then
            local isPresent, actualName = config.isPeripheralPresent(db.ioChests[1])
            return actualName or db.ioChests[1], nil
        end
        return nil, "No connected IO chest found!"
    end

    -- If player position is provided (GPS coordinates)
    if playerPos and playerPos.x and playerPos.y and playerPos.z then
        local nearest = nil
        local minDistance = math.huge

        for _, item in ipairs(candidates) do
            local dist = calculateDistance(playerPos, item.info)
            if dist < minDistance then
                minDistance = dist
                nearest = item
            end
        end

        if nearest then
            return nearest.name, minDistance, nearest.info
        end
    end

    -- Default fallback if GPS is not available: return first candidate
    local defaultChest = candidates[1]
    return defaultChest.name, nil, defaultChest.info
end

-- Withdraw specified amount of item to a target IO chest
function db.withdraw(itemName, count, targetIOChest, skipRescan)
    if not itemName or not count or count <= 0 then
        return 0, "Invalid item request arguments"
    end

    local isPresent, actualTarget = config.isPeripheralPresent(targetIOChest)
    if not isPresent then
        return 0, "Target IO chest '" .. tostring(targetIOChest) .. "' not present on network"
    end
    targetIOChest = actualTarget or targetIOChest

    local itemData = db.items[itemName]
    if not itemData or itemData.total <= 0 then
        return 0, "Item '" .. itemName .. "' is not in storage"
    end

    local amountNeeded = math.min(count, itemData.total)
    local amountMoved = 0

    local targetP = db.getPeripheral(targetIOChest)
    if not targetP then
        return 0, "Failed to connect to IO chest peripheral"
    end

    -- Move items from storage locations to IO chest
    local activeLocations = {}
    for _, loc in ipairs(itemData.locations) do
        if amountMoved < amountNeeded and loc.count > 0 then
            local p = db.getPeripheral(loc.chest)
            if p and p.pushItems then
                local toTransfer = math.min(amountNeeded - amountMoved, loc.count)
                local ok, moved = pcall(p.pushItems, targetIOChest, loc.slot, toTransfer)
                if ok and moved and moved > 0 then
                    amountMoved = amountMoved + moved
                    loc.count = loc.count - moved
                end
            end
        end
        if loc.count > 0 then
            table.insert(activeLocations, loc)
        end
    end

    -- Incrementally update database in memory
    itemData.locations = activeLocations
    itemData.total = math.max(0, itemData.total - amountMoved)

    -- Update db.itemIndex in memory
    for idx = #db.itemIndex, 1, -1 do
        local entry = db.itemIndex[idx]
        if entry.name == itemName then
            if itemData.total <= 0 then
                table.remove(db.itemIndex, idx)
            else
                entry.total = itemData.total
            end
            break
        end
    end

    if itemData.total <= 0 then
        db.items[itemName] = nil
    end

    -- Re-scan after transfer only if explicitly requested (default: skip blocking scan)
    if skipRescan == false then
        db.scanStorage()
    end

    db.addLog(string.format("Withdrew %d x %s to %s", amountMoved, itemData.displayName, targetIOChest), "withdraw")
    return amountMoved, nil
end

-- Withdraw multiple selected items in a single pass
function db.withdrawMulti(requests, targetIOChest)
    if not requests or #requests == 0 then
        return 0, "No items selected for withdrawal"
    end
    local isPresent, actualTarget = config.isPeripheralPresent(targetIOChest)
    if not isPresent then
        return 0, "Target IO chest not available"
    end
    targetIOChest = actualTarget or targetIOChest

    local totalMoved = 0
    for _, req in ipairs(requests) do
        if req.item then
            local qty = req.all and (db.items[req.item] and db.items[req.item].total or 0) or (req.count or 64)
            if qty > 0 then
                local moved, _ = db.withdraw(req.item, qty, targetIOChest, true)
                totalMoved = totalMoved + moved
            end
        end
    end

    return totalMoved, nil
end

local function updateItemIndexTotal(name, newTotal)
    for _, entry in ipairs(db.itemIndex) do
        if entry.name == name then
            entry.total = newTotal
            return
        end
    end
end

-- Deposit items from an IO chest into storage chests
function db.deposit(sourceIOChest, skipRescan)
    if not sourceIOChest then
        return 0, "Source IO chest not specified"
    end
    local isPresent, actualSource = config.isPeripheralPresent(sourceIOChest)
    if not isPresent then
        return 0, "Source IO chest '" .. tostring(sourceIOChest) .. "' not present"
    end
    sourceIOChest = actualSource or sourceIOChest

    if #db.storageChests == 0 then
        db.discoverPeripherals()
    end

    local sourceP = db.getPeripheral(sourceIOChest)
    if not sourceP or not sourceP.list then
        return 0, "Cannot access source IO chest"
    end

    local ok, sourceList = pcall(sourceP.list)
    if not ok or not sourceList then
        return 0, "Failed to read source IO chest items"
    end

    local totalDeposited = 0
    local fullChests = {}

    for slot, item in pairs(sourceList) do
        if item and item.name and item.count > 0 then
            local remaining = item.count
            local triedChests = {}

            local existingData = db.items[item.name]

            -- Phase 1: Fill existing partial stacks of this item first across storage
            -- Pushing directly to specific slots (toSlot) guarantees partial stacks are topped up to 64
            -- before any empty slots are touched, preventing duplicate partial stacks!
            if existingData and existingData.locations then
                for _, loc in ipairs(existingData.locations) do
                    if remaining <= 0 then break end
                    if loc.count and loc.count > 0 and loc.count < 64 and not fullChests[loc.chest] then
                        local space = 64 - loc.count
                        local toPush = math.min(remaining, space)
                        local pok, moved = pcall(sourceP.pushItems, loc.chest, slot, toPush, loc.slot)
                        if pok and moved and moved > 0 then
                            remaining = remaining - moved
                            totalDeposited = totalDeposited + moved
                            loc.count = loc.count + moved
                            existingData.total = existingData.total + moved
                            updateItemIndexTotal(item.name, existingData.total)
                        end
                    end
                end
            end

            -- Phase 2: Place remaining into chests that already contain this item (grouping items together)
            if remaining > 0 and existingData and existingData.locations then
                for _, loc in ipairs(existingData.locations) do
                    if remaining <= 0 then break end
                    local targetChest = loc.chest
                    if not fullChests[targetChest] and not triedChests[targetChest] then
                        triedChests[targetChest] = true
                        local pok, moved = pcall(sourceP.pushItems, targetChest, slot, remaining)
                        if pok and moved and moved > 0 then
                            remaining = remaining - moved
                            totalDeposited = totalDeposited + moved
                            existingData.total = existingData.total + moved
                            updateItemIndexTotal(item.name, existingData.total)
                        end
                        if not pok or not moved or moved < remaining then
                            fullChests[targetChest] = true
                        end
                    end
                end
            end

            -- Phase 3: Put remaining items into any available storage chest
            if remaining > 0 then
                for _, chestName in ipairs(db.storageChests) do
                    if remaining <= 0 then break end
                    if not fullChests[chestName] and not triedChests[chestName] then
                        triedChests[chestName] = true
                        local pok, moved = pcall(sourceP.pushItems, chestName, slot, remaining)
                        if pok and moved and moved > 0 then
                            remaining = remaining - moved
                            totalDeposited = totalDeposited + moved
                            if db.items[item.name] then
                                db.items[item.name].total = db.items[item.name].total + moved
                                updateItemIndexTotal(item.name, db.items[item.name].total)
                            else
                                local disp = formatDisplayName(item.name)
                                db.items[item.name] = {
                                    name = item.name,
                                    displayName = disp,
                                    total = moved,
                                    maxCount = 64,
                                    locations = {}
                                }
                                table.insert(db.itemIndex, {
                                    name = item.name,
                                    displayName = disp,
                                    total = moved,
                                    maxCount = 64
                                })
                            end
                        end
                        if not pok or not moved or moved < remaining then
                            fullChests[chestName] = true
                        end
                    end
                end
            end
        end
    end

    if totalDeposited > 0 then
        if not skipRescan then
            db.scanStorage()
        end
        db.addLog(string.format("Deposited %d items from %s into storage", totalDeposited, sourceIOChest), "deposit")
    end

    return totalDeposited, nil
end

-- Deposit from all registered/discovered IO chests
function db.depositAllIO()
    local grandTotal = 0
    local allIO = {}
    for name, info in pairs(config.getIOChests()) do
        if info.role == "input" or info.role == "both" then
            allIO[name] = true
        end
    end
    for _, name in ipairs(db.ioChests) do
        local isPresent, actualName = config.isPeripheralPresent(name)
        if isPresent and not config.isIOChest(name) then
            allIO[actualName or name] = true
        end
    end

    for chestName, _ in pairs(allIO) do
        local isPresent, actualName = config.isPeripheralPresent(chestName)
        if isPresent then
            local count, _ = db.deposit(actualName or chestName, true)
            grandTotal = grandTotal + count
        end
    end
    if grandTotal > 0 then
        db.scanStorage()
    end
    return grandTotal
end

-- Storage defragmentation and compaction algorithm
-- Consolidates partial stacks within chests and across chests to prevent slot waste
function db.defragStorage()
    if db.isDefragging then
        return 0, 0, "Defrag already in progress"
    end

    -- Wait for any active scan to complete (up to 3 seconds)
    local waitCount = 0
    while db.isScanning and waitCount < 30 do
        os.sleep(0.1)
        waitCount = waitCount + 1
    end
    db.isScanning = false
    db.isDefragging = true

    db.addLog("Starting storage compaction & defragmentation...", "info")

    local success, totalMerged, slotsFreed = pcall(function()
        -- Ensure fresh indexing
        doScanStorage()

        local merged = 0
        local freed = 0
        local lastYield = os.clock()

        for itemName, itemData in pairs(db.items) do
            if itemData.locations and #itemData.locations > 1 then
                -- Find all partial stacks (less than 64 items)
                local partials = {}
                for _, loc in ipairs(itemData.locations) do
                    if loc.count and loc.count > 0 and loc.count < 64 then
                        table.insert(partials, loc)
                    end
                end

                -- If 2 or more partial stacks exist for this item, consolidate them!
                if #partials >= 2 then
                    -- Sort by count descending so larger partial stacks get topped up first
                    table.sort(partials, function(a, b)
                        return a.count > b.count
                    end)

                    local destIdx = 1
                    local srcIdx = #partials
                    local itemUnstackable = false

                    while destIdx < srcIdx and not itemUnstackable do
                        if (os.clock() - lastYield) > 0.25 then
                            os.sleep(0)
                            lastYield = os.clock()
                        end

                        local destLoc = partials[destIdx]
                        local srcLoc = partials[srcIdx]

                        local space = 64 - destLoc.count
                        if space > 0 and srcLoc.count > 0 then
                            local toTransfer = math.min(srcLoc.count, space)
                            local srcP = db.getPeripheral(srcLoc.chest)

                            if srcP and srcP.pushItems then
                                local ok, moved = pcall(srcP.pushItems, destLoc.chest, srcLoc.slot, toTransfer, destLoc.slot)
                                if ok and moved and moved > 0 then
                                    merged = merged + moved
                                    destLoc.count = destLoc.count + moved
                                    srcLoc.count = srcLoc.count - moved

                                    if srcLoc.count <= 0 then
                                        freed = freed + 1
                                        srcIdx = srcIdx - 1
                                    end

                                    if destLoc.count >= 64 then
                                        destIdx = destIdx + 1
                                    end
                                else
                                    -- Could not move items
                                    if destLoc.count == 1 and srcLoc.count == 1 then
                                        -- Two stacks of 1 could not merge -> item is unstackable (tools/armor)
                                        itemUnstackable = true
                                    else
                                        -- Destination stack cannot accept more (e.g. item max stack is 16)
                                        destIdx = destIdx + 1
                                    end
                                end
                            else
                                srcIdx = srcIdx - 1
                            end
                        else
                            if destLoc.count >= 64 then
                                destIdx = destIdx + 1
                            end
                            if srcLoc.count <= 0 then
                                srcIdx = srcIdx - 1
                            end
                        end
                    end
                end
            end
        end

        -- If items were relocated, rescan to synchronize state
        if merged > 0 then
            doScanStorage()
        end

        return merged, freed
    end)

    db.isDefragging = false

    if not success then
        db.addLog("Defrag error: " .. tostring(totalMerged), "error")
        return 0, 0, tostring(totalMerged)
    end

    totalMerged = totalMerged or 0
    slotsFreed = slotsFreed or 0
    db.addLog(string.format("Storage defrag complete: %d items merged, %d slots freed", totalMerged, slotsFreed), "info")
    return totalMerged, slotsFreed, nil
end

return db

]=]

embeddedFiles["net_protocol.lua"] = [=[
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

]=]

embeddedFiles["io_config_tool.lua"] = [=[
-- Interactive IO Chest Configuration & GPS Calibration Tool
-- Supports both local server execution and remote execution over Rednet
local config = require("config")
local net = require("net_protocol")

term.clear()
term.setCursorPos(1, 1)

local myId = os.getComputerID()
local serverId = nil
local isRemote = false
local modemOK, side = nil, nil

local function refreshConnection(targetId)
    modemOK, side = net.openModem()
    serverId = nil
    isRemote = false
    if modemOK then
        local sId, _ = net.findServer(3, targetId)
        if sId and sId ~= myId then
            serverId = sId
            isRemote = true
        elseif sId == myId then
            serverId = myId
            isRemote = false
        end
    end
    return isRemote, serverId
end

refreshConnection()

local function drawHeader()
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.yellow)
    print("========================================")
    print("   AetherVault IO & GPS Setup Tool      ")
    print("========================================")
    term.setTextColor(colors.cyan)
    if isRemote then
        print(" Mode: NETWORK CLIENT -> Server #" .. tostring(serverId))
    elseif serverId == myId then
        print(" Mode: LOCAL STORAGE SERVER (ID #" .. tostring(myId) .. ")")
    elseif not modemOK then
        print(" Mode: LOCAL STANDALONE (No modem attached)")
    else
        print(" Mode: STANDALONE (Storage Server not found)")
    end
    term.setTextColor(colors.white)
    print()
end

local function getGPSCoords()
    term.setTextColor(colors.cyan)
    write("Locating GPS coordinates...")
    local x, y, z = gps.locate(3)
    print()
    if x and y and z then
        term.setTextColor(colors.green)
        print(string.format("GPS position found: X=%.1f, Y=%.1f, Z=%.1f", x, y, z))
        return x, y, z
    else
        term.setTextColor(colors.orange)
        print("GPS signal not found (no GPS host in range).")
        return nil
    end
end

local function listConnectedInventories()
    local names = peripheral.getNames()
    local inventories = {}
    for _, name in ipairs(names) do
        if peripheral.hasType(name, "inventory") and not name:find("computer") and not name:find("turtle") then
            table.insert(inventories, name)
        end
    end
    return inventories
end

local function getRemoteIOChests()
    if not isRemote then
        return config.getIOChests()
    end
    local ok, res = net.sendRequest(serverId, "GET_IO_CHESTS", {}, 3)
    if ok and res.success and res.chests then
        return res.chests
    end
    return config.getIOChests()
end

local function registerIOChest(pName, label, x, y, z, role)
    if isRemote then
        local payload = {
            peripheralName = pName,
            label = label,
            x = x,
            y = y,
            z = z,
            role = role
        }
        local ok, res = net.sendRequest(serverId, "REGISTER_IO_CHEST", payload, 4)
        if ok and res.success then
            return true, res.message or "Registered remotely on server!"
        else
            local errDetail = (type(res) == "table" and res.message) or (type(res) == "string" and res) or "RPC call failed"
            return false, errDetail
        end
    else
        config.setIOChest(pName, label, x, y, z, role)
        return true, "Registered locally in config!"
    end
end

local function removeIOChest(pName)
    if isRemote then
        local payload = { peripheralName = pName }
        local ok, res = net.sendRequest(serverId, "REMOVE_IO_CHEST", payload, 4)
        if ok and res.success then
            return true, res.message or "Removed remotely on server!"
        else
            local errDetail = (type(res) == "table" and res.message) or (type(res) == "string" and res) or "RPC call failed"
            return false, errDetail
        end
    else
        config.removeIOChest(pName)
        return true, "Removed locally from config!"
    end
end

local function performTestDeposit()
    if isRemote then
        local ok, res = net.sendRequest(serverId, "DEPOSIT_ITEMS", {}, 5)
        if ok and res.success then
            return res.count or 0, nil
        else
            local errDetail = (type(res) == "table" and res.message) or (type(res) == "string" and res) or "RPC call failed"
            return 0, errDetail
        end
    else
        local db = require("db")
        db.scanStorage()
        return db.depositAllIO()
    end
end

local function main()
    while true do
        drawHeader()
        print("1) List Configured IO Chests")
        print("2) Register / Edit IO Chest (with GPS)")
        print("3) Remove Registered IO Chest")
        print("4) Perform Test Deposit from IO Chest")
        print("5) Reconnect to Server / Set Server ID")
        print("6) Exit")
        print()
        write("Select option (1-6): ")
        local choice = read()

        if choice == "1" then
            drawHeader()
            print("Configured IO Chests on Server:")
            local ioChests = getRemoteIOChests()
            local count = 0
            for pName, data in pairs(ioChests) do
                count = count + 1
                local present = peripheral.isPresent(pName) and "[ONLINE]" or "[REGISTERED]"
                term.setTextColor(present:find("ONLINE") and colors.green or colors.cyan)
                print(string.format("- %s (%s) %s", pName, data.label, present))
                term.setTextColor(colors.lightGray)
                print(string.format("  Coords: X=%d, Y=%d, Z=%d | Role: %s", data.x, data.y, data.z, data.role))
                term.setTextColor(colors.white)
            end
            if count == 0 then
                print("No IO chests registered yet.")
            end
            print()
            write("Press Enter to continue...")
            read()

        elseif choice == "2" then
            drawHeader()
            print("Available Connected Inventories:")
            local inventories = listConnectedInventories()
            
            if #inventories > 0 then
                for i = 1, math.min(#inventories, 10) do
                    local name = inventories[i]
                    local isRegistered = config.isIOChest(name) and " [REG]" or ""
                    print(string.format("  %d) %s%s", i, name, isRegistered))
                end
                if #inventories > 10 then
                    print(string.format("  ... (%d more connected inventories)", #inventories - 10))
                end
            end
            print()
            write("Enter chest # (e.g. 0, 12), menu # (1-10), or full name: ")
            local inputStr = read()
            if inputStr and inputStr ~= "" then
                local selectedPName = nil
                local num = tonumber(inputStr)

                if num and inventories[num] then
                    selectedPName = inventories[num]
                else
                    local matches = {}
                    for _, pName in ipairs(inventories) do
                        if pName == inputStr or pName:sub(-#("_" .. inputStr)) == ("_" .. inputStr) or pName:find(inputStr, 1, true) then
                            table.insert(matches, pName)
                        end
                    end

                    if #matches == 1 then
                        selectedPName = matches[1]
                    elseif #matches > 1 then
                        print()
                        print("Multiple matching chests found:")
                        for i, m in ipairs(matches) do
                            print(string.format("  %d) %s", i, m))
                        end
                        write("Select match number (1-" .. #matches .. "): ")
                        local mNum = tonumber(read())
                        if mNum and matches[mNum] then
                            selectedPName = matches[mNum]
                        end
                    else
                        if peripheral.isPresent(inputStr) then
                            selectedPName = inputStr
                        elseif peripheral.isPresent("minecraft:chest_" .. inputStr) then
                            selectedPName = "minecraft:chest_" .. inputStr
                        elseif peripheral.isPresent("minecraft:barrel_" .. inputStr) then
                            selectedPName = "minecraft:barrel_" .. inputStr
                        else
                            selectedPName = inputStr -- allow custom peripheral name
                        end
                    end
                end

                if not selectedPName then
                    term.setTextColor(colors.red)
                    print("Could not find chest matching '" .. inputStr .. "'!")
                    write("Press Enter to return...")
                    read()
                else
                    local pName = selectedPName
                    drawHeader()
                    print("Configuring IO Chest: " .. pName)
                    print()
                    write("Enter friendly label (e.g. Main IO, Base Mine): ")
                    local label = read()
                    if label == "" then label = pName end

                    print()
                    print("Chest Role:")
                    print("1) Both (Input & Output)")
                    print("2) Input only")
                    print("3) Output only")
                    write("Choice (1-3) [default 1]: ")
                    local roleChoice = read()
                    local role = "both"
                    if roleChoice == "2" then role = "input"
                    elseif roleChoice == "3" then role = "output" end

                    print()
                    local gpsX, gpsY, gpsZ = getGPSCoords()
                    local finalX, finalY, finalZ

                    if gpsX then
                        write("Use detected GPS coords? (Y/n): ")
                        local useGps = read():lower()
                        if useGps == "" or useGps == "y" then
                            finalX, finalY, finalZ = math.floor(gpsX), math.floor(gpsY), math.floor(gpsZ)
                        end
                    end

                    if not finalX then
                        write("Enter X coordinate: ")
                        finalX = tonumber(read()) or 0
                        write("Enter Y coordinate: ")
                        finalY = tonumber(read()) or 0
                        write("Enter Z coordinate: ")
                        finalZ = tonumber(read()) or 0
                    end

                    local proceed = true
                    if not isRemote and serverId == nil then
                        term.setTextColor(colors.yellow)
                        write("Warning: Not connected to Storage Server! Register locally on this computer? (y/N): ")
                        local confirm = read():lower()
                        if confirm ~= "y" then
                            proceed = false
                            term.setTextColor(colors.white)
                            print("Registration cancelled.")
                        end
                    end

                    if proceed then
                        local ok, msg = registerIOChest(pName, label, finalX, finalY, finalZ, role)
                        if ok then
                            term.setTextColor(colors.green)
                            print()
                            print(string.format("Successfully registered '%s' (%s) at [%d, %d, %d]!", pName, label, finalX, finalY, finalZ))
                        else
                            term.setTextColor(colors.red)
                            print("Error: " .. tostring(msg))
                        end
                    end
                    write("Press Enter to continue...")
                    read()
                end
            end

        elseif choice == "3" then
            drawHeader()
            local ioChests = getRemoteIOChests()
            local list = {}
            for pName, data in pairs(ioChests) do
                table.insert(list, pName)
                print(string.format("%d) %s (%s)", #list, pName, data.label))
            end
            if #list == 0 then
                print("No registered IO chests to remove.")
            else
                print()
                write("Select chest number to remove: ")
                local num = tonumber(read())
                if num and list[num] then
                    local ok, msg = removeIOChest(list[num])
                    if ok then
                        term.setTextColor(colors.green)
                        print("Removed " .. list[num])
                    else
                        term.setTextColor(colors.red)
                        print("Error: " .. tostring(msg))
                    end
                end
            end
            write("Press Enter to continue...")
            read()

        elseif choice == "4" then
            drawHeader()
            print("Performing deposit from IO chests...")
            local count, err = performTestDeposit()
            if err then
                term.setTextColor(colors.red)
                print("Error: " .. tostring(err))
            else
                term.setTextColor(colors.green)
                print(string.format("Successfully deposited %d items into storage system!", count))
            end
            write("Press Enter to continue...")
            read()

        elseif choice == "5" then
            drawHeader()
            print("Searching for Storage Server on network...")
            local okRem, sId = refreshConnection()
            if okRem then
                term.setTextColor(colors.green)
                print(string.format("Connected to Storage Server #%d over network!", sId))
            else
                term.setTextColor(colors.orange)
                print("Auto-discovery could not locate Storage Server.")
                print()
                write("Enter Server Computer ID manually (or press Enter to cancel): ")
                local manualStr = read()
                local manualId = tonumber(manualStr)
                if manualId then
                    print("Pinging Server #" .. tostring(manualId) .. "...")
                    local okRem2, sId2 = refreshConnection(manualId)
                    if okRem2 then
                        term.setTextColor(colors.green)
                        print(string.format("Successfully connected to Server #%d!", sId2))
                    elseif sId2 == myId then
                        term.setTextColor(colors.green)
                        print("Target ID is this local computer.")
                    else
                        term.setTextColor(colors.red)
                        print(string.format("Server #%d did not respond to PING.", manualId))
                    end
                end
            end
            term.setTextColor(colors.white)
            print()
            write("Press Enter to continue...")
            read()

        elseif choice == "6" then
            term.clear()
            term.setCursorPos(1, 1)
            break
        end
    end
end

main()

]=]

embeddedFiles["storage_server.lua"] = [=[
-- Main Server Storage System with Basalt v2.5 GUI & Wireless Rednet Controller
local config = require("config")
local db = require("db")
local net = require("net_protocol")

-- Check for Basalt framework
local basaltOK, basalt = pcall(require, "basalt")
if not basaltOK then
    term.setTextColor(colors.red)
    print("Error: Basalt framework v2.5 is not installed!")
    print("Run installer.lua to download Basalt automatically.")
    return
end

-- Initialize network
local modemOK, modemSide = net.openModem()
if modemOK then
    rednet.host(config.data.protocol, config.data.hostname)
    db.addLog("Rednet started on " .. modemSide .. " (" .. config.data.hostname .. ")", "system")
else
    db.addLog("Warning: No modem active. Remote pocket computer & client control disabled.", "warning")
end

-- Get terminal dimensions dynamically
local termW, termH = term.getSize()
termW = termW or 51
termH = termH or 19
local contentH = termH - 4

-- Initial scan
db.scanStorage()
db.addLog("Storage system initialized.", "system")

-- Create main GUI Frame with Basalt 2.5
local mainFrame = (basalt.getMainFrame and basalt.getMainFrame()) or basalt.createFrame()
mainFrame:setSize(termW, termH):setBackground(colors.lightGray)

-- Header / Status Bar
local titleBar = mainFrame:addFrame()
    :setPosition(1, 1)
    :setSize(termW, 3)
    :setBackground(colors.gray)

local titleLabel = titleBar:addLabel()
    :setPosition(2, 1)
    :setForeground(colors.white)
titleLabel.text = "AETHERVAULT OS v2.5 | SPATIAL STORAGE MATRIX"

local statsLabel = titleBar:addLabel()
    :setPosition(2, 2)
    :setForeground(colors.yellow)
statsLabel.text = "Items: 0 | Types: 0 | IO Chests: 0"

local function updateStatsDisplay()
    local typeCount = #db.itemIndex
    local totalItems = 0
    for _, it in ipairs(db.itemIndex) do
        totalItems = totalItems + it.total
    end
    local ioCount = 0
    for _ in pairs(config.getIOChests()) do ioCount = ioCount + 1 end
    statsLabel.text = string.format("Items: %d | Types: %d | IO Chests: %d", totalItems, typeCount, ioCount)
end

-- Tab Buttons Navigation
local tabItemsBtn = mainFrame:addButton()
    :setPosition(1, 4)
    :setSize(12, 1)
    :setText("Item Catalog")
    :setBackground(colors.blue)
    :setForeground(colors.white)

local tabIOBtn = mainFrame:addButton()
    :setPosition(14, 4)
    :setSize(12, 1)
    :setText("IO Chests")
    :setBackground(colors.cyan)
    :setForeground(colors.black)

local tabLogsBtn = mainFrame:addButton()
    :setPosition(27, 4)
    :setSize(12, 1)
    :setText("Logs")
    :setBackground(colors.cyan)
    :setForeground(colors.black)

local tabSettingsBtn = mainFrame:addButton()
    :setPosition(40, 4)
    :setSize(12, 1)
    :setText("Settings")
    :setBackground(colors.cyan)
    :setForeground(colors.black)

-- Main Container Content Frame
local contentFrame = mainFrame:addFrame()
    :setPosition(1, 5)
    :setSize(termW, contentH)
    :setBackground(colors.lightGray)

---------------------------------------------------------
-- TAB 1: ITEM CATALOG
---------------------------------------------------------
local itemsFrame = contentFrame:addFrame()
    :setPosition(1, 1)
    :setSize(termW, contentH)

local searchInput = itemsFrame:addInput()
    :setPosition(1, 1)
    :setSize(termW - 25, 1)
    :setBackground(colors.white)
    :setForeground(colors.black)
searchInput.placeholder = "Search items..."

local searchHighlighted = false

local function setSearchHighlight(highlight)
    searchHighlighted = highlight
    if highlight then
        searchInput:setBackground(colors.lightBlue):setForeground(colors.black)
    else
        searchInput:setBackground(colors.white):setForeground(colors.black)
    end
end

searchInput:onClick(function(self)
    if setWithdrawQtyHighlight then setWithdrawQtyHighlight(false) end
    if searchHighlighted then
        self.text = ""
        if self.setValue then pcall(self.setValue, self, "") end
        if self.setText then pcall(self.setText, self, "") end
        setSearchHighlight(false)
        populateItemList("")
    else
        setSearchHighlight(true)
    end
end)

local autoCompleteBtn = itemsFrame:addButton()
    :setPosition(termW - 24, 1)
    :setSize(12, 1)
    :setText("TabComplete")
    :setBackground(colors.purple)
    :setForeground(colors.white)

local rescanBtn = itemsFrame:addButton()
    :setPosition(termW - 11, 1)
    :setSize(11, 1)
    :setText("Refresh")
    :setBackground(colors.green)
    :setForeground(colors.white)

local selectAllBtn = itemsFrame:addButton()
    :setPosition(1, 2)
    :setSize(11, 1)
    :setText("Select All")
    :setBackground(colors.cyan)
    :setForeground(colors.black)

local clearSelBtn = itemsFrame:addButton()
    :setPosition(13, 2)
    :setSize(11, 1)
    :setText("Clear Sel")
    :setBackground(colors.gray)
    :setForeground(colors.white)

local autoCompleteHint = itemsFrame:addLabel()
    :setPosition(25, 2)
    :setForeground(colors.yellow)
autoCompleteHint.text = ""

local itemList = itemsFrame:addList()
    :setPosition(1, 3)
    :setSize(termW, math.max(1, contentH - 5))
    :setBackground(colors.white)
    :setForeground(colors.black)

local withdrawBox = itemsFrame:addFrame()
    :setPosition(1, math.max(1, contentH - 1))
    :setSize(termW, 2)
    :setBackground(colors.gray)

local withdrawQtyInput = withdrawBox:addInput()
    :setPosition(1, 1)
    :setSize(6, 1)
    :setBackground(colors.white)
    :setForeground(colors.black)
withdrawQtyInput.text = "64"

local withdrawQtyHighlighted = false

local function setWithdrawQtyHighlight(highlight)
    withdrawQtyHighlighted = highlight
    if highlight then
        withdrawQtyInput:setBackground(colors.lightBlue):setForeground(colors.black)
    else
        withdrawQtyInput:setBackground(colors.white):setForeground(colors.black)
    end
end

withdrawQtyInput:onClick(function(self)
    setSearchHighlight(false)
    if withdrawQtyHighlighted then
        self.text = ""
        if self.setValue then pcall(self.setValue, self, "") end
        if self.setText then pcall(self.setText, self, "") end
        setWithdrawQtyHighlight(false)
    else
        setWithdrawQtyHighlight(true)
    end
end)

withdrawQtyInput:onChange(function(self, text)
    if withdrawQtyHighlighted then
        withdrawQtyHighlighted = false
        setWithdrawQtyHighlight(false)
        local clean = text or ""
        local newChar = clean:sub(-1)
        if not newChar:match("%d") then
            newChar = clean:match("%d") or ""
        end
        self.text = newChar
        if self.setValue then pcall(self.setValue, self, newChar) end
        if self.setText then pcall(self.setText, self, newChar) end
    end
end)

local pullAllMode = false

local pullAllBtn = withdrawBox:addButton()
    :setPosition(8, 1)
    :setSize(10, 1)
    :setText("PULL: QTY")
    :setBackground(colors.blue)
    :setForeground(colors.white)

local withdrawBtn = withdrawBox:addButton()
    :setPosition(19, 1)
    :setSize(math.max(1, termW - 19), 1)
    :setText("Withdraw Selection (0)")
    :setBackground(colors.orange)
    :setForeground(colors.white)

local selectedItems = {}
local filteredItems = {}
local currentAutoMatch = nil

local function getSelectedCount()
    local count = 0
    for _, sel in pairs(selectedItems) do
        if sel then count = count + 1 end
    end
    return count
end

local function updateWithdrawButtonText()
    local count = getSelectedCount()
    if count == 0 then
        withdrawBtn:setText("Withdraw Selection (0)")
    else
        withdrawBtn:setText(string.format("Withdraw Sel (%d items)", count))
    end
end

local function updateAutoComplete(filterText)
    currentAutoMatch = nil
    filterText = (filterText or ""):lower()
    if filterText ~= "" then
        for _, item in ipairs(db.itemIndex) do
            if item.displayName:lower():find(filterText, 1, true) == 1 or item.name:lower():find(filterText, 1, true) == 1 then
                currentAutoMatch = item
                break
            end
        end
        if not currentAutoMatch then
            for _, item in ipairs(db.itemIndex) do
                if item.displayName:lower():find(filterText, 1, true) or item.name:lower():find(filterText, 1, true) then
                    currentAutoMatch = item
                    break
                end
            end
        end
    end

    if currentAutoMatch then
        autoCompleteHint.text = "Auto: " .. currentAutoMatch.displayName
    else
        autoCompleteHint.text = ""
    end
end

local function updateListItemAt(idx, itemName)
    if not idx or not itemName then return end
    local isSel = selectedItems[itemName]
    local prefix = isSel and "[x] " or "[ ] "
    local maxNameLen = math.max(10, termW - 14)
    local itemData = db.items[itemName]
    local dispName = itemData and itemData.displayName or itemName
    if #dispName > maxNameLen then
        dispName = dispName:sub(1, maxNameLen - 2) .. ".."
    end
    local total = itemData and itemData.total or 0
    local entryText = string.format("%s%-" .. maxNameLen .. "s %6d", prefix, dispName, total)
    if itemList.editItem then
        pcall(itemList.editItem, itemList, idx, entryText)
    elseif itemList.getItem then
        local ok, itObj = pcall(itemList.getItem, itemList, idx)
        if ok and type(itObj) == "table" then
            itObj.text = entryText
        end
    end
end

local function populateItemList(filter)
    local prevOffset = nil
    if itemList.getOffset then
        local ok, off = pcall(itemList.getOffset, itemList)
        if ok and type(off) == "number" then prevOffset = off end
    end

    itemList:clear()
    filteredItems = {}
    filter = filter and filter:lower() or ""
    
    for _, item in ipairs(db.itemIndex) do
        if filter == "" or item.displayName:lower():find(filter, 1, true) or item.name:lower():find(filter, 1, true) then
            local isSel = selectedItems[item.name]
            local prefix = isSel and "[x] " or "[ ] "
            
            local maxNameLen = math.max(10, termW - 14)
            local dispName = item.displayName
            if #dispName > maxNameLen then
                dispName = dispName:sub(1, maxNameLen - 2) .. ".."
            end
            local entryText = string.format("%s%-" .. maxNameLen .. "s %6d", prefix, dispName, item.total)

            itemList:addItem(entryText)
            table.insert(filteredItems, item.name)
        end
    end

    if prevOffset and itemList.setOffset then
        pcall(itemList.setOffset, itemList, prevOffset)
    end

    updateStatsDisplay()
    updateWithdrawButtonText()
    updateAutoComplete(filter)
end

local isUpdatingList = false

local function resolveSelectedItemName(self, item, index)
    local idx = nil
    if type(index) == "number" then
        idx = index
    elseif type(item) == "number" then
        idx = item
    elseif self and self.getSelectedIndex then
        local ok, val = pcall(self.getSelectedIndex, self)
        if ok and type(val) == "number" then idx = val end
    end

    if idx and filteredItems[idx] then
        return filteredItems[idx], idx
    end

    local itemObj = item or (self and self.getItem and idx and pcall(self.getItem, self, idx) and self:getItem(idx)) or (self and self.getValue and pcall(self.getValue, self) and self:getValue())
    local strText = nil
    if type(itemObj) == "table" then
        if itemObj.value then return itemObj.value, idx end
        if itemObj.name then return itemObj.name, idx end
        if itemObj.args and itemObj.args[1] then return itemObj.args[1], idx end
        strText = itemObj.text
    elseif type(itemObj) == "string" then
        strText = itemObj
    end

    if strText then
        local cleanName = strText:match("^%[%p%]%s+(.-)%s+%d+$") or strText:match("^%[%p%]%s+(.+)$") or strText
        cleanName = cleanName:gsub("^%s*(.-)%s*$", "%1")
        for i, it in ipairs(db.itemIndex) do
            if it.displayName == cleanName or it.name == cleanName or cleanName:find(it.displayName, 1, true) then
                return it.name, idx
            end
        end
    end

    return nil, nil
end

local function handleSelection(self, item, index)
    if isUpdatingList then return end
    setWithdrawQtyHighlight(false)
    setSearchHighlight(false)
    local itemName, idx = resolveSelectedItemName(self, item, index)
    if itemName then
        selectedItems[itemName] = not selectedItems[itemName]
        if idx and itemList.editItem then
            updateListItemAt(idx, itemName)
            updateWithdrawButtonText()
        else
            isUpdatingList = true
            basalt.schedule(function()
                populateItemList(searchInput.text or searchInput.value or "")
                isUpdatingList = false
            end, 0)
        end
    end
end

if itemList.onSelect then itemList:onSelect(handleSelection) end
if itemList.onChange then itemList:onChange(handleSelection) end

searchInput:onChange(function(self, text)
    if searchHighlighted then
        searchHighlighted = false
        setSearchHighlight(false)
        local clean = text or ""
        local newChar = clean:sub(-1)
        if newChar == "" then newChar = clean:sub(1, 1) or "" end
        self.text = newChar
        if self.setValue then pcall(self.setValue, self, newChar) end
        if self.setText then pcall(self.setText, self, newChar) end
        populateItemList(newChar)
        return
    end
    populateItemList(text or searchInput.text or searchInput.value or "")
end)

autoCompleteBtn:onClick(function()
    setSearchHighlight(false)
    if currentAutoMatch then
        searchInput.text = currentAutoMatch.displayName
        if searchInput.setValue then pcall(searchInput.setValue, searchInput, currentAutoMatch.displayName) end
        if searchInput.setText then pcall(searchInput.setText, searchInput, currentAutoMatch.displayName) end
        populateItemList(currentAutoMatch.displayName)
    end
end)

selectAllBtn:onClick(function()
    local filter = (searchInput.text or searchInput.value or ""):lower()
    for _, item in ipairs(db.itemIndex) do
        if filter == "" or item.displayName:lower():find(filter, 1, true) or item.name:lower():find(filter, 1, true) then
            selectedItems[item.name] = true
        end
    end
    populateItemList(filter)
end)

clearSelBtn:onClick(function()
    selectedItems = {}
    populateItemList(searchInput.text or searchInput.value or "")
end)

pullAllBtn:onClick(function()
    pullAllMode = not pullAllMode
    if pullAllMode then
        pullAllBtn:setText("PULL: ALL"):setBackground(colors.purple)
    else
        pullAllBtn:setText("PULL: QTY"):setBackground(colors.blue)
    end
end)

rescanBtn:onClick(function()
    if rescanBtn.getText and rescanBtn:getText():find("Refreshing") then
        return
    end
    rescanBtn:setText("Refreshing..."):setBackground(colors.yellow)
    basalt.schedule(function()
        local waitCount = 0
        while (db.isScanning or db.isDefragging) and waitCount < 30 do
            os.sleep(0.1)
            waitCount = waitCount + 1
        end

        db.addLog("Refreshing storage index in background...", "info")
        db.scanStorage()
        populateItemList(searchInput.text or searchInput.value or "")
        updateStatsDisplay()
        rescanBtn:setText("Refresh"):setBackground(colors.green)
        db.addLog("Storage refresh complete.", "info")
    end)
end)

withdrawBtn:onClick(function()
    local requests = {}
    local rawVal = withdrawQtyInput.text or withdrawQtyInput.value or (withdrawQtyInput.getValue and withdrawQtyInput:getValue()) or "64"
    local count = tonumber(rawVal) or 64

    for name, sel in pairs(selectedItems) do
        if sel then
            table.insert(requests, { item = name, count = count, all = pullAllMode })
        end
    end

    if #requests == 0 then
        db.addLog("Select one or more items from the list first!", "warning")
        return
    end

    local nearestIO, dist, info = db.findNearestIOChest(nil, "output")
    if not nearestIO then
        db.addLog("No IO chest available for withdrawal!", "error")
        return
    end

    withdrawBtn:setText("Moving..."):setBackground(colors.yellow)
    basalt.schedule(function()
        local moved, err = db.withdrawMulti(requests, nearestIO)
        withdrawBtn:setText("Withdraw"):setBackground(colors.blue)
        if err then
            db.addLog("Withdraw error: " .. err, "error")
        else
            db.addLog(string.format("Multi-withdraw complete: moved %d total items.", moved), "info")
            selectedItems = {}
            populateItemList(searchInput.text or searchInput.value or "")
        end
    end)
end)

---------------------------------------------------------
-- TAB 2: IO CHESTS MANAGER
---------------------------------------------------------
local ioFrame = contentFrame:addFrame()
    :setPosition(1, 1)
    :setSize(termW, contentH)
ioFrame.visible = false

local ioList = ioFrame:addList()
    :setPosition(1, 1)
    :setSize(termW, math.max(1, contentH - 3))
    :setBackground(colors.black)
    :setForeground(colors.white)

local ioCountLabel = ioFrame:addLabel()
    :setPosition(1, math.max(1, contentH - 2))
    :setForeground(colors.yellow)

local ioDepositBtn = ioFrame:addButton()
    :setPosition(1, math.max(1, contentH - 1))
    :setSize(24, 1)
    :setText("Deposit All IO Chests")
    :setBackground(colors.green)
    :setForeground(colors.white)

local function populateIOList()
    ioList:clear()
    local registered = config.getIOChests()
    local count = 0

    for pName, data in pairs(registered) do
        count = count + 1
        local isPresent, actualPName = config.isPeripheralPresent(pName)
        local status = isPresent and "[ONLINE]" or "[OFFLINE]"
        local label = data.label or pName
        if #label > 14 then label = label:sub(1, 12) .. ".." end
        local role = (data.role or "both"):upper()
        local text = string.format("%-9s %-14s [%d,%d,%d] Role:%s", status, label, data.x or 0, data.y or 0, data.z or 0, role)
        ioList:addItem(text)
    end

    if count == 0 then
        ioList:addItem("[!] No IO chests registered yet.")
        ioList:addItem("Run 'io_config_tool' on a computer to add an IO chest.")
    end

    ioCountLabel.text = string.format(" Registered IO: %d | Storage Chests: %d", count, #db.storageChests)
end

ioDepositBtn:onClick(function()
    db.addLog("Executing manual deposit from all IO chests in background...", "info")
    ioDepositBtn:setText("Depositing..."):setBackground(colors.yellow)
    basalt.schedule(function()
        local moved, _ = db.depositAllIO()
        db.addLog(string.format("Manual IO Deposit complete: imported %d items.", moved), "info")
        ioDepositBtn:setText("Deposit All IO Chests"):setBackground(colors.green)
        populateIOList()
        populateItemList(searchInput.text or searchInput.value or "")
    end)
end)

---------------------------------------------------------
-- TAB 3: LOGS
---------------------------------------------------------
local logsFrame = contentFrame:addFrame()
    :setPosition(1, 1)
    :setSize(termW, contentH)
logsFrame.visible = false

local logsList = logsFrame:addList()
    :setPosition(1, 1)
    :setSize(termW, contentH)
    :setBackground(colors.black)
    :setForeground(colors.green)

local function populateLogs()
    logsList:clear()
    local maxLen = math.max(20, termW - 2)
    for _, log in ipairs(db.logs) do
        local fullText = string.format("[%s] %s", log.timestamp, log.text)
        if #fullText <= maxLen then
            logsList:addItem(fullText)
        else
            local remaining = fullText
            local isFirst = true
            while #remaining > 0 do
                local chunk = remaining:sub(1, maxLen)
                remaining = remaining:sub(maxLen + 1)
                if not isFirst then
                    chunk = "  " .. chunk
                end
                logsList:addItem(chunk)
                isFirst = false
            end
        end
    end
end

---------------------------------------------------------
-- TAB 4: SETTINGS
---------------------------------------------------------
local settingsFrame = contentFrame:addFrame()
    :setPosition(1, 1)
    :setSize(termW, contentH)
settingsFrame.visible = false

settingsFrame:addLabel():setPosition(2, 2):setText("Protocol: " .. config.data.protocol)
settingsFrame:addLabel():setPosition(2, 3):setText("Hostname: " .. config.data.hostname)
local scanIntervals = { 5, 10, 15, 30, 60, 120 }
local scanIntervalBtn = settingsFrame:addButton()
    :setPosition(2, 4)
    :setSize(28, 1)
    :setText(string.format("Scan Interval: %ds (Click)", config.data.scanInterval or 15))
    :setBackground(colors.blue)
    :setForeground(colors.white)

scanIntervalBtn:onClick(function()
    local current = config.data.scanInterval or 15
    local nextVal = 15
    for i, v in ipairs(scanIntervals) do
        if v == current then
            nextVal = scanIntervals[(i % #scanIntervals) + 1]
            break
        end
    end
    config.data.scanInterval = nextVal
    config.save()
    scanIntervalBtn:setText(string.format("Scan Interval: %ds (Click)", nextVal))
    db.addLog(string.format("Changed scan interval to %ds", nextVal), "info")
end)

local autoDepositBtn = settingsFrame:addButton()
    :setPosition(2, 6)
    :setSize(28, 1)
    :setText("Auto Deposit: " .. (config.data.autoDeposit and "ENABLED" or "DISABLED"))
    :setBackground(config.data.autoDeposit and colors.green or colors.red)
    :setForeground(colors.white)

autoDepositBtn:onClick(function()
    config.data.autoDeposit = not config.data.autoDeposit
    config.save()
    autoDepositBtn:setText("Auto Deposit: " .. (config.data.autoDeposit and "ENABLED" or "DISABLED"))
        :setBackground(config.data.autoDeposit and colors.green or colors.red)
end)

local defragBtn = settingsFrame:addButton()
    :setPosition(2, 8)
    :setSize(28, 1)
    :setText("Sort & Defrag Storage")
    :setBackground(colors.purple)
    :setForeground(colors.white)

local defragStatusLabel = settingsFrame:addLabel()
    :setPosition(2, 10)
    :setForeground(colors.yellow)
defragStatusLabel.text = ""

defragBtn:onClick(function()
    if db.isDefragging then
        db.addLog("Storage defrag already in progress.", "warning")
        return
    end
    defragBtn:setText("Defragmenting..."):setBackground(colors.yellow)
    defragStatusLabel.text = "Waiting for scanner to finish..."
    basalt.schedule(function()
        local merged, freed, err = db.defragStorage()
        defragBtn:setText("Sort & Defrag Storage"):setBackground(colors.purple)
        if err then
            defragStatusLabel.text = "Error: " .. tostring(err)
            db.addLog("Defrag failed: " .. tostring(err), "error")
        else
            defragStatusLabel.text = string.format("Complete: merged %d items, freed %d slots", merged, freed)
            updateStatsDisplay()
            populateItemList(searchInput.text or searchInput.value or "")
        end
    end)
end)

---------------------------------------------------------
-- TAB SWITCHING NAVIGATION HANDLER
---------------------------------------------------------
local function setFrameVisibility(frm, visible)
    if visible then
        if frm.show then frm:show() else frm.visible = true end
    else
        if frm.hide then frm:hide() else frm.visible = false end
    end
end

local function setActiveTab(tab)
    setFrameVisibility(itemsFrame, false)
    setFrameVisibility(ioFrame, false)
    setFrameVisibility(logsFrame, false)
    setFrameVisibility(settingsFrame, false)

    tabItemsBtn:setBackground(colors.cyan):setForeground(colors.black)
    tabIOBtn:setBackground(colors.cyan):setForeground(colors.black)
    tabLogsBtn:setBackground(colors.cyan):setForeground(colors.black)
    tabSettingsBtn:setBackground(colors.cyan):setForeground(colors.black)

    if tab == "items" then
        setFrameVisibility(itemsFrame, true)
        tabItemsBtn:setBackground(colors.blue):setForeground(colors.white)
        populateItemList(searchInput.text or searchInput.value or "")
    elseif tab == "io" then
        setFrameVisibility(ioFrame, true)
        tabIOBtn:setBackground(colors.blue):setForeground(colors.white)
        populateIOList()
    elseif tab == "logs" then
        setFrameVisibility(logsFrame, true)
        tabLogsBtn:setBackground(colors.blue):setForeground(colors.white)
        populateLogs()
    elseif tab == "settings" then
        setFrameVisibility(settingsFrame, true)
        tabSettingsBtn:setBackground(colors.blue):setForeground(colors.white)
    end
end

tabItemsBtn:onClick(function() setActiveTab("items") end)
tabIOBtn:onClick(function() setActiveTab("io") end)
tabLogsBtn:onClick(function() setActiveTab("logs") end)
tabSettingsBtn:onClick(function() setActiveTab("settings") end)

setActiveTab("items")

---------------------------------------------------------
-- BACKGROUND REDNET LISTENER (COROUTINE THREAD)
---------------------------------------------------------
basalt.schedule(function()
    while true do
        local event, senderId, message, protocol = os.pullEvent("rednet_message")
        if protocol == config.data.protocol and type(message) == "table" and message.cmd then
            local cmd = message.cmd
            local payload = message.payload or {}
            local response = { success = false, message = "Unknown command" }

            if cmd == "PING" then
                response = {
                    success = true,
                    hostname = config.data.hostname,
                    totalItems = #db.itemIndex,
                    ioCount = #db.ioChests
                }

            elseif cmd == "GET_ITEMS" then
                response = {
                    success = true,
                    items = db.itemIndex
                }

            elseif cmd == "WITHDRAW_ITEM" then
                local itemName = payload.item
                local count = payload.count or 64
                local gpsPos = payload.gpsPos

                local targetIO, dist, info = nil, nil, nil
                if payload.targetChest and config.isPeripheralPresent(payload.targetChest) then
                    local _, actualName = config.isPeripheralPresent(payload.targetChest)
                    targetIO = actualName or payload.targetChest
                    info = config.getIOChestInfo(targetIO)
                else
                    targetIO, dist, info = db.findNearestIOChest(gpsPos, "output")
                end
                
                if not targetIO then
                    response = { success = false, message = "No IO chest available on network!" }
                else
                    local moved, err = db.withdraw(itemName, count, targetIO, true)
                    if err then
                        response = { success = false, message = err }
                    else
                        response = {
                            success = true,
                            moved = moved,
                            targetChest = targetIO,
                            chestLabel = info and info.label or targetIO,
                            distance = dist,
                            message = string.format("Withdrew %d items to %s", moved, info and info.label or targetIO)
                        }
                    end
                end

            elseif cmd == "WITHDRAW_MULTI" then
                local requests = payload.requests or {}
                local gpsPos = payload.gpsPos

                local targetIO, dist, info = nil, nil, nil
                if payload.targetChest and config.isPeripheralPresent(payload.targetChest) then
                    local _, actualName = config.isPeripheralPresent(payload.targetChest)
                    targetIO = actualName or payload.targetChest
                    info = config.getIOChestInfo(targetIO)
                else
                    targetIO, dist, info = db.findNearestIOChest(gpsPos, "output")
                end
                
                if not targetIO then
                    response = { success = false, message = "No IO chest available on network!" }
                else
                    local moved, err = db.withdrawMulti(requests, targetIO)
                    if err then
                        response = { success = false, message = err }
                    else
                        response = {
                            success = true,
                            moved = moved,
                            targetChest = targetIO,
                            chestLabel = info and info.label or targetIO,
                            distance = dist,
                            message = string.format("Withdrew %d items to %s", moved, info and info.label or targetIO)
                        }
                    end
                end

            elseif cmd == "DEPOSIT_ITEMS" then
                local gpsPos = payload.gpsPos

                local sourceIO, dist, info = nil, nil, nil
                if payload.sourceChest and config.isPeripheralPresent(payload.sourceChest) then
                    local _, actualName = config.isPeripheralPresent(payload.sourceChest)
                    sourceIO = actualName or payload.sourceChest
                    info = config.getIOChestInfo(sourceIO)
                else
                    sourceIO, dist, info = db.findNearestIOChest(gpsPos, "input")
                end

                if not sourceIO then
                    response = { success = false, message = "No IO chest available for deposit!" }
                else
                    local moved, err = db.deposit(sourceIO, true)
                    if err then
                        response = { success = false, message = err }
                    else
                        response = {
                            success = true,
                            count = moved,
                            sourceChest = sourceIO,
                            chestLabel = info and info.label or sourceIO,
                            distance = dist,
                            message = string.format("Deposited %d items from %s", moved, info and info.label or sourceIO)
                        }
                    end
                end

            elseif cmd == "GET_IO_CHESTS" then
                response = {
                    success = true,
                    chests = config.getIOChests()
                }

            elseif cmd == "REGISTER_IO_CHEST" then
                local pName = payload.peripheralName
                local label = payload.label or pName
                local x = payload.x or 0
                local y = payload.y or 0
                local z = payload.z or 0
                local role = payload.role or "both"

                if pName then
                    config.setIOChest(pName, label, x, y, z, role)
                    db.discoverPeripherals()
                    db.addLog(string.format("Remote IO Register: %s (%s) [%d,%d,%d]", pName, label, x, y, z), "info")
                    response = { success = true, message = "Registered " .. pName .. " on server!" }
                    populateIOList()
                    updateStatsDisplay()
                else
                    response = { success = false, message = "Missing peripheralName parameter" }
                end

            elseif cmd == "REMOVE_IO_CHEST" then
                local pName = payload.peripheralName
                if pName then
                    config.removeIOChest(pName)
                    db.discoverPeripherals()
                    db.addLog(string.format("Remote IO Remove: %s", pName), "info")
                    response = { success = true, message = "Removed " .. pName .. " on server!" }
                    populateIOList()
                    updateStatsDisplay()
                else
                    response = { success = false, message = "Missing peripheralName parameter" }
                end

            elseif cmd == "DEFRAG_STORAGE" then
                if db.isDefragging then
                    response = { success = false, message = "Storage defrag already in progress" }
                else
                    local merged, freed, err = db.defragStorage()
                    if err then
                        response = { success = false, message = err }
                    else
                        response = {
                            success = true,
                            merged = merged,
                            freed = freed,
                            message = string.format("Storage defrag complete: merged %d items, freed %d slots", merged, freed)
                        }
                        updateStatsDisplay()
                    end
                end
            end

            rednet.send(senderId, response, config.data.protocol)
            populateItemList(searchInput.text or searchInput.value or "")
        end
    end
end)

---------------------------------------------------------
-- BACKGROUND PERIODIC STORAGE SCANNER (COROUTINE THREAD)
---------------------------------------------------------
basalt.schedule(function()
    while true do
        sleep(config.data.scanInterval or 15)
        if not db.isDefragging then
            local moved = 0
            if config.data.autoDeposit then
                moved = db.depositAllIO()
            end
            if moved == 0 then
                db.scanStorage()
            end
            updateStatsDisplay()
            if moved > 0 then
                populateItemList(searchInput.text or searchInput.value or "")
            end
        end
    end
end)

if basalt.run then
    basalt.run()
else
    basalt.autoUpdate()
end

]=]

embeddedFiles["pocket_client.lua"] = [=[
-- Pocket Computer Wireless Remote Client with Basalt v2.5 GUI
local config = require("config")
local net = require("net_protocol")

local basaltOK, basalt = pcall(require, "basalt")
if not basaltOK then
    term.setTextColor(colors.red)
    print("Error: Basalt v2.5 required!")
    print("Run installer.lua to setup.")
    return
end

local modemOK, err = net.openWirelessModem()
if not modemOK then
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.red)
    print("Error: No wireless modem!")
    print("Attach a wireless modem to pocket computer.")
    return
end

local serverId = nil
local playerPos = nil
local currentItems = {}
local selectedItems = {}
local pullAllMode = false
local currentAutoMatch = nil

local mainFrame = (basalt.getMainFrame and basalt.getMainFrame()) or basalt.createFrame()
mainFrame:setSize(26, 20):setBackground(colors.black)

local titleLabel = mainFrame:addLabel()
    :setPosition(1, 1)
    :setSize(26, 1)
    :setBackground(colors.blue)
    :setForeground(colors.white)
titleLabel.text = " AETHERVAULT REMOTE "

local gpsLabel = mainFrame:addLabel()
    :setPosition(1, 2)
    :setSize(26, 1)
    :setBackground(colors.gray)
    :setForeground(colors.yellow)
gpsLabel.text = " GPS: Locating..."

local searchInput = mainFrame:addInput()
    :setPosition(1, 3)
    :setSize(18, 1)
    :setBackground(colors.white)
    :setForeground(colors.black)
searchInput.placeholder = " Search..."

local searchHighlighted = false

local function setSearchHighlight(highlight)
    searchHighlighted = highlight
    if highlight then
        searchInput:setBackground(colors.lightBlue):setForeground(colors.black)
    else
        searchInput:setBackground(colors.white):setForeground(colors.black)
    end
end

searchInput:onClick(function(self)
    if setQtyHighlight then setQtyHighlight(false) end
    if searchHighlighted then
        self.text = ""
        if self.setValue then pcall(self.setValue, self, "") end
        if self.setText then pcall(self.setText, self, "") end
        setSearchHighlight(false)
        populateList()
    else
        setSearchHighlight(true)
    end
end)

local autoBtn = mainFrame:addButton()
    :setPosition(19, 3)
    :setSize(8, 1)
    :setText("Auto")
    :setBackground(colors.purple)
    :setForeground(colors.white)

local itemList = mainFrame:addList()
    :setPosition(1, 4)
    :setSize(26, 9)
    :setBackground(colors.lightGray)
    :setForeground(colors.black)

local qtyLabel = mainFrame:addLabel()
    :setPosition(1, 13)
    :setForeground(colors.white)
qtyLabel.text = "Qty:"

local qtyInput = mainFrame:addInput()
    :setPosition(5, 13)
    :setSize(5, 1)
    :setBackground(colors.white)
    :setForeground(colors.black)
qtyInput.text = "64"

local qtyHighlighted = false

local function setQtyHighlight(highlight)
    qtyHighlighted = highlight
    if highlight then
        qtyInput:setBackground(colors.lightBlue):setForeground(colors.black)
    else
        qtyInput:setBackground(colors.white):setForeground(colors.black)
    end
end

qtyInput:onClick(function(self)
    setSearchHighlight(false)
    if qtyHighlighted then
        self.text = ""
        if self.setValue then pcall(self.setValue, self, "") end
        if self.setText then pcall(self.setText, self, "") end
        setQtyHighlight(false)
    else
        setQtyHighlight(true)
    end
end)

qtyInput:onChange(function(self, text)
    if qtyHighlighted then
        qtyHighlighted = false
        setQtyHighlight(false)
        local clean = text or ""
        local newChar = clean:sub(-1)
        if not newChar:match("%d") then
            newChar = clean:match("%d") or ""
        end
        self.text = newChar
        if self.setValue then pcall(self.setValue, self, newChar) end
        if self.setText then pcall(self.setText, self, newChar) end
    end
end)

local pullAllBtn = mainFrame:addButton()
    :setPosition(11, 13)
    :setSize(5, 1)
    :setText("ALL")
    :setBackground(colors.blue)
    :setForeground(colors.white)

local selectAllBtn = mainFrame:addButton()
    :setPosition(17, 13)
    :setSize(5, 1)
    :setText("Sel*")
    :setBackground(colors.cyan)
    :setForeground(colors.black)

local clearSelBtn = mainFrame:addButton()
    :setPosition(23, 13)
    :setSize(4, 1)
    :setText("Clr")
    :setBackground(colors.gray)
    :setForeground(colors.white)

local withdrawBtn = mainFrame:addButton()
    :setPosition(1, 14)
    :setSize(26, 1)
    :setText("Withdraw Selection (0)")
    :setBackground(colors.orange)
    :setForeground(colors.white)

local depositBtn = mainFrame:addButton()
    :setPosition(1, 15)
    :setSize(26, 1)
    :setText("Deposit Here (Nearest IO)")
    :setBackground(colors.green)
    :setForeground(colors.white)

local statusLabel = mainFrame:addLabel()
    :setPosition(1, 16)
    :setSize(26, 2)
    :setForeground(colors.yellow)
statusLabel.text = " Connecting to network..."

local refreshBtn = mainFrame:addButton()
    :setPosition(1, 18)
    :setSize(26, 1)
    :setText("Refresh Server & GPS")
    :setBackground(colors.gray)
    :setForeground(colors.white)

local function updateGPS()
    local x, y, z = gps.locate(1.5)
    if x and y and z then
        playerPos = { x = math.floor(x), y = math.floor(y), z = math.floor(z) }
        gpsLabel.text = string.format(" GPS: %d, %d, %d", playerPos.x, playerPos.y, playerPos.z)
    else
        playerPos = nil
        gpsLabel.text = " GPS: Signal Unavailable"
    end
end

local function getSelectedCount()
    local count = 0
    for _, sel in pairs(selectedItems) do
        if sel then count = count + 1 end
    end
    return count
end

local function updateWithdrawButtonText()
    local count = getSelectedCount()
    if count == 0 then
        withdrawBtn:setText("Withdraw Selection (0)")
    else
        withdrawBtn:setText(string.format("Withdraw Sel (%d items)", count))
    end
end

local function updateAutoComplete(filterText)
    currentAutoMatch = nil
    filterText = (filterText or ""):lower()
    if filterText ~= "" then
        for _, item in ipairs(currentItems) do
            if item.displayName:lower():find(filterText, 1, true) == 1 or item.name:lower():find(filterText, 1, true) == 1 then
                currentAutoMatch = item
                break
            end
        end
    end
end

local filteredItems = {}

local function updateListItemAt(idx, itemName)
    if not idx or not itemName then return end
    local isSel = selectedItems[itemName]
    local prefix = isSel and "[x]" or "[ ]"
    local itObj = nil
    for _, it in ipairs(currentItems) do
        if it.name == itemName then
            itObj = it
            break
        end
    end
    local dispName = itObj and itObj.displayName or itemName
    if #dispName > 12 then
        dispName = dispName:sub(1, 10) .. ".."
    end
    local total = itObj and itObj.total or 0
    local entryText = string.format("%s %-12s %5d", prefix, dispName, total)
    if itemList.editItem then
        pcall(itemList.editItem, itemList, idx, entryText)
    elseif itemList.getItem then
        local ok, itemData = pcall(itemList.getItem, itemList, idx)
        if ok and type(itemData) == "table" then
            itemData.text = entryText
        end
    end
end

local function populateList()
    local prevOffset = nil
    if itemList.getOffset then
        local ok, off = pcall(itemList.getOffset, itemList)
        if ok and type(off) == "number" then prevOffset = off end
    end

    itemList:clear()
    filteredItems = {}
    local filter = (searchInput.text or searchInput.value or ""):lower()
    updateAutoComplete(filter)

    for _, item in ipairs(currentItems) do
        if filter == "" or item.displayName:lower():find(filter, 1, true) then
            local isSel = selectedItems[item.name]
            local prefix = isSel and "[x]" or "[ ]"
            local dispName = item.displayName
            if #dispName > 12 then
                dispName = dispName:sub(1, 10) .. ".."
            end
            local entryText = string.format("%s %-12s %5d", prefix, dispName, item.total)
            itemList:addItem(entryText)
            table.insert(filteredItems, item.name)
        end
    end

    if prevOffset and itemList.setOffset then
        pcall(itemList.setOffset, itemList, prevOffset)
    end

    updateWithdrawButtonText()
end

local function fetchItems()
    updateGPS()
    
    if not serverId then
        statusLabel.text = " Searching for server..."
        local sId, errStr = net.findServer(4)
        if not sId then
            statusLabel.text = " Error: Server offline"
            return
        end
        serverId = sId
    end

    statusLabel.text = " Fetching catalog..."
    local ok, res = net.sendRequest(serverId, "GET_ITEMS", {}, 5)
    if ok and res.success and res.items then
        currentItems = res.items
        table.sort(currentItems, function(a, b)
            if a.total == b.total then return a.displayName:lower() < b.displayName:lower() end
            return a.total > b.total
        end)
        populateList()
        statusLabel.text = " Connected: " .. #currentItems .. " item types"
    else
        serverId = nil
        statusLabel.text = " Connection failed!"
    end
end

local isUpdatingList = false

local function resolveSelectedItemName(self, item, index)
    local idx = nil
    if type(index) == "number" then
        idx = index
    elseif type(item) == "number" then
        idx = item
    elseif self and self.getSelectedIndex then
        local ok, val = pcall(self.getSelectedIndex, self)
        if ok and type(val) == "number" then idx = val end
    end

    if idx and filteredItems[idx] then
        return filteredItems[idx], idx
    end

    local itemObj = item or (self and self.getItem and idx and pcall(self.getItem, self, idx) and self:getItem(idx)) or (self and self.getValue and pcall(self.getValue, self) and self:getValue())
    local strText = nil
    if type(itemObj) == "table" then
        if itemObj.value then return itemObj.value, idx end
        if itemObj.name then return itemObj.name, idx end
        if itemObj.args and itemObj.args[1] then return itemObj.args[1], idx end
        strText = itemObj.text
    elseif type(itemObj) == "string" then
        strText = itemObj
    end

    if strText then
        local cleanName = strText:match("^%[%p%]%s+(.-)%s+%d+$") or strText:match("^%[%p%]%s+(.+)$") or strText
        cleanName = cleanName:gsub("^%s*(.-)%s*$", "%1")
        for _, it in ipairs(currentItems) do
            if it.displayName == cleanName or it.name == cleanName or cleanName:find(it.displayName, 1, true) then
                return it.name, idx
            end
        end
    end

    return nil, nil
end

local function handleSelection(self, item, index)
    if isUpdatingList then return end
    setQtyHighlight(false)
    setSearchHighlight(false)
    local itemName, idx = resolveSelectedItemName(self, item, index)
    if itemName then
        selectedItems[itemName] = not selectedItems[itemName]
        if idx and itemList.editItem then
            updateListItemAt(idx, itemName)
            updateWithdrawButtonText()
        else
            isUpdatingList = true
            basalt.schedule(function()
                populateList()
                isUpdatingList = false
            end, 0)
        end
    end
end

if itemList.onSelect then itemList:onSelect(handleSelection) end
if itemList.onChange then itemList:onChange(handleSelection) end

searchInput:onChange(function(self, text)
    if searchHighlighted then
        searchHighlighted = false
        setSearchHighlight(false)
        local clean = text or ""
        local newChar = clean:sub(-1)
        if newChar == "" then newChar = clean:sub(1, 1) or "" end
        self.text = newChar
        if self.setValue then pcall(self.setValue, self, newChar) end
        if self.setText then pcall(self.setText, self, newChar) end
        populateList()
        return
    end
    populateList()
end)

autoBtn:onClick(function()
    setSearchHighlight(false)
    if currentAutoMatch then
        searchInput.text = currentAutoMatch.displayName
        if searchInput.setValue then pcall(searchInput.setValue, searchInput, currentAutoMatch.displayName) end
        if searchInput.setText then pcall(searchInput.setText, searchInput, currentAutoMatch.displayName) end
        populateList()
    end
end)

pullAllBtn:onClick(function()
    pullAllMode = not pullAllMode
    if pullAllMode then
        pullAllBtn:setText("ALL!"):setBackground(colors.purple)
    else
        pullAllBtn:setText("ALL"):setBackground(colors.blue)
    end
end)

selectAllBtn:onClick(function()
    local filter = (searchInput.text or searchInput.value or ""):lower()
    for _, item in ipairs(currentItems) do
        if filter == "" or item.displayName:lower():find(filter, 1, true) then
            selectedItems[item.name] = true
        end
    end
    populateList()
end)

clearSelBtn:onClick(function()
    selectedItems = {}
    populateList()
end)

withdrawBtn:onClick(function()
    local requests = {}
    local rawVal = qtyInput.text or qtyInput.value or "64"
    local count = tonumber(rawVal) or 64

    for name, sel in pairs(selectedItems) do
        if sel then
            table.insert(requests, { item = name, count = count, all = pullAllMode })
        end
    end

    if #requests == 0 then
        statusLabel.text = " Select item(s) first!"
        return
    end

    withdrawBtn:setText("Withdrawing..."):setBackground(colors.yellow)
    statusLabel.text = " Sending request..."

    basalt.schedule(function()
        if not serverId then
            fetchItems()
            if not serverId then
                updateWithdrawButtonText()
                withdrawBtn:setBackground(colors.orange)
                return
            end
        end

        local payload = {
            requests = requests,
            gpsPos = playerPos
        }

        local ok, res = net.sendRequest(serverId, "WITHDRAW_MULTI", payload, 8)
        updateWithdrawButtonText()
        withdrawBtn:setBackground(colors.orange)
        if ok and res.success then
            local distStr = res.distance and string.format(" (%.1fm)", res.distance) or ""
            statusLabel.text = string.format(" Moved x%d to %s%s", res.moved or 0, res.chestLabel or "IO", distStr)
            selectedItems = {}
            fetchItems()
        else
            local errMsg = (type(res) == "table" and res.message) or (type(res) == "string" and res) or "Timeout"
            statusLabel.text = " Error: " .. errMsg
        end
    end)
end)

depositBtn:onClick(function()
    depositBtn:setText("Depositing..."):setBackground(colors.yellow)
    statusLabel.text = " Requesting deposit..."

    basalt.schedule(function()
        if not serverId then
            fetchItems()
            if not serverId then
                depositBtn:setText("Deposit Here (Nearest IO)"):setBackground(colors.green)
                return
            end
        end

        local payload = {
            gpsPos = playerPos
        }

        local ok, res = net.sendRequest(serverId, "DEPOSIT_ITEMS", payload, 8)
        depositBtn:setText("Deposit Here (Nearest IO)"):setBackground(colors.green)
        if ok and res.success then
            local distStr = res.distance and string.format(" (%.1fm)", res.distance) or ""
            statusLabel.text = string.format(" Deposited x%d from %s%s", res.count or 0, res.chestLabel or "IO", distStr)
            fetchItems()
        else
            local errMsg = (type(res) == "table" and res.message) or (type(res) == "string" and res) or "Timeout"
            statusLabel.text = " Error: " .. errMsg
        end
    end)
end)

refreshBtn:onClick(function()
    refreshBtn:setText("Refreshing..."):setBackground(colors.yellow)
    basalt.schedule(function()
        fetchItems()
        refreshBtn:setText("Refresh Server & GPS"):setBackground(colors.gray)
    end)
end)

fetchItems()

if basalt.run then
    basalt.run()
else
    basalt.autoUpdate()
end

]=]


embeddedFiles["io_terminal.lua"] = [=[
-- AetherVault OS: Dedicated I/O Station & Quick-Order Monitor Terminal
-- Designed for Advanced Computers with Advanced Touchscreen Monitors & adjacent I/O chests
local config = require("config")
local net = require("net_protocol")

local basaltOK, basalt = pcall(require, "basalt")
if not basaltOK then
    term.setTextColor(colors.red)
    print("Error: Basalt v2.5 required!")
    print("Run installer.lua to setup.")
    return
end

-- Open attached modems (wireless or wired)
local modemOK, modemSide = net.openModem()
if not modemOK then
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.red)
    print("Error: No modem attached!")
    print("Please attach a wired or wireless modem to connect to the AetherVault network.")
    return
end

local STATION_CONFIG_FILE = "/io_station_config.json"
local QUICK_ORDERS_FILE = "/quickorders.json"

-- Load station configuration
local stationConfig = {
    chest = nil,
    label = "I/O Station",
    monitor = nil,
    textScale = 0.5
}

local function loadStationConfig()
    if fs.exists(STATION_CONFIG_FILE) then
        local file = fs.open(STATION_CONFIG_FILE, "r")
        if file then
            local data = textutils.unserializeJSON(file.readAll())
            file.close()
            if type(data) == "table" then
                for k, v in pairs(data) do stationConfig[k] = v end
            end
        end
    end
end

local function saveStationConfig()
    local file = fs.open(STATION_CONFIG_FILE, "w")
    if file then
        file.write(textutils.serializeJSON(stationConfig))
        file.close()
    end
end

loadStationConfig()

-- Load quick-orders
local quickOrders = {}
local DEFAULT_ORDERS = {
    { item = "minecraft:cobblestone", displayName = "Cobblestone", count = 64 },
    { item = "minecraft:torch", displayName = "Torch", count = 16 },
    { item = "minecraft:iron_ingot", displayName = "Iron Ingot", count = 64 },
    { item = "minecraft:oak_planks", displayName = "Oak Planks", count = 32 },
    { item = "minecraft:coal", displayName = "Coal", count = 32 },
    { item = "minecraft:bread", displayName = "Bread", count = 16 }
}

local function loadQuickOrders()
    if fs.exists(QUICK_ORDERS_FILE) then
        local file = fs.open(QUICK_ORDERS_FILE, "r")
        if file then
            local data = textutils.unserializeJSON(file.readAll())
            file.close()
            if type(data) == "table" and #data > 0 then
                quickOrders = data
                return
            end
        end
    end
    quickOrders = DEFAULT_ORDERS
    saveStationConfig()
end

local function saveQuickOrders()
    local file = fs.open(QUICK_ORDERS_FILE, "w")
    if file then
        file.write(textutils.serializeJSON(quickOrders))
        file.close()
    end
end

loadQuickOrders()

-- Detect monitor
local monitor = nil
local monitorName = stationConfig.monitor
if monitorName and peripheral.isPresent(monitorName) and peripheral.getType(monitorName) == "monitor" then
    monitor = peripheral.wrap(monitorName)
else
    monitor = peripheral.find("monitor")
    if monitor then
        monitorName = peripheral.getName(monitor)
        stationConfig.monitor = monitorName
        saveStationConfig()
    end
end

if monitor and monitor.setTextScale then
    pcall(monitor.setTextScale, stationConfig.textScale or 0.5)
end

local renderTerm = monitor or term.current()
local termW, termH = renderTerm.getSize()
termW = termW or 29
termH = termH or 12

-- Detect adjacent or connected chest
local function detectChests()
    local candidates = {}
    -- Priority 1: Adjacent sides
    local sides = { "top", "bottom", "left", "right", "front", "back" }
    for _, s in ipairs(sides) do
        if peripheral.isPresent(s) and peripheral.hasType(s, "inventory") then
            table.insert(candidates, { name = s, label = "Adjacent (" .. s .. ")" })
        end
    end
    -- Priority 2: All connected peripherals on network
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.hasType(name, "inventory") and not name:find("computer") and not name:find("turtle") then
            local isAlready = false
            for _, c in ipairs(candidates) do
                if c.name == name then isAlready = true break end
            end
            if not isAlready then
                table.insert(candidates, { name = name, label = name })
            end
        end
    end
    return candidates
end

if not stationConfig.chest or not peripheral.isPresent(stationConfig.chest) then
    local candidates = detectChests()
    if #candidates > 0 then
        stationConfig.chest = candidates[1].name
        stationConfig.label = candidates[1].label
        saveStationConfig()
    end
end

-- Server state
local serverId = nil
local serverHostname = "Searching..."
local storageItems = {}
local stockMap = {}

local function connectServer()
    serverId = net.findServer(3)
    if serverId then
        local ok, pingRes = net.sendRequest(serverId, "PING", {}, 3)
        if ok and pingRes and pingRes.success then
            serverHostname = pingRes.hostname or "AetherVault Server"
        else
            serverHostname = "Server #" .. serverId
        end

        -- Register station chest on server
        if stationConfig.chest then
            net.sendRequest(serverId, "REGISTER_IO_CHEST", {
                peripheralName = stationConfig.chest,
                label = stationConfig.label or stationConfig.chest,
                role = "both"
            }, 3)
        end
        return true
    end
    return false
end

local function refreshStock()
    if not serverId then
        connectServer()
    end
    if serverId then
        local ok, res = net.sendRequest(serverId, "GET_ITEMS", {}, 5)
        if ok and res and res.success and res.items then
            storageItems = res.items
            stockMap = {}
            for _, it in ipairs(res.items) do
                stockMap[it.name] = it.total
            end
            return true
        end
    end
    return false
end

-- Create Basalt GUI Frame on monitor (or current terminal)
local mainFrame = basalt.createFrame(renderTerm, monitorName)
mainFrame:setSize(termW, termH):setBackground(colors.black)

-- Header Bar
local headerFrame = mainFrame:addFrame()
    :setPosition(1, 1)
    :setSize(termW, 2)
    :setBackground(colors.gray)

local titleLabel = headerFrame:addLabel()
    :setPosition(2, 1)
    :setForeground(colors.yellow)
titleLabel.text = "AETHERVAULT | I/O QUICK-ORDER STATION"

local chestLabel = headerFrame:addLabel()
    :setPosition(2, 2)
    :setForeground(colors.cyan)
local function updateChestLabel()
    chestLabel.text = string.format("Chest: %s | Server: %s", stationConfig.label or stationConfig.chest or "NONE", serverHostname)
end
updateChestLabel()

-- Header action buttons
local addBtn = headerFrame:addButton()
    :setPosition(math.max(1, termW - 21), 1)
    :setSize(7, 1)
    :setText("+ Add")
    :setBackground(colors.purple)
    :setForeground(colors.white)

local delMode = false
local delBtn = headerFrame:addButton()
    :setPosition(math.max(1, termW - 13), 1)
    :setSize(7, 1)
    :setText("Del:OFF")
    :setBackground(colors.gray)
    :setForeground(colors.white)

local syncBtn = headerFrame:addButton()
    :setPosition(math.max(1, termW - 5), 1)
    :setSize(5, 1)
    :setText("Sync")
    :setBackground(colors.green)
    :setForeground(colors.white)

-- Prominent Deposit Button
local depositBtn = mainFrame:addButton()
    :setPosition(1, 3)
    :setSize(termW, 1)
    :setText("v  DEPOSIT ALL ITEMS INTO STORAGE  v")
    :setBackground(colors.green)
    :setForeground(colors.white)

-- Status Bar
local statusBar = mainFrame:addFrame()
    :setPosition(1, termH)
    :setSize(termW, 1)
    :setBackground(colors.gray)

local statusLabel = statusBar:addLabel()
    :setPosition(2, 1)
    :setForeground(colors.yellow)
statusLabel.text = "Ready | Touch buttons to quick-order"

-- Scrollable Container for Quick-Order Buttons
local contentH = math.max(1, termH - 4)
local gridContainer = mainFrame:addFrame()
    :setPosition(1, 4)
    :setSize(termW, contentH)
    :setBackground(colors.black)
    :setScrollable(true)
    :setScrollbar("auto")

local renderQuickOrderGrid -- forward declare

depositBtn:onClick(function()
    depositBtn:setText("Depositing into Storage..."):setBackground(colors.yellow)
    statusLabel.text = "Transferring items from chest to storage..."
    basalt.schedule(function()
        if not serverId then connectServer() end
        if not serverId then
            depositBtn:setText("v  DEPOSIT ALL ITEMS INTO STORAGE  v"):setBackground(colors.green)
            statusLabel.text = "Error: Storage Server not connected!"
            return
        end

        local payload = {
            sourceChest = stationConfig.chest
        }
        local ok, res = net.sendRequest(serverId, "DEPOSIT_ITEMS", payload, 8)
        depositBtn:setText("v  DEPOSIT ALL ITEMS INTO STORAGE  v"):setBackground(colors.green)
        if ok and res and res.success then
            local count = res.count or 0
            if count > 0 then
                statusLabel.text = string.format("Deposited %d items into storage!", count)
            else
                statusLabel.text = "Deposit complete: Chest was empty."
            end
            refreshStock()
            renderQuickOrderGrid()
        else
            local err = (type(res) == "table" and res.message) or "Timeout or error"
            statusLabel.text = "Deposit failed: " .. tostring(err)
        end
    end)
end)

delBtn:onClick(function()
    delMode = not delMode
    if delMode then
        delBtn:setText("Del:ON"):setBackground(colors.red)
        statusLabel.text = "DELETE MODE: Tap any quick-order button to remove it."
    else
        delBtn:setText("Del:OFF"):setBackground(colors.gray)
        statusLabel.text = "Ready | Touch buttons to quick-order"
    end
end)

syncBtn:onClick(function()
    syncBtn:setText("..."):setBackground(colors.yellow)
    basalt.schedule(function()
        connectServer()
        refreshStock()
        updateChestLabel()
        syncBtn:setText("Sync"):setBackground(colors.green)
        renderQuickOrderGrid()
        statusLabel.text = "Storage catalog & stock synchronized."
    end)
end)

-- Render Quick-Order Buttons Grid
renderQuickOrderGrid = function()
    -- Clear previous buttons from container
    local children = gridContainer:getChildren()
    while #children > 0 do
        local child = children[#children]
        gridContainer:removeChild(child)
    end

    if #quickOrders == 0 then
        local emptyLabel = gridContainer:addLabel()
            :setPosition(2, 2)
            :setForeground(colors.lightGray)
        emptyLabel.text = "No quick-order buttons configured. Tap '+ Add' to create one!"
        return
    end

    -- Dynamic columns: 1 column if narrow, 2 if medium, 3 if wide
    local cols = 1
    if termW >= 48 then
        cols = 3
    elseif termW >= 24 then
        cols = 2
    end

    local colW = math.floor((termW - (cols + 1)) / cols)
    local btnH = 1

    for idx, order in ipairs(quickOrders) do
        local colIdx = (idx - 1) % cols
        local rowIdx = math.floor((idx - 1) / cols)

        local posX = 2 + colIdx * (colW + 1)
        local posY = 1 + rowIdx * (btnH + 1)

        local avail = stockMap[order.item] or 0
        local dispName = order.displayName or order.item:match("[^:]+:(.+)") or order.item
        local maxNameLen = math.max(4, colW - 6)
        if #dispName > maxNameLen then
            dispName = dispName:sub(1, maxNameLen - 1) .. "."
        end

        local btnText = string.format("+%d %s [%d]", order.count, dispName, avail)

        local btnBg = (avail >= order.count) and colors.blue or (avail > 0 and colors.orange or colors.gray)
        if delMode then btnBg = colors.red end

        local qBtn = gridContainer:addButton()
            :setPosition(posX, posY)
            :setSize(colW, btnH)
            :setText(btnText)
            :setBackground(btnBg)
            :setForeground(colors.white)

        qBtn:onClick(function()
            if delMode then
                table.remove(quickOrders, idx)
                saveQuickOrders()
                statusLabel.text = "Removed: " .. dispName
                renderQuickOrderGrid()
                return
            end

            qBtn:setText("Ordering..."):setBackground(colors.yellow)
            statusLabel.text = string.format("Requesting %dx %s...", order.count, dispName)
            basalt.schedule(function()
                if not serverId then connectServer() end
                if not serverId then
                    qBtn:setText(btnText):setBackground(btnBg)
                    statusLabel.text = "Error: Server not connected!"
                    return
                end

                local payload = {
                    item = order.item,
                    count = order.count,
                    targetChest = stationConfig.chest
                }

                local ok, res = net.sendRequest(serverId, "WITHDRAW_ITEM", payload, 8)
                if ok and res and res.success then
                    local moved = res.moved or 0
                    if moved > 0 then
                        statusLabel.text = string.format("Delivered %dx %s to chest!", moved, dispName)
                    else
                        statusLabel.text = string.format("Out of stock: %s", dispName)
                    end
                    refreshStock()
                    renderQuickOrderGrid()
                else
                    local errMsg = (type(res) == "table" and res.message) or "Timeout"
                    statusLabel.text = "Order failed: " .. tostring(errMsg)
                    qBtn:setText(btnText):setBackground(btnBg)
                end
            end)
        end)
    end
end

-- =========================================================
-- MODAL DIALOG: ADD QUICK-ORDER BUTTON
-- =========================================================
local modalW = math.min(termW - 2, 42)
local modalH = math.min(termH - 2, 14)
local modalX = math.max(2, math.floor((termW - modalW) / 2) + 1)
local modalY = math.max(2, math.floor((termH - modalH) / 2) + 1)

local addModal = mainFrame:addFrame()
    :setPosition(modalX, modalY)
    :setSize(modalW, modalH)
    :setBackground(colors.gray)
    :setZ(100)

local function setModalVisible(visible)
    if addModal.setVisible then
        pcall(addModal.setVisible, addModal, visible)
    end
    addModal.visible = visible
end
addModal.show = function() setModalVisible(true) end
addModal.hide = function() setModalVisible(false) end
setModalVisible(false)

local modalTitle = addModal:addLabel()
    :setPosition(2, 1)
    :setForeground(colors.yellow)
modalTitle.text = "ADD QUICK-ORDER BUTTON"

local modalSearch = addModal:addInput()
    :setPosition(2, 2)
    :setSize(modalW - 12, 1)
    :setBackground(colors.white)
    :setForeground(colors.black)
modalSearch.placeholder = "Search storage..."

local modalQtyInput = addModal:addInput()
    :setPosition(modalW - 9, 2)
    :setSize(8, 1)
    :setBackground(colors.white)
    :setForeground(colors.black)
modalQtyInput.text = "64"

local qtyHighlighted = false
modalQtyInput:onClick(function(self)
    if qtyHighlighted then
        self.text = ""
        if self.setValue then pcall(self.setValue, self, "") end
        qtyHighlighted = false
    else
        qtyHighlighted = true
        self:setBackground(colors.lightBlue)
    end
end)

modalQtyInput:onChange(function(self, text)
    if qtyHighlighted then
        qtyHighlighted = false
        self:setBackground(colors.white)
        local clean = text or ""
        local char = clean:sub(-1)
        if not char:match("%d") then char = clean:match("%d") or "" end
        self.text = char
        if self.setValue then pcall(self.setValue, self, char) end
    end
end)

local modalList = addModal:addList()
    :setPosition(2, 4)
    :setSize(modalW - 2, math.max(1, modalH - 6))
    :setBackground(colors.black)
    :setForeground(colors.white)

local modalAddBtn = addModal:addButton()
    :setPosition(2, modalH - 1)
    :setSize(math.floor(modalW / 2) - 2, 1)
    :setText("Add Button")
    :setBackground(colors.green)
    :setForeground(colors.white)

local modalCancelBtn = addModal:addButton()
    :setPosition(math.floor(modalW / 2) + 1, modalH - 1)
    :setSize(math.floor(modalW / 2) - 2, 1)
    :setText("Cancel")
    :setBackground(colors.red)
    :setForeground(colors.white)

local modalFilteredItems = {}

local function populateModalList(filter)
    modalList:clear()
    modalFilteredItems = {}
    filter = (filter or ""):lower()

    for _, it in ipairs(storageItems) do
        if filter == "" or it.displayName:lower():find(filter, 1, true) or it.name:lower():find(filter, 1, true) then
            table.insert(modalFilteredItems, it)
            local dName = it.displayName
            if #dName > (modalW - 14) then dName = dName:sub(1, modalW - 16) .. ".." end
            modalList:addItem(string.format("%-18s x%d", dName, it.total or 0))
        end
    end

    if #modalFilteredItems == 0 then
        modalList:addItem("No items match filter.")
    end
end

modalSearch:onChange(function(self, text)
    populateModalList(text or "")
end)

local selectedModalItem = nil
modalList:onSelect(function(self, item, index)
    if index and modalFilteredItems[index] then
        selectedModalItem = modalFilteredItems[index]
    end
end)

addBtn:onClick(function()
    selectedModalItem = nil
    modalSearch.text = ""
    if modalSearch.setValue then pcall(modalSearch.setValue, modalSearch, "") end
    modalQtyInput.text = "64"
    if modalQtyInput.setValue then pcall(modalQtyInput.setValue, modalQtyInput, "64") end
    modalQtyInput:setBackground(colors.white)
    qtyHighlighted = false
    setModalVisible(true)
    basalt.schedule(function()
        refreshStock()
        populateModalList("")
    end)
end)

modalCancelBtn:onClick(function()
    setModalVisible(false)
end)

modalAddBtn:onClick(function()
    if not selectedModalItem then
        statusLabel.text = "Select an item from the list first!"
        return
    end

    local qty = tonumber(modalQtyInput.text or modalQtyInput.value or "64") or 64
    if qty <= 0 then qty = 64 end

    table.insert(quickOrders, {
        item = selectedModalItem.name,
        displayName = selectedModalItem.displayName,
        count = qty
    })
    saveQuickOrders()
    setModalVisible(false)
    renderQuickOrderGrid()
    statusLabel.text = string.format("Added quick-order: +%d %s", qty, selectedModalItem.displayName)
end)

-- Initial Startup on Screen
if monitor then
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.yellow)
    print("===========================================")
    print("   AETHERVAULT OS | I/O MONITOR STATION    ")
    print("===========================================")
    term.setTextColor(colors.white)
    print("Monitor:       " .. (monitorName or "Attached"))
    print("Station Chest: " .. tostring(stationConfig.chest or "None"))
    print("Station Label: " .. tostring(stationConfig.label))
    print()
    term.setTextColor(colors.green)
    print("Status: Active and rendering to monitor.")
    print("Touch the monitor to interact.")
    term.setTextColor(colors.gray)
    print("Press Ctrl+T to exit.")
    print("===========================================")
end

basalt.schedule(function()
    connectServer()
    refreshStock()
    updateChestLabel()
    renderQuickOrderGrid()
end)

if basalt.run then
    basalt.run()
else
    basalt.autoUpdate()
end

]=]

local filesToDownload = {
    "config.lua",
    "db.lua",
    "net_protocol.lua",
    "storage_server.lua",
    "pocket_client.lua",
    "io_config_tool.lua",
    "io_terminal.lua"
}

term.setTextColor(colors.cyan)
print("Installing AetherVault OS system files...")

for _, filename in ipairs(filesToDownload) do
    write("Writing " .. filename .. "...")
    if embeddedFiles[filename] and writeFile(filename, embeddedFiles[filename]) then
        term.setTextColor(colors.green)
        print(" [OK]")
    else
        term.setTextColor(colors.red)
        print(" [FAILED]")
    end
    term.setTextColor(colors.cyan)
end

-- Download Basalt v2.5 framework directly
if not fs.exists("basalt.lua") then
    term.setTextColor(colors.cyan)
    write("Downloading Basalt v2.5 framework...")
    local resp, err = http.get(BASALT_RAW_URL)
    if resp then
        local code = resp.readAll()
        resp.close()
        writeFile("basalt.lua", code)
        term.setTextColor(colors.green)
        print(" [OK]")
    else
        term.setTextColor(colors.red)
        print(" [FAILED]")
        print("Could not download Basalt framework.")
        return
    end
else
    term.setTextColor(colors.green)
    print("Basalt framework (basalt.lua) is already installed.")
end

print()
term.setTextColor(colors.yellow)
print("Select installation target for this computer:")
term.setTextColor(colors.white)
print("1) Main Storage Server (Attached to wired modems/chests)")
print("2) Wireless Pocket Computer Remote")
print("3) I/O Station & Quick-Order Monitor Terminal (Advanced Monitor + Chest)")
print("4) IO Chest & GPS Setup / Calibration Tool Only")
print("5) Skip startup.lua setup")
print()
write("Select choice (1-5): ")
local choice = read()

local startupTarget = nil
if choice == "1" then
    startupTarget = "storage_server.lua"
elseif choice == "2" then
    startupTarget = "pocket_client.lua"
elseif choice == "3" then
    startupTarget = "io_terminal.lua"
elseif choice == "4" then
    startupTarget = "io_config_tool.lua"
end

if startupTarget then
    writeFile("startup.lua", "shell.run(\"" .. startupTarget .. "\")\n")
    term.setTextColor(colors.green)
    print("Set startup.lua to launch " .. startupTarget .. " on boot!")
end

print()
term.setTextColor(colors.green)
print("Installation complete! All files downloaded.")
print("Run 'storage_server.lua' on main server, 'pocket_client.lua' on pocket computers,")
print("or 'io_terminal.lua' on your I/O quick-order monitor stations.")
