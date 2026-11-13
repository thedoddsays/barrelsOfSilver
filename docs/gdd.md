# Barrels of Silver: Game Design Document

Status: **skeleton, v0** (2026-11-13). Sections follow the owner's five-step production process
(GDD, proof of concept, design, gameplay loop, refinement). The order is a guide, not a rule:
steps can be reordered or overlap depending on time and need, as long as this doc keeps up.
Facts already decided or proven are filled in, with dates and commits as evidence.
Lines marked **Owner:** are open questions that only the owner can answer.

Keep this file current. When a decision changes, update it here and record the old choice in
the decision log (section 4) with the reason, so nobody re-tries a dead end.

Related docs: [ship-roster.md](ship-roster.md), [famous-pirates.md](famous-pirates.md),
[../CREDITS.md](../CREDITS.md), [../CLAUDE.md](../CLAUDE.md) (technical state).

---

## 1. Vision

### 1.1 Pitch
**Internal pitch (owner, 2026-11-13):** a spiritual successor to Sid Meier's Pirates!. Nobody else
made one, so the owner is making it to play it.

**Public pitch (store page):** **Owner:** to write later. It must not name Pirates! or Sid Meier
(trademarks). Describe the experience instead, e.g. "an open-sea pirate career told through
sailing, broadsides, boarding and port life on a living map". Get legal advice before any
public comparison.

### 1.2 What the player gets out of it
**Owner:** the fantasy and the feeling. What does a good session leave them with?

### 1.3 What the owner loved about the inspiration (2026-11-13)
- **Open gameplay.** Go anywhere, do anything, in any order.
- **Capturing ships** and building up your own fleet. Commanding that fleet was the heart of it.
- **Finding treasure.**
- **Fighting real historical pirates.**
- **A simple, fun core loop.**
- **An open-ended story** that stayed in the background (third in importance, behind the
  freedom and the fleet).

**What it lacked or got wrong (owner, 2026-11-13):** "Perfect for its time": the owner still
plays it. What we improve:
- **It's dated.** Modern visuals and feel (see 1.5).
- **The dance minigame was clunky.** We don't carry over a dance minigame. Any social activity
  in ports is designed fresh, or left out.
- **Boarding and fencing were too thin.** Our boarding and sword fighting must be more robust:
  a real system, not a single duel. Design in section 6.

### 1.4 Pillars
3–4 short rules that every feature must serve. A feature that serves none gets cut.
**Confirmed by the owner, 2026-11-13.**
1. **Your sea, your story.** No forced plot. The player decides what to do next; the story
   stays in the background.
2. **Captain and fleet grow together.** Every ship at sea can be captured, but a ship only
   performs as well as the captain commanding it. (Reworded 2026-11-13 from "Your fleet is
   your progress" after the captain-skill decision.)
3. **Simple to play, rich to master.** Each activity is quick to learn; depth comes from how
   they connect.
4. **Real history as a playground.** Real pirates to hunt, treasure to find, in a loosely
   historical Caribbean.

### 1.5 Feel and look
Decided (owner, 2026-11-12):
- **Slightly stylized realism.** Realistic lighting, materials and water motion, with simplified
  shapes, a cohesive palette and readable silhouettes. Warm and adventurous. Consistency beats
  raw fidelity.
- **High top-down "2.5D" camera.** The map reads like a map and ships read like miniatures.
  A low "cruise" view behind the ship is for just sailing.
- Visual priority: water, then lighting and post-processing, then ship models and sails, then
  effects, then islands.

### 1.6 Inspirations
Mechanics and feel only. No names, assets, music, UI art or writing from any of these.

| Inspiration | What we take from it |
|---|---|
| Sid Meier's Pirates! (2004) | Structure: a string of activities on a world map; high top-down camera; career arc |
| Assassin's Creed IV: Black Flag | Ship combat feel and look; the "just sail" cruise view |
| Sea of Thieves | Stylized end of the look: readable shapes, painterly water |
| *Owner:* others? | |

### 1.7 Long-term context
This game is the first playable piece of a bigger long-term game (Pirates!-style play with
Black Flag-style ship combat and looks). Systems built here should carry forward.
What the big game adds (owner, 2026-11-13):
- A bigger map and more regions.
- More eras.
- Walking around on foot.
- Deeper ship combat.
- Multiplayer.

What that means for systems built now (release 1 stays single-player, one region, one loose era):
- **Multiplayer** is the hardest to add later. Keep game rules separate from input and visuals:
  ships are driven by controllers that set inputs (already true: `PlayerController` and
  `AiCaptain` both drive `Ship` the same way), and game state should be plain data that could
  be saved or sent over a network. No multiplayer code yet.
  - **Owner is undecided on multiplayer (2026-11-13).** It's not why the owner plays, but people
    ask about it first, and "jump into a server and be the pirate armada" has a real draw.
    Options, cheapest first: (a) none; (b) **co-op**: 2–4 friends, one player hosts, friends
    captain the fleet's other ships (fits the fleet of 3–4); (c) dedicated servers and a
    persistent world (ongoing server costs, live-service work, a different game).
    Recommendation: release 1 stays single-player; after the core loop works, run a small
    co-op proof of concept (two physics ships staying in sync between two machines) and
    decide with that evidence.
- **Bigger map:** world data (ports, islands, nations) lives in data files, not hard-coded, so
  regions can be added. Plan for loading areas in and out (see section 5).
- **Eras:** ships, nations and pirates carry an era or date range as data, even if release 1
  ignores it.
- **On foot (owner, 2026-11-13):** ports and boarding are **3D spaces with a railroaded scope**.
  The captain is there in 3D but can only interact with a limited set of things, along guided
  paths. No free roaming in release 1. The big game can open these same spaces up for walking.
  Working interpretation (**Owner:** confirm): in a port, the player picks a place (dock, tavern,
  shipyard, merchant, governor) and the captain walks or the camera cuts there; each place opens
  its own screen. Boarding plays out on the actual 3D decks of the two ships, in a confined area.
- **Deeper ship combat:** the damage model (hull, sails, crew) and ammo table should be easy
  to extend.

---

## 2. Tools and technology

| Tool | Choice | Why |
|---|---|---|
| Engine | Godot 4.7+, standard build | **Licensing (owner, 2026-11-13):** MIT license, so the game can be built, published and sold with no royalties, revenue share or per-install fees. The only obligation is shipping Godot's license notice (see section 3). By comparison, Unreal takes a royalty on gross revenue past a threshold, and Unity's pricing has changed under developers before (the 2023 runtime-fee episode). Re-check competitors' current terms before quoting them in a meeting. |
| Language | GDScript | Godot's default and it does the job (owner, 2026-11-13). Switching to C# is possible if a real need appears (e.g. CPU-heavy simulation); decide then and log it in section 4. |
| Renderer | Forward+ (Vulkan / Direct3D 12) | Needed for the water, lighting and post-processing quality the art direction asks for |
| Platforms | Windows 11, Linux (Mint) | Owner's machines; possible Steam release |
| Exports | `export_presets.cfg`, `export.sh` | Windows icon editing off, so Linux can build Windows exports without Wine |
| Source control | Git, GitHub | |
| 3D models | Blender 5.x, driven by Python scripts in `tools/blender/` | Owner installed Blender (2026-11-13). Ships are generated from numbers (hull lines, deck layout, rig), so they're 100% original, match the physics dimensions exactly and can be rebuilt or re-proportioned in seconds; exported as .glb so the game never depends on Blender. An artist can later model over the same dimensions and marker points |
| **Owner:** audio, other tools | | |

### 2.1 Target hardware
Estimates only; not yet measured. Measure with an FPS counter on real machines before
publishing anything.
- **Minimum:** GTX 1050 / RX 560 class GPU, 4-core CPU, 8 GB RAM.
- **Recommended:** GTX 1660 / RTX 2060 class GPU, 6-core CPU, 16 GB RAM.
- Planned: a graphics settings menu (shadows, ambient occlusion, glow, render scale) to reach
  integrated graphics. The Compatibility renderer is a possible low-end fallback at a visual cost.

---

## 3. Legal and credits

- Every third-party asset, font, sound or code snippet goes in [CREDITS.md](../CREDITS.md) with
  its license. Only confirmed permissive licenses (MIT, BSD, Apache, CC0, public domain, OFL).
  If the license can't be confirmed, we write it ourselves.
- Godot is MIT: its notice must be findable in the shipped game (credits screen).
- No Firaxis/2K material of any kind. Mechanics-inspired only.
- Real historical pirates are depicted from the historical record only, never from modern media
  (Black Flag, Pirates of the Caribbean, Black Sails, Our Flag Means Death). Edward Kenway is
  Ubisoft's and is never used.

---

## 4. Proof of concept and decision log

### 4.1 Proof-of-concept checklist
| Question | Result | Evidence |
|---|---|---|
| Can we make water that looks like water? | Yes. Owner confirmed it looks good. | 7a840a4, 2026-11-12 |
| Can a "ship" (placeholder shapes with real buoyancy and weight) float? | Yes. 8 buoyancy probes follow the same wave math as the shader. | 46d042d |
| Can it sail across the water with wind? | Yes. Points of sail, tacking, sail settings. Owner confirmed the feel. | 46d042d, 2026-11-12 |
| How does it react to waves? | Pitches, rolls and heels with the waves and wind. | 46d042d |
| Can two ships fight? | Yes. Broadsides, 3 ammo types, AI captain. Owner: working. | 75f3aaf, 2026-11-13 |
| Ship vs. island and ship collisions? | Yes. Ships collide solidly with each other and with islands, with no tunnelling or launching. **Ramming:** the rammed ship takes heavy hull and some crew damage, the rammer a little (about 5:1); a 10 m/s ram into a ship's side costs about a third of the target's hull. Head-on hits damage both equally. Islands do modest damage. Slow nudges (under 1.5 m/s) do nothing. Rocks/reefs don't exist yet. | Headless scenario tests, 2026-11-13 |
| Can the renderer handle many ships? | Yes, with headroom. On the owner's PC (RTX 4060, Ryzen 7 3700X, 1600×900, vsync off): 0 AI ships 436 FPS, 10 ships 396, 20 ships 236, 40 ships 110, 60 ships 55 (all fighting on screen, 40 islands). Cost grows about 30 draw calls per ship because placeholder ships are ~30 separate shapes; real models should cut that a lot. Large-map streaming is still untested. | `scenes/debug/stress_test.tscn`, 2026-11-13 |

### 4.2 What we tried and why we changed it
| Area | Tried | What went wrong | Now | Evidence |
|---|---|---|---|---|
| Water ripples | Value noise | Looked blocky and pixelated (owner) | Replaced | 2026-11-12 |
| Water ripples | Summed sine waves | Looked like a tiled, repeating image (owner) | Gradient noise, 5 octaves, with slow wind patches | 7a840a4 |
| Noise hash | `sin()`-based hash | Breaks down at large world coordinates | Integer hash | 7a840a4 |
| Noise hash | Constants from a snippet | License couldn't be confirmed | MurmurHash3 finalizer (public domain) | 1bcc16f |
| Ship speed | Realistic speeds | "Super slow" (owner) | ~4× "game scale", HUD knots × 0.5 so numbers read realistically | 2026-11-12 |
| Particles | Untextured squares | "Big white squares" (owner) | Soft round texture. Placeholder: reads cartoonish, needs realistic smoke | 34fa4ff |
| Aiming | Shots inherit ship velocity | Firing arcs skewed and flickered | Shots fire square to the hull; side switch has hysteresis. Slight flicker remains (tuning pass) | 34fa4ff |
| Upwind sailing | Zero thrust within 40° of the wind | Too punishing | 25–35% thrust head to wind; irons under 30°. Still to tune | 34fa4ff |
| Firing controls | Keys vs. mouse | Owner choice | Left click fires the side facing the mouse | 75f3aaf |
| Collision damage | Measuring impact speed from the ships' velocity when the contact is reported | Godot reports contacts *after* resolving the crash, so speeds were already cancelled: rams read half speed, islands read zero, and who-rammed-whom came out wrong | Measure from each ship's velocity a couple of physics ticks earlier | 2026-11-13 |
| Fleet formation | Wide stations (rear escort ~90 m astern), flagship capped to 90% of the slowest escort, max zoom 400 m | Owner playtest: slower escorts dropped out of the camera view, and the camera couldn't zoom out far enough | Tighter stations (rear ~65 m), 80% pace, the fleet waits for anyone >20 m behind station, pace counts tacking upwind, zoom out to 650 m | 2026-11-13 |
| Fleet collisions | Distance-only friend avoidance | Escorts fought their own stations (stations sat inside the avoid radius), and the heavy frigate rammed friends mid-battle | Look-ahead (predicted closest approach over 6 s), tighter clearance in formation, separate combat lanes per escort | 2026-11-13 |
| Ship visuals | Primitives (boxes, prisms, cylinders) built at runtime, ~30 draw calls per ship | Placeholder look; draw calls were the main render cost in the stress test | Script-generated Blender model per hull (sloop first), animated sails still built in code as curved canvas; ~15 draw calls per ship | 2026-11-13 |
| Fleet targeting | Once a battle started, escorts fought any non-fleet ship within 250 m of the flagship | Owner: a passing trader or a ship trying to flee shouldn't be attacked just for being near a fight | Escorts fight only aggressors: ships that attacked the fleet or that the player attacked | 2026-11-13 |
| Collision damage | Deciding who rammed whom from the contact surface's direction | Owner playtest: the rammer took more damage than the target. On angled hits Godot often reports the rammer's own bow or side face, so the target's speed looked like it was driving into the rammer | Judge each ship by its speed toward the point of contact; rammer now takes about 1/5 of what the target takes in live fights too | 2026-11-13 |

---

## 5. World design and technical limits (step 3)

Known:
- Scope: **one region, 6–8 ports.** Caribbean, loosely c. 1650–1800.
- Currently 14 randomly placed islands; the world is built in code at runtime.
- The ocean mesh follows the camera; fog hides its edge (~600 m) in the cruise view.

**Owner:**
- How big is the map, in real distance or sailing time from one end to the other?
- Which ports and towns, which nations own them, and where are they?
- Hand-built map or generated?
- What do ships look like at release (8 hull models per the roster)?

To test (technical):
- How many ships and islands can be on screen at 60 fps on the recommended hardware? Measured on the
  owner's PC (above recommended): about 60 fighting ships at 55 FPS, 40 at 110 FPS. Islands are cheap.
  Still to measure: the Mint machine and a recommended-spec (GTX 1660 / RTX 2060) machine.
- How far can the player see, and what does streaming or culling of distant areas look like?

---

## 6. Gameplay loop (step 4)

Known:
- Start in a sloop (optional hard start in a periagua). Every ship at sea can be captured.
- Fleet of 3–4 ships: you sail the flagship, the others follow and fight under AI. See 6.1.
- Broadside combat: fire the side facing the mouse; round, chain and grape shot.
- **Owner wants in release 1 (2026-11-13):** character creation, alignment with nations, and a
  fair amount of ship customization. Details below are still open.

**Owner:**
- What does the player do minute to minute, and in a typical hour?
- **Captain and ship go hand in glove (owner, 2026-11-13).** A powerful ship under a green
  captain performs like it: the ship only performs as well as its captain can handle it. This
  is another soft gate that fits the roster rule (any ship can be taken, none are off-limits):
  a rookie *can* capture and sail a 1st rate, just badly.
  Working proposal (**Owner:** confirm or change):
  - The captain has a few skills, e.g. **seamanship** (turning, sail handling), **gunnery**
    (reload speed, accuracy), **command** (crew morale, boarding) and **navigation**.
  - Each ship type has a handling demand that rises with size and rig complexity (see
    ship-roster.md).
  - When skill is below a ship's demand, performance drops gradually (slower turns, sail
    changes and reloads, shakier morale). It never locks the player out.
  - Fleet ships are captained by hired officers whose skills apply the same way.
- Character creation: what choices (name, look, nationality, background, starting skills)?
- **How the captain improves (owner, 2026-11-13): all three, working together.**
  - **Levels, earned by doing.** Sailing, fighting, trading and the like earn experience; the
    captain levels up over time and gets better at commanding any ship.
  - **Hired officers lighten the load.** Good people (e.g. a sailing master, gunner, quartermaster)
    cover part of the gap between the captain's skill and the ship's demand, so a weaker captain
    can still run a strong ship well with the right crew.
  - **General XP with point-buy (owner, 2026-11-13).** Every activity earns the same general
    experience. Each level gives points the player spends on whichever skills they choose.
  - Open: how much can officers cover: part of the gap, or all of it?
- Boarding: what does it look like and how is it won?
- Ship customization ("a fair amount"): cosmetic (paint, sails, flag, figurehead), functional
  (guns, hull, rigging, crew quarters), or both? Bought, built or captured?
- Nation alignment: pick one at creation, earn it through play, or both? Can the player
  switch sides or sail for none?
- What else happens at sea or ashore (treasure hunts, rescues, missions)?
- How does a career end (aging, retirement, score)?
- **Capturing ships is its own design pass (owner, 2026-11-13).** It will be "a rather robust
  endeavor", so it is not prototyped yet. Fleet management is designed first (6.1).

### 6.1 Fleet management
Already decided (2026-11-12): the player sails the flagship directly,
the other ships fight on their own under AI; the flagship can be switched outside combat only.

**Decided (owner, 2026-11-13):**
- **Fleet speed: soft cap with leave-behind.** While the fleet sails together, the flagship is
  held to the slowest ship's top speed (the HUD shows "fleet pace"). A fleet order lets the
  player break away at full speed; the others follow as best they can and catch up when the
  player slows or stops.
- **Friendly fire: off.** The player's cannonballs pass through their own fleet and vice versa.
  (Today's code hits any ship except the shooter; ships need a side/faction first.)
- **Crew: auto-split with manual override.** Crew is distributed automatically (each ship's
  minimum first, then by size and role), and the player can move men between ships.
  Taking a prize draws a prize crew from the fleet.
- **Over the cap: strip-and-scuttle, or harbor storage.** With a full fleet, a new prize can be
  plundered of cargo (and guns) and scuttled, or extra ships can be moored at a friendly port
  and swapped there later. Harbor storage depends on the port system. The cap doesn't grow
  with level or fame.
- **Fleet cap: 4 ships including the flagship** (owner, 2026-11-13; can be revisited).
- **Formation: loose.** Escorts keep loose stations around and behind the flagship, spaced by
  size, never ram a friend, and steer around islands.
- **Escorts fight aggressors only (owner, 2026-11-13).** No formation or combat orders:
  escorts leave every ship alone unless it is an aggressor, so they never chase ships
  passing by or trying to flee. An aggressor is a ship that fired on or rammed any ship
  of the fleet, or one the player hit, rammed or fired a broadside at. Escorts' own stray
  shots don't count. The battle ends when no aggressor is afloat, or after 20 quiet
  seconds with none within 250 m of the flagship. Escorts never stray more than 300 m
  from the flagship. Later, attacking a neutral should cost reputation with its nation.
- **Merchant prizes join the fleet only if the player chooses.** Once in the fleet they are
  treated like any other ship in battle (no special hang-back behaviour).

**Prototype built (2026-11-13), awaiting owner playtest.** Loose formation, fleet pace (soft
cap, lifted in battle or with F to break away), friendly fire off, escorts fight enemies near
the fleet and return to formation after. N adds a debug escort until capture exists. Fleet pace
counts tacking: a square-rigger that can't point as high as the flagship slows the fleet upwind.

**Proposed, owner to confirm:**
- **Formation orders:** line astern and line abreast as alternatives to the loose default.
- **Battle orders (later):** "attack my target", "hold back", "free hunt".
- **Cargo:** one combined fleet hold for trading, but each ship carries its own share, so a
  sunk ship takes her cargo down with her.
- **Officers:** each escort needs an officer as captain (ties into captain skill: the officer's
  skill sets how well that ship performs). Hiring officers becomes part of growing a fleet.
- **Losing an escort:** she sinks with her cargo and most of her crew; survivors in boats can
  be picked up.
- **Switching flagship:** in port it's instant; at sea the captain takes a boat across, which
  takes a few seconds.
- **Fleet panel (UI):** each ship's hull, sails, crew and current order; click a ship to centre
  the camera on her.

---

## 7. Refinement: world systems and economy (step 5)

**Owner:**
- How does the player interact with ports (trade, tavern, shipyard, governor)?
- How does the mercantile economy work: goods, prices, supply and demand?
- What do other ships do on their own (trade routes, patrols, other pirates)?
- How robust is the world without the player: does it change while they're away?
- Nations and reputation: wars, letters of marque, bounties?
- Upgrades: bought, built or both? How are they afforded?

---

## 8. Scope

| | Release 1 | Long-term game |
|---|---|---|
| Ships | All 20 types, 8 hull models | |
| Map | One region, 6–8 ports | **Owner** |
| **Owner:** more rows | | |

**Out of scope for release 1:** **Owner**
