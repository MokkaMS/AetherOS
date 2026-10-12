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

local STATION_CONFIG_FILE = "/io_station_config.json"
local QUICK_ORDERS_FILE = "/quickorders.json"

-- Load station configuration
local stationConfig = {
    chest = nil,
    label = "I/O Chest",
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

-- Auto-detect adjacent or network chest
local function detectChests()
    local candidates = {}
    local sides = { "top", "bottom", "left", "right", "front", "back" }
    for _, s in ipairs(sides) do
        if peripheral.isPresent(s) and peripheral.hasType(s, "inventory") then
            table.insert(candidates, { name = s, label = s })
        end
    end
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.hasType(name, "inventory") and not name:find("computer") and not name:find("turtle") then
            local exists = false
            for _, c in ipairs(candidates) do
                if c.name == name then exists = true break end
            end
            if not exists then
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
local serverHostname = "..."
local storageItems = {}
local stockMap = {}

local function connectServer()
    serverId = net.findServer(3)
    if serverId then
        local ok, pingRes = net.sendRequest(serverId, "PING", {}, 3)
        if ok and pingRes and pingRes.success then
            serverHostname = pingRes.hostname or ("Server #" .. serverId)
        else
            serverHostname = "Server #" .. serverId
        end

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

local function updateHeaderLabels()
    local shortChest = stationConfig.label or stationConfig.chest or "None"
    if #shortChest > 14 then shortChest = shortChest:sub(1, 12) .. ".." end
    chestLabel.text = " Chest: " .. shortChest
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
depositBtn:onClick(function()
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
            statusLabel.text = " Deposit error: " .. tostring(err)
        end
    end)
end)

-- =========================================================
-- TOUCH ACTION: ADD QUICK-ORDERS DIRECTLY FROM CHEST
-- (The ultimate Minecraft touch convenience!)
-- =========================================================
local function addFromChest()
    if not stationConfig.chest or not peripheral.isPresent(stationConfig.chest) then
        statusLabel.text = " Error: Target chest not found!"
        return
    end

    local p = peripheral.wrap(stationConfig.chest)
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
    for slot, item in pairs(list) do
        if item and item.name and item.count and item.count > 0 then
            local exists = false
            for _, q in ipairs(quickOrders) do
                if q.item == item.name then
                    exists = true
                    q.count = item.count
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

    if addedCount > 0 then
        saveQuickOrders()
        renderQuickOrderGrid()
        statusLabel.text = string.format(" Added %d quick-orders from chest!", addedCount)
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
                saveQuickOrders()
                statusLabel.text = " Removed: " .. dispName
                renderQuickOrderGrid()
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
            saveQuickOrders()
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
    print("Target Chest: " .. tostring(stationConfig.chest or "None"))
    print("Quick-Orders: " .. #quickOrders .. " buttons configured")
    print("Server:       " .. tostring(serverHostname))
    print()
    term.setTextColor(colors.cyan)
    print("Commands:")
    print(" [A] Add Item by Name (Type with Keyboard)")
    print(" [D] Deposit Chest Now")
    print(" [C] Select/Change Target Chest")
    print(" [R] Refresh Stock")
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
                            saveQuickOrders()
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

            elseif key == keys.c then
                term.clear()
                term.setCursorPos(1, 1)
                term.setTextColor(colors.yellow)
                print("--- SELECT TARGET I/O CHEST ---")
                local cList = detectChests()
                if #cList > 0 then
                    for idx, c in ipairs(cList) do
                        print(string.format(" %d) %s (%s)", idx, c.name, c.label))
                    end
                    write("\nSelect (1-" .. #cList .. "): ")
                    local choice = tonumber(read())
                    if choice and cList[choice] then
                        stationConfig.chest = cList[choice].name
                        stationConfig.label = cList[choice].label
                        saveStationConfig()
                        updateHeaderLabels()
                        term.setTextColor(colors.green)
                        print("Saved target chest: " .. stationConfig.chest)
                        sleep(1)
                    end
                else
                    print("No chest inventories detected!")
                    sleep(1.5)
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
end)

if basalt.run then
    basalt.run()
else
    basalt.autoUpdate()
end
