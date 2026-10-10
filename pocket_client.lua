-- Pocket Computer Wireless Remote Client with Basalt v2.5 GUI
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
local selectedItemName = nil

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
    :setSize(26, 1)
    :setBackground(colors.white)
    :setForeground(colors.black)
searchInput.placeholder = " Search items..."

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
statusLabel.text = " Connecting to network..."

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
        gpsLabel.text = string.format(" GPS: %d, %d, %d", playerPos.x, playerPos.y, playerPos.z)
    else
        playerPos = nil
        gpsLabel.text = " GPS: Signal Unavailable"
    end
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
        itemList:clear()
        selectedItemName = nil
        local filter = (searchInput.text or searchInput.value or (searchInput.getValue and searchInput:getValue()) or ""):lower()
        
        for _, item in ipairs(currentItems) do
            if filter == "" or item.displayName:lower():find(filter, 1, true) then
                local entryText = string.format("%-15s x%d", item.displayName:sub(1, 14), item.total)
                itemList:addItem({ text = entryText, value = item.name, name = item.name })
            end
        end
        statusLabel.text = " Connected: " .. #currentItems .. " item types"
    else
        serverId = nil
        statusLabel.text = " Connection failed!"
    end
end

itemList:onSelect(function(self, item, index)
    if type(item) == "table" then
        selectedItemName = item.value or item.name
    elseif type(item) == "string" then
        selectedItemName = item
    end
end)

searchInput:onChange(function(self, text)
    itemList:clear()
    selectedItemName = nil
    text = (text or searchInput.text or searchInput.value or ""):lower()
    for _, item in ipairs(currentItems) do
        if text == "" or item.displayName:lower():find(text, 1, true) then
            local entryText = string.format("%-15s x%d", item.displayName:sub(1, 14), item.total)
            itemList:addItem({ text = entryText, value = item.name, name = item.name })
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
    if not selectedItemName then
        statusLabel.text = " Select an item first!"
        return
    end

    local rawVal = qtyInput.text or qtyInput.value or (qtyInput.getValue and qtyInput:getValue()) or "64"
    local count = tonumber(rawVal) or 64

    if not serverId then
        fetchItems()
        if not serverId then return end
    end

    statusLabel.text = " Sending withdraw request..."
    local payload = {
        item = selectedItemName,
        count = count,
        gpsPos = playerPos
    }

    local ok, res = net.sendRequest(serverId, "WITHDRAW_ITEM", payload, 3)
    if ok and res.success then
        local distStr = res.distance and string.format(" (%.1fm)", res.distance) or ""
        statusLabel.text = string.format(" Moved x%d to %s%s", res.moved or 0, res.chestLabel or "IO", distStr)
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
