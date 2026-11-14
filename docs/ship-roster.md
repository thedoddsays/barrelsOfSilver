# Ship roster (v3)

Status: **owner decisions made**, 2026-11-12. Stats are first-pass numbers to be tuned in
play. Nothing here is built yet except the placeholder ship, whose numbers are the
baseline everything else is measured against.

## Decisions (owner, 2026-11-12)
- **Start:** a sloop by default, with an optional harder start in a periagua.
- **Fleet:** the player commands a small fleet (cap of 3–4 ships). The flagship is sailed
  directly, captured ships follow, and the slowest ship sets the fleet's speed. In battle,
  the other fleet ships fight on their own under AI control. The flagship can be switched
  outside combat only.
- **Release 1 includes every tier**, up to the 1st rate. That means all 20 ships and 8 hull models.
- **Ketch and snow added** to the roster.

## Design rules (owner)
1. **Every ship that appears at sea can be captured and sailed by the player.** There are
   no enemy-only ships.
2. **Every tier is a real option**, from a periagua to a 100-gun 1st rate. The gates are
   **rarity** and **difficulty**, never "off-limits". Strong ships are balanced by what they
   cost to capture and to keep: crew, upkeep, draft, speed and navy attention.
3. **The era is a loose backdrop, not a constraint.** The flavor is Caribbean age of sail,
   roughly 1650–1800. Ships from across that span sit side by side when they're fun.

All ship types are historical and generic, so none of them is anyone's intellectual property.

## Rarity
| Rarity | How often you meet one | Ships |
|---|---|---|
| **Common** | Every voyage | Sloop, ketch, merchantman, fluyt, barco luengo, periagua |
| **Uncommon** | Most cruises | Brigantine, brig, snow, barque, navy sloop-of-war, pirate frigate |
| **Rare** | A few times a campaign | Schooner, galleon, East Indiaman, 4th rate |
| **Very rare** | Wartime or high navy attention only | 3rd rate |
| **Legendary** | Once or twice a campaign, as a squadron flagship | 2nd rate, 1st rate |

## How ships differ (the levers)
Every ship is a set of numbers on the same `Ship` class plus a model. The tradeoffs that
make choosing a ship interesting:

| Lever | What it changes in play |
|---|---|
| **Rig** | Which points of sail are fast (see rig profiles). Upwind vs. downwind character. |
| **Speed** | Top speed relative to the baseline sloop (12 m/s game scale). |
| **Turn** | Rudder authority and how quickly she comes about. |
| **Guns per side** | Broadside weight. Also sets the spread of the firing arcs along the hull. |
| **Crew** | Reload speed, sail handling, boarding strength. Bigger crews cost more upkeep and grumble sooner. |
| **Hull** | Hit points; bigger ships take a beating. |
| **Cargo** | Plunder and trade-goods capacity. |
| **Draft** | Shallow ships cross reefs and shoals that deep ships can't, which makes reefs an escape route. |
| **Oars** | Moves with no wind at all (slowly, tiring the crew). |

## Rig profiles (sailing curves)
These plug into `Ship._efficiency()`. Each ship picks one. All of them keep the arcade
floor from playtest 1, so pointing straight into the wind is slow but never a dead stop.

| Rig | No-go zone | Close-hauled | Beam reach | Broad reach | Running | Character |
|---|---|---|---|---|---|---|
| **Fore-and-aft** (sloop, schooner, ketch) | < 25° | 0.75 | 1.0 | 0.95 | 0.8 | Points high, best upwind; only average dead downwind. |
| **Mixed** (brigantine, barque, sloop-of-war) | < 30° | 0.6 | 0.9 | 1.0 | 0.9 | All-rounder. *The current curve in `ship.gd` is roughly this.* |
| **Square** (brig, snow, frigate, galleon, merchants, ships of the line) | < 35° | 0.45 | 0.8 | 1.0 | 0.95 | Great downwind, sluggish upwind. Big ships want the trade winds behind them. |
| **Oared** (periagua, barco luengo) | – | flat 0.5 | flat 0.5 | – | – | Rows at about half speed in any direction or calm; its small sail adds speed off the wind. |

## The roster

Speed and turn are multipliers on the baseline sloop. Hull 100 equals the current
placeholder. Cargo is in tons.

### Light
| Ship | Rig | Guns/side | Crew | Hull | Cargo | Speed | Turn | Draft |
|---|---|---|---|---|---|---|---|---|
| **Periagua** | Oared + small sail | 0 (1 swivel) | 30 | 25 | 5 | 0.7 | 1.3 | Very shallow |
| **Barco luengo** | Oared + lateen | 2 swivels | 40 | 40 | 10 | 0.85 | 1.2 | Very shallow |
| **Sloop** | Fore-and-aft, 1 mast | 5 | 80 | 100 | 40 | 1.00 | 1.00 | Shallow |
| **Ketch** | Fore-and-aft, 2 masts (short mizzen) | 4 | 50 | 90 | 80 | 0.92 | 0.95 | Shallow |
| **Schooner** | Fore-and-aft, 2 masts | 5 | 70 | 90 | 60 | 1.05 | 0.95 | Shallow |

- **Periagua:** a large dugout canoe the early buccaneers raided with. It can't win a ship
  fight, but it's great for sneaking into bays and running landing raids. It could serve
  as a hard-mode start.
- **Barco luengo:** the Spanish coast guard's (*guarda costa*) oared craft. Early on they
  swarm you in shallows and calms. Captured, one makes a fast raider that rows through
  dead calms and slips into lagoons nothing else can reach. It's a natural second ship
  for a raiding fleet.
- **Sloop:** the classic pirate ship and the default start. It's the fastest, the most
  agile and slips over reefs. The current placeholder is two-masted and square-rigged,
  which actually makes it a small brigantine. **The first real model should be a proper
  one-mast fore-and-aft sloop.**
- **Ketch:** a sturdy coastal trader with a tall mainmast and a short mizzen behind it.
  It's a little slower than a sloop, but it doubles the sloop's hold with a smaller crew,
  so it's a good cheap cargo hauler for a young fleet. *Idea for later:* a **bomb ketch**
  variant carrying a mortar for shelling forts.
- **Schooner:** best upwind and fastest of all, but lightly built. It's a rare find and
  a prized scout.

### Medium
| Ship | Rig | Guns/side | Crew | Hull | Cargo | Speed | Turn | Draft |
|---|---|---|---|---|---|---|---|---|
| **Brigantine** | Mixed, 2 masts | 7 | 110 | 150 | 100 | 0.95 | 0.85 | Medium |
| **Brig** | Square, 2 masts | 8 | 100 | 140 | 90 | 0.98 | 0.85 | Medium |
| **Snow** | Square, 2 masts + trysail mast | 8 | 100 | 150 | 120 | 0.96 | 0.83 | Medium |
| **Navy sloop-of-war** | Mixed, 2–3 masts | 7 | 120 | 160 | 80 | 1.00 | 0.95 | Medium |

- **Brigantine:** the step up from a sloop: more guns, crew and cargo for longer cruises,
  at a small cost in speed and agility. It's a common pirate upgrade.
- **Brig:** the brigantine's all-square-rigged cousin. It's quicker downwind and a little
  harder-hitting, but weaker upwind. The two give you a real choice at the same tier.
- **Snow:** the largest two-master: a brig with a small extra mast just behind the
  mainmast for a big fore-and-aft sail. It's slightly sturdier and roomier than a brig and
  a touch slower. It's the merchant-minded choice at this tier, and navies used them as
  cruisers too.
- **Navy sloop-of-war:** a purpose-built pirate hunter, as fast as a sloop with a
  brigantine's punch. It's the best fighting ship in its class, but it carries less
  cargo. Flying a stolen navy ship draws the navy's anger: that nation's warships pursue
  you more often while you keep her.

### Heavy
| Ship | Rig | Guns/side | Crew | Hull | Cargo | Speed | Turn | Draft |
|---|---|---|---|---|---|---|---|---|
| **Pirate frigate** | Square, 3 masts | 16 | 220 | 300 | 160 | 0.90 | 0.65 | Deep |
| **Galleon** | Square, 3–4 masts | 20 | 300 | 420 | 500 | 0.70 | 0.45 | Deep |

- **Pirate frigate:** a captured merchant or warship re-armed for piracy, as with the
  *Queen Anne's Revenge* or the *Royal Fortune*. It's the practical endgame flagship: fast
  for its size with a crushing broadside, but its deep draft shuts off reef escapes and
  its crew costs a fortune.
- **Galleon:** a treasure ship. It's slow, clumsy and hungry for crew, and is often worth
  more as a prize than as a ship to sail, but its hold is enormous.

### Ships of the line (the navy's battle fleet)
| Ship | Decks | Guns/side | Crew | Hull | Cargo | Speed | Turn | Draft |
|---|---|---|---|---|---|---|---|---|
| **4th rate** (~50 guns) | 2 | 25 | 350 | 600 | 150 | 0.75 | 0.45 | Very deep |
| **3rd rate** (~74 guns) | 2 | 37 | 550 | 1000 | 200 | 0.72 | 0.40 | Very deep |
| **2nd rate** (~90 guns) | 3 | 45 | 750 | 1400 | 250 | 0.65 | 0.35 | Very deep |
| **1st rate** (~100 guns) | 3 | 50 | 850 | 1700 | 300 | 0.62 | 0.30 | Very deep |

- **4th rate:** a navy station ship and the first ship-of-the-line most captains meet. It
  plays as a boss fight early on, where reefs and upwind escapes are the counterplay.
- **3rd rate:** the workhorse of the battle line. It appears as a squadron flagship in
  wartime or when a nation hunts you hard.
- **2nd and 1st rates:** floating fortresses. Each one is a legendary event, met once or
  twice in a campaign. Taking one practically needs a whole fleet: batter her crew down
  with grapeshot from several ships, then board with your combined crews.
- **Owning one** makes you nearly unsinkable, but it's the slowest, clumsiest, deepest
  thing afloat. It can only run downwind in deep water, its wages bankrupt most captains,
  and every navy in the region makes you their top target while you sail her. It's the
  ultimate trophy, not a practical cruiser.

### Merchant prizes
| Ship | Rig | Guns/side | Crew | Hull | Cargo | Speed | Turn | Draft |
|---|---|---|---|---|---|---|---|---|
| **Fluyt** | Square, 3 masts | 4 | 30 | 140 | 300 | 0.80 | 0.65 | Medium |
| **Merchantman** | Square, 3 masts | 8 | 60 | 180 | 220 | 0.85 | 0.70 | Deep |
| **Barque** | Mixed, 3 masts | 6 | 50 | 170 | 280 | 0.85 | 0.70 | Medium |
| **East Indiaman** | Square, 3 masts | 16 | 140 | 350 | 450 | 0.75 | 0.50 | Deep |

- **Fluyt:** the Dutch bulk carrier. It holds a huge cargo, carries a tiny crew and is barely
  armed, which made it the bread-and-butter prize.
- **Merchantman:** the generic armed trader. It fights back a little.
- **Barque:** square sails on the fore and main masts, a fore-and-aft sail on the mizzen.
  A small crew handles a big hold, and she sails better upwind than other merchants.
  It's a good ship for a captain who trades as much as they raid.
- **East Indiaman:** the richest prize at sea, armed almost like a frigate. It should be a
  rare event in the Caribbean, worth a story.

Ship's boats (longboat, pinnace) aren't ships in the roster. They appear in landings,
boarding scenes and treasure hunts.

## Progression sketch
- **Start** in a sloop (or a periagua on a hard start).
- **Get ships by capturing them** in boarding fights. Ports might also sell small craft.
  Capturing is the main loop: it's how you upgrade, and prizes double as cargo and money.
- **Fleet (decided):** a small fleet (cap of 3–4 ships) where the slowest ship sets the
  fleet's speed. This makes a galleon or a ship of the line a real burden and keeps the
  sloop relevant all game. The fleet is also what makes the big rates capturable: escorts
  add their guns and crews to the fight.
  - **In battle (decided):** the player commands their flagship directly. Every other ship
    in the fleet fights on its own under AI control (`AiCaptain`), alongside the player.
  - **Switching ships (decided):** the player can change which ship is the flagship
    outside combat (at sea or in port), but not during a battle.
- **Upkeep:** crew wages and repairs scale with ship size, so bigger isn't automatically
  better.
- **Attention:** stolen navy ships (the sloop-of-war and all the rates) raise how hard
  their nation hunts you. Bigger ships raise it more. This is the main brake on simply
  keeping the strongest ship.

## Release-1 art scope
Each hull needs a model. Reuse hulls to keep it shippable:

| Hull model | Ships it covers (paint, flags and rig details vary) |
|---|---|
| 1. Sloop | Sloop, navy sloop-of-war (larger variant) |
| 2. Two-master | Brigantine, brig, snow, schooner, ketch (re-rigged variants) |
| 3. Three-masted ship | Merchantman, barque, pirate frigate, East Indiaman (scaled and re-rigged) |
| 4. Fluyt | Fluyt |
| 5. Galleon | Galleon |
| 6. Two-decker | 4th rate, 3rd rate (scaled and more ornate) |
| 7. Three-decker | 2nd rate, 1st rate |
| 8. Small craft | Periagua, barco luengo |

That gives **8 models for 20 ships, all of them sailable, all in release 1**.

**All 19 ship types are built (2026-11-14)**, every hull family above, generated by
`tools/blender/build_ship.py` (ids: periagua, barco_luengo, sloop, ketch, schooner, brigantine, brig,
snow, navy_sloop, barque, merchantman, fluyt, pirate_frigate, east_indiaman, galleon, fourth_rate,
third_rate, second_rate, first_rate). The two small boats are open (no deck) with animated oars: they row
at 65% thrust on any heading, even dead upwind, and their swivel guns hit for about a third of a
cannon (`gun_power`). Their swivels are one per side for now. Each ship gets its own exported model from
the same generator, with its own proportions and masts, so the reuse is in the build script
and the game still draws one merged mesh per ship.
- **Navy sloop-of-war** (28 m): a small ship-rigged hull (square, square, gaff mizzen: mixed rig).
- **Fluyt** (32 m): pear-shaped sections (`tumble`, `sec_k`), narrow high stern.
- **Galleon** (42 m): two gun decks, quarterdeck plus poop (`poop`), high forecastle, beakhead
  (`beak`), lateen mizzen and bonaventure (four masts).
- **Rates**: 4th (45 m) and 3rd (52 m) are two-deckers, 2nd (54 m) and 1st (58 m) three-deckers
  (`decks`). Lower decks have lidded ports between black wales in navy ochre (`navy`), plus stern
  galleries; ships over 41 m also set topgallants.
Sizes are estimates from typical period ships; change them in the script and the spec together.
Masses follow the existing ships (about 0.1235 t per m³ of L × B × H in game tonnes).

**The rigging needs to be modular.** Five ships share the two-master hull, with three
different rigs between them (fore-and-aft, square and mixed). Build masts, yards, gaffs
and booms as parts that a `ShipSpec` assembles, not as part of each hull model.

## Technical notes for when we build it
- **Done (2026-11-13):** each ship type is a `ShipSpec` resource in `data/ships/` (sloop,
  brigantine and pirate frigate so far). `Ship` builds its size, physics, guns, rig and
  placeholder visuals from it. Adding a ship is a new `.tres` file with the numbers above.
  A model scene per hull family comes with the real art.
- **Big broadsides need batching.** A 1st rate fires 50 guns, or 300 balls with grapeshot,
  and each ball has a smoke trail. Measured 2026-11-14: both 1st-rate broadsides of grape at once
  (600 balls) cost a worst frame of ~27 ms headless; one big ship is fine, a fleet battle won't be. Group guns into batteries (one simulated ball and trail
  stands for several guns) so performance doesn't fall over in fleet battles.
- Fore-and-aft rigs need different sail visuals: a boom that swings across when the ship
  changes tack, instead of the square-rig yard bracing now in `ship.gd`.
- Draft needs shoal/reef areas in the world, plus a depth check in `Ship`: run aground
  means stop, take hull damage and need to kedge off.
- Oars need a calm-weather case in `Wind` to matter.
- Ships of the line are 50–60 m long against the sloop's ~16 m. Check the camera zoom range
  and the collision/hit volumes against them early.

## Parked for a possible expansion (other seas)
Galley and xebec (Mediterranean), dhow (Indian Ocean). They're out for setting reasons,
not era reasons, so if the map ever grows beyond the Caribbean they come back.

## Famous ships
Historical pirates sail one-of-a-kind ships built on these hulls, scaled to their real
lengths with their real gun counts. See `docs/famous-pirates.md`.

## Still open
- First-pass stats all need tuning in play.
- Later, maybe: simple fleet orders in battle (e.g. "attack my target", "hold back",
  "screen the prizes") so escorts aren't purely self-directed.
