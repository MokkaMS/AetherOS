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

embeddedFiles["config.lua"] = [=[-- Configuration management for AetherVault OS
local config = {}

local CONFIG_FILE = "storage_config.json"

config.data = {
    protocol = "AETHER_VAULT_NET",
    hostname = "aether_vault_server",
    scanInterval = 5,
    autoDeposit = true,
    ioChests = {},
    ignoredPeripherals = {},
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

embeddedFiles["db.lua"] = [=[-- Database Engine for AetherVault OS
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

embeddedFiles["net_protocol.lua"] = [=[-- Network Communication Protocol for AetherVault OS
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

embeddedFiles["io_config_tool.lua"] = [=[-- Interactive IO Chest Configuration & GPS Calibration Tool
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

filesToDownload = {
    "config.lua",
    "db.lua",
    "net_protocol.lua",
    "storage_server.lua",
    "pocket_client.lua",
    "io_config_tool.lua"
}

term.setTextColor(colors.cyan)
print("Fetching AetherVault OS files...")

for _, filename in ipairs(filesToDownload) do
    write("Downloading " .. filename .. "...")
    local url = GITHUB_REPO_RAW .. filename
    local resp, err = http.get(url)
    
    if resp then
        local code = resp.readAll()
        resp.close()
        writeFile(filename, code)
        term.setTextColor(colors.green)
        print(" [OK]")
    else
        -- Fallback to embedded code if GitHub file not found
        term.setTextColor(colors.yellow)
        write(" [Unpack Fallback]...")
        if embeddedFiles[filename] and writeFile(filename, embeddedFiles[filename]) then
            term.setTextColor(colors.green)
            print(" [OK]")
        else
            term.setTextColor(colors.red)
            print(" [FAILED]")
        end
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
