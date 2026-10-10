-- Self-Contained Complete Installer for AetherVault OS (CC:Tweaked)
local BASALT_INSTALL_URL = "https://basalt.madefor.cc/2.5/install.lua"
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

-- Helper function to write embedded code files
local function writeFile(filename, code)
    local file = fs.open(filename, "w")
    if file then
        file.write(code)
        file.close()
        return true
    end
    return false
end

-- Embedded System Files Table
local files = {}

files["config.lua"] = [=[-- Configuration management for AetherVault OS
local config = {}

local CONFIG_FILE = "storage_config.json"

config.data = {
    protocol = "AETHER_VAULT_NET",
    hostname = "aether_vault_server",
    scanInterval = 5, -- seconds between automatic inventory scans
    autoDeposit = true, -- automatically import items placed in IO chests during scan
    ioChests = {}, -- format: { [peripheralName] = { label = "Main IO", x = 0, y = 64, z = 0, role = "both" } }
    ignoredPeripherals = {}, -- peripheral names to ignore
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
        role = role or "both"
    }
    config.save()
end

function config.removeIOChest(peripheralName)
    config.data.ioChests[peripheralName] = nil
    config.save()
end

function config.getIOChests()
    return config.data.ioChests
end

function config.isIOChest(peripheralName)
    return config.data.ioChests[peripheralName] ~= nil
end

config.load()
return config
]=]

files["db.lua"] = [=[-- Database and Storage Engine for AetherVault OS
local config = require("config")

local db = {}

db.items = {}           
db.itemIndex = {}       
db.storageChests = {}   
db.ioChests = {}        
db.logs = {}            
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

local function isValidInventory(name)
    if config.data.ignoredPeripherals[name] then
        return false
    end
    if name:find("computer") or name:find("turtle") or name:find("drive") then
        return false
    end
    return peripheral.hasType(name, "inventory")
end

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

function db.scanStorage()
    if db.isScanning then return false end
    db.isScanning = true

    db.discoverPeripherals()

    local newItems = {}
    local totalItemCount = 0

    for _, chestName in ipairs(db.storageChests) do
        local p = peripheral.wrap(chestName)
        if p and p.list then
            local ok, list = pcall(p.list)
            if ok and list then
                for slot, item in pairs(list) do
                    if item and item.name and item.count > 0 then
                        local key = item.name
                        if not newItems[key] then
                            local detail = nil
                            if p.getItemDetail then
                                ok, detail = pcall(p.getItemDetail, slot)
                            end
                            
                            newItems[key] = {
                                name = item.name,
                                displayName = formatDisplayName(item.name, detail),
                                total = 0,
                                maxCount = (detail and detail.maxCount) or 64,
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
        return a.displayName:lower() < b.displayName:lower()
    end)

    db.itemIndex = indexArray
    db.isScanning = false
    return true, #indexArray, totalItemCount
end

local function calculateDistance(pos1, pos2)
    local dx = (pos1.x or 0) - (pos2.x or 0)
    local dy = (pos1.y or 0) - (pos2.y or 0)
    local dz = (pos1.z or 0) - (pos2.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function db.findNearestIOChest(playerPos, requiredRole)
    requiredRole = requiredRole or "both"
    local ioConfig = config.getIOChests()
    local candidates = {}

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

    if #candidates == 0 then
        if #db.ioChests > 0 then
            return db.ioChests[1], nil
        end
        return nil, "No connected IO chest found!"
    end

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

    local defaultChest = candidates[1]
    return defaultChest.name, nil, defaultChest.info
end

function db.withdraw(itemName, count, targetIOChest)
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

    db.scanStorage()
    db.addLog(string.format("Withdrew %d x %s to %s", amountMoved, itemData.displayName, targetIOChest), "withdraw")
    return amountMoved, nil
end

function db.deposit(sourceIOChest)
    if not sourceIOChest or not peripheral.isPresent(sourceIOChest) then
        return 0, "Source IO chest '" .. tostring(sourceIOChest) .. "' not present"
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

            local existingData = db.items[item.name]
            if existingData and existingData.locations then
                for _, loc in ipairs(existingData.locations) do
                    if remaining <= 0 then break end
                    local destP = peripheral.wrap(loc.chest)
                    if destP and destP.pullItems then
                        local pok, moved = pcall(destP.pullItems, sourceIOChest, slot, remaining, loc.slot)
                        if pok and moved and moved > 0 then
                            remaining = remaining - moved
                            totalDeposited = totalDeposited + moved
                        end
                    end
                end
            end

            if remaining > 0 then
                for _, chestName in ipairs(db.storageChests) do
                    if remaining <= 0 then break end
                    local destP = peripheral.wrap(chestName)
                    if destP and destP.pullItems then
                        local pok, moved = pcall(destP.pullItems, sourceIOChest, slot, remaining)
                        if pok and moved and moved > 0 then
                            remaining = remaining - moved
                            totalDeposited = totalDeposited + moved
                        end
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

function db.depositAllIO()
    local grandTotal = 0
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

files["net_protocol.lua"] = [=[-- Network Communication Protocol for AetherVault OS
local config = require("config")

local net = {}

function net.openWirelessModem()
    local modem = peripheral.find("modem", function(name, wrapped)
        return wrapped.isWireless()
    end)
    if modem then
        local modemSide = peripheral.getName(modem)
        rednet.open(modemSide)
        return true, modemSide
    end
    for _, side in ipairs(rs.getSides()) do
        if peripheral.isPresent(side) and peripheral.getType(side) == "modem" then
            rednet.open(side)
            return true, side
        end
    end
    return false, "No wireless modem found!"
end

function net.findServer(timeout)
    timeout = timeout or 2
    local serverId = rednet.lookup(config.data.protocol, config.data.hostname)
    if serverId then
        return serverId
    end
    return nil, "Storage Server not found on Rednet channel " .. config.data.protocol
end

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
]=]

files["io_config_tool.lua"] = [=[-- Interactive IO Chest Configuration & GPS Calibration Tool
local config = require("config")

term.clear()
term.setCursorPos(1, 1)

local function drawHeader()
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.yellow)
    print("========================================")
    print("   AetherVault IO & GPS Setup Tool      ")
    print("========================================")
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

local function main()
    while true do
        drawHeader()
        print("1) List Connected & Configured IO Chests")
        print("2) Register / Edit IO Chest (with GPS)")
        print("3) Remove Registered IO Chest")
        print("4) Perform Test Deposit from IO Chest")
        print("5) Exit")
        print()
        write("Select option (1-5): ")
        local choice = read()

        if choice == "1" then
            drawHeader()
            print("Registered IO Chests in config:")
            local ioChests = config.getIOChests()
            local count = 0
            for pName, data in pairs(ioChests) do
                count = count + 1
                local present = peripheral.isPresent(pName) and "[CONNECTED]" or "[MISSING]"
                term.setTextColor(present:find("CONNECTED") and colors.green or colors.red)
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
            if #inventories == 0 then
                term.setTextColor(colors.red)
                print("No inventory peripherals found connected to wired modems!")
                write("Press Enter to return...")
                read()
            else
                for i, name in ipairs(inventories) do
                    local isRegistered = config.isIOChest(name) and " [REG]" or ""
                    print(string.format("%d) %s%s", i, name, isRegistered))
                end
                print()
                write("Select inventory number to register: ")
                local num = tonumber(read())
                if num and inventories[num] then
                    local pName = inventories[num]
                    drawHeader()
                    print("Configuring IO Chest: " .. pName)
                    print()
                    write("Enter friendly label (e.g., Main IO, Base Mine): ")
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

                    config.setIOChest(pName, label, finalX, finalY, finalZ, role)
                    term.setTextColor(colors.green)
                    print()
                    print(string.format("Successfully registered '%s' (%s) at [%d, %d, %d]!", pName, label, finalX, finalY, finalZ))
                    write("Press Enter to continue...")
                    read()
                end
            end

        elseif choice == "3" then
            drawHeader()
            local ioChests = config.getIOChests()
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
                    config.removeIOChest(list[num])
                    term.setTextColor(colors.green)
                    print("Removed " .. list[num])
                end
            end
            write("Press Enter to continue...")
            read()

        elseif choice == "4" then
            local db = require("db")
            drawHeader()
            print("Scanning & performing test deposit...")
            local count, err = db.depositAllIO()
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

files["storage_server.lua"] = [=[-- Main Server Storage System with Basalt v2.5 GUI & Wireless Rednet Controller
local config = require("config")
local db = require("db")
local net = require("net_protocol")

local basaltOK, basalt = pcall(require, "basalt")
if not basaltOK then
    term.setTextColor(colors.red)
    print("Error: Basalt framework v2.5 is not installed!")
    print("Run installer.lua to download Basalt automatically.")
    return
end

local modemOK, modemSide = net.openWirelessModem()
if modemOK then
    rednet.host(config.data.protocol, config.data.hostname)
    db.addLog("Wireless Rednet started on " .. modemSide .. " (" .. config.data.hostname .. ")", "system")
else
    db.addLog("Warning: No wireless modem active. Remote pocket computer control disabled.", "warning")
end

db.scanStorage()
db.addLog("Storage system initialized.", "system")

local mainFrame = (basalt.getMainFrame and basalt.getMainFrame()) or basalt.createFrame()
mainFrame:setBackground(colors.lightGray)

local titleBar = mainFrame:addFrame()
    :setPosition(1, 1)
    :setSize("parent.w", 3)
    :setBackground(colors.gray)

local titleLabel = titleBar:addLabel()
    :setPosition(2, 1)
    :setForeground(colors.white)
    :setText("AETHERVAULT OS v2.5 | SPATIAL STORAGE MATRIX")

local statsLabel = titleBar:addLabel()
    :setPosition(2, 2)
    :setForeground(colors.yellow)
    :setText("Items: 0 | Types: 0 | IO Chests: 0")

local function updateStatsDisplay()
    local typeCount = #db.itemIndex
    local totalItems = 0
    for _, it in ipairs(db.itemIndex) do
        totalItems = totalItems + it.total
    end
    local ioCount = 0
    for _ in pairs(config.getIOChests()) do ioCount = ioCount + 1 end
    statsLabel:setText(string.format("Items: %d | Types: %d | IO Chests: %d", totalItems, typeCount, ioCount))
end

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

local contentFrame = mainFrame:addFrame()
    :setPosition(1, 5)
    :setSize("parent.w", "parent.h - 4")
    :setBackground(colors.lightGray)

local itemsFrame = contentFrame:addFrame()
    :setPosition(1, 1)
    :setSize("parent.w", "parent.h")

local searchInput = itemsFrame:addInput()
    :setPosition(1, 1)
    :setSize("parent.w - 14", 1)
    :setPlaceholder("Search items...")

local rescanBtn = itemsFrame:addButton()
    :setPosition("parent.w - 12", 1)
    :setSize(12, 1)
    :setText("Refresh")
    :setBackground(colors.green)
    :setForeground(colors.white)

local itemList = itemsFrame:addList()
    :setPosition(1, 3)
    :setSize("parent.w", "parent.h - 5")
    :setBackground(colors.white)
    :setForeground(colors.black)

local withdrawBox = itemsFrame:addFrame()
    :setPosition(1, "parent.h - 1")
    :setSize("parent.w", 2)
    :setBackground(colors.gray)

local withdrawQtyInput = withdrawBox:addInput()
    :setPosition(1, 1)
    :setSize(8, 1)
    :setDefaultText("64")

local withdrawBtn = withdrawBox:addButton()
    :setPosition(10, 1)
    :setSize(22, 1)
    :setText("Withdraw to Closest IO")
    :setBackground(colors.orange)

local function populateItemList(filter)
    itemList:clear()
    filter = filter and filter:lower() or ""
    
    for _, item in ipairs(db.itemIndex) do
        if filter == "" or item.displayName:lower():find(filter, 1, true) or item.name:lower():find(filter, 1, true) then
            local entryText = string.format("%-28s x%d", item.displayName, item.total)
            itemList:addItem(entryText, nil, nil, item.name)
        end
    end
    updateStatsDisplay()
end

searchInput:onChange(function(self, text)
    populateItemList(text)
end)

rescanBtn:onClick(function()
    db.scanStorage()
    populateItemList(searchInput:getValue())
    db.addLog("Manual index refresh triggered.", "info")
end)

withdrawBtn:onClick(function()
    local selected = itemList:getItem(itemList:getItemIndex())
    if not selected or not selected.args or not selected.args[1] then
        db.addLog("Select an item from the list first!", "warning")
        return
    end

    local itemName = selected.args[1]
    local count = tonumber(withdrawQtyInput:getValue()) or 64
    
    local nearestIO, dist, info = db.findNearestIOChest(nil, "output")
    if not nearestIO then
        db.addLog("No IO chest available for withdrawal!", "error")
        return
    end

    local moved, err = db.withdraw(itemName, count, nearestIO)
    if err then
        db.addLog("Withdraw error: " .. err, "error")
    else
        populateItemList(searchInput:getValue())
    end
end)

local ioFrame = contentFrame:addFrame()
    :setPosition(1, 1)
    :setSize("parent.w", "parent.h")
    :hide()

local ioList = ioFrame:addList()
    :setPosition(1, 1)
    :setSize("parent.w", "parent.h - 3")
    :setBackground(colors.white)

local ioDepositBtn = ioFrame:addButton()
    :setPosition(1, "parent.h - 1")
    :setSize(24, 1)
    :setText("Deposit All IO Chests")
    :setBackground(colors.green)

local function populateIOList()
    ioList:clear()
    local registered = config.getIOChests()
    for pName, data in pairs(registered) do
        local present = peripheral.isPresent(pName) and "[ONLINE]" or "[OFFLINE]"
        local text = string.format("%s %-16s [%d, %d, %d] Role: %s", present, data.label, data.x, data.y, data.z, data.role)
        ioList:addItem(text)
    end
end

ioDepositBtn:onClick(function()
    local moved, _ = db.depositAllIO()
    db.addLog(string.format("Manual IO Deposit: imported %d items.", moved), "info")
    populateItemList(searchInput:getValue())
end)

local logsFrame = contentFrame:addFrame()
    :setPosition(1, 1)
    :setSize("parent.w", "parent.h")
    :hide()

local logsList = logsFrame:addList()
    :setPosition(1, 1)
    :setSize("parent.w", "parent.h")
    :setBackground(colors.black)
    :setForeground(colors.green)

local function populateLogs()
    logsList:clear()
    for _, log in ipairs(db.logs) do
        local text = string.format("[%s] %s", log.timestamp, log.text)
        logsList:addItem(text)
    end
end

local settingsFrame = contentFrame:addFrame()
    :setPosition(1, 1)
    :setSize("parent.w", "parent.h")
    :hide()

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

local function setActiveTab(tab)
    itemsFrame:hide()
    ioFrame:hide()
    logsFrame:hide()
    settingsFrame:hide()

    tabItemsBtn:setBackground(colors.cyan):setForeground(colors.black)
    tabIOBtn:setBackground(colors.cyan):setForeground(colors.black)
    tabLogsBtn:setBackground(colors.cyan):setForeground(colors.black)
    tabSettingsBtn:setBackground(colors.cyan):setForeground(colors.black)

    if tab == "items" then
        itemsFrame:show()
        tabItemsBtn:setBackground(colors.blue):setForeground(colors.white)
        populateItemList(searchInput:getValue())
    elseif tab == "io" then
        ioFrame:show()
        tabIOBtn:setBackground(colors.blue):setForeground(colors.white)
        populateIOList()
    elseif tab == "logs" then
        logsFrame:show()
        tabLogsBtn:setBackground(colors.blue):setForeground(colors.white)
        populateLogs()
    elseif tab == "settings" then
        settingsFrame:show()
        tabSettingsBtn:setBackground(colors.blue):setForeground(colors.white)
    end
end

tabItemsBtn:onClick(function() setActiveTab("items") end)
tabIOBtn:onClick(function() setActiveTab("io") end)
tabLogsBtn:onClick(function() setActiveTab("logs") end)
tabSettingsBtn:onClick(function() setActiveTab("settings") end)

setActiveTab("items")

mainFrame:addThread(function()
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
            end

            rednet.send(senderId, response, config.data.protocol)
            populateItemList(searchInput:getValue())
        end
    end
end)

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

files["pocket_client.lua"] = [=[-- Pocket Computer Wireless Remote Client with Basalt v2.5 GUI
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

local mainFrame = (basalt.getMainFrame and basalt.getMainFrame()) or basalt.createFrame()
mainFrame:setSize(26, 20):setBackground(colors.black)

local titleLabel = mainFrame:addLabel()
    :setPosition(1, 1)
    :setSize(26, 1)
    :setBackground(colors.blue)
    :setForeground(colors.white)
    :setText(" AETHERVAULT REMOTE ")

local gpsLabel = mainFrame:addLabel()
    :setPosition(1, 2)
    :setSize(26, 1)
    :setBackground(colors.gray)
    :setForeground(colors.yellow)
    :setText(" GPS: Locating...")

local searchInput = mainFrame:addInput()
    :setPosition(1, 3)
    :setSize(26, 1)
    :setPlaceholder(" Search items...")
    :setBackground(colors.white)
    :setForeground(colors.black)

local itemList = mainFrame:addList()
    :setPosition(1, 4)
    :setSize(26, 9)
    :setBackground(colors.lightGray)
    :setForeground(colors.black)

local qtyLabel = mainFrame:addLabel()
    :setPosition(1, 13)
    :setText("Qty:")
    :setForeground(colors.white)

local qtyInput = mainFrame:addInput()
    :setPosition(6, 13)
    :setSize(6, 1)
    :setDefaultText("64")
    :setBackground(colors.white)
    :setForeground(colors.black)

local preset16Btn = mainFrame:addButton()
    :setPosition(13, 13)
    :setSize(6, 1)
    :setText("x16")
    :setBackground(colors.cyan)
    :setForeground(colors.white)

local preset64Btn = mainFrame:addButton()
    :setPosition(20, 13)
    :setSize(6, 1)
    :setText("x64")
    :setBackground(colors.cyan)
    :setForeground(colors.white)

local withdrawBtn = mainFrame:addButton()
    :setPosition(1, 15)
    :setSize(26, 1)
    :setText("Withdraw (Nearest IO)")
    :setBackground(colors.orange)
    :setForeground(colors.white)

local depositBtn = mainFrame:addButton()
    :setPosition(1, 16)
    :setSize(26, 1)
    :setText("Deposit Here (Nearest IO)")
    :setBackground(colors.green)
    :setForeground(colors.white)

local statusLabel = mainFrame:addLabel()
    :setPosition(1, 17)
    :setSize(26, 2)
    :setForeground(colors.yellow)
    :setText(" Connecting to network...")

local refreshBtn = mainFrame:addButton()
    :setPosition(1, 19)
    :setSize(26, 1)
    :setText("Refresh Server & GPS")
    :setBackground(colors.gray)
    :setForeground(colors.white)

local function updateGPS()
    local x, y, z = gps.locate(1.5)
    if x and y and z then
        playerPos = { x = math.floor(x), y = math.floor(y), z = math.floor(z) }
        gpsLabel:setText(string.format(" GPS: %d, %d, %d", playerPos.x, playerPos.y, playerPos.z))
    else
        playerPos = nil
        gpsLabel:setText(" GPS: Signal Unavailable")
    end
end

local function fetchItems()
    updateGPS()
    
    if not serverId then
        statusLabel:setText(" Searching for server...")
        local sId, errStr = net.findServer(2)
        if not sId then
            statusLabel:setText(" Error: Server offline")
            return
        end
        serverId = sId
    end

    statusLabel:setText(" Fetching catalog...")
    local ok, res = net.sendRequest(serverId, "GET_ITEMS", {}, 2.5)
    if ok and res.success and res.items then
        currentItems = res.items
        itemList:clear()
        local filter = searchInput:getValue():lower()
        
        for _, item in ipairs(currentItems) do
            if filter == "" or item.displayName:lower():find(filter, 1, true) then
                local text = string.format("%-16s x%d", item.displayName:sub(1, 15), item.total)
                itemList:addItem(text, nil, nil, item.name)
            end
        end
        statusLabel:setText(" Connected: " .. #currentItems .. " item types")
    else
        serverId = nil
        statusLabel:setText(" Connection failed!")
    end
end

searchInput:onChange(function(self, text)
    itemList:clear()
    text = text:lower()
    for _, item in ipairs(currentItems) do
        if text == "" or item.displayName:lower():find(text, 1, true) then
            local entry = string.format("%-16s x%d", item.displayName:sub(1, 15), item.total)
            itemList:addItem(entry, nil, nil, item.name)
        end
    end
end)

preset16Btn:onClick(function() qtyInput:setValue("16") end)
preset64Btn:onClick(function() qtyInput:setValue("64") end)

withdrawBtn:onClick(function()
    local selected = itemList:getItem(itemList:getItemIndex())
    if not selected or not selected.args or not selected.args[1] then
        statusLabel:setText(" Select an item first!")
        return
    end

    local itemName = selected.args[1]
    local count = tonumber(qtyInput:getValue()) or 64

    if not serverId then
        fetchItems()
        if not serverId then return end
    end

    statusLabel:setText(" Sending withdraw request...")
    local payload = {
        item = itemName,
        count = count,
        gpsPos = playerPos
    }

    local ok, res = net.sendRequest(serverId, "WITHDRAW_ITEM", payload, 3)
    if ok and res.success then
        local distStr = res.distance and string.format(" (%.1fm)", res.distance) or ""
        statusLabel:setText(string.format(" Moved x%d to %s%s", res.moved or 0, res.chestLabel or "IO", distStr))
        fetchItems()
    else
        statusLabel:setText(" Error: " .. (res and res.message or "Timeout"))
    end
end)

depositBtn:onClick(function()
    if not serverId then
        fetchItems()
        if not serverId then return end
    end

    statusLabel:setText(" Requesting deposit...")
    local payload = {
        gpsPos = playerPos
    }

    local ok, res = net.sendRequest(serverId, "DEPOSIT_ITEMS", payload, 3)
    if ok and res.success then
        local distStr = res.distance and string.format(" (%.1fm)", res.distance) or ""
        statusLabel:setText(string.format(" Deposited x%d from %s%s", res.count or 0, res.chestLabel or "IO", distStr))
        fetchItems()
    else
        statusLabel:setText(" Error: " .. (res and res.message or "Timeout"))
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

-- Unpack & Create System Files
term.setTextColor(colors.cyan)
print("Installing system modules...")
for filename, content in pairs(files) do
    write("Writing " .. filename .. "...")
    if writeFile(filename, content) then
        term.setTextColor(colors.green)
        print(" [OK]")
    else
        term.setTextColor(colors.red)
        print(" [FAILED]")
    end
    term.setTextColor(colors.cyan)
end

-- Download Basalt v2.5 if missing
if not fs.exists("basalt.lua") then
    term.setTextColor(colors.cyan)
    print("Downloading Basalt v2.5 framework...")
    
    local success = pcall(function()
        shell.run("wget", "run", BASALT_INSTALL_URL, "minified")
    end)

    if not fs.exists("basalt.lua") then
        write("Fallback: Fetching raw Basalt bundle...")
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
            print("Could not download Basalt from " .. BASALT_RAW_URL)
            print("Error: " .. tostring(err))
            return
        end
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
print("Installation complete! Type 'ls' to verify files.")
print("Run 'storage_server.lua' on your main computer, or 'pocket_client.lua' on pocket computers.")
