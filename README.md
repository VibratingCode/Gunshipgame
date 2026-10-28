# Gunship: Overwatch

AC-130-style thermal gunship defence in Godot 4.7. You're the sensor operator of a gunship flying a
left-hand orbit over the last safe zone in the city, a stadium. Tens of thousands of infected are
walking toward it. You start with two machine guns. Every kill earns requisition points, which you spend climbing eight weapon
ladders (71 systems, from twin .50s to a lunar strike, each rung unlocked by buying the one below it) and on
permanent upgrades to the aircraft itself. After every wave you pick one of
three roguelite perks for the rest of the sortie. Your career saves: what you buy is yours on every AO, forever.

Each AO is also a three-day campaign. The waves are broken up by jobs from the people on the ground below you,
and the campaign ends in an evacuation flight you have to cover. Or switch seats and fly **CAS**: you're
the A-10 pilot hand-flying close air support, and the gunship is flown by the AI.

## Running it

Double-click **Gunship Overwatch** on the desktop, or open this folder in Godot 4.7 and press **F5**.

## Title screen

The live AO plays out behind the menu. **Deploy** (Enter) takes you to the pre-sortie loadout, **Fly CAS**
(C) puts you in the A-10 (see CAS mode), and **Settings** (Esc) opens sensitivity, invert Y, volume, sensor,
palette, the dev farm and the career wipe. On the right
is the list of areas of operations (W / S or click) with each one's threat rating and your best day and wave,
and a briefing for the selected AO with a live plan view of its approaches and the horde already on them.
Along the bottom: your requisition, rank and progress to the next promotion, systems owned and upgrade levels.

## Sensor: IR and colour TV

The turret carries two cameras. **X** switches between them (also in Settings):

- **IR**: the thermal imager the game was built around: white-hot, black-hot, ironbow or disco (F).
- **Colour TV**: the daylight camera. Every AO in real colour under its own sun and sky: brick, render and
  glass in the city with blue windows and tar or clay roofs, a farm patchwork with red barns and silos
  beyond it, sand, mud brick and HESCO at Anvil, a white hospital ship with red crosses, yellow gantry cranes
  and stacks of coloured containers at Trident, red modules on the ice at Kepler, forested hills at Gabriel.
  Smoke rises black, then grey.

**Glow is the colour of its temperature,** not of the weapon that made it. Everything hot is coloured by a
blackbody curve. A dying fire is dull red, a fresh one orange-yellow, and a fireball or a laser bolt
white-hot. Tracers, embers and molten metal follow the same rule. Streetlights are sodium orange, lamps
in windows are a warm 3,300 K, and beacons blink red.

### The horde on the thermal

- **The kinds glow differently:**
  - Walkers have a warm torso, a hot head and cooler limbs.
  - Runners are hotter all over, and their heads pulse with every stride.
  - Brutes carry a big, slowly throbbing slab of heat in the chest, with cold limbs.
- **The dead cool.** A body loses heat fast for a few seconds, then slowly over a couple of minutes,
  limbs before the trunk. It never quite reaches ground temperature, so a fight's trail stays readable
  long after it ends.
- **Burnt bodies** are charred black on the TV and smoulder hot for longer.

## Areas of operations

Pick an AO on the title screen. The world behind the menu is the live AO.

| AO | Refuge | Terrain | How it plays |
| --- | --- | --- | --- |
| **HOMEFIELD** | Stadium | Gridded city, farmland | Eight avenues and two parks funnel the horde inward |
| **ANVIL** | FOB Anvil (HESCO octagon) | Desert valley, wadis, mud-brick village, mountains | Broad waves across open sand plus a highway; very little cover for them |
| **TRIDENT** | Port terminal and hospital ship | Container yards, gantry cranes, tank farm, sea | Attacks from the landward half only; containers block low shots |
| **GALLOWS** | Blackwater Prison | Island in a wide river, towns on both banks | Four bridges are the only way in, so the horde jams into chokepoints |
| **FROSTBITE** | Kepler Station | Ice sheet, frozen lake, mountains, LC-130 on the skiway | Near-black cold terrain, infected glow white-hot, blowing-snow haze |
| **FOR GOD, FOR HEAVEN** | Firebase Gabriel (walled base, chapel at its heart) | Forested hills with real terrain collision, a single valley from the north | The entire horde comes down one valley in huge numbers (2.4× waves, a mega-horde every wave, doubled garrison); the hills block your shots |

Every AO keeps the same rule: the infected walk straight lines toward the refuge, down corridors that buildings, water and terrain never block.

The title screen groups the AOs by how many ways in they have. Besides the six above:

| Category | AO | Built on | Paths |
| --- | --- | --- | --- |
| One path | **Needle**: one wide boulevard through downtown | Homefield | 1 |
| One path | **Chute**: a single dry wadi through the rocks | Anvil | 1 |
| 2–4 paths | **Pincer**: two arms of sand | Anvil | 2 |
| 2–4 paths | **Twin Gates**: two ice roads through the station | Frostbite | 2 |
| 2–4 paths | **Salt Flats**: three wide-open fans of salt pan | Anvil | 3 |
| 2–4 paths | **Old Town**: four streets from the points of the compass | Homefield | 4 |
| 5–7 paths | **Sprawl**: six evenly spaced suburban avenues | Homefield | 6 |
| 8+ paths | **Starfall**: eight ice roads and four ice fields | Frostbite | 12 |
| 8+ paths | **Gridlock**: twelve jammed streets | Homefield | 12 |
| 8+ paths | **The Open**: ten sand wedges, every direction | Anvil | 10 |

The variants use their base AO's story, weather and look, with their own approaches.

### Challenge: Smoke of Their Torment

A burnt, still-burning plain. Each wave comes over the horizon as **one tide**: 30,000 infected
on wave 1 (30% more every wave), packed shoulder to shoulder in a 140 m deep band across a 70° front about 2 km out, every one walking at
the blood moon's pace. The rest of the wave keeps pouring in behind as you make room. **Three bosses**
ride in every tide from wave 1. There's no story, no evacuation and no side jobs: hold the Last Light
for as long as you can. Your best wave is your score.

**Iron Torment** is the same map with nothing but a GAU-8. Your career stays outside: no owned
systems, no upgrades, 0 RP. You earn requisition wave by wave and buy everything on the ladders as you
go. When the sortie ends, all of it is gone. The only thing you keep is the XP (lifetime RP, toward
your rank) and your best wave.

### A lived-in world

- **Buildings:**
  - Shopfronts with awnings, weathered facades, and windows both lit and dark.
  - Gabled houses.
  - Rooftops with parapets, stair and lift housings, AC units, water tanks, solar panels, and masts with
    blinking beacons.
  - Burnt-out shells and rubble lots.
  - Rooftop holdouts: tents, a cooking fire, and sometimes an SOS painted on the roof.
- **Streets:**
  - Abandoned traffic jams down the avenues: cars, buses and lorries. Some are burnt out and some are
    still burning.
  - Streetlights, power lines, barricades and military checkpoints.
- **Landmarks:** each AO has three or four named buildings, such as the Old Hospital, Central Mall,
  Warehouse Nine, the Cannery and the Sawmill. Any of them can become a nest (see Missions).
- **An airstrip** on every AO, with a runway, apron, hangar, tower, fuel bowsers, a windsock and edge
  lights. It's the FARP in CAS mode.
- **The grid fails day by day.** Streetlights and lit windows run on mains power, and districts go dark
  as the days pass: everything is lit on day one, and by day five it's candles.
- **Illumination flares.** After dark, when the infected press the walls, the refuge fires parachute
  flares over the worst sector. Each burns for about half a minute and lights the ground for the TV
  camera. On the IR it's just a blinding point.
- **Scars stay.** Every blast and every fire leaves a scorch mark on the ground for the rest of the
  sortie.

## Controls

| Input | Action |
| --- | --- |
| Mouse / arrow keys | Slew the sensor (it stays locked on a ground point while you orbit); arrows for fine holds |
| T / middle mouse | Point track: follow the infected under the crosshair; the fire-control computer leads it by each weapon's time of flight |
| TAB | Tactical map of the whole AO with horde density: left-click slews the sensor, right-click moves your orbit |
| C / H | Fly the orbit over the sensor point / back over the refuge |
| , / . | Time compression ×1, ×2, ×4, ×8 (drops to ×1 when anything reaches the wall) |
| V | HUD declutter: full / minimal / clean |
| F1 | Help overlay |
| LMB (hold) | Fire. Hold to charge the railgun, or to give nuclear release consent |
| RMB / Z / Space | Step zoom: wide 30°, medium 9°, narrow 2.6° |
| Mouse wheel | Fine zoom |
| 1-9, 0, - = / Q E | Select a loadout slot (- and = need the Weapon Stations upgrade) |
| R | Reload the current gun, or buy a full restock of the selected system (see Ammunition) |
| Y | Fuze: impact / airburst / delay, on the cannons, missiles and bombs that have a choice (see Fuzes) |
| G | Call an A-10 gun run through the crosshair (once owned, even if not in the loadout) |
| B | Armory, loadout and aircraft upgrades (pauses the battle) |
| 1-3 / R (between waves) | Pick a perk / reroll the offer for requisition |
| W / S | Throttle (107–243 kt) |
| Shift / Ctrl | Climb / descend (1,500–11,800 ft) |
| A / D | Tighten / widen the orbit (limited to 45° of bank) |
| F | Palette: white-hot / black-hot / ironbow false colour / DISCO |
| X | Sensor: the IR imager or the daylight colour TV camera |
| [ ] | Mouse sensitivity |
| Esc | Pause and settings: sensitivity, invert Y, volume, palette, dev farm, reset progress (saved with your career) |
| F9 | Dev: zombie farm on/off (see Dev switches) |

## Standoff

The hordes mass **1.2–2.8 km out** and walk in at human pace (0.9–1.4 m/s, with runners at 2.4–3.4 m/s), so
you engage them on the approach, as a real gunship would. About one clump in seven emerges from buildings
closer in. Mega-hordes gather 2.3–2.9 km out.

- **Standoff bonus:** kills earn up to **2× RP** the further they are from the refuge (×1 inside 600 m, ×2 beyond 2.4 km).
- **Lead contact:** the HUD shows how far out the leading edge of the horde is and its ETA to the wall.
- **Radar:** the bottom-right radar shows horde density out to 3.2 km, with threat bars by sector.
- **Weapon view:** guided munitions (Hellfire, bombs, Tomahawk, Switchblades) open a
  picture-in-picture seeker camera that rides the weapon into the target.

## Fuzes and blast

Press **Y** to step the selected weapon's fuze. The setting shows under the reticle and as a tag in the
weapon list (PD / AB / DLY), and the blast footprint on the ground changes with it.

| Fuze | What it does | Use it on |
| --- | --- | --- |
| **Impact** (PD) | Point detonating: the all-rounder | Anything |
| **Airburst** (AB) | Goes off a few metres up. Fragments rain over a circle about 1.5× wider, but each one is light: half the kill radius, a quarter of the damage to buildings | Crowds in the open |
| **Delay** (DLY) | Goes in before it goes off. Little blast escapes sideways, but bodies are thrown hard, it does 3× damage to a boss it's buried in, and 3.5× to a building | Bosses and nests |

The fuzes are on the Bofors and L/70, the Bushmaster (it comes set to airburst), the 105s (Willie Pete:
impact or airburst), Hydra and APKWS, Griffin, Hellfire (impact or delay), JAGM, Tomahawk, the SDB,
Paveway, StormBreaker and JDAM. The Daisy Cutter and MOAB come set to airburst, and the MOP to delay.

**Shock waves.** Every explosive throws a ground shock ring sized by its TNT equivalent, using
Hopkinson's cube-root scaling (R ∝ W^⅓). The kinetic weapons are sized by their impact energy as TNT.
The scale is pinned so that a 30 mm HEI round makes a 13 m ring:

- a Hydra makes about 37 m
- a 500 lb bomb about 160 m
- a MOAB about 730 m
- big rings expand faster and carry a fainter second overpressure ring

## Line of fire

Shells and missiles leave the aircraft and fly real paths, so buildings, terrain and hills get in the way.
When the line of fire for a gun, cannon, rocket, missile, the laser or the railgun is blocked, the reticle
warns you:

- `TRACK MASKED` means the line from the aircraft is blocked.
- `TARGET BEHIND STRUCTURE` means the aim point is on a wall in front of the target.

A red cross marks where the line of fire hits. The warning also tells you how long until the orbit
carries you clear (`CLEAR IN 12 S`), or says `REPOSITION THE ORBIT` when nothing on this orbit can see
the target.

The radar's orbit ring is coloured by the same test: green where the target can be seen from that point
of the orbit, red where it can't.

## How the weapons fly

- **Hellfire, JAGM and Griffin** loft before their terminal dive, climbing about a third of the ground range
  (a quarter for the Griffin) so they come down steep, over the rooftops instead of into them.
- **Tomahawk** comes in from the sea down whichever avenue lines up best with the target. It flies low
  between the buildings, cuts across the rooftops if the target is off the street, then pops up and
  dives. Its route is drawn on the tactical map.
- **Switchblades** cruise to the mark and circle over it, searching. Each one picks a crowd none of the
  others has claimed, then they dive one after another. The seeker view reads `SWITCHBLADE SEARCHING`
  while they loiter.
- **The A-10 and the F-16s** fly a real attack pattern, in the order below. The status line reads
  `IP INBOUND`, `IN HOT` and `EGRESS` as they go, and the tactical map shows their tracks.
  1. Check in at a holding point.
  2. Run to an initial point (IP).
  3. Roll in on a run-in heading that keeps overs and shorts away from friendlies. That's outbound when
     the target is well out, and parallel to the wall when it's close.
  4. Walk the burst or the bombs through the mark. The F-16 wingman follows a few seconds in trail.
  5. Pull off away from the refuge and egress.

## Career, the ladders and the arsenal

- **Persistent career:** requisition (RP), lifetime RP, owned systems, your loadout, your pinned goal and
  your best wave on each AO are saved to `%APPDATA%\Godot\app_userdata\Gunship Overwatch\pilot.cfg`. They save on every
  purchase, every wave, every game over, and every 20 s in flight. Delete that file to start a new pilot.
- **The ladders:** the 71 systems sit on eight ladders, one per armory tab, each running from the
  down-to-earth to the absurd. **You can only buy a rung once you own the one below it.** The next rung on
  each ladder pulses in the armory; everything above it reads `LOCKED: own the X first`. The last rung of
  every ladder is its **capstone**, and the most outrageous things in the game (the Atomic Gatling, the B61,
  the lunar strike) are all at the top. Each tab shows how far up its ladder you are.
- **The unlock:** every purchase gets a full-screen card with a fanfare: the system, rung *n* of *m*, how much
  more firepower it has than the rung below it (guns, cannons, rockets and bombs), its damage, blast, rate of
  fire and capacity against the rest of its ladder, whether it went straight aboard, and what's next up. The
  crew chief has something to say about most of them. Click or press anything to carry on.
- **Saving for something:** click the rung number on any armory row to **pin** it. In flight, the HUD under
  your requisition shows what you're saving for (the pinned system, or else the cheapest next rung on any
  ladder) with a progress bar, and flashes `READY` when you can afford it.
- **Rank:** lifetime RP earns promotions, Second Lieutenant to Major General, at 1.5k / 4k / 9k / 16k / 26k /
  40k / 60k lifetime RP. A promotion comes with a banner and a word from TOC. Rank is honour only: the ladders
  decide what you can buy.
- **Loadout:** after picking an AO you choose up to **10** owned systems for the aircraft (keys 1–9, 0),
  or 12 with the Weapon Stations upgrade (keys - and =). Swap them between waves in the armory (B → tab 9, LOADOUT).
- Kills earn 1 RP each, plus 400 × wave for clearing a wave.

### Ammunition

Nothing runs dry for good.

- **Guns** reload from the magazine and the **laser** recharges, forever and free.
- **Everything else restocks on its own**, in game time, even while it isn't selected. The HUD shows
  `RESTOCK 23S` and a filling bar on an empty system. Full load from empty: cannons 2.5 min, rockets and
  missiles 2 min, bombs 2.5 min, fire support 3 min, experimental 2.5 min. Big single items come back one at
  a time: MOAB / Daisy Cutter 3 min, B-52 4 min, Davy Crockett 4 min, B61 7 min, W70 9 min, THOR
  constellation 8 min.
- **Buy a restock** to skip the wait: press **R** with the system selected (the HUD shows the price), click
  **RESTOCK** on its armory row, or **RESTOCK ALL ABOARD** next to Deploy. A full load costs 15–30% of
  the system's purchase price, pro-rated for what's missing.
- Every new wave still brings a full resupply.

### Aircraft upgrades (permanent)

Armory tab 0 (the tenth), **UPGRADES**, left column. Bought with requisition, saved with your career, applied on every AO. Each level
costs more than the last (base × level^1.6).

| Upgrade | Levels | Base RP | Per level |
| --- | --- | --- | --- |
| T56-A-427 engines | 5 | 900 | +8% top speed, +20% climb rate |
| Airframe armor | 4 | 1,500 | Survive your own nukes 12% closer |
| MX-25D sensor turret | 4 | 1,100 | +20% zoom depth, −15% detector noise |
| Fire-control computer | 5 | 1,200 | −8% dispersion on guns and cannons |
| Autoloaders | 5 | 1,500 | −7% reload, +5% rate of fire |
| Magazines | 5 | 1,000 | +12% ammunition on every system |
| Barrel cooling | 5 | 700 | +15% sustained fire before a rotary overheats |
| Weapon stations | 2 | 6,000 | +1 loadout slot |
| Link-16 datalink | 4 | 2,000 | −10% fire-support cooldowns, +4% requisition |
| Quartermaster | 5 | 1,100 | Ordnance restocks 12% faster, bought restocks 8% cheaper |
| AN/APQ-180 radar | 4 | 1,800 | +10% standoff bonus, +10% muzzle velocity |
| Battle management system | 4 | 2,400 | −8% fire-support cooldowns, +5% blast radius, +5% requisition |

### Perks (roguelite, per sortie)

Every time you clear a wave the battle freezes and you're offered **three perks**: click one or press 1–3.
Press R to reroll the offer (400 RP, then 60% more each time). Perks last until the sortie ends and they
stack, so taking Hardened Tips three times is +52% damage. There are 59 of them in three rarities,
including restock perks (Speedball, Haggler, Air Bridge, Black Market, Bottomless Racks):

- **Common (70%)**, e.g. Hot Loads (+15% muzzle velocity), Sandbags (the walls slowly repair), Veteran Garrison,
  Accelerant (longer fires), Crippling Fear (new hordes walk slower), Extra Pods (+6 rockets per salvo).
- **Rare (25%)**, e.g. Incendiary Rounds (gun impacts start fires), Field Medics (kills repair the walls),
  Swarm Logic (+4 drones or micro-missiles), Lucky Rounds (some blasts are double size), Napalm Summer.
- **Legendary (5%)**, e.g. Volatile Infected (kills detonate and set off their neighbours), Chain Reaction,
  Divine Wind, Bullet Hell, Second Coming (double ammo, −40% reload), Time Dilation, Lucky Star.

### Fire

Every fire (napalm, white phosphorus, thermite, incendiary rounds) **cools as it burns**: damage falls with
(1 − age/duration)^1.5, the flames shrink and dim on the thermal sensor, and the ground fades back to ambient.
A fresh strip kills everything walking in; an old one only singes them.

### The arsenal, ladder by ladder

Prices in RP. Each rung needs the one above it in the table. ★ marks the capstone.

**Guns** (you start with the first two)

| # | System | RP | What makes it different |
| --- | --- | --- | --- |
| 1 | M2HB twin .50 | free | Inaccurate from altitude; fly low |
| 2 | GAU-19/A .50 Gatling | free | Three-barrel .50 at 1,300 rpm, far steadier than the twin M2s |
| 3 | M134 Minigun | 400 | A 6,000 rpm hose of 7.62 |
| 4 | M197 20 mm | 900 | Your first real cannon: three-barrel 20 mm HE, 1,100 well-aimed rounds a minute |
| 5 | GAU-12/U Equalizer 25 mm | 1,600 | The AC-130U's five-barrel workhorse, 1,800 rpm |
| 6 | M61A1 Vulcan 20 mm | 2,600 | A fighter's gun on a gunship: 6,000 rpm |
| 7 | GAU-8/A Avenger 30 mm | 4,200 | 3,900 rpm; every HEI round's blast kills all within 3 m |
| 8 | GSh-6-30 30 mm | 6,500 | 4,800 rpm of bigger 30 mm; overheats fast, so fire in bursts |
| 9 | EXACTO smart Gatling | 9,000 | Every round picks its own infected near the crosshair. It does not miss |
| 10 | M-ARC ricochet gun | 12,000 | Each round caroms off its victim into five more |
| 11 | Scattershot 40 | 16,000 | Eight shells a second, each bursting into ten bomblets |
| 12 | Ripsaw blade launcher | 21,000 | Saw blades that skip 110 m through the crowd, six a second |
| 13 | Pulse laser machine gun | 27,000 | Sixty light-speed bolts a second; no drop, no lead |
| 14 | Tesla arc projector | 34,000 | Ten bolts of lightning a second, each jumping through six more of them |
| 15 | Auric Gatling | 42,000 | Turns them to gold: every kill pays 4× requisition |
| 16 | Chrono cannon | 52,000 | Erases the heart of every hit and throws everything around it 450 m back up its path |
| 17 | Graviton repeater | 64,000 | Five black holes a second; each eats the crowd around it, then collapses |
| 18 | God's Gatling | 80,000 | An orbital tungsten gatling: twelve rods a second from space |
| 19 ★ | Atomic Gatling | 100,000 | Four micro-nukes a second |

**Cannons**

| # | System | RP | What makes it different |
| --- | --- | --- | --- |
| 1 | L/60 Bofors 40 mm | 500 | Four-round hand-fed clips |
| 2 | Mk44 Bushmaster II 30 mm | 1,200 | The AC-130J's gun: 200 rpm proximity airburst |
| 3 | L/70 Bofors 40 mm 3P | 2,400 | Belt-fed, 240 rpm, programmable proximity rounds |
| 4 | M102 105 mm | 4,000 | THE gunship gun: 3–4 s shell flight, throws bodies |
| 5 | M102 105 mm + PGK | 6,500 | GPS-steered 105: lands within a metre of the crosshair |
| 6 | M546 Beehive | 10,000 | Flechette airburst rakes a 100 m lane down the line of fire |
| 7 ★ | M60 Willie Pete 105 | 15,000 | White phosphorus: a blinding burst, then a burning field that cools over 18 s |

**Rockets**

| # | System | RP | What makes it different |
| --- | --- | --- | --- |
| 1 | Hydra 70 pod | 700 | 19 unguided rockets rippled in 1.4 s |
| 2 | APKWS II | 1,500 | Laser-guided Hydra: cheap, plentiful, precise |
| 3 | AGM-176 Griffin | 2,500 | Light laser-guided missile, 16 per sortie |
| 4 | AGM-114 Hellfire | 4,000 | Flies to whatever is under your crosshair |
| 5 | AGM-179 JAGM | 6,500 | Hellfire's heavier successor, 12 on the rails |
| 6 | Merlin micro-missile swarm | 10,000 | 48 micro-missiles, each picking its own infected |
| 7 | Switchblade 600 swarm | 15,000 | 14 drones that find the densest crowds near your mark and dive |
| 8 ★ | BGM-109 Tomahawk | 22,000 | From a destroyer offshore: rooftop-skimming, pop-up, dive |

**Bombs**

| # | System | RP | What makes it different |
| --- | --- | --- | --- |
| 1 | GBU-39 SDB | 1,200 | 250 lb GPS glide bombs off the ramp |
| 2 | GBU-12 Paveway II | 2,000 | 500 lb laser-guided. The workhorse |
| 3 | GBU-53/B StormBreaker | 3,200 | Follows a moving target: the point-tracked infected, or the nearest one to the mark |
| 4 | Lazy Dog darts | 4,500 | Kinetic dart rain over a block |
| 5 | Mk-77 incendiary | 6,000 | 160 m strip of fire that kills what walks in while it's hot, then cools |
| 6 | Thermite rain | 8,000 | 50 burning pellets across a block, each a small cooling fire |
| 7 | CBU-89 Gator | 10,500 | 72 mines that wait for the horde to walk into them |
| 8 | CBU-97 SFW | 13,500 | 40 sensor-fuzed skeets across a block |
| 9 | GBU-31 JDAM | 17,500 | 2,000 lb. Deletes an intersection |
| 10 | BLU-82 Daisy Cutter | 24,000 | 15,000 lb of slurry explosive off a pallet |
| 11 ★ | GBU-43/B MOAB | 33,000 | 11 tons out the ramp |

**Fire support**

| # | System | RP | What makes it different |
| --- | --- | --- | --- |
| 1 | A-10C gun run (also G) | 1,500 | Strafes the column; BRRRT arrives after the impacts |
| 2 | M777 155 mm fire mission | 3,000 | 18 rounds from a battery 12 km away. "Shot, over" … "Splash, over" |
| 3 | F-16 CAS two-ship | 4,800 | Two Vipers walk eight GBU-38s through your mark along the approach |
| 4 | AH-64 Apache pair | 7,500 | Two Apaches hover over your mark for 45 s with chain guns and rockets |
| 5 | M142 HIMARS GMLRS | 11,000 | Six GPS rockets from 70 km, one on the mark and five around it |
| 6 | Spectre 2-2 wingman | 15,000 | A second gunship on the far side of the orbit, hunting crowds for 50 s |
| 7 | TOS-1A salvo | 20,000 | 24 thermobaric rockets saturate a grid square |
| 8 ★ | B-52 Arc Light | 28,000 | 51 bombs carpet 1.2 km of the approach through your mark |

**Experimental**

| # | System | RP | What makes it different |
| --- | --- | --- | --- |
| 1 | AHEL laser | 5,000 | Speed of light, no spread; sweep it; the capacitor drains and recharges |
| 2 | High-power microwave | 8,000 | An invisible 30 m cone: hold it on a crowd and everything inside cooks |
| 3 | EM railgun | 11,500 | Hold 1.2 s to charge; the slug ploughs a 260 m trench |
| 4 | Die Glocke | 16,000 | A humming bell rises over your mark for 22 s and calls down chain lightning; steer it with the crosshair |
| 5 | THOR rod | 22,000 | Orbital tungsten rod 8 s after designation |
| 6 | SOL orbital laser | 30,000 | A 12 s beam from orbit that follows your crosshair |
| 7 ★ | Singularity projector | 40,000 | A pinprick black hole drags the crowd in for 8 s, then collapses |

**Strategic**

| # | System | RP | What makes it different |
| --- | --- | --- | --- |
| 1 | LRHW Dark Eagle | 20,000 | Hypersonic glide vehicle, Mach 17 onto the mark in six seconds |
| 2 | M388 Davy Crockett | 28,000 | 0.02 kt micro-nuke out of the howitzer tube; hold 1 s |
| 3 | GBU-57 MOP | 36,000 | 30,000 lb, off the ramp. The ground itself goes up |
| 4 | THOR constellation | 46,000 | Twelve rods walked down the approach through your mark, 30 m apart |
| 5 | W70 neutron bomb | 58,000 | Small blast; then everything alive within 1.1 km drops while buildings stand |
| 6 ★ | B61-12 | 75,000 | 10 kt; hold 2.5 s for consent. The shock wave rolls out at the speed of sound and flattens everything within 900 m and nearly everything to 1.6 km |

**Shenanigans**

| # | System | RP | What makes it different |
| --- | --- | --- | --- |
| 1 | Cow catapult | 1,000 | Live cattle out of the ramp, tumbling on a ballistic arc. Warm-blooded, so they glow |
| 2 | Grand piano drop | 3,000 | A concert grand, dead on the crosshair. It lands on a chord |
| 3 | The Boulder | 8,000 | 15 m of granite that lands on the mark, then rolls 900 m outward, flattening the approach |
| 4 | Titan mech | 25,000 | A 40 m friendly giant falls on your mark and stomps toward the thickest crowd for 40 s |
| 5 ★ | Lunar strike | 120,000 | Hold fire 2 s. Twelve seconds later a 300 m moon arrives: nothing lives within 1.4 km, almost nothing to 2.6 km. Keep it 1.5 km from the refuge |

The armory also sells **Reinforce the Walls** (+25% integrity) for 1,500 RP.

## Waves

Wave 1 is a couple of hundred infected. Every wave is ~55% bigger than the last: about 1,300 by wave 5,
11,000 by wave 10, and from wave 12 or so the horde hits the engine's cap of **80,000 alive at once**. From
then on the spawner holds the rest of the wave back and feeds it in as fast as you kill, so every approach
stays packed from the edge of town to the edge of the map. After wave 6 the hordes also spread wider and
closer in, until by wave 13 the whole AO is crawling. Clearing a wave pays 600 + 400 × wave RP.

From wave 4 (every wave on the big AOs), a **mega-horde** of about a third of the wave masses 2.3–2.9 km
out on one approach, a target worth heavy ordnance.

## Night and weather

Every day runs a full 24-hour clock across its five waves, starting at dawn: wave 1 is morning, wave 2
midday, wave 3 runs into dusk, waves 4 and 5 are fought in the dark, and surviving the day brings the next
dawn. The left of the HUD shows local time and the weather.

- **At night** the colour TV is close to useless: dark, grainy, lit only by fires, floodlights and lit
  windows. The HUD warns you, and the IR imager owns the dark.
- **At dawn and dusk** there's thermal crossover: for an hour or so the ground and everything on it sit at
  the same temperature, and the IR picture goes flat.
- **Weather** is rolled for each wave, and the radio calls it:

| Weather | Where | IR | TV | Also |
| --- | --- | --- | --- | --- |
| Clear | everywhere | full | full | |
| Overcast | everywhere | slightly softer | flat light, shorter range | |
| Rain | city, port, river, highlands | soft, short range | short range | streaks on the lens; fires burn 40% weaker |
| Fog | city, port, river, arctic, highlands | cuts through | blind beyond a few hundred metres | |
| Snow | arctic | soft | short range | flakes on the lens; fires 30% weaker |
| Sandstorm | desert | badly degraded | badly degraded | blowing dust on the lens |

## Ground operations

While you hold the refuge, the rest of the war happens on the ground below you:

- **Rescues** (from wave 2): survivors stranded out on an approach pop flares. A Black Hawk lifts from the
  refuge, flies out, lands and loads them. Keep the infected off them: the HUD shows a danger meter, and
  if too many reach them for too long, they're lost. Bring them home for 250 RP each (more in later waves).
- **Convoys** (usually during the third wave of every day): five supply trucks fight their way in
  down an avenue. They crush whatever's in the road, but every body hurts them and a crowd will tear one
  apart. Clear the road ahead. Each truck that makes it pays 1,200 RP and brings 25 people; three or more
  and every rack aboard is restocked.
- **The refuge's population** grows with everyone you bring in: a bigger, faster-shooting garrison, faster
  repairs, and more people visible inside the walls. Every day it survives the refuge also builds out:
  more shelters, prefab housing and floodlights.

## Missions

From wave 2, a new job comes in every minute or two while a wave is on. It's announced on the radio and
the banner, then tracked under the reticle and on the tactical map. Pay rises 5% a wave.

| Mission | The job | Pays |
| --- | --- | --- |
| **Hold** | Ranger 6 holds a bridge (or an overpass on an avenue) with six men and enough demo to drop it. Keep them alive for three minutes while the infected come down the road at them in numbers. When the time is up the charges blow, and the bridge goes down with everything on it | 3,000 + 300 a survivor |
| **Medevac** | Dustoff 3-1 collects wounded from two outposts 0.8–1.5 km out, against a clock (3 min 40 s). It won't set down on a hot LZ: it holds short until no more than two infected are within 60 m. Loading takes ten seconds, and if three get within 22 m it lifts without them. The rotor noise draws a crowd to every LZ | 150 a wounded man brought in |
| **Nest** | The infected have taken one of the AO's landmarks. It glows on the thermal and pours out a crowd every seven seconds. Bring the building down. Delay fuzes do 3.5× structural damage, airbursts a quarter, and gunfire barely chips it; a STRUCTURE % readout pops up as you hit it. It collapses on whatever is round it | 4,000 |
| **Engineers** | A team outside the wire rebuilds a wall section on the worst-hit side. Keep them alive for ninety seconds | 1,500, +20% integrity, and the walls take 10% less damage for the rest of the sortie |

If a team is wiped out, the job fails and the refuge loses six people.

### Danger close

Teams in contact call for fire on a crowd 18–45 m from their own position. The garrison does too when 30 or
more infected are at the wall. The banner gives the distance, and a 50 m ring is drawn round the
friendlies. You have 40 seconds to put 20 + 2 × wave of them down. It pays 1,500 + 50 a kill, and 2,000
more if your closest hit landed within 50 m of the friendlies.

Hit the friendlies and it's **blue on blue**: wounded, −1,000 RP, and the call is off. That means a gun
round within 3 m, or anything else within 60% of its fragment radius, so leave the JDAM on the rail.

### The campaign

Each AO's first three days are a short story. A card at each dawn tells you where things stand, and the
radio adds a line in the middle of each day. The wave after day three (wave 16) is the **evacuation**:

- Three Chinooks come in one at a time from the quietest bearing and land inside the refuge.
- Everything left on the AO comes for them, at least 40,000 infected.
- Each bird needs 25 seconds on the ground to load. Loading stops while 60 or more infected are at the
  wall, so keep the wall clear.
- The wave can't end until the last bird is out.

When it is, the sortie ends in **CAMPAIGN COMPLETE** with a 25,000 RP bonus, and the AO is marked
**EVACUATED** on the title screen. You can fly it again any time.

## Settings, controls and controller

Settings (Esc on the title or the pause menu) has three tabs:

- **General:** sensitivity, invert Y, volume, sensor, IR palette, tutorial, dev farm, reset progress.
- **Graphics:** windowed or fullscreen, vsync, render scale (below 100% uses FSR upscaling), MSAA
  off / 2× / 4×, the maximum infected alive (30,000 / 50,000 / 80,000; lower it if the late waves stutter),
  weather effects on the lens.
- **Controls:** click any action and press the key you want for it; a key already in use swaps over.
  Number keys, Space, Esc, F1 and F9 stay fixed.

**Controller:** left stick look, right stick fly (up/down altitude, left/right orbit), right trigger fire,
left trigger zoom in, A point track, B zoom out, X reload / restock, Y tactical map, bumpers previous / next
weapon, D-pad up/down throttle and left/right time compression, Back armory, Start pause, stick clicks
orbit over the sensor / orbit home. In menus the left stick moves the pointer and A clicks.

**Tutorial:** your first sortie walks you through it one step at a time, ticking over as you do each
thing: slew, zoom, fire, weapons, point track, the map, the sensors, the armory, flying, ground ops. Turn
it off or replay it under Settings > General.

## Days

Every five waves is a **day**. The HUD shows `DAY 2   WAVE 7  (2/5)`. Every wave you clear pays out, and
the debrief on the perk screen shows how:

| Reward | When | What |
| --- | --- | --- |
| Wave cleared | every wave | 600 + 400 × wave RP |
| Flawless defence | the refuge lost less than 1% this wave | +50% of that |
| Refuge above 75% | otherwise, if the walls are still mostly standing | +20% |
| Day survived | waves 5, 10, 15... | 2,500 × day RP, **the refuge repaired by 20%**, every system you own restocked, and better perk odds: the first card is rare or better and legendaries are three times as likely |

## The refuge: fortifications and passive defences

The armory's **UPGRADES** tab (key 0) has two columns: the aircraft on the left, the refuge on the right.
Refuge upgrades are permanent and go up at every refuge you defend. The passive defences are built where you
can see them, and pick their own targets, fire real rounds and pay requisition for their kills. Their
kill-feed lines tell you how they're doing.

| Upgrade | Levels | Base RP | Per level |
| --- | --- | --- | --- |
| Fortified walls | 5 | 1,200 | −12% damage from infected at the wall |
| Garrison training | 5 | 1,000 | +25% garrison rate of fire |
| Combat engineers | 4 | 1,500 | +0.04% integrity a second |
| M2 guard towers | 4 | 2,000 | +2 crewed .50 cal towers on the wall, leading the nearest infected inside 650 m |
| Claymore belt | 3 | 2,500 | Mines in front of the wall fire on whatever reaches it, more often per level |
| 81 mm mortar section | 3 | 3,500 | +1 tube dropping HE on the thickest crowd inside 1.6 km |
| Fire trench | 2 | 5,000 | A ring of burning fuel just outside the wall that everything has to cross |
| C-RAM Phalanx | 2 | 8,000 | +1 20 mm Centurion shredding anything inside 450 m |
| M777 battery | 2 | 9,000 | +1 155 mm gun inside the wire, firing on the biggest crowd 1–3 km out |
| Fire direction centre | 3 | 3,000 | Every passive defence fires 15% faster |

Some perks add defences or harden the walls for one sortie: Sandbagged, Fire Control Orders, Counter-Battery
Radar, Engineer Corps, Emergency Towers, Borrowed Mortars, Hold the Line, Fortress and Dawn Patrol (twice
the day-end repair).

## Wave events

From wave 2, about four waves in ten come with a twist, announced on the radio and the banner:

| Event | What happens |
| --- | --- |
| Gold rush | Every kill pays ×3 requisition for 45 s |
| Meteor shower | 30 s of meteors smashing into the horde, 2–3 a second, all credited to you |
| Supply drop | Every system you own is instantly restocked |
| Blood moon | The whole wave walks 40% faster, and pays ×2 |
| Golden piñata | A golden infected sprints for the wall. Pop it for 5,000 RP (more in later waves); let it reach the wall and it escapes with the lot |

## Bosses

From wave 3, a boss joins the horde now and then, more often later, and two or three at once after wave 7.
Each one walks in like the rest, but huge, slow and glowing hotter than anything else on the sensor. It
has hundreds of hit points and armour that shrugs off most of each small-arms hit, so bring heavy weapons.
The HUD brackets it with a health bar, an edge arrow points to it when it's off-screen, and it blinks on the
radar and tactical map. A wave can't end while a boss is alive or still due.

| Boss | From wave | What it does | Bounty |
| --- | --- | --- | --- |
| Behemoth | 3 | 260 HP. A walking wall of meat | 2,500 RP |
| Broodmother | 4 | Sheds 30 fresh infected every 8 s while she walks | 3,000 RP |
| Bloat King | 5 | Kill it in the field and it bursts, killing the crowd around it. Let it reach the wall and it takes 14% of the refuge with it | 2,500 RP |
| The Colossus | 9 | 30 m tall, 1,400 HP. Rare | 15,000 RP |

Boss HP grows 15% per wave past its first, and bounties 10% per wave. At the wall a boss pounds as hard as
150 to 500 ordinary infected. The garrison's rifles only chip at it. A neutron bomb's radiation burns it
down rather than dropping it outright.

### Nuclear weapons

- Hold fire for release consent. The HUD shows your aircraft's clearance and the refuge's distance first.
- On detonation the thermal sensor whites out and the HUD glitches. The blast wave kills ring by ring as it expands.
- Minimum safe distance for your aircraft: Davy Crockett 450 m, B61 900 m, W70 750 m (radiation incapacitates the crew). Airframe Armor and the Armored Hull perk shrink these.
- Shock fronts (B61, Davy Crockett): nothing inside the inner radius survives (B61 900 m, Davy 220 m), and
  past it the odds of living only climb near the outer edge (1.6 km, 420 m). Bodies are thrown outward as
  the front passes. A boss takes a huge hit instead of dropping outright, so a Colossus can walk out of
  one. A B61 within 1.1 km of the refuge costs it integrity.
- Detonating near the refuge kills survivors.
## Flying

Altitude, speed and orbit radius all affect the fight:

- **Low and slow:** shorter range, faster shells and tighter groups. The .50 cal only really works here.
- **High and wide:** a bigger view and safer separation from your own heavy weapons, but every round takes longer to arrive.
- **Bank limit:** the minimum orbit radius grows with the square of your speed.

## CAS mode: Hawg 1-1

**Fly CAS** (C on the title screen) swaps seats. You're Hawg 1-1, an A-10C flying close air support, and
**Spectre 2-1** is flown by the AI:

- It orbits the refuge working the big hordes with its 40 mm, 105 and 25 mm, starting with whatever is at
  the wall.
- It hands you the jobs it can't do. Every half-minute or so you get a **tasking**, shown on the HUD with
  a marker and on the tactical map:
  - a boss its guns barely scratch
  - a nest to bring down
  - a team on the ground to cover, or a dustoff's LZ to clear
  - a crowd in streets it can't see into past the buildings
  - runners slipping past toward the wall
  - a crowd massing out on an approach
- Taskings pay 1,500–4,000 RP. Everything else (waves, missions, danger close, the campaign and the
  evacuation) runs as it does in the gunship.

**Flying.** You go where you look. The mouse turns your head, and the aircraft rolls toward wherever
you're looking and pulls, then levels its wings when you're close. A / D roll it yourself, and holding C
looks around without steering. Underneath it's a real flight model, with lift up to the stall, drag, thrust
and gravity. Pull too hard and slow and it stalls, and the nose drops until it's flying again. Firing the
gun slows you down.

| Input | Action |
| --- | --- |
| Mouse | Look: the A-10 flies where you look |
| LMB | Fire the selected store |
| RMB | Lock a Maverick |
| Mouse wheel | Zoom |
| W / S | Throttle |
| A / D | Roll |
| Space | Speed brakes in the air, wheel brakes on the ground |
| C (hold) | Free look: look around without steering |
| 1–5 / Q E | Select a store |
| Y | Fuze |
| TAB | Tactical map, with Spectre, your tasking and the FARP |
| X | IR / colour TV |

**Stores:**

| Key | Store | Load | How it works |
| --- | --- | --- | --- |
| 1 | GAU-8/A Avenger | 1,150 rounds | 3,900 rpm through the gun cross; the pipper shows where they'll land |
| 2 | Mk-82 500 lb | 4 | Unguided; the CCIP cue shows where a bomb let go now would land |
| 3 | GBU-12 Paveway II | 2 | Laser-guided onto wherever you're looking |
| 4 | AGM-65 Maverick | 2 | Right-click to lock a boss or the thickest crowd under your look, then fire and forget |
| 5 | Hydra 70 | 14 | Unguided rockets down the boresight |

The bombs, Mavericks and rockets have fuzes (Y), as in the gunship.

**The threats.** Nobody is shooting back. What kills Hogs here is:

- **Running out of ammunition.** Call `WINCHESTER` and go home.
- **The ground.** Hills, buildings and masts end the sortie on contact. The nose and both wingtips are
  checked, and the HUD flashes `PULL UP` when the flight path meets something within four seconds.
- **Fuel.** A full tank lasts seven minutes at full throttle, longer throttled back. `BINGO` means you
  have just enough to get home. Run dry and the engines flame out, and you glide.

**The FARP.** One place does everything: the airstrip on the edge of the AO, marked on the HUD and the
map.

- The gear comes down by itself when you're low, slow and descending.
- Land on the runway, wings level and not too steep (the HUD's landing aid outlines the strip and calls
  the glide path), then stop on the runway or apron. Hot pits rearm and refuel you in 18 seconds.
- To take off, open the throttle and look up once you're past 140 kt.
- Touching down anywhere else, or too hard, is a crash, and so is flying into anything.

## How it scales

- **Zombies:** each zombie's position is a pure function of time. The GPU animates up to 80,000 of them, and the CPU only evaluates positions for hit tests and a spatial grid it refreshes a slice at a time. 30,000 zombies cost about 1 ms of CPU per frame.
- **Speeds are human-scale:** shamblers 0.6–1.1 m/s, runners 2.6–3.6 m/s, brutes 0.5–0.8 m/s.
- **Projectiles:** every round leaves a real mount on the aircraft and flies a gravity arc. Bombs fall from the ramp on guided paths to the coordinate you designated at release.

## Sound

Every sound in `sfx/` is synthesised by `tools/gen_sfx.py` (pure Python). To regenerate everything, or only the names you list:

```
python tools/gen_sfx.py sfx
python tools/gen_sfx.py sfx nuke exp_huge
```

To use real recordings instead, drop a file with the same name over the generated one.

## Dev switches

- **Zombie farm** (title screen bottom-right, the pause menu, or **F9** in flight): keeps **10,000 dummies**
  standing still on the approaches, 0.5–2.6 km out, topping them back up as fast as you kill them. They pay
  requisition like any kill, standoff bonus included. They never move, never reach the wall, never count as
  the lead contact and never hold up a wave clear. Turning it off removes them all without a trace. The
  switch is saved with your settings.
- **Reset all progress** (title screen bottom-right, or the pause menu): click once to arm it, then again
  within four seconds. It wipes requisition, rank, owned systems, loadout, best waves and aircraft
  upgrades, keeps your settings, and returns to the title screen.

## Automated test

```
godot --path . --audio-driver Dummy -- --autotest --stress
```

This runs a roughly 12-minute scripted session with 30,000 zombies plus two 2,500-strong mega-hordes. It maxes the refuge
defences, takes colour-TV shots, and fires all 71
systems one by one, spawns a Colossus and a Broodmother in view, opens the loadout, armory, perk screen and
aircraft tab, and saves screenshots to `user://autotest/`. It uses its own
save file, so your career is untouched. Add `--quick` to test only the guns and the laser.

Add `--ao=desert` (or `city`, `port`, `river`, `arctic`, `heaven`) to choose the AO. Other modes take the
place of `--stress`:

| Flag | What it runs |
| --- | --- |
| `--armory` | A B-52 carpet on the ordnance panel, then the purchase ceremony for the GAU-8 and the Atomic Gatling |
| `--missions` | Hold, nest, engineers and medevac in turn, a danger-close call, the evacuation and the campaign victory screen |
| `--cas` | An A-10 sortie: every store, the tactical map, an automatic approach to the FARP, hot pits, takeoff, and a deliberate dive into the ground |
| `--cas-land` | Just the FARP: a long final, the landing, hot pits and the takeoff |
| `--tour` | A 20-second visual tour of one AO: the title, wide, an approach, the refuge, a town and a city block. Add `--tv` for the colour camera, `--noon` or `--night` to hold the clock, and `--day=N` to see the power grid as it is on day N |
