-- Interactive IO Chest Configuration & GPS Calibration Tool
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
