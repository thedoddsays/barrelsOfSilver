# Barrels of Silver

*(working title)*

A top-down age-of-sail pirate game built in [Godot](https://godotengine.org). Sail the Caribbean
with a high, map-like camera, read the wind, and trade broadsides with enemy ships.

**Status: early prototype.** You can sail one ship around open water and islands and fight an
endless series of AI ships. Ports, trading, boarding and a campaign come later. Ships and
islands use placeholder shapes for now.

Runs natively on **Windows 11** and **Linux** (tested on Linux Mint).

---

## Contents

1. [What you need](#1-what-you-need)
2. [Install and run](#2-install-and-run)
3. [How to play](#3-how-to-play)
4. [Troubleshooting](#4-troubleshooting)
5. [Building a standalone game](#5-building-a-standalone-game)
6. [For developers](#6-for-developers)

---

## 1. What you need

- **Godot 4.7 or newer**, *standard* build (not the .NET/C# build). It's free and needs no installation.
- **Git**, to download the project ([git-scm.com](https://git-scm.com)). You can also download
  the project as a zip from GitHub instead.
- A graphics card with **up-to-date drivers** (Vulkan or Direct3D 12). Almost any GPU from the last ~8 years works.
- **Keyboard and a mouse with a scroll wheel.**

---

## 2. Install and run

### Step 1: Update your graphics driver

Old drivers are the #1 cause of crashes and black windows, so do this first.

- **Windows 11:** use the NVIDIA app, AMD Adrenalin, or Intel Driver & Support Assistant.
- **Linux Mint:**
  - NVIDIA: open **Driver Manager** and pick the recommended proprietary driver.
  - AMD / Intel: the built-in drivers work. Keep the system updated.
  - Optional check that Vulkan works:
    ```bash
    sudo apt install vulkan-tools
    vulkaninfo --summary
    ```

### Step 2: Download Godot

Go to <https://godotengine.org/download> and get **Godot 4.7.x – standard**.

- **Windows 11:** extract the zip to a permanent folder, e.g. `C:\Tools\Godot\`.
  Tip: right-click the `.exe` → *Show more options* → *Send to → Desktop (create shortcut)*.
- **Linux Mint:** extract it to e.g. `~/Apps/Godot/`, then make it executable:
  ```bash
  chmod +x ~/Apps/Godot/Godot_v4.7*_linux.x86_64
  ```

### Step 3: Get the project

**Windows 11** (Command Prompt or PowerShell):

```bash
git clone https://github.com/thedoddsays/barrelsOfSilver.git C:\Dev\barrels-of-silver
```

> ⚠️ Keep the project **out of OneDrive-synced folders** (Documents, Desktop, etc.). OneDrive
> locks files while Godot writes to them, which causes confusing import errors.

**Linux Mint:**

```bash
git clone https://github.com/thedoddsays/barrelsOfSilver.git ~/Dev/barrels-of-silver
```

**No Git?** On the GitHub page, click **Code → Download ZIP** and extract it to the same kind of folder.

### Step 4: Open it in Godot

1. Launch Godot. The **Project Manager** opens.
2. Click **Import** and select `project.godot` inside the project folder.
3. Click **Import & Edit**. The first import takes a few seconds.

### Step 5: Play

Press **F5**, or click the ▶ **Run Project** button at the top right. The game opens in its own window.

> **Only seeing an empty grid?** That's normal. The editor shows a blank 3D grid because the
> world is built when the game starts. Press F5.

---

## 3. How to play

You start at sea with an enemy ship already hunting you. Sink it and another arrives
10 seconds later. See how many you can take down before you go to the bottom.

### Controls

**Sailing**

| Input | Action |
|---|---|
| **A / D** or **← / →** | Steer |
| **W / S** or **↑ / ↓** | More / less sail: furled → battle sails → full sail |

**Combat**

| Input | Action |
|---|---|
| **Left click** | Fire the broadside on the side of the ship facing your mouse cursor |
| **1** | Round shot: smashes the hull. Longest range. |
| **2** | Chain shot: shreds sails and rigging, slowing the enemy down |
| **3** | Grape shot: cuts down crew. Short range only. |
| **R** | Sail again after your ship sinks |

**Camera**

| Input | Action |
|---|---|
| **Mouse wheel** | Zoom (closer = lower, more cinematic angle) |
| **Q / E** or **right-drag** | Rotate the view |
| **C** | Cruise view: a low camera behind the ship with the HUD hidden. Just sail and enjoy. |
| **F11** / **Esc** | Fullscreen / quit |

In cruise view, scrolling, right-dragging, Q/E, clicking or pressing C again returns you to
the map view. That click doesn't fire your guns.

### Sailing basics

- **The wind is everything.** On the compass (bottom right), the **blue arrow** shows where
  the wind is blowing *toward* and the **orange arrow** is your heading.
- **Heading into the wind is slow.** Within about 30° of it you're "in irons" and crawl along
  at a quarter of your speed or so.
- **A broad reach is fastest**, with the wind coming over your back corner. The HUD shows your
  point of sail and how well you're catching the wind as a percentage.
- **Speed helps you turn.** The rudder bites harder the faster you're moving.
- **Sails take time.** Your crew needs a moment to set or furl canvas.
- The wind slowly shifts and gusts, so keep an eye on the compass.

### Fighting

- **Aim with the mouse.** Move the cursor to the left or right of your ship to choose which
  broadside to use. Lines on the water show where the shots will go.
  - **Bright lines:** loaded, ready to fire.
  - **Dim red lines:** still reloading. Each side reloads separately, so you can fire one
    broadside, turn, and fire the other.
- **There's no range control.** Anything along the lines, out to their end, is in the line of fire.
- **Damage matters:**
  - **Hull:** at 0% the ship sinks.
  - **Sails:** damaged sails cost speed.
  - **Crew:** fewer crew means slower reloading and sail handling.
- **Finding the enemy:** red dots on the edge of the compass point to enemy ships.
- **The enemy is smart.** It circles to stay in range, uses the wind, avoids islands, and
  runs away when it's losing. Chain shot is great for stopping a runner.

**Tips:** open with chain shot to slow the enemy, switch to round shot to sink it, and keep
the wind on your side so you can choose the fight.

---

## 4. Troubleshooting

| Problem | Fix |
|---|---|
| Editor shows only an empty grid | Normal. Press **F5** to run the game. |
| Black window or crash on launch | Update your graphics driver (Step 1), then try another renderer (below). |
| Very old GPU / no Vulkan | Start Godot with `--rendering-driver opengl3`. It runs but looks simpler. |
| Windows: "Windows protected your PC" | Click **More info → Run anyway**. Godot and our builds aren't code-signed yet. |
| Windows: strange import or file errors | Move the project out of OneDrive-synced folders. |
| Image looks blurry | Check Windows Settings → Display → Scale, and try fullscreen (F11). |
| Anything else | Copy the red text from the **Output** and **Debugger → Errors** panels at the bottom of the editor and send it to the developer. |

**Starting Godot with a different renderer:**

```bash
# Windows (Command Prompt, in the Godot folder)
Godot_v4.7.2-stable_win64.exe --rendering-driver vulkan
Godot_v4.7.2-stable_win64.exe --rendering-driver opengl3

# Linux
./Godot_v4.7.2-stable_linux.x86_64 --rendering-driver opengl3
```

---

## 5. Building a standalone game

A build lets people play without installing Godot. Each one is a **single file** with nothing to install.

**One-time setup:** in the Godot editor, open **Editor → Manage Export Templates → Download and Install**.

**From the editor (Windows or Linux)**

1. Open **Project → Export…**
2. Pick **Windows Desktop** or **Linux**.
3. Click **Export Project**.

**From the command line (Linux)**

```bash
./export.sh
# or, if Godot isn't on your PATH:
GODOT=~/Apps/Godot/Godot_v4.7.2-stable_linux.x86_64 ./export.sh
```

| Platform | Output | To play |
|---|---|---|
| Windows 11 | `build/windows/BarrelsOfSilver.exe` | Double-click it. |
| Linux | `build/linux/BarrelsOfSilver.x86_64` | `chmod +x` it, then run it. |

You can build both platforms from either operating system.

Notes:

- Windows builds aren't code-signed yet, so SmartScreen warns on first run.
- Windows icon and version info are turned off (`application/modify_resources=false`) so
  building from Linux needs no extra tools.
- Game settings and saves are stored in `%APPDATA%\Godot\app_userdata\Barrels of Silver\` on
  Windows and `~/.local/share/godot/app_userdata/Barrels of Silver/` on Linux.

---

## 6. For developers

### Project layout

```
barrels-of-silver/
├── project.godot            Project settings (renderer, window, autoloads)
├── export_presets.cfg       Linux + Windows export settings
├── export.sh                Builds both platforms from the command line
├── CREDITS.md               Third-party notices (keep up to date!)
├── CLAUDE.md                Design decisions and dev notes
├── docs/
│   ├── ship-roster.md       Ship types, stats, rarity, fleet rules
│   └── famous-pirates.md    Historical pirates and their ships
├── scenes/
│   └── main.tscn            Entry scene (the world is built by main.gd)
├── scripts/
│   ├── main.gd              World setup, input map, enemy spawning, restart
│   ├── ocean.gd             Gerstner-wave ocean; get_height() matches the shader
│   ├── ship.gd              Buoyancy, sailing, guns and ammo, damage, sinking (takes no input)
│   ├── player_controller.gd Keyboard/mouse → ship; mouse-side aiming; firing arcs
│   ├── ai_captain.gd        Enemy AI: wind-aware circling, island avoidance, fleeing
│   ├── cannonball.gd        Projectile ballistics and hits
│   ├── fx.gd                Smoke, splashes, splinters, trails
│   ├── wind.gd              Global wind (autoload "Wind")
│   ├── camera_rig.gd        Map view + cruise view
│   └── hud.gd               Compass, readouts, damage bars, ammo
└── shaders/
    └── ocean.gdshader       Waves, ripples, foam
```

### Tuning

- **Ship handling:** the `@export` values at the top of `scripts/ship.gd`. Ships run at an
  exaggerated "game scale" speed. The HUD scales knots down so the numbers look realistic.
- **Guns and ammo:** the `AMMO` table and `reload_time` in `scripts/ship.gd`.
- **Sea state:** the `WAVES` table in `scripts/ocean.gd`. Keep total steepness under ~0.6.
- **Wind:** starting direction and gust range in `scripts/wind.gd`.
- **Camera:** the `@export` values in `scripts/camera_rig.gd`, for both map and cruise view.

### Conventions

- Compass bearing 0 = north = **−Z**; 90° = east = **+X**.
- `Wind.angle` is the bearing the wind blows **toward**.
- Broadside side +1 = starboard (local +X), −1 = port.

---

## Credits and legal

Built with [Godot Engine](https://godotengine.org) (MIT License). Every third-party notice is
listed in [CREDITS.md](CREDITS.md).

Barrels of Silver is an independent, original project inspired by classic age-of-sail games.
It is **not affiliated with or endorsed by** any other game's developer or publisher, and it
contains none of their assets.
