# Famous pirates and their ships (draft v1)

Status: **draft v2**, 2026-11-12. Owner decisions recorded; proposals A, C and D are
still open for discussion. Builds on `docs/ship-roster.md`.

## Goal (owner)
Famous historical pirates have a real presence in the game. Each one's ships are
**unique**: one of a kind, and **as close to the real ship's size as we can get** with our
hull models.

## How a famous ship works in the game
- **Built on a roster hull, then made unique.** Each famous ship uses one of the 8 roster
  hull models, scaled to the real ship's length, with its real gun count, its own paint
  and flag, and one small **signature trait** drawn from its history (examples below).
- **Real size in real metres.** Our ships are already built at real-world size; the
  placeholder sloop is about 16 m, in the range of a real sloop. Only *speed* uses arcade
  "game scale", so famous ships can use their historical lengths directly.
- **Capturable, like everything else** (roster rule 1). Defeating a famous captain and
  taking their flagship is the biggest prize in the game. If it's sunk instead, it's gone
  for that campaign. A historical wreck could become a treasure-hunt site (see "presence").
- **Hull scaling limits:** a hull model can stretch about ±25% before it looks wrong.
  Each hull family should be modelled at the middle of the range its famous ships need
  (see "Model implications").

### Confidence key
- **Sourced:** a figure from a cited reference (usually Wikipedia or a museum source).
  Sources often disagree, and ranges are given where they do.
- **Est.:** our estimate from the ship's type and gun count. The real figure isn't recorded
  or wasn't found yet. Research these before the model is built.

## Corrections and caveats on the source list
1. **The *Cacafuego* was Francis Drake's prize, not l'Olonnais's.** It was the Spanish
   galleon *Nuestra Señora de la Concepción* (about 120 tons), nicknamed *Cacafuego*.
   Drake's *Golden Hind* captured her off Ecuador on 1 March 1579 with a huge silver cargo.
   L'Olonnais was active in the 1660s; his ships are mostly unnamed in the records.
2. **Benito de Soto's brig was the *Burla Negra*** ("Black Joke"), not *Burl Negra*.
3. **Calico Jack's *Revenge* couldn't be confirmed.** His well-attested ships are the
   brigantine *Ranger* (taken over from Charles Vane in 1718) and the sloop *William*
   (seized at Nassau in 1720, the ship he sailed with Anne Bonny and Mary Read).
4. **Several famous gun counts are disputed:**
   - *Queen Anne's Revenge*: "40 guns" is alleged; recovery teams have found about 30.
   - *Royal Fortune*: given as 40, 42 or 52.
   - Morgan's *Satisfaction*: sources say 14 or 36.
   We'll pick a playable number and note the range.
5. **The Edward Kenway exclusion is correct, and important.** He is Ubisoft's fictional
   character from *Assassin's Creed IV: Black Flag*. John Quelch is a good historical
   substitute.

## Release-1 candidates: Caribbean and Atlantic (Golden Age)

| Captain | Ship | Hull family | Length | Guns | Crew | Signature trait (idea) | Confidence |
|---|---|---|---|---|---|---|---|
| **Edward Teach (Blackbeard)** | *Queen Anne's Revenge* (ex-French *La Concorde*) | Three-masted ship | 31.4 m (103 ft), beam 7.5 m | ~40 (30 found) | 300 | **Dread:** weaker crews may strike their colours (surrender) without a fight | Sourced (guns disputed) |
| | *Adventure* (sloop) | Sloop | ~18 m | ~8 | 80 | Consort | Est. |
| **Bartholomew Roberts (Black Bart)** | *Royal Fortune* (final, ex-*Onslow* of the Royal African Company) | Three-masted ship | ~32 m | 40 (sources: 40–52) | 150+ (up to 250) | **Fortune:** better plunder from every prize | Guns sourced; length est. |
| | *Ranger* | Brigantine | ~22 m | ~18 | 100 | Consort | Est. |
| **Samuel Bellamy (Black Sam)** | *Whydah Gally* | Three-masted ship | 34 m (110 ft), 300 tons | 28 as a pirate ship (18 as built) | 150 | **Swift:** fastest large ship in the game (about 13 knots historically) | Sourced |
| | *Marianne* (sloop) | Sloop | ~17 m | ~8 | 70 | Consort (formerly Hornigold's) | Est. |
| **William Kidd** | *Adventure Galley* | Three-masted ship (oar-port variant) | ~38 m (124 ft), beam 8.5 m, 287 tons | 34 | 150–160 | **Sweeps:** rows in a dead calm, a frigate that never stalls | Sourced |
| | *Adventure Prize* (ex-*Quedagh Merchant*) | Three-masted ship (Indiaman scale) | ~35–40 m | ~30 | 120 | Treasure ship: rich hold | Est. |
| **Henry Every (Long Ben)** | *Fancy* (ex-*Charles II*) | Three-masted ship | ~36 m | 46 | 150 | **Razeed:** upper works cut down for speed, so she's fast for her firepower but has a weaker hull | Guns and crew sourced; length est. |
| **Stede Bonnet** | *Revenge* (later *Royal James*) | Sloop | ~20 m | 10 | 70 | **Gentleman's ship:** a fine cabin and library, so crew morale is higher but she costs more to run | Guns sourced; length est. |
| **John Rackham (Calico Jack)** with **Anne Bonny** and **Mary Read** | *William* (sloop) | Sloop | ~14 m | ~4–6 | 15–20 | Small and quick; Bonny and Read as named fighters in boarding | Est. |
| **Charles Vane** | *Ranger* (brigantine) | Two-master (brigantine) | ~22 m | ~12 | 90 | **Defiant:** never surrenders, always tries to break out | Est. |
| **Benjamin Hornigold** | *Benjamin* (sloop) | Sloop | ~18 m | ~10 | 80 | Mentor of Blackbeard: their fleets may sail together | Est. |
| **Henry Jennings** | *Barsheba* (sloop) | Sloop | ~18 m | ~10 | 80 | Salvage raider: hunts treasure wrecks | Est. |
| **Edward Low** | *Merry Christmas* | Three-masted ship | ~30 m | 34 | 120 | **Cruel:** merchants fight to the death rather than surrender to him | Guns sourced; length est. |
| | *Rose* (a pink) | Fluyt (pinks are fluyt-like) | ~22 m | ~6 | 40 | Consort | Est. |
| **John Phillips** | *Revenge* (schooner) | Two-master (schooner) | ~18 m | ~6 | 50 | Fast upwind raider | Est. |
| **John Quelch** | *Charles* (brigantine) | Two-master (brigantine) | ~20 m | ~10 | 90 | | Est. |
| **William Fly** | *Fame's Revenge* (ex-snow *Elizabeth*) | Two-master (snow) | ~22 m | ~8 | 60 | | Est. |
| **Richard Worley** | *New York's Revenge* (sloop) | Sloop | ~14 m | ~6 | 25 | | Est. |
| **George Lowther** | *Delivery* (ex-*Gambia Castle*) | Three-masted ship | ~28 m | ~16 | 100 | | Est. |
| **Francis Spriggs** | *Delight* | Sloop or brigantine | ~18 m | ~12 | 60 | | Est. |
| **Howell Davis** | *Rover* | Three-masted ship | ~28 m | ~30 | 120 | Roberts' mentor: the *Rover* passes to Roberts' fleet if Davis falls | Est. |
| **Walter Kennedy** | *Rover* (taken from Roberts) | Three-masted ship | as Davis's *Rover* | ~30 | 100 | Same hull as Davis's *Rover*: one ship, two owners over time | Est. |

## Pirate Round captains (Indian Ocean and Madagascar)
These mostly operated off Madagascar and in the Indian Ocean, though most also sailed the
Atlantic or the Caribbean. Since the era and geography are loose, they could appear in
the Caribbean as **rare legendary visitors** without needing a new map:
**Thomas Tew** (*Amity*, 8-gun sloop, sourced), **Edward England** (*Fancy*, *Royal James*),
**Olivier Levasseur "La Buse"** (*Victorieux*), **John Taylor** (*Cassandra*, *Victory*),
**Christopher Condent** (*Flying Dragon*), **John Bowen** (*Speaker*), **Thomas Cocklyn**
(*Rising Sun*). Kidd and Every (above) belong here too.

La Buse is a great hook: legend says he threw a coded cryptogram to the crowd from the
gallows, pointing to his buried treasure. That's history and folklore, free to use, and
perfect for a treasure hunt.

## Legends from other eras (buccaneers and privateers)
The era is loose, so these can appear as legendary encounters, or as figures whose ships
and treasure survive them:

| Captain | Ship | Hull family | Length | Guns | Notes | Confidence |
|---|---|---|---|---|---|---|
| **Sir Henry Morgan** | *Satisfaction* (ex-French *Cerf Volant*) | Three-masted ship | ~28 m | 14–36 (disputed) | Lost on a reef on the way to Panama, 1671: a treasure-hunt wreck | Guns disputed; length est. |
| | *Oxford* (5th rate) | Three-masted ship | ~30 m | 26 | Blew up in 1669 during Morgan's council of war, an infamous event | Sourced |
| **Sir Francis Drake** | *Golden Hind* (ex-*Pelican*) | Galleon (small; scaled down) | 21–31 m (sources disagree) | 18–22 | Her prize, the *Cacafuego*, could be a famous treasure galleon in the game | Ranges sourced |
| | *Revenge* (race-built galleon) | Galleon | ~28 m (92 ft), 440 tons | ~40 | Drake's flagship against the Armada (1588) | Size sourced; guns est. |
| **Bartholomew Sharp** | *Trinity* (*Santísima Trinidad*) | Galleon | ~30 m | ~30 | Captured from the Spanish | Est. |
| **John Cook** | *Bachelor's Delight* | Three-masted ship | ~30 m | ~36 | Captured Danish ship | Est. |
| **William Dampier** | *Cygnet*, HMS *Roebuck*, *St George* | Three-masted ship | ~28 m | ~26 | Explorer-buccaneer; maps and charts as rewards | Est. |
| **François l'Olonnais** | Captured Spanish frigate (name unrecorded) | Three-masted ship | ~26 m | ~16 | Notoriously brutal; see correction 1 | Est. |
| **Roche Braziliano** | Captured Spanish barques (unnamed) | Barque hull | ~25 m | ~10 | | Est. |

**19th-century Caribbean pirates** (also loose-era options): **Jean Lafitte** (schooners and
brigs out of Barataria Bay), **Roberto Cofresí** (*El Mosquito*, a small fast sloop),
**Benito de Soto** (*Burla Negra*, brig), **Pedro Gibert** (*Panda*, schooner).

## Parked: other seas
**Barbary corsairs** (Barbarossa, Oruç Reis, Dragut, Murat Reis the Elder, Jack Ward and Jan
Janszoon) and **Chinese pirates** (Zheng Yi Sao, Cheung Po Tsai, Chui A-poo, Shap Ng-tsai)
belong with the parked "other seas" expansion. Most of them need new hull types: galley,
galliot, *baştarda* and xebec for the Mediterranean; junk for the South China Sea. Jack
Ward and Jan Janszoon sailed European square-riggers, so they could visit the Atlantic
side earlier if wanted. Zheng Yi Sao's fleet of hundreds of junks would be an extraordinary
expansion centrepiece.

## Giving them a real presence (ideas)
- **They sail the map** as named fleets: flagship plus historical consorts (for example
  Blackbeard with the *Queen Anne's Revenge*, the *Adventure*, and Bonnet's *Revenge*).
- **Rumours in taverns** about where each famous captain was last seen. A bounty board in
  governors' offices.
- **Relationships from history:** Hornigold mentored Blackbeard; Davis mentored Roberts;
  Rackham sailed with Bonny and Read; Vane was deposed by his crew in favour of Rackham.
  These can drive who sails together and who replaces whom.
- **Events from history:** the *Oxford* explosion, the *Whydah* wreck, the *Fancy*'s
  capture of the *Ganj-i-Sawai*, La Buse's cryptogram, Every's disappearance. Each can be
  a rumour, a treasure hunt or an encounter.
- **Timeline (if the campaign has aging and years):** each captain could be active only in
  their historical window. Otherwise each campaign draws a random subset, so not every
  legend is at sea at once and replays differ.

## Model implications
Famous ships push the three-masted ship hull hardest: it has to span 26–38 m.
- **Three-masted ship:** model it at ~32 m, so it scales from about 26 m (l'Olonnais) to
  38 m (*Adventure Galley*) within ±25%.
- **Oar-port variant** of the three-masted ship for the *Adventure Galley*: a row of
  sweep ports on the hull. It's a texture/detail variant, not a new model.
- **Galleon:** model it at ~32 m. The *Golden Hind* at the small end (~21 m) may fall
  outside its range; if so it borrows the three-masted ship hull with galleon-style
  castles added.
- **Sloop and two-master:** existing ranges cover all the famous sloops, brigantines,
  schooners and snows.
- The roster's 8 models stay at 8. Famous ships add paint, flags, figureheads and small
  details, not new hulls.

## Legal notes
- **Real historical people and their ships are fair game.** History isn't owned, and all
  of these people died centuries ago.
- **Depict them from the historical record, never from modern media.** Several of these
  same pirates appear in other works whose portrayals *are* owned:
  - *Assassin's Creed IV: Black Flag* (Blackbeard, Hornigold, Vane, Rackham, Bonny, Read,
    Roberts, Kidd and more)
  - *Pirates of the Caribbean: On Stranger Tides* (Blackbeard and its version of the
    *Queen Anne's Revenge*)
  - *Black Sails* (Vane, Rackham, Hornigold, Bonny)
  - *Our Flag Means Death* (Bonnet and Blackbeard)
  
  Don't copy any of these works' character designs, personalities, dialogue or ship
  designs. Build from period accounts (such as the 1724 *A General History of the
  Pyrates*, long in the public domain) and archaeology (the *QAR* and *Whydah* wreck
  finds).
- **Flags:** many "famous pirate flags" were attributed in much later books and are
  historically uncertain. The designs are simple and old, but treat them as legend, not fact.
- The mechanic of hunting famous pirates also appeared in the game this project was
  inspired by. Mechanics are fine; don't copy its specific list, portraits or presentation.

## Decisions (owner, 2026-11-12)
1. **Release 1 includes every pirate in this doc** except the parked other-seas captains
   (Barbary and Chinese), who need new hull types.
2. **Legends from other eras are in.** *How* they appear is still to be discussed (see
   proposal A).
3. **Every famous ship gets both a passive trait and an active ability** (proposal B).
4. **Timeline:** the owner leans toward captains appearing freely regardless of their
   era, but wants a wider discussion (proposal C).
5. **Alliances with famous captains are possible, and they're pirates: expect betrayal**
   (proposal D).

## Proposals under discussion

### A. How legends from other eras appear
- **Option 1, just sail (simplest):** Drake, Morgan and the others roam like any famous
  captain, at legendary rarity. This matches the loose era and the owner's instinct on
  the timeline.
- **Option 2, legacy ships:** the legend is gone but their ship sails on under a
  successor ("the *Golden Hind*, now under Drake's old sailing master"). This keeps
  history plausible, but you never meet the legend himself.
- **Option 3, legend events:** each legend appears through a rare event tied to their
  history: Morgan gathering a fleet to sack a city, Drake hunting a treasure galleon like
  the *Cacafuego*.
- **Recommendation:** combine 1 and 3. They sail like other famous captains, at
  legendary rarity, and each carries a signature event that can trigger when they're nearby.

### B. Traits and abilities (decided: both)
Every famous ship has:
- **A passive trait:** always on, built into the ship.
- **An active ability:** triggered, then a cooldown. The AI uses it too, so you feel it
  when fighting her.

**Both belong to the ship and come with her when captured.** That's the payoff for taking
a famous flagship instead of sinking it. Captain *personality* (Vane refusing to surrender,
Low's cruelty) is AI behavior and leaves with the captain.

First-pass examples (to be tuned, and to be designed for every famous ship):

| Ship | Passive trait | Active ability |
|---|---|---|
| *Queen Anne's Revenge* | **Dread:** weaker crews may surrender without a fight | **Lit fuses:** before boarding, the enemy crew's morale breaks (Blackbeard famously wore burning slow-match in his hair and beard) |
| *Whydah Gally* | **Swift:** fastest large ship in the game | **Crowd sail:** short speed burst on any point of sail |
| *Adventure Galley* | **Sweeps:** rows in a dead calm | **Out sweeps:** for a short time, turns and moves at full speed ignoring the wind |
| *Royal Fortune* | **Fortune:** better plunder from every prize | **Roberts' articles:** crew rally, an instant reload and a morale boost (Roberts famously ran his ships under written articles) |
| *Fancy* | **Razeed:** fast for her guns, weaker hull | **Run them down:** speed burst while chasing a fleeing ship |
| *Revenge* (Bonnet) | **Gentleman's ship:** higher morale, higher upkeep | **Fair terms:** a strong surrender offer to merchants |
| *William* (Rackham) | **Small and quick** | **Bonny and Read:** boarding strength doubled for one boarding |
| *Merry Christmas* (Low) | **Cruel:** merchants fight to the death against her | **No quarter:** extra damage to enemy crew |

### C. Timeline (open)
- **Option 1, free (the owner's instinct):** all captains can appear at any time, gated
  only by rarity. It's simple, and it means you can meet Blackbeard and Drake in one
  campaign.
- **Option 2, historical windows:** each captain appears only in their real active years.
  It needs a campaign calendar, and it means most legends never meet.
- **Option 3, chosen start era:** pick a start year (1660, 1690, 1715...). Captains from
  near that year are common, distant ones rare. History has a pull, but nothing is
  locked out.
- **Option 4, random cast:** each campaign draws a subset of captains, so replays feel
  different and the sea isn't crowded with legends.
- **Thought:** 1 + 4 together is free roaming with a different cast each campaign.
  Option 3 could be added later as a "historical" setting.

### D. Alliances and betrayal
Allying with a famous captain should be possible, valuable, and **risky, but not certain
to go wrong.** If betrayal were guaranteed, players would never ally, or would always strike
first.
- **How an alliance works:** an allied captain sails nearby with their own fleet, fights
  alongside you under their own AI, and takes an agreed share of the plunder. You don't
  control them.
- **Loyalty** drifts with the situation:
  - **Down:** unequal shares, a rich prize in your hold, you looking weak (damaged ship,
    small crew), a pardon offer from a governor, their personality.
  - **Up:** fair shares, winning together, your fame.
- **Telegraphed, so it's fair:** warning signs come before a betrayal. Tavern rumours,
  ignored signals, the ally drifting out of formation, a sudden argument over shares.
  An attentive player can see it coming and act first. Betraying an ally yourself costs
  reputation with every pirate.
- **History supplies each captain's betrayal style**:
  - **Blackbeard** ran the *Queen Anne's Revenge* aground in 1718, widely believed to
    be deliberate, then left with the loot and a loyal few, marooning many of the
    others. He's the take-the-treasure-and-run type.
  - **Hornigold** accepted the King's pardon and became a pirate hunter, so he may turn
    up hunting you.
  - **Vane** was deposed by his own crew, and Rackham took his ship. Allied fleets can
    have mutinies.
  - **Every** vanished with his fortune. A partnership ends with him gone and your share
    with him.
  - **Kennedy** deserted Roberts and took the *Rover*.
- **Some captains are more reliable than others.** Bonnet is naive, a likely victim rather
  than a betrayer (Blackbeard took advantage of him historically).
