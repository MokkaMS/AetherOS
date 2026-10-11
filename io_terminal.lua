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
addModal:hide()

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
    addModal:show()
    basalt.schedule(function()
        refreshStock()
        populateModalList("")
    end)
end)

modalCancelBtn:onClick(function()
    addModal:hide()
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
    addModal:hide()
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
