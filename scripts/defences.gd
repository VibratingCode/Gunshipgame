extends Node3D
## The refuge's passive defences, built from the REFUGE upgrades (and a few perks): crewed .50 cal
## guard towers, a claymore belt, 81 mm mortars, a fire trench, C-RAM Phalanx mounts and a 155 mm
## battery. They pick their own targets and fire real rounds from real positions in the refuge;
## their kills pay requisition like yours.

const MeshKit = preload("res://scripts/mesh_kit.gd")
const G := 9.8

var main
var visual: MeshInstance3D
var mat: ShaderMaterial
var layout := ""            # the levels the current visuals were built for

var towers: Array = []      # {pos, acc}
var ciws: Array = []        # {pos, acc, snd}
var mortars: Array = []     # {pos, cd}
var guns: Array = []        # {pos, cd}
var shells: Array = []      # [hit time, point, kind]
var claymore_cd := 0.0
var trench_acc := 0.0
var trench_r := 0.0
var trench_lvl := 0
var claymore_lvl := 0
var tally := {}             # kills per defence since the last kill-feed line
var tally_t := 0.0
# the refuge grows: shelters for every day survived, and the people you bring in
var growth_days := 0
var people: MultiMeshInstance3D
var people_n := -1
var mat_people: ShaderMaterial

# what each kind of round does when it lands: r_kill, r_frag, damage, fling, fx, sound, volume
const HITS := {
	"50": [1.3, 2.0, 2.0, 3.0, 7, "", 0.0],
	"20": [1.5, 2.6, 2.5, 4.0, 8, "", 0.0],
	"81": [6.0, 14.0, 12.0, 12.0, 1, "exp_med", 2.0],
	"155": [14.0, 32.0, 35.0, 22.0, 2, "exp_large", 8.0],
}
const NAMES := {"50": "GUARD TOWERS", "20": "PHALANX", "81": "MORTARS", "155": "M777 BATTERY", "claymore": "CLAYMORES", "trench": "FIRE TRENCH"}


func _ready() -> void:
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/world.gdshader")
	mat_people = ShaderMaterial.new()
	mat_people.shader = load("res://shaders/survivor.gdshader")


## Another day survived: the refuge builds out a little more.
func grow_day() -> void:
	growth_days += 1
	layout = ""
	rebuild()


## Everyone brought in since the sortie began, visible inside the walls.
func set_people(extra: int) -> void:
	var n := clampi(extra, 0, 400)
	if n == people_n:
		return
	people_n = n
	if people:
		people.queue_free()
		people = null
	if n <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var wall: float = main.wall_r
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = MeshKit.humanoid(false)
	mm.instance_count = n
	for k in n:
		var p := _inside(rng, 0.2, 0.75) * wall
		mm.set_instance_transform(k, Transform3D(Basis(), Vector3(p.x, 0.1, p.y)))
		mm.set_instance_custom_data(k, Color(rng.randf_range(1.0, 4.0), rng.randf_range(0.3, 0.8), rng.randf(), rng.randf_range(0.86, 0.97)))
	people = MultiMeshInstance3D.new()
	people.multimesh = mm
	people.material_override = mat_people
	add_child(people)


## A random point inside the refuge, as a fraction of its radius (landward only at the port).
func _inside(rng: RandomNumberGenerator, f0: float, f1: float) -> Vector2:
	var a := rng.randf() * TAU
	if String(main.ao_base) == "port":
		a = rng.randf_range(PI * 1.1, PI * 1.9)
	return Vector2(cos(a), sin(a)) * sqrt(rng.randf_range(f0 * f0, f1 * f1))


func _ring(n: int, r: float, start := 0.0) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var a0 := 0.0
	var span := TAU
	if String(main.ao_base) == "port":
		# the sea is at our back: everything faces the land
		a0 = PI * 1.08
		span = PI * 0.84
	for k in n:
		var a := a0 + span * (float(k) + 0.5 + start) / float(maxi(n, 1))
		out.append(Vector2(cos(a), sin(a)) * r)
	return out


## (Re)build the positions and meshes for the current upgrade levels.
func rebuild() -> void:
	var n_towers := int(main.stat("add_towers"))
	var n_ciws := int(main.stat("add_ciws"))
	var n_mortars := int(main.stat("add_mortars"))
	var n_guns := int(main.stat("add_howitzers"))
	claymore_lvl = int(main.stat("add_claymores"))
	trench_lvl = int(main.stat("add_trench"))
	var key := "%d/%d/%d/%d/%d/%d/%d" % [n_towers, n_ciws, n_mortars, n_guns, claymore_lvl, trench_lvl, growth_days]
	if key == layout:
		return
	layout = key
	var wall: float = main.wall_r
	var arrive: Vector2 = main.arrive
	trench_r = arrive.y + 14.0
	towers.clear()
	ciws.clear()
	mortars.clear()
	guns.clear()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for p in _ring(n_towers, wall - 4.0, 0.25):
		towers.append({"pos": Vector3(p.x, 13.0, p.y), "acc": randf()})
		MeshKit.tag = MeshKit.TAG_TIMBER
		for s: Vector2 in [Vector2(-1.4, -1.4), Vector2(1.4, -1.4), Vector2(1.4, 1.4), Vector2(-1.4, 1.4)]:
			MeshKit.box(st, Transform3D(Basis(), Vector3(p.x + s.x, 5.5, p.y + s.y)), Vector3(0.4, 11.0, 0.4), Color(0.28, 0.4, 0.6, 1.0))
		MeshKit.tag = MeshKit.TAG_HESCO
		MeshKit.box(st, Transform3D(Basis(), Vector3(p.x, 11.6, p.y)), Vector3(4.2, 1.2, 4.2), Color(0.31, 0.6, 1.0, 1.0))
		MeshKit.tag = MeshKit.TAG_OLIVE
		MeshKit.box(st, Transform3D(Basis(), Vector3(p.x, 13.6, p.y)), Vector3(4.4, 0.3, 4.4), Color(0.3, 0.3, 0.6, 1.0))
		any = true
	for p in _ring(n_ciws, wall * 0.62, 0.5):
		ciws.append({"pos": Vector3(p.x, 9.0, p.y), "acc": 0.0, "snd": 0.0})
		MeshKit.tag = MeshKit.TAG_OLIVE
		MeshKit.box(st, Transform3D(Basis(), Vector3(p.x, 3.0, p.y)), Vector3(4.0, 6.0, 4.0), Color(0.3, 0.4, 0.6, 1.0))
		MeshKit.tag = MeshKit.TAG_WHITE
		MeshKit.box(st, Transform3D(Basis(), Vector3(p.x, 7.0, p.y)), Vector3(2.4, 2.0, 2.4), Color(0.32, 0.4, 0.6, 1.0))
		MeshKit.dome(st, Vector3(p.x, 8.0, p.y), 1.4, Color(0.34, 0.4, 0.6, 1.0))
		MeshKit.tag = MeshKit.TAG_DARK
		MeshKit.box(st, Transform3D(Basis(), Vector3(p.x, 7.4, p.y - 1.8)), Vector3(0.5, 0.5, 2.6), Color(0.3, 0.0, 0.0, 1.0))
		any = true
	for p in _ring(n_mortars, wall * 0.42, 0.1):
		mortars.append({"pos": Vector3(p.x, 0.5, p.y), "cd": randf_range(1.0, 4.0)})
		MeshKit.tag = MeshKit.TAG_HESCO
		for k in 6:
			var a := TAU * k / 6.0
			MeshKit.box(st, Transform3D(Basis(Vector3.UP, -a), Vector3(p.x + cos(a) * 3.0, 0.5, p.y + sin(a) * 3.0)), Vector3(3.0, 1.0, 0.9), Color(0.31, 0.6, 1.0, 1.0))
		MeshKit.tag = MeshKit.TAG_DARK
		MeshKit.box(st, Transform3D(Basis(Vector3.RIGHT, 0.6), Vector3(p.x, 0.8, p.y)), Vector3(0.25, 0.25, 1.6), Color(0.3, 0.0, 0.0, 1.0))
		any = true
	for p in _ring(n_guns, wall * 0.28, 0.75):
		guns.append({"pos": Vector3(p.x, 2.2, p.y), "cd": randf_range(2.0, 6.0)})
		MeshKit.tag = MeshKit.TAG_OLIVE
		var face := Basis(Vector3.UP, -p.angle() - PI * 0.5)
		MeshKit.box(st, Transform3D(face, Vector3(p.x, 0.8, p.y)), Vector3(3.0, 1.6, 4.0), Color(0.3, 0.3, 0.5, 1.0))
		MeshKit.box(st, Transform3D(face * Basis(Vector3.RIGHT, 0.45), Vector3(p.x, 2.2, p.y) + face * Vector3(0, 0, -2.5)), Vector3(0.45, 0.45, 6.0), Color(0.31, 0.3, 0.4, 1.0))
		any = true
	if trench_lvl > 0:
		MeshKit.tag = MeshKit.TAG_DIRT
		var segs := 72
		for k in segs:
			var a0 := TAU * k / segs
			var a1 := TAU * (k + 1) / segs
			var d0 := Vector3(cos(a0), 0, sin(a0))
			var d1 := Vector3(cos(a1), 0, sin(a1))
			var y := Vector3(0, 0.09, 0)
			MeshKit.quad(st, d0 * (trench_r - 3.0) + y, d1 * (trench_r - 3.0) + y, d1 * (trench_r + 3.0) + y, d0 * (trench_r + 3.0) + y, Vector3.UP, Color(0.36, 0.0, 0.6, 1.0))
		any = true
	if claymore_lvl > 0:
		MeshKit.tag = MeshKit.TAG_OLIVE
		var n := 24 * claymore_lvl
		for k in n:
			var a := TAU * k / n
			var p := Vector2(cos(a), sin(a)) * (arrive.x - 2.0)
			MeshKit.box(st, Transform3D(Basis(Vector3.UP, -a), Vector3(p.x, 0.25, p.y)), Vector3(0.25, 0.3, 0.7), Color(0.27, 0.2, 0.4, 1.0))
		any = true
	# the refuge builds out a little more every day it survives: shelters, prefabs, lights
	var grng := RandomNumberGenerator.new()
	grng.seed = 1777
	for day in mini(growth_days, 10):
		for k in 4:
			var p := _inside(grng, 0.3, 0.85) * wall
			MeshKit.tag = MeshKit.TAG_TENT
			MeshKit.box(st, Transform3D(Basis(Vector3.UP, grng.randf() * TAU), Vector3(p.x, 1.3, p.y)), Vector3(4.0, 2.6, 6.0), Color(grng.randf_range(0.5, 0.62), 0.0, 0.6, 1.0))
		for k in 2:
			var p := _inside(grng, 0.3, 0.8) * wall
			MeshKit.tag = MeshKit.TAG_WHITE
			MeshKit.box(st, Transform3D(Basis(Vector3.UP, grng.randf() * TAU), Vector3(p.x, 1.5, p.y)), Vector3(6.0, 3.0, 2.6), Color(grng.randf_range(0.4, 0.45), 1.0, 1.0, 0.5))
		var lp := _inside(grng, 0.4, 0.8) * wall
		MeshKit.tag = MeshKit.TAG_DARK
		MeshKit.box(st, Transform3D(Basis(), Vector3(lp.x, 6.0, lp.y)), Vector3(0.5, 12.0, 0.5), Color(0.25, 0.0, 0.0, 1.0))
		MeshKit.box(st, Transform3D(Basis(), Vector3(lp.x, 12.3, lp.y)), Vector3(2.0, 0.8, 0.8), Color(1.15, 0.8, 0.0, 1.0))
		any = true
	MeshKit.tag = MeshKit.TAG_AUTO
	if visual:
		visual.queue_free()
		visual = null
	if any:
		visual = MeshInstance3D.new()
		visual.mesh = st.commit()
		visual.material_override = mat
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(visual)


# ---------------------------------------------------------------- targeting
## A live infected near `from`, within r, chosen from the horde's list of threats near the refuge.
func _target(from: Vector3, r: float) -> int:
	var thr: PackedInt32Array = main.horde.threats
	if thr.is_empty():
		return -1
	var best := -1
	var bd := r * r
	for k in 8:
		var i: int = thr[randi() % thr.size()]
		if main.horde.z_alive[i] == 0:
			continue
		var p: Vector2 = main.horde.pos_of(i)
		var d := Vector2(p.x - from.x, p.y - from.z).length_squared()
		if d < bd:
			bd = d
			best = i
	return best


## The centre of the thickest crowd between r0 and r1 from the refuge, from the horde's density map.
func _crowd(r0: float, r1: float) -> Vector3:
	var dens: PackedInt32Array = main.horde.density
	var dn: int = main.horde.DN
	var dbin: float = main.horde.DBIN
	var half: float = main.horde.GRID_HALF
	var best := Vector3.INF
	var bn := 3
	for bz in dn:
		for bx in dn:
			var n := dens[bz * dn + bx]
			if n <= bn:
				continue
			var c := Vector3((bx + 0.5) * dbin - half, 0.0, (bz + 0.5) * dbin - half)
			var r := Vector2(c.x, c.z).length()
			if r < r0 or r > r1:
				continue
			bn = n
			best = c
	if best == Vector3.INF:
		return best
	return best + Vector3(randf_range(-35, 35), 0.0, randf_range(-35, 35))


func _shoot(from: Vector3, to: Vector3, speed: float, kind: String, heat: float, width: float, arc := 0.0) -> void:
	var dist := from.distance_to(to)
	var tf := maxf(dist / speed, 0.05) + arc
	var v0 := (to - from) / tf + Vector3(0.0, 0.5 * G * tf, 0.0)
	main.fx.tracer(from, v0, tf, heat, width, 0.03 if arc == 0.0 else 0.06)
	shells.append([main.t + tf, to, kind])


func _credit(kind: String, k: int, pos: Vector3) -> void:
	if k <= 0:
		return
	main.add_kills(k, pos, false)
	tally[kind] = int(tally.get(kind, 0)) + k


# ---------------------------------------------------------------- per frame
func update(dt: float) -> void:
	if dt <= 0.0:
		return
	var rate: float = main.stat("def_rate")
	var now: float = main.t
	var cam_pos: Vector3 = main.cam.global_position
	# guard towers: aimed .50 cal, 4 rounds a second each
	for tw in towers:
		tw["acc"] = float(tw["acc"]) + dt * 4.0 * rate
		while float(tw["acc"]) >= 1.0:
			tw["acc"] = float(tw["acc"]) - 1.0
			var pos: Vector3 = tw["pos"]
			var zi := _target(pos, 650.0)
			if zi < 0:
				tw["acc"] = 0.0
				break
			# lead it by the round's time of flight
			var zp0: Vector2 = main.horde.pos_of(zi)
			var tof := pos.distance_to(Vector3(zp0.x, 0.0, zp0.y)) / 900.0
			var zp: Vector2 = main.horde.pos_at(zi, now + tof)
			var to := Vector3(zp.x + randfn(0.0, 1.2), 0.6, zp.y + randfn(0.0, 1.2))
			_shoot(pos, to, 900.0, "50", 1.1, 0.06)
			main.fx.particle(true, pos, Vector3.ZERO, 0.05, 0.4, 1.2, 1.6, 0)
	# Phalanx: a stream of 20 mm at anything close
	for cw in ciws:
		var pos: Vector3 = cw["pos"]
		var zi := _target(pos, 450.0)
		if zi < 0:
			cw["acc"] = 0.0
			continue
		cw["acc"] = float(cw["acc"]) + dt * 25.0 * rate
		var zp: Vector2 = main.horde.pos_of(zi)
		while float(cw["acc"]) >= 1.0:
			cw["acc"] = float(cw["acc"]) - 1.0
			var to := Vector3(zp.x + randfn(0.0, 2.5), 0.6, zp.y + randfn(0.0, 2.5))
			_shoot(pos, to, 1100.0, "20", 1.4, 0.07)
		cw["snd"] = float(cw["snd"]) - dt
		if float(cw["snd"]) <= 0.0:
			cw["snd"] = 0.9
			main.sfx.play_at("gau12_loop", pos, cam_pos, -4.0, 1.25)
			main.fx.particle(true, pos + Vector3(0, -0.6, -1.8), Vector3.ZERO, 0.1, 0.6, 2.5, 1.8, 0)
	# mortars: high arcs onto the thickest crowd inside 1.6 km
	for m in mortars:
		m["cd"] = float(m["cd"]) - dt
		if float(m["cd"]) > 0.0:
			continue
		var c := _crowd(150.0, 1600.0)
		if c == Vector3.INF:
			m["cd"] = 2.0
			continue
		m["cd"] = 4.5 / rate
		var pos: Vector3 = m["pos"]
		_shoot(pos, c, 220.0, "81", 0.55, 0.12, 6.0)
		main.sfx.play_at("howitzer", pos, cam_pos, -10.0, 1.7)
		main.fx.particle(false, pos + Vector3.UP * 2.0, Vector3.UP * 3.0, 1.5, 1.5, 5.0, 0.5, 2, 0.0, 0.5)
	# the 155 battery: the biggest crowd 1 to 3 km out
	for g in guns:
		g["cd"] = float(g["cd"]) - dt
		if float(g["cd"]) > 0.0:
			continue
		var c := _crowd(900.0, 3100.0)
		if c == Vector3.INF:
			g["cd"] = 3.0
			continue
		g["cd"] = 11.0 / rate
		var pos: Vector3 = g["pos"]
		_shoot(pos, c, 500.0, "155", 0.6, 0.18, 6.0)
		main.sfx.play_at("howitzer", pos, cam_pos, 2.0, 0.95)
		main.fx.particle(true, pos + Vector3.UP * 3.0, Vector3.ZERO, 0.12, 3.0, 14.0, 2.0, 0)
		main.fx.particle(false, pos + Vector3.UP * 3.0, Vector3.UP * 4.0, 3.0, 4.0, 14.0, 0.5, 2, 0.0, 0.5)
	# claymores: whatever reaches the wall walks into one
	if claymore_lvl > 0 and main.horde.arrived_count > 0:
		claymore_cd -= dt
		if claymore_cd <= 0.0:
			claymore_cd = 3.0 / (claymore_lvl * rate)
			var lst: PackedInt32Array = main.horde.arrived_list
			for k in 6:
				if lst.is_empty():
					break
				var ci: int = lst[randi() % lst.size()]
				if main.horde.z_alive[ci] == 1 and main.horde.z_arrived[ci] == 1:
					var cp: Vector2 = main.horde.pos_of(ci)
					var bp := Vector3(cp.x, 0.5, cp.y)
					var kc: int = main.horde.blast(bp, 7.0, 15.0, 15.0, 12.0)
					_credit("claymore", kc, bp)
					main.fx.explosion(bp, 1)
					main.sfx.play_at("exp_med", bp, cam_pos, 0.0, 1.2)
					break
	# the fire trench: everything crossing it burns
	if trench_lvl > 0:
		trench_acc += dt
		if trench_acc >= 0.5:
			var step := trench_acc
			trench_acc = 0.0
			var dps: float = 3.5 * trench_lvl * float(main.stat("fire_dps"))
			var segs := 36
			for k in segs:
				var a0 := TAU * k / segs
				var a1 := TAU * (k + 1) / segs
				var p0 := Vector3(cos(a0), 0, sin(a0)) * trench_r
				var p1 := Vector3(cos(a1), 0, sin(a1)) * trench_r
				main.horde.burn_kills = true
				var kt: int = main.horde.line_blast(p0, p1, 4.0, dps * step, 1.5)
				main.horde.burn_kills = false
				_credit("trench", kt, p0)
			for k in 6:
				var a := randf() * TAU
				var fp := Vector3(cos(a), 0, sin(a)) * (trench_r + randf_range(-2.5, 2.5))
				main.fx.particle(true, fp + Vector3.UP * 1.5, Vector3.UP * randf_range(2, 4), randf_range(1.0, 2.0), 2.0, 5.0, 1.3, 1, -0.02, 0.5)
	# rounds landing
	var si := 0
	while si < shells.size():
		var s: Array = shells[si]
		if float(s[0]) > now:
			si += 1
			continue
		shells.remove_at(si)
		var sk: String = s[2]
		var sp: Vector3 = s[1]
		var h: Array = HITS[sk]
		var kills: int = main.horde.blast(sp, float(h[0]), float(h[1]), float(h[2]), float(h[3]))
		_credit(sk, kills, sp)
		main.fx.explosion(sp, int(h[4]))
		if String(h[5]) != "":
			main.sfx.play_at(String(h[5]), sp, cam_pos, float(h[6]))
	# a kill-feed line now and then for the defences that are earning their keep
	tally_t += dt
	if tally_t > 8.0:
		tally_t = 0.0
		for kind in tally:
			if int(tally[kind]) >= 10:
				main._feed("%s  +%d" % [String(NAMES.get(kind, kind)), int(tally[kind])])
		tally.clear()
