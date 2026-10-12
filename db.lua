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

    -- Filter connected & registered IO chests that are verified INVENTORIES
    for pName, info in pairs(ioConfig) do
        local isPresent, actualName = config.isPeripheralPresent(pName)
        if isPresent and actualName and peripheral.hasType(actualName, "inventory") then
            local p = db.getPeripheral(actualName)
            if p and p.list then
                if info.role == "both" or info.role == requiredRole or requiredRole == "both" then
                    table.insert(candidates, {
                        name = actualName,
                        info = info
                    })
                end
            end
        end
    end

    -- Fallback: If no registered IO chest matches, check any connected IO chest
    if #candidates == 0 then
        if #db.ioChests > 0 then
            for _, cName in ipairs(db.ioChests) do
                local isPresent, actualName = config.isPeripheralPresent(cName)
                if isPresent and actualName and peripheral.hasType(actualName, "inventory") then
                    local p = db.getPeripheral(actualName)
                    if p and p.list then
                        return actualName, nil, { label = actualName, x = 0, y = 0, z = 0, role = "both" }
                    end
                end
            end
        end
        return nil, "No valid connected IO chest found on network!"
    end

    -- If player position is provided (GPS coordinates)
    if playerPos and playerPos.x and playerPos.y and playerPos.z then
        local nearest = nil
        local minDistance = math.huge

        for _, item in ipairs(candidates) do
            -- Only measure against chests with calibrated coordinates (not default 0,0,0 unless player is at 0,0,0)
            local hasCoords = (item.info.x ~= 0 or item.info.y ~= 0 or item.info.z ~= 0)
            if hasCoords then
                local dist = calculateDistance(playerPos, item.info)
                if dist < minDistance then
                    minDistance = dist
                    nearest = item
                end
            end
        end

        if nearest then
            return nearest.name, minDistance, nearest.info
        end
    end

    -- Default fallback if GPS is not available or chests lack coordinates:
    -- Prefer candidates with friendly labels or calibrated coordinates
    table.sort(candidates, function(a, b)
        local aHas = (a.info.x ~= 0 or a.info.y ~= 0 or a.info.z ~= 0) and 1 or 0
        local bHas = (b.info.x ~= 0 or b.info.y ~= 0 or b.info.z ~= 0) and 1 or 0
        if aHas ~= bHas then return aHas > bHas end
        return tostring(a.info.label or a.name) < tostring(b.info.label or b.name)
    end)

    local defaultChest = candidates[1]
    return defaultChest.name, nil, defaultChest.info
end

-- Withdraw specified amount of item to a target IO chest
function db.withdraw(itemName, count, targetIOChest, skipRescan)
    if not itemName or not count or count <= 0 then
        return 0, "Invalid item request arguments"
    end

    local isPresent, actualTarget = config.isPeripheralPresent(targetIOChest)
    if not isPresent or not actualTarget then
        return 0, "Target IO chest '" .. tostring(targetIOChest) .. "' not present on network"
    end
    targetIOChest = actualTarget

    if not peripheral.hasType(targetIOChest, "inventory") then
        return 0, "Target '" .. tostring(targetIOChest) .. "' is not an inventory peripheral"
    end

    local targetP = db.getPeripheral(targetIOChest)
    if not targetP or not targetP.list then
        return 0, "Failed to connect to IO chest peripheral '" .. tostring(targetIOChest) .. "'"
    end

    local itemData = db.items[itemName]
    if not itemData or itemData.total <= 0 then
        return 0, "Item '" .. itemName .. "' is not in storage"
    end

    local amountNeeded = math.min(count, itemData.total)
    local amountMoved = 0

    -- Move items from storage locations to IO chest
    local activeLocations = {}
    local pushErrorEncountered = false
    local lastErrorMsg = nil

    for _, loc in ipairs(itemData.locations) do
        if amountMoved < amountNeeded and loc.count > 0 and not pushErrorEncountered then
            local p = db.getPeripheral(loc.chest)
            if p and p.pushItems then
                local toTransfer = math.min(amountNeeded - amountMoved, loc.count)
                local ok, moved = pcall(p.pushItems, targetIOChest, loc.slot, toTransfer)
                if ok and moved and moved > 0 then
                    amountMoved = amountMoved + moved
                    loc.count = loc.count - moved
                elseif not ok then
                    -- Peripheral push call failed (e.g. unknown network peripheral or unreachable block)
                    -- Abort immediately to prevent hanging/timing out across 560 chests!
                    pushErrorEncountered = true
                    lastErrorMsg = tostring(moved)
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

    if pushErrorEncountered and amountMoved == 0 then
        return 0, "Push failed to target IO chest: " .. tostring(lastErrorMsg or "peripheral unreachable")
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
    if not isPresent or not actualTarget then
        return 0, "Target IO chest '" .. tostring(targetIOChest) .. "' not present on network"
    end
    targetIOChest = actualTarget

    if not peripheral.hasType(targetIOChest, "inventory") then
        return 0, "Target '" .. tostring(targetIOChest) .. "' is not an inventory peripheral"
    end

    local totalMoved = 0
    for _, req in ipairs(requests) do
        if req.item then
            local qty = req.all and (db.items[req.item] and db.items[req.item].total or 0) or (req.count or 64)
            if qty > 0 then
                local moved, err = db.withdraw(req.item, qty, targetIOChest, true)
                totalMoved = totalMoved + (moved or 0)
                if err and totalMoved == 0 then
                    return 0, err
                end
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
    if not isPresent or not actualSource then
        return 0, "Source IO chest '" .. tostring(sourceIOChest) .. "' not present on network"
    end
    sourceIOChest = actualSource

    if not peripheral.hasType(sourceIOChest, "inventory") then
        return 0, "Source '" .. tostring(sourceIOChest) .. "' is not an inventory peripheral"
    end

    if #db.storageChests == 0 then
        db.discoverPeripherals()
    end

    local sourceP = db.getPeripheral(sourceIOChest)
    if not sourceP or not sourceP.list then
        return 0, "Cannot access source IO chest peripheral '" .. tostring(sourceIOChest) .. "'"
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
