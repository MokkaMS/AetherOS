-- Main Server Storage System with Basalt v2.5 GUI & Wireless Rednet Controller
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
    :setSize(termW - 14, 1)
searchInput.placeholder = "Search items..."

local rescanBtn = itemsFrame:addButton()
    :setPosition(termW - 12, 1)
    :setSize(12, 1)
    :setText("Refresh")
    :setBackground(colors.green)
    :setForeground(colors.white)

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
    :setSize(8, 1)
withdrawQtyInput.text = "64"

local withdrawBtn = withdrawBox:addButton()
    :setPosition(10, 1)
    :setSize(22, 1)
    :setText("Withdraw to Closest IO")
    :setBackground(colors.orange)

local selectedItemName = nil

local function populateItemList(filter)
    itemList:clear()
    selectedItemName = nil
    filter = filter and filter:lower() or ""
    
    for _, item in ipairs(db.itemIndex) do
        if filter == "" or item.displayName:lower():find(filter, 1, true) or item.name:lower():find(filter, 1, true) then
            local entryText = string.format("%-28s x%d", item.displayName, item.total)
            itemList:addItem({ text = entryText, value = item.name, name = item.name })
        end
    end
    updateStatsDisplay()
end

itemList:onSelect(function(self, item, index)
    if type(item) == "table" then
        selectedItemName = item.value or item.name
    elseif type(item) == "string" then
        selectedItemName = item
    end
end)

searchInput:onChange(function(self, text)
    populateItemList(text or searchInput.text or searchInput.value or "")
end)

rescanBtn:onClick(function()
    db.scanStorage()
    populateItemList(searchInput.text or searchInput.value or "")
    db.addLog("Manual index refresh triggered.", "info")
end)

withdrawBtn:onClick(function()
    if not selectedItemName then
        db.addLog("Select an item from the list first!", "warning")
        return
    end

    local rawVal = withdrawQtyInput.text or withdrawQtyInput.value or (withdrawQtyInput.getValue and withdrawQtyInput:getValue()) or "64"
    local count = tonumber(rawVal) or 64
    
    local nearestIO, dist, info = db.findNearestIOChest(nil, "output")
    if not nearestIO then
        db.addLog("No IO chest available for withdrawal!", "error")
        return
    end

    local moved, err = db.withdraw(selectedItemName, count, nearestIO)
    if err then
        db.addLog("Withdraw error: " .. err, "error")
    else
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
    for pName, data in pairs(registered) do
        local present = peripheral.isPresent(pName) and "[ONLINE]" or "[OFFLINE]"
        local text = string.format("%s %-16s [%d, %d, %d] Role: %s", present, data.label, data.x, data.y, data.z, data.role)
        ioList:addItem(text)
    end
end

ioDepositBtn:onClick(function()
    local moved, _ = db.depositAllIO()
    db.addLog(string.format("Manual IO Deposit: imported %d items.", moved), "info")
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
