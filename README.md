# ⚡ AetherVault OS
### *Spatial Storage & Wireless Logistics Network for CC:Tweaked (NeoForge 1.21.1)*
**Repository:** [`MokkaMS/AetherOS`](https://github.com/MokkaMS/AetherOS)

**AetherVault OS** is an automated, GPS-driven storage and logistics system built for **Minecraft (NeoForge 1.21.1)** with **CC:Tweaked**, featuring a **Basalt v2.5 desktop GUI**, wireless **Pocket Computer remote control**, dedicated touchscreen **I/O Quick-Order Stations**, and intelligent **GPS nearest Input/Output chest routing**.

---

## 🌟 Key Features

- 🖥️ **Basalt v2.5 Graphical UI**: Modern desktop dashboard on the main server computer, and a responsive touch GUI optimized for handheld Pocket Computers (`26x20` screen).
- 📺 **Dedicated I/O Monitor Stations (`io_terminal.lua`)**: Touchscreen monitors next to chests for 1-tap instant ordering, live stock count badges, and 1-tap deposit all.
- 💾 **Dual Persistent Station Memory**:
  - **No More Resets**: Rebooting or restarting your computer will **never** reset your buttons or wipe your coordinates back to `0,0,0`!
  - Both button configurations and 3D coordinates (`X, Y, Z`) are saved locally in `/io_station_config.json` and backed up to the central storage server (`/storage_config.json`).
  - Replacing or resetting a terminal computer automatically adopts the server's saved coordinates and quick-order buttons for that chest!
- 📡 **Wireless Pocket Remote Control (`pocket_client.lua`)**: Browse items, withdraw stacks, or deposit items from anywhere in your base using Pocket Computers over Rednet.
- 🎯 **GPS Nearest IO Chest Routing**: Automatically calculates player 3D coordinates using `gps.locate()` and routes items to/from the closest registered Input/Output chest across your underground base!
- 🔌 **Dynamic Storage Network**: Connects all your chests/barrels via CC:Tweaked Wired Modems and Networking Cables.
- 📦 **Manual & Auto Deposit/Withdrawal**: Seamlessly handles manual placement/removal of items from storage chests or designated I/O dropoff points.
- ⚡ **Background Indexing & Auto-Deposit**: Automatically scans storage network contents every few seconds and imports items placed in I/O chests into main storage.

---

## 🏗️ Hardware & Block Setup Guide

### 1. Main Storage Server Computer
- **Computer**: Advanced Computer (or normal ComputerCraft computer).
- **Networking**:
  - Connect a **Wired Modem** to **any side of the Computer** (bottom, back, top, left, right, or front) and attach **Networking Cables** to all storage chests/barrels.
  - Right-click each Wired Modem attached to a chest to turn it on (red ring glowing).
  - Attach a **Wireless Modem** (or End Modem) to any open face of the computer for Pocket Computer communication.

### 2. Dedicated I/O Station (Monitor + Chest)
- **Computer**: Advanced Computer.
- **Monitor**: Advanced Monitor placed adjacent to the computer (e.g., 2x1, 3x2, or 1x1).
- **Chest**: Any chest or barrel connected to the wired networking cable with a Wired Modem (modem right-clicked active).
- **Networking**: Wired or Wireless Modem attached to connect to the AetherVault storage network.

### 3. Storage Chests & I/O Dropoff Chests
- **Storage Chests**: Chests/barrels connected to the wired modem network used for mass item storage.
- **Input/Output (I/O) Chests**: Designated chests placed at key locations in your base (e.g. Main Entrance, Mine Shaft, Crafting Hub, Mob Farm).

### 4. GPS Host Computers Setup (Wireless 📡)
> **Note**: GPS Host computers do **NOT** need wired cables or a connection to the storage network! They operate 100% wirelessly.

1. Craft **4 Advanced Computers** and attach a **Wireless Modem** (or End Modem for long range) to each.
2. Place the 4 computers in a 3D arrangement around your base (e.g. 3 computers at different corners at `Y=64`, and 1 computer placed higher up at `Y=95`). **Important**: Do not place all 4 in a straight line or on the exact same flat 2D plane.
3. Stand in front of each computer and press `F3` to write down its exact block coordinates `(X, Y, Z)`.
4. On each computer, create a `startup.lua` file so it runs automatically on boot:
   ```lua
   shell.run("gps", "host", "120", "95", "-240")  -- Replace with that computer's exact X Y Z
   ```
5. Whenever your Pocket Computer or I/O Station runs `gps.locate()`, it pinpoints your exact 3D position anywhere in your base!

---

## 🚀 Installation

### In-Game One-Command Install (Recommended ⚡)

On any in-game computer, run this single command to download and launch the installer:

```bash
wget run https://raw.githubusercontent.com/MokkaMS/AetherOS/main/installer.lua
```

Alternatively, download the installer to run it at any time:

```bash
wget https://raw.githubusercontent.com/MokkaMS/AetherOS/main/installer.lua installer.lua
installer.lua
```

The installer will:
1. Download or verify **Basalt v2.5**.
2. Install all core OS modules (`config.lua`, `db.lua`, `net_protocol.lua`, `storage_server.lua`, `pocket_client.lua`, `io_terminal.lua`, `io_config_tool.lua`).
3. Offer an interactive prompt to configure `startup.lua` for the computer's role:
   - `1` Main Storage Server (`storage_server.lua`)
   - `2` Wireless Pocket Computer Remote (`pocket_client.lua`)
   - `3` I/O Station & Quick-Order Monitor Terminal (`io_terminal.lua`)
   - `4` I/O Chest & GPS Setup / Calibration Tool (`io_config_tool.lua`)

---

### Manual File Copy (Singleplayer / Server File Access)

If you have file access to your Minecraft world or server:

1. In Minecraft, run `id` on the target computer to find its ID (e.g. `0`, `1`, `2`).
2. Open your computer save directory on your PC:
   - **Singleplayer**: `%appdata%\.minecraft\saves\<WorldName>\computercraft\computer\<id>\`
   - **Dedicated Server**: `<ServerDirectory>\world\computercraft\computer\<id>\`
3. Copy all `.lua` files from this repository directly into that folder.
4. Run `installer.lua` on the in-game computer to download **Basalt v2.5** and configure boot options.

---

## 🛠️ Usage Guide

### 1. Running the Storage Server
On the Main Server Computer:

```bash
storage_server.lua
```

The Basalt v2.5 desktop interface provides:
- **Item Catalog Tab**: Live item stock counts, search bar, auto-complete, and multi-selection withdrawal.
- **IO Chests Tab**: Real-time status of all registered I/O chests, calibrated 3D coordinates, and manual bulk deposit buttons.
- **Activity Logs Tab**: Track transfers, withdrawals, deposits, and remote client requests.
- **Settings Tab**: Toggle auto-deposit scans and adjust scan frequencies.

---

### 2. Running a Dedicated I/O Station (`io_terminal.lua`)
On an Advanced Computer connected to an Advanced Monitor and I/O Chest:

```bash
io_terminal.lua
```

#### Monitor Touchscreen:
- **1-Tap Quick Orders**: Tap any item button (e.g. `+64 Cobblestone [1.2k]`) to instantly order items from storage into the chest. Stock count badges show live availability.
- **`v DEPOSIT ALL v`**: 1-tap button to empty the I/O chest into main storage.
- **`+Chest`**: Place items into the chest and tap `+Chest` to automatically create quick-order buttons matching those items and stack sizes!
- **`+Browse`**: Browse storage catalog directly on the monitor and pick items with 16, 32, or 64 quantity presets.
- **`Del`**: Toggle delete mode and tap any button to remove it.
- **Paging**: Use `< Prev` and `Next >` to scroll through multiple pages of buttons.

#### Computer Terminal Console:
- Displays current monitor status, bound chest, registered coordinates `[X, Y, Z]`, and button count.
- **Hotkeys**:
  - `[A]` **Add Item**: Search catalog and set order count via keyboard.
  - `[D]` **Deposit Chest**: Trigger immediate deposit of the bound chest.
  - `[C]` **Select / Change Chest**: Select registered network chests or enter peripheral names; automatically adopts server coordinates and button layouts.
  - `[X]` **Set / Calibrate Coordinates**: Scans for GPS signal or prompts for manual `X, Y, Z` coordinates, instantly syncing them locally and with the server.
  - `[R]` **Refresh**: Re-scan storage stock and synchronize server connection.

#### Persistent Memory Highlights:
- Custom buttons and counts persist in `/io_station_config.json` and are backed up to the server.
- Coordinates will **never** reset to `0,0,0` on computer reboot.
- Replacing or wiping an I/O station computer and binding it to an existing chest restores all saved coordinates and buttons directly from the server.

---

### 3. Running the Pocket Computer Remote (`pocket_client.lua`)
On your handheld Wireless Pocket Computer:

```bash
pocket_client.lua
```

- Displays live **GPS coordinates** and available storage items.
- Tap an item, choose a quantity (or select `ALL`), and tap **"Withdraw Selection"** to send items to the nearest I/O chest.
- Dump items into your nearest I/O chest, tap **"Deposit Here (Nearest IO)"**, and the system imports them into main storage!

---

### 4. Registering & Calibrating I/O Chests via CLI Tool (`io_config_tool.lua`)
For quick standalone chest registration and GPS calibration from any network computer:

```bash
io_config_tool.lua
```

- **Option 1**: List all registered I/O chests with coordinates and online status.
- **Option 2**: Register or edit I/O chests (auto-detects GPS coordinates or shows current values as defaults; preserves existing quick-orders).
- **Option 3**: Remove registered I/O chests.
- **Option 4**: Test deposit from all I/O chests.
- **Option 5**: Server discovery / reconnect.

---

## 📄 File Structure

| File | Description |
| :--- | :--- |
| [`config.lua`](file:///C:/Users/matth/Documents/Code/Minecraft/AetherOS/config.lua) | Configuration loader, `/storage_config.json` manager, coordinate protection, and station button registry. |
| [`db.lua`](file:///C:/Users/matth/Documents/Code/Minecraft/AetherOS/db.lua) | Storage indexing engine, 3D Euclidean distance calculations, defragmentation, and transfer logic. |
| [`net_protocol.lua`](file:///C:/Users/matth/Documents/Code/Minecraft/AetherOS/net_protocol.lua) | Rednet RPC protocol for discovery, item requests, deposit triggers, and station synchronization. |
| [`storage_server.lua`](file:///C:/Users/matth/Documents/Code/Minecraft/AetherOS/storage_server.lua) | Central storage server application with desktop Basalt v2.5 GUI and background RPC daemon. |
| [`io_terminal.lua`](file:///C:/Users/matth/Documents/Code/Minecraft/AetherOS/io_terminal.lua) | Dedicated I/O Station application with monitor touchscreen buttons, persistent dual memory, and console calibration. |
| [`pocket_client.lua`](file:///C:/Users/matth/Documents/Code/Minecraft/AetherOS/pocket_client.lua) | Handheld Wireless Pocket Computer client with touch GUI and GPS routing. |
| [`io_config_tool.lua`](file:///C:/Users/matth/Documents/Code/Minecraft/AetherOS/io_config_tool.lua) | Interactive CLI configuration tool for I/O chest registration and GPS calibration. |
| [`installer.lua`](file:///C:/Users/matth/Documents/Code/Minecraft/AetherOS/installer.lua) | Standalone auto-installer embedding all system files and downloading Basalt v2.5. |
