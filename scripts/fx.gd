extends Node3D
## Pooled GPU effects. Each pool is a ring buffer in a MultiMesh; particles move
## analytically in their shaders, so the CPU only writes a particle once at birth.

const CAP_ADD := 16000
const CAP_MIX := 9000
const CAP_TR := 6000
const CAP_DEC := 5000

var time := 0.0
var mm_add: MultiMesh
var mm_mix: MultiMesh
var mm_tr: MultiMesh
var mm_dec: MultiMesh
var i_add := 0
var i_mix := 0
var i_tr := 0
var i_dec := 0
var n_add := 0
var n_mix := 0
var n_tr := 0
var n_dec := 0


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var plane := PlaneMesh.new()
	plane.size = Vector2(1, 1)
	mm_dec = _make(plane, "res://shaders/decal.gdshader", CAP_DEC)
	mm_mix = _make(quad, "res://shaders/fx_mix.gdshader", CAP_MIX)
	mm_add = _make(quad, "res://shaders/fx_add.gdshader", CAP_ADD)
	mm_tr = _make(quad, "res://shaders/tracer.gdshader", CAP_TR)


func _make(mesh: Mesh, shader_path: String, cap: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.custom_aabb = AABB(Vector3(-6000, -100, -6000), Vector3(12000, 4000, 12000))
	mm.mesh = mesh
	mm.instance_count = cap
	var buf := PackedFloat32Array()
	buf.resize(cap * 16)
	mm.buffer = buf
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = load(shader_path)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-6000, -100, -6000), Vector3(12000, 4000, 12000))
	add_child(mi)
	return mm


func _process(_dt: float) -> void:
	for pair in [[mm_add, n_add], [mm_mix, n_mix], [mm_tr, n_tr], [mm_dec, n_dec]]:
		var m: MultiMesh = pair[0]
		if m.visible_instance_count != int(pair[1]):
			m.visible_instance_count = pair[1]


## kind: 0 flash, 1 fireball, 2 smoke/dust, 3 spark/debris, 4 ground shock ring.
func particle(additive: bool, pos: Vector3, vel: Vector3, life: float, s0: float, s1: float, heat: float, kind: int, grav := 0.0, drag := 0.0) -> void:
	var xf := Transform3D(Basis(vel, Vector3(grav, drag, heat), Vector3(kind, randf() * TAU, 0.0)), pos)
	var cd := Color(time, life, s0, s1)
	if additive:
		mm_add.set_instance_transform(i_add, xf)
		mm_add.set_instance_custom_data(i_add, cd)
		i_add = (i_add + 1) % CAP_ADD
		n_add = mini(n_add + 1, CAP_ADD)
	else:
		mm_mix.set_instance_transform(i_mix, xf)
		mm_mix.set_instance_custom_data(i_mix, cd)
		i_mix = (i_mix + 1) % CAP_MIX
		n_mix = mini(n_mix + 1, CAP_MIX)


## A hot projectile on a ballistic arc from p0 with launch velocity v0, landing after tf seconds.
func tracer(p0: Vector3, v0: Vector3, tf: float, heat: float, width: float, streak: float, delay := 0.0) -> void:
	var xf := Transform3D(Basis(v0, Vector3(heat, width, streak), Vector3.ZERO), p0)
	mm_tr.set_instance_transform(i_tr, xf)
	mm_tr.set_instance_custom_data(i_tr, Color(time + delay, tf, 0.0, 0.0))
	i_tr = (i_tr + 1) % CAP_TR
	n_tr = mini(n_tr + 1, CAP_TR)


func decal(pos: Vector3, size: float, h0: float, residual: float, cool: float) -> void:
	var b := Basis(Vector3.UP, randf() * TAU).scaled(Vector3(size, 1.0, size))
	mm_dec.set_instance_transform(i_dec, Transform3D(b, pos + Vector3(0, 0.12, 0)))
	mm_dec.set_instance_custom_data(i_dec, Color(time, h0, residual, cool))
	i_dec = (i_dec + 1) % CAP_DEC
	n_dec = mini(n_dec + 1, CAP_DEC)


static func _rdir(up_bias: float) -> Vector3:
	var v := Vector3(randf_range(-1, 1), randf_range(0.0, 1.0) + up_bias, randf_range(-1, 1))
	return v.normalized()


## power: 0 = 30 mm, 1 = 40 mm, 2 = 105 mm, 3 = Hellfire, 4 = SDB, 5 = JDAM, 6 = MOAB,
## 7 = .50 cal, 8 = 25 mm, 9 = THOR rod
## tnt: TNT-equivalent kg (explosive fill, or impact energy for kinetic weapons). When given, the
## ground shock ring is sized from it instead of from the visual recipe.
func explosion(pos: Vector3, power: int, tnt := -1.0) -> void:
	var own_ring := tnt < 0.0
	if not own_ring:
		shock(pos, tnt)
	match power:
		0:
			# 30 mm HEI: a small but solid blast wave, visible as a ring racing out over the ground
			if own_ring:
				particle(true, pos + Vector3(0, 0.3, 0), Vector3.ZERO, 0.16, 0.5, 13.0, 1.2, 4)
			particle(true, pos + Vector3(0, 0.8, 0), Vector3.ZERO, 0.07, 1.0, 5.5, 1.8, 0)
			particle(true, pos + Vector3(0, 1.0, 0), Vector3(0, 3, 0), 0.35, 1.5, 3.5, 1.0, 1, 0.0, 2.0)
			for k in 4:
				particle(true, pos, _rdir(0.6) * randf_range(14, 32), randf_range(0.3, 0.7), 0.35, 0.25, 1.3, 3, 1.0, 0.6)
			particle(false, pos + Vector3(0, 1.5, 0), Vector3(randf_range(-1, 1), 2.5, randf_range(-1, 1)), randf_range(2.0, 3.2), 2.0, 7.0, 0.5, 2, 0.0, 0.8)
			decal(pos, randf_range(2.2, 3.4), 0.75, 0.35, 9.0)
		1:
			particle(true, pos + Vector3(0, 1.5, 0), Vector3.ZERO, 0.09, 2.0, 10.0, 2.0, 0)
			particle(true, pos + Vector3(0, 2.0, 0), Vector3(0, 4, 0), 0.6, 4.0, 8.0, 1.1, 1, 0.0, 1.5)
			for k in 12:
				particle(true, pos, _rdir(0.5) * randf_range(18, 45), randf_range(0.4, 1.1), 0.5, 0.35, 1.4, 3, 1.0, 0.5)
			for k in 2:
				particle(false, pos + Vector3(randf_range(-2, 2), 3, randf_range(-2, 2)), Vector3(randf_range(-1.5, 1.5), 3.0, randf_range(-1.5, 1.5)), randf_range(4.0, 6.0), 4.0, 15.0, 0.55, 2, -0.02, 0.5)
			decal(pos, randf_range(5.0, 6.5), 0.8, 0.37, 18.0)
		7:
			# .50 cal ball: a kick of dirt, a spark, no detonation
			particle(true, pos + Vector3(0, 0.3, 0), Vector3.ZERO, 0.05, 0.4, 1.2, 1.2, 0)
			particle(false, pos + Vector3(0, 0.6, 0), Vector3(randf_range(-0.5, 0.5), 1.5, randf_range(-0.5, 0.5)), randf_range(1.0, 1.6), 0.8, 2.6, 0.42, 2, 0.0, 1.0)
		8:
			# 25 mm HEI
			particle(true, pos + Vector3(0, 0.6, 0), Vector3.ZERO, 0.06, 0.8, 3.2, 1.5, 0)
			for k in 3:
				particle(true, pos, _rdir(0.6) * randf_range(10, 24), randf_range(0.25, 0.5), 0.3, 0.2, 1.2, 3, 1.0, 0.6)
			particle(false, pos + Vector3(0, 1.0, 0), Vector3(randf_range(-1, 1), 2.0, randf_range(-1, 1)), randf_range(1.5, 2.4), 1.4, 5.0, 0.48, 2, 0.0, 0.8)
			if randf() < 0.5:
				decal(pos, randf_range(1.6, 2.4), 0.7, 0.33, 7.0)
		9:
			_rod_impact(pos, own_ring)
		13:
			# directed energy / lightning: a white-hot spot, sparks, and a scorch that glows then cools
			particle(true, pos + Vector3(0, 0.8, 0), Vector3.ZERO, 0.1, 1.0, 5.0, 2.4, 0)
			for k in 4:
				particle(true, pos, _rdir(0.8) * randf_range(10, 28), randf_range(0.3, 0.7), 0.35, 0.2, 1.6, 3, 1.0, 0.6)
			particle(true, pos + Vector3.UP, Vector3.UP * 2.0, 0.6, 1.5, 3.0, 1.3, 1, 0.0, 1.0)
			if randf() < 0.6:
				decal(pos, randf_range(1.5, 2.6), 1.15, 0.36, 12.0)
		_:
			big_blast(pos, {2: 1.0, 3: 0.6, 4: 1.25, 5: 2.2, 6: 3.6, 11: 1.4, 12: 1.6}.get(power, 1.0), own_ring)
			if power == 11:
				# thermobaric: the fuel cloud burns for a moment after the blast
				for k in 6:
					particle(true, pos + Vector3(randf_range(-14, 14), randf_range(3, 12), randf_range(-14, 14)), Vector3.UP * randf_range(4, 9), randf_range(1.5, 2.5), 10.0, 26.0, 1.5, 1, -0.05, 0.8)


## The ground shock ring for a blast of `tnt` kg TNT equivalent. Radius follows Hopkinson
## cube-root scaling (R ∝ W^1/3), pinned so a 30 mm HEI round (60 g) makes the 13 m ring.
## Big rings expand faster, like a real shock front, and get a second, fainter overpressure ring.
func shock(pos: Vector3, tnt: float) -> void:
	if tnt <= 0.0:
		return
	var r := minf(33.0 * pow(tnt, 1.0 / 3.0), 2600.0)
	var life := r / (80.0 + 0.4 * r)
	var heat := clampf(1.15 + 0.08 * log(tnt + 1.0), 1.15, 1.8)
	particle(true, pos + Vector3(0, 0.4, 0), Vector3.ZERO, life, 0.5, r, heat, 4)
	if r > 40.0:
		particle(true, pos + Vector3(0, 0.6, 0), Vector3.ZERO, life * 1.5, 1.0, r * 1.4, heat * 0.7, 4)


## An airburst: the round goes off hob metres over the ground. A flash and a black puff left
## hanging in the air, fragments sleeting down across a wide circle, a ring of dust beneath and
## no crater.
func airburst(ground: Vector3, hob: float, sc: float, tnt: float) -> void:
	var p := ground + Vector3.UP * hob
	particle(true, p, Vector3.ZERO, 0.08 + 0.05 * sqrt(sc), 2.0 * sc, 9.0 * sc, 2.4, 0)
	particle(true, p, Vector3.UP * 2.0, 0.35 * sqrt(sc), 2.5 * sc, 6.0 * sc, 1.5, 1, 0.0, 1.5)
	particle(false, p, Vector3(randf_range(-1, 1), 1.0, randf_range(-1, 1)), randf_range(4.0, 7.0) * sqrt(sc), 3.0 * sc, 10.0 * sc, 0.62, 2, -0.01, 0.4)
	for k in int(10 + 14 * minf(sc, 3.0)):
		var d := Vector3(randf_range(-1, 1), randf_range(-1.6, -0.3), randf_range(-1, 1)).normalized()
		particle(true, p, d * randf_range(30, 70) * sqrt(sc), randf_range(0.3, 0.7), 0.4, 0.25, 1.3, 3, 1.0, 0.4)
	shock(ground, tnt * 0.5)
	if sc >= 1.0:
		decal(ground, 9.0 * sc, 0.6, 0.33, 15.0)


## A delay-fuzed round buries itself before it goes off: a muffled flash, a column of earth and
## smoke thrown straight up, a deep dark crater, and little of the blast getting out sideways.
## Into a building, it guts it: dust coughing out of every window.
func delay_burst(pos: Vector3, sc: float, tnt: float, structure: bool) -> void:
	particle(true, pos + Vector3.UP, Vector3.ZERO, 0.06 + 0.05 * sqrt(sc), 1.5 * sc, 5.0 * sc, 1.6, 0)
	for k in int(8 + 10 * minf(sc, 4.0)):
		var v := Vector3(randf_range(-0.35, 0.35), 1.0, randf_range(-0.35, 0.35)).normalized() * randf_range(18.0, 45.0) * sqrt(sc)
		particle(false, pos + Vector3.UP * 1.5, v, randf_range(3.0, 6.0) * sqrt(sc), 1.5 * sc, 7.0 * sc, 0.5, 2, 0.6, 0.6)
	for k in int(6 + 6 * minf(sc, 4.0)):
		particle(true, pos, Vector3(randf_range(-1, 1), randf_range(0.8, 1.6), randf_range(-1, 1)).normalized() * randf_range(20, 50) * sqrt(sc), randf_range(0.6, 1.4), 0.6, 0.4, 1.2, 3, 1.0, 0.3)
	if structure:
		for k in 10:
			particle(false, pos + Vector3(randf_range(-6, 6), randf_range(-4, 4), randf_range(-6, 6)) * sqrt(sc), Vector3(randf_range(-6, 6), randf_range(0, 4), randf_range(-6, 6)), randf_range(6.0, 10.0), 4.0 * sc, 14.0 * sc, 0.45, 2, 0.05, 0.4)
	shock(Vector3(pos.x, 0.0, pos.z), tnt * 0.25)
	decal(Vector3(pos.x, 0.0, pos.z), 8.0 * sc, 1.0, 0.45, 40.0 * sqrt(sc))


## Everything from the 105 up: one recipe scaled by blast size.
func big_blast(pos: Vector3, sc: float, ring := true) -> void:
	var many := clampf(sc, 0.6, 2.0)
	particle(true, pos + Vector3(0, 4, 0) * sc, Vector3.ZERO, 0.14 * sqrt(sc), 8.0 * sc, 38.0 * sc, 2.6, 0)
	if ring:
		particle(true, pos + Vector3(0, 0.5, 0), Vector3.ZERO, 0.45 * sqrt(sc), 2.0, 75.0 * sc, 1.4, 4)
	for k in int(7 * many):
		particle(true, pos + Vector3(randf_range(-4, 4), randf_range(1, 6), randf_range(-4, 4)) * sc, _rdir(1.0) * randf_range(3, 9) * sqrt(sc), randf_range(0.8, 1.4) * sqrt(sc), 7.0 * sc, 20.0 * sc, 1.25, 1, -0.1, 1.2)
	for k in int(40 * many):
		particle(true, pos, _rdir(0.8) * randf_range(25, 75) * sqrt(sc), randf_range(1.0, 3.0), 0.7, 0.5, 1.5, 3, 1.0, 0.3)
	for k in int(10 * many):
		var off := Vector3(randf_range(-8, 8), randf_range(2, 10), randf_range(-8, 8)) * sc
		particle(false, pos + off, Vector3(randf_range(-2, 2), randf_range(3, 7), randf_range(-2, 2)) * sqrt(sc), randf_range(14.0, 24.0) * sqrt(sc), 10.0 * sc, 38.0 * sc, 0.62, 2, -0.03, 0.25)
	if sc > 2.0:
		# heavy bombs throw a dust skirt out along the ground
		for k in 36:
			var d := Vector3(cos(TAU * k / 36.0), 0.0, sin(TAU * k / 36.0))
			particle(false, pos + d * 6.0 * sc + Vector3.UP * 3.0, d * randf_range(60, 90) * sqrt(sc), randf_range(8.0, 14.0), 6.0 * sc, 22.0 * sc, 0.5, 2, 0.0, 1.4)
	decal(pos, 17.0 * sc, 0.85, 0.4, 45.0 * sqrt(sc))


## THOR: no explosive, just kinetic energy. A blinding flash and a crater-shaped ring of dust.
func _rod_impact(pos: Vector3, ring := true) -> void:
	particle(true, pos + Vector3.UP * 10.0, Vector3.ZERO, 0.2, 20.0, 160.0, 3.2, 0)
	if ring:
		particle(true, pos + Vector3.UP, Vector3.ZERO, 0.7, 4.0, 320.0, 1.6, 4)
	particle(true, pos + Vector3.UP * 30.0, Vector3.UP * 40.0, 1.2, 10.0, 60.0, 1.8, 1, 0.0, 1.0)
	for k in 70:
		particle(true, pos, _rdir(1.5) * randf_range(60, 160), randf_range(2.0, 4.5), 1.4, 1.0, 1.6, 3, 1.0, 0.25)
	for k in 48:
		var d := Vector3(cos(TAU * k / 48.0), 0.0, sin(TAU * k / 48.0))
		particle(false, pos + d * 15.0 + Vector3.UP * 4.0, d * randf_range(90, 150) + Vector3.UP * randf_range(5, 30), randf_range(12.0, 20.0), 12.0, 50.0, 0.52, 2, 0.0, 1.1)
	for k in 10:
		particle(false, pos + Vector3(randf_range(-20, 20), randf_range(10, 60), randf_range(-20, 20)), Vector3.UP * randf_range(10, 25), randf_range(20.0, 30.0), 30.0, 80.0, 0.6, 2, -0.02, 0.2)
	decal(pos, 70.0, 1.1, 0.45, 90.0)


## A nuclear detonation seen through a thermal imager: the flash, a fireball that rises and
## lingers, a ground shock ring running out at the speed of sound, a dust skirt,
## a stem and a mushroom cap climbing for half a minute, and a scorched, glowing scar.
## The Atomic Gatling's round: the whole nuclear recipe in miniature, cheap enough for four a second.
func mini_nuke(pos: Vector3) -> void:
	particle(true, pos + Vector3.UP * 8.0, Vector3.ZERO, 0.25, 25.0, 120.0, 3.0, 0)
	particle(true, pos + Vector3.UP, Vector3.ZERO, 0.9, 6.0, 260.0, 1.5, 4)
	for k in 10:
		var d := Vector3(cos(TAU * k / 10.0), 0.0, sin(TAU * k / 10.0))
		particle(false, pos + d * 8.0 + Vector3.UP * 3.0, d * randf_range(60, 90) + Vector3.UP * 4.0, randf_range(5.0, 8.0), 8.0, 30.0, 0.55, 2, 0.0, 0.9)
	# a little stem and cap
	for k in 6:
		particle(false, pos + Vector3(randf_range(-5, 5), k * 5.0, randf_range(-5, 5)), Vector3.UP * randf_range(8, 14), randf_range(10.0, 16.0), 12.0, 34.0, 0.7, 2, -0.04, 0.05)
	for k in 6:
		var d := Vector3(cos(TAU * k / 6.0), 0.0, sin(TAU * k / 6.0))
		particle(true, pos + Vector3.UP * 40.0 + d * 10.0, Vector3.UP * 8.0 + d * randf_range(4, 8), randf_range(8.0, 12.0), 16.0, 48.0, 1.5, 1, -0.02, 0.05)
	for k in 12:
		particle(true, pos, _rdir(1.0) * randf_range(40, 120), randf_range(1.5, 3.0), 1.5, 1.0, 1.8, 3, 1.0, 0.15)
	decal(pos, 70.0, 1.3, 0.55, 90.0)


func nuke(pos: Vector3, s := 1.0, mushroom := true) -> void:
	var n := clampf(s, 0.35, 1.0)
	particle(true, pos + Vector3.UP * 60.0 * s, Vector3.ZERO, 0.5 * sqrt(s), 200.0 * s, 1100.0 * s, 4.0, 0)
	particle(true, pos + Vector3.UP * 2.0, Vector3.ZERO, 2.6 * s, 10.0, 1900.0 * s, 1.7, 4)
	particle(true, pos + Vector3.UP * 2.0, Vector3.ZERO, 4.0 * s, 10.0, 2600.0 * s, 0.9, 4)
	for k in int(8 * n):
		var o := Vector3(randf_range(-25, 25), randf_range(40, 90), randf_range(-25, 25)) * s
		particle(true, pos + o, Vector3.UP * randf_range(10, 16) * sqrt(s), randf_range(18.0, 28.0) * sqrt(s), 90.0 * s, 230.0 * s, 2.6, 1, -0.012, 0.04)
	# dust skirt pushed out by the shock front
	for k in int(96 * n):
		var d := Vector3(cos(TAU * k / (96.0 * n)), 0.0, sin(TAU * k / (96.0 * n)))
		particle(false, pos + d * 40.0 * s + Vector3.UP * 8.0, d * randf_range(280, 360) * sqrt(s) + Vector3.UP * randf_range(0, 20), randf_range(20.0, 32.0) * sqrt(s), 30.0 * s, 110.0 * s, 0.55, 2, 0.0, 0.9)
	if mushroom:
		# stem
		for k in int(34 * n):
			particle(false, pos + Vector3(randf_range(-30, 30) * s, k * 14.0 * s, randf_range(-30, 30) * s), Vector3.UP * randf_range(18, 32) * sqrt(s), randf_range(35.0, 50.0) * sqrt(s), 45.0 * s, 110.0 * s, 0.7, 2, -0.04, 0.05)
		# cap: hot core and the rolling toroid
		for k in int(26 * n):
			var a := TAU * k / (26.0 * n)
			var d := Vector3(cos(a), 0.0, sin(a))
			particle(true, pos + Vector3.UP * 160.0 * s + d * 40.0 * s, (Vector3.UP * 26.0 + d * randf_range(10, 25)) * sqrt(s), randf_range(25.0, 35.0) * sqrt(s), 60.0 * s, 170.0 * s, 1.5, 1, -0.02, 0.05)
			particle(false, pos + Vector3.UP * 150.0 * s + d * 70.0 * s, (Vector3.UP * 24.0 + d * randf_range(15, 40)) * sqrt(s), randf_range(40.0, 55.0) * sqrt(s), 80.0 * s, 260.0 * s, 0.78, 2, -0.035, 0.05)
	else:
		# enhanced radiation: little blast, a fading glow dome
		particle(true, pos + Vector3.UP * 30.0, Vector3.ZERO, 9.0, 300.0, 700.0, 0.7, 1, 0.0, 0.0)
	# hot debris raining out
	for k in int(120 * n):
		particle(true, pos, _rdir(1.0) * randf_range(80, 260) * sqrt(s), randf_range(3.0, 8.0), 3.0, 2.0, 1.8, 3, 1.0, 0.15)
	# the scar: ground that will glow for minutes, and fires across the blocks
	decal(pos, 330.0 * s, 1.4, 0.6, 240.0)
	decal(pos, 900.0 * s, 0.7, 0.33, 120.0)
	for k in int(70 * n):
		var p := pos + Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)).normalized() * randf_range(60, 420) * s
		particle(true, p + Vector3.UP * 2.0, Vector3.UP * 2.0, randf_range(60.0, 140.0), randf_range(4.0, 9.0), randf_range(5.0, 12.0), 1.4, 1, 0.0, 0.5)