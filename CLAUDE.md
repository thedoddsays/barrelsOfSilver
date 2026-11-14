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
- `docs/gdd.md`: the game design document (skeleton v0, 2026-11-13). Follows the owner's 5-step
  process: vision, tools and why, proof of concept with a "what we tried" decision log, world,
  gameplay loop, systems. **Keep its decision log current** whenever an approach is replaced.
- `docs/ship-roster.md`: 20 ship types, stats, rig profiles, rarity, fleet, art scope (v3,
  owner decisions made 2026-11-12: sloop start, fleet of 3–4, all tiers in release 1).
- `docs/famous-pirates.md`: historical pirates and their unique ships at real sizes (v2: owner decisions recorded; legends, timeline and alliances still open).
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
  **Hull mask (2026-11-14):** `ocean.gd` passes every afloat ship (max 96) to the shader, which discards
  water inside the hull's plan outline above `Ship.water_mask_height()` (deck, or an open boat's floorboards),
  so crests shorter than a ship can't show through her deck. Sunk ships are left out so the sea closes over
  them. `Ocean.hull_mask_enabled` toggles it for debugging. Fixed owner-reported "water clipping through hulls in waves".
- `ship.gd`: RigidBody3D, 8 buoyancy probes, anisotropic hull drag (keel), wind thrust by
  point of sail (per-rig curve from the spec, all with a thrust floor head to wind), rudder bite scales with speed, heel
  torque, braced yards, furl/unfurl sails (W/S: furled / battle / full), wake particles.
  Uses Pirates!-style "game scale": top speed about 12 m/s; HUD knots × 0.5 so they read
  realistically. Ships without a model use placeholder primitives (see "Ship models" below).
- **Data-driven ships (2026-11-13):** `ShipSpec` resource (`scripts/ship_spec.gd`), data in `data/ships/*.tres`
  (sloop, brigantine, pirate_frigate so far, from docs/ship-roster.md). `Ship.spec` (default sloop) sets size,
  mass, hull, crew, guns (rows per gun deck), rig curve (`RIG_CURVES`: fore-and-aft / mixed / square) and masts
  ("square" yards or "gaff" boom sails, plus jib). All forces scale from the 16 m / 20 t sloop baseline by mass,
  inertia and speed_mult, so new ships need no hand-tuning. Set hull/crew overrides AFTER add_child (spec applies
  in _ready). New class_names need a rescan before headless `--script` runs: `godot --headless --path . --import`.
  Enemies spawn as a random type (50% sloop, 35% brigantine, 15% frigate). Ketch, schooner, brig, snow,
  barque, merchantman, East Indiaman, periagua and barco luengo specs (2026-11-14; sizes estimated, stats from the roster) are only in
  the N debug-escort cycle and the stress test so far. The pirate frigate's mizzen is now "spanker". The player's sloop is now a true
  fore-and-aft sloop: better upwind, a bit slower dead downwind than the old curve.
- `wind.gd` (autoload `Wind`): `angle` = bearing the wind blows TOWARD; drifts and gusts.
  Compass: bearing 0 = north = -Z, PI/2 = east = +X. Ship heading bearing = `-rotation.y`.
- `camera_rig.gd`: two blended views. **Map view**: narrow 28° lens (flat 2.5D look), 40–650 m,
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
  - Retest (2026-11-13): owner confirmed the new smoke makes cannonballs much easier to see. It reads
    as cartoonish, which is fine as a **placeholder**; the VFX pass must replace it with realistic smoke
    to fit the stylized-realism art direction. Aim arcs still flicker a little (much better than before);
    upwind is less punishing but not final. Owner: good enough for now, fine-tune both in a later
    tuning pass. Milestone 2 combat counts as working.
- **Collisions (2026-11-13):** ships collide physically with each other and with islands (static cylinders).
  `Ship._integrate_forces` reads contacts (`contact_monitor` on): ramming splits damage by how much each
  ship drove into the other (rammed ≈ 4 hull per m/s above 1.5 m/s, ×1.0 on a square side hit, ×0.5 end-on;
  rammer 0.8 per m/s; scaled by sqrt(mass ratio)), plus crew loss on the rammed ship. Islands: 1.5 per m/s.
  **Gotcha:** contacts arrive after the solver has resolved the crash, so impact speed must come from
  `pre_impact_velocity()` (velocity 2 ticks back), never the current velocity. **Gotcha 2:** don't use
  the contact normal either: on angled box-on-box hits it's often the rammer's own face, which made the
  rammer look rammed (owner playtest 2026-11-13). Roles come from each ship's speed toward the contact point. `impact(kind, closing, damage)`
  signal is the hook for sound/shake/HUD. The AI doesn't ram on purpose (yet).
- **Stress test (2026-11-13):** `scenes/debug/stress_test.tscn` (F6; `]`/`[` add/remove 5 AI pairs, `B` benchmark,
  `V` vsync; `-- --bench --quit` runs it from the command line). Extends main.gd (`island_count` is the hook).
  scenes/debug and scripts/debug are excluded from exports. Owner PC (RTX 4060, Ryzen 7 3700X): 20 AI ships
  236 FPS, 40 ships 110, 60 ships 55. Main costs: ~30 draw calls per placeholder ship (many primitives) and
  GDScript buoyancy/AI (~8 ms physics at 60 ships). Real merged models and distant-ship LOD are the levers.
  **With real models (2026-11-14, 1600x900 windowed; pass `--windowed --resolution 1600x900`, the window
  otherwise opens at the desktop size):** stress ships are now a random mix of all ten modelled types
  (`STRESS_MIX`; `-- --sloops` for sloops only). Mix: 20 ships 200 FPS, 40 ships 110, 60 ships 47 (1% low 29);
  ~19 draw calls per ship (big ships ~25: one per sail and yard). Sloops only: 20 ships 240, 40 ships 128,
  60 ships 57; ~13 per ship. Spars and flags cast no shadows (saved ~18% of draw calls). At 60 ships
  process + physics is ~24 ms of CPU, so GDScript per-ship work (buoyancy, AI, sail trim) is now the bigger cost.
- **Fleet prototype (2026-11-13):** `scripts/fleet.gd` (`Fleet`, cap 4 incl. flagship) owns the player's escorts.
  Ships have a `faction` (0 = player's fleet); cannonballs skip the shooter's faction (friendly fire off).
  Escorts run `AiCaptain` with `fleet` set: follow mode keeps loose stations (`Fleet.station_position`, laid
  out on a smoothed heading so turns don't whip the formation), never loops back when ahead of station,
  trims speed with `Ship.thrust_limit`, and brakes/steers around friends (look-ahead: predicted closest
  approach over 6 s, so heavy ships turn away early; tighter clearance in formation so stations don't
  fight the avoidance). In battle, escorts circle a shared target in separate range lanes.
  **Aggressors only (owner, 2026-11-13; no formation orders wanted):** escorts fight only ships on
  `Fleet.aggressors`: ships that hit or rammed any fleet ship (`Ship.attacked`), or that the PLAYER hit,
  rammed (`Ship.landed_hit`) or fired a broadside at (in the line of fire: ~28° of abeam plus the target's
  half-length, within 1.15 × ammo range). Escorts' own stray hits don't add aggressors, so passing or fleeing
  ships are left alone. `Fleet.engaged` = there are aggressors; the battle ends when none is afloat or after
  20 quiet seconds with none within 250 m of the flagship, and the list clears. Escorts only take aggressors
  within 250 m of the flagship, leashed to 300 m from it (with hysteresis). The list is the hook for
  reputation later (attacking a neutral). Escort status shows on the HUD and prints
  `[fleet] ...` lines to the Output panel. Enemies auto-target the nearest fleet ship. Fleet pace (off while
  engaged): flagship thrust capped to 80% of the slowest escort's
  progress on its heading (`potential_progress`, which counts tacking for rigs that can't point as high),
  and drops further (to 35%) while any escort is >20 m behind her station ("the fleet waits"); off during
  battle or with F ("break away"). N = debug add escort (stand-in for capture). Owner playtest 1
  (2026-11-13): escorts dropped out of view → tighter stations (rank 1 ≈ 35–45 m back, rear ≈ 65 m),
  the fleet-waits rule, and map zoom out to 650 m (tilt unchanged up to 400 m, haze held constant beyond).
  Headless: station error ~8–12 m (sloop/brigantine), ~15–19 m (frigate); 2 slow friendly bumps in 11 battles.
  - Godot on the dev box: `C:\Users\Stephen\Documents\Tools\Godot\Godot_v4.7.2-stable_win64.exe\` is a
    *folder*; the console exe is inside it.

## Open issues / feedback from last playtest
- ~~"Very pixelated" visuals~~: resolved. Owner confirmed (2026-11-12) the water looks much
  better after the ripples were reworked (now gradient noise; see the ocean notes above).
- ~~Speed was "super slow"~~: resolved. After the ~4× boost the owner confirmed (2026-11-12)
  it's "noticeably better, actually feels like it's moving". Treat current ship.gd values as
  the baseline feel.

- **Ship models (2026-11-13):** generated by Blender Python scripts, no hand modeling and no
  third-party assets. `tools/blender/build_ship.py` holds every modelled ship in its `SHIPS`
  table (sloop; ketch, schooner, brigantine, brig, snow; barque, merchantman, pirate frigate, East
  Indiaman: hull models 1–3). Three-masters get a raised quarterdeck (`qd`) and forecastle (`fc`) with
  red breasts, rails and ladders, a wheel instead of a tiller, great-cabin windows and wider gun spacing
  (`gun_span`); mizzen kind "spanker" = gaff sail + square topsail (full ship rig; barque mizzen is "gaff").
  **Small boats (2026-11-14):** periagua (12 m dugout, double-ended, 2 small gaff/sprit-like sails) and
  barco luengo (16 m, one "lateen": triangular sail under a 40° yard, swings and brails like a boom) are
  `open=True`: inner skin, floorboards (**kept 0.25 H above the waterline**: the ocean is one opaque
  surface, so anything inside an open hull below the water shows sea through it; owner spotted it), benches, thole pins, `oar_N` oarlock markers, swivel guns on posts
  (`gun_power` 0.3/0.35 scales shot damage, 1 gun a side). Rig OARED: `_efficiency` = max(sail curve,
  `Ship.OAR_POWER` 0.65), irons 0, so they row anywhere (HUD "Rowing"); W/S still sets effort. Oars are
  one MultiMesh (one draw call), sweeping while `_rowing`, held level otherwise. Sails don't receive
  shadows (thin curved canvas self-shadowed in jagged streaks); they still cast them.
  It lofts the hull from lines (keel, stem profile, sheer, sections; the sloop's lines scaled by
  each ship's L/B/H plus shape knobs: bow fullness, forefoot, transom, sheer), adds deck, bulwarks,
  guns, boat, masts (gaff, square, or a snow's "trysail" pole), bowsprit (jib-boom look from 20 m)
  and standing rigging (shrouds, ratlines, stays between masts), generates plank textures (numpy),
  and exports `assets/ships/<id>/<id>.glb`. **Its L/B/H, guns and mast kinds must match
  `data/ships/<id>.tres`.** Rebuild: `"C:\Program Files\Blender Foundation\Blender 5.3\blender.exe"
  --background --factory-startup --python tools/blender/build_ship.py -- <id|all|id1,id2> [preview_dir]`
  (preview_dir renders Workbench views), then `godot --headless --path . --import`. Godot unpacks
  the glb's textures next to it (`sloop_*.png`): commit them. `tools/` has a `.gdignore`.
  The script writes in Godot ship space (x starboard, y up, bow -Z) and converts to Blender Z-up.
  It must match ship.gd: deck y = 1.1, waterline about y = -0.42 (buoyancy puts each probe ~0.58 m
  under), bow z = -10, stern +6, mast z = -0.1 L.
  `ShipSpec.model` (optional PackedScene): Ship instances it and reads marker empties
  (`mast_N`, `mast_N_head` = gaff throat, `mast_N_top` = truck, `jib_tack`, `jib_head`, `flag`, `gun_N` = starboard
  muzzles bow to stern; guns fall back to the spec layout if the count is wrong). The
  `Topsides` material is a neutral texture tinted by `Ship.hull_color`. Sails, booms, gaffs, yards
  and the flag stay in code (they animate); sails are now curved patches (`Ship._sail_mesh`) for
  every ship: square sails hang from and furl up to their yard, the gaff sail's peaked gaff (0.65 × boom
  length, peaked 30°; owner: a boom-length gaff looked wrong) lowers onto the boom, the jib swings round its stay and slides down it; fore-and-aft canvas bellies to
  leeward. ~15 draw calls per modelled ship vs ~30 for placeholders. The scene's low sun leaves
  flat surfaces (the deck) greyish from above: a lighting-pass question, not a texture bug.

## Planned next steps
1. ~~Confirm sailing feel and visual quality on the owner's machine.~~ Done 2026-11-12.
2. ~~Broadside cannon combat vs. an AI ship (ammo types; sail/hull/crew damage).~~ Working, 2026-11-13;
   aim-arc flicker, upwind feel and smoke look go to a later tuning/VFX pass.
3. Make the world editable in the editor; real ship models (sloop 2026-11-13; ketch, schooner,
   brigantine, brig, snow, barque, merchantman, pirate frigate, East Indiaman, periagua, barco luengo
   2026-11-14). Still to model: fluyt, galleon, navy sloop-of-war, two- and three-deckers (ships of the line).
4. Ports (trade, tavern, governor/nation reputation), boarding duel minigame, light
   campaign (aging, fame, treasure hunts). Scope: one region, 6–8 ports.
