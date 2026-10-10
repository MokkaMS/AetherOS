-- Pocket Computer Wireless Remote Client with Basalt v2.5 GUI
local config = require("config")
local net = require("net_protocol")

-- Check for Basalt framework
local basaltOK, basalt = pcall(require, "basalt")
if not basaltOK then
    term.setTextColor(colors.red)
    print("Error: Basalt v2.5 required!")
    print("Run installer.lua to setup.")
    return
end

-- Open wireless modem
local modemOK, err = net.openWirelessModem()
if not modemOK then
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.red)
    print("Error: No wireless modem!")
    print("Attach a wireless modem to pocket computer.")
    return
end

-- State variables
local serverId = nil
local playerPos = nil
local currentItems = {}

-- Create main frame fitted for Pocket Computer screen (26x20)
local mainFrame = (basalt.getMainFrame and basalt.getMainFrame()) or basalt.createFrame()
mainFrame:setSize(26, 20):setBackground(colors.black)

-- Header Bar
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

-- Search Box
local searchInput = mainFrame:addInput()
    :setPosition(1, 3)
    :setSize(26, 1)
    :setBackground(colors.white)
    :setForeground(colors.black)
searchInput.placeholder = " Search items..."

-- Item List
local itemList = mainFrame:addList()
    :setPosition(1, 4)
    :setSize(26, 9)
    :setBackground(colors.lightGray)
    :setForeground(colors.black)

-- Controls Section
local qtyLabel = mainFrame:addLabel()
    :setPosition(1, 13)
    :setText("Qty:")
    :setForeground(colors.white)

local qtyInput = mainFrame:addInput()
    :setPosition(6, 13)
    :setSize(6, 1)
    :setBackground(colors.white)
    :setForeground(colors.black)
qtyInput.text = "64"

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

-- Action Buttons
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

-- Status / Output Feedback Label
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

-- Function to update GPS coordinates
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

-- Function to connect to server and fetch item catalog
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
        local filter = (searchInput.text or searchInput.value or (searchInput.getValue and searchInput:getValue()) or ""):lower()
        
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

-- Event Listeners
searchInput:onChange(function(self, text)
    itemList:clear()
    text = (text or searchInput.text or searchInput.value or ""):lower()
    for _, item in ipairs(currentItems) do
        if text == "" or item.displayName:lower():find(text, 1, true) then
            local entry = string.format("%-16s x%d", item.displayName:sub(1, 15), item.total)
            itemList:addItem(entry, nil, nil, item.name)
        end
    end
end)

preset16Btn:onClick(function()
    qtyInput.text = "16"
    if qtyInput.setValue then pcall(function() qtyInput:setValue("16") end) end
end)
preset64Btn:onClick(function()
    qtyInput.text = "64"
    if qtyInput.setValue then pcall(function() qtyInput:setValue("64") end) end
end)

withdrawBtn:onClick(function()
    local selected = itemList:getItem(itemList:getItemIndex())
    if not selected or not selected.args or not selected.args[1] then
        statusLabel:setText(" Select an item first!")
        return
    end

    local itemName = selected.args[1]
    local rawVal = qtyInput.text or qtyInput.value or (qtyInput.getValue and qtyInput:getValue()) or "64"
    local count = tonumber(rawVal) or 64

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

-- Initial connection attempt
fetchItems()

-- Run Basalt loop
if basalt.run then
    basalt.run()
else
    basalt.autoUpdate()
end
