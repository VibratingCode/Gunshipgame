extends Node3D
## Ground operations between and during the holding actions:
##   RESCUE  - survivors stranded out on an approach pop flares; a Black Hawk launches from the
##             refuge to pick them up. Keep the infected off them until it has.
##   CONVOY  - a supply convoy fights its way in down an avenue. The trucks crush what's in the
##             road but a crowd will tear them apart. Clear the road ahead of them.
## Both grow the refuge: everyone brought in joins its population.

const MeshKit = preload("res://scripts/mesh_kit.gd")

var main
var rescue: Dictionary = {}
var convoy: Dictionary = {}
var next_rescue := 60.0
var convoy_due := -1.0
var heli_mesh: ArrayMesh
var truck_mesh: ArrayMesh
var mat_world: ShaderMaterial
var mat_people: ShaderMaterial


func _ready() -> void:
	mat_world = ShaderMaterial.new()
	mat_world.shader = load("res://shaders/world.gdshader")
	mat_people = ShaderMaterial.new()
	mat_people.shader = load("res://shaders/survivor.gdshader")
	heli_mesh = _uh60()
	truck_mesh = _truck()


static func _uh60() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var olive := Vector2(MeshKit.TAG_OLIVE, 0)
	var dark := Vector2(MeshKit.TAG_DARK, 0)
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 0, 0)), Vector3(2.6, 2.6, 11.0), Color(0.36, 0.3, 0.4, 1.0), olive)
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 0.6, 7.5)), Vector3(0.6, 0.8, 5.0), Color(0.33, 0.3, 0.4, 1.0), olive)
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 1.6, -0.8)), Vector3(1.6, 0.9, 3.0), Color(0.95, 0.0, 0.0, 1.0), olive)
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 2.2, 0)), Vector3(16.0, 0.12, 0.5), Color(0.3, 0.0, 0.0, 1.0), dark)
	MeshKit.box(st, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, 2.2, 0)), Vector3(16.0, 0.12, 0.5), Color(0.3, 0.0, 0.0, 1.0), dark)
	return st.commit()


static func _truck() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 1.5, 1.2)), Vector3(2.5, 2.6, 6.0), Color(0.3, 0.3, 0.5, 1.0), Vector2(MeshKit.TAG_TENT, 0))
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 1.3, -2.8)), Vector3(2.4, 2.2, 2.0), Color(0.8, 0.0, 0.3, 1.0), Vector2(MeshKit.TAG_OLIVE, 0))
	for z: float in [-2.6, 0.4, 2.8]:
		for x: float in [-1.2, 1.2]:
			MeshKit.box(st, Transform3D(Basis(), Vector3(x, 0.5, z)), Vector3(0.4, 1.0, 1.0), Color(0.45, 0.0, 0.0, 1.0), Vector2(MeshKit.TAG_DARK, 0))
	return st.commit()


func busy() -> bool:
	return not rescue.is_empty() or not convoy.is_empty()


# ---------------------------------------------------------------- scheduling
## Called every frame of a wave in progress.
func update(dt: float) -> void:
	if dt <= 0.0:
		return
	# new operations only start while a wave is being fought; running ones carry on regardless
	if main.wave_active and int(main.wave) >= 2 and rescue.is_empty():
		next_rescue -= dt
		if next_rescue <= 0.0:
			_start_rescue()
	if main.wave_active and convoy.is_empty() and convoy_due >= 0.0:
		convoy_due -= dt
		if convoy_due <= 0.0:
			convoy_due = -1.0
			_start_convoy()
	_update_rescue(dt)
	_update_convoy(dt)


## A new wave: from wave 3, the middle wave of every day brings a convoy.
func wave_started(wave: int) -> void:
	if wave >= 3 and (wave - 1) % int(main.DAY_LEN) == 2 and randf() < 0.85:
		convoy_due = randf_range(15.0, 35.0)
	next_rescue = minf(next_rescue, randf_range(35.0, 80.0))


# ---------------------------------------------------------------- rescue
func _start_rescue() -> void:
	var cors: Array = main.corridors
	var c: Dictionary = cors[randi() % cors.size()]
	var a: float = c["ang"]
	var r := randf_range(maxf(float(c["rmin"]) + 120.0, 700.0), 1700.0)
	var lat := 0.0
	if int(c["type"]) == 0:
		lat = randf_range(-float(c["hw"]) + 4.0, float(c["hw"]) - 4.0)
	else:
		a += randf_range(-float(c["half"]), float(c["half"])) * 0.7
	var radial := Vector2(cos(a), sin(a))
	var p2 := radial * r + Vector2(-radial.y, radial.x) * lat
	var p := Vector3(p2.x, 0.0, p2.y)
	var hit: Dictionary = main.raycast(p + Vector3.UP * 400.0, p + Vector3.DOWN * 50.0)
	if not hit.is_empty():
		p = hit["position"]
	var n := randi_range(6, 14)
	# the people themselves, milling about and waving
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = MeshKit.humanoid(false)
	mm.instance_count = n
	for k in n:
		var o := Vector2.from_angle(randf() * TAU) * randf_range(0.5, 3.5)
		mm.set_instance_transform(k, Transform3D(Basis(), p + Vector3(o.x, 0.05, o.y)))
		mm.set_instance_custom_data(k, Color(0.9, randf_range(0.6, 1.2), randf(), randf_range(0.88, 0.96)))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat_people
	add_child(mi)
	# the infected already on that stretch of the approach come with them
	main._spawn_clump(c, 30 + int(main.wave) * 6, r + randf_range(70.0, 220.0))
	rescue = {"pos": p, "n": n, "t": 0.0, "danger": 0.0, "flare": 0.0, "phase": "call", "people": mi,
		"heli": null, "hp": Vector3(0, 30, 0), "load": 0.0}
	var sector := String(main.SECTORS[main.horde.sector_of(p.x, p.z)]).to_lower()
	main.radio("OVERWATCH", "Spectre, %d survivors stranded %.1f klicks out on the %s approach, popping flares. Dustoff's spinning up. Keep them clear." % [n, Vector2(p.x, p.z).length() / 1000.0, sector], true)
	main.banner = "RESCUE  //  %d SURVIVORS  //  %s  %.1f KM" % [n, sector.to_upper(), Vector2(p.x, p.z).length() / 1000.0]
	main.banner_t = main.real_t
	main.sfx.play("alarm", -10.0, 1.3)


func _update_rescue(dt: float) -> void:
	if rescue.is_empty():
		return
	var p: Vector3 = rescue["pos"]
	rescue["t"] = float(rescue["t"]) + dt
	# flares every few seconds until the bird is on the ground
	if String(rescue["phase"]) in ["call", "out"]:
		rescue["flare"] = float(rescue["flare"]) - dt
		if float(rescue["flare"]) <= 0.0:
			rescue["flare"] = 3.5
			main.fx.particle(true, p + Vector3.UP * 2.0, Vector3(randf_range(-4, 4), 45.0, randf_range(-4, 4)), 5.0, 1.4, 2.6, 2.4, 3, 0.28, 0.25)
			main.fx.particle(true, p + Vector3.UP, Vector3.ZERO, 0.4, 1.0, 6.0, 1.8, 0)
	# how close the infected are to them
	var near: int = main.horde.count_near(p, 22.0, true)
	if near >= 4:
		rescue["danger"] = float(rescue["danger"]) + dt * near / 4.0
	else:
		rescue["danger"] = maxf(0.0, float(rescue["danger"]) - dt * 0.5)
	if float(rescue["danger"]) > 6.0 and String(rescue["phase"]) != "back":
		_end_rescue(false)
		return
	var heli: MeshInstance3D = rescue["heli"]
	match String(rescue["phase"]):
		"call":
			if float(rescue["t"]) > 6.0:
				heli = MeshInstance3D.new()
				heli.mesh = heli_mesh
				heli.material_override = mat_world
				add_child(heli)
				heli.global_position = rescue["hp"]
				rescue["heli"] = heli
				rescue["phase"] = "out"
				main.radio("DUSTOFF", "Dustoff two-six lifting. Inbound to the survivors.")
		"out":
			var goal := p + Vector3.UP * 60.0
			if _fly(heli, goal, 65.0, dt):
				rescue["phase"] = "land"
		"land":
			if _fly(heli, p + Vector3(6.0, 1.5, 0.0), 12.0, dt):
				rescue["phase"] = "load"
				main.radio("DUSTOFF", "Wheels down. Loading. Keep them off us, Spectre.")
		"load":
			rescue["load"] = float(rescue["load"]) + dt
			if float(rescue["load"]) > 7.0:
				(rescue["people"] as Node3D).queue_free()
				rescue["people"] = null
				rescue["phase"] = "back"
				main.radio("DUSTOFF", "Everyone's aboard. Coming home.")
		"back":
			if _fly(heli, rescue["hp"] + Vector3.UP * 20.0, 70.0, dt):
				_end_rescue(true)


## Move the helicopter toward goal; true once it's there.
func _fly(heli: MeshInstance3D, goal: Vector3, speed: float, dt: float) -> bool:
	var pos := heli.global_position
	var to := goal - pos
	if to.length() < 2.0:
		return true
	var step := to.normalized() * minf(speed * dt, to.length())
	heli.global_position = pos + step
	var flat := Vector3(to.x, 0.0, to.z)
	if flat.length() > 1.0:
		heli.look_at(heli.global_position + flat, Vector3.UP)
		heli.rotate_object_local(Vector3.RIGHT, -0.15)
	main.fx.particle(false, heli.global_position + Vector3.DOWN * 2.0, Vector3.DOWN * 4.0, 0.6, 2.0, 5.0, 0.4, 2, 0.0, 0.8)
	return false


func _end_rescue(ok: bool) -> void:
	var n: int = rescue["n"]
	var p: Vector3 = rescue["pos"]
	if rescue["people"] != null:
		(rescue["people"] as Node3D).queue_free()
	if rescue["heli"] != null:
		(rescue["heli"] as Node3D).queue_free()
	rescue = {}
	next_rescue = randf_range(70.0, 140.0)
	if ok:
		var pay := int(round(250.0 * n * (1.0 + float(main.wave) * 0.05) * float(main.stat("rp")) * float(main.rp_event)))
		main.rp += pay
		main.rp_total += pay
		main.add_population(n)
		main.radio("OVERWATCH", "Dustoff's down inside the wire. %d more souls in the %s. Good work, Spectre." % [n, String(main.refuge_name).to_lower()], true)
		main.banner = "RESCUE COMPLETE  //  +%d SURVIVORS  //  +%s RP" % [n, main.hud.commas(pay)]
		main._feed("RESCUE  +%d SURVIVORS  +%s RP" % [n, main.hud.commas(pay)])
		main.sfx.play("buy", -2.0, 1.1)
	else:
		main.radio("OVERWATCH", "We lost them, Spectre. The infected got there first.", true)
		main.banner = "RESCUE FAILED  //  %d LOST" % n
		main.fx.explosion(p, 1)
	main.banner_t = main.real_t


# ---------------------------------------------------------------- convoy
func _start_convoy() -> void:
	var lanes: Array = []
	for c in main.corridors:
		if int(c["type"]) == 0 and float(c["rmax"]) > 2000.0:
			lanes.append(c)
	if lanes.is_empty():
		return
	var c: Dictionary = lanes[randi() % lanes.size()]
	var a: float = c["ang"]
	var d := Vector3(cos(a), 0.0, sin(a))
	var r0 := maxf(2300.0, float(c["rmin"]) + 300.0)
	var trucks: Array = []
	for k in 5:
		var node := MeshInstance3D.new()
		node.mesh = truck_mesh
		node.material_override = mat_world
		add_child(node)
		var r := r0 + k * 22.0
		node.global_position = d * r
		node.look_at(Vector3.ZERO, Vector3.UP)
		trucks.append({"r": r, "hp": 100.0, "node": node, "alive": true, "in": false})
	convoy = {"dir": d, "trucks": trucks, "speed": 11.0, "t": 0.0, "kills": 0}
	var sector := String(main.SECTORS[main.horde.sector_of(d.x, d.z)]).to_lower()
	main.radio("TOC", "Spectre, a supply convoy is fighting in down the %s avenue. Five trucks: food, ammunition, people. Clear the road for them." % sector, true)
	main.banner = "CONVOY  //  5 TRUCKS  //  %s AVENUE" % sector.to_upper()
	main.banner_t = main.real_t
	main.sfx.play("alarm", -10.0, 1.0)


func _update_convoy(dt: float) -> void:
	if convoy.is_empty():
		return
	var d: Vector3 = convoy["dir"]
	var speed: float = convoy["speed"]
	var stop: float = float(main.wall_r) + 14.0
	var running := 0
	var arrived := 0
	for k in convoy["trucks"].size():
		var tr: Dictionary = convoy["trucks"][k]
		if not tr["alive"]:
			continue
		if tr["in"]:
			arrived += 1
			continue
		running += 1
		var node: MeshInstance3D = tr["node"]
		var r0: float = tr["r"]
		# keep station behind the truck ahead
		var r := maxf(r0 - speed * dt, stop + k * 3.0)
		tr["r"] = r
		var prev := d * r0
		var pos := d * r
		node.global_position = pos + Vector3.UP * 0.1
		# whatever is in the road goes under the wheels, and every one of them hurts the truck
		var crushed: int = main.horde.line_blast(prev, pos + -d * 3.0, 2.4, 50.0, 7.0)
		if crushed > 0:
			main.add_kills(crushed, pos, false)
			convoy["kills"] = int(convoy["kills"]) + crushed
		var crowd: int = main.horde.count_near(pos, 7.0, true)
		tr["hp"] = float(tr["hp"]) - crushed * 1.6 - crowd * 1.3 * dt
		if randf() < dt * 2.0:
			main.fx.particle(false, pos + Vector3.UP + d * 3.0, Vector3.UP * 2.0 + d * 3.0, 1.5, 1.5, 5.0, 0.5, 2, 0.0, 0.6)
		if float(tr["hp"]) <= 0.0:
			tr["alive"] = false
			node.queue_free()
			main.fx.explosion(pos, 3)
			main.sfx.play_at("exp_large", pos, main.cam.global_position, 6.0, 0.9)
			main.horde.blast(pos, 8.0, 18.0, 20.0, 15.0)
			main.radio("CONVOY", ["Truck down! Truck down!", "We lost one, they're all over it!", "Vehicle's burning, crew's gone!"].pick_random(), true)
		elif r <= stop + k * 3.0 + 0.5:
			tr["in"] = true
			arrived += 1
			running -= 1
	if running == 0:
		_end_convoy(arrived)


func _end_convoy(arrived: int) -> void:
	for tr in convoy["trucks"]:
		if tr["alive"]:
			(tr["node"] as Node3D).queue_free()
	convoy = {}
	if arrived <= 0:
		main.radio("TOC", "The convoy's gone, Spectre. Every truck.", true)
		main.banner = "CONVOY LOST"
		main.banner_t = main.real_t
		return
	var pay := int(round(1200.0 * arrived * (1.0 + float(main.wave) * 0.05) * float(main.stat("rp")) * float(main.rp_event)))
	main.rp += pay
	main.rp_total += pay
	main.add_population(25 * arrived)
	if arrived >= 3:
		for w in main.arsenal.weapons:
			if w["owned"]:
				main.arsenal.fill(w)
	main.radio("TOC", "%d trucks inside the wire. %s Thank you, Spectre." % [arrived, "Ammunition's going straight to your loadmasters." if arrived >= 3 else "It's not much, but it's something."], true)
	main.banner = "CONVOY IN  //  %d OF 5 TRUCKS  //  +%s RP%s" % [arrived, main.hud.commas(pay), "  //  RESTOCKED" if arrived >= 3 else ""]
	main.banner_t = main.real_t
	main._feed("CONVOY  %d/5 IN  +%s RP" % [arrived, main.hud.commas(pay)])
	main.sfx.play("buy", -2.0, 0.9)
