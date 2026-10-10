-- Automatic Installer & Dependency Downloader for CC:Tweaked ME System
local BASALT_URL = "https://basalt.madefor.cc/basalt.lua"

term.clear()
term.setCursorPos(1, 1)

local function drawTitle()
    term.setTextColor(colors.yellow)
    print("========================================")
    print("   AetherVault OS Installer v2.5       ")
    print("========================================")
    term.setTextColor(colors.white)
    print()
end

drawTitle()

-- Check HTTP API
if not http then
    term.setTextColor(colors.red)
    print("Error: HTTP API is disabled in ComputerCraft config!")
    print("Please enable http_enable=true in minecraft config.")
    return
end

-- Download Basalt v2.5 if missing
if not fs.exists("basalt.lua") then
    term.setTextColor(colors.cyan)
    write("Downloading Basalt v2.5 framework...")
    local resp, err = http.get(BASALT_URL)
    if resp then
        local code = resp.readAll()
        resp.close()
        local file = fs.open("basalt.lua", "w")
        file.write(code)
        file.close()
        term.setTextColor(colors.green)
        print(" [OK]")
    else
        term.setTextColor(colors.red)
        print(" [FAILED]")
        print("Could not download Basalt from " .. BASALT_URL)
        print("Error: " .. tostring(err))
        return
    end
else
    term.setTextColor(colors.green)
    print("Basalt framework (basalt.lua) is already installed.")
end

print()
term.setTextColor(colors.yellow)
print("Select installation target for this computer:")
term.setTextColor(colors.white)
print("1) Main Storage Server (Attached to wired modems/chests)")
print("2) Wireless Pocket Computer Remote")
print("3) IO Chest & GPS Setup / Calibration Tool Only")
print("4) Skip startup.lua setup")
print()
write("Select choice (1-4): ")
local choice = read()

local startupTarget = nil
if choice == "1" then
    startupTarget = "storage_server.lua"
elseif choice == "2" then
    startupTarget = "pocket_client.lua"
elseif choice == "3" then
    startupTarget = "io_config_tool.lua"
end

if startupTarget then
    local file = fs.open("startup.lua", "w")
    file.write("shell.run(\"" .. startupTarget .. "\")\n")
    file.close()
    term.setTextColor(colors.green)
    print("Set startup.lua to launch " .. startupTarget .. " on boot!")
end

print()
term.setTextColor(colors.green)
print("Installation complete!")
print("Run 'storage_server.lua' on your main computer, or 'pocket_client.lua' on pocket computers.")
