# Pirates Slice: context for Claude Code

## What this is
A smaller, shippable spiritual successor to **Sid Meier's Pirates! (2004)**: modern visuals,
same high top-down camera and "string of minigames on a world map" structure. It's also the
first playable piece of the owner's much bigger long-term game (Pirates! gameplay + AC: Black
Flag-style ship combat and looks), so systems built here should carry forward.

## Hard constraints
- **Engine:** Godot 4.7+, **GDScript** (standard build, not .NET). Forward+ renderer.
- **Platforms:** native **Linux (owner uses Linux Mint)** and **Windows 11**. Exports via
  `export_presets.cfg` / `export.sh`. Keep `application/modify_resources=false` on Windows so
  exports from Linux don't need rcedit/Wine.
- **May be sold on Steam later.** Use NO Firaxis/2K material: no assets, names ("Pirates!",
  "Sid Meier"), music, UI art or writing from the original. Mechanics-inspired only. Godot's
  MIT notice must ship in credits. Keep any modding of the original game completely separate.
- Owner tests on Windows 11 (and Mint). Ask them to paste errors from Godot's Output /
  Debugger panels.

## Current state (milestone 2 in progress: broadside combat vs. one AI ship)
- The world is **built in code at runtime** (`scripts/main.gd`), so the editor viewport of
  `main.tscn` is empty. Press F5 to see it. A planned improvement is making it visible/editable
  in the editor (`@tool` or real scenes).
- `ocean.gd` + `shaders/ocean.gdshader`: 4 Gerstner waves; CPU `get_height()` mirrors the
  shader so buoyancy matches visuals. The mesh follows the camera, snapped to the vertex grid.
  Ripples are directional sines (the earlier value noise looked blocky/pixelated) and fade
  with distance.
- `ship.gd`: RigidBody3D, 8 buoyancy probes, anisotropic hull drag (keel), wind thrust by
  point of sail (in irons < 40°, best on a broad reach), rudder bite scales with speed, heel
  torque, braced yards, furl/unfurl sails (W/S: furled / battle / full), wake particles.
  Uses Pirates!-style "game scale": top speed about 12 m/s; HUD knots × 0.5 so they read
  realistically. Ship visuals are placeholder primitives.
- `wind.gd` (autoload `Wind`): `angle` = bearing the wind blows TOWARD; drifts and gusts.
  Compass: bearing 0 = north = -Z, PI/2 = east = +X. Ship heading bearing = `-rotation.y`.
- `camera_rig.gd`: follow cam; zooming in lowers the pitch (-32°…-68°); Q/E or right-drag rotates.
- `hud.gd`: compass (wind and heading arrows), speed, sails, point of sail, controls.
- `main.gd`: input map in code, sky/fog/ACES/glow/SSAO, sun, 14 seeded islands with palms.

- **Combat (milestone 2, built 2026-11-12, not yet playtested by owner):**
  - `Ship` no longer reads input; controllers set `steer_input`, call `sail_up/down()`, `fire(side, ammo)`.
    Side +1 = starboard (local +X), -1 = port. `Ship.AMMO` table holds ballistics + damage.
  - `player_controller.gd`: left click fires the side facing the mouse (owner chose mouse
    over keys; Q/E stay camera rotate); 1/2/3 ammo; draws firing arcs (ImmediateMesh).
  - `ai_captain.gd`: circles target at 0.6 × ammo range, picks orbit side by readiness,
    wears ship instead of tacking, ray-based island avoidance, flees when losing badly.
  - `cannonball.gd` (manual ballistics; hit test via `Ship.contains_point`, islands via ray on
    `Ship.LAYER_WORLD`), `fx.gd` (one-shot CPUParticles3D). Main spawns one enemy at a time.
  - Headless soak test: AI closes from ~280 m and sinks a stationary player in ~2.5 min.
  - Testing tip: `--script` test harnesses must not reference project class_names by type
    (they compile before the `Wind` autoload exists); use untyped vars.

## Open issues / feedback from last playtest
- ~~"Very pixelated" visuals~~: resolved. Owner confirmed (2026-11-12) the water looks much
  better after the switch to sine ripples + distance fade.
- ~~Speed was "super slow"~~: resolved. After the ~4× boost the owner confirmed (2026-11-12)
  it's "noticeably better, actually feels like it's moving". Treat current ship.gd values as
  the baseline feel.

## Planned next steps
1. ~~Confirm sailing feel and visual quality on the owner's machine.~~ Done 2026-11-12.
2. Broadside cannon combat vs. an AI ship (ammo types; sail/hull/crew damage). Built; awaiting playtest.
3. Make the world editable in the editor; real ship models.
4. Ports (trade, tavern, governor/nation reputation), boarding duel minigame, light
   campaign (aging, fame, treasure hunts). Scope: one region, 6–8 ports.
