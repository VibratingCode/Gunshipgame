extends Node3D
## Objectives inside a wave, the ground's danger-close calls, and each AO's campaign.
##   HOLD          A squad holds a bridge or an overpass out on an approach for three minutes,
##                 then blows it and everything on it.
##   MEDEVAC       A dustoff collects wounded from two outposts. It won't set down on a hot LZ,
##                 so clear each one ahead of it; the wounded only have so long.
##   NEST          The infected have taken a building and pour out of it. Bring the building
##                 down: delay fuzes and heavy ordnance.
##   ENGINEERS     A team outside the wire rebuilds a wall section. Keep them alive ninety seconds.
##   DANGER CLOSE  A team in contact calls for fire within fifty metres of its own position.
##   CAMPAIGN      Each AO's days are a short story. After day three, the evacuation flight.

const MeshKit = preload("res://scripts/mesh_kit.gd")
const CAMPAIGN_DAYS := 3

# Each AO's story: a card for the dawn of each day, a line in the middle of it, the evacuation
# and how it ends.
const STORY := {
	"city": {
		"days": [
			["THE LAST GAME", "Forty thousand seats and every one of them taken by somebody who ran here. The Guard is fighting its way in from the river. Keep the avenues clear until it does."],
			["NOBODY IS COMING", "The Guard convoy was overrun at the river crossing. Nobody is coming overland now. Hold until command can find us the airframes."],
			["THE AIRLIFT", "The carrier group has Chinooks. Three birds at dawn tomorrow, onto the pitch one at a time. One more day, Spectre. Then we get them out."],
		],
		"mid": ["The stadium PA is playing the anthem. Don't ask. Morale's up.", "We've started rationing water. Two days at this rate, three if it rains.", "The kids have painted SPECTRE on the pitch. They wave every time you come round."],
		"evac": ["EXFIL // THE AIRLIFT", "Three Chinooks, one at a time onto the pitch. Hold them off until the last bird lifts. Everything they have is coming."],
		"won": "The last Chinook clears the rim with the coach and the band and the kids aboard. Homefield is empty. Spectre, take us home.",
	},
	"desert": {
		"days": [
			["DUST", "FOB Anvil was a supply depot. Now it's two hundred souls and a lot of HESCO. Hold the valley until the relief column gets through the pass."],
			["THE PASS", "The pass is closed: rockslide, and them on the far side of it. We're cut off. The airfield at Bastion is sending Hercules."],
			["LAST LIGHT", "Hercules land at first light on the strip outside the wire. Every one of them is going to hear the engines. Make tonight count."],
		],
		"mid": ["The generators are on their last barrels of diesel. We're cutting the floodlights after midnight.", "A sandstorm took the comms mast. We're on the backup set.", "The interpreter's teaching the kids cards. Somebody's always losing."],
		"evac": ["EXFIL // FIRST LIGHT", "Three birds into the FOB, one at a time. Keep the wire clear until the last one is wheels-up."],
		"won": "The last bird climbs out of the valley into the sunrise. Anvil is empty and the horde has it. Good work, Spectre.",
	},
	"port": {
		"days": [
			["THE SHIP", "The hospital ship can't sail until she's loaded, and loading takes days. Hold the terminal and the quay."],
			["THE TIDE", "The ship's under way at high tide on the third night, loaded or not. The rest go out by helicopter."],
			["LAST BOATS", "The ship's away with the wounded. Helicopters from the carrier for everyone left on the quay at dawn."],
		],
		"mid": ["The cranes are moving pallets aboard all night. They're loud. Expect company.", "Two more ambulances made it to the quay. Twenty-six more aboard.", "Somebody's fishing off the breakwater. Of course they are."],
		"evac": ["EXFIL // THE QUAY", "Three helicopters onto the quay, one at a time. Hold the landward side until the last one lifts."],
		"won": "The last helicopter swings out over the breakwater. Trident is empty. Somewhere out there the ship is still sailing.",
	},
	"river": {
		"days": [
			["THE ISLAND", "Blackwater Prison: the only dry ground for miles, and four bridges in. Make the bridges cost them."],
			["HIGH WATER", "The river's rising. Engineers want to drop the bridges, but the relief column needs one standing."],
			["THE BOATS DON'T COME", "The river boats were lost upstream. It's helicopters now: three at dawn, into the yard."],
		],
		"mid": ["The inmates and the guards are sharing the kitchens now. Nobody's said a word about it.", "Water's over the lower yard. Everybody's moved up a floor.", "The chaplain is holding services on the roof. They can see you from up there."],
		"evac": ["EXFIL // THE YARD", "Three helicopters into the prison yard, one at a time. Keep the bridges clear until the last one is out."],
		"won": "The last bird lifts out of the yard and follows the river south. Blackwater is empty. Bring it home, Spectre.",
	},
	"arctic": {
		"days": [
			["NOTHING WARM", "Kepler Station: forty scientists and a winter crew, and nothing out on the ice is warm except them. Keep them off the berm."],
			["WHITEOUT", "The LC-130 can't come in through this weather. The station's on generator heat and short of fuel."],
			["THE SKIWAY", "Weather's breaking tomorrow. Three aircraft onto the skiway at dawn. They'll be heard for fifty kilometres."],
		],
		"mid": ["The heating's down to the galley and one dorm. Everybody's sleeping in the galley.", "The cook's making doughnuts with the last of the flour. The smell is half the reason we're still sane.", "Somebody's playing the piano in the rec room. It's mostly in tune."],
		"evac": ["EXFIL // THE SKIWAY", "Three aircraft down onto the station, one at a time. Hold the berm until the last one is airborne."],
		"won": "The last aircraft lifts off the ice. Kepler Station is dark. The infected are standing in the snow, steaming.",
	},
	"heaven": {
		"days": [
			["THE VALLEY", "Firebase Gabriel holds the mouth of the valley, and everything in it is coming for us. For God, for heaven."],
			["THE CHAPEL", "We've moved the wounded into the chapel. The chaplain won't leave them. Neither will we."],
			["THE LAST NIGHT", "Birds at dawn, three of them, onto the pads. Everything in the valley is going to come down it tonight."],
		],
		"mid": ["The chaplain's been ringing the bell every hour. It carries the whole length of the valley.", "Ammunition's down to what's in the bunkers. Make every round count.", "They're singing in the chapel. You can hear it on the open mic."],
		"evac": ["EXFIL // GABRIEL", "Three birds onto the pads, one at a time. The whole valley is coming. Hold them until the last one lifts."],
		"won": "The last bird lifts off over the chapel, the bell still ringing. Gabriel is empty. For God, for heaven, Spectre.",
	},
}

var main
var obj: Dictionary = {}
var next_obj := 75.0
var last_kind := ""
var dc: Dictionary = {}
var dc_cd := 30.0
var evac: Dictionary = {}
# wall damage multiplier: every section the engineers reinforce takes it down a little
var wall_k := 1.0
var story_card: Dictionary = {}
var sinking: Array = []
var mat_people: ShaderMaterial
var chinook_mesh: ArrayMesh


func _ready() -> void:
	mat_people = ShaderMaterial.new()
	mat_people.shader = load("res://shaders/survivor.gdshader")
	chinook_mesh = _chinook()


## A CH-47: a long box with a rotor at each end, hot engines on the aft pylon.
static func _chinook() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var olive := Vector2(MeshKit.TAG_OLIVE, 0)
	var dark := Vector2(MeshKit.TAG_DARK, 0)
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 0, 0)), Vector3(3.6, 3.6, 15.0), Color(0.36, 0.3, 0.4, 1.0), olive)
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 2.6, 6.2)), Vector3(1.6, 2.2, 3.0), Color(0.36, 0.3, 0.4, 1.0), olive)
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 2.2, -6.6)), Vector3(1.4, 1.0, 1.6), Color(0.36, 0.3, 0.4, 1.0), olive)
	for s: float in [-1.0, 1.0]:
		MeshKit.box(st, Transform3D(Basis(), Vector3(1.6 * s, 2.6, 5.4)), Vector3(1.0, 1.0, 3.0), Color(0.9, 0.0, 0.0, 1.0), olive)
	for z: float in [-6.6, 6.2]:
		var y := 2.9 if z < 0.0 else 3.9
		MeshKit.box(st, Transform3D(Basis(), Vector3(0, y, z)), Vector3(18.0, 0.1, 0.6), Color(0.3, 0.0, 0.0, 1.0), dark)
		MeshKit.box(st, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, y, z)), Vector3(18.0, 0.1, 0.6), Color(0.3, 0.0, 0.0, 1.0), dark)
	return st.commit()


# ---------------------------------------------------------------- helpers
func _people(pos: Vector3, n: int, spread: float, soldier: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = MeshKit.humanoid(false)
	mm.instance_count = n
	for k in n:
		var o := Vector2.from_angle(randf() * TAU) * randf_range(0.5, spread)
		mm.set_instance_transform(k, Transform3D(Basis(), pos + Vector3(o.x, 0.05, o.y)))
		mm.set_instance_custom_data(k, Color(randf_range(0.5, 1.5), randf_range(0.4, 0.9), randf(), 0.95 if soldier else 0.9))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat_people
	add_child(mi)
	return mi


func _ground(p: Vector3) -> Vector3:
	var hit: Dictionary = main.raycast(p + Vector3.UP * 400.0, p + Vector3.DOWN * 60.0)
	return hit.get("position", Vector3(p.x, 0.0, p.z))


func _pay(base: float) -> int:
	var pay := int(round(base * (1.0 + float(main.wave) * 0.05) * float(main.stat("rp")) * float(main.rp_event)))
	main.rp += pay
	main.rp_total += pay
	return pay


func _sector_name(p: Vector3) -> String:
	return String(main.SECTORS[main.horde.sector_of(p.x, p.z)]).to_lower()


func _announce(text: String) -> void:
	main.banner = text
	main.banner_t = main.real_t


## Keep a little squad shooting: a few rounds a second at whatever comes near.
func _squad_fire(pos: Vector3, rate: float, reach: float, dt: float, key: Dictionary) -> void:
	key["fire_acc"] = float(key.get("fire_acc", 0.0)) + dt * rate
	while float(key["fire_acc"]) >= 1.0:
		key["fire_acc"] = float(key["fire_acc"]) - 1.0
		var zi: int = main.horde.nearest(pos + Vector3(randf_range(-reach, reach) * 0.5, 0.0, randf_range(-reach, reach) * 0.5), reach * 0.5)
		if zi < 0:
			key["fire_acc"] = 0.0
			return
		var zp: Vector2 = main.horde.pos_of(zi)
		var from := pos + Vector3.UP * 1.4
		var to := Vector3(zp.x, 1.0, zp.y)
		var tf := maxf(from.distance_to(to) / 850.0, 0.02)
		main.fx.tracer(from, (to - from) / tf, tf, 1.1, 0.05, 0.03)
		main.fx.particle(true, from, Vector3.ZERO, 0.05, 0.4, 1.1, 1.6, 0)
		if randf() < 0.6:
			main.horde.kill(zi, zp, from, 3.0)
			main.horde.defender_kills += 1


## Casualties from the infected close around a team; returns how many it has left.
func _squad_losses(o: Dictionary, pos: Vector3, dt: float, who: String) -> int:
	var near: int = main.horde.count_near(pos, 11.0, true)
	if near > 0:
		o["hurt"] = float(o.get("hurt", 0.0)) + dt * near * 0.3
		while float(o["hurt"]) >= 1.0 and int(o["alive"]) > 0:
			o["hurt"] = float(o["hurt"]) - 1.0
			o["alive"] = int(o["alive"]) - 1
			main.radio(who, ["Man down! Man down!", "They've got one of us!", "We're losing people out here!", "Get them off us, Spectre!"].pick_random(), true)
			var mi: MultiMeshInstance3D = o["people"]
			mi.multimesh.visible_instance_count = int(o["alive"])
	return int(o["alive"])


# ---------------------------------------------------------------- per frame
func update(dt: float) -> void:
	if dt <= 0.0:
		return
	_update_sinking(dt)
	if not evac.is_empty():
		_update_evac(dt)
	dc_cd -= dt
	if not dc.is_empty():
		_update_dc(dt)
	if obj.is_empty():
		if main.wave_active and int(main.wave) >= 2 and evac.is_empty() and not main.ops.busy():
			next_obj -= dt
			if next_obj <= 0.0:
				_start_next()
	else:
		match String(obj["kind"]):
			"hold":
				_update_hold(dt)
			"medevac":
				_update_medevac(dt)
			"nest":
				_update_nest(dt)
			"engineers":
				_update_engineers(dt)
	# the garrison calls danger close when they're swamped at the wall
	if dc.is_empty() and dc_cd <= 0.0 and int(main.horde.arrived_count) > 30:
		var s: int = main.horde.worst_sector()
		if s >= 0 and float(main.horde.sector_w[s]) > 25.0:
			var bearing := deg_to_rad(s * 45.0)
			var wp := Vector3(sin(bearing), 0.0, -cos(bearing)) * float(main.wall_r)
			request_dc(wp + Vector3.UP * 2.0, "GARRISON", "the %s wall" % String(main.SECTORS[s]).to_lower(), "wall")


func _start_next() -> void:
	var kinds: Array = ["hold", "medevac"]
	var lms: Array = main.world.get("landmarks", [])
	for lm in lms:
		if lm["alive"]:
			kinds.append("nest")
			kinds.append("nest")
			break
	if float(main.integrity) < 96.0:
		kinds.append("engineers")
	kinds.erase(last_kind)
	if kinds.is_empty():
		kinds = ["medevac"]
	var k := String(kinds[randi() % kinds.size()])
	match k:
		"hold":
			_start_hold()
		"medevac":
			_start_medevac()
		"nest":
			_start_nest()
		"engineers":
			_start_engineers()
	last_kind = k


func _finish(ok: bool) -> void:
	for key in ["people", "heli", "truck"]:
		if obj.has(key) and obj[key] != null and is_instance_valid(obj[key]):
			(obj[key] as Node).queue_free()
	obj = {}
	next_obj = randf_range(70.0, 130.0)
	if ok:
		main.sfx.play("buy", -2.0, 1.05)


# ---------------------------------------------------------------- HOLD
func _start_hold() -> void:
	var cands: Array = []
	for c in main.corridors:
		if int(c["type"]) == 0 and (c.has("bridge") or (float(c["rmin"]) < 700.0 and float(c["rmax"]) > 1500.0)):
			cands.append(c)
	if cands.is_empty():
		_start_medevac()
		return
	var c: Dictionary = cands[randi() % cands.size()]
	var d := Vector3(cos(float(c["ang"])), 0.0, sin(float(c["ang"])))
	var perp := Vector3(-d.z, 0.0, d.x)
	var bridge: bool = c.has("bridge")
	var r_line := float((c["bridge"] as Vector2).y) - 30.0 if bridge else randf_range(650.0, 950.0)
	var line := _ground(d * r_line)
	var pos := _ground(line + perp * float(c["hw"]) * 0.55 - d * 6.0)
	var place := "the %s bridge" % _sector_name(d) if bridge else "the overpass on the %s avenue" % _sector_name(d)
	obj = {"kind": "hold", "c": c, "pos": pos, "line": line, "dir": d, "t": 0.0, "dur": 180.0, "alive": 6, "hurt": 0.0,
		"spawn_acc": 4.0, "people": _people(pos, 6, 3.0, true), "name": place, "dc_cd": 20.0}
	main.radio("RANGER 6", "Spectre, Ranger six. We're holding %s with six men and enough demo to drop it. Give us three minutes and it's coming down. Keep them off us." % place, true)
	_announce("HOLD  //  %s  //  3:00" % place.to_upper())
	main.sfx.play("alarm", -10.0, 1.1)


func _update_hold(dt: float) -> void:
	obj["t"] = float(obj["t"]) + dt
	var pos: Vector3 = obj["pos"]
	var c: Dictionary = obj["c"]
	# they're coming down the road in numbers
	obj["spawn_acc"] = float(obj["spawn_acc"]) - dt
	if float(obj["spawn_acc"]) <= 0.0:
		obj["spawn_acc"] = 10.0
		var ln: Vector3 = obj["line"]
		main._spawn_clump(c, 25 + int(main.wave) * 5, Vector2(ln.x, ln.z).length() + randf_range(250.0, 800.0))
	_squad_fire(pos, 3.5, 140.0, dt, obj)
	if _squad_losses(obj, pos, dt, "RANGER 6") <= 0:
		main.radio("TOC", "Ranger six is gone. %s is theirs." % String(obj["name"]).capitalize(), true)
		_announce("HOLD FAILED  //  RANGER 6 LOST")
		main.add_population(-6)
		_finish(false)
		return
	obj["dc_cd"] = float(obj["dc_cd"]) - dt
	if float(obj["dc_cd"]) <= 0.0 and main.horde.count_near(pos, 45.0, true) >= 12:
		obj["dc_cd"] = 40.0
		request_dc(pos, "RANGER 6", String(obj["name"]), "team")
	if float(obj["t"]) >= float(obj["dur"]):
		# the charges go: the bridge and everything on it
		var line: Vector3 = obj["line"]
		var k: int = main.horde.blast(line, 35.0, 70.0, 80.0, 30.0)
		main.add_kills(k, line)
		main.fx.explosion(line, 6, 900.0)
		main.scorch(line, 60.0, 0.9)
		main.sfx.play_at("exp_huge", line, main.cam.global_position, 16.0, 0.7)
		main.kick(0.5)
		var pay := _pay(3000.0 + 300.0 * int(obj["alive"]))
		main.add_population(int(obj["alive"]))
		main.radio("RANGER 6", "FIRE IN THE HOLE! %s is down! Ranger six falling back with %d men. Thanks for the cover, Spectre." % [String(obj["name"]).capitalize(), int(obj["alive"])], true)
		_announce("HELD  //  %s DOWN  //  +%s RP" % [String(obj["name"]).to_upper(), main.hud.commas(pay)])
		main._feed("HOLD  +%s RP" % main.hud.commas(pay))
		_finish(true)


# ---------------------------------------------------------------- MEDEVAC
func _lz_on(c: Dictionary) -> Vector3:
	var a: float = c["ang"]
	var r := randf_range(maxf(float(c["rmin"]) + 150.0, 800.0), 1500.0)
	var d := Vector2(cos(a), sin(a))
	var lat := 0.0
	if int(c["type"]) == 0:
		lat = (float(c["hw"]) - 6.0) * (1.0 if randf() < 0.5 else -1.0)
	else:
		a += float(c["half"]) * 0.6 * (1.0 if randf() < 0.5 else -1.0)
		d = Vector2(cos(a), sin(a))
	var p := d * r + Vector2(-d.y, d.x) * lat
	return _ground(Vector3(p.x, 0.0, p.y))


func _start_medevac() -> void:
	var cors: Array = main.corridors.duplicate()
	cors.shuffle()
	var lzs: Array = [_lz_on(cors[0]), _lz_on(cors[1 % cors.size()])]
	var heli := MeshInstance3D.new()
	heli.mesh = main.ops.heli_mesh
	heli.material_override = main.ops.mat_world
	add_child(heli)
	heli.global_position = Vector3(0, 40, 0)
	obj = {"kind": "medevac", "lzs": lzs, "cors": [cors[0], cors[1 % cors.size()]], "i": 0, "phase": "out", "t": 0.0, "limit": 220.0,
		"heli": heli, "load": 0.0, "saved": 0, "lost": 0, "spawned": false, "orbit": 0.0}
	main.radio("DUSTOFF 3-1", "Spectre, Dustoff three-one. Two outposts with wounded, %.1f and %.1f klicks out. I won't set down on a hot LZ, so clear them ahead of me." % [Vector2(lzs[0].x, lzs[0].z).length() / 1000.0, Vector2(lzs[1].x, lzs[1].z).length() / 1000.0], true)
	_announce("MEDEVAC  //  2 LANDING ZONES  //  CLEAR THEM AHEAD OF THE DUSTOFF")
	main.sfx.play("alarm", -10.0, 1.3)


func _update_medevac(dt: float) -> void:
	obj["t"] = float(obj["t"]) + dt
	var heli: MeshInstance3D = obj["heli"]
	var i: int = obj["i"]
	var lzs: Array = obj["lzs"]
	if float(obj["t"]) > float(obj["limit"]) and String(obj["phase"]) != "home":
		main.radio("DUSTOFF 3-1", "We're out of time, Spectre. They didn't make it. RTB.", true)
		obj["lost"] = int(obj["lost"]) + (lzs.size() - i) * 6
		obj["phase"] = "home"
	match String(obj["phase"]):
		"out":
			var lz: Vector3 = lzs[i]
			var hold := lz - Vector3(lz.x, 0.0, lz.z).normalized() * 260.0 + Vector3.UP * 110.0
			if not obj["spawned"]:
				obj["spawned"] = true
				# the rotor noise draws them in
				main._spawn_clump(obj["cors"][i], 30 + int(main.wave) * 5, Vector2(lz.x, lz.z).length() + randf_range(250.0, 450.0))
			if main.ops._fly(heli, hold, 70.0, dt):
				obj["phase"] = "hold"
				main.radio("DUSTOFF 3-1", "Holding short of LZ %d. Tell me when it's cold." % (i + 1))
		"hold":
			var lz: Vector3 = lzs[i]
			obj["orbit"] = float(obj["orbit"]) + dt * 0.35
			var a: float = obj["orbit"]
			var hold := lz - Vector3(lz.x, 0.0, lz.z).normalized() * 260.0 + Vector3(cos(a) * 90.0, 110.0, sin(a) * 90.0)
			main.ops._fly(heli, hold, 45.0, dt)
			if randf() < dt * 3.0:
				main.fx.particle(false, lz + Vector3.UP, Vector3(randf_range(-1, 1), 3.0, randf_range(-1, 1)), 6.0, 2.0, 9.0, 0.42, 2, -0.01, 0.3)
			if main.horde.count_near(lz, 60.0, true) <= 2:
				obj["phase"] = "land"
				main.radio("DUSTOFF 3-1", "LZ %d is cold. Going in." % (i + 1))
		"land":
			var lz: Vector3 = lzs[i]
			if main.ops._fly(heli, lz + Vector3.UP * 1.6, 16.0, dt):
				obj["phase"] = "load"
				obj["load"] = 0.0
				main._spawn_clump(obj["cors"][i], 15 + int(main.wave) * 3, Vector2(lz.x, lz.z).length() + 160.0)
				main.radio("DUSTOFF 3-1", "Wheels down at LZ %d. Loading. Keep them off us." % (i + 1))
		"load":
			var lz: Vector3 = lzs[i]
			obj["load"] = float(obj["load"]) + dt
			if main.horde.count_near(lz, 22.0, true) >= 3:
				main.radio("DUSTOFF 3-1", "Taking contact! Lifting! We had to leave them!", true)
				obj["lost"] = int(obj["lost"]) + 6
				_next_lz()
			elif float(obj["load"]) >= 10.0:
				obj["saved"] = int(obj["saved"]) + 6
				main.radio("DUSTOFF 3-1", "Six aboard. Lifting.")
				_next_lz()
		"home":
			if main.ops._fly(heli, Vector3(0, float(main.world["refuge_h"]) + 12.0, 0), 75.0, dt):
				var saved: int = obj["saved"]
				if saved > 0:
					var pay := _pay(150.0 * saved)
					main.add_population(saved)
					main.radio("DUSTOFF 3-1", "Dustoff's down inside the wire with %d wounded. Couldn't have done it without you, Spectre." % saved, true)
					_announce("MEDEVAC COMPLETE  //  %d WOUNDED IN  //  +%s RP" % [saved, main.hud.commas(pay)])
					main._feed("MEDEVAC  %d IN  +%s RP" % [saved, main.hud.commas(pay)])
				else:
					_announce("MEDEVAC FAILED  //  NO SURVIVORS")
				_finish(saved > 0)


func _next_lz() -> void:
	obj["i"] = int(obj["i"]) + 1
	obj["spawned"] = false
	obj["phase"] = "home" if int(obj["i"]) >= (obj["lzs"] as Array).size() else "out"


# ---------------------------------------------------------------- NEST
func _start_nest() -> void:
	var alive: Array = []
	for lm in main.world.get("landmarks", []):
		if lm["alive"]:
			alive.append(lm)
	if alive.is_empty():
		_start_medevac()
		return
	var lm: Dictionary = alive[randi() % alive.size()]
	(lm["mat"] as ShaderMaterial).set_shader_parameter("infest", 1.0)
	obj = {"kind": "nest", "lm": lm, "hp": 2500.0, "max": 2500.0, "spawn_acc": 3.0, "t": 0.0, "hit_t": -10.0}
	main.radio("TOC", "Spectre, they've taken %s, %.1f klicks %s. It's full of them and they're pouring out. Bring it down: delay fuzes, heavy stuff." % [String(lm["name"]).to_lower(), Vector2(lm["pos"].x, lm["pos"].z).length() / 1000.0, _sector_name(lm["pos"])], true)
	_announce("NEST  //  %s  //  BRING IT DOWN" % String(lm["name"]))
	main.sfx.play("alarm", -8.0, 0.8)


func _update_nest(dt: float) -> void:
	obj["t"] = float(obj["t"]) + dt
	var lm: Dictionary = obj["lm"]
	var pos: Vector3 = lm["pos"]
	var size: Vector3 = lm["size"]
	obj["spawn_acc"] = float(obj["spawn_acc"]) - dt
	if float(obj["spawn_acc"]) <= 0.0:
		obj["spawn_acc"] = 7.0
		# out of the doors on the side facing the refuge
		var door := pos - Vector3(pos.x, 0.0, pos.z).normalized() * (maxf(size.x, size.z) * 0.5 + 4.0)
		var ar: Vector2 = main.arrive
		for k in 15 + int(main.wave) * 2:
			var o := Vector2.from_angle(randf() * TAU) * randf_range(0.0, 10.0)
			var kind := 1 if randf() < 0.15 else 0
			main.horde.spawn(door.x + o.x, door.z + o.y, randf_range(1.0, 1.5) if kind == 0 else randf_range(2.4, 3.2), kind, randf_range(ar.x, ar.y))


## A hit from anything on whatever building is the nest: structural damage by the size of the
## charge and the fuze. Delay-fuzed rounds go off inside and do the real damage; airbursts
## barely mark it; gunfire chips at it.
func structure_hit(ip: Vector3, tnt: float, fuze: String) -> void:
	if obj.get("kind", "") != "nest":
		return
	var lm: Dictionary = obj["lm"]
	var rel := Basis(Vector3.UP, float(lm["yaw"])).inverse() * (ip - (lm["pos"] as Vector3))
	var size: Vector3 = lm["size"]
	if absf(rel.x) > size.x * 0.5 + 5.0 or absf(rel.z) > size.z * 0.5 + 5.0 or rel.y > size.y + 6.0:
		return
	var k: float = 1.0 if fuze == "" else float(main.arsenal.fuze_fx(fuze)["struct"])
	var dmg := 40.0 * pow(maxf(tnt, 0.01), 0.8) * k
	if tnt < 0.2:
		dmg *= 0.25
	obj["hp"] = float(obj["hp"]) - dmg
	if main.real_t - float(obj["hit_t"]) > 1.5 and dmg > 30.0:
		main.popups.append({"pos": ip + Vector3.UP * 8.0, "text": "STRUCTURE %d%%" % int(maxf(float(obj["hp"]), 0.0) / float(obj["max"]) * 100.0), "t": main.real_t, "big": false})
	obj["hit_t"] = main.real_t
	if float(obj["hp"]) <= 0.0:
		_collapse()


func _collapse() -> void:
	var lm: Dictionary = obj["lm"]
	lm["alive"] = false
	PhysicsServer3D.free_rid(lm["body"])
	PhysicsServer3D.free_rid(lm["shape"])
	var pos: Vector3 = lm["pos"]
	var size: Vector3 = lm["size"]
	var span := maxf(size.x, size.z)
	var k: int = main.horde.blast(pos + Vector3.UP * 2.0, span * 0.6, span * 0.6 + 25.0, 60.0, 20.0)
	main.add_kills(k, pos)
	main.fx.explosion(pos, 6, 2000.0)
	for i in 40:
		var a := randf() * TAU
		var d := Vector3(cos(a), 0.0, sin(a))
		main.fx.particle(false, pos + d * span * 0.5 + Vector3.UP * 4.0, d * randf_range(20.0, 45.0) + Vector3.UP * randf_range(2.0, 8.0), randf_range(10.0, 18.0), 10.0, 38.0, 0.45, 2, 0.0, 0.7)
	main.scorch(pos, span * 0.9, 0.9)
	main.sfx.play_at("exp_huge", pos, main.cam.global_position, 18.0, 0.55)
	main.kick(0.8)
	sinking.append({"node": lm["node"], "t": 0.0, "depth": size.y + 2.0, "tilt": randf_range(-0.12, 0.12)})
	var pay := _pay(4000.0)
	main.radio("TOC", "%s is coming down! Good effect, Spectre, the nest is gone." % String(lm["name"]).capitalize(), true)
	_announce("NEST DESTROYED  //  %s  //  +%s RP" % [String(lm["name"]), main.hud.commas(pay)])
	main._feed("NEST DOWN  +%s RP" % main.hud.commas(pay))
	_finish(true)


func _update_sinking(dt: float) -> void:
	for k in range(sinking.size() - 1, -1, -1):
		var s: Dictionary = sinking[k]
		s["t"] = float(s["t"]) + dt
		var node: Node3D = s["node"]
		var f := clampf(float(s["t"]) / 5.0, 0.0, 1.0)
		node.position.y = -float(s["depth"]) * f * f
		node.rotation.z = float(s["tilt"]) * f
		if randf() < dt * 12.0 and f < 1.0:
			main.fx.particle(false, node.global_position + Vector3(randf_range(-20, 20), randf_range(0.0, 10.0), randf_range(-20, 20)), Vector3(randf_range(-4, 4), randf_range(3, 8), randf_range(-4, 4)), randf_range(8.0, 14.0), 8.0, 26.0, 0.45, 2, -0.01, 0.4)
		if f >= 1.0:
			node.position.y = -float(s["depth"]) + 3.0
			sinking.remove_at(k)


# ---------------------------------------------------------------- ENGINEERS
func _start_engineers() -> void:
	var s: int = main.horde.worst_sector()
	var bearing := deg_to_rad(s * 45.0) if s >= 0 else randf() * TAU
	if String(main.ao_base) == "port":
		bearing = deg_to_rad(randf_range(200.0, 340.0)) + PI * 0.5
	var d := Vector3(sin(bearing), 0.0, -cos(bearing))
	var pos := _ground(d * (float(main.wall_r) + 12.0))
	var truck := MeshInstance3D.new()
	truck.mesh = main.ops.truck_mesh
	truck.material_override = main.ops.mat_world
	add_child(truck)
	truck.global_position = pos + d.cross(Vector3.UP) * 6.0
	truck.look_at(truck.global_position + d.cross(Vector3.UP), Vector3.UP)
	obj = {"kind": "engineers", "pos": pos, "t": 0.0, "dur": 90.0, "alive": 6, "hurt": 0.0, "people": _people(pos, 6, 4.0, false),
		"truck": truck, "sector": _sector_name(d), "dc_cd": 15.0}
	main.radio("ENGINEERS", "Spectre, engineers. We're outside the wire on the %s side to rebuild the section. Ninety seconds. Don't let them near us." % String(obj["sector"]), true)
	_announce("ENGINEERS  //  %s WALL  //  1:30" % String(obj["sector"]).to_upper())


func _update_engineers(dt: float) -> void:
	obj["t"] = float(obj["t"]) + dt
	var pos: Vector3 = obj["pos"]
	if randf() < dt * 4.0:
		main.fx.particle(true, pos + Vector3(randf_range(-3, 3), 1.0, randf_range(-3, 3)), Vector3(randf_range(-3, 3), 4.0, randf_range(-3, 3)), 0.4, 0.3, 0.2, 2.2, 3, 1.0, 0.5)
	if _squad_losses(obj, pos, dt, "ENGINEERS") <= 0:
		main.radio("OVERWATCH", "We lost the engineering team. All of them.", true)
		_announce("ENGINEERS LOST")
		main.add_population(-6)
		_finish(false)
		return
	obj["dc_cd"] = float(obj["dc_cd"]) - dt
	if float(obj["dc_cd"]) <= 0.0 and main.horde.count_near(pos, 45.0, true) >= 10:
		obj["dc_cd"] = 35.0
		request_dc(pos, "ENGINEERS", "the engineers on the %s side" % String(obj["sector"]), "team")
	if float(obj["t"]) >= float(obj["dur"]):
		main.integrity = minf(100.0, float(main.integrity) + 20.0)
		wall_k *= 0.9
		var pay := _pay(1500.0)
		main.radio("ENGINEERS", "Section's up, and it's better than it was. Coming back in.", true)
		_announce("WALL REBUILT  //  +20%% INTEGRITY  //  WALLS REINFORCED  //  +%s RP" % main.hud.commas(pay))
		_finish(true)


# ---------------------------------------------------------------- DANGER CLOSE
## A team in contact asks for fire on the crowd right on top of it. Put enough of them down
## inside the minute without hurting a single friendly and it pays very well; drop anything
## big enough on them and it's blue on blue.
func request_dc(friendly: Vector3, who: String, where: String, kind: String) -> void:
	if not dc.is_empty() or dc_cd > 0.0:
		return
	var best := Vector3.INF
	var bn := 0
	for k in 16:
		var a := randf() * TAU
		var p := friendly + Vector3(cos(a), 0.0, sin(a)) * randf_range(18.0, 45.0)
		var n: int = main.horde.count_near(p, 10.0, true)
		if n > bn:
			bn = n
			best = p
	if bn < 4:
		return
	var dist := Vector2(best.x - friendly.x, best.z - friendly.z).length()
	dc = {"friendly": friendly, "target": best, "t": 0.0, "dur": 40.0, "kills": 0, "need": 20 + int(main.wave) * 2, "closest": INF, "who": who, "kind": kind, "where": where}
	main.radio(who, "Spectre, %s, DANGER CLOSE! Infected %d metres from us, request immediate fire, I say again, DANGER CLOSE!" % [who.capitalize(), int(dist)], true)
	_announce("DANGER CLOSE  //  %s  //  %d M FROM FRIENDLIES" % [where.to_upper(), int(dist)])
	main.sfx.play("alarm", -6.0, 1.4)


func _update_dc(dt: float) -> void:
	dc["t"] = float(dc["t"]) + dt
	if float(dc["t"]) > float(dc["dur"]):
		main.radio(String(dc["who"]), "We're pulling back, Spectre. Couldn't hold there.")
		dc = {}
		dc_cd = 40.0


## Called for every one of our own detonations.
func on_impact(pos: Vector3, w: Dictionary, k: int) -> void:
	if dc.is_empty():
		return
	var fr: Vector3 = dc["friendly"]
	var df := Vector2(pos.x - fr.x, pos.z - fr.z).length()
	var gun: bool = String(w.get("kind", "")) in ["rotary", "auto"]
	var reach: float = 3.0 if gun else float(w.get("r_frag", 2.0)) * 0.6
	if df < reach:
		_blue_on_blue()
		return
	var tg: Vector3 = dc["target"]
	if Vector2(pos.x - tg.x, pos.z - tg.z).length() < 45.0 and k > 0:
		dc["kills"] = int(dc["kills"]) + k
		dc["closest"] = minf(float(dc["closest"]), df)
		if int(dc["kills"]) >= int(dc["need"]):
			var close: float = dc["closest"]
			var pay := _pay(1500.0 + 50.0 * int(dc["kills"]) + (2000.0 if close < 50.0 else 0.0))
			main.radio(String(dc["who"]), "Good effect! Good effect! Splash at %d metres and not a scratch on us. Spectre, we owe you." % int(close), true)
			_announce("DANGER CLOSE  //  CLEAN  //  CLOSEST %d M  //  +%s RP" % [int(close), main.hud.commas(pay)])
			main._feed("DANGER CLOSE CLEAN  +%s RP" % main.hud.commas(pay))
			main.sfx.play("buy", -2.0, 1.3)
			dc = {}
			dc_cd = 30.0


func _blue_on_blue() -> void:
	var who := String(dc["who"])
	main.radio(who, "CHECK FIRE! CHECK FIRE! You hit us! We've got wounded!", true)
	_announce("BLUE ON BLUE  //  FRIENDLY CASUALTIES")
	main.flash = maxf(main.flash, 0.1)
	match String(dc["kind"]):
		"wall":
			main.integrity = maxf(0.0, float(main.integrity) - 4.0)
			main.add_population(-5)
		"team":
			if obj.has("alive"):
				obj["alive"] = maxi(0, int(obj["alive"]) - 2)
				var mi: MultiMeshInstance3D = obj["people"]
				mi.multimesh.visible_instance_count = int(obj["alive"])
	main.rp = maxi(0, int(main.rp) - 1000)
	dc = {}
	dc_cd = 45.0


# ---------------------------------------------------------------- the campaign
## A new wave: the dawn of each day brings the next chapter of the AO's story; the wave after
## day three is the evacuation.
func wave_started(wave: int) -> void:
	# Smoke of Their Torment has no story and no way out: just the tide, for as long as you last
	if bool(main.world.get("torment", false)):
		next_obj = INF
		return
	next_obj = minf(next_obj, randf_range(40.0, 80.0))
	var st: Dictionary = STORY.get(String(main.ao_base), STORY["city"])
	var day_len: int = main.DAY_LEN
	var d := (wave - 1) / day_len
	var in_day := (wave - 1) % day_len
	if wave == CAMPAIGN_DAYS * day_len + 1:
		_start_evac(st)
		return
	if d >= CAMPAIGN_DAYS:
		return
	if in_day == 0:
		var day: Array = st["days"][d]
		story_card = {"title": String(day[0]), "text": String(day[1]), "sub": "DAY %d OF %d" % [d + 1, CAMPAIGN_DAYS], "t": main.real_t}
		main.radio("OVERWATCH", String(day[1]))
	elif in_day == 2:
		main.radio("OVERWATCH", String(st["mid"][d]))


func evac_running() -> bool:
	return not evac.is_empty()


func _quiet_bearing() -> float:
	var best := 0.0
	var bn := INF
	for k in 12:
		var a := TAU * k / 12.0
		var n: int = main.horde.count_near(Vector3(cos(a), 0.0, sin(a)) * 1400.0, 250.0, true)
		if String(main.ao_base) == "port" and sin(a) < 0.0:
			n -= 100000
		if n < bn:
			bn = n
			best = a
	return best


func _start_evac(st: Dictionary) -> void:
	var e: Array = st["evac"]
	story_card = {"title": String(e[0]), "text": String(e[1]), "sub": "THE LAST WAVE", "t": main.real_t}
	evac = {"birds": [], "launched": 0, "out": 0, "bearing": _quiet_bearing(), "won": String(st["won"])}
	main.radio("TOC", String(e[1]), true)
	_announce("EXFIL  //  COVER THE EVACUATION  //  0 OF 3 OUT")
	main.to_spawn = maxi(int(main.to_spawn), 40000)
	main.sfx.play("alarm", -4.0, 0.7)
	_launch_bird()


func _launch_bird() -> void:
	var a: float = float(evac["bearing"]) + randf_range(-0.2, 0.2)
	var start := Vector3(cos(a), 0.0, sin(a)) * 4500.0 + Vector3.UP * 220.0
	var node := MeshInstance3D.new()
	node.mesh = chinook_mesh
	node.material_override = main.ops.mat_world
	add_child(node)
	node.global_position = start
	var n: int = evac["launched"]
	var lz_a := TAU * n / 3.0 + 0.4
	var spot := Vector2(cos(lz_a), sin(lz_a)) * float(main.wall_r) * 0.32
	if String(main.ao_base) == "port":
		spot = Vector2(-60.0 + n * 50.0, 15.0)
	var lz := _ground(Vector3(spot.x, 0.0, spot.y)) + Vector3.UP * 2.5
	(evac["birds"] as Array).append({"node": node, "phase": "in", "load": 0.0, "lz": lz, "home": start})
	evac["launched"] = n + 1
	main.radio("TOC", "Bird %d is inbound to the %s. %d minutes." % [n + 1, String(main.refuge_name).to_lower(), 1])


func _update_evac(dt: float) -> void:
	var birds: Array = evac["birds"]
	for b in birds:
		var node: MeshInstance3D = b["node"]
		var lz: Vector3 = b["lz"]
		match String(b["phase"]):
			"in":
				if main.ops._fly(node, lz + Vector3.UP * 60.0, 70.0, dt):
					b["phase"] = "land"
			"land":
				if main.ops._fly(node, lz, 14.0, dt):
					b["phase"] = "load"
					main.radio("TOC", "Bird's down. Loading. Keep the wall clear, we can't move people with them at it.")
					if int(evac["launched"]) < 3:
						_launch_bird()
			"load":
				# people can't cross the yard with the infected at the wall
				if int(main.horde.arrived_count) < 60:
					b["load"] = float(b["load"]) + dt
				elif randf() < dt * 0.2:
					main.radio("OVERWATCH", "They're at the wall! We've stopped loading, clear them, Spectre!", true)
				if float(b["load"]) >= 25.0:
					b["phase"] = "out"
					main.radio("TOC", "Bird is full and lifting.")
			"out":
				if main.ops._fly(node, b["home"] + Vector3.UP * 300.0, 75.0, dt) or node.global_position.distance_to(lz) > 3000.0:
					b["phase"] = "gone"
					node.queue_free()
					evac["out"] = int(evac["out"]) + 1
					main.add_population(-mini(int(main.population), int(float(main.pop0) * 0.34) + 20))
					_announce("EXFIL  //  %d OF 3 OUT" % int(evac["out"]))
					if int(evac["out"]) >= 3:
						main.radio("TOC", String(evac["won"]), true)
						evac = {}
						main.campaign_won()
						return
	for k in range(birds.size() - 1, -1, -1):
		if String(birds[k]["phase"]) == "gone":
			birds.remove_at(k)


# ---------------------------------------------------------------- HUD
## The lines under the sensor for whatever's running, and markers on the people and places in it.
## Returns the y below them.
func draw_hud(h, sz: Vector2, c: Vector2, y: float) -> float:
	var cam: Camera3D = main.cam
	var WARN: Color = h.WARN
	var GOOD: Color = h.GOOD
	if not obj.is_empty():
		match String(obj["kind"]):
			"hold":
				var left := maxf(float(obj["dur"]) - float(obj["t"]), 0.0)
				h.txt(Vector2(sz.x * 0.5, y), "HOLD  //  %s  //  %d:%02d  //  %d MEN" % [String(obj["name"]).to_upper(), int(left) / 60, int(left) % 60, int(obj["alive"])], GOOD if int(obj["alive"]) > 3 else WARN, 15, 1, h.font_b)
				h._mark(cam, obj["pos"] + Vector3.UP * 3.0, "RANGER 6", sz, c, true, GOOD)
				h._mark(cam, obj["line"], "DEMO", sz, c, false, Color(GOOD, 0.7))
			"medevac":
				var i: int = obj["i"]
				var lzs: Array = obj["lzs"]
				var left := maxf(float(obj["limit"]) - float(obj["t"]), 0.0)
				if i < lzs.size():
					var lz: Vector3 = lzs[i]
					var hot: int = main.horde.count_near(lz, 60.0, true)
					h.txt(Vector2(sz.x * 0.5, y), "MEDEVAC  //  LZ %d OF %d  //  %s  //  WOUNDED %d:%02d" % [i + 1, lzs.size(), ("HOT: %d INFECTED" % hot) if hot > 2 else "COLD", int(left) / 60, int(left) % 60], WARN if hot > 2 else GOOD, 15, 1, h.font_b)
					h._mark(cam, lz + Vector3.UP * 2.0, "LZ %d %s" % [i + 1, "HOT" if hot > 2 else "COLD"], sz, c, true, WARN if hot > 2 else GOOD)
				else:
					h.txt(Vector2(sz.x * 0.5, y), "MEDEVAC  //  RTB WITH %d WOUNDED" % int(obj["saved"]), GOOD, 15, 1, h.font_b)
				h._mark(cam, (obj["heli"] as Node3D).global_position, "DUSTOFF 3-1", sz, c, false, GOOD)
			"nest":
				var lm: Dictionary = obj["lm"]
				var frac := clampf(float(obj["hp"]) / float(obj["max"]), 0.0, 1.0)
				h.txt(Vector2(sz.x * 0.5, y), "NEST  //  %s  //  STRUCTURE %d%%  //  DELAY FUZES, HEAVY ORDNANCE" % [String(lm["name"]), int(frac * 100.0)], WARN, 15, 1, h.font_b)
				h._mark(cam, (lm["pos"] as Vector3) + Vector3.UP * float((lm["size"] as Vector3).y), "NEST %d%%" % int(frac * 100.0), sz, c, true, WARN)
			"engineers":
				var left := maxf(float(obj["dur"]) - float(obj["t"]), 0.0)
				h.txt(Vector2(sz.x * 0.5, y), "ENGINEERS  //  %s WALL  //  %d:%02d  //  %d OF 6" % [String(obj["sector"]).to_upper(), int(left) / 60, int(left) % 60, int(obj["alive"])], GOOD if int(obj["alive"]) > 3 else WARN, 15, 1, h.font_b)
				h._mark(cam, obj["pos"] + Vector3.UP * 3.0, "ENGINEERS", sz, c, true, GOOD)
		y += 22.0
	if not evac.is_empty():
		var lines: Array = []
		for b in evac["birds"]:
			match String(b["phase"]):
				"in", "land":
					lines.append("INBOUND")
				"load":
					lines.append("LOADING %d%%" % int(float(b["load"]) / 25.0 * 100.0))
				"out":
					lines.append("LIFTING")
			h._mark(cam, (b["node"] as Node3D).global_position, "CHINOOK", sz, c, false, GOOD)
		h.txt(Vector2(sz.x * 0.5, y), "EXFIL  //  %d OF 3 OUT  //  %s" % [int(evac["out"]), "  ".join(lines)], GOOD, 16, 1, h.font_b)
		y += 24.0
	if not dc.is_empty():
		var fr: Vector3 = dc["friendly"]
		var tg: Vector3 = dc["target"]
		var left := maxf(float(dc["dur"]) - float(dc["t"]), 0.0)
		var col := WARN if fmod(float(main.real_t), 0.7) < 0.45 else Color(WARN, 0.7)
		h.txt(Vector2(sz.x * 0.5, y), "DANGER CLOSE  //  %s  //  %d / %d  //  %d S" % [String(dc["where"]).to_upper(), int(dc["kills"]), int(dc["need"]), int(left)], col, 16, 1, h.font_b)
		y += 24.0
		h._mark(cam, fr + Vector3.UP * 2.0, "FRIENDLIES", sz, c, true, GOOD)
		h._mark(cam, tg + Vector3.UP * 1.0, "DANGER CLOSE", sz, c, true, WARN)
		# a 50 m ring round the friendlies on the ground
		var prev := Vector2.INF
		for k in 33:
			var a := TAU * k / 32.0
			var p := fr + Vector3(cos(a), 0.0, sin(a)) * 50.0
			if cam.is_position_behind(p):
				prev = Vector2.INF
				continue
			var s: Vector2 = h.proj(p)
			if prev != Vector2.INF and k % 2 == 1:
				h.ln(prev, s, Color(GOOD, 0.6), 1.5)
			prev = s
	return y


func draw_tac(h, w2s: Callable) -> void:
	var GOOD: Color = h.GOOD
	var WARN: Color = h.WARN
	if not obj.is_empty():
		match String(obj["kind"]):
			"hold", "engineers":
				var p: Vector2 = w2s.call(obj["pos"])
				h.draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), GOOD)
				h.txt(p + Vector2(8, 4), "RANGER 6" if obj["kind"] == "hold" else "ENGINEERS", GOOD, 12, 0, h.font_b)
			"medevac":
				var lzs: Array = obj["lzs"]
				for i in lzs.size():
					var p: Vector2 = w2s.call(lzs[i])
					h.draw_arc(p, 6.0, 0, TAU, 16, GOOD if i >= int(obj["i"]) else Color(GOOD, 0.3), 2.0)
					h.txt(p + Vector2(8, 4), "LZ %d" % (i + 1), GOOD, 12, 0, h.font_b)
				h.draw_circle(w2s.call((obj["heli"] as Node3D).global_position), 3.0, GOOD)
			"nest":
				var lm: Dictionary = obj["lm"]
				var p: Vector2 = w2s.call(lm["pos"])
				h.draw_rect(Rect2(p - Vector2(6, 6), Vector2(12, 12)), WARN, false, 2.0)
				h.txt(p + Vector2(10, 4), "NEST", WARN, 12, 0, h.font_b)
	if not dc.is_empty():
		var p: Vector2 = w2s.call(dc["target"])
		h.draw_arc(p, 8.0, 0, TAU, 16, WARN, 2.0)
		h.txt(p + Vector2(10, 4), "DANGER CLOSE", WARN, 12, 0, h.font_b)
	if not evac.is_empty():
		for b in evac["birds"]:
			h.draw_circle(w2s.call((b["node"] as Node3D).global_position), 3.5, GOOD)


## A story card: the dawn of each day, and the evacuation.
func draw_story(h, sz: Vector2) -> void:
	if story_card.is_empty():
		return
	var age: float = float(main.real_t) - float(story_card["t"])
	if age > 9.0:
		story_card = {}
		return
	var a := clampf(minf(age * 2.0, (9.0 - age) * 1.5), 0.0, 1.0)
	var w := 720.0
	var r := Rect2(Vector2((sz.x - w) * 0.5, 140.0), Vector2(w, 150))
	h.draw_rect(r, Color(0, 0, 0, 0.72 * a))
	h.draw_rect(Rect2(r.position, Vector2(4, r.size.y)), Color(h.ACCENT, a))
	h.ui_txt(r.position + Vector2(26, 34), String(story_card["sub"]), Color(h.ACCENT, a), 14, 0, true)
	h.ui_txt(r.position + Vector2(26, 72), String(story_card["title"]), Color(h.FG, a), 32, 0, true)
	h._wrap(r.position + Vector2(26, 100), String(story_card["text"]), w - 52.0, 15, Color(h.FG, 0.85 * a))
