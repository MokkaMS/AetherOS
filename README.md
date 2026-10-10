# ⚡ AetherVault OS
### *Spatial Storage & Wireless Logistics Network for CC:Tweaked (NeoForge 1.21.1)*

**AetherVault OS** is an automated, GPS-driven storage system built for **Minecraft (NeoForge 1.21.1)** with **CC:Tweaked**, featuring a **Basalt v2.5 GUI**, wireless **Pocket Computer remote control**, and intelligent **GPS nearest Input/Output chest selection**.

---

## 🌟 Key Features

- 🖥️ **Basalt v2.5 Graphical UI**: Sleek, modern graphical desktop dashboard on the main server computer, and a responsive touch GUI optimized for handheld Pocket Computers (`26x20` screen).
- 📡 **Wireless Pocket Remote Control**: Browse items, withdraw stacks, or deposit items from anywhere in your base using Pocket Computers over Rednet.
- 🎯 **GPS Nearest IO Chest Selection**: Automatically calculates player 3D coordinates using `gps.locate()` and routes items to/from the closest registered Input/Output chest across your underground base!
- 🔌 **Dynamic Storage Network**: Connects all your chests/barrels via CC:Tweaked Wired Modems and Networking Cables.
- 📦 **Manual & Auto Deposit/Withdrawal**: Seamlessly handles manual placement/removal of items from storage chests or designated I/O dropoff points.
- ⚡ **Background Indexing & Auto-Deposit**: Automatically scans storage network contents every few seconds and imports items placed in I/O chests into main storage.

---

## 🏗️ Hardware & Block Setup Guide

### 1. Main Storage Server Computer
- **Computer**: Advanced Computer (or normal Computer Craft computer).
- **Networking**:
  - Connect a **Wired Modem** to **any side of the Computer** (below/bottom, behind, top, left, right, or front) and attach **Networking Cables** to all your storage chests/barrels.
  - Right-click each Wired Modem attached to a chest to turn it on (red ring glowing).
  - Attach a **Wireless Modem** (or End Modem) to any open face of the computer for Pocket Computer communication.

### 2. Storage Chests & I/O Chests
- **Storage Chests**: Chests/barrels connected to the wired modem network used for mass item storage.
- **Input/Output (I/O) Chests**: Designated chests placed at key locations in your base (e.g. Main Base Entrance, Mine Shaft, Crafting Hub, Mob Farm).

### 3. GPS Host Computers Setup (Wireless 📡)
> **Note**: GPS Host computers do **NOT** need to be connected via wired cables or connected to the storage network! They operate 100% wirelessly.

1. Craft **4 Advanced Computers** and attach a **Wireless Modem** (or End Modem for long range) to each.
2. Place the 4 computers in a 3D arrangement around your base (e.g. 3 computers at different corners at `Y=64`, and 1 computer placed higher up at `Y=95`). **Important**: Do not place all 4 in a straight line or on the exact same flat 2D plane.
3. Stand in front of each computer and press `F3` to write down its exact block coordinates `(X, Y, Z)`.
4. On each computer, create a `startup.lua` file so it runs automatically on boot:
   ```lua
   shell.run("gps", "host", "120", "95", "-240")  -- Replace with that computer's exact X Y Z
   ```
5. Whenever your Pocket Computer runs `gps.locate()`, it sends a wireless ping to these 4 hosts to pinpoint your exact 3D player position anywhere in your base!

---

## 🚀 Installation Methods

You have **two easy ways** to get these files onto your ComputerCraft computers:

---

### Method A: Direct File Copy (No GitHub Required! ⚡)

If you are playing in **Singleplayer** or host/have file access to your Minecraft server, you can copy the `.lua` files directly into the computer's save folder on your PC!

1. In Minecraft, place down your Computer and type `id` in the terminal to find its Computer ID (e.g. `0`, `1`, `2`).
2. Open your Minecraft save directory on your PC:
   - **Singleplayer**: `%appdata%\.minecraft\saves\<YourWorldName>\computercraft\computer\<computer_id>\`
   - **Server**: `<ServerDirectory>\world\computercraft\computer\<computer_id>\`
3. Copy all `.lua` files from this folder (`storage_server.lua`, `pocket_client.lua`, `io_config_tool.lua`, `db.lua`, `config.lua`, `net_protocol.lua`, `installer.lua`) directly into that computer folder!
4. On the in-game computer, type `lua installer.lua` to download **Basalt v2.5** and finish setup.

---

### Method B: GitHub / Pastebin `wget` Download

If you prefer installing via URL in-game (or play on a remote server without file system access):

1. Upload these `.lua` files to your **GitHub repository** (or a GitHub Gist / Pastebin).
2. Get the **Raw URL** of `installer.lua` (e.g. `https://raw.githubusercontent.com/YourUsername/YourRepo/main/installer.lua`).
3. In Minecraft, run:
   ```bash
   wget run https://raw.githubusercontent.com/YourUsername/YourRepo/main/installer.lua
   ```

---

## 🛠️ Usage Guide

### 1. Registering & Calibrating I/O Chests
Run the setup tool on any computer connected to the wired modem network:

```bash
lua io_config_tool.lua
```

- Select **Option 2 (Register / Edit IO Chest)**.
- Pick a chest peripheral from the detected list (e.g. `minecraft:chest_0`).
- Give it a friendly label (e.g., `"Mine Shaft Dropoff"`).
- Set its role (`both`, `input`, or `output`).
- The tool will attempt to auto-fetch GPS coordinates if standing next to it, or you can input X, Y, Z coordinates manually.

### 2. Running the Storage Server
On the Main Server Computer:

```bash
lua storage_server.lua
```

The Basalt v2.5 desktop interface will open:
- **Item Catalog Tab**: Search items, view live inventory counts, and withdraw items.
- **IO Chests Tab**: Monitor connected I/O chests and trigger manual deposits.
- **Activity Logs Tab**: Track real-time network transfers and client requests.
- **Settings Tab**: Toggle auto-deposit or change scan frequencies.

### 3. Running the Pocket Computer Remote
On your handheld Wireless Pocket Computer:

```bash
lua pocket_client.lua
```

- The Pocket Computer connects over Rednet to the server.
- Shows current **GPS position** and item catalog.
- Select an item, enter quantity, and tap **"Withdraw (Nearest IO)"**. The system automatically computes distance to all I/O chests and sends items to the nearest one!
- Drop items into your nearest I/O chest, tap **"Deposit Here (Nearest IO)"**, and the system imports all items into main storage!

---

## 📄 File Structure

- `config.lua`: Configuration loader & serialized I/O chest registry.
- `db.lua`: Inventory indexing engine, Euclidean 3D GPS distance math, and item transfer algorithms.
- `net_protocol.lua`: Rednet message definitions & RPC communication handler.
- `storage_server.lua`: Main server application with Basalt v2.5 desktop GUI.
- `pocket_client.lua`: Handheld Pocket Computer client with Basalt v2.5 touch UI.
- `io_config_tool.lua`: Interactive CLI setup tool for I/O chest registration and GPS calibration.
- `installer.lua`: One-click installer & dependency downloader.
