extends RefCounted
## Data for the two progression layers that modify everything else:
##   UPGRADES - permanent aircraft upgrades bought with requisition, kept forever.
##   PERKS    - roguelite picks offered after every wave, kept for the current sortie only.
##
## Both are lists of stat modifiers. Stats are multipliers that start at 1.0 (a value of
## +0.15 means x1.15 per level or stack), except those prefixed "add_", which start at 0
## and simply add up. main.gd folds them all into main.stats; everything else asks
## main.stat("name").
##
## Stats: dmg, radius, rof, reload, ammo, disp, heat, mv, rp, standoff, garrison, speed, climb,
## zoom, noise, support_cd, fire_dps, fire_dur, horde_speed, nuke_safe,
## restock (time for spent ordnance to come back), restock_cost (price of a bought restock),
## wall_dmg (damage the refuge takes from infected at the wall), def_rate (passive defence rate
## of fire), day_repair (repair at the end of each day), add_towers, add_mortars, add_claymores,
## add_trench, add_ciws, add_howitzers (passive defences, see defences.gd),
## add_regen (% integrity / s), add_heal (% per kill), add_slots, add_salvo, add_drones,
## add_crit (chance of a double-radius blast), add_ignite (chance a gun impact starts a fire),
## add_chain (chance a kill detonates).

const RARITY := ["COMMON", "RARE", "LEGENDARY"]
const RARITY_W := [70.0, 25.0, 5.0]

const UPGRADES := [
	{"id": "engines", "name": "T56-A-427 ENGINES", "max": 5, "cost": 900,
		"desc": "+8% top speed and +20% climb rate per level.", "mods": {"speed": 0.08, "climb": 0.2}},
	{"id": "armor", "name": "AIRFRAME ARMOR", "max": 4, "cost": 1500,
		"desc": "Survive your own nuclear detonations 12% closer per level.", "mods": {"nuke_safe": -0.12}},
	{"id": "sensor", "name": "MX-25D SENSOR TURRET", "max": 4, "cost": 1100,
		"desc": "+20% zoom depth and 15% less detector noise per level.", "mods": {"zoom": 0.2, "noise": -0.15}},
	{"id": "fcs", "name": "FIRE-CONTROL COMPUTER", "max": 5, "cost": 1200,
		"desc": "-8% dispersion on every gun and cannon per level.", "mods": {"disp": -0.08}},
	{"id": "loaders", "name": "AUTOLOADERS", "max": 5, "cost": 1500,
		"desc": "-7% reload time and +5% rate of fire per level.", "mods": {"reload": -0.07, "rof": 0.05}},
	{"id": "mags", "name": "MAGAZINES", "max": 5, "cost": 1000,
		"desc": "+12% ammunition for every system per level.", "mods": {"ammo": 0.12}},
	{"id": "cooling", "name": "BARREL COOLING", "max": 5, "cost": 700,
		"desc": "+15% sustained fire before a rotary overheats per level.", "mods": {"heat": 0.15}},
	{"id": "stations", "name": "WEAPON STATIONS", "max": 2, "cost": 6000,
		"desc": "+1 loadout slot per level (keys - and =).", "mods": {"add_slots": 1.0}},
	{"id": "datalink", "name": "LINK-16 DATALINK", "max": 4, "cost": 2000,
		"desc": "-10% fire-support cooldowns and +4% requisition per level.", "mods": {"support_cd": -0.1, "rp": 0.04}},
	{"id": "quartermaster", "name": "QUARTERMASTER", "max": 5, "cost": 1100,
		"desc": "Spent ordnance restocks 12% faster and bought restocks cost 8% less per level.", "mods": {"restock": -0.12, "restock_cost": -0.08}},
	{"id": "radar", "name": "AN/APQ-180 RADAR", "max": 4, "cost": 1800,
		"desc": "Ground-moving-target tracking: +10% standoff bonus and +10% muzzle velocity per level.", "mods": {"standoff": 0.1, "mv": 0.1}},
	{"id": "bms", "name": "BATTLE MANAGEMENT SYSTEM", "max": 4, "cost": 2400,
		"desc": "-8% fire-support cooldowns, +5% blast radius and +5% requisition per level.", "mods": {"support_cd": -0.08, "radius": 0.05, "rp": 0.05}},
]

## The refuge: fortifications and passive defences, bought once and built at every refuge you defend.
const REFUGE := [
	{"id": "walls", "name": "FORTIFIED WALLS", "max": 5, "cost": 1200,
		"desc": "Concrete, rebar and HESCO: the refuge takes 12% less damage from infected at the wall per level.", "mods": {"wall_dmg": -0.12}},
	{"id": "training", "name": "GARRISON TRAINING", "max": 5, "cost": 1000,
		"desc": "+25% garrison rate of fire per level.", "mods": {"garrison": 0.25}},
	{"id": "engineers", "name": "COMBAT ENGINEERS", "max": 4, "cost": 1500,
		"desc": "Repair crews patch the walls: +0.04% integrity per second per level.", "mods": {"add_regen": 0.04}},
	{"id": "towers", "name": "M2 GUARD TOWERS", "max": 4, "cost": 2000,
		"desc": "+2 crewed .50 cal towers per level. Each engages the nearest infected inside 650 m.", "mods": {"add_towers": 2.0}},
	{"id": "claymores", "name": "CLAYMORE BELT", "max": 3, "cost": 2500,
		"desc": "Directional mines in front of the wall. Each level fires them more often at anything that reaches it.", "mods": {"add_claymores": 1.0}},
	{"id": "mortars", "name": "81 MM MORTAR SECTION", "max": 3, "cost": 3500,
		"desc": "+1 mortar tube per level, dropping HE on the thickest crowd inside 1.6 km.", "mods": {"add_mortars": 1.0}},
	{"id": "trench", "name": "FIRE TRENCH", "max": 2, "cost": 5000,
		"desc": "A ring of burning fuel just outside the wall. Everything that crosses it burns; hotter per level.", "mods": {"add_trench": 1.0}},
	{"id": "ciws", "name": "C-RAM PHALANX", "max": 2, "cost": 8000,
		"desc": "+1 20 mm Centurion per level: 4,500 rounds a minute at anything inside 450 m.", "mods": {"add_ciws": 1.0}},
	{"id": "howitzers", "name": "M777 BATTERY", "max": 2, "cost": 9000,
		"desc": "+1 155 mm howitzer per level inside the wire, firing on the biggest crowd 1 to 3 km out.", "mods": {"add_howitzers": 1.0}},
	{"id": "fdc", "name": "FIRE DIRECTION CENTRE", "max": 3, "cost": 3000,
		"desc": "Every passive defence fires 15% faster per level.", "mods": {"def_rate": 0.15}},
]

const PERKS := [
	# ---------------------------------------------------------------- common
	{"id": "hot_loads", "name": "HOT LOADS", "rarity": 0, "desc": "+15% muzzle velocity: shorter flight times.", "mods": {"mv": 0.15}},
	{"id": "steady", "name": "STEADY HANDS", "rarity": 0, "desc": "-15% dispersion.", "mods": {"disp": -0.15}},
	{"id": "quick", "name": "QUICK HANDS", "rarity": 0, "desc": "-15% reload time.", "mods": {"reload": -0.15}},
	{"id": "deep_mags", "name": "DEEP MAGAZINES", "rarity": 0, "desc": "+20% ammunition next resupply.", "mods": {"ammo": 0.2}},
	{"id": "heavy", "name": "HEAVY CHARGES", "rarity": 0, "desc": "+10% blast radius.", "mods": {"radius": 0.1}},
	{"id": "hardened", "name": "HARDENED TIPS", "rarity": 0, "desc": "+15% damage.", "mods": {"dmg": 0.15}},
	{"id": "discipline", "name": "TRIGGER DISCIPLINE", "rarity": 0, "desc": "+25% sustained fire before overheating.", "mods": {"heat": 0.25}},
	{"id": "fast_loaders", "name": "FAST LOADERS", "rarity": 0, "desc": "+8% rate of fire.", "mods": {"rof": 0.08}},
	{"id": "bounty", "name": "BOUNTY", "rarity": 0, "desc": "+10% requisition from kills.", "mods": {"rp": 0.1}},
	{"id": "long_game", "name": "THE LONG GAME", "rarity": 0, "desc": "+20% standoff bonus.", "mods": {"standoff": 0.2}},
	{"id": "sandbags", "name": "SANDBAGS", "rarity": 0, "desc": "The refuge repairs 0.03% integrity per second.", "mods": {"add_regen": 0.03}},
	{"id": "veterans", "name": "VETERAN GARRISON", "rarity": 0, "desc": "The defenders shoot 25% faster.", "mods": {"garrison": 0.25}},
	{"id": "tailwind", "name": "TAILWIND", "rarity": 0, "desc": "+10% top speed, +20% climb.", "mods": {"speed": 0.1, "climb": 0.2}},
	{"id": "optics", "name": "SHARP OPTICS", "rarity": 0, "desc": "+20% zoom depth.", "mods": {"zoom": 0.2}},
	{"id": "priority", "name": "PRIORITY TASKING", "rarity": 0, "desc": "-12% fire-support cooldowns.", "mods": {"support_cd": -0.12}},
	{"id": "accelerant", "name": "ACCELERANT", "rarity": 0, "desc": "Fires burn 30% longer.", "mods": {"fire_dur": 0.3}},
	{"id": "fear", "name": "CRIPPLING FEAR", "rarity": 0, "desc": "New hordes walk 8% slower.", "mods": {"horde_speed": -0.08}},
	{"id": "pods", "name": "EXTRA PODS", "rarity": 0, "desc": "+6 rockets per salvo.", "mods": {"add_salvo": 6.0}},
	{"id": "speedball", "name": "SPEEDBALL", "rarity": 0, "desc": "Spent ordnance restocks 20% faster.", "mods": {"restock": -0.2}},
	{"id": "haggler", "name": "HAGGLER", "rarity": 0, "desc": "Bought restocks cost 25% less.", "mods": {"restock_cost": -0.25}},
	{"id": "ammo_handlers", "name": "AMMO HANDLERS", "rarity": 0, "desc": "+15% ammunition, -10% reload time.", "mods": {"ammo": 0.15, "reload": -0.1}},
	{"id": "sensor_fusion", "name": "SENSOR FUSION", "rarity": 0, "desc": "+12% muzzle velocity, -10% dispersion.", "mods": {"mv": 0.12, "disp": -0.1}},
	{"id": "sandbagged", "name": "SANDBAGGED", "rarity": 0, "desc": "The refuge takes 12% less damage at the wall.", "mods": {"wall_dmg": -0.12}},
	{"id": "fire_control", "name": "FIRE CONTROL ORDERS", "rarity": 0, "desc": "Passive defences fire 15% faster.", "mods": {"def_rate": 0.15}},
	# ---------------------------------------------------------------- rare
	{"id": "shaped", "name": "SHAPED CHARGES", "rarity": 1, "desc": "+20% blast radius.", "mods": {"radius": 0.2}},
	{"id": "overpressure", "name": "OVERPRESSURE", "rarity": 1, "desc": "+30% damage, +5% blast radius.", "mods": {"dmg": 0.3, "radius": 0.05}},
	{"id": "overhaul", "name": "AUTOLOADER OVERHAUL", "rarity": 1, "desc": "+18% rate of fire, -10% reload.", "mods": {"rof": 0.18, "reload": -0.1}},
	{"id": "war_chest", "name": "WAR CHEST", "rarity": 1, "desc": "+25% requisition from kills.", "mods": {"rp": 0.25}},
	{"id": "incendiary", "name": "INCENDIARY ROUNDS", "rarity": 1, "desc": "8% of gun impacts start a small fire.", "mods": {"add_ignite": 0.08}},
	{"id": "medics", "name": "FIELD MEDICS", "rarity": 1, "desc": "Every kill restores 0.01% integrity.", "mods": {"add_heal": 0.01}},
	{"id": "swarm", "name": "SWARM LOGIC", "rarity": 1, "desc": "+4 drones or micro-missiles per swarm.", "mods": {"add_drones": 4.0}},
	{"id": "lucky", "name": "LUCKY ROUNDS", "rarity": 1, "desc": "12% of blasts are twice the size.", "mods": {"add_crit": 0.12}},
	{"id": "summer", "name": "NAPALM SUMMER", "rarity": 1, "desc": "Fires burn 50% hotter and 30% longer.", "mods": {"fire_dps": 0.5, "fire_dur": 0.3}},
	{"id": "datalink", "name": "DATALINK UPLINK", "rarity": 1, "desc": "-25% fire-support cooldowns.", "mods": {"support_cd": -0.25}},
	{"id": "slow_burn", "name": "SLOW BURN", "rarity": 1, "desc": "New hordes walk 15% slower.", "mods": {"horde_speed": -0.15}},
	{"id": "cold_barrels", "name": "COLD BARRELS", "rarity": 1, "desc": "+60% sustained fire before overheating.", "mods": {"heat": 0.6}},
	{"id": "mother_lode", "name": "MOTHER LODE", "rarity": 1, "desc": "+40% ammunition next resupply.", "mods": {"ammo": 0.4}},
	{"id": "fortify", "name": "FORTIFY", "rarity": 1, "desc": "Repairs 0.08% integrity per second.", "mods": {"add_regen": 0.08}},
	{"id": "air_bridge", "name": "AIR BRIDGE", "rarity": 1, "desc": "Spent ordnance restocks 40% faster.", "mods": {"restock": -0.4}},
	{"id": "black_market", "name": "BLACK MARKET", "rarity": 1, "desc": "Bought restocks cost half.", "mods": {"restock_cost": -0.5}},
	{"id": "counter_battery", "name": "COUNTER-BATTERY RADAR", "rarity": 1, "desc": "Passive defences fire 35% faster.", "mods": {"def_rate": 0.35}},
	{"id": "engineer_corps", "name": "ENGINEER CORPS", "rarity": 1, "desc": "Repairs 0.06% integrity per second; 20% less damage at the wall.", "mods": {"add_regen": 0.06, "wall_dmg": -0.2}},
	{"id": "jtac", "name": "JTAC ON THE WALL", "rarity": 1, "desc": "-20% fire-support cooldowns, +10% blast radius.", "mods": {"support_cd": -0.2, "radius": 0.1}},
	{"id": "extra_tower", "name": "EMERGENCY TOWERS", "rarity": 1, "desc": "Two more .50 cal towers go up for this sortie.", "mods": {"add_towers": 2.0}},
	{"id": "extra_mortar", "name": "BORROWED MORTARS", "rarity": 1, "desc": "One more mortar tube for this sortie.", "mods": {"add_mortars": 1.0}},
	# ---------------------------------------------------------------- legendary
	{"id": "volatile", "name": "VOLATILE INFECTED", "rarity": 2, "desc": "8% of kills detonate, setting off the ones around them.", "mods": {"add_chain": 0.08}},
	{"id": "divine_wind", "name": "DIVINE WIND", "rarity": 2, "desc": "+50% damage, +25% blast radius.", "mods": {"dmg": 0.5, "radius": 0.25}},
	{"id": "bullet_hell", "name": "BULLET HELL", "rarity": 2, "desc": "+40% rate of fire, +40% heat capacity.", "mods": {"rof": 0.4, "heat": 0.4}},
	{"id": "phantom", "name": "PHANTOM PROTOCOL", "rarity": 2, "desc": "+50% muzzle velocity, -40% dispersion.", "mods": {"mv": 0.5, "disp": -0.4}},
	{"id": "holy", "name": "HOLY ORDNANCE", "rarity": 2, "desc": "+50% requisition, +50% standoff bonus.", "mods": {"rp": 0.5, "standoff": 0.5}},
	{"id": "blessed", "name": "BLESSED WALLS", "rarity": 2, "desc": "Repairs 0.15% integrity per second; garrison +60%.", "mods": {"add_regen": 0.15, "garrison": 0.6}},
	{"id": "hellfire_rain", "name": "HELLFIRE RAIN", "rarity": 2, "desc": "25% of gun impacts ignite; fires burn twice as hot.", "mods": {"add_ignite": 0.25, "fire_dps": 1.0}},
	{"id": "second_coming", "name": "SECOND COMING", "rarity": 2, "desc": "Double ammunition, -40% reload.", "mods": {"ammo": 1.0, "reload": -0.4}},
	{"id": "dilation", "name": "TIME DILATION", "rarity": 2, "desc": "New hordes walk 25% slower.", "mods": {"horde_speed": -0.25}},
	{"id": "chain_reaction", "name": "CHAIN REACTION", "rarity": 2, "desc": "15% of kills detonate; +10% blast radius.", "mods": {"add_chain": 0.15, "radius": 0.1}},
	{"id": "armored", "name": "ARMORED HULL", "rarity": 2, "desc": "Survive your own nukes 40% closer.", "mods": {"nuke_safe": -0.4}},
	{"id": "lucky_star", "name": "LUCKY STAR", "rarity": 2, "desc": "30% of blasts are twice the size.", "mods": {"add_crit": 0.3}},
	{"id": "bottomless", "name": "BOTTOMLESS RACKS", "rarity": 2, "desc": "Spent ordnance restocks 3x faster; +25% ammunition.", "mods": {"restock": -0.67, "ammo": 0.25}},
	{"id": "hold_the_line", "name": "HOLD THE LINE", "rarity": 2, "desc": "40% less damage at the wall; passive defences fire 50% faster.", "mods": {"wall_dmg": -0.4, "def_rate": 0.5}},
	{"id": "dawn_patrol", "name": "DAWN PATROL", "rarity": 2, "desc": "Each day survived repairs the refuge twice as much.", "mods": {"day_repair": 1.0}},
	{"id": "fortress", "name": "FORTRESS", "rarity": 2, "desc": "A Phalanx and a 155 mm gun join the refuge for this sortie.", "mods": {"add_ciws": 1.0, "add_howitzers": 1.0}},
]


static func upgrade(id: String) -> Dictionary:
	for u in UPGRADES:
		if u["id"] == id:
			return u
	for u in REFUGE:
		if u["id"] == id:
			return u
	return {}


static func perk(id: String) -> Dictionary:
	for p in PERKS:
		if p["id"] == id:
			return p
	return {}


## Requisition cost of the next level of an upgrade.
static func upgrade_cost(u: Dictionary, level: int) -> int:
	return int(round(float(u["cost"]) * pow(level + 1.0, 1.6) / 50.0)) * 50


## Three distinct rarity-weighted perk offers. At the end of a day the first card is always
## rare or better and legendaries are three times as likely.
static func roll_offers(rng: RandomNumberGenerator, day_end := false) -> Array:
	var out: Array = []
	var tries := 0
	while out.size() < 3 and tries < 100:
		tries += 1
		var roll := rng.randf() * 100.0
		var rarity := 0 if roll < RARITY_W[0] else (1 if roll < RARITY_W[0] + RARITY_W[1] else 2)
		if day_end:
			rarity = 2 if roll < 15.0 else (1 if (roll < 60.0 or out.is_empty()) else rarity)
		var pool: Array = PERKS.filter(func(p: Dictionary) -> bool: return int(p["rarity"]) == rarity)
		var pick: Dictionary = pool[rng.randi() % pool.size()]
		if not pick["id"] in out:
			out.append(pick["id"])
	return out
