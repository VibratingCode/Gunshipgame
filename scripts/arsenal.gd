extends Node3D
## The weapon suite: 57 systems in eight categories, from twin .50 cals to dropping a moon.
##
## Every gun round leaves a real mount on the moving aircraft and flies a gravity arc solved
## by the fire-control computer. Bombs fall from the ramp on guided paths to the coordinate
## under the crosshair at release. Call-ins (artillery, rockets, wingmen, satellites) arrive
## from where they really come from. Nothing is hitscan except light itself.
##
## `weapons` is the whole catalogue. `owned` persists between sorties (see main.gd);
## `loadout` is the 10-12 systems actually aboard for this sortie (keys 1-9, 0, -, =).

const MeshKit = preload("res://scripts/mesh_kit.gd")
const G := 9.8
const SLOTS := 10
const CATS := ["GUNS", "CANNONS", "ROCKETS & MISSILES", "BOMBS", "FIRE SUPPORT", "EXPERIMENTAL", "STRATEGIC", "SHENANIGANS"]
# Blast size in kg of TNT equivalent: the explosive fill (with its RE factor) for explosives,
# impact energy / 4.184 MJ for kinetic weapons. Sizes the ground shock ring (fx.shock).
# Anything not listed (ball ammo, lasers, fire, nukes with their own recipe) gets no ring.
const TNT_KG := {
	# guns: HE fill per round
	"m197": 0.01, "vulcan": 0.01, "gau12": 0.03, "gau8": 0.06, "gsh630": 0.05, "smart": 0.06,
	"ricochet": 0.03, "rico": 0.02, "scatter": 0.1, "bomblet": 0.1, "auric": 0.06,
	"godgun": 400.0,      # small orbital rods, ~1.7 GJ each
	"atomic": 600.0,      # "micro-nukes", sized to taste
	# cannons
	"bofors": 0.09, "bushmaster": 0.04, "l70": 0.12, "m102": 2.2, "pgk": 2.2, "beehive": 0.1, "wp105": 1.0,
	"m230": 0.04, "chain": 0.05,
	# rockets and missiles
	"hydra": 1.4, "hydra_ah": 1.4, "apkws": 1.4, "griffin": 2.7, "hellfire": 5.0, "jagm": 6.0,
	"micro": 0.5, "switchblade": 3.0, "tomahawk": 300.0,
	# bombs
	"sdb": 23.0, "gbu12": 120.0, "stormbreaker": 15.0, "gator": 0.6, "cbu": 1.0, "jdam": 550.0,
	"daisy": 6800.0, "moab": 11000.0, "mk82": 120.0, "gbu38": 120.0,
	# fire support
	"arty": 7.0, "gmlrs": 30.0,
	# kinetic: impact energy as TNT
	"lazydog": 0.002,     # 0.2 kg dart at 300 m/s
	"rail": 11.0,         # 10 kg slug at 3 km/s, 45 MJ
	"thor": 9700.0,       # 9 t tungsten at Mach 9, 40 GJ
	"constellation": 9700.0,
	"lrhw": 4000.0,       # 1 t glide body at Mach 17
	"mop": 3200.0,        # 2.4 t of AFX-757
	"meteor": 2000.0,
	"cow": 0.46,          # 600 kg at 80 m/s
	"piano": 0.54,        # 450 kg at 100 m/s
	"boulder": 5600.0,    # 15 m of granite at 100 m/s
}


func tnt_of(w: Dictionary) -> float:
	return float(TNT_KG.get(String(w.get("id", "")), -1.0))


# Fuze settings, cycled with the fuze key; the first is what the weapon comes set to.
#   IMPACT:   point detonating, the all-rounder.
#   AIRBURST: proximity, a few metres up: fragments rain over a much wider circle, but each one is
#             light, so it shreds crowds in the open and barely scratches a boss or a building.
#   DELAY:    it goes in before it goes off: little blast escapes sideways, but buried in a boss it
#             tears it apart, and inside a building it brings the building down.
const FUZES := {
	"bofors": ["IMPACT", "AIRBURST"], "bushmaster": ["AIRBURST", "IMPACT"], "l70": ["IMPACT", "AIRBURST", "DELAY"],
	"m102": ["IMPACT", "AIRBURST", "DELAY"], "pgk": ["IMPACT", "AIRBURST", "DELAY"], "wp105": ["IMPACT", "AIRBURST"],
	"hydra": ["IMPACT", "AIRBURST"], "apkws": ["IMPACT", "AIRBURST"], "griffin": ["IMPACT", "AIRBURST", "DELAY"],
	"hellfire": ["IMPACT", "DELAY"], "jagm": ["IMPACT", "AIRBURST", "DELAY"], "tomahawk": ["IMPACT", "AIRBURST", "DELAY"],
	"sdb": ["IMPACT", "AIRBURST", "DELAY"], "gbu12": ["IMPACT", "AIRBURST", "DELAY"], "stormbreaker": ["IMPACT", "AIRBURST", "DELAY"],
	"jdam": ["IMPACT", "AIRBURST", "DELAY"], "daisy": ["AIRBURST", "IMPACT"], "moab": ["AIRBURST", "IMPACT"], "mop": ["DELAY", "IMPACT"],
	# the A-10's own stores (CAS mode)
	"cas_mk82": ["IMPACT", "AIRBURST", "DELAY"], "cas_gbu12": ["IMPACT", "AIRBURST", "DELAY"], "cas_agm65": ["IMPACT", "DELAY"],
	"cas_hydra": ["IMPACT", "AIRBURST"],
}
# how high a laser-guided missile lofts before its terminal dive, as a fraction of the ground range
const LOFT := {"hellfire": 0.35, "jagm": 0.35, "griffin": 0.25}
# what each setting does to the blast: kill radius, fragment radius, damage, fling, structural
# damage and damage to a boss it's buried in, as multipliers
const FUZE_FX := {
	"IMPACT": {"kill": 1.0, "frag": 1.0, "dmg": 1.0, "fling": 1.0, "struct": 1.0, "boss": 1.0, "tag": "PD"},
	"AIRBURST": {"kill": 0.55, "frag": 1.55, "dmg": 0.7, "fling": 0.6, "struct": 0.25, "boss": 1.0, "tag": "AB"},
	"DELAY": {"kill": 0.5, "frag": 0.45, "dmg": 1.0, "fling": 1.6, "struct": 3.5, "boss": 3.0, "tag": "DLY"},
}


func fuzes_of(w: Dictionary) -> Array:
	return FUZES.get(String(w.get("id", "")), [])


## The weapon's current fuze setting, or "" if it has no choice of fuze.
func fuze_of(w: Dictionary) -> String:
	var f: Array = fuzes_of(w)
	if f.is_empty():
		return ""
	return String(f[clampi(int(w.get("fuze", 0)), 0, f.size() - 1)])


func fuze_fx(fuze: String) -> Dictionary:
	return FUZE_FX.get(fuze, FUZE_FX["IMPACT"])


## The fuze key: step the selected weapon to its next fuze setting.
func cycle_fuze() -> void:
	var w := current()
	var f: Array = fuzes_of(w)
	if f.size() < 2:
		main.sfx.play("switch", -10.0, 0.7)
		return
	w["fuze"] = (int(w.get("fuze", 0)) + 1) % f.size()
	main.sfx.play("clip", -8.0, 1.4)
	var lines := {"IMPACT": "Fuze impact. Point detonating.", "AIRBURST": "Fuze proximity. It'll burst over their heads.", "DELAY": "Fuze delay. It goes in before it goes off."}
	main.radio("FCO", "%s: %s" % [String(w["short"]), String(lines[fuze_of(w)])])


const TIER_RP :=[0, 1500, 4000, 9000, 16000, 26000, 40000, 60000]
# Every category is a ladder, cheapest and most down-to-earth first, the outrageous at the top.
# You can only buy a rung once you own the one below it. [id, price]; rung 0 of GUNS is free.
const LADDERS := [
	# GUNS
	[["m2", 0], ["gau19", 0], ["m134", 400], ["m197", 900], ["gau12", 1600], ["vulcan", 2600], ["gau8", 4200],
		["gsh630", 6500], ["smart", 9000], ["ricochet", 12000], ["scatter", 16000], ["ripsaw", 21000], ["lasermg", 27000],
		["tesla", 34000], ["auric", 42000], ["chrono", 52000], ["graviton", 64000], ["godgun", 80000], ["atomic", 100000]],
	# CANNONS
	[["bofors", 500], ["bushmaster", 1200], ["l70", 2400], ["m102", 4000], ["pgk", 6500], ["beehive", 10000], ["wp105", 15000]],
	# ROCKETS & MISSILES
	[["hydra", 700], ["apkws", 1500], ["griffin", 2500], ["hellfire", 4000], ["jagm", 6500], ["micro", 10000], ["switchblade", 15000], ["tomahawk", 22000]],
	# BOMBS
	[["sdb", 1200], ["gbu12", 2000], ["stormbreaker", 3200], ["lazydog", 4500], ["napalm", 6000], ["thermite", 8000],
		["gator", 10500], ["cbu", 13500], ["jdam", 17500], ["daisy", 24000], ["moab", 33000]],
	# FIRE SUPPORT
	[["a10", 1500], ["arty", 3000], ["cas", 4800], ["apache", 7500], ["himars", 11000], ["wingman", 15000], ["tos", 20000], ["b52", 28000]],
	# EXPERIMENTAL
	[["ahel", 5000], ["hpm", 8000], ["rail", 11500], ["glocke", 16000], ["thor", 22000], ["sol", 30000], ["singularity", 40000]],
	# STRATEGIC
	[["lrhw", 20000], ["davy", 28000], ["mop", 36000], ["constellation", 46000], ["neutron", 58000], ["nuke", 75000]],
	# SHENANIGANS
	[["cow", 1000], ["piano", 3000], ["boulder", 8000], ["titan", 25000], ["moon", 120000]],
]
const CONSENT_KINDS := ["nuke", "neutron", "davy", "moon"]
# call-ins whose cooldowns the datalink and support perks shorten
const SUPPORT_KINDS := ["a10", "arty", "wingman", "tos", "apache", "b52", "glocke", "singularity", "orbital", "sol", "constellation", "titan", "cas", "himars"]
# Nothing runs dry for good. Seconds to restock a whole load from empty, by category
# (guns reload and lasers recharge instead), and per-unit times for the big single items.
const RESTOCK_FULL := [0.0, 150.0, 120.0, 150.0, 180.0, 150.0, 300.0, 150.0]
const RESTOCK_UNIT := {"tomahawk": 90.0, "moab": 180.0, "daisy": 180.0, "wingman": 150.0, "b52": 240.0,
	"thor": 120.0, "sol": 180.0, "glocke": 180.0, "singularity": 180.0,
	"davy": 240.0, "nuke": 420.0, "neutron": 540.0, "constellation": 480.0,
	"titan": 200.0, "moon": 900.0, "mop": 360.0, "lrhw": 200.0}
# share of a system's purchase price that buys a full restock right now, by category
const RESTOCK_K := [0.0, 0.15, 0.15, 0.18, 0.2, 0.2, 0.3, 0.2]

var main
var cur := 0
var weapons: Array = []
var loadout: Array = []
var hidden := {}
var pending: Array = []
var missiles: Array = []
var bombs: Array = []
var rods: Array = []
var drones: Array = []
var mines: Array = []
var zones: Array = []
var missions: Array = []
var wingman: Dictionary = {}
var sol: Dictionary = {}
var consent := 0.0
var rail_charge := 0.0
var zone_tick := 0.0
var snd_ctr := 0
var laser_kill_acc := 0
var beam_on := false
var beam_pitch := 1.0
var laser_popup_t := 0.0

var glocke: Dictionary = {}
var apaches: Dictionary = {}
var b52: Dictionary = {}
var bolt_nodes: Array[MeshInstance3D] = []
var bolt_until := PackedFloat32Array()
var bolt_i := 0
var bell_mesh: ArrayMesh
var heli_mesh: ArrayMesh
var bomber_mesh: ArrayMesh
# shenanigans
var cow_mesh: ArrayMesh
var boulder_mesh: ArrayMesh
var titan_mesh: ArrayMesh
var mat_titan: ShaderMaterial
var boulders: Array = []
var titan: Dictionary = {}
var moon: Dictionary = {}
var jets: Array = []

var a10: Dictionary = {}
var a10_mesh: ArrayMesh
var gunship_mesh: ArrayMesh
var mat_world: ShaderMaterial
var mat_hot: ShaderMaterial
var mat_bomb: ShaderMaterial
var mat_beam: ShaderMaterial
var missile_mesh: BoxMesh
var drone_mesh: BoxMesh
var beam_node: MeshInstance3D
var sol_node: MeshInstance3D


static func _w(d: Dictionary) -> Dictionary:
	var base := {
		"owned": false, "price": 0, "tier": 1, "cat": 0, "interval": 0.0, "cd": 0.0, "rt": 0.0, "reload": 0.0,
		"spin": 0.0, "acc": 0.0, "temp": 0.0, "hot": false, "looping": false, "spun_snd": false,
		"disp": 0.0, "tw": 0.1, "heat": 1.2, "streak": 0.03, "off": Vector3(2.4, -1.0, 0.0),
		"ff": 1.0, "vol": 0.0, "snd": "", "snd_every": 1, "fx": 1, "fling": 5.0, "mv": 500.0,
		"r_kill": 1.0, "r_frag": 2.0, "dmg": 1.0, "max": 1, "desc": "", "restock_acc": 0.0,
	}
	base.merge(d, true)
	base["ammo"] = base["max"]
	return base


func _ready() -> void:
	weapons = [
		# ---------------------------------------------------------------- GUNS
		_w({"id": "m2", "name": "M2HB TWIN .50 CAL", "short": ".50", "kind": "auto", "cat": 0, "tier": 1, "owned": true,
			"rate": 14.0, "mv": 890.0, "disp": 0.0034, "r_kill": 1.1, "r_frag": 1.6, "dmg": 1.3, "fling": 2.5,
			"max": 2400, "reload": 6.0, "fx": 7, "tw": 0.04, "heat": 1.1, "streak": 0.02, "off": Vector3(2.3, -1.2, 8.0),
			"ff": 0.05, "snd": "exp_small", "vol": -16.0, "snd_every": 7, "shot": "m2", "shot_vol": -7.0,
			"desc": "Twin heavy machine guns. Cheap and inaccurate from altitude: fly low and slow."}),
		_w({"id": "m134", "name": "M134 MINIGUN", "short": "7.62", "kind": "rotary", "cat": 0, "tier": 1, "price": 300,
			"rate": 100.0, "spin_time": 0.25, "spin_pitch": 1.6, "loop": "minigun_loop", "overheat": 6.0,
			"mv": 850.0, "disp": 0.004, "r_kill": 0.8, "r_frag": 1.1, "dmg": 1.1, "fling": 2.0,
			"max": 4000, "reload": 7.0, "fx": 7, "tw": 0.03, "heat": 1.05, "streak": 0.015, "off": Vector3(2.3, -1.6, 10.0),
			"ff": 0.03, "snd": "exp_small", "vol": -18.0, "snd_every": 12,
			"desc": "Six-barrel 7.62 mm at 6,000 rounds a minute. A hose of hot lead; best on a low pass."}),
		_w({"id": "gau12", "name": "GAU-12/U EQUALIZER", "short": "25MM", "kind": "rotary", "cat": 0, "tier": 1,
			"rate": 30.0, "spin_time": 0.3, "spin_pitch": 1.25, "loop": "gau12_loop", "overheat": 4.5,
			"mv": 1040.0, "disp": 0.003, "r_kill": 2.0, "r_frag": 4.0, "dmg": 3.0, "fling": 4.0,
			"max": 1500, "reload": 9.0, "fx": 8, "tw": 0.05, "heat": 1.2, "streak": 0.02, "off": Vector3(2.4, -1.0, 7.0),
			"ff": 0.12, "snd": "exp_small", "vol": -8.0, "snd_every": 3,
			"desc": "25 mm five-barrel rotary cannon, 1,800 rounds a minute. The AC-130U's workhorse."}),
		_w({"id": "gau8", "name": "GAU-8/A AVENGER", "short": "30MM", "kind": "rotary", "cat": 0, "tier": 2, "price": 1200,
			"rate": 65.0, "spin_time": 0.45, "spin_pitch": 1.0, "loop": "gau8_loop", "overheat": 3.4,
			"mv": 1013.0, "disp": 0.0026, "r_kill": 3.0, "r_frag": 6.0, "dmg": 6.0, "fling": 9.0,
			"max": 1350, "reload": 11.0, "fx": 0, "tw": 0.07, "heat": 1.25, "streak": 0.025, "off": Vector3(2.4, -1.0, 6.0),
			"ff": 0.3, "snd": "exp_small", "vol": -2.0, "snd_every": 3,
			"desc": "The A-10's 30 mm, 3,900 rounds a minute. Every HEI round's blast kills all within 3 m."}),
		_w({"id": "gau19", "name": "GAU-19/A .50 GATLING", "short": "GAU19", "kind": "rotary", "cat": 0, "tier": 1, "owned": true,
			"rate": 22.0, "spin_time": 0.35, "spin_pitch": 0.9, "loop": "minigun_loop", "loop_pitch": 0.72, "overheat": 7.0,
			"mv": 890.0, "disp": 0.0026, "r_kill": 1.2, "r_frag": 1.8, "dmg": 1.6, "fling": 3.0,
			"max": 1500, "reload": 7.0, "fx": 7, "tw": 0.045, "heat": 1.1, "streak": 0.02, "off": Vector3(2.3, -1.3, 9.0),
			"ff": 0.06, "snd": "exp_small", "vol": -14.0, "snd_every": 8,
			"desc": "Three-barrel .50 cal, 1,300 rounds a minute. Far steadier than the twin M2s."}),
		_w({"id": "m197", "name": "M197 20MM GATLING", "short": "M197", "kind": "rotary", "cat": 0, "tier": 2, "price": 1100,
			"rate": 18.0, "spin_time": 0.3, "spin_pitch": 1.1, "loop": "gau12_loop", "loop_pitch": 0.8, "overheat": 6.0,
			"mv": 1030.0, "disp": 0.0022, "r_kill": 1.9, "r_frag": 3.8, "dmg": 3.0, "fling": 4.0,
			"max": 1000, "reload": 7.0, "fx": 8, "tw": 0.05, "heat": 1.2, "streak": 0.02, "off": Vector3(2.4, -1.1, 7.0),
			"ff": 0.1, "snd": "exp_small", "vol": -9.0, "snd_every": 3,
			"desc": "Your first real cannon: three-barrel 20 mm HE, 1,100 well-aimed rounds a minute."}),
		_w({"id": "gsh630", "name": "GSh-6-30 30MM", "short": "GSh30", "kind": "rotary", "cat": 0, "tier": 4, "price": 4800,
			"rate": 80.0, "spin_time": 0.3, "spin_pitch": 1.15, "loop": "gau8_loop", "loop_pitch": 1.25, "overheat": 2.6,
			"mv": 900.0, "disp": 0.0032, "r_kill": 3.2, "r_frag": 6.4, "dmg": 7.0, "fling": 10.0,
			"max": 1100, "reload": 11.0, "fx": 0, "tw": 0.07, "heat": 1.25, "streak": 0.025, "off": Vector3(2.4, -1.0, 6.0),
			"ff": 0.3, "snd": "exp_small", "vol": -3.0, "snd_every": 3,
			"desc": "The Soviet answer to the Avenger: 4,800 rounds a minute of bigger 30 mm. Overheats fast: fire in bursts."}),
		# ---------------------------------------------------------------- CANNONS
		_w({"id": "bofors", "name": "L/60 BOFORS", "short": "40MM", "kind": "cannon", "cat": 1, "tier": 1, "price": 400,
			"mv": 875.0, "disp": 0.0011, "r_kill": 4.5, "r_frag": 10.0, "dmg": 5.0, "fling": 11.0,
			"max": 256, "clip": 4, "inclip": 4, "clip_t": 1.7, "clip_rt": 0.0, "interval": 0.5,
			"fx": 1, "tw": 0.2, "heat": 1.4, "off": Vector3(2.4, -0.8, -2.0), "ff": 1.5, "snd": "exp_med", "vol": 4.0,
			"desc": "40 mm autocannon fed by hand in four-round clips. Each round clears a knot of them."}),
		_w({"id": "m102", "name": "M102 HOWITZER", "short": "105MM", "kind": "cannon", "cat": 1, "tier": 3, "price": 2200,
			"mv": 494.0, "disp": 0.0007, "r_kill": 14.0, "r_frag": 32.0, "dmg": 30.0, "fling": 22.0,
			"max": 100, "interval": 3.5, "fx": 2, "tw": 0.45, "heat": 1.6, "streak": 0.04, "off": Vector3(2.6, -0.5, -9.0),
			"ff": 9.0, "snd": "exp_large", "vol": 10.0,
			"desc": "THE gunship gun. A 105 mm howitzer out the side door: 3-4 s time of flight, an enormous blast."}),
		_w({"id": "beehive", "name": "M546 BEEHIVE", "short": "APERS", "kind": "cannon", "cat": 1, "tier": 4, "price": 4000,
			"mv": 494.0, "disp": 0.0007, "r_kill": 12.0, "r_frag": 12.0, "dmg": 6.0, "fling": 7.0,
			"max": 40, "interval": 3.0, "fx": 7, "tw": 0.4, "heat": 1.5, "streak": 0.04, "off": Vector3(2.6, -0.5, -9.0),
			"ff": 3.0, "snd": "exp_small", "vol": 6.0,
			"desc": "105 mm flechette round. Bursts short and rakes a 100 m lane with 8,000 steel darts."}),
		_w({"id": "l70", "name": "L/70 BOFORS 40MM 3P", "short": "40L70", "kind": "cannon", "cat": 1, "tier": 3, "price": 3000,
			"mv": 1000.0, "disp": 0.0009, "r_kill": 4.2, "r_frag": 9.5, "dmg": 5.0, "fling": 11.0,
			"max": 300, "interval": 0.25, "fx": 1, "tw": 0.18, "heat": 1.4, "off": Vector3(2.4, -0.8, -2.0), "ff": 1.5,
			"snd": "exp_med", "vol": 2.0, "snd_every": 2, "snd_fire": "bofors", "fire_pitch": 1.12, "fire_vol": -2.0, "kick": 0.25,
			"desc": "Belt-fed 40 mm with programmable 3P proximity rounds, 240 a minute."}),
		_w({"id": "pgk", "name": "M102 105MM + PGK", "short": "105PG", "kind": "cannon", "cat": 1, "tier": 4, "price": 5200,
			"mv": 494.0, "disp": 0.00004, "r_kill": 15.0, "r_frag": 34.0, "dmg": 34.0, "fling": 24.0,
			"max": 60, "interval": 2.8, "fx": 2, "tw": 0.45, "heat": 1.6, "streak": 0.04, "off": Vector3(2.6, -0.5, -9.0),
			"ff": 9.0, "snd": "exp_large", "vol": 10.0, "manual": true, "kick": 1.0,
			"desc": "105 mm with a precision guidance kit fuze: GPS-steered, lands within a metre of the crosshair."}),
		# ---------------------------------------------------------------- ROCKETS & MISSILES
		_w({"id": "hydra", "name": "HYDRA 70 ROCKET POD", "short": "FFAR", "kind": "rockets", "cat": 2, "tier": 2, "price": 700,
			"mv": 700.0, "disp": 0.012, "r_kill": 3.5, "r_frag": 9.0, "dmg": 6.0, "fling": 10.0, "salvo": 19,
			"max": 76, "interval": 4.0, "fx": 1, "ff": 1.5, "snd": "exp_med", "vol": 0.0, "snd_every": 2,
			"desc": "Nineteen unguided 2.75 in rockets rippled in 1.4 seconds. Wildly inaccurate, wildly fun."}),
		_w({"id": "hellfire", "name": "AGM-114 HELLFIRE", "short": "AGM", "kind": "missile", "cat": 2, "tier": 3, "price": 3500,
			"mv": 425.0, "r_kill": 8.0, "r_frag": 18.0, "dmg": 20.0, "fling": 17.0,
			"max": 8, "interval": 1.5, "fx": 3, "ff": 6.0, "snd": "exp_large", "vol": 8.0,
			"desc": "Laser-guided missile. It flies to whatever is under your crosshair: keep the laser on it."}),
		_w({"id": "switchblade", "name": "SWITCHBLADE 600 SWARM", "short": "LM", "kind": "drones", "cat": 2, "tier": 5, "price": 9000,
			"mv": 110.0, "r_kill": 7.0, "r_frag": 15.0, "dmg": 12.0, "fling": 14.0, "salvo": 14,
			"max": 28, "interval": 6.0, "fx": 3, "ff": 4.0, "snd": "exp_med", "vol": 4.0,
			"desc": "Fourteen loitering munitions. They circle over your mark, each picks a crowd none of the others has, and they dive one after another."}),
		_w({"id": "tomahawk", "name": "BGM-109 TOMAHAWK", "short": "TLAM", "kind": "cruise", "cat": 2, "tier": 6, "price": 13000,
			"mv": 450.0, "r_kill": 26.0, "r_frag": 60.0, "dmg": 60.0, "fling": 30.0,
			"max": 2, "interval": 5.0, "fx": 12, "ff": 25.0, "snd": "exp_huge", "vol": 14.0,
			"desc": "Cruise missile from a destroyer offshore. Hugs the rooftops, pops up and dives."}),
		_w({"id": "apkws", "name": "APKWS II", "short": "APKWS", "kind": "missile", "cat": 2, "tier": 2, "price": 1800,
			"mv": 600.0, "r_kill": 4.0, "r_frag": 9.0, "dmg": 7.0, "fling": 10.0,
			"max": 28, "interval": 0.5, "fx": 1, "ff": 1.5, "snd": "exp_med", "vol": 0.0,
			"desc": "A Hydra with a laser seeker bolted on. Cheap, plentiful, and goes where you point."}),
		_w({"id": "jagm", "name": "AGM-179 JAGM", "short": "JAGM", "kind": "missile", "cat": 2, "tier": 4, "price": 5500,
			"mv": 425.0, "r_kill": 10.0, "r_frag": 22.0, "dmg": 25.0, "fling": 18.0,
			"max": 12, "interval": 1.2, "fx": 3, "ff": 7.0, "snd": "exp_large", "vol": 9.0,
			"desc": "Hellfire's successor: dual-mode seeker and a heavier warhead. Twelve on the rails."}),
		# ---------------------------------------------------------------- BOMBS
		_w({"id": "lazydog", "name": "LAZY DOG DART CANISTER", "short": "DART", "kind": "darts", "cat": 3, "tier": 3, "price": 2600,
			"tof_base": 2.5, "tof_speed": 260.0, "mv": 260.0, "len": 2.0, "spread": 75.0,
			"r_kill": 0.0, "r_frag": 75.0, "dmg": 10.0, "fling": 3.0,
			"max": 3, "interval": 2.0, "fx": 7, "ff": 3.0,
			"desc": "Kinetic: a canister of steel darts dropped from height. No explosive, no survivors."}),
		_w({"id": "napalm", "name": "MK-77 INCENDIARY", "short": "FIRE", "kind": "napalm", "cat": 3, "tier": 3, "price": 3000,
			"tof_base": 2.5, "tof_speed": 260.0, "mv": 260.0, "len": 3.0,
			"r_kill": 16.0, "r_frag": 16.0, "dmg": 10.0, "fling": 4.0, "dps": 4.0, "burn": 28.0,
			"max": 3, "interval": 2.0, "fx": 1, "ff": 15.0, "snd": "napalm", "vol": 10.0,
			"desc": "A 160 m strip of fire that burns for half a minute. Everything that walks in, burns."}),
		_w({"id": "sdb", "name": "GBU-39 SDB", "short": "SDB", "kind": "bomb", "cat": 3, "tier": 4, "price": 5000,
			"tof_base": 3.0, "tof_speed": 240.0, "mv": 240.0, "len": 1.8,
			"r_kill": 15.0, "r_frag": 34.0, "dmg": 35.0, "fling": 24.0,
			"max": 6, "interval": 1.0, "fx": 4, "ff": 12.0, "snd": "exp_large", "vol": 12.0,
			"desc": "250 lb GPS glide bomb off the ramp. Six per sortie, lands on the coordinate."}),
		_w({"id": "gator", "name": "CBU-89 GATOR MINES", "short": "MINE", "kind": "mines", "cat": 3, "tier": 4, "price": 5500,
			"tof_base": 2.5, "tof_speed": 260.0, "mv": 260.0, "len": 2.3, "subs": 72, "spread": 85.0,
			"r_kill": 3.5, "r_frag": 8.0, "dmg": 6.0, "fling": 10.0,
			"max": 2, "interval": 3.0, "fx": 1, "ff": 1.0,
			"desc": "Scatters 72 mines across an approach. They wait. The horde walks into them."}),
		_w({"id": "cbu", "name": "CBU-97 SFW", "short": "CBU", "kind": "cluster", "cat": 3, "tier": 5, "price": 8000,
			"tof_base": 2.5, "tof_speed": 260.0, "mv": 260.0, "len": 2.3, "subs": 40, "spread": 70.0,
			"r_kill": 4.0, "r_frag": 10.0, "dmg": 6.0, "fling": 10.0,
			"max": 3, "interval": 2.0, "fx": 1, "ff": 2.0, "snd": "cluster", "vol": 10.0,
			"desc": "Cluster canister: 40 sensor-fuzed skeets rain across a whole block."}),
		_w({"id": "jdam", "name": "GBU-31 JDAM 2000LB", "short": "JDAM", "kind": "bomb", "cat": 3, "tier": 6, "price": 12000,
			"tof_base": 2.5, "tof_speed": 280.0, "mv": 280.0, "len": 3.8,
			"r_kill": 35.0, "r_frag": 80.0, "dmg": 80.0, "fling": 38.0,
			"max": 2, "interval": 3.0, "fx": 5, "ff": 30.0, "snd": "exp_huge", "vol": 16.0,
			"desc": "2,000 lb GPS bomb. Deletes an intersection."}),
		_w({"id": "moab", "name": "GBU-43/B MOAB", "short": "MOAB", "kind": "bomb", "cat": 3, "tier": 7, "price": 22000,
			"tof_base": 5.0, "tof_speed": 170.0, "mv": 170.0, "len": 9.0,
			"r_kill": 90.0, "r_frag": 190.0, "dmg": 120.0, "fling": 55.0,
			"max": 1, "interval": 5.0, "fx": 6, "ff": 60.0, "snd": "exp_huge", "vol": 20.0,
			"desc": "Massive Ordnance Air Blast, extracted out of the cargo ramp. 11 tons."}),
		_w({"id": "gbu12", "name": "GBU-12 PAVEWAY II", "short": "GBU12", "kind": "bomb", "cat": 3, "tier": 3, "price": 3600,
			"tof_base": 3.0, "tof_speed": 230.0, "mv": 230.0, "len": 3.3,
			"r_kill": 20.0, "r_frag": 45.0, "dmg": 45.0, "fling": 26.0,
			"max": 4, "interval": 1.5, "fx": 4, "ff": 15.0, "snd": "exp_large", "vol": 12.0,
			"desc": "500 lb laser-guided bomb. The workhorse."}),
		_w({"id": "stormbreaker", "name": "GBU-53/B STORMBREAKER", "short": "SDB-II", "kind": "bomb", "cat": 3, "tier": 5, "price": 9500,
			"tof_base": 3.0, "tof_speed": 220.0, "mv": 220.0, "len": 1.8, "track": true,
			"r_kill": 18.0, "r_frag": 40.0, "dmg": 40.0, "fling": 24.0,
			"max": 8, "interval": 0.6, "fx": 4, "ff": 10.0, "snd": "exp_large", "vol": 10.0,
			"desc": "Tri-mode seeker glide bomb. It follows a moving target: point-track one (T) or it picks its own."}),
		# ---------------------------------------------------------------- FIRE SUPPORT
		_w({"id": "a10", "name": "A-10C HAWG GUN RUN", "short": "HAWG", "kind": "a10", "cat": 4, "tier": 2, "price": 1800,
			"max": 3, "interval": 45.0, "r_kill": 3.0, "r_frag": 6.0, "mv": 1200.0,
			"desc": "Hawg 1-1 strafes the column under your crosshair. Also on G."}),
		_w({"id": "arty", "name": "M777 155MM FIRE MISSION", "short": "155", "kind": "arty", "cat": 4, "tier": 3, "price": 3200,
			"max": 2, "interval": 25.0, "r_kill": 14.0, "r_frag": 32.0, "mv": 800.0,
			"desc": "A battery 12 km away fires eighteen rounds onto your mark. Shot, over. Splash, over."}),
		_w({"id": "wingman", "name": "SPECTRE 2-2 WINGMAN", "short": "2-2", "kind": "wingman", "cat": 4, "tier": 5, "price": 10000,
			"max": 1, "interval": 60.0, "r_kill": 4.5, "r_frag": 10.0, "mv": 875.0,
			"desc": "A second gunship joins the orbit for 50 s and hunts the biggest crowds on its own."}),
		_w({"id": "tos", "name": "TOS-1A THERMOBARIC SALVO", "short": "TOS", "kind": "tos", "cat": 4, "tier": 6, "price": 15000,
			"max": 1, "interval": 30.0, "r_kill": 18.0, "r_frag": 38.0, "mv": 600.0,
			"desc": "Twenty-four thermobaric rockets from a launcher on the ridge. A grid square of fire."}),
		_w({"id": "cas", "name": "F-16 CAS TWO-SHIP", "short": "VIPER", "kind": "cas", "cat": 4, "tier": 3, "price": 4200,
			"max": 2, "interval": 30.0, "r_kill": 15.0, "r_frag": 34.0, "mv": 230.0,
			"desc": "Two Vipers run in along the approach and walk eight GBU-38s through your mark."}),
		_w({"id": "himars", "name": "M142 HIMARS GMLRS", "short": "GMLRS", "kind": "himars", "cat": 4, "tier": 5, "price": 11000,
			"max": 2, "interval": 30.0, "r_kill": 18.0, "r_frag": 40.0, "mv": 1200.0,
			"desc": "Six GPS-guided rockets from 70 km away, each a 200 lb warhead, in a ring around your mark."}),
		# ---------------------------------------------------------------- EXPERIMENTAL
		_w({"id": "ahel", "name": "AHEL HIGH-ENERGY LASER", "short": "LASER", "kind": "laser", "cat": 5, "tier": 4, "price": 6500,
			"r_kill": 2.6, "r_frag": 2.6, "dps": 9.0, "cap": 9.0, "recharge": 0.6, "charge": 9.0, "mv": 299792458.0,
			"max": 100, "fx": 7, "ff": 0.02, "off": Vector3(1.5, -2.0, 12.0),
			"desc": "Airborne laser. Speed-of-light, zero spread: sweep the beam and cut through them."}),
		_w({"id": "rail", "name": "EM RAILGUN", "short": "RAIL", "kind": "rail", "cat": 5, "tier": 5, "price": 11000,
			"mv": 3000.0, "disp": 0.0003, "r_kill": 2.8, "r_frag": 2.8, "dmg": 60.0, "fling": 30.0, "trench": 260.0,
			"max": 12, "interval": 3.5, "fx": 1, "tw": 0.6, "heat": 2.5, "streak": 0.05, "off": Vector3(2.0, -1.0, 4.0),
			"ff": 6.0, "snd": "exp_med", "vol": 8.0,
			"desc": "Hold to charge. A Mach 9 slug that skips along the ground and ploughs a 260 m trench."}),
		_w({"id": "thor", "name": "THOR KINETIC ROD", "short": "ROD", "kind": "orbital", "cat": 5, "tier": 6, "price": 16000,
			"delay": 8.0, "mv": 3000.0, "r_kill": 45.0, "r_frag": 110.0, "dmg": 90.0, "fling": 50.0,
			"max": 2, "interval": 12.0, "fx": 9, "ff": 40.0, "snd": "exp_huge", "vol": 18.0,
			"desc": "Orbital tungsten rod. Eight seconds after designation it arrives at Mach 9."}),
		_w({"id": "sol", "name": "SOL ORBITAL LASER", "short": "SOL", "kind": "sol", "cat": 5, "tier": 7, "price": 26000,
			"r_kill": 10.0, "r_frag": 10.0, "dps": 30.0, "dur": 12.0, "mv": 299792458.0,
			"max": 1, "interval": 20.0, "fx": 1, "ff": 3.0,
			"desc": "A beam from orbit for twelve seconds. It follows your crosshair. Draw with it."}),
		_w({"id": "hpm", "name": "HIGH-POWER MICROWAVE", "short": "HPM", "kind": "laser", "cat": 5, "tier": 5, "price": 12500, "hpm": true,
			"r_kill": 32.0, "r_frag": 32.0, "dps": 2.4, "cap": 7.0, "recharge": 0.5, "charge": 7.0, "mv": 299792458.0,
			"max": 100, "fx": 7, "ff": 0.0, "off": Vector3(0.0, -2.0, 4.0),
			"desc": "An invisible 30 m cone of microwaves. Hold it on a crowd and everything inside cooks."}),
		# ---------------------------------------------------------------- STRATEGIC
		_w({"id": "davy", "name": "M388 DAVY CROCKETT", "short": "M388", "kind": "davy", "cat": 6, "tier": 6, "price": 18000,
			"mv": 300.0, "disp": 0.001, "r_kill": 220.0, "r_frag": 420.0, "dmg": 200.0, "fling": 30.0,
			"max": 2, "interval": 8.0, "fx_scale": 0.42, "air_lethal": 450.0, "ff_max": 50.0, "ff_range": 450.0,
			"consent_t": 1.0, "pitch": 1.45, "tw": 0.3, "heat": 1.4, "streak": 0.04, "off": Vector3(2.6, -0.5, -9.0),
			"ff": 0.0, "snd": "nuke", "vol": 12.0,
			"desc": "A 20-ton micro-nuke fired out of the howitzer tube. Yes, really. Hold fire 1 s."}),
		_w({"id": "nuke", "name": "B61-12 TACTICAL NUKE", "short": "B61", "kind": "nuke", "cat": 6, "tier": 7, "price": 30000,
			"tof_base": 4.0, "tof_speed": 220.0, "mv": 220.0, "len": 3.6,
			"r_kill": 900.0, "r_frag": 1600.0, "dmg": 200.0, "fling": 55.0,
			"max": 1, "interval": 10.0, "fx_scale": 1.4, "air_lethal": 900.0, "ff_max": 85.0, "ff_range": 1100.0,
			"consent_t": 2.5, "ff": 0.0, "snd": "nuke", "vol": 18.0,
			"desc": "10 kt. The shock wave flattens everything for 900 m and nearly everything to 1.6 km. Hold fire 2.5 s."}),
		_w({"id": "neutron", "name": "W70 NEUTRON BOMB", "short": "ERW", "kind": "neutron", "cat": 6, "tier": 8, "price": 45000,
			"tof_base": 4.0, "tof_speed": 220.0, "mv": 220.0, "len": 3.0,
			"r_kill": 150.0, "r_frag": 1100.0, "dmg": 200.0, "fling": 10.0,
			"max": 1, "interval": 10.0, "fx_scale": 0.45, "air_lethal": 750.0, "ff_max": 80.0, "ff_range": 1100.0,
			"consent_t": 2.5, "ff": 0.0, "snd": "neutron", "vol": 16.0,
			"desc": "Enhanced radiation. A small blast, then everything alive within 1.1 km drops. Buildings stand."}),
		_w({"id": "mop", "name": "GBU-57 MOP", "short": "MOP", "kind": "bomb", "cat": 6, "tier": 7, "price": 34000,
			"tof_base": 6.0, "tof_speed": 160.0, "mv": 160.0, "len": 6.2,
			"r_kill": 120.0, "r_frag": 260.0, "dmg": 150.0, "fling": 60.0,
			"max": 1, "interval": 8.0, "fx": 6, "ff": 70.0, "snd": "exp_huge", "vol": 22.0,
			"desc": "The 30,000 lb Massive Ordnance Penetrator, off the ramp. The ground itself goes up."}),
		_w({"id": "lrhw", "name": "LRHW DARK EAGLE", "short": "LRHW", "kind": "orbital", "cat": 6, "tier": 7, "price": 26000,
			"delay": 6.0, "mv": 6000.0, "r_kill": 60.0, "r_frag": 140.0, "dmg": 100.0, "fling": 50.0,
			"max": 2, "interval": 15.0, "fx": 9, "ff": 40.0, "snd": "exp_huge", "vol": 18.0,
			"desc": "Conventional hypersonic glide vehicle from 2,000 km away. Mach 17 onto your mark in six seconds."}),
		# ---------------------------------------------------------------- expansion
		_w({"id": "vulcan", "name": "M61A1 VULCAN", "short": "20MM", "kind": "rotary", "cat": 0, "tier": 2, "price": 900,
			"rate": 100.0, "spin_time": 0.25, "spin_pitch": 1.4, "loop": "gau12_loop", "loop_pitch": 1.45, "overheat": 4.0,
			"mv": 1050.0, "disp": 0.003, "r_kill": 1.5, "r_frag": 3.2, "dmg": 3.0, "fling": 4.0,
			"max": 2000, "reload": 8.0, "fx": 8, "tw": 0.05, "heat": 1.2, "streak": 0.02, "off": Vector3(2.4, -1.1, 7.5),
			"ff": 0.12, "snd": "exp_small", "vol": -10.0, "snd_every": 5,
			"desc": "Six-barrel 20 mm at 6,000 rounds a minute. A fighter's gun on a gunship."}),
		_w({"id": "lasermg", "name": "PULSE LASER MACHINE GUN", "short": "PLMG", "kind": "rotary", "cat": 0, "tier": 5, "price": 9500,
			"rate": 60.0, "spin_time": 0.05, "spin_pitch": 2.0, "loop": "laser_loop", "loop_pitch": 1.7, "overheat": 6.0,
			"mv": 30000.0, "disp": 0.0008, "r_kill": 3.5, "r_frag": 5.0, "dmg": 10.0, "fling": 5.0,
			"max": 1800, "reload": 5.0, "fx": 13, "tw": 0.22, "heat": 2.4, "streak": 0.004, "off": Vector3(1.5, -2.0, 12.0),
			"ff": 0.05, "desc": "Sixty bolts of light a second, each one cooking a 3 m circle. No drop, no lead, no mercy."}),
		# ---------------------------------------------------------------- GUNS: it gets silly
		_w({"id": "smart", "name": "EXACTO SMART GATLING", "short": "SMRT", "kind": "rotary", "cat": 0, "tier": 3,
			"rate": 60.0, "spin_time": 0.3, "spin_pitch": 1.3, "loop": "gau12_loop", "loop_pitch": 1.3, "overheat": 5.0,
			"mv": 1000.0, "disp": 0.002, "r_kill": 2.6, "r_frag": 4.0, "dmg": 5.0, "fling": 6.0, "smart": 25.0,
			"max": 2400, "reload": 7.0, "fx": 8, "tw": 0.05, "heat": 1.25, "streak": 0.02, "off": Vector3(2.3, -1.6, 10.0),
			"ff": 0.08, "snd": "exp_small", "vol": -10.0, "snd_every": 6,
			"desc": "Self-steering 30 mm: every round picks its own infected near the crosshair. It does not miss."}),
		_w({"id": "ricochet", "name": "M-ARC RICOCHET GUN", "short": "RICO", "kind": "rotary", "cat": 0, "tier": 3,
			"rate": 20.0, "spin_time": 0.2, "spin_pitch": 1.4, "loop": "minigun_loop", "loop_pitch": 1.3, "overheat": 6.0,
			"mv": 1100.0, "disp": 0.0012, "r_kill": 2.0, "r_frag": 3.0, "dmg": 6.0, "fling": 6.0, "bounce": 5,
			"max": 1200, "reload": 6.0, "fx": 8, "tw": 0.08, "heat": 1.6, "streak": 0.03, "off": Vector3(2.3, -1.2, 6.0),
			"ff": 0.1, "snd": "exp_small", "vol": -10.0, "snd_every": 4,
			"desc": "Every round caroms off its victim into five more. Pinball, with the dead."}),
		_w({"id": "scatter", "name": "SCATTERSHOT 40", "short": "SCAT", "kind": "auto", "cat": 0, "tier": 4,
			"rate": 8.0, "mv": 875.0, "disp": 0.0012, "r_kill": 2.5, "r_frag": 5.0, "dmg": 5.0, "fling": 8.0, "split": 10,
			"max": 480, "reload": 6.0, "fx": 1, "tw": 0.15, "heat": 1.4, "streak": 0.03, "off": Vector3(2.4, -0.8, -2.0),
			"ff": 1.2, "shot": "bofors", "shot_vol": -7.0, "snd": "exp_med", "vol": -4.0, "snd_every": 3,
			"desc": "Eight 40 mm shells a second, each bursting into ten bomblets. Rain, but worse."}),
		_w({"id": "ripsaw", "name": "RIPSAW BLADE LAUNCHER", "short": "SAW", "kind": "auto", "cat": 0, "tier": 4,
			"rate": 6.0, "mv": 600.0, "disp": 0.0015, "r_kill": 2.6, "r_frag": 2.6, "dmg": 12.0, "fling": 12.0, "trench": 110.0, "trench_flash": 5.0,
			"max": 300, "reload": 6.0, "fx": 7, "tw": 0.25, "heat": 1.8, "streak": 0.05, "off": Vector3(2.4, -1.0, 4.0),
			"ff": 0.5, "shot": "breech", "shot_vol": -8.0, "snd": "exp_small", "vol": -10.0,
			"desc": "Spinning saw blades that skip 110 m through the crowd, six a second. Ridiculous. Effective."}),
		_w({"id": "tesla", "name": "TESLA ARC PROJECTOR", "short": "ARC", "kind": "auto", "cat": 0, "tier": 5,
			"rate": 10.0, "mv": 1.0e9, "disp": 0.002, "r_kill": 4.0, "r_frag": 6.0, "dmg": 10.0, "fling": 14.0, "arcs": 6,
			"max": 600, "reload": 6.0, "fx": 13, "off": Vector3(0.0, -2.5, 0.0),
			"ff": 0.3, "shot": "railgun", "shot_vol": -14.0, "snd": "", "vol": 0.0,
			"desc": "Throws lightning from the aircraft, ten bolts a second, each jumping through six more of them."}),
		_w({"id": "auric", "name": "AURIC GATLING", "short": "GOLD", "kind": "rotary", "cat": 0, "tier": 5,
			"rate": 50.0, "spin_time": 0.4, "spin_pitch": 0.9, "loop": "gau12_loop", "loop_pitch": 0.85, "overheat": 5.0,
			"mv": 1000.0, "disp": 0.003, "r_kill": 3.5, "r_frag": 6.0, "dmg": 6.0, "fling": 6.0, "rp_mult": 4.0,
			"max": 2000, "reload": 9.0, "fx": 8, "tw": 0.06, "heat": 1.5, "streak": 0.02, "off": Vector3(2.4, -1.0, 6.5),
			"ff": 0.2, "snd": "exp_small", "vol": -8.0, "snd_every": 3,
			"desc": "Gold-plated 30 mm that turns the infected to money: every kill pays four times the requisition."}),
		_w({"id": "chrono", "name": "CHRONO CANNON", "short": "TIME", "kind": "auto", "cat": 0, "tier": 6,
			"rate": 4.0, "mv": 1400.0, "disp": 0.001, "r_kill": 18.0, "r_frag": 18.0, "dmg": 0.0, "fling": 0.0, "rewind": 450.0, "kill_r": 7.0,
			"max": 200, "reload": 6.0, "fx": 13, "tw": 0.3, "heat": 2.6, "streak": 0.06, "off": Vector3(2.0, -1.5, 5.0),
			"ff": 0.0, "shot": "charge", "shot_vol": -6.0,
			"desc": "Shears time: everything at the heart of the hit is erased, everything around it thrown 450 m back up its path."}),
		_w({"id": "graviton", "name": "GRAVITON REPEATER", "short": "GRAV", "kind": "auto", "cat": 0, "tier": 6,
			"rate": 5.0, "mv": 900.0, "disp": 0.001, "r_kill": 14.0, "r_frag": 14.0, "dmg": 2.0, "fling": 12.0,
			"well_t": 1.6, "grow": 0.5, "collapse_r": 12.0, "collapse_dmg": 40.0, "collapse_vol": -2.0, "collapse_fx": 1, "collapse_flash": 0.0,
			"max": 250, "reload": 7.0, "fx": 13, "tw": 0.2, "heat": 2.2, "streak": 0.06, "off": Vector3(2.4, -1.0, 4.0),
			"ff": 0.5, "shot": "charge", "shot_vol": -10.0,
			"desc": "Five black holes a second. Each eats the crowd around it, then collapses in a blast."}),
		_w({"id": "godgun", "name": "GOD'S GATLING", "short": "GODS", "kind": "rotary", "cat": 0, "tier": 7,
			"rate": 16.0, "spin_time": 0.8, "spin_pitch": 0.7, "loop": "gau8_loop", "loop_pitch": 0.6, "overheat": 6.0,
			"mv": 3000.0, "disp": 0.006, "r_kill": 9.0, "r_frag": 22.0, "dmg": 25.0, "fling": 22.0, "tof_fixed": 1.5,
			"max": 400, "reload": 10.0, "fx": 4, "tw": 0.6, "heat": 3.0, "streak": 0.1, "off": Vector3(0.0, 0.0, 0.0),
			"ff": 8.0, "snd": "exp_large", "vol": 2.0, "snd_every": 3,
			"desc": "An orbital tungsten gatling: twelve rods a second, every one of them from space."}),
		_w({"id": "atomic", "name": "ATOMIC GATLING", "short": "ATOM", "kind": "auto", "cat": 0, "tier": 8, "price": 60000,
			"rate": 5.0, "mv": 600.0, "disp": 0.002, "r_kill": 28.0, "r_frag": 64.0, "dmg": 80.0, "fling": 35.0,
			"max": 100, "reload": 12.0, "fx": 5, "tw": 0.4, "heat": 2.5, "streak": 0.06, "off": Vector3(2.6, -0.5, -9.0),
			"ff": 25.0, "shot": "howitzer", "shot_vol": -4.0, "snd": "exp_huge", "vol": 6.0, "snd_every": 2,
			"desc": "Four micro-nukes a second. Your airframe will be fine. Probably."}),
		_w({"id": "bushmaster", "name": "MK44 BUSHMASTER II", "short": "30AB", "kind": "cannon", "cat": 1, "tier": 2, "price": 1000,
			"mv": 1080.0, "disp": 0.0015, "r_kill": 3.6, "r_frag": 7.5, "dmg": 4.0, "fling": 8.0,
			"max": 400, "interval": 0.3, "fx": 1, "tw": 0.1, "heat": 1.3, "off": Vector3(2.4, -0.9, 3.0), "ff": 0.6,
			"snd": "exp_med", "vol": -2.0, "snd_every": 2, "snd_fire": "bofors", "fire_pitch": 1.35, "fire_vol": -4.0, "kick": 0.18,
			"desc": "The AC-130J's 30 mm. Proximity airburst rounds, 200 a minute."}),
		_w({"id": "wp105", "name": "M60 WILLIE PETE 105", "short": "WP", "kind": "cannon", "cat": 1, "tier": 4, "price": 4500,
			"mv": 494.0, "disp": 0.0006, "r_kill": 12.0, "r_frag": 26.0, "dmg": 20.0, "fling": 12.0,
			"max": 40, "interval": 3.5, "fx": 2, "tw": 0.45, "heat": 1.7, "streak": 0.04, "off": Vector3(2.6, -0.5, -9.0),
			"ff": 6.0, "snd": "exp_large", "vol": 8.0, "manual": true, "kick": 1.0,
			"fire_r": 32.0, "fire_dps": 5.0, "fire_t": 22.0,
			"desc": "White phosphorus. A blinding burst, then a burning field that cools over 18 seconds."}),
		_w({"id": "griffin", "name": "AGM-176 GRIFFIN", "short": "GRIF", "kind": "missile", "cat": 2, "tier": 2, "price": 1600,
			"mv": 425.0, "r_kill": 5.5, "r_frag": 12.0, "dmg": 12.0, "fling": 12.0,
			"max": 16, "interval": 0.8, "fx": 1, "ff": 3.0, "snd": "exp_med", "vol": 4.0,
			"desc": "A light laser-guided missile. Sixteen per sortie; keep the laser on it."}),
		_w({"id": "micro", "name": "MERLIN MICRO-MISSILE SWARM", "short": "MMS", "kind": "drones", "cat": 2, "tier": 5, "price": 10500,
			"mv": 320.0, "r_kill": 2.6, "r_frag": 5.0, "dmg": 5.0, "fling": 9.0, "salvo": 48, "seek": true,
			"max": 96, "interval": 7.0, "fx": 8, "ff": 0.5, "snd": "exp_small", "vol": -4.0, "snd_every": 4,
			"desc": "Forty-eight micro-missiles, each one picking its own infected out of the crowd."}),
		_w({"id": "thermite", "name": "THERMITE RAIN", "short": "TRM", "kind": "thermite", "cat": 3, "tier": 4, "price": 4800,
			"tof_base": 2.5, "tof_speed": 260.0, "mv": 260.0, "len": 2.3, "subs": 50, "spread": 75.0,
			"r_kill": 6.0, "r_frag": 6.0, "dmg": 4.0, "fling": 3.0, "fire_r": 7.0, "fire_dps": 4.0, "fire_t": 20.0,
			"max": 3, "interval": 2.0, "fx": 1, "ff": 2.0,
			"desc": "Fifty burning thermite pellets scattered across a block. Each one a small, cooling fire."}),
		_w({"id": "daisy", "name": "BLU-82 DAISY CUTTER", "short": "BLU82", "kind": "bomb", "cat": 3, "tier": 6, "price": 15000,
			"tof_base": 5.0, "tof_speed": 180.0, "mv": 180.0, "len": 6.0,
			"r_kill": 70.0, "r_frag": 150.0, "dmg": 100.0, "fling": 48.0,
			"max": 1, "interval": 5.0, "fx": 6, "ff": 50.0, "snd": "exp_huge", "vol": 18.0,
			"desc": "15,000 lb of slurry explosive, pushed out of the ramp on a pallet. Clears a landing zone."}),
		_w({"id": "apache", "name": "AH-64 APACHE PAIR", "short": "AH64", "kind": "apache", "cat": 4, "tier": 4, "price": 7000,
			"max": 1, "interval": 50.0, "dur": 45.0, "r_kill": 2.5, "r_frag": 5.0, "mv": 800.0,
			"desc": "Two Apaches hover over your mark for 45 s with 30 mm chain guns and rockets."}),
		_w({"id": "b52", "name": "B-52 ARC LIGHT", "short": "ARC", "kind": "b52", "cat": 4, "tier": 7, "price": 24000,
			"max": 1, "interval": 60.0, "r_kill": 10.0, "r_frag": 24.0, "mv": 200.0,
			"desc": "A Stratofortress lays 51 bombs in a 1.2 km carpet along the approach through your mark."}),
		_w({"id": "glocke", "name": "DIE GLOCKE", "short": "BELL", "kind": "glocke", "cat": 5, "tier": 6, "price": 20000,
			"max": 1, "interval": 30.0, "dur": 22.0, "r_kill": 4.5, "r_frag": 7.0, "dmg": 9.0, "fling": 14.0,
			"desc": "Wacky: a humming bell rises over your mark and calls down chain lightning. Steer it with the crosshair."}),
		_w({"id": "singularity", "name": "SINGULARITY PROJECTOR", "short": "SING", "kind": "singularity", "cat": 5, "tier": 7, "price": 28000,
			"max": 1, "interval": 20.0, "dur": 8.0, "r_kill": 48.0, "r_frag": 48.0, "dmg": 8.0, "fling": 18.0,
			"desc": "Wacky: a pinprick black hole. It drags the crowd in for eight seconds, then collapses."}),
		_w({"id": "constellation", "name": "THOR CONSTELLATION", "short": "THORx12", "kind": "constellation", "cat": 6, "tier": 8, "price": 50000,
			"delay": 8.0, "mv": 3000.0, "r_kill": 40.0, "r_frag": 95.0, "dmg": 80.0, "fling": 45.0,
			"max": 1, "interval": 20.0, "fx": 9, "ff": 40.0, "snd": "exp_huge", "vol": 16.0,
			"desc": "Twelve tungsten rods walked down the approach through your mark, 30 m apart."}),
		# ---------------------------------------------------------------- SHENANIGANS
		_w({"id": "cow", "name": "COW CATAPULT", "short": "MOO", "kind": "cows", "cat": 7, "tier": 2, "price": 1500,
			"mv": 260.0, "disp": 0.006, "r_kill": 5.0, "r_frag": 9.0, "dmg": 8.0, "fling": 14.0,
			"max": 60, "interval": 0.4, "fx": 1, "ff": 1.0, "snd": "exp_med", "vol": -2.0,
			"desc": "Launches live cattle out of the ramp. Warm-blooded, so they glow on the way down."}),
		_w({"id": "piano", "name": "GRAND PIANO DROP", "short": "PIANO", "kind": "bomb", "cat": 7, "tier": 3, "price": 2600,
			"tof_base": 3.0, "tof_speed": 200.0, "mv": 200.0, "len": 2.7, "box": Vector3(1.6, 1.0, 2.7),
			"r_kill": 7.0, "r_frag": 14.0, "dmg": 20.0, "fling": 16.0,
			"max": 8, "interval": 1.0, "fx": 2, "ff": 4.0, "snd": "exp_med", "vol": 4.0,
			"desc": "A concert grand out of the ramp, dead on the crosshair. It lands on a chord."}),
		_w({"id": "boulder", "name": "THE BOULDER", "short": "ROCK", "kind": "boulder", "cat": 7, "tier": 4, "price": 6500,
			"r_kill": 9.0, "r_frag": 9.0, "dmg": 50.0, "fling": 20.0, "roll": 900.0, "speed": 26.0,
			"max": 3, "interval": 6.0, "ff": 0.0,
			"desc": "15 m of granite dropped on the crosshair. It rolls outward, away from the refuge, flattening 900 m of horde."}),
		_w({"id": "titan", "name": "TITAN MECH", "short": "TITAN", "kind": "titan", "cat": 7, "tier": 6, "price": 24000,
			"r_kill": 14.0, "r_frag": 30.0, "dmg": 40.0, "fling": 30.0, "dur": 40.0,
			"max": 1, "interval": 60.0, "ff": 0.0,
			"desc": "Drops a 40 m friendly giant on your mark. For forty seconds it stomps toward the thickest crowd."}),
		_w({"id": "moon", "name": "LUNAR STRIKE", "short": "MOON", "kind": "moon", "cat": 7, "tier": 8, "price": 90000,
			"delay": 12.0, "r_kill": 1400.0, "r_frag": 2600.0, "dmg": 400.0, "fling": 70.0,
			"max": 1, "interval": 30.0, "ff": 0.0, "ff_max": 95.0, "ff_range": 1500.0, "consent_t": 2.0, "air_lethal": 0.0,
			"desc": "Not THE Moon. A moon. Twelve seconds after you designate, 300 m of rock arrives. Hold fire 2 s."}),
	]
	hidden = {
		"skeet": _w({"id": "skeet", "kind": "sub", "r_kill": 4.0, "r_frag": 10.0, "dmg": 6.0, "fling": 10.0, "fx": 1, "ff": 2.0}),
		"dart": _w({"id": "dart", "kind": "sub", "r_kill": 1.0, "r_frag": 1.2, "dmg": 3.0, "fling": 3.0, "fx": 7, "ff": 0.05}),
		"mine": _w({"id": "mine", "kind": "sub", "r_kill": 3.5, "r_frag": 8.0, "dmg": 6.0, "fling": 10.0, "fx": 1, "ff": 1.0, "snd": "exp_small", "vol": 2.0}),
		"shell155": _w({"id": "shell155", "kind": "sub", "r_kill": 14.0, "r_frag": 32.0, "dmg": 35.0, "fling": 24.0, "fx": 2, "ff": 10.0, "snd": "exp_large", "vol": 10.0}),
		"tos": _w({"id": "tos_rkt", "kind": "sub", "r_kill": 18.0, "r_frag": 38.0, "dmg": 40.0, "fling": 26.0, "fx": 11, "ff": 12.0, "snd": "exp_huge", "vol": 8.0, "snd_every": 3}),
		"chain": _w({"id": "chain", "short": "CHAIN", "kind": "sub", "r_kill": 2.6, "r_frag": 5.5, "dmg": 3.0, "fling": 9.0, "fx": 8, "ff": 0.3, "snd": "exp_small", "vol": -8.0, "snd_every": 4}),
		"pellet": _w({"id": "pellet", "kind": "sub", "r_kill": 3.0, "r_frag": 5.0, "dmg": 3.0, "fling": 3.0, "fx": 13, "ff": 0.5}),
		"mk82": _w({"id": "mk82", "short": "MK82", "kind": "sub", "r_kill": 10.0, "r_frag": 24.0, "dmg": 25.0, "fling": 20.0, "fx": 4, "ff": 12.0, "snd": "exp_large", "vol": 6.0, "snd_every": 3}),
		"m230": _w({"id": "m230", "short": "AH64", "kind": "sub", "r_kill": 2.0, "r_frag": 4.0, "dmg": 3.0, "fling": 6.0, "fx": 0, "ff": 0.2, "snd": "exp_small", "vol": -8.0, "snd_every": 4}),
		"hydra_ah": _w({"id": "hydra_ah", "short": "AH64", "kind": "sub", "r_kill": 3.5, "r_frag": 9.0, "dmg": 6.0, "fling": 10.0, "fx": 1, "ff": 1.5, "snd": "exp_med", "vol": 0.0}),
		"bolt": _w({"id": "bolt", "short": "BELL", "kind": "sub", "r_kill": 4.5, "r_frag": 7.0, "dmg": 9.0, "fling": 14.0, "fx": 13, "ff": 1.0}),
		"spark": _w({"id": "spark", "short": "BELL", "kind": "sub", "r_kill": 3.0, "r_frag": 5.0, "dmg": 6.0, "fling": 10.0, "fx": 13, "ff": 0.5}),
		"arc": _w({"id": "arc", "short": "ARC", "kind": "sub", "r_kill": 2.6, "r_frag": 4.0, "dmg": 6.0, "fling": 10.0, "fx": 13, "ff": 0.2}),
		"bomblet": _w({"id": "bomblet", "short": "SCAT", "kind": "sub", "r_kill": 3.0, "r_frag": 6.0, "dmg": 5.0, "fling": 9.0, "fx": 8, "ff": 0.3,
			"snd": "exp_small", "vol": -10.0, "snd_every": 3}),
		"meteor": _w({"id": "meteor", "short": "METEOR", "kind": "sub", "r_kill": 12.0, "r_frag": 26.0, "dmg": 40.0, "fling": 24.0, "fx": 3, "ff": 0.0,
			"snd": "exp_large", "vol": 2.0, "snd_every": 2}),
		"gbu38": _w({"id": "gbu38", "short": "GBU38", "kind": "sub", "r_kill": 15.0, "r_frag": 34.0, "dmg": 35.0, "fling": 24.0, "fx": 4, "ff": 12.0,
			"snd": "exp_large", "vol": 10.0, "len": 2.4}),
		"gmlrs": _w({"id": "gmlrs", "short": "GMLRS", "kind": "sub", "r_kill": 18.0, "r_frag": 40.0, "dmg": 45.0, "fling": 26.0, "fx": 5, "ff": 15.0,
			"snd": "exp_huge", "vol": 8.0}),
	}
	# the ricochet gun's round, one stage per remaining bounce
	for n in 6:
		hidden["rico%d" % n] = _w({"id": "rico", "short": "RICO", "kind": "sub", "r_kill": 1.4, "r_frag": 2.0, "dmg": 4.0, "fling": 6.0,
			"fx": 8, "ff": 0.1, "bounce": n})
	loadout = ["m2", "gau19"]
	_apply_ladders()

	a10_mesh = MeshKit.a10()
	gunship_mesh = _gunship_mesh()
	mat_world = ShaderMaterial.new()
	mat_world.shader = load("res://shaders/world.gdshader")
	mat_hot = ShaderMaterial.new()
	mat_hot.shader = load("res://shaders/solid.gdshader")
	mat_hot.set_shader_parameter("heat", 1.2)
	mat_bomb = ShaderMaterial.new()
	mat_bomb.shader = load("res://shaders/solid.gdshader")
	mat_bomb.set_shader_parameter("heat", 0.62)
	mat_beam = ShaderMaterial.new()
	mat_beam.shader = load("res://shaders/beam.gdshader")
	missile_mesh = BoxMesh.new()
	missile_mesh.size = Vector3(0.25, 0.25, 1.6)
	drone_mesh = BoxMesh.new()
	drone_mesh.size = Vector3(0.9, 0.2, 1.3)
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	beam_node = MeshInstance3D.new()
	beam_node.mesh = cube
	beam_node.material_override = mat_beam
	beam_node.visible = false
	add_child(beam_node)
	sol_node = MeshInstance3D.new()
	sol_node.mesh = cube
	sol_node.material_override = mat_beam.duplicate()
	sol_node.visible = false
	add_child(sol_node)
	# a pool of beam segments for lightning bolts
	var bolt_mat: ShaderMaterial = mat_beam.duplicate()
	bolt_mat.set_shader_parameter("heat", 5.0)
	for i in 36:
		var n := MeshInstance3D.new()
		n.mesh = cube
		n.material_override = bolt_mat
		n.visible = false
		add_child(n)
		bolt_nodes.append(n)
	bolt_until.resize(36)
	bell_mesh = _bell_mesh()
	heli_mesh = _apache_mesh()
	bomber_mesh = _bomber_mesh()
	cow_mesh = _cow_mesh()
	boulder_mesh = _boulder_mesh()
	titan_mesh = MeshKit.humanoid(false)
	mat_titan = ShaderMaterial.new()
	mat_titan.shader = load("res://shaders/solid.gdshader")
	mat_titan.set_shader_parameter("heat", 0.92)


## A cow, as seen by a thermal imager: a warm barrel on legs.
static func _cow_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var skin := Color(0.86, 0.0, 0.3, 1.0)
	var white := Vector2(MeshKit.TAG_WHITE, 0)
	var dark := Vector2(MeshKit.TAG_DARK, 0)
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 0.3, 0)), Vector3(1.0, 1.0, 2.0), skin, white)
	MeshKit.box(st, Transform3D(Basis(), Vector3(0.2, 0.55, 0.3)), Vector3(0.65, 0.5, 0.8), skin, dark)
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 0.6, -1.25)), Vector3(0.6, 0.6, 0.7), Color(0.95, 0.0, 0.3, 1.0), dark)
	for x in [-0.35, 0.35]:
		for z in [-0.7, 0.7]:
			MeshKit.box(st, Transform3D(Basis(), Vector3(x, -0.45, z)), Vector3(0.2, 0.7, 0.2), Color(0.7, 0.0, 0.2, 1.0), white)
	return st.commit()


## A 15 m boulder with blotchy sun-warmed faces, so you can see it roll.
static func _boulder_mesh() -> ArrayMesh:
	var sm := SphereMesh.new()
	sm.radius = 7.5
	sm.height = 15.0
	sm.radial_segments = 14
	sm.rings = 9
	var arrays := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var cols := PackedColorArray()
	cols.resize(verts.size())
	var uvs := PackedVector2Array()
	uvs.resize(verts.size())
	for k in verts.size():
		var v := verts[k]
		var n := sin(v.x * 1.7 + 1.3) * sin(v.y * 2.3) * sin(v.z * 1.9 + 0.7)
		cols[k] = Color(0.5 + 0.14 * n, 0.6, 1.0, 1.0)
		uvs[k] = Vector2(MeshKit.TAG_ROCK, 0.0)
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


## Die Glocke: a squat bell with a glowing rim.
static func _bell_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	MeshKit.cylinder(st, Vector3(0, -4.0, 0), 6.5, 6.0, Color(0.55, 0.5, 0.6, 1.0), Color(0.5, 0.3, 0.6, 1.0), 20)
	MeshKit.dome(st, Vector3(0, 2.0, 0), 6.5, Color(0.6, 0.5, 0.8, 1.0), 5, 20)
	MeshKit.cylinder(st, Vector3(0, -4.6, 0), 7.2, 0.8, Color(1.6, 0.0, 0.0, 1.0), Color(1.6, 0.0, 0.0, 1.0), 24)
	return st.commit()


static func _apache_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := Color(0.38, 0.0, 0.3, 1.0)
	MeshKit.box(st, Transform3D(Basis(), Vector3.ZERO), Vector3(1.6, 2.2, 9.0), body)
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 0.3, 7.5)), Vector3(0.5, 0.8, 6.0), body)
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 0.0, 0.5)), Vector3(4.0, 0.3, 1.2), body)
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 1.3, 0.5)), Vector3(2.6, 0.9, 2.4), Color(0.95, 0.0, 0.0, 1.0))
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 1.9, 0)), Vector3(14.6, 0.1, 0.5), Color(0.3, 0.0, 0.0, 1.0))
	MeshKit.box(st, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, 1.9, 0)), Vector3(14.6, 0.1, 0.5), Color(0.3, 0.0, 0.0, 1.0))
	return st.commit()


static func _bomber_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := Color(0.4, 0.0, 0.3, 1.0)
	MeshKit.box(st, Transform3D(Basis(), Vector3.ZERO), Vector3(3.5, 4.0, 48.0), body)
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 1.2, -2.0)), Vector3(56.0, 0.8, 7.0), body)
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 5.0, 20.0)), Vector3(0.6, 10.0, 6.0), body)
	for x in [-20.0, -13.0, 13.0, 20.0]:
		MeshKit.box(st, Transform3D(Basis(), Vector3(x, 0.0, -3.0)), Vector3(2.4, 1.6, 5.0), Color(1.15, 0.0, 0.0, 1.0))
	return st.commit()


static func _gunship_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := Color(0.44, 0.0, 0.3, 1.0)
	MeshKit.box(st, Transform3D(Basis(), Vector3.ZERO), Vector3(4.0, 4.0, 30.0), body)
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 1.5, -2.0)), Vector3(40.0, 0.6, 4.5), body)
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 4.0, 13.0)), Vector3(0.6, 7.0, 4.0), body)
	for x in [-14.0, -7.0, 7.0, 14.0]:
		MeshKit.box(st, Transform3D(Basis(), Vector3(x, 1.0, -3.0)), Vector3(1.4, 1.4, 4.0), Color(1.1, 0.0, 0.0, 1.0))
	return st.commit()


# ------------------------------------------------------------------ the ladders
## Prices, rungs and display order all come from LADDERS.
func _apply_ladders() -> void:
	for c in LADDERS.size():
		var ladder: Array = LADDERS[c]
		for i in ladder.size():
			var w := by_id(String(ladder[i][0]))
			if w.is_empty():
				continue
			w["price"] = int(ladder[i][1])
			w["cat"] = c
			w["rung"] = i
			w["tier"] = i + 1
	weapons.sort_custom(func(a, b) -> bool: return int(a["cat"]) * 100 + int(a.get("rung", 99)) < int(b["cat"]) * 100 + int(b.get("rung", 99)))


func ladder_size(cat: int) -> int:
	return (LADDERS[cat] as Array).size()


## The rung below this one, or {} for the first rung.
func prev_of(w: Dictionary) -> Dictionary:
	var r := int(w.get("rung", 0))
	if r <= 0:
		return {}
	return by_id(String(LADDERS[int(w["cat"])][r - 1][0]))


## The rung above this one, or {} at the top of the ladder.
func next_of(w: Dictionary) -> Dictionary:
	var c := int(w["cat"])
	var r := int(w.get("rung", 0))
	if r + 1 >= ladder_size(c):
		return {}
	return by_id(String(LADDERS[c][r + 1][0]))


## Can it be bought: the first rung always, any other once the rung below is owned.
func unlocked(w: Dictionary) -> bool:
	var p := prev_of(w)
	return p.is_empty() or bool(p["owned"])


func owned_in(cat: int) -> int:
	var n := 0
	for w in in_category(cat):
		if w["owned"]:
			n += 1
	return n


## A rough figure for how much a weapon kills per second in a crowd, for the unlock card's
## "+X% firepower". Only meaningful between weapons of the same ladder.
func firepower(w: Dictionary) -> float:
	var rk := float(w.get("r_kill", 1.0))
	var rf := maxf(float(w.get("r_frag", rk)), rk)
	var area := PI * (rk * rk + 0.4 * (rf * rf - rk * rk))
	var punch := clampf(float(w.get("dmg", 4.0)) / 4.0, 0.3, 3.0)
	var extra := 1.0 + float(w.get("bounce", 0)) + float(w.get("split", 0)) * 0.8 + float(w.get("arcs", 0))
	if w.has("trench"):
		extra *= float(w["trench"]) / maxf(rk * 2.0, 1.0)
	if w.has("salvo"):
		extra *= float(w["salvo"])
	if w.has("subs"):
		extra *= float(w["subs"]) * 0.3
	var rate := float(w.get("rate", 0.0))
	if rate <= 0.0:
		rate = 1.0 / maxf(float(w.get("interval", 1.0)), 0.1)
	if w.get("kind", "") == "laser":
		rate = float(w.get("dps", 1.0))
	return area * punch * extra * rate


# ------------------------------------------------------------------ catalogue
## Loadout stations: ten, plus whatever the weapon-stations upgrade adds.
func slots() -> int:
	return SLOTS + int(main.stat("add_slots"))


## Ammunition per resupply after magazine upgrades and perks (the laser is a charge, not rounds).
func cap_of(w: Dictionary) -> int:
	if w.get("kind", "") == "laser":
		return int(w["max"])
	return maxi(1, int(round(float(w["max"]) * main.stat("ammo"))))


## Seconds for one round, missile, bomb or call-in to come back on its own.
## 0 for guns and lasers, which reload or recharge instead and never run dry.
func restock_time(w: Dictionary) -> float:
	if w.get("kind", "") in ["rotary", "auto", "laser"] or not w.has("cat"):
		return 0.0
	var id := String(w["id"])
	var per: float = RESTOCK_UNIT[id] if RESTOCK_UNIT.has(id) else float(RESTOCK_FULL[int(w["cat"])]) / float(cap_of(w))
	var k: float = main.stat("restock")
	return per * k


## Progress toward the next restocked unit, 0-1.
func restock_frac(w: Dictionary) -> float:
	return clampf(float(w.get("restock_acc", 0.0)), 0.0, 1.0)


## Requisition to top a system back up right now (0 when it's full or never runs dry).
func restock_price(w: Dictionary) -> int:
	if not w.get("owned", false) or restock_time(w) <= 0.0:
		return 0
	var missing: int = cap_of(w) - int(w["ammo"])
	if missing <= 0:
		return 0
	var unit: float = float(w["price"]) * float(RESTOCK_K[int(w["cat"])]) / float(w["max"])
	var k: float = main.stat("restock_cost")
	return ceili(maxf(unit * missing, 10.0) * k / 10.0) * 10


## Everything aboard that isn't full, priced together.
func restock_all_price() -> int:
	var total := 0
	for w in equipped():
		total += restock_price(w)
	return total


## A full load, right now.
func fill(w: Dictionary) -> void:
	w["ammo"] = cap_of(w)
	w["restock_acc"] = 0.0
	if w["id"] == "bofors":
		w["inclip"] = mini(4, int(w["ammo"]))
		w["clip_rt"] = 0.0


## Ammunition comes back by itself: the loadmasters break more out of the hold and the support
## assets rearm. Shells and rockets trickle in; big bombs, call-ins and nukes take minutes.
func _restock(dt: float) -> void:
	for w in weapons:
		if not w["owned"]:
			continue
		var per: float = restock_time(w)
		if per <= 0.0:
			continue
		var cap: int = cap_of(w)
		var have: int = int(w["ammo"])
		if have >= cap:
			w["restock_acc"] = 0.0
			continue
		var acc: float = float(w["restock_acc"]) + dt / per
		if acc >= 1.0:
			var n: int = mini(int(acc), cap - have)
			acc -= n
			w["ammo"] = have + n
			if have + n >= cap:
				acc = 0.0
			if have == 0 and is_equipped(String(w["id"])):
				main.sfx.play("clip", -8.0, 1.1)
			if per >= 30.0:
				if w["kind"] in SUPPORT_KINDS:
					main.radio("TOC", "Spectre, %s is rearmed and available again." % String(w["name"]))
				else:
					main.radio("LOADMASTER", "Another %s is up from the hold." % String(w["short"]))
		w["restock_acc"] = acc


## Start a weapon's cooldown: support call-ins scale with the datalink, everything else with rate of fire.
func _set_cd(w: Dictionary) -> void:
	if w.get("kind", "") in SUPPORT_KINDS:
		w["cd"] = float(w["interval"]) * main.stat("support_cd")
	else:
		w["cd"] = float(w["interval"]) / main.stat("rof")


func by_id(id: String) -> Dictionary:
	for w in weapons:
		if w["id"] == id:
			return w
	return {}


func owned() -> Array:
	return weapons.filter(func(w: Dictionary) -> bool: return w["owned"])


func owned_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for w in owned():
		out.append(String(w["id"]))
	return out


func in_category(cat: int) -> Array:
	return weapons.filter(func(w: Dictionary) -> bool: return int(w["cat"]) == cat)


func equipped() -> Array:
	var out: Array = []
	for id in loadout:
		var w := by_id(String(id))
		if not w.is_empty():
			out.append(w)
	return out


func current() -> Dictionary:
	if loadout.is_empty():
		return by_id("m2")
	return by_id(String(loadout[clampi(cur, 0, loadout.size() - 1)]))


func is_equipped(id: String) -> bool:
	return id in loadout


func toggle_equip(id: String) -> bool:
	var w := by_id(id)
	if w.is_empty() or not w["owned"]:
		return false
	if id in loadout:
		if loadout.size() <= 1:
			return false
		loadout.erase(id)
	else:
		if loadout.size() >= slots():
			return false
		loadout.append(id)
		# keep the loadout in catalogue order so the number keys stay predictable
		loadout.sort_custom(func(a, b) -> bool: return weapons.find(by_id(String(a))) < weapons.find(by_id(String(b))))
	cur = clampi(cur, 0, loadout.size() - 1)
	return true


func select_slot(slot: int) -> void:
	if slot < 0 or slot >= loadout.size() or slot == cur:
		return
	_stop_continuous()
	cur = slot
	consent = 0.0
	rail_charge = 0.0
	main.sfx.play("switch", -4.0)


func select_id(id: String) -> void:
	var i := loadout.find(id)
	if i >= 0:
		select_slot(i)


func cycle(step: int) -> void:
	if loadout.size() > 0:
		select_slot(posmod(cur + step, loadout.size()))


func resupply() -> void:
	for w in weapons:
		w["ammo"] = cap_of(w)
		w["restock_acc"] = 0.0
		w["rt"] = 0.0
		w["cd"] = 0.0
		if w.has("cap"):
			w["charge"] = w["cap"]
	var bof := by_id("bofors")
	bof["inclip"] = 4
	bof["clip_rt"] = 0.0


func reload() -> void:
	var w := current()
	if w["kind"] in ["rotary", "auto"] and int(w["ammo"]) < cap_of(w) and float(w["rt"]) <= 0.0:
		w["rt"] = float(w["reload"]) * main.stat("reload")
		main.sfx.play("breech", -6.0, 0.8)
		main.radio("LOADER", "Reloading the %s." % String(w["short"]))


func status_text(w: Dictionary) -> String:
	var kind := String(w["kind"])
	if float(w["rt"]) > 0.0:
		return "RELOAD %.1f" % float(w["rt"])
	if kind == "rotary":
		if w["hot"]:
			return "OVERHEAT"
		if float(w["spin"]) > 0.05:
			return "SPIN %d%%" % int(float(w["spin"]) * 100.0)
	if kind == "laser":
		if w["hot"]:
			return "RECHARGE"
		return "CHARGE %d%%" % int(w["ammo"])
	if kind == "sol" and not sol.is_empty():
		return "FIRING %.1f" % (float(sol["dur"]) - float(sol["t"]))
	if kind == "wingman" and not wingman.is_empty():
		return "ON STATION"
	if kind == "a10" and not a10.is_empty():
		var s: float = a10["s"]
		return "IP INBOUND" if s < float(a10["ip_s"]) else ("IN HOT" if s < float(a10["fire_s1"]) else "EGRESS")
	if kind == "glocke" and not glocke.is_empty():
		return "TOLLING %d" % int(float(glocke["dur"]) - float(glocke["t"]))
	if kind == "apache" and not apaches.is_empty():
		return "ON STATION %d" % int(float(apaches["dur"]) - float(apaches["t"]))
	if kind == "b52" and not b52.is_empty():
		return "INBOUND"
	if kind == "cas" and not jets.is_empty():
		return "IN HOT"
	if kind == "titan" and not titan.is_empty():
		return "STOMPING %d" % int(float(titan["dur"]) - float(titan["t"])) if titan["landed"] else "PLANETFALL"
	if kind == "moon" and not moon.is_empty():
		return "IMPACT %.0fS" % (float(moon["delay"]) - float(moon["t"]))
	if int(w["ammo"]) <= 0:
		var per: float = restock_time(w)
		if per > 0.0:
			return "RESTOCK %dS" % ceili((1.0 - restock_frac(w)) * per)
		return "WINCHESTER"
	if w["id"] == "bofors" and float(w["clip_rt"]) > 0.0:
		return "CLIP %.1f" % float(w["clip_rt"])
	if float(w["cd"]) > 0.0:
		return "LOADING %.1f" % float(w["cd"])
	if kind in CONSENT_KINDS and consent > 0.0:
		return "CONSENT"
	if kind == "rail" and rail_charge > 0.0:
		return "CHARGING"
	return "READY"


func ammo_text(w: Dictionary) -> String:
	match String(w["kind"]):
		"laser":
			return "%d%%" % int(w["ammo"])
	return main.hud.commas(int(w["ammo"]))


func time_of_flight() -> float:
	var w := current()
	if w.has("tof_fixed"):
		return float(w["tof_fixed"])
	var muzzle: Vector3 = main.mount_pos(w["off"])
	var d := muzzle.distance_to(main.aim_point)
	match String(w["kind"]):
		"bomb", "cluster", "nuke", "neutron", "darts", "napalm", "mines", "thermite":
			return float(w["tof_base"]) + d / float(w["tof_speed"])
		"orbital", "constellation", "moon":
			return float(w["delay"])
		"boulder", "titan":
			return 1.5
		"cas":
			return 24.0
		"himars":
			return 14.0
		"arty":
			return 11.0
		"tos":
			return 8.0
		"cruise":
			return 24.0
		"a10":
			return 19.0
		"apache":
			return 6.0
		"b52":
			return 20.0
		"glocke":
			return 3.0
		"laser", "sol", "singularity":
			return 0.0
	return d / (float(w["mv"]) * main.stat("mv"))


# ------------------------------------------------------------------ update
func update(dt: float, trigger: bool) -> void:
	var now: float = main.t
	beam_on = false
	var cw := current()
	for w in equipped():
		if float(w["cd"]) > 0.0:
			w["cd"] = maxf(0.0, float(w["cd"]) - dt)
			if w["id"] in ["m102", "beehive", "wp105", "pgk"] and float(w["cd"]) <= 0.0 and int(w["ammo"]) > 0:
				main.sfx.play("beep", -6.0)
		if float(w["rt"]) > 0.0:
			w["rt"] = float(w["rt"]) - dt
			if float(w["rt"]) <= 0.0:
				w["rt"] = 0.0
				w["ammo"] = cap_of(w)
				main.sfx.play("clip", -4.0)
				main.radio("LOADER", "%s up!" % String(w["short"]))
		var on: bool = trigger and w["id"] == cw["id"]
		match String(w["kind"]):
			"rotary", "auto":
				_update_gun(w, dt, on)
			"laser":
				_update_laser(w, dt, on)
			"rockets", "drones":
				_update_salvo(w, dt)
	_restock(dt)
	var bof := by_id("bofors")
	if float(bof["clip_rt"]) > 0.0:
		bof["clip_rt"] = float(bof["clip_rt"]) - dt
		if float(bof["clip_rt"]) <= 0.0:
			bof["clip_rt"] = 0.0
			bof["inclip"] = mini(4, int(bof["ammo"]))
	elif int(bof["inclip"]) <= 0 and int(bof["ammo"]) > 0:
		# ran dry and has since been restocked: load a fresh clip
		bof["clip_rt"] = bof["clip_t"]

	var kind := String(cw["kind"])
	if kind in CONSENT_KINDS and trigger:
		_consent(cw, dt)
	else:
		consent = 0.0
	if kind == "rail":
		_update_rail(cw, dt, trigger)
	elif trigger and not (kind in ["rotary", "auto", "laser"]) and not (kind in CONSENT_KINDS):
		_fire_discrete(cw)

	var i := 0
	while i < pending.size():
		var ev: Array = pending[i]
		if float(ev[0]) <= now:
			pending.remove_at(i)
			_impact(ev[1], ev[2], ev[3], ev[4] if ev.size() > 4 else Vector3.ZERO, String(ev[5]) if ev.size() > 5 else "")
		else:
			i += 1
	# kills by nuclear shock fronts (the horde sweeps them as the front expands)
	for sk in main.horde.take_shock_kills():
		main.add_kills(int(sk[0]), sk[1], false)
		var toll := int(sk[2])
		if toll > 0:
			var gz: Vector3 = sk[1]
			main.popups.append({"pos": gz + Vector3.UP * 80.0, "text": "+%s" % main.hud.commas(toll), "t": main.real_t, "big": true})
			main._feed("SHOCK FRONT  +%s  @ %.1f KM" % [main.hud.commas(toll), Vector2(gz.x, gz.z).length() / 1000.0])
			main.best_multi = maxi(main.best_multi, toll)

	# Volatile Infected: kills that detonate (bounded per frame so it can't run away)
	var chains: Array[Vector3] = main.horde.chain_events
	var n_chain := mini(chains.size(), 24)
	for c in n_chain:
		_impact(chains[c], hidden["chain"], true)
	chains.clear()

	_update_missiles(dt)
	_update_bombs(dt)
	_update_rods(dt)
	_update_drones(dt)
	_update_mines(dt)
	_update_zones(dt)
	_update_missions(dt)
	_update_wingman(dt)
	_update_sol(dt)
	_update_a10(dt)
	_update_glocke(dt)
	_update_wells(dt)
	_update_apaches(dt)
	_update_b52(dt)
	_update_boulders(dt)
	_update_titan(dt)
	_update_moon(dt)
	_update_jets(dt)
	for b in bolt_nodes.size():
		if bolt_nodes[b].visible and now > bolt_until[b]:
			bolt_nodes[b].visible = false
	main.sfx.beam(beam_on, beam_pitch)


func _stop_continuous() -> void:
	beam_node.visible = false
	main.sfx.beam(false)


# ------------------------------------------------------------------ guns
func _update_gun(w: Dictionary, dt: float, want: bool) -> void:
	var rotary: bool = w["kind"] == "rotary"
	var can: bool = want and not w["hot"] and int(w["ammo"]) > 0 and float(w["rt"]) <= 0.0
	var rate := 0.0
	var pitch: float = w.get("spin_pitch", 1.0)
	if rotary:
		if can:
			if not w["spun_snd"]:
				main.sfx.play("gau8_spinup", -3.0, pitch)
				w["spun_snd"] = true
			w["spin"] = minf(1.0, float(w["spin"]) + dt / float(w["spin_time"]))
		else:
			w["spin"] = maxf(0.0, float(w["spin"]) - dt / 0.6)
		# real rotary cannons take a moment to reach full rate
		if can and float(w["spin"]) > 0.3:
			rate = float(w["rate"]) * clampf((float(w["spin"]) - 0.2) / 0.8, 0.0, 1.0)
	elif can:
		rate = w["rate"]
	rate *= main.stat("rof")
	if rate > 0.0:
		if rotary:
			w["looping"] = true
			var full: float = float(w["rate"]) * main.stat("rof")
			main.sfx.gun_loop(String(w["loop"]), clampf(rate / full, 0.55, 1.0) * float(w.get("loop_pitch", 1.0)))
		w["acc"] = float(w["acc"]) + rate * dt
		while float(w["acc"]) >= 1.0 and int(w["ammo"]) > 0:
			w["acc"] = float(w["acc"]) - 1.0
			w["ammo"] = int(w["ammo"]) - 1
			_fire_round(w)
			if not rotary:
				main.sfx.play(String(w["shot"]), float(w["shot_vol"]), randf_range(0.95, 1.05))
		w["temp"] = float(w["temp"]) + dt * rate / (float(w["rate"]) * main.stat("rof"))
		main.kick(0.05 if rotary else 0.03)
		if float(w["temp"]) >= float(w.get("overheat", INF)) * main.stat("heat"):
			w["hot"] = true
			main.radio("LOADER", "%s is cooking off, give it a second!" % String(w["short"]))
	else:
		if w["looping"]:
			w["looping"] = false
			main.sfx.gun_cease()
			main.sfx.play("gau8_spindown", -3.0, pitch)
		if not want:
			w["spun_snd"] = false
			w["acc"] = 0.0
		w["temp"] = maxf(0.0, float(w["temp"]) - dt * 0.6)
	if w["hot"] and float(w["temp"]) < 1.0:
		w["hot"] = false
	if int(w["ammo"]) <= 0 and float(w["rt"]) <= 0.0 and not w["looping"]:
		w["rt"] = float(w["reload"]) * main.stat("reload")
		main.radio("LOADER", "%s is dry! Reloading." % String(w["short"]))


func _fire_discrete(w: Dictionary) -> void:
	if float(w["cd"]) > 0.0 or float(w["rt"]) > 0.0 or int(w["ammo"]) <= 0:
		return
	match String(w["kind"]):
		"cannon":
			if w["id"] == "bofors":
				if int(w["inclip"]) <= 0:
					return
				w["inclip"] = int(w["inclip"]) - 1
				w["ammo"] = int(w["ammo"]) - 1
				_set_cd(w)
				_fire_round(w)
				main.sfx.play("bofors", -1.0, randf_range(0.97, 1.03))
				main.kick(0.35)
				if int(w["inclip"]) == 0 and int(w["ammo"]) > 0:
					w["clip_rt"] = w["clip_t"]
					main.sfx.play("clip", -5.0, 1.0, 0.55)
			elif w.has("snd_fire"):
				# light autocannons: no loader crew, just the gun
				w["ammo"] = int(w["ammo"]) - 1
				_set_cd(w)
				_fire_round(w)
				main.sfx.play(String(w["snd_fire"]), float(w.get("fire_vol", 0.0)), float(w.get("fire_pitch", 1.0)) * randf_range(0.97, 1.03))
				main.kick(float(w.get("kick", 0.3)))
			else:
				_fire_howitzer(w)
		"missile":
			_launch_missile(w)
		"rockets", "drones":
			var extra := int(main.stat("add_salvo")) if w["kind"] == "rockets" else int(main.stat("add_drones"))
			var n := mini(int(w["salvo"]) + extra, int(w["ammo"]) + extra)
			w["ammo"] = maxi(0, int(w["ammo"]) - n + extra)
			_set_cd(w)
			w["salvo_left"] = n
			w["salvo_acc"] = 1.0
			w["salvo_target"] = main.aim_point
			w["salvo_fuze"] = fuze_of(w)
			w["salvo_n"] = n
			# the crowds this swarm's drones have already picked, so they spread themselves out
			w["salvo_claims"] = []
			if w["kind"] == "drones":
				main.radio("FCO", "Micro-missiles away, picking targets." if w.get("seek", false) else "Switchblades away. They'll find the crowd.")
		"cruise":
			_launch_cruise(w)
		"bomb", "cluster", "darts", "napalm", "mines", "thermite":
			_release_bomb(w)
		"glocke":
			if glocke.is_empty():
				_call_glocke(w)
		"singularity":
			_call_singularity(w)
		"apache":
			if apaches.is_empty():
				_call_apaches(w)
		"b52":
			if b52.is_empty():
				_call_b52(w)
		"constellation":
			_call_constellation(w)
		"cows":
			_launch_cow(w)
		"cas":
			if jets.is_empty():
				_call_cas(w)
		"himars":
			_call_himars(w)
		"boulder":
			_call_boulder(w)
		"titan":
			if titan.is_empty():
				_call_titan(w)
		"orbital":
			_call_rod(w)
		"a10":
			if a10.is_empty():
				call_a10(main.aim_point)
				w["ammo"] = int(w["ammo"]) - 1
				_set_cd(w)
		"arty", "tos":
			_call_mission(w)
		"wingman":
			if wingman.is_empty():
				_call_wingman(w)
		"sol":
			if sol.is_empty():
				_call_sol(w)


func _fire_howitzer(w: Dictionary) -> void:
	w["ammo"] = int(w["ammo"]) - 1
	_set_cd(w)
	_fire_round(w)
	main.sfx.play("howitzer", 0.0, randf_range(0.97, 1.02))
	main.sfx.play("casing", -8.0, 1.0, 0.8)
	main.sfx.play("breech", -5.0, 1.0, maxf(0.3, float(w["cd"]) - 1.3))
	main.kick(1.0)


## Fire one round from a gun at the sensor's aim point.
func _fire_round(w: Dictionary) -> void:
	if w.has("arcs"):
		_tesla(w)
		return
	if w.has("tof_fixed"):
		_orbital_round(w)
		return
	var mv: float = float(w["mv"]) * main.stat("mv")
	var muzzle: Vector3 = main.mount_pos(w["off"])
	var tof: float = muzzle.distance_to(main.aim_point) / mv
	var target: Vector3 = main.fire_point(tof)
	var sig_k := 1.0
	if w.has("smart"):
		# smart rounds: each one is handed its own infected near the crosshair and steers onto it
		var sr: float = w["smart"]
		var zi: int = main.horde.nearest(target + Vector3(randf_range(-sr, sr), 0.0, randf_range(-sr, sr)), sr * 0.6)
		if zi >= 0:
			var zp: Vector2 = main.horde.pos_at(zi, main.t + tof)
			target = Vector3(zp.x, 0.9, zp.y)
			sig_k = 0.0
	var los := target - muzzle
	var dist := los.length()
	if dist < 1.0:
		return
	var dir := los / dist
	var u := dir.cross(Vector3.UP).normalized()
	var v := u.cross(dir)
	var sig: float = float(w["disp"]) * dist * main.stat("disp") * sig_k
	var pt := target + u * randfn(0.0, sig) + v * randfn(0.0, sig)
	var ray := (pt - muzzle).normalized()
	var hit: Dictionary = main.raycast(muzzle, muzzle + ray * dist * 1.6)
	if hit.is_empty():
		return
	launch_shell(muzzle, hit["position"], mv, w, float(w["heat"]), float(w["tw"]), float(w["streak"]), false)
	main.shots_fired += 1


func launch_shell(muzzle: Vector3, ip: Vector3, mv: float, w: Dictionary, heat: float, width: float, streak: float, support: bool, fuze := "-") -> void:
	var tf := muzzle.distance_to(ip) / mv
	var v0 := (ip - muzzle) / tf + Vector3(0.0, 0.5 * G * tf, 0.0)
	main.fx.tracer(muzzle, v0, tf, heat, width, streak)
	# our own rounds carry the fuze set when they were fired; other people's go off on impact
	var fz := fuze if fuze != "-" else ("" if support else fuze_of(w))
	pending.append([main.t + tf, ip, w, support, Vector3(v0.x, 0.0, v0.z).normalized(), fz])


func _impact(ip: Vector3, w: Dictionary, support: bool, dir := Vector3.ZERO, fuze := "") -> void:
	match String(w["id"]):
		"beehive":
			_beehive(ip, w, dir)
			return
		"rail":
			_rail_impact(ip, w, dir)
			return
		"davy":
			_nuke(ip, w)
			return
		"pellet":
			# a thermite pellet: a small burst, then a fire that burns down over time
			_add_fire(ip, ip, 7.0, 4.0, 20.0)
			main.fx.particle(true, ip + Vector3.UP, Vector3.UP * 2.0, randf_range(10.0, 18.0), 3.0, 6.0, 1.5, 1, -0.02, 0.4)
		"wp105":
			_add_fire(ip, ip, float(w["fire_r"]), float(w["fire_dps"]), float(w["fire_t"]))
			for j in 14:
				main.fx.particle(false, ip + Vector3(randf_range(-6, 6), 2.0, randf_range(-6, 6)), (Vector3(randf_range(-1, 1), 1.2, randf_range(-1, 1)).normalized()) * randf_range(15, 40), randf_range(8.0, 14.0), 3.0, 18.0, 1.1, 2, 0.4, 0.5)
		"ripsaw":
			_rail_impact(ip, w, dir)
			return
		"chrono":
			_chrono(ip, w)
			return
		"graviton":
			wells.append({"c": ip, "t": 0.0, "dur": float(w["well_t"]), "w": w, "acc": 0.0})
			main.fx.explosion(ip, 13)
			return
		"atomic":
			main.fx.mini_nuke(ip)
			main.flash = maxf(main.flash, 0.22)
			main.kick(0.5)
		"piano":
			# it lands on a chord: root, major third, fifth
			var root := randf_range(0.5, 0.6)
			for p: float in [1.0, 1.26, 1.5]:
				main.sfx.play_at("beep", ip, main.cam.global_position, 4.0, p * root)
		"cow":
			main.fx.particle(true, ip + Vector3.UP, Vector3.UP * 3.0, 0.8, 2.0, 8.0, 1.0, 1)
	# perks and upgrades: bigger, harder hits, and the occasional lucky double-radius blast
	var R: float = main.stat("radius")
	if randf() < main.stat("add_crit"):
		R *= 2.0
	var D: float = main.stat("dmg")
	# the fuze shapes the blast
	var fm := fuze_fx(fuze)
	var rk := float(w["r_kill"]) * R * float(fm["kill"])
	var rf := maxf(float(w["r_frag"]) * R * float(fm["frag"]), rk * 1.05)
	var tnt := tnt_of(w)
	var k: int = main.horde.blast(ip, rk, rf, float(w["dmg"]) * D * float(fm["dmg"]), float(w["fling"]) * float(fm["fling"]))
	# The shock wave (the same ring the sensor shows): the inner three quarters of it kills
	# whatever's standing in it, and the outer quarter only throws them back. Bosses ride it out.
	if tnt > 0.0:
		var rs := minf(33.0 * pow(tnt, 1.0 / 3.0), 2600.0)
		var fl := clampf(maxf(float(w["fling"]), rs * 0.4), 4.0, 60.0)
		k += main.horde.blast(ip, rs * 0.75, rs * 0.76, 1.0e6, fl, 0.0, INF, true)
		main.horde.shove(ip, rs * 0.75, rs, maxf(rs * 0.15, 2.0))
	var sc := clampf(float(w["r_frag"]) / 12.0, 0.3, 6.0)
	match fuze:
		"AIRBURST":
			main.fx.airburst(ip, clampf(float(w["r_kill"]) * 0.6, 4.0, 18.0), sc, maxf(tnt, 0.0))
		"DELAY":
			main.fx.delay_burst(ip, sc, maxf(tnt, 0.0), ip.y > 2.0)
			# buried in a boss, it goes off inside it
			k += main.horde.boss_hit(ip, rk + 3.0, float(w["dmg"]) * D * (float(fm["boss"]) - 1.0))
		_:
			main.fx.explosion(ip, int(w["fx"]), tnt)
	if main.missions:
		main.missions.structure_hit(ip, maxf(tnt, 0.0), fuze)
	if w["kind"] in ["rotary", "auto", "cannon"] and randf() < main.stat("add_ignite"):
		_add_fire(ip, ip, 5.0, 3.0, 8.0)
	if w.has("split"):
		_split(ip, int(w["split"]))
	if int(w.get("bounce", 0)) > 0:
		_ricochet(ip, int(w["bounce"]))
	if k > 0 and w.has("rp_mult"):
		main.bonus_rp(int(round(k * (float(w["rp_mult"]) - 1.0))), ip)
		main.fx.particle(true, ip + Vector3.UP * 2.0, Vector3.UP * 4.0, 0.6, 1.0, 5.0, 2.2, 3, 0.0, 0.5)
	var snd := String(w["snd"])
	if snd != "":
		snd_ctr += 1
		if snd_ctr % int(w["snd_every"]) == 0:
			main.sfx.play_at(snd, ip, main.cam.global_position, float(w["vol"]))
	main.on_impact(ip, w, k, support)


# ------------------------------------------------------------------ the silly guns
## Scattershot: the shell bursts overhead into bomblets that rain across a small circle.
func _split(ip: Vector3, n: int) -> void:
	var burst := ip + Vector3.UP * 9.0
	for j in n:
		var off := Vector2.from_angle(randf() * TAU) * sqrt(randf()) * 16.0
		var land := ip + Vector3(off.x, 0.0, off.y)
		var hit: Dictionary = main.raycast(land + Vector3.UP * 60.0, land + Vector3.DOWN * 20.0)
		if hit.is_empty():
			continue
		var tp: Vector3 = hit["position"]
		var tf := randf_range(0.25, 0.55)
		main.fx.tracer(burst, (tp - burst) / tf + Vector3(0.0, 0.5 * G * tf, 0.0), tf, 1.3, 0.07, 0.03)
		pending.append([main.t + tf, tp, hidden["bomblet"], false, Vector3.ZERO])


## Ricochet rifle: the round leaves its victim for the next one nearby, `left` more times.
func _ricochet(ip: Vector3, left: int) -> void:
	var zi: int = main.horde.nearest(ip + Vector3(randf_range(-12, 12), 0.0, randf_range(-12, 12)), 14.0)
	if zi < 0:
		return
	var zp: Vector2 = main.horde.pos_at(zi, main.t + 0.06)
	var to := Vector3(zp.x, 0.6, zp.y)
	if to.distance_to(ip) < 1.0:
		return
	var from := ip + Vector3.UP * 0.6
	var tf := maxf(from.distance_to(to) / 420.0, 0.02)
	main.fx.tracer(from, (to - from) / tf + Vector3(0.0, 0.5 * G * tf, 0.0), tf, 1.5, 0.06, 0.03)
	pending.append([main.t + tf, to, hidden["rico%d" % (left - 1)], false, Vector3.ZERO])


## Tesla arc projector: a lightning bolt from the aircraft that jumps on through the crowd.
func _tesla(w: Dictionary) -> void:
	var muzzle: Vector3 = main.mount_pos(w["off"])
	var aim: Vector3 = main.fire_point(0.0)
	var dist := muzzle.distance_to(aim)
	var sig: float = float(w["disp"]) * dist * main.stat("disp")
	var target := aim + Vector3(randfn(0.0, sig), 0.0, randfn(0.0, sig))
	var zi: int = main.horde.nearest(target, 10.0)
	if zi >= 0:
		var zp: Vector2 = main.horde.pos_of(zi)
		target = Vector3(zp.x, 0.0, zp.y)
	var hit: Dictionary = main.raycast(target + Vector3.UP * 200.0, target + Vector3.DOWN * 20.0)
	if not hit.is_empty():
		target = hit["position"]
	# drawn from partway down the path: right at the lens a bolt would fill the screen
	_bolt(muzzle.lerp(target, 0.45), target)
	_impact(target, w, false)
	var from := target
	for c in int(w["arcs"]):
		var zj: int = main.horde.nearest(from + Vector3(randf_range(-14, 14), 0.0, randf_range(-14, 14)), 12.0)
		if zj < 0:
			break
		var zq: Vector2 = main.horde.pos_of(zj)
		var nxt := Vector3(zq.x, 0.5, zq.y)
		_bolt(from + Vector3.UP, nxt)
		_impact(nxt, hidden["arc"], false)
		from = nxt
	main.shots_fired += 1
	main.flash = maxf(main.flash, 0.04)


## God's Gatling: each round is a small tungsten rod dropped from orbit onto the crosshair.
func _orbital_round(w: Dictionary) -> void:
	var tf: float = w["tof_fixed"]
	var aim: Vector3 = main.fire_point(tf)
	var sig: float = float(w["disp"]) * main.aim_range * main.stat("disp")
	var target := aim + Vector3(randfn(0.0, sig), 0.0, randfn(0.0, sig))
	var hit: Dictionary = main.raycast(target + Vector3.UP * 400.0, target + Vector3.DOWN * 30.0)
	if not hit.is_empty():
		target = hit["position"]
	var p0 := target + Vector3(randf_range(-120, 120), 5000.0, randf_range(-120, 120))
	main.fx.tracer(p0, (target - p0) / tf + Vector3(0.0, 0.5 * G * tf, 0.0), tf, float(w["heat"]), float(w["tw"]), float(w["streak"]))
	pending.append([main.t + tf, target, w, false, Vector3.ZERO])
	main.shots_fired += 1


## Chrono cannon: a flash, and everything nearby is somewhere else, much further out.
func _chrono(ip: Vector3, w: Dictionary) -> void:
	var R: float = main.stat("radius")
	# the heart of the hit is simply erased
	var kr: float = float(w.get("kill_r", 0.0)) * R
	if kr > 0.0:
		var k0: int = main.horde.blast(ip, kr, kr * 1.4, 60.0 * main.stat("dmg"), 4.0)
		main.add_kills(k0, ip, false)
	var n: int = main.horde.rewind(ip, float(w["r_kill"]) * R, float(w["rewind"]))
	main.fx.particle(true, ip + Vector3.UP, Vector3.ZERO, 0.35, 2.0, float(w["r_kill"]) * R * 2.4, 2.4, 4)
	main.fx.particle(true, ip + Vector3.UP * 2.0, Vector3.ZERO, 0.12, 1.0, 9.0, 2.8, 0)
	main.fx.decal(ip, float(w["r_kill"]) * R, 0.95, 0.3, 8.0)
	if n > 0:
		main.popups.append({"pos": ip + Vector3(0, 6, 0), "text": "-%d  REWOUND" % n, "t": main.real_t, "big": n >= 25})
		main.sfx.play_at("charge", ip, main.cam.global_position, -6.0, 0.5)


# ------------------------------------------------------------------ beehive & railgun
## Flechette round: bursts short and above the target, raking a lane down-range.
func _beehive(ip: Vector3, w: Dictionary, dir: Vector3) -> void:
	if dir == Vector3.ZERO:
		dir = Vector3.FORWARD
	var burst := ip - dir * 30.0 + Vector3.UP * 22.0
	main.fx.particle(true, burst, Vector3.ZERO, 0.08, 2.0, 7.0, 1.8, 0)
	for k in 70:
		var land := ip + dir * randf_range(-10.0, 65.0) + dir.cross(Vector3.UP) * randf_range(-1.0, 1.0) * randf_range(2.0, 12.0)
		var tf := randf_range(0.08, 0.2)
		main.fx.tracer(burst, (land - burst) / tf, tf, 1.2, 0.05, 0.03)
		if k % 2 == 0:
			main.fx.particle(false, land + Vector3.UP * 0.4, Vector3.UP * 1.5, randf_range(0.8, 1.4), 0.6, 2.0, 0.42, 2, 0.0, 1.0)
	var k2: int = main.horde.line_blast(ip - dir * 15.0, ip + dir * 90.0, float(w["r_kill"]) + 1.5, float(w["dmg"]), float(w["fling"]), 0.85)
	main.sfx.play_at("cluster", ip, main.cam.global_position, 2.0, 1.3)
	main.on_impact(ip, w, k2, false)


func _update_rail(w: Dictionary, dt: float, want: bool) -> void:
	if want and float(w["cd"]) <= 0.0 and int(w["ammo"]) > 0:
		if rail_charge <= 0.0:
			main.sfx.play("charge", -4.0)
		rail_charge += dt
		if rail_charge >= 1.2:
			rail_charge = 0.0
			w["ammo"] = int(w["ammo"]) - 1
			_set_cd(w)
			_fire_round(w)
			main.sfx.play("railgun", 0.0)
			main.kick(1.2)
			main.flash = maxf(main.flash, 0.15)
	else:
		rail_charge = 0.0


## The slug hits, skips and keeps going: a trench of destruction along the line of fire.
func _rail_impact(ip: Vector3, w: Dictionary, dir: Vector3) -> void:
	if dir == Vector3.ZERO:
		dir = Vector3.FORWARD
	var end := ip + dir * float(w["trench"])
	var hit: Dictionary = main.raycast(ip + Vector3.UP * 1.5, end + Vector3.UP * 1.5)
	if not hit.is_empty():
		end = hit["position"]
	var k: int = main.horde.line_blast(ip, end, float(w["r_kill"]), float(w["dmg"]) * main.stat("dmg"), float(w["fling"]))
	main.fx.particle(true, ip + Vector3.UP, Vector3.ZERO, 0.12, 4.0, float(w.get("trench_flash", 22.0)), 2.2, 0)
	var length := ip.distance_to(end)
	var n := int(length / 7.0)
	for i in n:
		var p := ip.lerp(end, float(i) / maxf(n, 1))
		main.fx.particle(false, p + Vector3.UP, Vector3.UP * randf_range(4, 9) + dir.cross(Vector3.UP) * randf_range(-6, 6), randf_range(3.0, 5.0), 3.0, 9.0, 0.5, 2, 0.1, 0.8)
		if i % 2 == 0:
			main.fx.decal(Vector3(p.x, 0.0, p.z), 4.0, 0.95, 0.4, 25.0)
		if i % 3 == 0:
			main.fx.particle(true, p, Vector3(randf_range(-20, 20), randf_range(10, 30), randf_range(-20, 20)), 0.8, 0.6, 0.4, 1.5, 3, 1.0, 0.4)
	main.sfx.play_at("exp_med", ip, main.cam.global_position, float(w["vol"]))
	main.on_impact(ip, w, k, false)


# ------------------------------------------------------------------ laser
func _set_beam(node: MeshInstance3D, a: Vector3, b: Vector3, width: float, heat: float) -> void:
	var d := b - a
	var L := d.length()
	if L < 0.5:
		node.visible = false
		return
	var up := Vector3.UP if absf(d.y / L) < 0.98 else Vector3.FORWARD
	var lb := Basis.looking_at(d / L, up)
	node.global_transform = Transform3D(Basis(lb.x * width, lb.y * width, lb.z * L), (a + b) * 0.5)
	node.visible = true
	(node.material_override as ShaderMaterial).set_shader_parameter("heat", heat)


func _update_laser(w: Dictionary, dt: float, want: bool) -> void:
	var cap: float = w["cap"]
	if want and float(w["charge"]) > 0.0 and not w["hot"]:
		w["charge"] = float(w["charge"]) - dt
		var src: Vector3 = main.mount_pos(w["off"])
		var dst: Vector3 = main.aim_point
		if w.has("hpm"):
			# microwaves are invisible: only the ground ring where the cone lands shimmers
			beam_node.visible = false
			if randf() < dt * 8.0:
				main.fx.particle(true, dst + Vector3.UP * 0.4, Vector3.ZERO, 0.45, float(w["r_kill"]) * 0.6, float(w["r_kill"]) * 2.1, 0.9, 4)
			beam_pitch = 0.5
		else:
			# draw only the far 60% of the path, fading in: near the lens a real beam is invisible
			_set_beam(beam_node, src.lerp(dst, 0.4), dst, 0.35 + randf() * 0.15, 2.8)
			(beam_node.material_override as ShaderMaterial).set_shader_parameter("fade_source", 0.5)
			beam_pitch = 1.0
		beam_on = true
		var k: int = main.horde.line_blast(dst, dst, float(w["r_kill"]), float(w["dps"]) * dt, 1.5)
		laser_kill_acc += k
		main.add_kills(k, dst, false)
		main.fx.particle(true, dst + Vector3.UP * 0.5, Vector3.UP * 3.0, 0.25, 2.0, 4.0, 1.6, 1)
		if randf() < 0.5:
			main.fx.particle(true, dst, Vector3(randf_range(-1, 1), 1.5, randf_range(-1, 1)).normalized() * randf_range(10, 25), 0.5, 0.3, 0.2, 1.4, 3, 1.0, 0.5)
		if randf() < dt * 8.0:
			main.fx.decal(Vector3(dst.x, 0.0, dst.z), 3.0, 1.1, 0.42, 20.0)
		laser_popup_t += dt
		if laser_popup_t > 0.6:
			laser_popup_t = 0.0
			if laser_kill_acc > 0:
				main.popups.append({"pos": dst + Vector3(0, 4, 0), "text": "+%d" % laser_kill_acc, "t": main.real_t, "big": laser_kill_acc >= 25})
				laser_kill_acc = 0
		if float(w["charge"]) <= 0.0:
			w["hot"] = true
			main.radio("FCO", "Laser's drained, recharging the capacitor bank.")
	else:
		if beam_node.visible and w["id"] == current()["id"]:
			beam_node.visible = false
		w["charge"] = minf(cap, float(w["charge"]) + dt * float(w["recharge"]))
		if w["hot"] and float(w["charge"]) > cap * 0.3:
			w["hot"] = false
	w["ammo"] = int(float(w["charge"]) / cap * 100.0)


# ------------------------------------------------------------------ Hellfire & rockets
func _launch_missile(w: Dictionary) -> void:
	w["ammo"] = int(w["ammo"]) - 1
	_set_cd(w)
	var side := 1.0 if int(w["ammo"]) % 2 == 0 else -1.0
	var pos: Vector3 = main.mount_pos(Vector3(9.0 * side, -1.4, 1.5))
	missiles.append({"pos": pos, "vel": main.air_vel + Vector3.DOWN * 6.0, "t": 0.0, "node": _node(missile_mesh, mat_hot, pos), "w": w, "guided": true, "fuze": fuze_of(w)})
	main.sfx.play("hellfire_launch", -1.0)
	main.sfx.play("lock", -10.0)
	main.radio("FCO", "Rifle. Keep the laser on it.")


func _node(mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	add_child(node)
	node.global_position = pos
	return node


## Ripple-fired salvos (rockets) and swarm launches (drones) go out one at a time.
func _update_salvo(w: Dictionary, dt: float) -> void:
	if int(w.get("salvo_left", 0)) <= 0:
		return
	var launch_rate := 13.0 if w["kind"] == "rockets" else (24.0 if w.get("seek", false) else 7.0)
	w["salvo_acc"] = float(w["salvo_acc"]) + dt * launch_rate
	while float(w["salvo_acc"]) >= 1.0 and int(w["salvo_left"]) > 0:
		w["salvo_acc"] = float(w["salvo_acc"]) - 1.0
		w["salvo_left"] = int(w["salvo_left"]) - 1
		var side := 1.0 if int(w["salvo_left"]) % 2 == 0 else -1.0
		var pos: Vector3 = main.mount_pos(Vector3(7.0 * side, -1.6, 2.0))
		if w["kind"] == "rockets":
			# unguided: the fire-control solution plus a rocket's natural scatter
			var target: Vector3 = main.fire_point(pos.distance_to(main.aim_point) / float(w["mv"]))
			var d := pos.distance_to(target)
			var T := d / float(w["mv"])
			var v0 := (target - pos) / T + Vector3(0.0, 0.5 * G * T, 0.0)
			var sc := float(w["disp"]) * float(w["mv"])
			v0 += Vector3(randfn(0.0, sc), randfn(0.0, sc * 0.5), randfn(0.0, sc))
			missiles.append({"pos": pos, "vel": v0, "t": 0.0, "node": _node(missile_mesh, mat_hot, pos), "w": w, "guided": false, "fuze": String(w.get("salvo_fuze", ""))})
			main.sfx.play("rocket", -7.0, randf_range(0.9, 1.1))
			main.kick(0.15)
		elif w.get("seek", false):
			# micro-missiles: each one is handed its own infected near the mark and goes straight for it
			var area: Vector3 = w["salvo_target"]
			var tgt := area + Vector3(randf_range(-90, 90), 0.0, randf_range(-90, 90))
			var zi: int = main.horde.nearest(tgt, 45.0)
			if zi >= 0:
				var zp: Vector2 = main.horde.pos_at(zi, main.t + 3.0)
				tgt = Vector3(zp.x, 0.0, zp.y)
			var v0: Vector3 = main.air_vel + (Vector3(randf_range(-1, 1), randf_range(-0.6, 0.4), randf_range(-1, 1)).normalized() * 60.0)
			drones.append({"pos": pos, "vel": v0, "t": 0.0, "phase": 1, "area": area, "target": tgt, "node": _node(missile_mesh, mat_hot, pos), "w": w})
			main.sfx.play("rocket", -12.0, randf_range(1.3, 1.6))
		else:
			var area: Vector3 = w["salvo_target"]
			# each one loiters a little longer than the last, so they go in one after another
			var idx := int(w.get("salvo_n", 1)) - int(w["salvo_left"]) - 1
			drones.append({"pos": pos, "vel": main.air_vel + Vector3.DOWN * 5.0, "t": 0.0, "phase": 0, "area": area, "target": area,
				"node": _node(drone_mesh, mat_hot, pos), "w": w, "loiter": 3.0 + idx * 0.55, "claims": w["salvo_claims"]})
			main.sfx.play("drone_launch", -8.0, randf_range(0.9, 1.1))


func _update_missiles(dt: float) -> void:
	var spot: Vector3 = main.aim_point
	for k in range(missiles.size() - 1, -1, -1):
		var m: Dictionary = missiles[k]
		m["t"] = float(m["t"]) + dt
		var t: float = m["t"]
		var pos: Vector3 = m["pos"]
		var vel: Vector3 = m["vel"]
		if not m["guided"]:
			vel += Vector3.DOWN * G * dt
		elif t < 0.35:
			vel += Vector3.DOWN * G * dt
		else:
			# semi-active laser homing on the designator spot under the crosshair. The lofted
			# missiles fly high (holding well above the line of sight), then push over into a
			# steep terminal dive onto the spot; APKWS just goes straight in.
			var mw: Dictionary = m["w"]
			var speed := minf(float(mw["mv"]), 70.0 + (t - 0.35) * 260.0)
			var goal := spot
			var turn := 1.8
			var loft: float = LOFT.get(String(mw["id"]), 0.0)
			if loft > 0.0 and not m.get("terminal", false):
				var flat_d := Vector2(spot.x - pos.x, spot.z - pos.z).length()
				if atan2(pos.y - spot.y, flat_d) > deg_to_rad(40.0) or flat_d < 320.0:
					m["terminal"] = true
					if m.get("pip", false):
						main.sfx.play("lock", -12.0, 1.4)
				else:
					goal = spot + Vector3.UP * minf(flat_d * loft, 450.0)
			if m.get("terminal", false):
				turn = 3.2
			var want := (goal - pos).normalized()
			var cd := vel.normalized()
			var ang := cd.angle_to(want)
			var nd := cd if ang < 0.0001 else cd.slerp(want, minf(1.0, turn * dt / ang))
			vel = nd * speed
		var np := pos + vel * dt
		var hit: Dictionary = main.raycast(pos, np + vel.normalized() * 0.5)
		var node: MeshInstance3D = m["node"]
		if not hit.is_empty() or t > 30.0:
			var ip: Vector3 = hit.get("position", np)
			node.queue_free()
			missiles.remove_at(k)
			_impact(ip, m["w"], false, Vector3(vel.x, 0.0, vel.z).normalized(), String(m.get("fuze", "")))
			continue
		m["pos"] = np
		m["vel"] = vel
		node.global_position = np
		if absf(vel.normalized().y) < 0.995:
			node.look_at(np + vel, Vector3.UP)
		if m.has("spin"):
			# livestock tumbles; it does not have a rocket motor
			node.rotate_object_local(Vector3.RIGHT, t * float(m["spin"]))
			continue
		var back := -vel.normalized()
		main.fx.particle(true, np + back * 1.2, back * 20.0, 0.12, 1.4, 0.6, 1.7, 1)
		if t > 0.3 and (m["guided"] or randf() < 0.5):
			main.fx.particle(false, np + back * 2.0, Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)), randf_range(2.0, 4.0), 1.0, 5.0, 0.58, 2, -0.01, 0.6)


# ------------------------------------------------------------------ drones
## Switchblades cruise to the marked area and loiter over it in a wide circle, each one sniffing
## out a crowd none of the others has picked; then, one after another, they dive.
## Phases: 0 cruise, 2 loiter, 1 terminal dive. Micro-missiles go straight to phase 1.
func _update_drones(dt: float) -> void:
	for k in range(drones.size() - 1, -1, -1):
		var d: Dictionary = drones[k]
		d["t"] = float(d["t"]) + dt
		var pos: Vector3 = d["pos"]
		var vel: Vector3 = d["vel"]
		var area: Vector3 = d["area"]
		var node: MeshInstance3D = d["node"]
		var w: Dictionary = d["w"]
		var goal: Vector3
		var speed := float(w["mv"])
		if int(d["phase"]) == 0:
			goal = area + Vector3.UP * 140.0
			if Vector2(pos.x - area.x, pos.z - area.z).length() < 220.0 and float(d["t"]) > 1.0:
				d["phase"] = 2
				d["orbit_a"] = atan2(pos.z - area.z, pos.x - area.x)
				d["orbit_r"] = randf_range(110.0, 170.0)
				d["loiter_until"] = float(d["t"]) + float(d.get("loiter", 3.0))
		if int(d["phase"]) == 2:
			# circling, searching: aim a little ahead round the circle
			var orb_r: float = d["orbit_r"]
			d["orbit_a"] = float(d["orbit_a"]) + speed * 0.85 / orb_r * dt
			var a := float(d["orbit_a"]) + 0.45
			goal = area + Vector3(cos(a) * orb_r, 150.0 + sin(float(d["t"]) * 1.3) * 8.0, sin(a) * orb_r)
			if float(d["t"]) >= float(d["loiter_until"]):
				d["phase"] = 1
				var claims: Array = d.get("claims", [])
				var tgt := _densest_unclaimed(area, 170.0, claims)
				claims.append(tgt)
				d["target"] = tgt
				main.sfx.play_at("drone_launch", pos, main.cam.global_position, -4.0, 1.6)
		if int(d["phase"]) == 1:
			goal = d["target"]
			speed *= 1.25
		var want := (goal - pos).normalized()
		var cd := vel.normalized() if vel.length() > 1.0 else want
		var ang := cd.angle_to(want)
		var seeker: bool = w.get("seek", false)
		var nd := cd if ang < 0.0001 else cd.slerp(want, minf(1.0, (5.0 if seeker else 2.5) * dt / ang))
		vel = nd * minf(speed, vel.length() + (220.0 if seeker else 80.0) * dt)
		var np := pos + vel * dt
		var hit: Dictionary = main.raycast(pos, np + vel.normalized())
		if not hit.is_empty() or float(d["t"]) > 40.0:
			node.queue_free()
			drones.remove_at(k)
			_impact(hit.get("position", np), w, false)
			continue
		d["pos"] = np
		d["vel"] = vel
		node.global_position = np
		if absf(vel.normalized().y) < 0.995:
			node.look_at(np + vel, Vector3.UP)
		if randf() < 0.3:
			main.fx.particle(true, np - vel.normalized() * 1.0, Vector3.ZERO, 0.3, 0.8, 0.4, 1.2, 1)


## The thickest crowd near center that isn't within 25 m of one already claimed.
func _densest_unclaimed(center: Vector3, r: float, claims: Array) -> Vector3:
	var best := center
	var bn := -1
	for i in 18:
		var p := center + Vector3(randf_range(-r, r), 0.0, randf_range(-r, r))
		var taken := false
		for c in claims:
			if (c as Vector3).distance_to(p) < 25.0:
				taken = true
				break
		if taken:
			continue
		var n: int = main.horde.count_near(p, 10.0)
		if n > bn:
			bn = n
			best = p
	return best


func _densest_near(center: Vector3, r: float) -> Vector3:
	var best := center
	var bn := -1
	for i in 14:
		var p := center + Vector3(randf_range(-r, r), 0.0, randf_range(-r, r))
		var n: int = main.horde.count_near(p, 10.0)
		if n > bn:
			bn = n
			best = p
	return best


# ------------------------------------------------------------------ bombs
func _release_bomb(w: Dictionary) -> void:
	w["ammo"] = int(w["ammo"]) - 1
	_set_cd(w)
	var p0: Vector3 = main.mount_pos(Vector3(0.0, -3.0, -14.0))
	var T := float(w["tof_base"]) + p0.distance_to(main.aim_point) / float(w["tof_speed"])
	var target: Vector3 = main.fire_point(T)
	# guided fall: leaves with the aircraft's momentum, then curves onto the coordinate
	var ctrl: Vector3 = p0 + main.air_vel * T * 0.35 + Vector3.DOWN * 40.0
	var mesh := BoxMesh.new()
	var L: float = w["len"]
	mesh.size = w.get("box", Vector3(L * 0.22, L * 0.22, L))
	var dir := Vector3(target.x - p0.x, 0.0, target.z - p0.z).normalized()
	var b := {"p0": p0, "ctrl": ctrl, "target": target, "T": T, "t": 0.0, "w": w, "node": _node(mesh, mat_bomb, p0), "opened": false, "dir": dir, "fuze": fuze_of(w)}
	if w.get("track", false):
		# a moving-target seeker: the point-tracked infected, or whichever is nearest the mark
		var ti: int = main.track_lock if main.track_lock >= 0 else main.horde.nearest(target, 40.0)
		if ti >= 0:
			b["track_i"] = ti
	bombs.append(b)
	main.sfx.play("bomb_release", -2.0)
	main.kick(0.25)
	match String(w["id"]):
		"sdb":
			main.radio("FCO", "Bomb away. Time of fall %d seconds." % int(T))
		"cbu":
			main.radio("FCO", "CBU away, canister opens over the target.")
		"lazydog":
			main.radio("FCO", "Darts away. Lazy Dog, lazy dog.")
		"napalm":
			main.radio("FCO", "Fire bomb away. Stand by for the light show.")
		"gator":
			main.radio("FCO", "Gator away, seeding the approach.")
		"jdam":
			main.radio("FCO", "Two thousand pounder away! Impact in %d." % int(T))
		"moab":
			main.radio("LOADMASTER", "MOAB is out the ramp! Extraction chute good!")
		"mop":
			main.radio("LOADMASTER", "MOP is out the ramp! Fifteen tons! Impact in %d!" % int(T))
		"stormbreaker":
			main.radio("FCO", "StormBreaker away, seeker's tracking the mover." if bombs[bombs.size() - 1].has("track_i") else "StormBreaker away.")
		"piano":
			if randf() < 0.4:
				main.radio("LOADMASTER", ["Piano away. Mind your heads.", "That one was a Steinway.", "It's out of tune anyway.", "Encore!"].pick_random())
		"nuke":
			main.radio("PILOT", "Weapon released. God help us. Impact in %d seconds." % int(T))
			main.sfx.play("alarm", -6.0, 0.8)
		"neutron":
			main.radio("PILOT", "Enhanced radiation weapon released. Impact in %d." % int(T))
			main.sfx.play("alarm", -6.0, 0.7)


func _launch_cruise(w: Dictionary) -> void:
	w["ammo"] = int(w["ammo"]) - 1
	_set_cd(w)
	var target: Vector3 = main.fire_point(24.0)
	var route := street_route(target)
	var path := make_path(route["pts"])
	var T: float = float(path["len"]) / 250.0
	var p0: Vector3 = (route["pts"] as Array)[0]
	var last := target - path_at(path, float(path["len"]) - 80.0)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.6, 0.6, 6.0)
	bombs.append({"p0": p0, "ctrl": p0, "target": target, "T": T, "t": 0.0, "w": w, "node": _node(mesh, mat_hot, p0), "opened": false,
		"dir": Vector3(last.x, 0.0, last.z).normalized(), "fuze": fuze_of(w), "path": path})
	main.radio("NAVY", "Tomahawk away from the Arleigh Burke. Ingress down the %s at rooftop height, time of flight %d seconds." % [String(route["name"]), int(T)])
	main.sfx.play("beep", -6.0, 0.7)


## A cruise missile's way in: it comes down the avenue that lines up best with the target, low
## between the buildings, cuts across the rooftops if the target is off the street, then pops up
## and dives. {pts, name}
func street_route(target: Vector3) -> Dictionary:
	var flat := Vector2(target.x, target.z)
	var best: Dictionary = {}
	var bd := INF
	for c in main.corridors:
		if int(c["type"]) != 0:
			continue
		var d := Vector2(cos(float(c["ang"])), sin(float(c["ang"])))
		var along := flat.dot(d)
		var lat := absf(flat.cross(d)) if along > 0.0 else flat.length() + 400.0
		if lat < bd:
			bd = lat
			best = c
	if best.is_empty():
		var from := flat.normalized() if flat.length() > 10.0 else Vector2.RIGHT
		var f3 := Vector3(from.x, 0.0, from.y)
		return {"pts": [target + f3 * 6000.0 + Vector3.UP * 120.0, target + f3 * 2000.0 + Vector3.UP * 60.0, target + f3 * 420.0 + Vector3.UP * 260.0, target] as Array[Vector3], "name": "approach"}
	var dv := Vector2(cos(float(best["ang"])), sin(float(best["ang"])))
	var d3 := Vector3(dv.x, 0.0, dv.y)
	var along := clampf(flat.dot(dv), 250.0, 5500.0)
	var low := 32.0
	var pts: Array[Vector3] = [d3 * (along + 5200.0) + Vector3.UP * 140.0, d3 * (along + 3000.0) + Vector3.UP * low, d3 * (along + 1300.0) + Vector3.UP * low]
	if bd > 60.0:
		# off the avenue: leave it abreast of the target and cut across the rooftops
		var turn := d3 * (along + 500.0) + Vector3.UP * low
		pts.append(turn)
		var to := Vector3(target.x - turn.x, 0.0, target.z - turn.z)
		pts.append(target - to.normalized() * minf(420.0, to.length() * 0.6) + Vector3.UP * 260.0)
	else:
		pts.append(d3 * (along + 420.0) + Vector3.UP * 260.0)
	pts.append(target)
	var sector := String(main.SECTORS[main.horde.sector_of(dv.x, dv.y)]).to_lower()
	return {"pts": pts, "name": "%s avenue" % sector}


func bomb_pos(b: Dictionary, u: float) -> Vector3:
	if b.has("path"):
		var path: Dictionary = b["path"]
		return path_at(path, u * float(path["len"]))
	var p0: Vector3 = b["p0"]
	var c: Vector3 = b["ctrl"]
	var p1: Vector3 = b["target"]
	if b.has("c2"):
		var c2: Vector3 = b["c2"]
		var v := 1.0 - u
		return p0 * v * v * v + c * 3.0 * v * v * u + c2 * 3.0 * v * u * u + p1 * u * u * u
	return p0 * (1.0 - u) * (1.0 - u) + c * 2.0 * u * (1.0 - u) + p1 * u * u


func _update_bombs(dt: float) -> void:
	for k in range(bombs.size() - 1, -1, -1):
		var b: Dictionary = bombs[k]
		b["t"] = float(b["t"]) + dt
		var u := float(b["t"]) / float(b["T"])
		var w: Dictionary = b["w"]
		var kind := String(w["kind"])
		var node: MeshInstance3D = b["node"]
		if b.has("track_i"):
			# steer onto where the tracked infected will be at impact
			var ti: int = b["track_i"]
			if main.horde.z_alive[ti] == 1:
				var zp: Vector2 = main.horde.pos_at(ti, main.t + maxf(float(b["T"]) - float(b["t"]), 0.0))
				b["target"] = Vector3(zp.x, 0.0, zp.y)
			else:
				b.erase("track_i")
		if kind in ["cluster", "darts", "mines", "thermite"] and u >= 0.86 and not b["opened"]:
			b["opened"] = true
			_dispense(b, bomb_pos(b, u))
			node.visible = false
		if u >= 1.0:
			node.queue_free()
			bombs.remove_at(k)
			match kind:
				"nuke", "neutron":
					_nuke(b["target"], w)
				"napalm":
					_napalm(b["target"], b["dir"], w)
				"cluster", "darts", "mines", "thermite":
					pass
				_:
					_impact(b["target"], w, false, b["dir"], String(b.get("fuze", "")))
			continue
		var p := bomb_pos(b, u)
		var ahead := bomb_pos(b, minf(u + 0.01, 1.0))
		node.global_position = p
		if (ahead - p).length() > 0.01 and absf((ahead - p).normalized().y) < 0.995:
			node.look_at(ahead, Vector3.UP)
		if w["id"] == "moab" and fmod(float(b["t"]), 0.1) < dt:
			main.fx.particle(false, p + Vector3.UP * 6.0, Vector3.ZERO, 0.4, 7.0, 7.0, 0.4, 2)
		if kind == "cruise":
			main.fx.particle(true, p - (ahead - p).normalized() * 3.0, Vector3.ZERO, 0.2, 1.5, 0.8, 1.6, 1)


## Canisters that open over the target: skeets, darts or mines.
func _dispense(b: Dictionary, pos: Vector3) -> void:
	var w: Dictionary = b["w"]
	var target: Vector3 = b["target"]
	main.fx.particle(true, pos, Vector3.ZERO, 0.12, 2.0, 12.0, 1.6, 0)
	var spread: float = w.get("spread", 70.0)
	match String(w["kind"]):
		"cluster":
			main.sfx.play_at("cluster", target, main.cam.global_position, float(w["vol"]))
			for i in int(w["subs"]):
				_sub_drop(pos, target, spread, hidden["skeet"], randf_range(0.5, 1.5), 1.4, 0.15)
		"thermite":
			main.sfx.play_at("cluster", target, main.cam.global_position, 0.0, 0.8)
			for i in int(w["subs"]):
				_sub_drop(pos, target, spread, hidden["pellet"], randf_range(0.6, 1.4), 2.0, 0.2)
		"darts":
			# hundreds of steel darts: a few kill by direct hit, the area pass does the rest
			for i in 260:
				_sub_drop(pos, target, spread, hidden["dart"], randf_range(0.7, 1.2), 0.9, 0.04)
			pending.append([main.t + 1.0, target, w, false, Vector3.ZERO])
			main.sfx.play_at("cluster", target, main.cam.global_position, -2.0, 1.7)
		"mines":
			for i in int(w["subs"]):
				var off := Vector2.from_angle(randf() * TAU) * sqrt(randf()) * spread
				var aim := target + Vector3(off.x, 0.0, off.y * 0.7)
				var hit: Dictionary = main.raycast(aim + Vector3.UP * 300.0, aim + Vector3.DOWN * 50.0)
				if hit.is_empty():
					continue
				var ip: Vector3 = hit["position"]
				var tf := randf_range(0.5, 1.4)
				main.fx.tracer(pos, (ip - pos) / tf + Vector3(0.0, 0.5 * G * tf, 0.0), tf, 1.0, 0.1, 0.03)
				mines.append({"pos": ip, "armed": main.t + tf + 1.0, "until": main.t + 240.0})
				main.fx.decal(ip, 1.4, 0.62, 0.5, 400.0)


func _sub_drop(pos: Vector3, target: Vector3, spread: float, w: Dictionary, tf: float, heat: float, width: float) -> void:
	var off := Vector2.from_angle(randf() * TAU) * sqrt(randf()) * spread
	var aim := target + Vector3(off.x, 0.0, off.y * 0.7)
	var hit: Dictionary = main.raycast(aim + Vector3.UP * 300.0, aim + Vector3.DOWN * 50.0)
	if hit.is_empty():
		return
	var ip: Vector3 = hit["position"]
	main.fx.tracer(pos, (ip - pos) / tf + Vector3(0.0, 0.5 * G * tf, 0.0), tf, heat, width, 0.04)
	pending.append([main.t + tf, ip, w, false, Vector3.ZERO])


## Mk-77: a strip of burning gel along the bomb's line of travel that burns for half a minute.
func _napalm(target: Vector3, dir: Vector3, w: Dictionary) -> void:
	var a := target - dir * 70.0
	var b := target + dir * 90.0
	main.horde.burn_kills = true
	var k: int = main.horde.line_blast(a, b, float(w["r_kill"]), float(w["dmg"]) * main.stat("dmg"), float(w["fling"]))
	main.horde.burn_kills = false
	main.on_impact(target, w, k, false)
	_add_fire(a, b, float(w["r_kill"]) * 0.85, float(w["dps"]), float(w["burn"]))
	main.sfx.play_at("napalm", target, main.cam.global_position, float(w["vol"]))
	for i in 18:
		var p := a.lerp(b, i / 17.0) + Vector3(randf_range(-6, 6), 0.0, randf_range(-6, 6))
		main.fx.particle(true, p + Vector3.UP * 4.0, Vector3.UP * randf_range(4, 10), randf_range(1.2, 2.2), 6.0, 20.0, 1.6, 1, -0.05, 1.0)
		main.fx.decal(Vector3(p.x, 0.0, p.z), randf_range(14.0, 22.0), 1.35, 0.5, 70.0)
	for i in 70:
		var p := a.lerp(b, randf()) + Vector3(randf_range(-12, 12), 0.0, randf_range(-12, 12))
		main.fx.particle(true, p + Vector3.UP * 2.0, Vector3.UP * randf_range(1, 3), randf_range(16.0, float(w["burn"])), randf_range(4.0, 7.0), randf_range(6.0, 11.0), 1.45, 1, -0.01, 0.6)
	for i in 10:
		var p := a.lerp(b, randf())
		main.fx.particle(false, p + Vector3.UP * 12.0, Vector3.UP * randf_range(6, 10), randf_range(20.0, 30.0), 12.0, 40.0, 0.55, 2, -0.02, 0.2)


## A burning area (a strip from a to b, or a disc when a == b). Fires cool as they burn:
## damage falls off with the fuel until the ground is back at ambient.
func _add_fire(a: Vector3, b: Vector3, r: float, dps: float, dur: float) -> void:
	zones.append({"a": a, "b": b, "r": r, "dps": dps * main.stat("fire_dps"), "t0": main.t, "dur": dur * main.stat("fire_dur")})
	# whatever burns stays burnt
	var n := maxi(1, int(a.distance_to(b) / 15.0))
	for i in n + 1:
		main.scorch(a.lerp(b, float(i) / float(n)), r * 1.2, 0.75)
	while zones.size() > 160:
		zones.pop_front()


func _update_zones(dt: float) -> void:
	zone_tick += dt
	if zone_tick < 0.25:
		return
	var step := zone_tick
	zone_tick = 0.0
	for k in range(zones.size() - 1, -1, -1):
		var z: Dictionary = zones[k]
		var frac := 1.0 - (float(main.t) - float(z["t0"])) / float(z["dur"])
		if frac <= 0.0:
			zones.remove_at(k)
			continue
		# a hot fire kills fast; a dying one barely singes
		var dps: float = float(z["dps"]) * pow(frac, 1.5) * main.stat("dmg") * main.weather_fire()
		var a: Vector3 = z["a"]
		var b: Vector3 = z["b"]
		main.horde.burn_kills = true
		var kills: int = main.horde.line_blast(a, b, float(z["r"]), dps * step, 1.0)
		main.horde.burn_kills = false
		main.add_kills(kills, (a + b) * 0.5, false)
		# the flames themselves cool toward ambient as the zone burns down
		if randf() < 0.3 + frac:
			var p := a.lerp(b, randf()) + Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)) * float(z["r"]) * 0.7
			main.fx.particle(true, p + Vector3.UP * 1.5, Vector3.UP * (1.0 + 3.0 * frac), randf_range(1.5, 3.0), 2.0 + 3.0 * frac, 4.0 + 6.0 * frac, 0.35 + 1.1 * frac, 1, -0.02, 0.5)


func _update_mines(dt: float) -> void:
	var now: float = main.t
	for k in range(mines.size() - 1, -1, -1):
		var m: Dictionary = mines[k]
		if now > float(m["until"]):
			mines.remove_at(k)
			continue
		if now < float(m["armed"]):
			continue
		if main.horde.nearest(m["pos"], 2.0) >= 0:
			mines.remove_at(k)
			_impact(m["pos"], hidden["mine"], false)


# ------------------------------------------------------------------ THOR
func _call_rod(w: Dictionary) -> void:
	w["ammo"] = int(w["ammo"]) - 1
	_set_cd(w)
	rods.append({"t": 0.0, "target": main.fire_point(float(w["delay"])), "w": w, "launched": false})
	main.sfx.play("lock", -6.0, 0.7)
	if w["id"] == "lrhw":
		main.radio("DARK EAGLE", "Dark Eagle away from two thousand kilometres. Mach seventeen. Impact in %d." % int(w["delay"]))
	else:
		main.radio("THOR", "Kinetic strike authorized. Rod impact in %d seconds." % int(w["delay"]))


func _update_rods(dt: float) -> void:
	for k in range(rods.size() - 1, -1, -1):
		var r: Dictionary = rods[k]
		r["t"] = float(r["t"]) + dt
		var w: Dictionary = r["w"]
		var delay: float = w["delay"]
		if float(r["t"]) >= delay - 2.0 and not r["launched"]:
			r["launched"] = true
			var target: Vector3 = r["target"]
			var p0 := target + Vector3(randf_range(-250, 250), 6000.0, randf_range(-250, 250))
			var tf := 2.0
			main.fx.tracer(p0, (target - p0) / tf + Vector3(0.0, 0.5 * G * tf, 0.0), tf, 3.0, 1.6, 0.12)
			pending.append([main.t + tf, target, w, false, Vector3.ZERO])
			rods.remove_at(k)


# ------------------------------------------------------------------ SOL
func _call_sol(w: Dictionary) -> void:
	w["ammo"] = int(w["ammo"]) - 1
	_set_cd(w)
	sol = {"t": 0.0, "dur": float(w["dur"]), "spot": main.aim_point, "w": w}
	main.radio("SOL", "Beam is live. It follows your designator. Twelve seconds.")
	main.sfx.play("charge", 0.0, 0.6)


func _update_sol(dt: float) -> void:
	if sol.is_empty():
		sol_node.visible = false
		return
	sol["t"] = float(sol["t"]) + dt
	var w: Dictionary = sol["w"]
	var spot: Vector3 = sol["spot"]
	var to: Vector3 = main.aim_point - spot
	var step := minf(to.length(), 75.0 * dt)
	var prev := spot
	if to.length() > 0.01:
		spot += to.normalized() * step
	sol["spot"] = spot
	_set_beam(sol_node, spot, spot + Vector3.UP * 4000.0, 7.0 + randf() * 2.0, 3.2)
	beam_on = true
	beam_pitch = 0.55
	var k: int = main.horde.line_blast(prev, spot, float(w["r_kill"]), float(w["dps"]) * dt + 0.5, 6.0)
	main.add_kills(k, spot, false)
	laser_kill_acc += k
	main.fx.particle(true, spot + Vector3.UP * 2.0, Vector3.UP * 12.0, 0.35, 10.0, 22.0, 2.0, 1)
	for i in 2:
		main.fx.particle(true, spot, Vector3(randf_range(-1, 1), 1.0, randf_range(-1, 1)).normalized() * randf_range(20, 60), 1.0, 0.8, 0.5, 1.6, 3, 1.0, 0.4)
	if randf() < dt * 14.0:
		main.fx.decal(Vector3(spot.x, 0.0, spot.z), 20.0, 1.4, 0.55, 90.0)
	if randf() < dt * 3.0:
		main.fx.particle(false, spot + Vector3.UP * 8.0, Vector3.UP * 10.0, 8.0, 10.0, 30.0, 0.6, 2, -0.02, 0.3)
	main.flash = maxf(main.flash, 0.08)
	laser_popup_t += dt
	if laser_popup_t > 0.6:
		laser_popup_t = 0.0
		if laser_kill_acc > 0:
			main.popups.append({"pos": spot + Vector3(0, 6, 0), "text": "+%d" % laser_kill_acc, "t": main.real_t, "big": laser_kill_acc >= 25})
			laser_kill_acc = 0
	if float(sol["t"]) >= float(sol["dur"]):
		sol = {}
		sol_node.visible = false
		main.radio("SOL", "Beam secure. Satellite repositioning.")


# ------------------------------------------------------------------ fire missions
## Artillery and rocket artillery: real calls, real delays, rounds arriving from afar.
func _call_mission(w: Dictionary) -> void:
	w["ammo"] = int(w["ammo"]) - 1
	_set_cd(w)
	var target: Vector3 = main.fire_point(8.0 if w["kind"] == "tos" else 14.0)
	var from := Vector2.from_angle(randf() * TAU)
	var tos: bool = w["kind"] == "tos"
	var shots: Array = []
	var n := 24 if tos else 18
	for i in n:
		var t_hit: float = main.t + (8.0 + i * 0.22 if tos else 11.0 + i * 0.45 + randf_range(-0.1, 0.1))
		var off := Vector2(randfn(0.0, 55.0), randfn(0.0, 28.0)) if tos else Vector2(randfn(0.0, 30.0), randfn(0.0, 30.0))
		var along := Vector2(-from.y, from.x)
		var p := Vector2(target.x, target.z) + from * off.y + along * off.x if tos else Vector2(target.x + off.x, target.z + off.y)
		shots.append({"t": t_hit, "p": Vector3(p.x, 0.0, p.y), "fired": false})
	missions.append({"w": w, "shots": shots, "from": from, "tos": tos, "splash": false, "t0": main.t})
	if tos:
		main.radio("RAZOR", "Razor six, TOS salvo on your mark. Rockets in the air in five.")
		main.sfx.play("barrage", -10.0, 1.0, 2.0)
	else:
		main.radio("KING", "King battery, fire mission, eighteen rounds HE. Shot, over.")
		main.sfx.play("arty", -12.0, 1.0, 0.5)


func _update_missions(dt: float) -> void:
	for k in range(missions.size() - 1, -1, -1):
		var m: Dictionary = missions[k]
		var shots: Array = m["shots"]
		var tos: bool = m["tos"]
		var from: Vector2 = m["from"]
		var all_done := true
		if not m["splash"] and not shots.is_empty() and main.t > float(shots[0]["t"]) - 5.0:
			m["splash"] = true
			if not tos and not m.has("quiet"):
				main.radio("KING", "Splash, over.")
		# per-mission flight: TOS and 155 by default, HIMARS brings its own
		var tf: float = m.get("tf", 3.0 if tos else 2.4)
		var dist: float = m.get("dist", 2600.0 if tos else 1400.0)
		var alt: float = m.get("alt", 650.0 if tos else 1200.0)
		var heat: float = m.get("heat", 1.8 if tos else 1.4)
		var width: float = m.get("width", 0.5 if tos else 0.3)
		var sub: Dictionary = m.get("sub", hidden["tos"] if tos else hidden["shell155"])
		for s in shots:
			if s["fired"]:
				continue
			all_done = false
			if main.t >= float(s["t"]) - tf:
				s["fired"] = true
				var hit: Dictionary = main.raycast(s["p"] + Vector3.UP * 400.0, s["p"] + Vector3.DOWN * 20.0)
				var ip: Vector3 = hit.get("position", s["p"])
				var p0: Vector3 = ip + Vector3(from.x, 0.0, from.y) * dist + Vector3.UP * alt
				var v0 := (ip - p0) / tf + Vector3(0.0, 0.5 * G * tf, 0.0)
				main.fx.tracer(p0, v0, tf, heat, width, 0.1)
				pending.append([main.t + tf, ip, sub, false, Vector3.ZERO])
		if all_done:
			missions.remove_at(k)


## HIMARS: six GMLRS unitary rockets, one on the mark and five in a ring around it,
## diving almost vertically out of a 70 km lob.
func _call_himars(w: Dictionary) -> void:
	w["ammo"] = int(w["ammo"]) - 1
	_set_cd(w)
	var target: Vector3 = main.fire_point(14.0)
	var shots: Array = []
	for i in 6:
		var a := TAU * i / 6.0
		var off := Vector2.ZERO if i == 0 else Vector2(cos(a), sin(a)) * 55.0
		shots.append({"t": main.t + 14.0 + i * 0.6, "p": Vector3(target.x + off.x, 0.0, target.z + off.y), "fired": false})
	missions.append({"w": w, "shots": shots, "from": Vector2.from_angle(randf() * TAU), "tos": false, "splash": false, "t0": main.t,
		"label": "HIMARS GMLRS", "sub": hidden["gmlrs"], "tf": 4.0, "dist": 700.0, "alt": 5000.0, "heat": 2.0, "width": 0.6, "quiet": true})
	main.radio("STEEL RAIN", "Steel Rain two-three, six GMLRS unitary on your coordinates. Time of flight fourteen seconds.")
	main.sfx.play("barrage", -14.0, 0.7, 1.0)


# ------------------------------------------------------------------ F-16 CAS
## Two Vipers check in at a holding point, run to the IP, then down the run-in heading (outbound
## and away from friendlies, or parallel to the wall when it's close) walking four GBU-38s each
## through the mark, the wingman a few seconds in trail, and break away from the refuge.
func _call_cas(w: Dictionary) -> void:
	w["ammo"] = int(w["ammo"]) - 1
	_set_cd(w)
	var tgt: Vector3 = main.fire_point(24.0)
	var flat := Vector2(tgt.x, tgt.z)
	var out := Vector3(flat.x, 0.0, flat.y).normalized() if flat.length() > 10.0 else Vector3.RIGHT
	var run := run_in(tgt)
	var lat := Vector3(-run.z, 0.0, run.x)
	var alt := 900.0
	for j in 2:
		var lane := lat * 22.0 * (j * 2 - 1)
		var drops: Array = []
		for b in 4:
			var dp := tgt + lane + run * (-60.0 + 40.0 * b)
			var hit: Dictionary = main.raycast(dp + Vector3.UP * 400.0, dp + Vector3.DOWN * 30.0)
			drops.append(hit.get("position", dp))
		var ip := tgt + lane - run * 4200.0 + Vector3.UP * alt
		var hold := ip - run * 1800.0 + lat * 1500.0 + Vector3.UP * 200.0
		var entry := tgt + lane - run * 1500.0 + Vector3.UP * alt
		var exit := tgt + lane + run * 700.0 + Vector3.UP * alt
		var brk := exit + run * 1200.0 + out * 1000.0 + Vector3.UP * 600.0
		var gone := brk + out * 3500.0 + Vector3.UP * 1200.0
		var path := make_path([hold, ip, entry, exit, brk, gone] as Array[Vector3])
		var wd: PackedFloat32Array = path["wd"]
		jets.append({"s": -1300.0 * j, "path": path, "pos": hold, "dir": run, "drops": drops, "next": 0, "ip": ip, "ip_s": wd[1],
			"node": _node(a10_mesh, mat_world, hold), "heard": false, "at_ip": false, "lead": j == 0})
	main.radio("VIPER", "Viper one-one, two-ship, GBU-38s. IP inbound, run-in heading %03d, egress %s." % [_heading(run), String(main.SECTORS[main.horde.sector_of(out.x, out.z)]).to_lower()])


func _update_jets(dt: float) -> void:
	var speed := 230.0
	var fall := 6.0
	var throw := speed * fall * 0.7
	for k in range(jets.size() - 1, -1, -1):
		var j: Dictionary = jets[k]
		j["s"] = float(j["s"]) + speed * dt
		var s: float = j["s"]
		var node: MeshInstance3D = j["node"]
		if s < 0.0:
			# the wingman, still a few seconds in trail
			node.visible = false
			continue
		node.visible = true
		var path: Dictionary = j["path"]
		var fwd := fly_on_path(node, path, s, speed)
		var pos := node.global_position
		var dir := Vector3(fwd.x, 0.0, fwd.z).normalized()
		j["pos"] = pos
		j["dir"] = dir
		main.fx.particle(true, pos - fwd * 9.0, -fwd * 20.0, 0.25, 1.5, 3.0, 1.2, 1)
		if j["lead"] and not j["at_ip"] and s >= float(j["ip_s"]):
			j["at_ip"] = true
			main.radio("VIPER", "Viper one-one, IP, in hot.")
		var drops: Array = j["drops"]
		while int(j["next"]) < drops.size():
			var tp: Vector3 = drops[int(j["next"])]
			if Vector2(tp.x - pos.x, tp.z - pos.z).dot(Vector2(dir.x, dir.z)) > throw:
				break
			j["next"] = int(j["next"]) + 1
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.45, 0.45, 2.4)
			bombs.append({"p0": pos, "ctrl": pos + dir * speed * fall * 0.5 + Vector3.DOWN * 120.0, "target": tp, "T": fall, "t": 0.0,
				"w": hidden["gbu38"], "node": _node(mesh, mat_bomb, pos), "opened": false, "dir": dir})
			if not j["heard"]:
				j["heard"] = true
				main.sfx.play_at("a10_flyby", pos, main.cam.global_position, 8.0, 1.35)
				if j["lead"]:
					main.radio("VIPER", "Bombs away. Breaking off.")
		if s >= float(path["len"]):
			node.queue_free()
			jets.remove_at(k)


# ------------------------------------------------------------------ Spectre 2-2
func _call_wingman(w: Dictionary) -> void:
	w["ammo"] = int(w["ammo"]) - 1
	_set_cd(w)
	wingman = {"t": 0.0, "dur": 50.0, "acc40": 0.0, "acc105": 3.0, "node": _node(gunship_mesh, mat_world, main.air_pos)}
	main.radio("SPECTRE 2-2", "Two-two on station, opposite side of your orbit. Engaging targets of opportunity.")


func wingman_pos() -> Vector3:
	var th: float = main.theta + PI
	return main.orbit_center + Vector3(cos(th) * main.orbit_r, main.alt + 60.0, sin(th) * main.orbit_r)


func _update_wingman(dt: float) -> void:
	if wingman.is_empty():
		return
	wingman["t"] = float(wingman["t"]) + dt
	var pos := wingman_pos()
	var th: float = main.theta + PI
	var fwd := Vector3(sin(th), 0.0, -cos(th))
	var node: MeshInstance3D = wingman["node"]
	node.global_position = pos
	node.look_at(pos + fwd, Vector3.UP)
	node.rotate_object_local(Vector3.FORWARD, -0.35)
	wingman["acc40"] = float(wingman["acc40"]) + dt
	wingman["acc105"] = float(wingman["acc105"]) + dt
	if float(wingman["acc40"]) > 0.55:
		wingman["acc40"] = 0.0
		_wingman_shot(pos, by_id("bofors"), 0.0012)
	if float(wingman["acc105"]) > 5.0:
		wingman["acc105"] = 0.0
		_wingman_shot(pos, by_id("m102"), 0.0007)
	if float(wingman["t"]) > float(wingman["dur"]):
		node.queue_free()
		wingman = {}
		main.radio("SPECTRE 2-2", "Two-two is Winchester, RTB. Good hunting.")


func _wingman_shot(pos: Vector3, gun: Dictionary, disp: float) -> void:
	# pick the thickest of a handful of sampled crowds, preferring ones closer to the refuge
	var best := Vector3.INF
	var bs := -1.0
	for i in 8:
		var p: Vector3 = main.horde.random_alive_pos()
		if p == Vector3.INF:
			continue
		var s: float = float(main.horde.count_near(p, 12.0)) / (1.0 + Vector2(p.x, p.z).length() / 600.0)
		if s > bs:
			bs = s
			best = p
	if best == Vector3.INF:
		return
	var muzzle := pos + Vector3.DOWN * 2.0
	var dist := muzzle.distance_to(best)
	var aim := best + Vector3(randfn(0.0, disp * dist), 0.0, randfn(0.0, disp * dist))
	var hit: Dictionary = main.raycast(muzzle, muzzle + (aim - muzzle) * 1.4)
	if hit.is_empty():
		return
	launch_shell(muzzle, hit["position"], float(gun["mv"]), gun, float(gun["heat"]), float(gun["tw"]), float(gun["streak"]), true)


# ------------------------------------------------------------------ nuclear
func _consent(w: Dictionary, dt: float) -> void:
	if float(w["cd"]) > 0.0 or int(w["ammo"]) <= 0:
		return
	var before := consent
	consent += dt
	var need: float = w["consent_t"]
	if int(before / 0.4) != int(consent / 0.4):
		main.sfx.play("beep", -4.0, 0.8 + consent / need * 0.6)
	if consent >= need:
		consent = 0.0
		if w["kind"] == "davy":
			w["ammo"] = int(w["ammo"]) - 1
			_set_cd(w)
			_fire_round(w)
			main.sfx.play("howitzer", 2.0, 0.85)
			main.kick(1.2)
			main.radio("FCO", "Davy Crockett away. Nobody look at it.")
		elif w["kind"] == "moon":
			if moon.is_empty():
				_call_moon(w)
		else:
			_release_bomb(w)


func _nuke(pos: Vector3, w: Dictionary) -> void:
	var neutron: bool = w["kind"] == "neutron"
	main.fx.nuke(pos, float(w["fx_scale"]), not neutron)
	main.sfx.play_at(String(w["snd"]), pos, main.cam.global_position, float(w["vol"]), float(w.get("pitch", 1.0)))
	if neutron:
		# a modest blast; the radiation does the rest over the next ten seconds
		var k: int = main.horde.blast(pos, float(w["r_kill"]), float(w["r_kill"]) * 1.6, float(w["dmg"]), float(w["fling"]))
		main.add_kills(k, pos, false)
		main.horde.irradiate(pos, float(w["r_frag"]), 10.0, 0.11)
	else:
		# the blast wave expands at the speed of sound and flattens everything it reaches
		var R: float = main.stat("radius")
		main.horde.nuclear_shock(pos, float(w["r_kill"]) * R, float(w["r_frag"]) * R, float(w["fling"]), float(w["dmg"]) * 1.5 * main.stat("dmg"))
	main.on_nuke(pos, w)


# ------------------------------------------------------------------ Die Glocke
var wells: Array = []


func _call_glocke(w: Dictionary) -> void:
	w["ammo"] = int(w["ammo"]) - 1
	_set_cd(w)
	var p: Vector3 = main.aim_point + Vector3.UP * 420.0
	glocke = {"t": 0.0, "dur": float(w["dur"]), "pos": p, "acc": 0.0, "w": w, "node": _node(bell_mesh, mat_world, p)}
	main.radio("???", "Something is humming on every frequency. It sounds like... a bell.")
	main.sfx.play("neutron", -8.0, 1.6)


## The bell descends over the mark, follows the crosshair, and strikes the thickest crowd
## beneath it with lightning that arcs on through the bodies.
func _update_glocke(dt: float) -> void:
	if glocke.is_empty():
		return
	glocke["t"] = float(glocke["t"]) + dt
	var t: float = glocke["t"]
	var node: MeshInstance3D = glocke["node"]
	var pos: Vector3 = glocke["pos"]
	var aim: Vector3 = main.aim_point
	var goal := Vector3(aim.x, 140.0 + sin(t * 1.3) * 4.0, aim.z)
	var to := goal - pos
	if to.length() > 0.01:
		pos += to.normalized() * minf(to.length(), (110.0 if t < 3.5 else 28.0) * dt)
	glocke["pos"] = pos
	node.global_position = pos
	node.rotate_y(dt * 2.4)
	beam_on = true
	beam_pitch = 0.35
	if t > 2.5:
		glocke["acc"] = float(glocke["acc"]) + dt
		while float(glocke["acc"]) > 0.22:
			glocke["acc"] = float(glocke["acc"]) - 0.22
			_glocke_strike(pos)
	if t > float(glocke["dur"]):
		node.queue_free()
		glocke = {}
		main.radio("???", "The humming stops. The bell is gone.")


func _glocke_strike(bell: Vector3) -> void:
	var target := _densest_near(Vector3(bell.x, 0.0, bell.z), 110.0)
	var hit: Dictionary = main.raycast(target + Vector3.UP * 300.0, target + Vector3.DOWN * 20.0)
	if not hit.is_empty():
		target = hit["position"]
	_bolt(bell + Vector3.DOWN * 5.0, target)
	_impact(target, hidden["bolt"], true)
	main.sfx.play_at("railgun", target, main.cam.global_position, -4.0, randf_range(0.7, 1.1))
	# the lightning arcs on through the crowd
	var from := target
	for c in 2:
		var zi: int = main.horde.nearest(from + Vector3(randf_range(-18, 18), 0.0, randf_range(-18, 18)), 14.0)
		if zi < 0:
			break
		var zp: Vector2 = main.horde.pos_of(zi)
		var nxt := Vector3(zp.x, 0.5, zp.y)
		_bolt(from + Vector3.UP, nxt)
		_impact(nxt, hidden["spark"], true)
		from = nxt
	main.flash = maxf(main.flash, 0.06)


## A jagged lightning bolt drawn with pooled beam segments; it lasts a fraction of a second.
func _bolt(a: Vector3, b: Vector3) -> void:
	var d := b - a
	if d.length() < 0.5:
		return
	var side := Vector3.RIGHT if absf(d.normalized().y) > 0.95 else d.cross(Vector3.UP).normalized()
	var side2 := d.cross(side).normalized()
	var segs := 6
	var pts: Array[Vector3] = [a]
	for i in range(1, segs):
		var f := float(i) / segs
		var j := d.length() * 0.06 * sin(PI * f)
		pts.append(a + d * f + side * randf_range(-j, j) + side2 * randf_range(-j, j))
	pts.append(b)
	for i in segs:
		var node := bolt_nodes[bolt_i]
		bolt_until[bolt_i] = main.t + 0.12
		bolt_i = (bolt_i + 1) % bolt_nodes.size()
		_set_beam(node, pts[i], pts[i + 1], 0.9, 5.0)
	main.fx.particle(true, b + Vector3.UP, Vector3.ZERO, 0.12, 2.0, 9.0, 2.2, 0)


# ------------------------------------------------------------------ singularity
func _call_singularity(w: Dictionary) -> void:
	w["ammo"] = int(w["ammo"]) - 1
	_set_cd(w)
	wells.append({"c": main.aim_point, "t": 0.0, "dur": float(w["dur"]), "w": w, "acc": 0.0})
	main.radio("FCO", "Singularity is up. Do not look directly at it.")
	main.sfx.play("charge", 0.0, 0.5)


## A growing well that drags the crowd inward (bodies fly toward it), then collapses in a blast.
func _update_wells(dt: float) -> void:
	for k in range(wells.size() - 1, -1, -1):
		var s: Dictionary = wells[k]
		s["t"] = float(s["t"]) + dt
		var t: float = s["t"]
		var c: Vector3 = s["c"]
		var w: Dictionary = s["w"]
		var R: float = main.stat("radius")
		var r := float(w["r_kill"]) * R * clampf(t / float(w.get("grow", 2.0)), 0.15, 1.0)
		beam_on = true
		beam_pitch = 0.3
		s["acc"] = float(s["acc"]) + dt
		if float(s["acc"]) >= 0.25:
			s["acc"] = 0.0
			var kills: int = main.horde.line_blast(c, c, r, float(w["dmg"]) * main.stat("dmg"), -float(w["fling"]))
			main.add_kills(kills, c, kills >= 5)
			main.fx.particle(true, c + Vector3.UP * 2.0, Vector3.ZERO, 0.5, r * 2.6, 3.0, 1.3, 4)
			main.fx.particle(true, c + Vector3.UP * 3.0, Vector3.ZERO, 0.3, 3.0, 1.0, 2.6, 0)
			for i in 6:
				var a := randf() * TAU
				var p := c + Vector3(cos(a), 0.0, sin(a)) * r
				main.fx.particle(true, p + Vector3.UP * randf_range(1.0, 6.0), (c - p) * 2.2, 0.45, 0.6, 0.2, 1.4, 3, 0.0, 0.0)
		if t >= float(s["dur"]):
			wells.remove_at(k)
			# the collapse: the singularity's is a huge blast, a graviton round's a pop
			var cr: float = float(w.get("collapse_r", 30.0)) * R
			var k2: int = main.horde.blast(c, cr, cr * 2.0, float(w.get("collapse_dmg", 40.0)) * main.stat("dmg"), 30.0)
			main.fx.explosion(c, int(w.get("collapse_fx", 5)), 200.0)
			main.fx.particle(true, c + Vector3.UP, Vector3.ZERO, 0.6, 2.0, cr * 8.7, 1.6, 4)
			main.sfx.play_at("exp_huge" if cr > 15.0 else "exp_med", c, main.cam.global_position, float(w.get("collapse_vol", 14.0)))
			main.flash = maxf(main.flash, float(w.get("collapse_flash", 0.5)))
			main.on_impact(c, w, k2, false)


# ------------------------------------------------------------------ Apaches
func _call_apaches(w: Dictionary) -> void:
	w["ammo"] = int(w["ammo"]) - 1
	_set_cd(w)
	var tgt: Vector3 = main.aim_point
	var flat := Vector2(tgt.x, tgt.z)
	var inward := -flat.normalized() if flat.length() > 10.0 else Vector2.RIGHT
	var inw := Vector3(inward.x, 0.0, inward.y)
	var lat := Vector3(-inward.y, 0.0, inward.x)
	var hovers: Array = []
	var posns: Array = []
	var nodes: Array = []
	for s: float in [-1.0, 1.0]:
		var hp := tgt + inw * 650.0 + lat * 90.0 * s + Vector3.UP * 120.0
		var start := hp + inw * 1600.0 + Vector3.UP * 80.0
		hovers.append(hp)
		posns.append(start)
		nodes.append(_node(heli_mesh, mat_world, start))
	apaches = {"t": 0.0, "dur": float(w["dur"]), "target": tgt, "hover": hovers, "pos": posns, "nodes": nodes, "acc_gun": 0.0, "acc_rkt": 0.0, "inw": inw}
	main.radio("GUNFIGHTER", "Gunfighter two-one, flight of two Apaches, inbound to your mark. Forty-five seconds of station time.")


func _update_apaches(dt: float) -> void:
	if apaches.is_empty():
		return
	apaches["t"] = float(apaches["t"]) + dt
	var t: float = apaches["t"]
	var tgt: Vector3 = apaches["target"]
	var leaving := t > float(apaches["dur"])
	var hovers: Array = apaches["hover"]
	var posns: Array = apaches["pos"]
	var nodes: Array = apaches["nodes"]
	var inw: Vector3 = apaches["inw"]
	for i in 2:
		var p: Vector3 = posns[i]
		var goal: Vector3 = hovers[i]
		if leaving:
			goal = p + inw * 300.0 + Vector3.UP * 40.0
		p = p.move_toward(goal + Vector3.UP * sin(t * 1.7 + i) * 2.0, 75.0 * dt)
		posns[i] = p
		var node: MeshInstance3D = nodes[i]
		node.global_position = p
		var look := Vector3(tgt.x, p.y, tgt.z)
		if Vector2(look.x - p.x, look.z - p.z).length() > 1.0:
			node.look_at(look, Vector3.UP)
	if not leaving and t > 7.0:
		apaches["acc_gun"] = float(apaches["acc_gun"]) + dt
		while float(apaches["acc_gun"]) > 0.1:
			apaches["acc_gun"] = float(apaches["acc_gun"]) - 0.1
			var muzzle: Vector3 = posns[randi() % 2] + Vector3.DOWN * 1.5
			var aim := _densest_near(tgt, 110.0)
			var dist := muzzle.distance_to(aim)
			aim += Vector3(randfn(0.0, 0.004 * dist), 0.0, randfn(0.0, 0.004 * dist))
			var hit: Dictionary = main.raycast(muzzle, muzzle + (aim - muzzle) * 1.3)
			if not hit.is_empty():
				launch_shell(muzzle, hit["position"], 800.0, hidden["m230"], 1.2, 0.08, 0.02, true)
		apaches["acc_rkt"] = float(apaches["acc_rkt"]) + dt
		if float(apaches["acc_rkt"]) > 2.6:
			apaches["acc_rkt"] = 0.0
			for i in 2:
				var from: Vector3 = posns[i] + Vector3.DOWN * 1.0
				var aim := _densest_near(tgt, 110.0)
				var T := from.distance_to(aim) / 450.0
				var v0 := (aim - from) / T + Vector3(0.0, 0.5 * G * T, 0.0)
				missiles.append({"pos": from, "vel": v0, "t": 0.0, "node": _node(missile_mesh, mat_hot, from), "w": hidden["hydra_ah"], "guided": false})
	if t > float(apaches["dur"]) + 18.0:
		for n in nodes:
			(n as MeshInstance3D).queue_free()
		apaches = {}
		main.radio("GUNFIGHTER", "Gunfighter is Winchester, RTB. Good luck down there.")


# ------------------------------------------------------------------ B-52 Arc Light
func _call_b52(w: Dictionary) -> void:
	w["ammo"] = int(w["ammo"]) - 1
	_set_cd(w)
	var tgt: Vector3 = main.aim_point
	var flat := Vector2(tgt.x, tgt.z)
	var out := Vector3(flat.x, 0.0, flat.y).normalized() if flat.length() > 10.0 else Vector3.RIGHT
	# the carpet runs along the approach through the mark, but never onto the refuge
	var centre_r := maxf(flat.length(), float(main.wall_r) + 760.0)
	var mid := out * centre_r
	var a := mid - out * 600.0
	var b := mid + out * 600.0
	var alt := 2400.0
	var start := a - out * 230.0 * 16.0 + Vector3.UP * alt
	b52 = {"t": 0.0, "pos": start, "dir": out, "a": a, "b": b, "dropped": 0, "node": _node(bomber_mesh, mat_world, start)}
	main.radio("BUFF 1-1", "Buff one-one, Arc Light inbound from the refuge side, release in eight seconds. Heads down.")
	main.sfx.play_at("a10_flyby", start, main.cam.global_position, 6.0, 0.5)


func _update_b52(dt: float) -> void:
	if b52.is_empty():
		return
	b52["t"] = float(b52["t"]) + dt
	var dir: Vector3 = b52["dir"]
	var pos: Vector3 = b52["pos"] + dir * 230.0 * dt
	b52["pos"] = pos
	var node: MeshInstance3D = b52["node"]
	node.global_position = pos
	node.look_at(pos + dir, Vector3.UP)
	main.fx.particle(true, pos - dir * 26.0, -dir * 20.0, 0.4, 3.0, 6.0, 0.9, 1)
	var a: Vector3 = b52["a"]
	var b: Vector3 = b52["b"]
	# bombs keep most of the bomber's speed as they fall, so each is released well short of its point
	var throw := 230.0 * 10.0 * 0.75
	var along := ((Vector3(pos.x, 0.0, pos.z) - a).dot(dir) + throw) / a.distance_to(b)
	var mk82: Dictionary = hidden["mk82"]
	while int(b52["dropped"]) < 51 and along >= float(b52["dropped"]) / 51.0:
		var f := float(b52["dropped"]) / 50.0
		b52["dropped"] = int(b52["dropped"]) + 1
		var p := a.lerp(b, f) + dir.cross(Vector3.UP) * randf_range(-35.0, 35.0)
		var hit: Dictionary = main.raycast(p + Vector3.UP * 400.0, p + Vector3.DOWN * 20.0)
		var tp: Vector3 = hit.get("position", p)
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.45, 0.45, 2.2)
		bombs.append({"p0": pos, "ctrl": pos + dir * 230.0 * 5.0 + Vector3.DOWN * 150.0, "target": tp, "T": 10.0, "t": 0.0, "w": mk82, "node": _node(mesh, mat_bomb, pos), "opened": false, "dir": dir})
		if int(b52["dropped"]) == 1:
			main.radio("BUFF 1-1", "Bombs away, bombs away.")
	if along > 3.5:
		node.queue_free()
		b52 = {}


# ------------------------------------------------------------------ THOR constellation
func _call_constellation(w: Dictionary) -> void:
	w["ammo"] = int(w["ammo"]) - 1
	_set_cd(w)
	var tgt: Vector3 = main.fire_point(float(w["delay"]))
	var flat := Vector2(tgt.x, tgt.z)
	var out := Vector3(flat.x, 0.0, flat.y).normalized() if flat.length() > 10.0 else Vector3.RIGHT
	for i in 12:
		var p := tgt + out * ((i - 5.5) * 30.0)
		var hit: Dictionary = main.raycast(p + Vector3.UP * 400.0, p + Vector3.DOWN * 20.0)
		rods.append({"t": -i * 0.35, "target": hit.get("position", p), "w": w, "launched": false})
	main.sfx.play("lock", -6.0, 0.6)
	main.radio("THOR", "Full constellation authorized. Twelve rods, walking fire. First impact in eight seconds.")


# ------------------------------------------------------------------ shenanigans
## Cow catapult: a live cow out of the ramp on a ballistic arc, tumbling all the way down.
func _launch_cow(w: Dictionary) -> void:
	w["ammo"] = int(w["ammo"]) - 1
	_set_cd(w)
	var pos: Vector3 = main.mount_pos(Vector3(0.0, -2.5, -14.0))
	var mv: float = float(w["mv"]) * main.stat("mv")
	var target: Vector3 = main.fire_point(pos.distance_to(main.aim_point) / mv)
	var T := maxf(pos.distance_to(target) / mv, 0.5)
	var v0 := (target - pos) / T + Vector3(0.0, 0.5 * G * T, 0.0)
	var sc: float = float(w["disp"]) * mv * main.stat("disp")
	v0 += Vector3(randfn(0.0, sc), randfn(0.0, sc * 0.4), randfn(0.0, sc))
	missiles.append({"pos": pos, "vel": v0, "t": 0.0, "node": _node(cow_mesh, mat_world, pos), "w": w, "guided": false, "spin": randf_range(3.0, 8.0)})
	main.sfx.play("breech", -3.0, 0.55)
	main.kick(0.12)
	if randf() < 0.08:
		main.radio("LOADMASTER", ["Cow away.", "That one had a name.", "Moo-ving out.", "Bessie, no!"].pick_random())


## The Boulder: falls onto the crosshair, then rolls outward along the approach, away from the
## refuge, flattening everything in its path until it has rolled its distance or left the map.
func _call_boulder(w: Dictionary) -> void:
	w["ammo"] = int(w["ammo"]) - 1
	_set_cd(w)
	var target: Vector3 = main.fire_point(1.5)
	var flat := Vector2(target.x, target.z)
	var out := Vector3(flat.x, 0.0, flat.y).normalized() if flat.length() > 10.0 else Vector3.RIGHT
	var start := target + Vector3.UP * 260.0
	boulders.append({"pos": start, "t": 0.0, "dir": out, "rolled": 0.0, "landed": false, "w": w,
		"node": _node(boulder_mesh, mat_world, start), "acc": 0.0, "kills": 0, "ground": target.y})
	main.radio("FCO", ["Boulder away. Do not ask where we got it.", "Rock and roll.", "Fore!"].pick_random())
	main.sfx.play("bomb_release", -2.0, 0.6)


func _update_boulders(dt: float) -> void:
	var radius := 7.5
	for k in range(boulders.size() - 1, -1, -1):
		var b: Dictionary = boulders[k]
		var w: Dictionary = b["w"]
		var node: MeshInstance3D = b["node"]
		b["t"] = float(b["t"]) + dt
		var pos: Vector3 = b["pos"]
		var dir: Vector3 = b["dir"]
		var R: float = main.stat("radius")
		if not b["landed"]:
			pos.y -= (40.0 + 180.0 * float(b["t"])) * dt
			if pos.y <= float(b["ground"]) + radius:
				pos.y = float(b["ground"]) + radius
				b["landed"] = true
				var gp := Vector3(pos.x, float(b["ground"]), pos.z)
				var k0: int = main.horde.blast(gp, 16.0 * R, 30.0 * R, 60.0 * main.stat("dmg"), 25.0)
				main.add_kills(k0, gp)
				b["kills"] = int(b["kills"]) + k0
				main.fx.explosion(gp, 2, 300.0)
				main.sfx.play_at("exp_large", gp, main.cam.global_position, 8.0, 0.5)
				main.kick(0.6)
			b["pos"] = pos
			node.global_position = pos
			continue
		var speed: float = w["speed"]
		var prev := pos
		pos += dir * speed * dt
		# hug the ground: hills, rubble, river banks
		var hit: Dictionary = main.raycast(pos + Vector3.UP * 200.0, pos + Vector3.DOWN * 200.0)
		if not hit.is_empty():
			pos.y = lerpf(pos.y, (hit["position"] as Vector3).y + radius, 1.0 - exp(-dt * 8.0))
		b["pos"] = pos
		b["rolled"] = float(b["rolled"]) + speed * dt
		node.global_position = pos
		node.rotate(Vector3.UP.cross(dir).normalized(), speed / radius * dt)
		var kills: int = main.horde.line_blast(prev, pos, float(w["r_kill"]) * R, float(w["dmg"]) * main.stat("dmg"), float(w["fling"]))
		if kills > 0:
			main.add_kills(kills, pos, false)
			b["kills"] = int(b["kills"]) + kills
		b["acc"] = float(b["acc"]) + dt
		if float(b["acc"]) > 0.35:
			b["acc"] = 0.0
			main.sfx.play_at("exp_small", pos, main.cam.global_position, -2.0, 0.35)
			main.fx.particle(false, pos - dir * radius + Vector3.UP * 2.0, -dir * 4.0 + Vector3.UP * 3.0, randf_range(3.0, 5.0), 6.0, 16.0, 0.5, 2, 0.0, 0.6)
			main.fx.decal(Vector3(pos.x, 0.0, pos.z), 9.0, 0.8, 0.4, 30.0)
		if float(b["rolled"]) >= float(w["roll"]) or Vector2(pos.x, pos.z).length() > 3300.0:
			node.queue_free()
			boulders.remove_at(k)
			main.fx.explosion(pos, 2, 300.0)
			var total: int = b["kills"]
			if total > 0:
				main.popups.append({"pos": pos + Vector3.UP * 20.0, "text": "ROCK +%s" % main.hud.commas(total), "t": main.real_t, "big": true})
				main._feed("THE BOULDER  +%s" % main.hud.commas(total))


## Titan: a 40 m friendly giant dropped on the mark. It stomps toward the thickest crowd nearby,
## and every footfall is a blast.
func _call_titan(w: Dictionary) -> void:
	w["ammo"] = int(w["ammo"]) - 1
	_set_cd(w)
	var target: Vector3 = main.fire_point(1.5)
	var start := target + Vector3.UP * 500.0
	var node := _node(titan_mesh, mat_titan, start)
	node.scale = Vector3.ONE * 22.0
	titan = {"pos": start, "ground": target.y, "t": 0.0, "dur": float(w["dur"]), "landed": false, "w": w, "node": node,
		"goal": target, "next_stomp": 0.0, "foot": 1.0, "kills": 0}
	main.radio("TITAN", "Titan one is falling to your mark. Stand by for planetfall.", true)
	main.sfx.play("alarm", -8.0, 0.5)


func _update_titan(dt: float) -> void:
	if titan.is_empty():
		return
	var w: Dictionary = titan["w"]
	var node: MeshInstance3D = titan["node"]
	titan["t"] = float(titan["t"]) + dt
	var t: float = titan["t"]
	var pos: Vector3 = titan["pos"]
	var R: float = main.stat("radius")
	if not titan["landed"]:
		pos.y -= (120.0 + 300.0 * t) * dt
		if pos.y <= float(titan["ground"]):
			pos.y = float(titan["ground"])
			titan["landed"] = true
			titan["t"] = 0.0
			var k0: int = main.horde.blast(pos, 30.0 * R, 60.0 * R, 80.0 * main.stat("dmg"), 40.0)
			main.add_kills(k0, pos)
			titan["kills"] = int(titan["kills"]) + k0
			main.fx.explosion(pos, 4, 60.0)
			main.sfx.play_at("exp_huge", pos, main.cam.global_position, 10.0, 0.6)
			main.kick(1.0)
			main.flash = maxf(main.flash, 0.2)
		titan["pos"] = pos
		node.global_position = pos
		return
	if t > float(titan["dur"]):
		# it leaves the way it came: a flash and gone
		main.fx.explosion(pos, 13)
		main.fx.particle(true, pos + Vector3.UP * 20.0, Vector3.UP * 30.0, 1.2, 10.0, 80.0, 2.0, 0)
		node.queue_free()
		var total: int = titan["kills"]
		main._feed("TITAN ONE  +%s" % main.hud.commas(total))
		main.radio("TITAN", "Titan one extracting. %s confirmed. It was an honour." % main.hud.commas(total))
		titan = {}
		return
	# walk toward the thickest crowd nearby, re-picking the goal every few strides
	var goal: Vector3 = titan["goal"]
	var to := Vector3(goal.x - pos.x, 0.0, goal.z - pos.z)
	if to.length() < 12.0 or fmod(t, 4.0) < dt:
		goal = _densest_near(pos, 260.0)
		titan["goal"] = goal
		to = Vector3(goal.x - pos.x, 0.0, goal.z - pos.z)
	var walking := to.length() > 6.0
	if walking:
		pos += to.normalized() * minf(9.0 * dt, to.length())
	var gy: float = titan["ground"]
	var hit: Dictionary = main.raycast(pos + Vector3.UP * 300.0, pos + Vector3.DOWN * 100.0)
	if not hit.is_empty():
		gy = (hit["position"] as Vector3).y
	titan["ground"] = gy
	titan["pos"] = pos
	var stride := sin(t * TAU / 1.2)
	node.global_position = Vector3(pos.x, gy + absf(stride) * 1.5, pos.z)
	if walking:
		node.look_at(Vector3(goal.x, node.global_position.y, goal.z), Vector3.UP)
		node.rotate_object_local(Vector3.FORWARD, stride * 0.06)
	# every footfall is a blast under the foot that came down
	if t >= float(titan["next_stomp"]):
		titan["next_stomp"] = t + 0.6
		var foot: float = titan["foot"]
		titan["foot"] = -foot
		var fwd := -node.global_transform.basis.z.normalized()
		var side := node.global_transform.basis.x.normalized()
		var fp := Vector3(pos.x, gy, pos.z) + fwd * 6.0 + side * foot * 4.0
		var k: int = main.horde.blast(fp, float(w["r_kill"]) * R, float(w["r_frag"]) * R, float(w["dmg"]) * main.stat("dmg"), float(w["fling"]))
		main.add_kills(k, fp, k >= 5)
		titan["kills"] = int(titan["kills"]) + k
		main.fx.explosion(fp, 2, 60.0)
		main.fx.decal(fp, 12.0, 0.9, 0.4, 40.0)
		main.sfx.play_at("exp_large", fp, main.cam.global_position, 2.0, 0.45)
		main.kick(0.15)


## Lunar strike: a 300 m moon falls out of the sky onto the designated point.
func _call_moon(w: Dictionary) -> void:
	w["ammo"] = int(w["ammo"]) - 1
	_set_cd(w)
	var delay: float = w["delay"]
	var target: Vector3 = main.fire_point(delay)
	var flat := Vector2(target.x, target.z)
	var out := Vector3(flat.x, 0.0, flat.y).normalized() if flat.length() > 10.0 else Vector3.RIGHT
	var start := target + out * 4000.0 + Vector3.UP * 9000.0
	var node := _node(boulder_mesh, mat_hot, start)
	node.scale = Vector3.ONE * 20.0
	moon = {"t": 0.0, "delay": delay, "start": start, "target": target, "node": node, "w": w}
	main.radio("TOC", "Spectre... Overwatch. Is that... is that a moon? All stations, brace. BRACE.", true)
	main.sfx.play("alarm", -2.0, 0.4)


func _update_moon(dt: float) -> void:
	if moon.is_empty():
		return
	moon["t"] = float(moon["t"]) + dt
	var u := clampf(float(moon["t"]) / float(moon["delay"]), 0.0, 1.0)
	var start: Vector3 = moon["start"]
	var target: Vector3 = moon["target"]
	var node: MeshInstance3D = moon["node"]
	# it falls faster and faster, and the whole airframe feels it coming
	var p := start.lerp(target + Vector3.UP * 150.0, u * u)
	node.global_position = p
	node.rotate_y(dt * 0.3)
	main.kick(0.1 + u * u * 0.8)
	if fmod(float(moon["t"]), 0.15) < dt:
		main.fx.particle(true, p + Vector3(randf_range(-150, 150), randf_range(-150, 150), randf_range(-150, 150)), Vector3.ZERO, 1.5, 60.0, 160.0, 1.6, 1, 0.0, 0.1)
	if u >= 1.0:
		var w: Dictionary = moon["w"]
		node.queue_free()
		moon = {}
		var R: float = main.stat("radius")
		main.horde.nuclear_shock(target, float(w["r_kill"]) * R, float(w["r_frag"]) * R, float(w["fling"]), float(w["dmg"]) * main.stat("dmg"), 600.0)
		main.fx.nuke(target, 2.0, true)
		main.fx.explosion(target, 6)
		main.sfx.play_at("nuke", target, main.cam.global_position, 20.0, 0.6)
		main.sfx.play_at("exp_huge", target, main.cam.global_position, 20.0, 0.4)
		main.on_moon(target, w)


## Meteor shower event: a rock out of the sky onto a random patch of horde.
func meteor() -> void:
	var p: Vector3 = main.horde.random_alive_pos()
	if p == Vector3.INF:
		var a := randf() * TAU
		p = Vector3(cos(a), 0.0, sin(a)) * randf_range(600.0, 2800.0)
	p += Vector3(randf_range(-30, 30), 0.0, randf_range(-30, 30))
	var hit: Dictionary = main.raycast(p + Vector3.UP * 500.0, p + Vector3.DOWN * 50.0)
	if not hit.is_empty():
		p = hit["position"]
	var tf := 2.2
	var p0 := p + Vector3(randf_range(-1500, 1500), 7000.0, randf_range(-1500, 1500))
	main.fx.tracer(p0, (p - p0) / tf + Vector3(0.0, 0.5 * G * tf, 0.0), tf, 3.0, 2.2, 0.15)
	pending.append([main.t + tf, p, hidden["meteor"], true, Vector3.ZERO])


# ------------------------------------------------------------------ flight paths
## A smooth path through waypoints (Catmull-Rom), sampled so it can be flown by distance.
func make_path(pts: Array[Vector3]) -> Dictionary:
	var samples := PackedVector3Array()
	var dists := PackedFloat32Array()
	# distance along the path at each waypoint
	var wd := PackedFloat32Array()
	var total := 0.0
	var n := pts.size()
	for i in n - 1:
		var p0: Vector3 = pts[maxi(i - 1, 0)]
		var p1: Vector3 = pts[i]
		var p2: Vector3 = pts[i + 1]
		var p3: Vector3 = pts[mini(i + 2, n - 1)]
		var steps := maxi(4, int(p1.distance_to(p2) / 40.0))
		for s in steps:
			var u := float(s) / float(steps)
			var q := 0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u * u + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u * u * u)
			if samples.size() > 0:
				total += samples[samples.size() - 1].distance_to(q)
			if s == 0:
				wd.append(total)
			samples.append(q)
			dists.append(total)
	var last: Vector3 = pts[n - 1]
	if samples.size() > 0:
		total += samples[samples.size() - 1].distance_to(last)
	samples.append(last)
	dists.append(total)
	wd.append(total)
	return {"pts": samples, "d": dists, "len": total, "way": pts, "wd": wd}


## Where you are after flying s metres along a path.
func path_at(path: Dictionary, s: float) -> Vector3:
	var d: PackedFloat32Array = path["d"]
	var pts: PackedVector3Array = path["pts"]
	if s <= 0.0:
		return pts[0]
	if s >= float(path["len"]):
		return pts[pts.size() - 1]
	var lo := 0
	var hi := d.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if d[mid] <= s:
			lo = mid
		else:
			hi = mid
	var f := (s - d[lo]) / maxf(d[hi] - d[lo], 0.001)
	return pts[lo].lerp(pts[hi], f)


## Fly a node along a path: placed, pointed down the path and banked into the turns.
func fly_on_path(node: Node3D, path: Dictionary, s: float, speed: float) -> Vector3:
	var p := path_at(path, s)
	var t0 := path_at(path, s + 15.0) - p
	var t1 := path_at(path, s + 45.0) - path_at(path, s + 15.0)
	node.global_position = p
	if t0.length() > 0.5:
		var fwd := t0.normalized()
		var bank := 0.0
		if t1.length() > 0.5:
			var turn := fwd.cross(t1.normalized()).y / 30.0
			bank = clampf(atan(speed * speed * turn / 9.8), -1.3, 1.3)
		if absf(fwd.y) < 0.98:
			node.look_at(p + fwd, Vector3.UP.rotated(fwd, -bank))
		return fwd
	return Vector3.FORWARD


## The run-in heading for an attack on p: away from friendlies (outbound, so overs and shorts fall
## further from the refuge) when it's well out, parallel to the wall when it's close in.
func run_in(p: Vector3) -> Vector3:
	var flat := Vector2(p.x, p.z)
	var out := Vector3(flat.x, 0.0, flat.y).normalized() if flat.length() > 5.0 else Vector3.RIGHT
	if flat.length() > 1200.0:
		return out
	return Vector3(-out.z, 0.0, out.x)


# ------------------------------------------------------------------ A-10 gun run
func quick_a10() -> void:
	var w := by_id("a10")
	if w["owned"] and a10.is_empty() and float(w["cd"]) <= 0.0 and int(w["ammo"]) > 0:
		call_a10(main.aim_point)
		w["ammo"] = int(w["ammo"]) - 1
		_set_cd(w)
	else:
		main.sfx.play("switch", -10.0, 0.8)


## Call a Hog strafing run through point p. It doesn't just appear on the target: it checks in at
## a holding point, runs to an initial point, rolls in on a heading that keeps its overs and shorts
## away from friendlies, walks a two-second burst through the mark, pulls off away from the
## refuge and egresses.
func call_a10(p: Vector3) -> void:
	var flat := Vector2(p.x, p.z)
	var out := Vector3(flat.x, 0.0, flat.y).normalized() if flat.length() > 5.0 else Vector3.RIGHT
	var run := run_in(p)
	var lat := Vector3(-run.z, 0.0, run.x)
	var dive := deg_to_rad(25.0)
	var run3 := (run * cos(dive) + Vector3.DOWN * sin(dive)).normalized()
	var speed := 190.0
	var fire_pos := p + Vector3.UP * 2.0 - run3 * 1250.0
	var fire_end := fire_pos + run3 * speed * 2.0
	var roll_in := fire_pos - run3 * 650.0
	var ip := roll_in - run * 1700.0 + Vector3.UP * 60.0
	var hold := ip - run * 900.0 + lat * 900.0 + Vector3.UP * 150.0
	var pull := fire_end + run * 450.0 + out * 350.0 + Vector3.UP * 380.0
	var egress := pull + out * 2600.0 + run * 900.0 + Vector3.UP * 900.0
	var path := make_path([hold, ip, roll_in, fire_pos, fire_end, pull, egress] as Array[Vector3])
	var wd: PackedFloat32Array = path["wd"]
	a10 = {
		"t": 0.0, "s": 0.0, "speed": speed, "path": path, "pos": hold, "vel": run * speed, "target": p, "run": run, "out": out,
		"ip": ip, "ip_s": wd[1], "fire_s0": wd[3], "fire_s1": wd[4], "fired": 0, "acc": 0.0,
		"node": _node(a10_mesh, mat_world, hold), "heard": false, "at_ip": false,
	}
	main.radio("HAWG 1-1", "Hawg one-one checking in, guns. Run-in heading %03d, %s. Tally the column." % [_heading(run), "pulling off away from the wall" if flat.length() > 1200.0 else "parallel to the wall, danger close"])
	main.sfx.play("beep", -6.0)


## Compass heading of a horizontal direction.
static func _heading(d: Vector3) -> int:
	return int(round(fposmod(rad_to_deg(atan2(d.x, -d.z)), 360.0))) % 360


func _update_a10(dt: float) -> void:
	if a10.is_empty():
		return
	a10["t"] = float(a10["t"]) + dt
	var speed: float = a10["speed"]
	a10["s"] = float(a10["s"]) + speed * dt
	var s: float = a10["s"]
	var path: Dictionary = a10["path"]
	var node: MeshInstance3D = a10["node"]
	var fwd := fly_on_path(node, path, s, speed)
	var pos := node.global_position
	a10["pos"] = pos
	a10["vel"] = fwd * speed
	var target: Vector3 = a10["target"]
	var run: Vector3 = a10["run"]
	var s0: float = a10["fire_s0"]
	var s1: float = a10["fire_s1"]
	var gun := by_id("gau8")
	if not a10["at_ip"] and s >= float(a10["ip_s"]):
		a10["at_ip"] = true
		main.radio("HAWG 1-1", "IP inbound.")
	if s >= s0 and s < s1:
		# a two-second burst: ~130 rounds walked down the column
		if not bool(a10["heard"]):
			a10["heard"] = true
			main.sfx.play_at("gau8_distant", pos, main.cam.global_position, 12.0)
			main.radio("HAWG 1-1", "In hot. Guns, guns, guns.")
		a10["acc"] = float(a10["acc"]) + 65.0 * dt
		while float(a10["acc"]) >= 1.0:
			a10["acc"] = float(a10["acc"]) - 1.0
			var k := (s - s0) / maxf(s1 - s0, 1.0)
			var aim := target + run * lerpf(-60.0, 60.0, k) + Vector3(randfn(0.0, 4.0), 0.0, randfn(0.0, 4.0))
			var muzzle := pos + fwd * 8.0
			var hit: Dictionary = main.raycast(muzzle, muzzle + (aim - muzzle) * 1.3)
			if not hit.is_empty():
				launch_shell(muzzle, hit["position"], 1013.0 + speed, gun, 1.3, 0.12, 0.025, true)
	elif s >= s1:
		# pull off: climb away from the refuge, punching out flares
		if s < s1 + 380.0 and fmod(float(a10["t"]), 0.25) < dt:
			main.fx.particle(true, pos, fwd * 60.0 + Vector3(randf_range(-15, 15), -5, randf_range(-15, 15)), 4.0, 2.5, 1.5, 2.2, 3, 0.25, 1.2)
		if int(a10["fired"]) == 0:
			a10["fired"] = 1
			main.sfx.play_at("a10_flyby", pos, main.cam.global_position, 10.0)
			var out: Vector3 = a10["out"]
			main.radio("HAWG 1-1", "Hawg one-one off safe, egressing %s. Good hits." % String(main.SECTORS[main.horde.sector_of(out.x, out.z)]).to_lower())
	main.fx.particle(true, pos - fwd * 9.0, -fwd * 19.0, 0.25, 2.0, 3.5, 0.9, 1)
	if s >= float(path["len"]):
		node.queue_free()
		a10 = {}


## The munition worth watching in the picture-in-picture seeker view, if any:
## {pos, look, label}. Newest guided weapon wins.
func pip_target() -> Dictionary:
	for k in range(missiles.size() - 1, -1, -1):
		var m: Dictionary = missiles[k]
		if m["guided"] and float(m["t"]) > 0.4:
			return {"pos": m["pos"], "look": main.aim_point, "label": "AGM-114  SEEKER", "range": (main.aim_point - (m["pos"] as Vector3)).length(), "node": m["node"]}
	for k in range(bombs.size() - 1, -1, -1):
		var b: Dictionary = bombs[k]
		var u := float(b["t"]) / float(b["T"])
		if u < 0.97:
			var p := bomb_pos(b, u)
			var w: Dictionary = b["w"]
			return {"pos": p, "look": b["target"], "label": "%s  WEAPON VIEW" % String(w["short"]), "range": p.distance_to(b["target"]), "node": b["node"]}
	for k in range(drones.size() - 1, -1, -1):
		var d: Dictionary = drones[k]
		if int(d["phase"]) == 1:
			var lbl := "MERLIN  SEEKER" if (d["w"] as Dictionary).get("seek", false) else "SWITCHBLADE  TERMINAL"
			return {"pos": d["pos"], "look": d["target"], "label": lbl, "range": (d["pos"] as Vector3).distance_to(d["target"]), "node": d["node"]}
	for k in range(drones.size() - 1, -1, -1):
		var d: Dictionary = drones[k]
		if int(d["phase"]) == 2:
			# loitering: the seeker looks down into the circle it's searching
			return {"pos": d["pos"], "look": d["area"], "label": "SWITCHBLADE  SEARCHING", "range": (d["pos"] as Vector3).distance_to(d["area"]), "node": d["node"]}
	return {}
