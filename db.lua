-- Database and Storage Engine for CC:Tweaked ME System
local config = require("config")

local db = {}

db.items = {}           -- Aggregated item catalog: { [itemName] = { name, displayName, total, maxCount, locations = {...} } }
db.itemIndex = {}       -- Array list of items for Basalt UI lists: { { name, displayName, total, maxCount }, ... }
db.storageChests = {}   -- List of peripheral names categorized as storage
db.ioChests = {}        -- Cached IO chest peripherals
db.logs = {}            -- Activity log entries for GUI display: { { timestamp, text, type } }
db.isScanning = false

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

-- Find all connected inventory peripherals on wired modem network
function db.discoverPeripherals()
    local names = peripheral.getNames()
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

-- Complete scan of all storage chests and item indexing
function db.scanStorage()
    if db.isScanning then return false end
    db.isScanning = true

    db.discoverPeripherals()

    local newItems = {}
    local totalItemCount = 0
    local lastYield = os.clock()

    for _, chestName in ipairs(db.storageChests) do
        -- Only yield if execution time exceeds 0.4s to prevent lag without artificial delays
        if (os.clock() - lastYield) > 0.4 and coroutine.running() then
            os.sleep(0)
            lastYield = os.clock()
        end

        local p = db.getPeripheral(chestName)
        if p and p.list then
            local ok, list = pcall(p.list)
            if ok and list then
                for slot, item in pairs(list) do
                    if item and item.name and item.count > 0 then
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
            displayName = itemData.displayName,
            total = itemData.total,
            maxCount = itemData.maxCount
        })
    end

    table.sort(indexArray, function(a, b)
        if a.total == b.total then
            return a.displayName:lower() < b.displayName:lower()
        end
        return a.total > b.total
    end)

    db.itemIndex = indexArray
    db.isScanning = false
    return true, #indexArray, totalItemCount
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

            -- Phase 1: Try chests that already contain this item (grouping items together)
            local existingData = db.items[item.name]
            if existingData and existingData.locations then
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
                        end
                        if not pok or not moved or moved < remaining then
                            fullChests[targetChest] = true
                        end
                    end
                end
            end

            -- Phase 2: Put remaining items into any available storage chest
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

return db
