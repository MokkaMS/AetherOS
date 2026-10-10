-- Automatic Installer & Dependency Downloader for AetherVault OS (CC:Tweaked)
local BASALT_INSTALL_URL = "https://basalt.madefor.cc/2.5/install.lua"
local BASALT_RAW_URL = "https://raw.githubusercontent.com/Pyroxenium/Basalt2/refs/heads/basalt2.5/bundle/basalt.min.lua"

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
    print("Downloading Basalt v2.5 framework...")
    
    -- Attempt 1: Run official Basalt 2.5 installer script
    local success = pcall(function()
        shell.run("wget", "run", BASALT_INSTALL_URL, "minified")
    end)

    -- Attempt 2: Direct URL download if Attempt 1 didn't produce basalt.lua
    if not fs.exists("basalt.lua") then
        write("Fallback: Fetching raw Basalt bundle...")
        local resp, err = http.get(BASALT_RAW_URL)
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
            print("Could not download Basalt from " .. BASALT_RAW_URL)
            print("Error: " .. tostring(err))
            return
        end
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
