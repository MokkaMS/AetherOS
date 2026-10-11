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

embeddedFiles["config.lua"] = [=[-- Configuration management for CC:Tweaked Storage & ME System
local config = {}

local CONFIG_FILE = "/storage_config.json"

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

embeddedFiles["db.lua"] = [=[-- Database and Storage Engine for CC:Tweaked ME System
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

-- Check if peripheral is an inventory and not ignored
local function isValidInventory(name)
    if config.data.ignoredPeripherals[name] then
        return false
    end
    -- Ignore computer/pocket peripherals if they act as inventories
    if name:find("computer") or name:find("turtle") or name:find("drive") then
        return false
    end
    return peripheral.hasType(name, "inventory")
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

-- Format technical ID to readable display name (e.g. minecraft:iron_ingot -> Iron Ingot)
local function formatDisplayName(technicalName, itemDetail)
    if itemDetail and itemDetail.displayName then
        return itemDetail.displayName
    end
    local id = technicalName:match("[^:]+:(.+)") or technicalName
    id = id:gsub("_", " ")
    return id:gsub("(%a)([%w_']*)", function(first, rest)
        return first:upper() .. rest:lower()
    end)
end

-- Complete scan of all storage chests and item indexing
function db.scanStorage()
    if db.isScanning then return false end
    db.isScanning = true

    db.discoverPeripherals()

    local newItems = {}
    local totalItemCount = 0

    for i, chestName in ipairs(db.storageChests) do
        -- Yield periodically during large chest scans to prevent UI freezing
        if i % 20 == 0 and coroutine.running() then
            os.sleep(0)
        end

        local p = peripheral.wrap(chestName)
        if p and p.list then
            local ok, list = pcall(p.list)
            if ok and list then
                for slot, item in pairs(list) do
                    if item and item.name and item.count > 0 then
                        local key = item.name
                        if not newItems[key] then
                            newItems[key] = {
                                name = item.name,
                                displayName = formatDisplayName(item.name, nil),
                                total = 0,
                                maxCount = 64,
                                locations = {}
                            }
                        end

                        newItems[key].total = newItems[key].total + item.count
                        table.insert(newItems[key].locations, {
                            chest = chestName,
                            slot = slot,
                            count = item.count
                        })
                        totalItemCount = totalItemCount + item.count
                    end
                end
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
        if peripheral.isPresent(pName) then
            if info.role == "both" or info.role == requiredRole or requiredRole == "both" then
                table.insert(candidates, {
                    name = pName,
                    info = info
                })
            end
        end
    end

    -- Fallback: If no registered IO chest matches, check any connected IO chest or storage chest fallback
    if #candidates == 0 then
        if #db.ioChests > 0 then
            return db.ioChests[1], nil -- Return first available IO chest without distance
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

    if not targetIOChest or not peripheral.isPresent(targetIOChest) then
        return 0, "Target IO chest '" .. tostring(targetIOChest) .. "' not present on network"
    end

    local itemData = db.items[itemName]
    if not itemData or itemData.total <= 0 then
        return 0, "Item '" .. itemName .. "' is not in storage"
    end

    local amountNeeded = math.min(count, itemData.total)
    local amountMoved = 0

    local targetP = peripheral.wrap(targetIOChest)
    if not targetP then
        return 0, "Failed to connect to IO chest peripheral"
    end

    -- Move items from storage locations to IO chest
    for _, loc in ipairs(itemData.locations) do
        if amountMoved >= amountNeeded then break end
        
        local p = peripheral.wrap(loc.chest)
        if p and p.pushItems then
            local toTransfer = math.min(amountNeeded - amountMoved, loc.count)
            local ok, moved = pcall(p.pushItems, targetIOChest, loc.slot, toTransfer)
            if ok and moved then
                amountMoved = amountMoved + moved
            end
        end
    end

    -- Re-scan after transfer if not skipped
    if not skipRescan then
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
    if not targetIOChest or not peripheral.isPresent(targetIOChest) then
        return 0, "Target IO chest not available"
    end

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

    db.scanStorage()
    return totalMoved, nil
end

-- Deposit items from an IO chest into storage chests
function db.deposit(sourceIOChest)
    if not sourceIOChest or not peripheral.isPresent(sourceIOChest) then
        return 0, "Source IO chest '" .. tostring(sourceIOChest) .. "' not present"
    end

    -- Ensure storage peripherals are discovered if not yet loaded
    if #db.storageChests == 0 then
        db.discoverPeripherals()
    end

    local sourceP = peripheral.wrap(sourceIOChest)
    if not sourceP or not sourceP.list then
        return 0, "Cannot access source IO chest"
    end

    local ok, sourceList = pcall(sourceP.list)
    if not ok or not sourceList then
        return 0, "Failed to read source IO chest items"
    end

    local totalDeposited = 0

    for slot, item in pairs(sourceList) do
        if item and item.name and item.count > 0 then
            local remaining = item.count

            -- Step 1: Try stacking into existing storage chests containing the same item
            local existingData = db.items[item.name]
            if existingData and existingData.locations then
                for _, loc in ipairs(existingData.locations) do
                    if remaining <= 0 then break end
                    
                    -- Try push from source IO chest first
                    local moved = 0
                    if sourceP and sourceP.pushItems then
                        local pok, res = pcall(sourceP.pushItems, loc.chest, slot, remaining, loc.slot)
                        if pok and res and res > 0 then moved = res end
                    end
                    -- Fallback to pull from destination storage chest
                    if moved == 0 then
                        local destP = peripheral.wrap(loc.chest)
                        if destP and destP.pullItems then
                            local pok, res = pcall(destP.pullItems, sourceIOChest, slot, remaining, loc.slot)
                            if pok and res and res > 0 then moved = res end
                        end
                    end

                    if moved > 0 then
                        remaining = remaining - moved
                        totalDeposited = totalDeposited + moved
                    end
                end
            end

            -- Step 2: Put remaining items into any available storage chest slot
            if remaining > 0 then
                for _, chestName in ipairs(db.storageChests) do
                    if remaining <= 0 then break end
                    
                    local moved = 0
                    if sourceP and sourceP.pushItems then
                        local pok, res = pcall(sourceP.pushItems, chestName, slot, remaining)
                        if pok and res and res > 0 then moved = res end
                    end
                    if moved == 0 then
                        local destP = peripheral.wrap(chestName)
                        if destP and destP.pullItems then
                            local pok, res = pcall(destP.pullItems, sourceIOChest, slot, remaining)
                            if pok and res and res > 0 then moved = res end
                        end
                    end

                    if moved > 0 then
                        remaining = remaining - moved
                        totalDeposited = totalDeposited + moved
                    end
                end
            end
        end
    end

    if totalDeposited > 0 then
        db.scanStorage()
        db.addLog(string.format("Deposited %d items from %s into storage", totalDeposited, sourceIOChest), "deposit")
    end

    return totalDeposited, nil
end

-- Deposit from all registered/discovered IO chests
function db.depositAllIO()
    local grandTotal = 0
    -- Collect IO chests from both config and auto-discovered
    local allIO = {}
    for _, name in ipairs(db.ioChests) do
        allIO[name] = true
    end
    for name, info in pairs(config.getIOChests()) do
        if info.role == "input" or info.role == "both" then
            allIO[name] = true
        end
    end

    for chestName, _ in pairs(allIO) do
        if peripheral.isPresent(chestName) then
            local count, _ = db.deposit(chestName)
            grandTotal = grandTotal + count
        end
    end
    return grandTotal
end

return db
]=]

embeddedFiles["net_protocol.lua"] = [=[-- Network Communication Protocol for CC:Tweaked Wireless Pocket Computers & Storage Server
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

embeddedFiles["io_config_tool.lua"] = [=[-- Interactive IO Chest Configuration & GPS Calibration Tool
-- Supports both local server execution and remote execution over Rednet
local config = require("config")
local net = require("net_protocol")

term.clear()
term.setCursorPos(1, 1)

local serverId = nil
local isRemote = false

local myId = os.getComputerID()
local modemOK, side = net.openWirelessModem()
if modemOK then
    local sId, _ = net.findServer(2)
    if sId and sId ~= myId then
        serverId = sId
        isRemote = true
    end
end

local function drawHeader()
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.yellow)
    print("========================================")
    print("   AetherVault IO & GPS Setup Tool      ")
    print("========================================")
    term.setTextColor(colors.cyan)
    if isRemote then
        print(" Mode: WIRELESS REMOTE (Server #" .. tostring(serverId) .. ")")
    else
        print(" Mode: LOCAL STORAGE SERVER")
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
        local ok, res = net.sendRequest(serverId, "REGISTER_IO_CHEST", payload, 3)
        if ok and res.success then
            return true, res.message or "Registered wirelessly on server!"
        else
            return false, res and res.message or "RPC call failed"
        end
    else
        config.setIOChest(pName, label, x, y, z, role)
        return true, "Registered locally in config!"
    end
end

local function removeIOChest(pName)
    if isRemote then
        local payload = { peripheralName = pName }
        local ok, res = net.sendRequest(serverId, "REMOVE_IO_CHEST", payload, 3)
        if ok and res.success then
            return true, res.message or "Removed wirelessly on server!"
        else
            return false, res and res.message or "RPC call failed"
        end
    else
        config.removeIOChest(pName)
        return true, "Removed locally from config!"
    end
end

local function performTestDeposit()
    if isRemote then
        local ok, res = net.sendRequest(serverId, "DEPOSIT_ITEMS", {}, 4)
        if ok and res.success then
            return res.count or 0, nil
        else
            return 0, res and res.message or "RPC call failed"
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
        print("5) Exit")
        print()
        write("Select option (1-5): ")
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

                    local ok, msg = registerIOChest(pName, label, finalX, finalY, finalZ, role)
                    if ok then
                        term.setTextColor(colors.green)
                        print()
                        print(string.format("Successfully registered '%s' (%s) at [%d, %d, %d]!", pName, label, finalX, finalY, finalZ))
                    else
                        term.setTextColor(colors.red)
                        print("Error: " .. tostring(msg))
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
            term.clear()
            term.setCursorPos(1, 1)
            break
        end
    end
end

main()
]=]

embeddedFiles["storage_server.lua"] = [=[-- Main Server Storage System with Basalt v2.5 GUI & Wireless Rednet Controller
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
local modemOK, modemSide = net.openWirelessModem()
if modemOK then
    rednet.host(config.data.protocol, config.data.hostname)
    db.addLog("Wireless Rednet started on " .. modemSide .. " (" .. config.data.hostname .. ")", "system")
else
    db.addLog("Warning: No wireless modem active. Remote pocket computer control disabled.", "warning")
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
    :setText("Activity Logs")
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
searchInput.placeholder = "Search items..."

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
withdrawQtyInput.text = "64"

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

local function populateItemList(filter)
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
        return filteredItems[idx]
    end

    local itemObj = item or (self and self.getItem and idx and pcall(self.getItem, self, idx) and self:getItem(idx)) or (self and self.getValue and pcall(self.getValue, self) and self:getValue())
    local strText = nil
    if type(itemObj) == "table" then
        if itemObj.value then return itemObj.value end
        if itemObj.name then return itemObj.name end
        if itemObj.args and itemObj.args[1] then return itemObj.args[1] end
        strText = itemObj.text
    elseif type(itemObj) == "string" then
        strText = itemObj
    end

    if strText then
        local cleanName = strText:match("^%[%p%]%s+(.-)%s+%d+$") or strText:match("^%[%p%]%s+(.+)$") or strText
        cleanName = cleanName:gsub("^%s*(.-)%s*$", "%1")
        for _, it in ipairs(db.itemIndex) do
            if it.displayName == cleanName or it.name == cleanName or cleanName:find(it.displayName, 1, true) then
                return it.name
            end
        end
    end

    return nil
end

local function handleSelection(self, item, index)
    if isUpdatingList then return end
    local itemName = resolveSelectedItemName(self, item, index)
    if itemName then
        selectedItems[itemName] = not selectedItems[itemName]
        isUpdatingList = true
        basalt.schedule(function()
            populateItemList(searchInput.text or searchInput.value or "")
            isUpdatingList = false
        end, 0)
    end
end

if itemList.onSelect then itemList:onSelect(handleSelection) end
if itemList.onChange then itemList:onChange(handleSelection) end

searchInput:onChange(function(self, text)
    populateItemList(text or searchInput.text or searchInput.value or "")
end)

autoCompleteBtn:onClick(function()
    if currentAutoMatch then
        searchInput.text = currentAutoMatch.displayName
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
    db.addLog("Refreshing storage index in background...", "info")
    rescanBtn:setText("Scanning..."):setBackground(colors.yellow)
    basalt.schedule(function()
        db.scanStorage()
        populateItemList(searchInput.text or searchInput.value or "")
        rescanBtn:setText("Refresh"):setBackground(colors.green)
        db.addLog("Storage refresh complete.", "info")
    end, 0)
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

    local moved, err = db.withdrawMulti(requests, nearestIO)
    if err then
        db.addLog("Withdraw error: " .. err, "error")
    else
        db.addLog(string.format("Multi-withdraw complete: moved %d total items.", moved), "info")
        selectedItems = {}
        populateItemList(searchInput.text or searchInput.value or "")
    end
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
    :setBackground(colors.white)

local ioDepositBtn = ioFrame:addButton()
    :setPosition(1, math.max(1, contentH - 1))
    :setSize(24, 1)
    :setText("Deposit All IO Chests")
    :setBackground(colors.green)

local function populateIOList()
    ioList:clear()
    local registered = config.getIOChests()
    local allPeripherals = peripheral.getNames()
    local seen = {}

    -- First list all registered IO chests
    for pName, data in pairs(registered) do
        local isPresent, actualPName = config.isPeripheralPresent(pName)
        seen[pName] = true
        local stripped = pName:match("[^:]+:(.+)") or pName
        seen[stripped] = true
        if actualPName then
            seen[actualPName] = true
            local actualStripped = actualPName:match("[^:]+:(.+)") or actualPName
            seen[actualStripped] = true
        end

        local status = isPresent and "[ONLINE]" or "[OFFLINE]"
        local label = data.label or pName
        if #label > 14 then label = label:sub(1, 12) .. ".." end
        local text = string.format("%-9s IO: %-14s [%d,%d,%d] Role:%s", status, label, data.x or 0, data.y or 0, data.z or 0, data.role or "both")
        ioList:addItem(text)
    end

    -- Also list all remaining connected storage inventories on network
    for _, name in ipairs(allPeripherals) do
        if peripheral.hasType(name, "inventory") and not name:find("computer") and not name:find("turtle") and not name:find("drive") then
            local stripped = name:match("[^:]+:(.+)") or name
            if not seen[name] and not seen[stripped] and not config.isIOChest(name) then
                seen[name] = true
                seen[stripped] = true
                local label = name
                if #label > 16 then label = label:sub(1, 14) .. ".." end
                local text = string.format("[ONLINE]  STORAGE: %-16s (Connected)", label)
                ioList:addItem(text)
            end
        end
    end
end

ioDepositBtn:onClick(function()
    db.addLog("Executing manual deposit from all IO chests...", "info")
    local moved, _ = db.depositAllIO()
    db.addLog(string.format("Manual IO Deposit complete: imported %d items.", moved), "info")
    populateIOList()
    populateItemList(searchInput.text or searchInput.value or "")
end)

---------------------------------------------------------
-- TAB 3: ACTIVITY LOGS
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
    for _, log in ipairs(db.logs) do
        local text = string.format("[%s] %s", log.timestamp, log.text)
        logsList:addItem(text)
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
settingsFrame:addLabel():setPosition(2, 4):setText("Scan Interval: " .. config.data.scanInterval .. " seconds")

local autoDepositBtn = settingsFrame:addButton()
    :setPosition(2, 6)
    :setSize(24, 1)
    :setText("Auto Deposit: " .. (config.data.autoDeposit and "ENABLED" or "DISABLED"))
    :setBackground(config.data.autoDeposit and colors.green or colors.red)

autoDepositBtn:onClick(function()
    config.data.autoDeposit = not config.data.autoDeposit
    config.save()
    autoDepositBtn:setText("Auto Deposit: " .. (config.data.autoDeposit and "ENABLED" or "DISABLED"))
        :setBackground(config.data.autoDeposit and colors.green or colors.red)
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
-- BACKGROUND REDNET LISTENER (NON-BLOCKING SCHEDULE)
---------------------------------------------------------
basalt.schedule(function()
    while true do
        local senderId, message, protocol = rednet.receive(config.data.protocol, 0)
        if not senderId then break end

        if type(message) == "table" and message.cmd then
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

                local targetIO, dist, info = db.findNearestIOChest(gpsPos, "output")
                
                if not targetIO then
                    response = { success = false, message = "No IO chest available on network!" }
                else
                    local moved, err = db.withdraw(itemName, count, targetIO)
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
                local sourceIO, dist, info = db.findNearestIOChest(gpsPos, "input")

                if not sourceIO then
                    response = { success = false, message = "No IO chest available for deposit!" }
                else
                    local moved, err = db.deposit(sourceIO)
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
                else
                    response = { success = false, message = "Missing peripheralName parameter" }
                end
            end

            rednet.send(senderId, response, config.data.protocol)
            populateItemList(searchInput.text or searchInput.value or "")
        end
    end
end, 0.1)

basalt.schedule(function()
    if config.data.autoDeposit then
        db.depositAllIO()
    else
        db.scanStorage()
    end
    updateStatsDisplay()
end, config.data.scanInterval or 5)

if basalt.run then
    basalt.run()
else
    basalt.autoUpdate()
end
]=]

embeddedFiles["pocket_client.lua"] = [=[-- Pocket Computer Wireless Remote Client with Basalt v2.5 GUI
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

local function populateList()
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
    updateWithdrawButtonText()
end

local function fetchItems()
    updateGPS()
    
    if not serverId then
        statusLabel.text = " Searching for server..."
        local sId, errStr = net.findServer(2)
        if not sId then
            statusLabel.text = " Error: Server offline"
            return
        end
        serverId = sId
    end

    statusLabel.text = " Fetching catalog..."
    local ok, res = net.sendRequest(serverId, "GET_ITEMS", {}, 2.5)
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
        return filteredItems[idx]
    end

    local itemObj = item or (self and self.getItem and idx and pcall(self.getItem, self, idx) and self:getItem(idx)) or (self and self.getValue and pcall(self.getValue, self) and self:getValue())
    local strText = nil
    if type(itemObj) == "table" then
        if itemObj.value then return itemObj.value end
        if itemObj.name then return itemObj.name end
        if itemObj.args and itemObj.args[1] then return itemObj.args[1] end
        strText = itemObj.text
    elseif type(itemObj) == "string" then
        strText = itemObj
    end

    if strText then
        local cleanName = strText:match("^%[%p%]%s+(.-)%s+%d+$") or strText:match("^%[%p%]%s+(.+)$") or strText
        cleanName = cleanName:gsub("^%s*(.-)%s*$", "%1")
        for _, it in ipairs(currentItems) do
            if it.displayName == cleanName or it.name == cleanName or cleanName:find(it.displayName, 1, true) then
                return it.name
            end
        end
    end

    return nil
end

local function handleSelection(self, item, index)
    if isUpdatingList then return end
    local itemName = resolveSelectedItemName(self, item, index)
    if itemName then
        selectedItems[itemName] = not selectedItems[itemName]
        isUpdatingList = true
        basalt.schedule(function()
            populateList()
            isUpdatingList = false
        end, 0)
    end
end

if itemList.onSelect then itemList:onSelect(handleSelection) end
if itemList.onChange then itemList:onChange(handleSelection) end

searchInput:onChange(function(self, text)
    populateList()
end)

autoBtn:onClick(function()
    if currentAutoMatch then
        searchInput.text = currentAutoMatch.displayName
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

    if not serverId then
        fetchItems()
        if not serverId then return end
    end

    statusLabel.text = " Withdrawing selection..."
    local payload = {
        requests = requests,
        gpsPos = playerPos
    }

    local ok, res = net.sendRequest(serverId, "WITHDRAW_MULTI", payload, 4)
    if ok and res.success then
        local distStr = res.distance and string.format(" (%.1fm)", res.distance) or ""
        statusLabel.text = string.format(" Moved x%d to %s%s", res.moved or 0, res.chestLabel or "IO", distStr)
        selectedItems = {}
        fetchItems()
    else
        statusLabel.text = " Error: " .. (res and res.message or "Timeout")
    end
end)

depositBtn:onClick(function()
    if not serverId then
        fetchItems()
        if not serverId then return end
    end

    statusLabel.text = " Requesting deposit..."
    local payload = {
        gpsPos = playerPos
    }

    local ok, res = net.sendRequest(serverId, "DEPOSIT_ITEMS", payload, 3)
    if ok and res.success then
        local distStr = res.distance and string.format(" (%.1fm)", res.distance) or ""
        statusLabel.text = string.format(" Deposited x%d from %s%s", res.count or 0, res.chestLabel or "IO", distStr)
        fetchItems()
    else
        statusLabel.text = " Error: " .. (res and res.message or "Timeout")
    end
end)

refreshBtn:onClick(function()
    fetchItems()
end)

fetchItems()

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
    "io_config_tool.lua"
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
print("3) IO Chest & GPS Setup / Calibration Tool Only")
print("4) Skip startup.lua setup")
print()
write("Select choice (1-4): ")
local choice = read()

local startupTarget = nil
if choice == "1" then
    startupTarget = "storage_server.lua"
elseif choice == "2" then
    startupTarget = "pocket_client.lua"
elseif choice == "3" then
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
print("Run 'storage_server.lua' on main server, or 'pocket_client.lua' on pocket computers.")
