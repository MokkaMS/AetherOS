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

local function registerIOChest(pName, label, x, y, z, role, quickOrders)
    if isRemote then
        local payload = {
            peripheralName = pName,
            label = label,
            x = x,
            y = y,
            z = z,
            role = role,
            quickOrders = quickOrders
        }
        local ok, res = net.sendRequest(serverId, "REGISTER_IO_CHEST", payload, 4)
        if ok and res.success then
            return true, res.message or "Registered remotely on server!"
        else
            local errDetail = (type(res) == "table" and res.message) or (type(res) == "string" and res) or "RPC call failed"
            return false, errDetail
        end
    else
        config.setIOChest(pName, label, x, y, z, role, quickOrders)
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

                    local remoteChests = getRemoteIOChests()
                    local existingInfo = remoteChests and remoteChests[pName]
                    if not finalX then
                        local defX = existingInfo and existingInfo.x or 0
                        local defY = existingInfo and existingInfo.y or 0
                        local defZ = existingInfo and existingInfo.z or 0
                        write(string.format("Enter X coordinate [%d]: ", defX))
                        local inX = read()
                        finalX = (inX ~= "" and tonumber(inX)) or defX
                        write(string.format("Enter Y coordinate [%d]: ", defY))
                        local inY = read()
                        finalY = (inY ~= "" and tonumber(inY)) or defY
                        write(string.format("Enter Z coordinate [%d]: ", defZ))
                        local inZ = read()
                        finalZ = (inZ ~= "" and tonumber(inZ)) or defZ
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
                        local ok, msg = registerIOChest(pName, label, finalX, finalY, finalZ, role, existingInfo and existingInfo.quickOrders)
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
