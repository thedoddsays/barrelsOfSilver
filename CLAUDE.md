# Barrels of Silver: context for Claude Code

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
  MIT notice must ship in credits. **Every third-party asset, font, sound or code snippet goes
  in `CREDITS.md` with its license. Only use code or assets with a confirmed permissive
  license (MIT/BSD/Apache/CC0/public domain/OFL); if you can't confirm the license, write
  it ourselves instead.** Owner requires unique assets (legal risk). Keep any modding of the original game completely separate.
- Owner tests on Windows 11 (and Mint). Ask them to paste errors from Godot's Output /
  Debugger panels.

## Art direction (owner decision, 2026-11-12)
- **Slightly stylized realism**: realistic lighting, materials and water motion, with simplified
  shapes, a cohesive palette and readable silhouettes. Think between Sea of Thieves and Black Flag;
  keep the warm, adventurous feel. Consistency beats raw fidelity.
- **High top-down "2.5D" camera** stays: a 3D world read from above at a fixed-feeling angle,
  where the map reads like a map and ships read like miniatures.
- Priority order for visual work: water, then lighting/post, then ship models and sails, then
  VFX, then islands.

## Design docs
- `docs/ship-roster.md`: 20 ship types, stats, rig profiles, rarity, fleet, art scope (v3,
  owner decisions made 2026-11-12: sloop start, fleet of 3–4, all tiers in release 1).
- `docs/famous-pirates.md`: historical pirates and their unique ships at real sizes (draft v1).
  Depict real pirates from the historical record only, never from modern media (AC4: Black Flag,
  Pirates of the Caribbean, Black Sails, Our Flag Means Death). Edward Kenway is Ubisoft's, never use.
- **Rule: every ship at sea can be captured and sailed by the player; no enemy-only ships.**
  Balance strong ships through their capture difficulty and costs (crew, upkeep, draft, navy
  attention), never by making them off-limits. Every tier, from a periagua to a 1st rate, is a
  real option, gated by rarity and difficulty. The era is loose (Caribbean, c. 1650–1800),
  not strict history.

## Current state (milestone 2 in progress: broadside combat vs. one AI ship)
- The world is **built in code at runtime** (`scripts/main.gd`), so the editor viewport of
  `main.tscn` is empty. Press F5 to see it. A planned improvement is making it visible/editable
  in the editor (`@tool` or real scenes).
- `ocean.gd` + `shaders/ocean.gdshader`: 4 Gerstner waves; CPU `get_height()` mirrors the
  shader so buoyancy matches visuals. The mesh follows the camera, snapped to the vertex grid.
  Ripples are 5 octaves of gradient noise with analytic derivatives (rotated, drifting, each
  fading by distance) modulated by large slow "wind patches". History: value noise looked
  blocky/pixelated; summed sines looked like a tiled image (owner, 2026-11-12). Avoid both.
  Integer hash, not sin() hash, so it stays stable at large world coordinates.
- `ship.gd`: RigidBody3D, 8 buoyancy probes, anisotropic hull drag (keel), wind thrust by
  point of sail (in irons < 40°, best on a broad reach), rudder bite scales with speed, heel
  torque, braced yards, furl/unfurl sails (W/S: furled / battle / full), wake particles.
  Uses Pirates!-style "game scale": top speed about 12 m/s; HUD knots × 0.5 so they read
  realistically. Ship visuals are placeholder primitives.
- `wind.gd` (autoload `Wind`): `angle` = bearing the wind blows TOWARD; drifts and gusts.
  Compass: bearing 0 = north = -Z, PI/2 = east = +X. Ship heading bearing = `-rotation.y`.
- `camera_rig.gd`: two blended views. **Map view**: narrow 28° lens (flat 2.5D look), 40–400 m,
  zooming in lowers the pitch (-32°…-68°); Q/E or right-drag rotates. **Cruise view** (C, inspired by
  Black Flag's "just sail" mode): low chase cam behind the ship following its heading, HUD and firing
  arcs fade out, fog thickens to hide the ocean mesh edge (~600 m). Wheel, right-drag, Q/E, click or C
  returns to map view (a click there doesn't fire). Rig drives fog density and sun shadow distance.
  `cruise_changed` signal is the hook for crew-shanty music: needs original/licensed recordings.
  Owner loved both views on first try (2026-11-12): treat the current camera values as the baseline.
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

- **Combat playtest 1 (2026-11-12):** owner said the AI was fine; the problems were look and feel. Fixed:
  - Particles were untextured quads ("big white squares"): `Fx.particle_quad()` now uses a soft radial
    texture. Cannonballs are drawn 2× larger (visual only) and leave a smoke trail (`Fx.ball_trail()`).
  - Aim arcs flickered: the side now has hysteresis near bow/stern, and shots no longer inherit ship velocity
    (arcs stay square to the hull; the AI leads using target velocity only). Arcs also get a filled zone on the water.
  - Upwind was too punishing: head to wind now gives 25–35% thrust (was 0 inside 40°), irons is <30°,
    and the rudder keeps 50% bite at zero speed (was 25%).
  - Godot on the dev box: `C:\Users\Stephen\Documents\Tools\Godot\Godot_v4.7.2-stable_win64.exe\` is a
    *folder*; the console exe is inside it.

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
