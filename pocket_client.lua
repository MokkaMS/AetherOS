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
local selectedItems = {}
local pullAllMode = false
local currentAutoMatch = nil

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
    :setSize(18, 1)
    :setBackground(colors.white)
    :setForeground(colors.black)
searchInput.placeholder = " Search..."

local autoBtn = mainFrame:addButton()
    :setPosition(19, 3)
    :setSize(8, 1)
    :setText("Auto")
    :setBackground(colors.purple)
    :setForeground(colors.white)

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
    :setPosition(5, 13)
    :setSize(5, 1)
    :setBackground(colors.white)
    :setForeground(colors.black)
qtyInput.text = "64"

local pullAllBtn = mainFrame:addButton()
    :setPosition(11, 13)
    :setSize(5, 1)
    :setText("ALL")
    :setBackground(colors.blue)
    :setForeground(colors.white)

local selectAllBtn = mainFrame:addButton()
    :setPosition(17, 13)
    :setSize(5, 1)
    :setText("Sel*")
    :setBackground(colors.cyan)
    :setForeground(colors.black)

local clearSelBtn = mainFrame:addButton()
    :setPosition(23, 13)
    :setSize(4, 1)
    :setText("Clr")
    :setBackground(colors.gray)
    :setForeground(colors.white)

local withdrawBtn = mainFrame:addButton()
    :setPosition(1, 14)
    :setSize(26, 1)
    :setText("Withdraw Selection (0)")
    :setBackground(colors.orange)
    :setForeground(colors.white)

local depositBtn = mainFrame:addButton()
    :setPosition(1, 15)
    :setSize(26, 1)
    :setText("Deposit Here (Nearest IO)")
    :setBackground(colors.green)
    :setForeground(colors.white)

local statusLabel = mainFrame:addLabel()
    :setPosition(1, 16)
    :setSize(26, 2)
    :setForeground(colors.yellow)
statusLabel.text = " Connecting to network..."

local refreshBtn = mainFrame:addButton()
    :setPosition(1, 18)
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
        for _, item in ipairs(currentItems) do
            if item.displayName:lower():find(filterText, 1, true) == 1 or item.name:lower():find(filterText, 1, true) == 1 then
                currentAutoMatch = item
                break
            end
        end
    end
end

local filteredItems = {}

local function populateList()
    itemList:clear()
    filteredItems = {}
    local filter = (searchInput.text or searchInput.value or ""):lower()
    updateAutoComplete(filter)

    for _, item in ipairs(currentItems) do
        if filter == "" or item.displayName:lower():find(filter, 1, true) then
            local isSel = selectedItems[item.name]
            local prefix = isSel and "[x]" or "[ ]"
            local dispName = item.displayName
            if #dispName > 12 then
                dispName = dispName:sub(1, 10) .. ".."
            end
            local entryText = string.format("%s %-12s %5d", prefix, dispName, item.total)
            itemList:addItem(entryText)
            table.insert(filteredItems, item.name)
        end
    end
    updateWithdrawButtonText()
end

local function fetchItems()
    updateGPS()
    
    if not serverId then
        statusLabel.text = " Searching for server..."
        local sId, errStr = net.findServer(4)
        if not sId then
            statusLabel.text = " Error: Server offline"
            return
        end
        serverId = sId
    end

    statusLabel.text = " Fetching catalog..."
    local ok, res = net.sendRequest(serverId, "GET_ITEMS", {}, 5)
    if ok and res.success and res.items then
        currentItems = res.items
        table.sort(currentItems, function(a, b)
            if a.total == b.total then return a.displayName:lower() < b.displayName:lower() end
            return a.total > b.total
        end)
        populateList()
        statusLabel.text = " Connected: " .. #currentItems .. " item types"
    else
        serverId = nil
        statusLabel.text = " Connection failed!"
    end
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
        return filteredItems[idx]
    end

    local itemObj = item or (self and self.getItem and idx and pcall(self.getItem, self, idx) and self:getItem(idx)) or (self and self.getValue and pcall(self.getValue, self) and self:getValue())
    local strText = nil
    if type(itemObj) == "table" then
        if itemObj.value then return itemObj.value end
        if itemObj.name then return itemObj.name end
        if itemObj.args and itemObj.args[1] then return itemObj.args[1] end
        strText = itemObj.text
    elseif type(itemObj) == "string" then
        strText = itemObj
    end

    if strText then
        local cleanName = strText:match("^%[%p%]%s+(.-)%s+%d+$") or strText:match("^%[%p%]%s+(.+)$") or strText
        cleanName = cleanName:gsub("^%s*(.-)%s*$", "%1")
        for _, it in ipairs(currentItems) do
            if it.displayName == cleanName or it.name == cleanName or cleanName:find(it.displayName, 1, true) then
                return it.name
            end
        end
    end

    return nil
end

local function handleSelection(self, item, index)
    if isUpdatingList then return end
    local itemName = resolveSelectedItemName(self, item, index)
    if itemName then
        selectedItems[itemName] = not selectedItems[itemName]
        isUpdatingList = true
        basalt.schedule(function()
            populateList()
            isUpdatingList = false
        end, 0)
    end
end

if itemList.onSelect then itemList:onSelect(handleSelection) end
if itemList.onChange then itemList:onChange(handleSelection) end

searchInput:onChange(function(self, text)
    populateList()
end)

autoBtn:onClick(function()
    if currentAutoMatch then
        searchInput.text = currentAutoMatch.displayName
        populateList()
    end
end)

pullAllBtn:onClick(function()
    pullAllMode = not pullAllMode
    if pullAllMode then
        pullAllBtn:setText("ALL!"):setBackground(colors.purple)
    else
        pullAllBtn:setText("ALL"):setBackground(colors.blue)
    end
end)

selectAllBtn:onClick(function()
    local filter = (searchInput.text or searchInput.value or ""):lower()
    for _, item in ipairs(currentItems) do
        if filter == "" or item.displayName:lower():find(filter, 1, true) then
            selectedItems[item.name] = true
        end
    end
    populateList()
end)

clearSelBtn:onClick(function()
    selectedItems = {}
    populateList()
end)

withdrawBtn:onClick(function()
    local requests = {}
    local rawVal = qtyInput.text or qtyInput.value or "64"
    local count = tonumber(rawVal) or 64

    for name, sel in pairs(selectedItems) do
        if sel then
            table.insert(requests, { item = name, count = count, all = pullAllMode })
        end
    end

    if #requests == 0 then
        statusLabel.text = " Select item(s) first!"
        return
    end

    withdrawBtn:setText("Withdrawing..."):setBackground(colors.yellow)
    statusLabel.text = " Sending request..."

    basalt.schedule(function()
        if not serverId then
            fetchItems()
            if not serverId then
                updateWithdrawButtonText()
                withdrawBtn:setBackground(colors.orange)
                return
            end
        end

        local payload = {
            requests = requests,
            gpsPos = playerPos
        }

        local ok, res = net.sendRequest(serverId, "WITHDRAW_MULTI", payload, 8)
        updateWithdrawButtonText()
        withdrawBtn:setBackground(colors.orange)
        if ok and res.success then
            local distStr = res.distance and string.format(" (%.1fm)", res.distance) or ""
            statusLabel.text = string.format(" Moved x%d to %s%s", res.moved or 0, res.chestLabel or "IO", distStr)
            selectedItems = {}
            fetchItems()
        else
            local errMsg = (type(res) == "table" and res.message) or (type(res) == "string" and res) or "Timeout"
            statusLabel.text = " Error: " .. errMsg
        end
    end)
end)

depositBtn:onClick(function()
    depositBtn:setText("Depositing..."):setBackground(colors.yellow)
    statusLabel.text = " Requesting deposit..."

    basalt.schedule(function()
        if not serverId then
            fetchItems()
            if not serverId then
                depositBtn:setText("Deposit Here (Nearest IO)"):setBackground(colors.green)
                return
            end
        end

        local payload = {
            gpsPos = playerPos
        }

        local ok, res = net.sendRequest(serverId, "DEPOSIT_ITEMS", payload, 8)
        depositBtn:setText("Deposit Here (Nearest IO)"):setBackground(colors.green)
        if ok and res.success then
            local distStr = res.distance and string.format(" (%.1fm)", res.distance) or ""
            statusLabel.text = string.format(" Deposited x%d from %s%s", res.count or 0, res.chestLabel or "IO", distStr)
            fetchItems()
        else
            local errMsg = (type(res) == "table" and res.message) or (type(res) == "string" and res) or "Timeout"
            statusLabel.text = " Error: " .. errMsg
        end
    end)
end)

refreshBtn:onClick(function()
    refreshBtn:setText("Refreshing..."):setBackground(colors.yellow)
    basalt.schedule(function()
        fetchItems()
        refreshBtn:setText("Refresh Server & GPS"):setBackground(colors.gray)
    end)
end)

fetchItems()

if basalt.run then
    basalt.run()
else
    basalt.autoUpdate()
end
