# Pirates Slice

Top-down age-of-sail prototype in Godot 4.7+. Milestone 1: a modern-looking ocean and one
ship that sails by the wind. Builds natively for **Linux (Mint)** and **Windows 11**.

## Run it (Linux Mint)

1. Download Godot 4.7.x (standard build, not .NET) from godotengine.org, unzip, `chmod +x` it.
2. Make sure Vulkan works: `sudo apt install vulkan-tools && vulkaninfo --summary`.
   NVIDIA: use the proprietary driver from Driver Manager. AMD/Intel: Mesa is fine.
3. Open Godot → Import → pick `project.godot` → press F5.

No Vulkan? Run with `--rendering-driver opengl3` (it will look simpler).

## Run it (Windows 11)

1. Update your GPU driver (NVIDIA app / AMD Adrenalin / Intel Driver & Support Assistant).
   Godot uses Direct3D 12 or Vulkan, so an old driver is the most common cause of a crash on launch.
2. Download **Godot 4.7.x – Windows, standard build** (not .NET) from godotengine.org.
   It's a zip with no installer: extract it somewhere permanent, e.g. `C:\Tools\Godot\`.
   Optional: right-click the `.exe` → *Show more options* → *Send to → Desktop (create shortcut)*.
3. Extract `pirates_slice.zip` somewhere **outside OneDrive-synced folders** (e.g. `C:\Dev\pirates_slice`).
   OneDrive locks files while Godot is writing its `.godot` cache and can cause odd import errors.
4. Launch Godot → **Import** → browse to `pirates_slice\project.godot` → **Import & Edit** → press **F5**.

If Windows Defender SmartScreen flags Godot or an exported game: *More info → Run anyway*.
If the window opens black or crashes, start Godot from a terminal with
`Godot_v4.7.2-stable_win64.exe --rendering-driver vulkan` (or `opengl3` as a last resort).

### Playing an exported build on Windows

Copy `build\windows\PiratesSlice.exe` anywhere (USB stick, another PC) and double-click it. It's a
single self-contained file with nothing to install. Settings and saves will live in
`%APPDATA%\Godot\app_userdata\Pirates Slice\`.

### Building on Windows instead of Mint

Same as Linux: install export templates once (*Editor → Manage Export Templates → Download and Install*),
then *Project → Export → Windows Desktop → Export Project*. You can export the Linux build from Windows too.

## Controls

| Key | Action |
|---|---|
| A / D | Steer |
| W / S | More / less sail (furled → battle sails → full) |
| Q / E, right-drag | Rotate camera |
| Mouse wheel | Zoom (closer = lower, more cinematic angle) |
| F11 / Esc | Fullscreen / quit |

You can't sail within ~40° of the wind. A broad reach is fastest. The blue compass
arrow shows where the wind is blowing toward; the orange one is your heading.

## Build native releases

One time: in the editor, **Editor → Manage Export Templates → Download and Install**.

- From Mint, both platforms: `./export.sh` (set `GODOT=/path/to/godot` if it isn't on PATH).
- Or in the editor: **Project → Export**, pick "Linux" or "Windows Desktop", then Export Project.

Output: `build/linux/PiratesSlice.x86_64` and `build/windows/PiratesSlice.exe`, each a single
self-contained file. Windows SmartScreen will warn about the unsigned .exe ("More info → Run
anyway"); code signing can come later. The Windows icon/version info is off
(`application/modify_resources=false`) so exporting from Linux doesn't need rcedit/Wine.

## Layout

- `scripts/main.gd`: builds the world (sky, sun, ocean, islands, ship, camera, HUD)
- `scripts/ocean.gd` + `shaders/ocean.gdshader`: Gerstner waves; CPU height matches GPU
- `scripts/ship.gd`: buoyancy probes, hull drag, wind thrust by point of sail, rudder, heel
- `scripts/wind.gd`: global wind (autoload), drifts and gusts
- `scripts/camera_rig.gd`, `scripts/hud.gd`

## Tuning

Ship feel is in the `@export` values at the top of `ship.gd`. Sea state is the `WAVES`
table in `ocean.gd`. Bigger steepness and wavelength make rougher seas; keep total steepness under ~0.6.
