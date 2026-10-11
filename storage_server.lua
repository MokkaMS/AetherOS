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
local modemOK, modemSide = net.openModem()
if modemOK then
    rednet.host(config.data.protocol, config.data.hostname)
    db.addLog("Rednet started on " .. modemSide .. " (" .. config.data.hostname .. ")", "system")
else
    db.addLog("Warning: No modem active. Remote pocket computer & client control disabled.", "warning")
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
    :setSize(termW - 25, 1)
searchInput.placeholder = "Search items..."

local autoCompleteBtn = itemsFrame:addButton()
    :setPosition(termW - 24, 1)
    :setSize(12, 1)
    :setText("TabComplete")
    :setBackground(colors.purple)
    :setForeground(colors.white)

local rescanBtn = itemsFrame:addButton()
    :setPosition(termW - 11, 1)
    :setSize(11, 1)
    :setText("Refresh")
    :setBackground(colors.green)
    :setForeground(colors.white)

local selectAllBtn = itemsFrame:addButton()
    :setPosition(1, 2)
    :setSize(11, 1)
    :setText("Select All")
    :setBackground(colors.cyan)
    :setForeground(colors.black)

local clearSelBtn = itemsFrame:addButton()
    :setPosition(13, 2)
    :setSize(11, 1)
    :setText("Clear Sel")
    :setBackground(colors.gray)
    :setForeground(colors.white)

local autoCompleteHint = itemsFrame:addLabel()
    :setPosition(25, 2)
    :setForeground(colors.yellow)
autoCompleteHint.text = ""

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
    :setSize(6, 1)
    :setBackground(colors.white)
    :setForeground(colors.black)
withdrawQtyInput.text = "64"

local withdrawQtyHighlighted = false

local function setWithdrawQtyHighlight(highlight)
    withdrawQtyHighlighted = highlight
    if highlight then
        withdrawQtyInput:setBackground(colors.lightBlue):setForeground(colors.black)
    else
        withdrawQtyInput:setBackground(colors.white):setForeground(colors.black)
    end
end

withdrawQtyInput:onClick(function(self)
    if withdrawQtyHighlighted then
        self.text = ""
        if self.setValue then pcall(self.setValue, self, "") end
        if self.setText then pcall(self.setText, self, "") end
        setWithdrawQtyHighlight(false)
    else
        setWithdrawQtyHighlight(true)
    end
end)

withdrawQtyInput:onChange(function(self, text)
    if withdrawQtyHighlighted then
        withdrawQtyHighlighted = false
        setWithdrawQtyHighlight(false)
        local clean = text or ""
        local newChar = clean:sub(-1)
        if not newChar:match("%d") then
            newChar = clean:match("%d") or ""
        end
        self.text = newChar
        if self.setValue then pcall(self.setValue, self, newChar) end
        if self.setText then pcall(self.setText, self, newChar) end
    end
end)

local pullAllMode = false

local pullAllBtn = withdrawBox:addButton()
    :setPosition(8, 1)
    :setSize(10, 1)
    :setText("PULL: QTY")
    :setBackground(colors.blue)
    :setForeground(colors.white)

local withdrawBtn = withdrawBox:addButton()
    :setPosition(19, 1)
    :setSize(math.max(1, termW - 19), 1)
    :setText("Withdraw Selection (0)")
    :setBackground(colors.orange)
    :setForeground(colors.white)

local selectedItems = {}
local filteredItems = {}
local currentAutoMatch = nil

local function getSelectedCount()
    local count = 0
    for _, sel in pairs(selectedItems) do
        if sel then count = count + 1 end
    end
    return count
end

local function updateWithdrawButtonText()
    local count = getSelectedCount()
    if count == 0 then
        withdrawBtn:setText("Withdraw Selection (0)")
    else
        withdrawBtn:setText(string.format("Withdraw Sel (%d items)", count))
    end
end

local function updateAutoComplete(filterText)
    currentAutoMatch = nil
    filterText = (filterText or ""):lower()
    if filterText ~= "" then
        for _, item in ipairs(db.itemIndex) do
            if item.displayName:lower():find(filterText, 1, true) == 1 or item.name:lower():find(filterText, 1, true) == 1 then
                currentAutoMatch = item
                break
            end
        end
        if not currentAutoMatch then
            for _, item in ipairs(db.itemIndex) do
                if item.displayName:lower():find(filterText, 1, true) or item.name:lower():find(filterText, 1, true) then
                    currentAutoMatch = item
                    break
                end
            end
        end
    end

    if currentAutoMatch then
        autoCompleteHint.text = "Auto: " .. currentAutoMatch.displayName
    else
        autoCompleteHint.text = ""
    end
end

local function updateListItemAt(idx, itemName)
    if not idx or not itemName then return end
    local isSel = selectedItems[itemName]
    local prefix = isSel and "[x] " or "[ ] "
    local maxNameLen = math.max(10, termW - 14)
    local itemData = db.items[itemName]
    local dispName = itemData and itemData.displayName or itemName
    if #dispName > maxNameLen then
        dispName = dispName:sub(1, maxNameLen - 2) .. ".."
    end
    local total = itemData and itemData.total or 0
    local entryText = string.format("%s%-" .. maxNameLen .. "s %6d", prefix, dispName, total)
    if itemList.editItem then
        pcall(itemList.editItem, itemList, idx, entryText)
    elseif itemList.getItem then
        local ok, itObj = pcall(itemList.getItem, itemList, idx)
        if ok and type(itObj) == "table" then
            itObj.text = entryText
        end
    end
end

local function populateItemList(filter)
    local prevOffset = nil
    if itemList.getOffset then
        local ok, off = pcall(itemList.getOffset, itemList)
        if ok and type(off) == "number" then prevOffset = off end
    end

    itemList:clear()
    filteredItems = {}
    filter = filter and filter:lower() or ""
    
    for _, item in ipairs(db.itemIndex) do
        if filter == "" or item.displayName:lower():find(filter, 1, true) or item.name:lower():find(filter, 1, true) then
            local isSel = selectedItems[item.name]
            local prefix = isSel and "[x] " or "[ ] "
            
            local maxNameLen = math.max(10, termW - 14)
            local dispName = item.displayName
            if #dispName > maxNameLen then
                dispName = dispName:sub(1, maxNameLen - 2) .. ".."
            end
            local entryText = string.format("%s%-" .. maxNameLen .. "s %6d", prefix, dispName, item.total)

            itemList:addItem(entryText)
            table.insert(filteredItems, item.name)
        end
    end

    if prevOffset and itemList.setOffset then
        pcall(itemList.setOffset, itemList, prevOffset)
    end

    updateStatsDisplay()
    updateWithdrawButtonText()
    updateAutoComplete(filter)
end

local isUpdatingList = false

local function resolveSelectedItemName(self, item, index)
    local idx = nil
    if type(index) == "number" then
        idx = index
    elseif type(item) == "number" then
        idx = item
    elseif self and self.getSelectedIndex then
        local ok, val = pcall(self.getSelectedIndex, self)
        if ok and type(val) == "number" then idx = val end
    end

    if idx and filteredItems[idx] then
        return filteredItems[idx], idx
    end

    local itemObj = item or (self and self.getItem and idx and pcall(self.getItem, self, idx) and self:getItem(idx)) or (self and self.getValue and pcall(self.getValue, self) and self:getValue())
    local strText = nil
    if type(itemObj) == "table" then
        if itemObj.value then return itemObj.value, idx end
        if itemObj.name then return itemObj.name, idx end
        if itemObj.args and itemObj.args[1] then return itemObj.args[1], idx end
        strText = itemObj.text
    elseif type(itemObj) == "string" then
        strText = itemObj
    end

    if strText then
        local cleanName = strText:match("^%[%p%]%s+(.-)%s+%d+$") or strText:match("^%[%p%]%s+(.+)$") or strText
        cleanName = cleanName:gsub("^%s*(.-)%s*$", "%1")
        for i, it in ipairs(db.itemIndex) do
            if it.displayName == cleanName or it.name == cleanName or cleanName:find(it.displayName, 1, true) then
                return it.name, idx
            end
        end
    end

    return nil, nil
end

local function handleSelection(self, item, index)
    if isUpdatingList then return end
    setWithdrawQtyHighlight(false)
    local itemName, idx = resolveSelectedItemName(self, item, index)
    if itemName then
        selectedItems[itemName] = not selectedItems[itemName]
        if idx and itemList.editItem then
            updateListItemAt(idx, itemName)
            updateWithdrawButtonText()
        else
            isUpdatingList = true
            basalt.schedule(function()
                populateItemList(searchInput.text or searchInput.value or "")
                isUpdatingList = false
            end, 0)
        end
    end
end

if itemList.onSelect then itemList:onSelect(handleSelection) end
if itemList.onChange then itemList:onChange(handleSelection) end

searchInput:onChange(function(self, text)
    populateItemList(text or searchInput.text or searchInput.value or "")
end)

autoCompleteBtn:onClick(function()
    if currentAutoMatch then
        searchInput.text = currentAutoMatch.displayName
        populateItemList(currentAutoMatch.displayName)
    end
end)

selectAllBtn:onClick(function()
    local filter = (searchInput.text or searchInput.value or ""):lower()
    for _, item in ipairs(db.itemIndex) do
        if filter == "" or item.displayName:lower():find(filter, 1, true) or item.name:lower():find(filter, 1, true) then
            selectedItems[item.name] = true
        end
    end
    populateItemList(filter)
end)

clearSelBtn:onClick(function()
    selectedItems = {}
    populateItemList(searchInput.text or searchInput.value or "")
end)

pullAllBtn:onClick(function()
    pullAllMode = not pullAllMode
    if pullAllMode then
        pullAllBtn:setText("PULL: ALL"):setBackground(colors.purple)
    else
        pullAllBtn:setText("PULL: QTY"):setBackground(colors.blue)
    end
end)

rescanBtn:onClick(function()
    db.addLog("Refreshing storage index in background...", "info")
    rescanBtn:setText("Scanning..."):setBackground(colors.yellow)
    basalt.schedule(function()
        db.scanStorage()
        populateItemList(searchInput.text or searchInput.value or "")
        rescanBtn:setText("Refresh"):setBackground(colors.green)
        db.addLog("Storage refresh complete.", "info")
    end, 0)
end)

withdrawBtn:onClick(function()
    local requests = {}
    local rawVal = withdrawQtyInput.text or withdrawQtyInput.value or (withdrawQtyInput.getValue and withdrawQtyInput:getValue()) or "64"
    local count = tonumber(rawVal) or 64

    for name, sel in pairs(selectedItems) do
        if sel then
            table.insert(requests, { item = name, count = count, all = pullAllMode })
        end
    end

    if #requests == 0 then
        db.addLog("Select one or more items from the list first!", "warning")
        return
    end

    local nearestIO, dist, info = db.findNearestIOChest(nil, "output")
    if not nearestIO then
        db.addLog("No IO chest available for withdrawal!", "error")
        return
    end

    withdrawBtn:setText("Moving..."):setBackground(colors.yellow)
    basalt.schedule(function()
        local moved, err = db.withdrawMulti(requests, nearestIO)
        withdrawBtn:setText("Withdraw"):setBackground(colors.blue)
        if err then
            db.addLog("Withdraw error: " .. err, "error")
        else
            db.addLog(string.format("Multi-withdraw complete: moved %d total items.", moved), "info")
            selectedItems = {}
            populateItemList(searchInput.text or searchInput.value or "")
        end
    end)
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
    :setBackground(colors.black)
    :setForeground(colors.white)

local ioCountLabel = ioFrame:addLabel()
    :setPosition(1, math.max(1, contentH - 2))
    :setForeground(colors.yellow)

local ioDepositBtn = ioFrame:addButton()
    :setPosition(1, math.max(1, contentH - 1))
    :setSize(24, 1)
    :setText("Deposit All IO Chests")
    :setBackground(colors.green)
    :setForeground(colors.white)

local function populateIOList()
    ioList:clear()
    local registered = config.getIOChests()
    local count = 0

    for pName, data in pairs(registered) do
        count = count + 1
        local isPresent, actualPName = config.isPeripheralPresent(pName)
        local status = isPresent and "[ONLINE]" or "[OFFLINE]"
        local label = data.label or pName
        if #label > 14 then label = label:sub(1, 12) .. ".." end
        local role = (data.role or "both"):upper()
        local text = string.format("%-9s %-14s [%d,%d,%d] Role:%s", status, label, data.x or 0, data.y or 0, data.z or 0, role)
        ioList:addItem(text)
    end

    if count == 0 then
        ioList:addItem("[!] No IO chests registered yet.")
        ioList:addItem("Run 'io_config_tool' on a computer to add an IO chest.")
    end

    ioCountLabel.text = string.format(" Registered IO: %d | Storage Chests: %d", count, #db.storageChests)
end

ioDepositBtn:onClick(function()
    db.addLog("Executing manual deposit from all IO chests in background...", "info")
    ioDepositBtn:setText("Depositing..."):setBackground(colors.yellow)
    basalt.schedule(function()
        local moved, _ = db.depositAllIO()
        db.addLog(string.format("Manual IO Deposit complete: imported %d items.", moved), "info")
        ioDepositBtn:setText("Deposit All IO Chests"):setBackground(colors.green)
        populateIOList()
        populateItemList(searchInput.text or searchInput.value or "")
    end)
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
local scanIntervals = { 5, 10, 15, 30, 60, 120 }
local scanIntervalBtn = settingsFrame:addButton()
    :setPosition(2, 4)
    :setSize(28, 1)
    :setText(string.format("Scan Interval: %ds (Click)", config.data.scanInterval or 15))
    :setBackground(colors.blue)
    :setForeground(colors.white)

scanIntervalBtn:onClick(function()
    local current = config.data.scanInterval or 15
    local nextVal = 15
    for i, v in ipairs(scanIntervals) do
        if v == current then
            nextVal = scanIntervals[(i % #scanIntervals) + 1]
            break
        end
    end
    config.data.scanInterval = nextVal
    config.save()
    scanIntervalBtn:setText(string.format("Scan Interval: %ds (Click)", nextVal))
    db.addLog(string.format("Changed scan interval to %ds", nextVal), "info")
end)

local autoDepositBtn = settingsFrame:addButton()
    :setPosition(2, 6)
    :setSize(28, 1)
    :setText("Auto Deposit: " .. (config.data.autoDeposit and "ENABLED" or "DISABLED"))
    :setBackground(config.data.autoDeposit and colors.green or colors.red)
    :setForeground(colors.white)

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
-- BACKGROUND REDNET LISTENER (COROUTINE THREAD)
---------------------------------------------------------
basalt.schedule(function()
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
                    local moved, err = db.withdraw(itemName, count, targetIO, true)
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

            elseif cmd == "WITHDRAW_MULTI" then
                local requests = payload.requests or {}
                local gpsPos = payload.gpsPos

                local targetIO, dist, info = db.findNearestIOChest(gpsPos, "output")
                
                if not targetIO then
                    response = { success = false, message = "No IO chest available on network!" }
                else
                    local moved, err = db.withdrawMulti(requests, targetIO)
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
                    local moved, err = db.deposit(sourceIO, true)
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

            elseif cmd == "REGISTER_IO_CHEST" then
                local pName = payload.peripheralName
                local label = payload.label or pName
                local x = payload.x or 0
                local y = payload.y or 0
                local z = payload.z or 0
                local role = payload.role or "both"

                if pName then
                    config.setIOChest(pName, label, x, y, z, role)
                    db.discoverPeripherals()
                    db.addLog(string.format("Remote IO Register: %s (%s) [%d,%d,%d]", pName, label, x, y, z), "info")
                    response = { success = true, message = "Registered " .. pName .. " on server!" }
                    populateIOList()
                    updateStatsDisplay()
                else
                    response = { success = false, message = "Missing peripheralName parameter" }
                end

            elseif cmd == "REMOVE_IO_CHEST" then
                local pName = payload.peripheralName
                if pName then
                    config.removeIOChest(pName)
                    db.discoverPeripherals()
                    db.addLog(string.format("Remote IO Remove: %s", pName), "info")
                    response = { success = true, message = "Removed " .. pName .. " on server!" }
                    populateIOList()
                    updateStatsDisplay()
                else
                    response = { success = false, message = "Missing peripheralName parameter" }
                end
            end

            rednet.send(senderId, response, config.data.protocol)
            populateItemList(searchInput.text or searchInput.value or "")
        end
    end
end)

---------------------------------------------------------
-- BACKGROUND PERIODIC STORAGE SCANNER (COROUTINE THREAD)
---------------------------------------------------------
basalt.schedule(function()
    while true do
        sleep(config.data.scanInterval or 5)
        local moved = 0
        if config.data.autoDeposit then
            moved = db.depositAllIO()
        end
        if moved == 0 then
            db.scanStorage()
        end
        updateStatsDisplay()
        if moved > 0 then
            populateItemList(searchInput.text or searchInput.value or "")
        end
    end
end)

if basalt.run then
    basalt.run()
else
    basalt.autoUpdate()
end
