-- AetherVault OS: Dedicated I/O Station & Quick-Order Monitor Terminal
-- Optimized for Advanced Monitors (Touchscreen friendly, compact text, paging, and 1-tap chest adding)
local config = require("config")
local net = require("net_protocol")

local basaltOK, basalt = pcall(require, "basalt")
if not basaltOK then
    term.setTextColor(colors.red)
    print("Error: Basalt v2.5 required!")
    print("Run installer.lua to setup.")
    return
end

-- Open network modems (wireless or wired)
local modemOK, modemSide = net.openModem()
if not modemOK then
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.red)
    print("Error: No modem attached!")
    print("Attach a wired or wireless modem to connect to the AetherVault network.")
    return
end

local updateHeaderLabels = nil

-- Check for physically attached Wireless Modem (required for CC:Tweaked GPS)
local function getWirelessModemSide()
    for _, side in ipairs(rs.getSides()) do
        if peripheral.isPresent(side) and peripheral.getType(side) == "modem" then
            if peripheral.call(side, "isWireless") then
                return side
            end
        end
    end
    return nil
end

-- Safely scan for GPS coordinates with adequate timeout (3s)
local function scanGPS(timeout)
    timeout = timeout or 3
    local wSide = getWirelessModemSide()
    if not wSide then
        return nil, "No wireless modem attached"
    end
    if not rednet.isOpen(wSide) then
        pcall(rednet.open, wSide)
    end
    if gps and gps.locate then
        local gx, gy, gz = gps.locate(timeout)
        if gx and gy and gz then
            return { x = math.floor(gx), y = math.floor(gy), z = math.floor(gz) }, nil
        else
            return nil, "No GPS response received within timeout"
        end
    end
    return nil, "GPS API not available"
end

local STATION_CONFIG_FILE = "/io_station_config.json"
local QUICK_ORDERS_FILE = "/quickorders.json"

-- Load station configuration
local stationConfig = {
    chest = nil,
    label = "I/O Chest",
    x = 0,
    y = 0,
    z = 0,
    monitor = nil,
    textScale = 0.5,
    quickOrders = nil,
    hasCustomOrders = false
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

-- Quick orders
local quickOrders = {}
local DEFAULT_ORDERS = {
    { item = "minecraft:cobblestone", displayName = "Cobblestone", count = 64 },
    { item = "minecraft:torch", displayName = "Torch", count = 16 },
    { item = "minecraft:iron_ingot", displayName = "Iron Ingot", count = 64 },
    { item = "minecraft:oak_planks", displayName = "Oak Planks", count = 32 },
    { item = "minecraft:coal", displayName = "Coal", count = 32 },
    { item = "minecraft:bread", displayName = "Bread", count = 16 }
}

local function saveStationConfig()
    stationConfig.quickOrders = quickOrders
    local file = fs.open(STATION_CONFIG_FILE, "w")
    if file then
        file.write(textutils.serializeJSON(stationConfig))
        file.close()
    end
end

local function saveQuickOrders()
    stationConfig.quickOrders = quickOrders
    saveStationConfig()
    local file = fs.open(QUICK_ORDERS_FILE, "w")
    if file then
        file.write(textutils.serializeJSON(quickOrders))
        file.close()
    end
end

local function loadQuickOrders()
    -- 1. Check if stationConfig has saved quickOrders
    if type(stationConfig.quickOrders) == "table" and (stationConfig.hasCustomOrders or #stationConfig.quickOrders > 0) then
        quickOrders = stationConfig.quickOrders
        return
    end

    -- 2. Check legacy / separate QUICK_ORDERS_FILE
    if fs.exists(QUICK_ORDERS_FILE) then
        local file = fs.open(QUICK_ORDERS_FILE, "r")
        if file then
            local content = file.readAll()
            file.close()
            local data = textutils.unserializeJSON(content)
            if type(data) == "table" and (stationConfig.hasCustomOrders or #data > 0) then
                quickOrders = data
                stationConfig.quickOrders = quickOrders
                saveStationConfig()
                return
            end
        end
    end

    -- 3. Default orders for first-time setup
    quickOrders = {}
    for _, order in ipairs(DEFAULT_ORDERS) do
        table.insert(quickOrders, {
            item = order.item,
            displayName = order.displayName,
            count = order.count
        })
    end
    stationConfig.quickOrders = quickOrders
    saveQuickOrders()
end

loadStationConfig()
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

-- Auto-detect adjacent or network chest
local SIDES_MAP = { top = true, bottom = true, left = true, right = true, front = true, back = true }

-- Clean up any legacy invalid computer side name from config file
if stationConfig.chest and SIDES_MAP[stationConfig.chest] then
    stationConfig.chest = nil
    stationConfig.label = "Not Set"
    saveStationConfig()
end

-- Detect available network inventories (excluding computers/turtles)
local function detectNetworkInventories()
    local candidates = {}
    for _, name in ipairs(peripheral.getNames()) do
        if not SIDES_MAP[name] and peripheral.hasType(name, "inventory") and not name:find("computer") and not name:find("turtle") and not name:find("drive") then
            table.insert(candidates, { name = name, label = name })
        end
    end
    return candidates
end

-- Server state
local serverId = nil
local serverHostname = "..."
local storageItems = {}
local stockMap = {}

local function syncOrdersWithServer()
    if serverId and stationConfig.chest and not SIDES_MAP[stationConfig.chest] then
        basalt.schedule(function()
            net.sendRequest(serverId, "UPDATE_IO_ORDERS", {
                peripheralName = stationConfig.chest,
                quickOrders = quickOrders
            }, 3)
        end)
    end
end

local function connectServer()
    serverId = net.findServer(3)
    if serverId then
        local ok, pingRes = net.sendRequest(serverId, "PING", {}, 3)
        if ok and pingRes and pingRes.success then
            serverHostname = pingRes.hostname or ("Server #" .. serverId)
        else
            serverHostname = "Server #" .. serverId
        end

        local serverChests = {}
        local okChests, resChests = net.sendRequest(serverId, "GET_IO_CHESTS", {}, 3)
        if okChests and resChests and resChests.success and resChests.chests then
            serverChests = resChests.chests
        end

        -- If chest is not set, try to adopt a registered IO chest from the server
        if not stationConfig.chest or not peripheral.isPresent(stationConfig.chest) then
            local validKeys = {}
            for k, info in pairs(serverChests) do
                if not SIDES_MAP[k] then
                    table.insert(validKeys, { name = k, info = info })
                end
            end
            if #validKeys == 1 then
                local chosen = validKeys[1]
                stationConfig.chest = chosen.name
                stationConfig.label = chosen.info.label or chosen.name
                if chosen.info.x and (chosen.info.x ~= 0 or chosen.info.y ~= 0 or chosen.info.z ~= 0) then
                    stationConfig.x = chosen.info.x
                    stationConfig.y = chosen.info.y
                    stationConfig.z = chosen.info.z
                end
                if chosen.info.quickOrders and #chosen.info.quickOrders > 0 and not stationConfig.hasCustomOrders then
                    quickOrders = chosen.info.quickOrders
                    stationConfig.quickOrders = quickOrders
                    stationConfig.hasCustomOrders = true
                    saveQuickOrders()
                end
                saveStationConfig()
            end
        end

        -- If chest is configured and valid, synchronize state with the server
        if stationConfig.chest and not SIDES_MAP[stationConfig.chest] then
            local serverInfo = serverChests[stationConfig.chest]
            if serverInfo then
                -- Check if server has calibrated coords that local station is missing
                local localHasCoords = (stationConfig.x and stationConfig.x ~= 0) or
                                       (stationConfig.y and stationConfig.y ~= 0) or
                                       (stationConfig.z and stationConfig.z ~= 0)
                local serverHasCoords = (serverInfo.x and serverInfo.x ~= 0) or
                                        (serverInfo.y and serverInfo.y ~= 0) or
                                        (serverInfo.z and serverInfo.z ~= 0)

                if not localHasCoords and serverHasCoords then
                    stationConfig.x = serverInfo.x or 0
                    stationConfig.y = serverInfo.y or 0
                    stationConfig.z = serverInfo.z or 0
                    saveStationConfig()
                end

                -- Adopt server label if local is generic
                if (not stationConfig.label or stationConfig.label == "I/O Chest" or stationConfig.label == "Not Set") and serverInfo.label then
                    stationConfig.label = serverInfo.label
                    saveStationConfig()
                end

                -- Adopt quick orders from server if station has not customized them locally yet
                if not stationConfig.hasCustomOrders and serverInfo.quickOrders and #serverInfo.quickOrders > 0 then
                    quickOrders = serverInfo.quickOrders
                    stationConfig.quickOrders = quickOrders
                    stationConfig.hasCustomOrders = true
                    saveQuickOrders()
                end
            end

            -- Determine coords to send to server
            local regX = stationConfig.x or 0
            local regY = stationConfig.y or 0
            local regZ = stationConfig.z or 0

            -- If still 0,0,0, try GPS locate as fallback (checks wireless modem with 3s timeout)
            if regX == 0 and regY == 0 and regZ == 0 then
                local gpsPos = scanGPS(3)
                if gpsPos then
                    regX = gpsPos.x
                    regY = gpsPos.y
                    regZ = gpsPos.z
                    stationConfig.x = regX
                    stationConfig.y = regY
                    stationConfig.z = regZ
                    saveStationConfig()
                    if updateHeaderLabels then updateHeaderLabels() end
                end
            end

            -- If still 0,0,0 and server had coordinates, keep server coords
            if regX == 0 and regY == 0 and regZ == 0 and serverInfo and serverInfo.x then
                regX = serverInfo.x or 0
                regY = serverInfo.y or 0
                regZ = serverInfo.z or 0
                stationConfig.x = regX
                stationConfig.y = regY
                stationConfig.z = regZ
                saveStationConfig()
            end

            -- Register this station's chest with server (never zeroing out coords, syncing buttons!)
            net.sendRequest(serverId, "REGISTER_IO_CHEST", {
                peripheralName = stationConfig.chest,
                label = stationConfig.label or stationConfig.chest,
                x = regX,
                y = regY,
                z = regZ,
                role = "both",
                quickOrders = quickOrders
            }, 3)
        end
        return true
    end
    return false
end

local function refreshStock()
    if not serverId then connectServer() end
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

-- Helper: Format large numbers compactly (e.g. 1280 -> 1.3k)
local function formatCount(n)
    n = n or 0
    if n >= 1000000 then
        return string.format("%.1fM", n / 1000000)
    elseif n >= 1000 then
        return string.format("%.1fk", n / 1000)
    else
        return tostring(n)
    end
end

local function formatDisplayName(rawName)
    local id = rawName:match("[^:]+:(.+)") or rawName
    id = id:gsub("_", " ")
    return id:gsub("(%a)([%w_']*)", function(first, rest)
        return first:upper() .. rest:lower()
    end)
end

-- Create Basalt GUI Frame
local mainFrame = basalt.createFrame(renderTerm, monitorName)
mainFrame:setSize(termW, termH):setBackground(colors.black)

-- =========================================================
-- HEADER (Compact: Title, Chest, and Action Buttons)
-- =========================================================
local headerFrame = mainFrame:addFrame()
    :setPosition(1, 1)
    :setSize(termW, 2)
    :setBackground(colors.gray)

local titleLabel = headerFrame:addLabel()
    :setPosition(1, 1)
    :setForeground(colors.yellow)
titleLabel.text = " I/O STATION"

local chestLabel = headerFrame:addLabel()
    :setPosition(1, 2)
    :setForeground(colors.cyan)

updateHeaderLabels = function()
    local shortChest = stationConfig.label or stationConfig.chest or "None"
    local coordsStr = ""
    if stationConfig.x and (stationConfig.x ~= 0 or stationConfig.y ~= 0 or stationConfig.z ~= 0) then
        coordsStr = string.format(" [%d,%d,%d]", stationConfig.x, stationConfig.y, stationConfig.z)
    end
    local maxLen = math.max(10, termW - 2)
    local fullStr = shortChest .. coordsStr
    if #fullStr > maxLen then
        if #shortChest > (maxLen - 3) then shortChest = shortChest:sub(1, math.max(1, maxLen - 5)) .. ".." end
        fullStr = shortChest
    end
    chestLabel.text = " Chest: " .. fullStr
end
updateHeaderLabels()

-- Action buttons on top right
local btnFromChest = headerFrame:addButton()
    :setPosition(math.max(13, termW - 25), 1)
    :setSize(9, 1)
    :setText("+Chest")
    :setBackground(colors.green)
    :setForeground(colors.white)

local btnBrowse = headerFrame:addButton()
    :setPosition(math.max(13, termW - 15), 1)
    :setSize(8, 1)
    :setText("+Browse")
    :setBackground(colors.purple)
    :setForeground(colors.white)

local delMode = false
local btnDel = headerFrame:addButton()
    :setPosition(math.max(13, termW - 6), 1)
    :setSize(6, 1)
    :setText("Del")
    :setBackground(colors.gray)
    :setForeground(colors.white)

-- =========================================================
-- PROMINENT DEPOSIT BUTTON (Compact, bold)
-- =========================================================
local depositBtn = mainFrame:addButton()
    :setPosition(1, 3)
    :setSize(termW, 1)
    :setText("v  DEPOSIT ALL  v")
    :setBackground(colors.green)
    :setForeground(colors.white)

-- =========================================================
-- BOTTOM BAR (Page navigation + Status)
-- =========================================================
local navBar = mainFrame:addFrame()
    :setPosition(1, math.max(4, termH - 1))
    :setSize(termW, 1)
    :setBackground(colors.gray)

local btnPrevPage = navBar:addButton()
    :setPosition(1, 1)
    :setSize(7, 1)
    :setText("< Prev")
    :setBackground(colors.cyan)
    :setForeground(colors.black)

local pageLabel = navBar:addLabel()
    :setPosition(9, 1)
    :setForeground(colors.yellow)
pageLabel.text = "Page 1/1"

local btnNextPage = navBar:addButton()
    :setPosition(math.max(15, termW - 7), 1)
    :setSize(7, 1)
    :setText("Next >")
    :setBackground(colors.cyan)
    :setForeground(colors.black)

local statusBar = mainFrame:addFrame()
    :setPosition(1, termH)
    :setSize(termW, 1)
    :setBackground(colors.black)

local statusLabel = statusBar:addLabel()
    :setPosition(1, 1)
    :setForeground(colors.lightGray)
statusLabel.text = " Ready | Tap buttons to order"

-- =========================================================
-- QUICK-ORDER BUTTONS GRID (Paged, Touchscreen-friendly)
-- =========================================================
local gridTop = 4
local gridH = math.max(1, termH - 5)
local gridContainer = mainFrame:addFrame()
    :setPosition(1, gridTop)
    :setSize(termW, gridH)
    :setBackground(colors.black)

local currentPage = 1
local renderQuickOrderGrid -- forward declare

-- =========================================================
-- TOUCH ACTION: DEPOSIT
-- =========================================================
-- =========================================================
-- TOUCH ACTION: DEPOSIT
-- =========================================================
depositBtn:onClick(function()
    if not stationConfig.chest then
        statusLabel.text = " Error: No chest set! Press [C] on computer."
        return
    end
    depositBtn:setText("Depositing..."):setBackground(colors.yellow)
    statusLabel.text = " Depositing items into storage..."
    basalt.schedule(function()
        if not serverId then connectServer() end
        if not serverId then
            depositBtn:setText("v  DEPOSIT ALL  v"):setBackground(colors.green)
            statusLabel.text = " Error: Server not connected!"
            return
        end

        local payload = { sourceChest = stationConfig.chest }
        local ok, res = net.sendRequest(serverId, "DEPOSIT_ITEMS", payload, 8)
        depositBtn:setText("v  DEPOSIT ALL  v"):setBackground(colors.green)
        if ok and res and res.success then
            local count = res.count or 0
            if count > 0 then
                statusLabel.text = string.format(" Deposited x%d items!", count)
            else
                statusLabel.text = " Chest was empty."
            end
            refreshStock()
            renderQuickOrderGrid()
        else
            local err = (type(res) == "table" and res.message) or "Timeout"
            statusLabel.text = " Deposit: " .. tostring(err)
        end
    end)
end)

-- =========================================================
-- TOUCH ACTION: ADD QUICK-ORDERS DIRECTLY FROM CHEST
-- (The ultimate Minecraft touch convenience!)
-- =========================================================
local function addFromChest()
    local targetChest = stationConfig.chest
    if not targetChest or not peripheral.isPresent(targetChest) then
        -- Also check adjacent computer sides so players can quickly drop items to create buttons!
        for _, s in ipairs({ "top", "bottom", "left", "right", "front", "back" }) do
            if peripheral.isPresent(s) and peripheral.hasType(s, "inventory") then
                targetChest = s
                break
            end
        end
    end

    if not targetChest then
        statusLabel.text = " Put items in chest & tap [+Chest]!"
        return
    end

    local p = peripheral.wrap(targetChest)
    if not p or not p.list then
        statusLabel.text = " Error: Cannot read chest!"
        return
    end

    local ok, list = pcall(p.list)
    if not ok or not list then
        statusLabel.text = " Error: Failed reading chest inventory"
        return
    end

    local addedCount = 0
    local updatedCount = 0
    for slot, item in pairs(list) do
        if item and item.name and item.count and item.count > 0 then
            local exists = false
            for _, q in ipairs(quickOrders) do
                if q.item == item.name then
                    exists = true
                    if q.count ~= item.count then
                        q.count = item.count
                        updatedCount = updatedCount + 1
                    end
                    break
                end
            end
            if not exists then
                local dName = item.displayName or formatDisplayName(item.name)
                table.insert(quickOrders, {
                    item = item.name,
                    displayName = dName,
                    count = item.count
                })
                addedCount = addedCount + 1
            end
        end
    end

    if addedCount > 0 or updatedCount > 0 then
        stationConfig.hasCustomOrders = true
        saveQuickOrders()
        syncOrdersWithServer()
        renderQuickOrderGrid()
        if addedCount > 0 and updatedCount > 0 then
            statusLabel.text = string.format(" Added %d, updated %d buttons!", addedCount, updatedCount)
        elseif addedCount > 0 then
            statusLabel.text = string.format(" Added %d quick-orders from chest!", addedCount)
        else
            statusLabel.text = string.format(" Updated %d button counts!", updatedCount)
        end
    else
        statusLabel.text = " Put items in chest to add them!"
    end
end

btnFromChest:onClick(addFromChest)

-- Delete mode toggle
btnDel:onClick(function()
    delMode = not delMode
    if delMode then
        btnDel:setText("Del:ON"):setBackground(colors.red)
        statusLabel.text = " DEL MODE: Tap any button to remove."
    else
        btnDel:setText("Del"):setBackground(colors.gray)
        statusLabel.text = " Ready | Tap buttons to order"
    end
    renderQuickOrderGrid()
end)

-- Page navigation
btnPrevPage:onClick(function()
    if currentPage > 1 then
        currentPage = currentPage - 1
        renderQuickOrderGrid()
    end
end)

btnNextPage:onClick(function()
    local cols = (termW >= 50) and 3 or ((termW >= 24) and 2 or 1)
    local pageSize = math.max(1, gridH * cols)
    local totalPages = math.max(1, math.ceil(#quickOrders / pageSize))
    if currentPage < totalPages then
        currentPage = currentPage + 1
        renderQuickOrderGrid()
    end
end)

-- =========================================================
-- RENDER QUICK-ORDER GRID (Paginated)
-- =========================================================
renderQuickOrderGrid = function()
    local children = gridContainer:getChildren()
    while #children > 0 do
        gridContainer:removeChild(children[#children])
    end

    local cols = 1
    if termW >= 50 then
        cols = 3
    elseif termW >= 24 then
        cols = 2
    end

    local colW = math.floor((termW - (cols + 1)) / cols)
    local pageSize = math.max(1, gridH * cols)
    local totalPages = math.max(1, math.ceil(#quickOrders / pageSize))
    if currentPage > totalPages then currentPage = totalPages end
    if currentPage < 1 then currentPage = 1 end

    pageLabel.text = string.format("P %d/%d (%d)", currentPage, totalPages, #quickOrders)

    if #quickOrders == 0 then
        local emptyMsg = gridContainer:addLabel()
            :setPosition(2, 1)
            :setForeground(colors.lightGray)
        emptyMsg.text = "Put items in chest & tap [+Chest]!"
        return
    end

    local startIdx = (currentPage - 1) * pageSize + 1
    local endIdx = math.min(#quickOrders, startIdx + pageSize - 1)

    for idx = startIdx, endIdx do
        local order = quickOrders[idx]
        local slotInPage = idx - startIdx
        local colIdx = slotInPage % cols
        local rowIdx = math.floor(slotInPage / cols)

        local posX = 1 + colIdx * (colW + 1)
        local posY = 1 + rowIdx

        local avail = stockMap[order.item] or 0
        local dispName = order.displayName or order.item:match("[^:]+:(.+)") or order.item
        local countStr = formatCount(avail)

        -- Compact text: +64 Cobble [1.2k]
        local maxNameLen = math.max(4, colW - #tostring(order.count) - #countStr - 6)
        if #dispName > maxNameLen then
            dispName = dispName:sub(1, maxNameLen - 1) .. "."
        end

        local btnText = string.format("+%d %s [%s]", order.count, dispName, countStr)
        local btnBg = (avail >= order.count) and colors.blue or (avail > 0 and colors.orange or colors.gray)
        if delMode then btnBg = colors.red end

        local qBtn = gridContainer:addButton()
            :setPosition(posX, posY)
            :setSize(colW, 1)
            :setText(btnText)
            :setBackground(btnBg)
            :setForeground(colors.white)

        qBtn:onClick(function()
            if delMode then
                table.remove(quickOrders, idx)
                stationConfig.hasCustomOrders = true
                saveQuickOrders()
                syncOrdersWithServer()
                statusLabel.text = " Removed: " .. dispName
                renderQuickOrderGrid()
                return
            end

            if not stationConfig.chest then
                statusLabel.text = " Error: No chest set! Press [C] on computer."
                return
            end

            qBtn:setText("Ordering..."):setBackground(colors.yellow)
            statusLabel.text = string.format(" Ordering %dx %s...", order.count, dispName)
            basalt.schedule(function()
                if not serverId then connectServer() end
                if not serverId then
                    qBtn:setText(btnText):setBackground(btnBg)
                    statusLabel.text = " Error: Server not connected!"
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
                        statusLabel.text = string.format(" Delivered x%d %s!", moved, dispName)
                    else
                        statusLabel.text = string.format(" Out of stock: %s", dispName)
                    end
                    refreshStock()
                    renderQuickOrderGrid()
                else
                    local errMsg = (type(res) == "table" and res.message) or "Timeout"
                    statusLabel.text = " Order failed: " .. tostring(errMsg)
                    qBtn:setText(btnText):setBackground(btnBg)
                end
            end)
        end)
    end
end

-- =========================================================
-- TOUCH-FRIENDLY BROWSE MODAL (Paged storage picker + Touch Qty)
-- =========================================================
local modalW = math.min(termW, 36)
local modalH = math.min(termH, 12)
local modalX = math.max(1, math.floor((termW - modalW) / 2) + 1)
local modalY = math.max(1, math.floor((termH - modalH) / 2) + 1)

local browseModal = mainFrame:addFrame()
    :setPosition(modalX, modalY)
    :setSize(modalW, modalH)
    :setBackground(colors.gray)
    :setZ(100)

local function setBrowseVisible(visible)
    if browseModal.setVisible then
        pcall(browseModal.setVisible, browseModal, visible)
    end
    browseModal.visible = visible
end
setBrowseVisible(false)

local modalTitle = browseModal:addLabel()
    :setPosition(2, 1)
    :setForeground(colors.yellow)
modalTitle.text = "BROWSE STORAGE ITEMS"

local chosenQty = 64
local qtyLabel = browseModal:addLabel():setPosition(2, 2):setForeground(colors.white)
qtyLabel.text = "Qty: 64"

local btnQ16 = browseModal:addButton():setPosition(modalW - 17, 2):setSize(4, 1):setText("16"):setBackground(colors.blue)
local btnQ32 = browseModal:addButton():setPosition(modalW - 12, 2):setSize(4, 1):setText("32"):setBackground(colors.blue)
local btnQ64 = browseModal:addButton():setPosition(modalW - 7, 2):setSize(4, 1):setText("64"):setBackground(colors.green)

local function updateQtyBtns()
    btnQ16:setBackground(chosenQty == 16 and colors.green or colors.blue)
    btnQ32:setBackground(chosenQty == 32 and colors.green or colors.blue)
    btnQ64:setBackground(chosenQty == 64 and colors.green or colors.blue)
    qtyLabel.text = "Qty: " .. tostring(chosenQty)
end

btnQ16:onClick(function() chosenQty = 16; updateQtyBtns() end)
btnQ32:onClick(function() chosenQty = 32; updateQtyBtns() end)
btnQ64:onClick(function() chosenQty = 64; updateQtyBtns() end)

local browsePage = 1
local browseItemsPerPage = math.max(1, modalH - 5)
local browseContainer = browseModal:addFrame()
    :setPosition(2, 3)
    :setSize(modalW - 2, browseItemsPerPage)
    :setBackground(colors.black)

local btnBrowsePrev = browseModal:addButton():setPosition(2, modalH - 1):setSize(6, 1):setText("< Prev"):setBackground(colors.cyan):setForeground(colors.black)
local browsePageLabel = browseModal:addLabel():setPosition(9, modalH - 1):setForeground(colors.yellow)
local btnBrowseNext = browseModal:addButton():setPosition(modalW - 15, modalH - 1):setSize(6, 1):setText("Next >"):setBackground(colors.cyan):setForeground(colors.black)
local btnBrowseClose = browseModal:addButton():setPosition(modalW - 8, modalH - 1):setSize(7, 1):setText("Close"):setBackground(colors.red):setForeground(colors.white)

btnBrowseClose:onClick(function() setBrowseVisible(false) end)

local function renderBrowseList()
    local children = browseContainer:getChildren()
    while #children > 0 do browseContainer:removeChild(children[#children]) end

    local totalPages = math.max(1, math.ceil(#storageItems / browseItemsPerPage))
    if browsePage > totalPages then browsePage = totalPages end
    if browsePage < 1 then browsePage = 1 end

    browsePageLabel.text = string.format("P %d/%d", browsePage, totalPages)

    local startIdx = (browsePage - 1) * browseItemsPerPage + 1
    local endIdx = math.min(#storageItems, startIdx + browseItemsPerPage - 1)

    for i = startIdx, endIdx do
        local it = storageItems[i]
        local rowY = (i - startIdx) + 1
        local dName = it.displayName or formatDisplayName(it.name)
        local countText = formatCount(it.total)
        local maxL = math.max(4, modalW - #countText - 8)
        if #dName > maxL then dName = dName:sub(1, maxL - 1) .. "." end

        local rowBtn = browseContainer:addButton()
            :setPosition(1, rowY)
            :setSize(modalW - 2, 1)
            :setText(string.format(" + %s [%s]", dName, countText))
            :setBackground(colors.blue)
            :setForeground(colors.white)

        rowBtn:onClick(function()
            table.insert(quickOrders, {
                item = it.name,
                displayName = it.displayName,
                count = chosenQty
            })
            stationConfig.hasCustomOrders = true
            saveQuickOrders()
            syncOrdersWithServer()
            setBrowseVisible(false)
            renderQuickOrderGrid()
            statusLabel.text = string.format(" Added: +%d %s", chosenQty, dName)
        end)
    end
end

btnBrowsePrev:onClick(function()
    if browsePage > 1 then
        browsePage = browsePage - 1
        renderBrowseList()
    end
end)

btnBrowseNext:onClick(function()
    local totalPages = math.max(1, math.ceil(#storageItems / browseItemsPerPage))
    if browsePage < totalPages then
        browsePage = browsePage + 1
        renderBrowseList()
    end
end)

btnBrowse:onClick(function()
    setBrowseVisible(true)
    basalt.schedule(function()
        refreshStock()
        renderBrowseList()
    end)
end)

-- =========================================================
-- PHYSICAL COMPUTER TERMINAL CONSOLE
-- (Allows full keyboard typing, chest selection, and management!)
-- =========================================================
local function drawConsoleHeader()
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.yellow)
    print("==============================================")
    print("     AETHERVAULT OS | I/O TERMINAL CONSOLE    ")
    print("==============================================")
    term.setTextColor(colors.white)
    print("Monitor:      " .. (monitorName or "Attached"))
    local chestName = stationConfig.chest or "None"
    local chestLabelStr = stationConfig.label and (" (" .. stationConfig.label .. ")") or ""
    print("Target Chest: " .. chestName .. chestLabelStr)
    local hasCoords = (stationConfig.x and stationConfig.x ~= 0) or
                      (stationConfig.y and stationConfig.y ~= 0) or
                      (stationConfig.z and stationConfig.z ~= 0)
    local coordsStr = string.format("X=%d, Y=%d, Z=%d", stationConfig.x or 0, stationConfig.y or 0, stationConfig.z or 0)
    if hasCoords then
        print("Coordinates:  " .. coordsStr .. " (Calibrated)")
    else
        print("Coordinates:  " .. coordsStr .. " (Uncalibrated)")
    end
    local wSide = getWirelessModemSide()
    if wSide then
        term.setTextColor(colors.green)
        print("GPS Hardware: Wireless Modem on '" .. wSide .. "'")
    else
        term.setTextColor(colors.yellow)
        print("GPS Hardware: None (Attach Wireless Modem for GPS)")
    end
    term.setTextColor(colors.white)
    print("Quick-Orders: " .. #quickOrders .. " buttons configured")
    print("Server:       " .. tostring(serverHostname))
    print()
    term.setTextColor(colors.cyan)
    print("Commands:")
    print(" [A] Add Item by Name (Type with Keyboard)")
    print(" [D] Deposit Chest Now")
    print(" [C] Select/Change Target Chest")
    print(" [X] Set / Calibrate Coordinates (GPS/Manual)")
    print(" [R] Refresh Stock & Server")
    term.setTextColor(colors.gray)
    print("==============================================")
end

if monitor then
    drawConsoleHeader()
end

-- Background listener for Computer Keyboard Input
basalt.schedule(function()
    while true do
        local event, key = os.pullEvent("key")
        if event == "key" and monitor then
            if key == keys.a then
                -- Add item by typing search
                term.clear()
                term.setCursorPos(1, 1)
                term.setTextColor(colors.yellow)
                print("--- ADD QUICK-ORDER BY SEARCH ---")
                term.setTextColor(colors.white)
                write("Search Item: ")
                local query = (read() or ""):lower()
                if query ~= "" then
                    refreshStock()
                    local matches = {}
                    for _, it in ipairs(storageItems) do
                        if it.name:lower():find(query, 1, true) or (it.displayName and it.displayName:lower():find(query, 1, true)) then
                            table.insert(matches, it)
                            if #matches >= 9 then break end
                        end
                    end
                    if #matches > 0 then
                        print("\nMatching items:")
                        for idx, m in ipairs(matches) do
                            print(string.format(" %d) %s (%d in storage)", idx, m.displayName, m.total or 0))
                        end
                        write("\nSelect (1-" .. #matches .. "): ")
                        local selIdx = tonumber(read())
                        if selIdx and matches[selIdx] then
                            local chosenItem = matches[selIdx]
                            write("Order Quantity (e.g. 64, 32, 16): ")
                            local qty = tonumber(read()) or 64
                            table.insert(quickOrders, {
                                item = chosenItem.name,
                                displayName = chosenItem.displayName,
                                count = qty
                            })
                            stationConfig.hasCustomOrders = true
                            saveQuickOrders()
                            syncOrdersWithServer()
                            renderQuickOrderGrid()
                            term.setTextColor(colors.green)
                            print("\nAdded '+ " .. qty .. " " .. chosenItem.displayName .. "' to monitor!")
                            sleep(1.5)
                        end
                    else
                        term.setTextColor(colors.red)
                        print("No items matched '" .. query .. "'.")
                        sleep(1.5)
                    end
                end
                drawConsoleHeader()

            elseif key == keys.d then
                term.setTextColor(colors.yellow)
                print("Depositing chest...")
                if serverId then
                    net.sendRequest(serverId, "DEPOSIT_ITEMS", { sourceChest = stationConfig.chest }, 8)
                    refreshStock()
                    renderQuickOrderGrid()
                    term.setTextColor(colors.green)
                    print("Deposit complete!")
                    sleep(1)
                end
                drawConsoleHeader()

            elseif key == keys.x then
                term.clear()
                term.setCursorPos(1, 1)
                term.setTextColor(colors.yellow)
                print("==============================================")
                print("       SET / CALIBRATE I/O COORDINATES        ")
                print("==============================================")
                term.setTextColor(colors.white)
                print("Current Coords: X=" .. (stationConfig.x or 0) .. ", Y=" .. (stationConfig.y or 0) .. ", Z=" .. (stationConfig.z or 0))
                print()

                local finalX, finalY, finalZ
                local wSide = getWirelessModemSide()
                if not wSide then
                    term.setTextColor(colors.yellow)
                    print("[!] No Wireless Modem attached to this computer.")
                    print("    CC:Tweaked GPS requires an attached Wireless or Ender Modem.")
                    print("    (Wired modems cannot receive wireless GPS satellite pings).")
                    print("    Tip: Attach a Wireless Modem to any open face for auto-GPS.\n")
                else
                    term.setTextColor(colors.cyan)
                    write("Scanning for GPS signal via '" .. wSide .. "' (3s)... ")
                    local gpsPos, err = scanGPS(3)
                    print()
                    if gpsPos then
                        term.setTextColor(colors.green)
                        print(string.format("GPS position detected: X=%d, Y=%d, Z=%d", gpsPos.x, gpsPos.y, gpsPos.z))
                        term.setTextColor(colors.white)
                        write("Use detected GPS coords? (Y/n): ")
                        local useGps = (read() or ""):lower()
                        if useGps == "" or useGps == "y" then
                            finalX, finalY, finalZ = gpsPos.x, gpsPos.y, gpsPos.z
                        end
                    else
                        term.setTextColor(colors.orange)
                        print("No GPS signal received within 3 seconds.")
                        print("Ensure at least 4 GPS satellites/hosts are running within range.\n")
                    end
                end

                if not finalX then
                    term.setTextColor(colors.white)
                    write(string.format("Enter X coordinate [%d]: ", stationConfig.x or 0))
                    local inX = read()
                    finalX = (inX ~= "" and tonumber(inX)) or stationConfig.x or 0

                    write(string.format("Enter Y coordinate [%d]: ", stationConfig.y or 0))
                    local inY = read()
                    finalY = (inY ~= "" and tonumber(inY)) or stationConfig.y or 0

                    write(string.format("Enter Z coordinate [%d]: ", stationConfig.z or 0))
                    local inZ = read()
                    finalZ = (inZ ~= "" and tonumber(inZ)) or stationConfig.z or 0
                end

                stationConfig.x = finalX
                stationConfig.y = finalY
                stationConfig.z = finalZ
                saveStationConfig()

                if serverId and stationConfig.chest and not SIDES_MAP[stationConfig.chest] then
                    net.sendRequest(serverId, "REGISTER_IO_CHEST", {
                        peripheralName = stationConfig.chest,
                        label = stationConfig.label or stationConfig.chest,
                        x = finalX,
                        y = finalY,
                        z = finalZ,
                        role = "both",
                        quickOrders = quickOrders
                    }, 3)
                end

                updateHeaderLabels()
                term.setTextColor(colors.green)
                print(string.format("\nCoordinates saved: [%d, %d, %d]!", finalX, finalY, finalZ))
                sleep(1.5)
                drawConsoleHeader()

            elseif key == keys.c then
                term.clear()
                term.setCursorPos(1, 1)
                term.setTextColor(colors.yellow)
                print("==============================================")
                print("          SELECT / CONFIGURE I/O CHEST        ")
                print("==============================================")
                term.setTextColor(colors.white)
                print("An IO chest must have a Wired Modem connected")
                print("to the AetherVault network cable.\n")

                if not serverId then connectServer() end

                local serverChests = {}
                if serverId then
                    local ok, res = net.sendRequest(serverId, "GET_IO_CHESTS", {}, 3)
                    if ok and res and res.success and res.chests then
                        serverChests = res.chests
                    end
                end

                local options = {}
                term.setTextColor(colors.cyan)
                print("Registered I/O Chests on Server:")
                local count = 0
                for pName, info in pairs(serverChests) do
                    if not SIDES_MAP[pName] then
                        count = count + 1
                        table.insert(options, { name = pName, label = info.label or pName, info = info })
                        local coordStr = string.format("[%d,%d,%d]", info.x or 0, info.y or 0, info.z or 0)
                        print(string.format(" %d) %s (%s) %s", count, pName, info.label or pName, coordStr))
                    end
                end
                if count == 0 then
                    print(" (None registered yet on server)")
                end

                print("\nOptions:")
                print(" - Type a menu # (1-" .. math.max(1, #options) .. ")")
                print(" - Or enter new chest peripheral name (e.g. 561 or minecraft:chest_561)")
                write("\nChest selection: ")
                local inputStr = read()
                if inputStr and inputStr ~= "" then
                    local selectedName = nil
                    local selectedLabel = nil
                    local selectedInfo = nil
                    local num = tonumber(inputStr)
                    if num and options[num] then
                        selectedName = options[num].name
                        selectedLabel = options[num].label
                        selectedInfo = options[num].info
                    else
                        if peripheral.isPresent(inputStr) and peripheral.hasType(inputStr, "inventory") then
                            selectedName = inputStr
                        elseif peripheral.isPresent("minecraft:chest_" .. inputStr) then
                            selectedName = "minecraft:chest_" .. inputStr
                        elseif peripheral.isPresent("minecraft:barrel_" .. inputStr) then
                            selectedName = "minecraft:barrel_" .. inputStr
                        else
                            selectedName = inputStr
                        end
                        write("Enter friendly label (e.g. Station Chest): ")
                        selectedLabel = read()
                        if not selectedLabel or selectedLabel == "" then selectedLabel = selectedName end
                    end

                    if selectedName then
                        if SIDES_MAP[selectedName] then
                            term.setTextColor(colors.red)
                            print("\nCannot use computer side '" .. selectedName .. "'!")
                            print("The chest MUST have a Wired Modem attached to connect to the network.")
                            sleep(2.5)
                        else
                            stationConfig.chest = selectedName
                            stationConfig.label = selectedLabel or selectedName

                            if selectedInfo then
                                if selectedInfo.x and (selectedInfo.x ~= 0 or selectedInfo.y ~= 0 or selectedInfo.z ~= 0) then
                                    stationConfig.x = selectedInfo.x
                                    stationConfig.y = selectedInfo.y
                                    stationConfig.z = selectedInfo.z
                                end
                                if selectedInfo.quickOrders and #selectedInfo.quickOrders > 0 and not stationConfig.hasCustomOrders then
                                    quickOrders = selectedInfo.quickOrders
                                    stationConfig.quickOrders = quickOrders
                                    stationConfig.hasCustomOrders = true
                                    saveQuickOrders()
                                end
                            end

                            print()
                            write(string.format("Configure coordinates now? Current: [%d,%d,%d] (y/N): ", stationConfig.x or 0, stationConfig.y or 0, stationConfig.z or 0))
                            local setCoords = (read() or ""):lower()
                            if setCoords == "y" then
                                local wSide = getWirelessModemSide()
                                local gx, gy, gz = nil, nil, nil
                                if wSide then
                                    write("Scanning for GPS signal via '" .. wSide .. "'... ")
                                    local gpsPos = scanGPS(3)
                                    if gpsPos then
                                        gx, gy, gz = gpsPos.x, gpsPos.y, gpsPos.z
                                        print("OK!")
                                        write(string.format("Use detected GPS coords [%d,%d,%d]? (Y/n): ", gx, gy, gz))
                                        local uGps = (read() or ""):lower()
                                        if uGps == "" or uGps == "y" then
                                            stationConfig.x = gx
                                            stationConfig.y = gy
                                            stationConfig.z = gz
                                        end
                                    else
                                        print("Failed (no signal).")
                                    end
                                else
                                    term.setTextColor(colors.yellow)
                                    print("Note: No Wireless Modem attached. (GPS requires Wireless Modem).")
                                    term.setTextColor(colors.white)
                                end
                                if not gx or (stationConfig.x ~= gx) then
                                    write(string.format("Enter X [%d]: ", stationConfig.x or 0))
                                    local inX = read()
                                    if inX ~= "" and tonumber(inX) then stationConfig.x = tonumber(inX) end
                                    write(string.format("Enter Y [%d]: ", stationConfig.y or 0))
                                    local inY = read()
                                    if inY ~= "" and tonumber(inY) then stationConfig.y = tonumber(inY) end
                                    write(string.format("Enter Z [%d]: ", stationConfig.z or 0))
                                    local inZ = read()
                                    if inZ ~= "" and tonumber(inZ) then stationConfig.z = tonumber(inZ) end
                                end
                            end

                            saveStationConfig()
                            connectServer()
                            updateHeaderLabels()
                            renderQuickOrderGrid()
                            term.setTextColor(colors.green)
                            print("\nSaved target chest: " .. stationConfig.chest)
                            sleep(1.5)
                        end
                    end
                end
                drawConsoleHeader()

            elseif key == keys.r then
                connectServer()
                refreshStock()
                updateHeaderLabels()
                renderQuickOrderGrid()
                drawConsoleHeader()
            end
        end
    end
end)

-- Initial Data Load
basalt.schedule(function()
    connectServer()
    refreshStock()
    updateHeaderLabels()
    renderQuickOrderGrid()
    if monitor then
        drawConsoleHeader()
    end
end)

if basalt.run then
    basalt.run()
else
    basalt.autoUpdate()
end
