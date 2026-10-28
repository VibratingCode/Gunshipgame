extends Node3D
## The horde: tens of thousands of zombies with analytic movement.
##
## Each zombie walks a straight radial path toward the stadium with a lateral wobble.
## Its position is a pure function of time, so the GPU animates it in zombie.gdshader
## and the CPU only evaluates the same formula when it needs to (hit tests and a
## spatial grid that is refreshed a slice at a time).

const MeshKit = preload("res://scripts/mesh_kit.gd")

const CAP := 80000
const CORPSE_CAP := 34000
const CELL := 8.0
const GRID_HALF := 3400.0
const GN := 850
const SLACK := 3.0
# coarse density map for the radar / tactical map: 100 m bins over the whole AO
const DBIN := 100.0
const DN := 68

var main
var fx
var time := 0.0

# per-zombie state (struct-of-arrays)
var z_sx := PackedFloat32Array()
var z_sz := PackedFloat32Array()
var z_dx := PackedFloat32Array()
var z_dz := PackedFloat32Array()
var z_t0 := PackedFloat32Array()
var z_v := PackedFloat32Array()
var z_L := PackedFloat32Array()
var z_seed := PackedFloat32Array()
var z_hp := PackedFloat32Array()
var z_scale := PackedFloat32Array()
var z_alive := PackedByteArray()
var z_arrived := PackedByteArray()
var z_type := PackedByteArray()
var z_cell := PackedInt32Array()
var z_next := PackedInt32Array()
var z_prev := PackedInt32Array()
var head := PackedInt32Array()
var free_list := PackedInt32Array()
var high := 0
var cursor := 0

var alive_count := 0
var arrived_count := 0
var arrived_weight := 0.0
var arrived_list := PackedInt32Array()
var sector_w := PackedFloat32Array()
var defender_kills := 0

var density := PackedInt32Array()
var dens_build := PackedInt32Array()
var nearest_r := INF
var nearest_eta := INF
var near_build := INF
var eta_build := INF
# infected inside 700 m of the refuge (and everything at the wall): what the passive defences shoot at
var threats := PackedInt32Array()
var threat_build := PackedInt32Array()

var mm: MultiMesh
var corpse_mm: MultiMesh
var corpse_i := 0
var corpse_n := 0
var survivors_mm: MultiMesh
var defender_spots: Array[Vector3] = []
var def_acc := 0.0
var garrison := 1.0
# "Volatile Infected": some kills detonate; the arsenal turns these into blasts each frame
var chain_p := 0.0
var chain_events: Array[Vector3] = []
var dead_basis := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
var last_spawned := -1
# set while fire is doing the killing: those bodies are left charred and smouldering
var burn_kills := false
# the graphics setting: how many may be alive at once (never more than CAP)
var max_alive := CAP
# dev farm: dummies that stand still to be shot (speed 0, never arrive, never block a wave clear)
const FARM := 4
var farm_alive := 0

# ---------------------------------------------------------------- bosses
# Rare giants on the same analytic walk: huge, slow, hundreds of hit points, and a trick each.
const BOSS := 3
# small arms barely scratch them: this much is shaved off every hit (never below 15% of it)
const BOSS_ARMOR := 1.5
const BOSSES := [
	{"id": "behemoth", "name": "BEHEMOTH", "scale": 7.0, "hp": 260.0, "speed": 0.55, "weight": 150.0, "bounty": 2500, "min_wave": 3, "odds": 1.0,
		"brief": "A walking wall of meat. It just keeps coming."},
	{"id": "brood", "name": "BROODMOTHER", "scale": 6.0, "hp": 200.0, "speed": 0.5, "weight": 120.0, "bounty": 3000, "min_wave": 4, "odds": 1.0,
		"brood": 30, "brood_t": 8.0, "brief": "It sheds fresh infected as it walks. Kill it early."},
	{"id": "bloat", "name": "BLOAT KING", "scale": 6.5, "hp": 160.0, "speed": 0.75, "weight": 150.0, "bounty": 2500, "min_wave": 5, "odds": 0.9,
		"burst": 70.0, "brief": "Full of gas. Pop it out there and it takes its friends with it. Let it reach the wall and it takes the wall."},
	{"id": "colossus", "name": "THE COLOSSUS", "scale": 15.0, "hp": 1400.0, "speed": 0.4, "weight": 500.0, "bounty": 15000, "min_wave": 9, "odds": 0.35,
		"brief": "Thirty metres tall. Bring the big stuff."},
	# never scheduled as a boss: the Golden Pinata wave event sends it in
	{"id": "pinata", "name": "GOLDEN PINATA", "scale": 1.25, "hp": 4.0, "speed": 3.2, "weight": 1.0, "bounty": 5000, "min_wave": 999, "odds": 0.0,
		"escape": true, "pinata": true, "brief": "A golden infected sprinting for the wall, stuffed with requisition. Pop it before it gets there."},
]
var bosses: Array = []        # {i, def, max_hp, next_brood, pos}
var boss_events: Array = []   # {type: dead | breach | brood, def, pos}
var _breaching := -1


func _ready() -> void:
	z_sx.resize(CAP)
	z_sz.resize(CAP)
	z_dx.resize(CAP)
	z_dz.resize(CAP)
	z_t0.resize(CAP)
	z_v.resize(CAP)
	z_L.resize(CAP)
	z_seed.resize(CAP)
	z_hp.resize(CAP)
	z_scale.resize(CAP)
	z_alive.resize(CAP)
	z_arrived.resize(CAP)
	z_type.resize(CAP)
	z_cell.resize(CAP)
	z_next.resize(CAP)
	z_prev.resize(CAP)
	z_cell.fill(-1)
	head.resize(GN * GN)
	head.fill(-1)
	sector_w.resize(8)
	density.resize(DN * DN)
	dens_build.resize(DN * DN)

	mm = _make_mm(MeshKit.humanoid(true), "res://shaders/zombie.gdshader", CAP)
	corpse_mm = _make_mm(MeshKit.humanoid(false), "res://shaders/corpse.gdshader", CORPSE_CAP)


func _make_mm(mesh: Mesh, shader_path: String, cap: int) -> MultiMesh:
	var m := MultiMesh.new()
	m.transform_format = MultiMesh.TRANSFORM_3D
	m.use_custom_data = true
	# a fixed AABB stops the engine re-scanning every instance whenever one changes
	m.custom_aabb = AABB(Vector3(-4000, -50, -4000), Vector3(8000, 400, 8000))
	m.mesh = mesh
	m.instance_count = cap
	var buf := PackedFloat32Array()
	buf.resize(cap * 16)
	m.buffer = buf
	m.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = m
	var mat := ShaderMaterial.new()
	mat.shader = load(shader_path)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-4000, -50, -4000), Vector3(8000, 400, 8000))
	add_child(mi)
	return m


func setup_stadium(spots: Array, defenders: Array[Vector3]) -> void:
	defender_spots = defenders
	survivors_mm = _make_mm(MeshKit.humanoid(false), "res://shaders/survivor.gdshader", spots.size() + defenders.size())
	var i := 0
	for s in spots:
		var p: Vector3 = s[0]
		survivors_mm.set_instance_transform(i, Transform3D(Basis(), p))
		survivors_mm.set_instance_custom_data(i, Color(float(s[1]), randf_range(0.05, 0.25), randf(), randf_range(0.86, 0.98)))
		i += 1
	for p in defenders:
		survivors_mm.set_instance_transform(i, Transform3D(Basis(), p))
		survivors_mm.set_instance_custom_data(i, Color(0.6, 0.3, randf(), 0.95))
		i += 1
	survivors_mm.visible_instance_count = i


# ------------------------------------------------------------------ spawning
func spawn(x: float, z: float, speed: float, kind: int, arrive_r: float, s_over := 0.0, hp_over := 0.0) -> bool:
	if alive_count >= max_alive:
		return false
	var i: int
	if free_list.size() > 0:
		i = free_list[free_list.size() - 1]
		free_list.resize(free_list.size() - 1)
	elif high < CAP:
		i = high
		high += 1
	else:
		return false
	var r := sqrt(x * x + z * z)
	var dx := -x / r
	var dz := -z / r
	var s := randf_range(0.9, 1.08)
	var hp := 1.0
	if kind == 2:
		s = randf_range(1.55, 1.75)
		hp = 7.0
	if s_over > 0.0:
		s = s_over
		hp = hp_over
	last_spawned = i
	z_sx[i] = x
	z_sz[i] = z
	z_dx[i] = dx
	z_dz[i] = dz
	z_t0[i] = time
	z_v[i] = speed
	z_L[i] = maxf(r - arrive_r, 0.0)
	z_seed[i] = randf()
	z_hp[i] = hp
	z_scale[i] = s
	z_alive[i] = 1
	z_arrived[i] = 0
	z_type[i] = kind
	var b := Basis(Vector3(-dz, 0, dx) * s, Vector3(0, s, 0), Vector3(-dx, 0, -dz) * s)
	mm.set_instance_transform(i, Transform3D(b, Vector3(x, 0, z)))
	mm.set_instance_custom_data(i, Color(z_t0[i], z_v[i], z_L[i], z_seed[i]))
	var p := pos_of(i)
	_grid_insert(i, _cell_of(p.x, p.y))
	alive_count += 1
	if kind == FARM:
		farm_alive += 1
	return true


func pos_of(i: int) -> Vector2:
	return pos_at(i, time)


## Where zombie i will be at time tt. Movement is analytic, so prediction is exact:
## the fire-control computer uses this to lead a tracked target by the time of flight.
func pos_at(i: int, tt: float) -> Vector2:
	var d := minf(maxf(tt - z_t0[i], 0.0) * z_v[i], z_L[i])
	var sd := z_seed[i]
	var amp := 1.0 + fposmod(sd * 13.7, 1.0) * 2.5
	var lat := sin(d * 0.045 + sd * 6.2831853) * amp
	return Vector2(z_sx[i] + z_dx[i] * d - z_dz[i] * lat, z_sz[i] + z_dz[i] * d + z_dx[i] * lat)


# ---------------------------------------------------------------- the grid
func _cell_of(x: float, z: float) -> int:
	var cx := clampi(int((x + GRID_HALF) / CELL), 0, GN - 1)
	var cz := clampi(int((z + GRID_HALF) / CELL), 0, GN - 1)
	return cz * GN + cx


func _grid_insert(i: int, c: int) -> void:
	z_cell[i] = c
	z_prev[i] = -1
	var h := head[c]
	z_next[i] = h
	if h >= 0:
		z_prev[h] = i
	head[c] = i


func _grid_remove(i: int) -> void:
	var c := z_cell[i]
	if c < 0:
		return
	var p := z_prev[i]
	var n := z_next[i]
	if p >= 0:
		z_next[p] = n
	else:
		head[c] = n
	if n >= 0:
		z_prev[n] = p
	z_cell[i] = -1


static func sector_of(x: float, z: float) -> int:
	var bearing := fposmod(rad_to_deg(atan2(x, -z)), 360.0)
	return int(round(bearing / 45.0)) % 8


# ---------------------------------------------------------------- per frame
func update_sim(dt: float, wave: int) -> void:
	if mm.visible_instance_count != high:
		mm.visible_instance_count = high
	if corpse_mm.visible_instance_count != corpse_n:
		corpse_mm.visible_instance_count = corpse_n
	# Re-bucket a slice of the moving zombies each frame. Every walker is revisited about
	# every 20 frames; at human speeds (< 4 m/s) the grid is never more than ~1 m stale.
	# pos_of() is inlined here because this is the hottest loop in the game.
	if high > 0:
		# under time compression each frame covers more sim time, so refresh more of the grid
		var n := mini(high, maxi(600, int(high * clampf(dt * 3.0, 0.05, 1.0))))
		var t := time
		for k in n:
			if cursor >= high:
				cursor = 0
				# a full pass is done: publish the density map and nearest-contact figures
				var tmp := density
				density = dens_build
				dens_build = tmp
				dens_build.fill(0)
				nearest_r = near_build
				nearest_eta = eta_build
				near_build = INF
				eta_build = INF
				threats = threat_build
				threat_build = PackedInt32Array()
			var i := cursor
			cursor += 1
			if z_alive[i] == 0:
				continue
			if z_arrived[i] == 1:
				var ap := pos_of(i)
				dens_build[clampi(int((ap.y + GRID_HALF) / DBIN), 0, DN - 1) * DN + clampi(int((ap.x + GRID_HALF) / DBIN), 0, DN - 1)] += 1
				if threat_build.size() < 600:
					threat_build.append(i)
				continue
			var travel := (t - z_t0[i]) * z_v[i]
			var L := z_L[i]
			var d := clampf(travel, 0.0, L)
			var sd := z_seed[i]
			var lat := sin(d * 0.045 + sd * 6.2831853) * (1.0 + fposmod(sd * 13.7, 1.0) * 2.5)
			var dx := z_dx[i]
			var dz := z_dz[i]
			var px := z_sx[i] + dx * d - dz * lat
			var pz := z_sz[i] + dz * d + dx * lat
			var c := clampi(int((pz + GRID_HALF) / CELL), 0, GN - 1) * GN + clampi(int((px + GRID_HALF) / CELL), 0, GN - 1)
			if c != z_cell[i]:
				_grid_remove(i)
				_grid_insert(i, c)
			dens_build[clampi(int((pz + GRID_HALF) / DBIN), 0, DN - 1) * DN + clampi(int((px + GRID_HALF) / DBIN), 0, DN - 1)] += 1
			if z_type[i] == FARM:
				# farm dummies stand still: not a threat, so not the lead contact either
				continue
			var rr := sqrt(px * px + pz * pz)
			if rr < 700.0 and threat_build.size() < 600:
				threat_build.append(i)
			if rr < near_build:
				near_build = rr
			var eta := (L - travel) / maxf(z_v[i], 0.1)
			if eta < eta_build:
				eta_build = eta
			if travel >= L:
				z_arrived[i] = 1
				var w := _weight(i)
				arrived_count += 1
				arrived_weight += w
				sector_w[sector_of(px, pz)] += w
				arrived_list.append(i)
	_defenders(dt, wave)
	_radiation_pass()
	_update_shocks()
	_update_bosses()


## The garrison on the stadium rim shoots whatever reaches the wall first.
func _defenders(dt: float, wave: int) -> void:
	if defender_spots.is_empty():
		return
	def_acc += (2.5 + wave * 0.7) * garrison * dt
	while def_acc >= 1.0:
		def_acc -= 1.0
		var target := -1
		var tries := 0
		while arrived_list.size() > 0 and tries < 6:
			tries += 1
			var k := randi() % arrived_list.size()
			var i := arrived_list[k]
			arrived_list[k] = arrived_list[arrived_list.size() - 1]
			arrived_list.resize(arrived_list.size() - 1)
			if z_alive[i] == 1 and z_arrived[i] == 1:
				target = i
				break
		if target < 0 and randf() < 0.5:
			var a := randf() * TAU
			target = nearest(Vector3(cos(a), 0, sin(a)) * randf_range(70.0, 170.0), 10.0)
		if target < 0:
			continue
		var p := pos_of(target)
		var sh := defender_spots[int(round(fposmod(atan2(p.y, p.x), TAU) / TAU * defender_spots.size())) % defender_spots.size()]
		var tp := Vector3(p.x, 1.2, p.y)
		var tf := sh.distance_to(tp) / 850.0
		fx.tracer(sh, (tp - sh) / tf, tf, 1.1, 0.06, 0.03)
		fx.particle(true, sh, Vector3.ZERO, 0.06, 0.5, 1.3, 1.6, 0)
		if z_type[target] == BOSS:
			# rifles only chip at a boss
			z_hp[target] -= 0.6
			if z_hp[target] > 0.0:
				continue
			kill(target, p, sh, 0.0)
			defender_kills += 1
		elif randf() < 0.8:
			kill(target, p, sh, 0.0)
			defender_kills += 1


func nearest(pos: Vector3, radius: float) -> int:
	var best := -1
	var bd := radius * radius
	var R := radius + SLACK
	var cx0 := clampi(int((pos.x - R + GRID_HALF) / CELL), 0, GN - 1)
	var cx1 := clampi(int((pos.x + R + GRID_HALF) / CELL), 0, GN - 1)
	var cz0 := clampi(int((pos.z - R + GRID_HALF) / CELL), 0, GN - 1)
	var cz1 := clampi(int((pos.z + R + GRID_HALF) / CELL), 0, GN - 1)
	for cz in range(cz0, cz1 + 1):
		for cx in range(cx0, cx1 + 1):
			var i := head[cz * GN + cx]
			while i >= 0:
				var p := pos_of(i)
				var d := (p.x - pos.x) * (p.x - pos.x) + (p.y - pos.z) * (p.y - pos.z)
				if d < bd:
					bd = d
					best = i
				i = z_next[i]
	return best


## High-explosive effect: certain kill inside r_kill, probabilistic fragment wounds out to r_frag.
## Returns the number killed. r_in / r_out restrict it to an annulus (an expanding shock front).
func blast(center: Vector3, r_kill: float, r_frag: float, dmg: float, fling: float, r_in := 0.0, r_out := INF, spare_boss := false) -> int:
	var kills := 0
	var rmax := minf(r_frag, r_out)
	var R := rmax + SLACK
	var cx0 := clampi(int((center.x - R + GRID_HALF) / CELL), 0, GN - 1)
	var cx1 := clampi(int((center.x + R + GRID_HALF) / CELL), 0, GN - 1)
	var cz0 := clampi(int((center.z - R + GRID_HALF) / CELL), 0, GN - 1)
	var cz1 := clampi(int((center.z + R + GRID_HALF) / CELL), 0, GN - 1)
	var dy := maxf(center.y - 1.0, 0.0)
	var dy2 := dy * dy
	var rf2 := rmax * rmax
	var ri2 := r_in * r_in
	var inner := maxf(r_in - SLACK - CELL * 0.75, 0.0)
	for cz in range(cz0, cz1 + 1):
		for cx in range(cx0, cx1 + 1):
			if inner > 0.0:
				# skip cells wholly inside the part of the ring already swept
				var ccx := (cx + 0.5) * CELL - GRID_HALF - center.x
				var ccz := (cz + 0.5) * CELL - GRID_HALF - center.z
				if ccx * ccx + ccz * ccz < inner * inner:
					continue
			var i := head[cz * GN + cx]
			while i >= 0:
				var nxt := z_next[i]
				var p := pos_of(i)
				var ex := p.x - center.x
				var ez := p.y - center.z
				var d2 := ex * ex + ez * ez + dy2
				if d2 < rf2 and d2 >= ri2 and not (spare_boss and z_type[i] == BOSS):
					var d := sqrt(d2)
					var f := 1.0
					if d > r_kill:
						f = 1.0 - (d - r_kill) / (r_frag - r_kill)
						if randf() > f:
							i = nxt
							continue
					var hit := dmg * f * randf_range(0.6, 1.4)
					if z_type[i] == BOSS:
						hit = maxf(hit - BOSS_ARMOR, hit * 0.15)
					z_hp[i] -= hit
					if z_hp[i] <= 0.0:
						var hd := sqrt(ex * ex + ez * ez) + 0.5
						var vel := Vector3(ex / hd, 0.0, ez / hd) * fling * f * randf_range(0.6, 1.2)
						vel.y = fling * f * randf_range(0.4, 1.0)
						_kill_with(i, p, vel)
						kills += 1
				i = nxt
	return kills


## Deterministic damage to everything inside a capsule (segment a-b, radius r): beams,
## railgun trenches, napalm strips. prob < 1 lets some survive (flechettes). Returns kills.
func line_blast(a: Vector3, b: Vector3, r: float, dmg: float, fling: float, prob := 1.0) -> int:
	var kills := 0
	var R := r + SLACK
	var cx0 := clampi(int((minf(a.x, b.x) - R + GRID_HALF) / CELL), 0, GN - 1)
	var cx1 := clampi(int((maxf(a.x, b.x) + R + GRID_HALF) / CELL), 0, GN - 1)
	var cz0 := clampi(int((minf(a.z, b.z) - R + GRID_HALF) / CELL), 0, GN - 1)
	var cz1 := clampi(int((maxf(a.z, b.z) + R + GRID_HALF) / CELL), 0, GN - 1)
	var a2 := Vector2(a.x, a.z)
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var l2 := ab.length_squared()
	var r2 := r * r
	for cz in range(cz0, cz1 + 1):
		for cx in range(cx0, cx1 + 1):
			var i := head[cz * GN + cx]
			while i >= 0:
				var nxt := z_next[i]
				var p := pos_of(i)
				var t := 0.0 if l2 < 0.001 else clampf((p - a2).dot(ab) / l2, 0.0, 1.0)
				var q := a2 + ab * t
				var off := p - q
				if off.length_squared() < r2 and (prob >= 1.0 or randf() < prob):
					var hit := dmg * randf_range(0.8, 1.2)
					if z_type[i] == BOSS:
						hit = maxf(hit - BOSS_ARMOR * 0.25, hit * 0.15)
					z_hp[i] -= hit
					if z_hp[i] <= 0.0:
						# a negative fling pulls bodies inward (the singularity) but still lofts them
						var away := off.normalized() if off.length_squared() > 0.01 else Vector2.from_angle(randf() * TAU)
						_kill_with(i, p, Vector3(away.x, 0.0, away.y) * fling * randf_range(0.5, 1.2) + Vector3.UP * absf(fling) * randf_range(0.3, 0.8))
						kills += 1
				i = nxt
	return kills


## How many zombies are within r of pos: lets drones and the wingman find the thickest crowd.
func count_near(pos: Vector3, r: float, skip_farm := false) -> int:
	var n := 0
	var R := r + SLACK
	var cx0 := clampi(int((pos.x - R + GRID_HALF) / CELL), 0, GN - 1)
	var cx1 := clampi(int((pos.x + R + GRID_HALF) / CELL), 0, GN - 1)
	var cz0 := clampi(int((pos.z - R + GRID_HALF) / CELL), 0, GN - 1)
	var cz1 := clampi(int((pos.z + R + GRID_HALF) / CELL), 0, GN - 1)
	for cz in range(cz0, cz1 + 1):
		for cx in range(cx0, cx1 + 1):
			var i := head[cz * GN + cx]
			while i >= 0:
				if not skip_farm or z_type[i] != FARM:
					n += 1
				i = z_next[i]
	return n


## A random living zombie's position (or Vector3.INF if the map is clear).
func random_alive_pos() -> Vector3:
	if alive_count <= 0 or high <= 0:
		return Vector3.INF
	for k in 24:
		var i := randi() % high
		if z_alive[i] == 1:
			var p := pos_of(i)
			return Vector3(p.x, 0.0, p.y)
	return Vector3.INF


# ---------------------------------------------------------------- radiation
var rad_center := Vector3.ZERO
var rad_r := 0.0
var rad_until := -1.0
var rad_p := 0.0
var rad_cursor := 0
var rad_kills := 0


## Enhanced-radiation weapon: the infected keep walking for a few seconds, then drop.
## Every pass, each zombie inside the radius dies with a probability that falls off with range.
func irradiate(center: Vector3, r: float, duration: float, p_per_pass: float) -> void:
	rad_center = center
	rad_r = r
	rad_until = time + duration
	rad_p = p_per_pass


func _radiation_pass() -> void:
	if time > rad_until or high <= 0:
		return
	var n := mini(high, maxi(1500, high / 18))
	for k in n:
		if rad_cursor >= high:
			rad_cursor = 0
		var i := rad_cursor
		rad_cursor += 1
		if z_alive[i] == 0:
			continue
		var p := pos_of(i)
		var d := Vector2(p.x - rad_center.x, p.y - rad_center.z).length()
		if d >= rad_r:
			continue
		var f := pow(1.0 - d / rad_r, 0.6) * (2.5 if d < rad_r * 0.35 else 1.0)
		if z_type[i] == BOSS:
			# a boss soaks radiation as damage instead of simply dropping
			z_hp[i] -= 8.0 * f
			if z_hp[i] > 0.0:
				continue
			_kill_with(i, p, Vector3.ZERO)
			rad_kills += 1
		elif randf() < rad_p * f:
			_kill_with(i, p, Vector3.ZERO)
			rad_kills += 1


# ---------------------------------------------------------------- nuclear shock fronts
# At detonation every zombie inside the outer radius is sorted into 25 m bands, once. The front
# then sweeps out at the speed of sound and knocks each band flat as it arrives: one pass over
# the horde however big the blast, instead of a fresh area search for every ring.
const SHOCK_STEP := 25.0
var shock_fronts: Array = []
var shock_kills: Array = []   # [kills, detonation point, final toll or 0] since the last take_shock_kills()


## Inside r_kill nothing survives; between r_kill and r_frag the odds of living rise toward the
## edge. Bosses take boss_dmg (falling off with range) instead of simply dropping.
func nuclear_shock(center: Vector3, r_kill: float, r_frag: float, fling: float, boss_dmg: float, speed := 340.0) -> void:
	var n_bands := int(ceil(r_frag / SHOCK_STEP)) + 1
	var bands: Array = []
	for k in n_bands:
		bands.append([])
	var rf2 := r_frag * r_frag
	var span := maxf(r_frag - r_kill, 1.0)
	var t := time
	for i in high:
		if z_alive[i] == 0:
			continue
		# pos_of() inlined: this runs over the whole horde in one frame
		var d := clampf((t - z_t0[i]) * z_v[i], 0.0, z_L[i])
		var sd := z_seed[i]
		var lat := sin(d * 0.045 + sd * 6.2831853) * (1.0 + fposmod(sd * 13.7, 1.0) * 2.5)
		var ex := z_sx[i] + z_dx[i] * d - z_dz[i] * lat - center.x
		var ez := z_sz[i] + z_dz[i] * d + z_dx[i] * lat - center.z
		var d2 := ex * ex + ez * ez
		if d2 >= rf2:
			continue
		var r := sqrt(d2)
		if r > r_kill and z_type[i] != BOSS and randf() > sqrt(1.0 - (r - r_kill) / span):
			continue
		bands[int(r / SHOCK_STEP)].append(i)
	shock_fronts.append({"c": center, "t0": t, "speed": speed, "next": 0, "bands": bands,
		"r_frag": r_frag, "fling": fling, "boss_dmg": boss_dmg})


func _update_shocks() -> void:
	for k in range(shock_fronts.size() - 1, -1, -1):
		var f: Dictionary = shock_fronts[k]
		var c: Vector3 = f["c"]
		var reach := (time - float(f["t0"])) * float(f["speed"])
		var bands: Array = f["bands"]
		var rf: float = f["r_frag"]
		var fling: float = f["fling"]
		var kills := 0
		while int(f["next"]) < bands.size() and int(f["next"]) * SHOCK_STEP <= reach:
			for iv in bands[int(f["next"])]:
				var i: int = iv
				if z_alive[i] == 0:
					continue
				var p := pos_of(i)
				var e := Vector2(p.x - c.x, p.y - c.z)
				var r := e.length()
				var fall := clampf(1.0 - r / rf, 0.0, 1.0)
				if z_type[i] == BOSS:
					z_hp[i] -= float(f["boss_dmg"]) * (0.3 + 0.7 * fall)
					if z_hp[i] > 0.0:
						continue
				var out := e / (r + 0.5)
				var push := fling * (0.35 + 0.65 * fall) * randf_range(0.6, 1.2)
				_kill_with(i, p, Vector3(out.x * push, push * randf_range(0.4, 0.9), out.y * push))
				kills += 1
			f["next"] = int(f["next"]) + 1
		f["total"] = int(f.get("total", 0)) + kills
		if kills > 0:
			shock_kills.append([kills, c, 0])
		if int(f["next"]) >= bands.size():
			# the front has passed its last band: report the whole toll once
			shock_kills.append([0, c, int(f["total"])])
			shock_fronts.remove_at(k)


## Kills by shock fronts since the last call, as [count, detonation point] pairs.
func take_shock_kills() -> Array:
	var out := shock_kills
	shock_kills = []
	return out


func take_rad_kills() -> int:
	var k := rad_kills
	rad_kills = 0
	return k


func kill(i: int, p: Vector2, from: Vector3, fling: float) -> void:
	var dir := Vector3(p.x - from.x, 0.0, p.y - from.z).normalized()
	_kill_with(i, p, dir * fling + Vector3(0, fling * 0.5, 0))


func _kill_with(i: int, p: Vector2, vel: Vector3) -> void:
	if z_alive[i] == 0:
		return
	_grid_remove(i)
	z_alive[i] = 0
	if z_arrived[i] == 1:
		var w := _weight(i)
		arrived_count -= 1
		arrived_weight -= w
		var sec := sector_of(p.x, p.y)
		sector_w[sec] = maxf(0.0, sector_w[sec] - w)
	if z_type[i] == BOSS:
		_boss_down(i, p)
	elif z_type[i] == FARM:
		farm_alive -= 1
	z_arrived[i] = 0
	alive_count -= 1
	mm.set_instance_transform(i, Transform3D(dead_basis, Vector3.ZERO))
	free_list.append(i)
	if chain_p > 0.0 and chain_events.size() < 48 and randf() < chain_p:
		chain_events.append(Vector3(p.x, 0.0, p.y))

	var s := z_scale[i]
	var b := Basis(Vector3.UP, randf() * TAU) * Basis(Vector3.RIGHT, -PI * 0.5 if randf() < 0.5 else PI * 0.5)
	corpse_mm.set_instance_transform(corpse_i, Transform3D(b.scaled(Vector3(s, s, s)), Vector3(p.x, 0.14 * s, p.y)))
	corpse_mm.set_instance_custom_data(corpse_i, Color(time + (100000.0 if burn_kills else 0.0), vel.x, vel.y, vel.z))
	corpse_i = (corpse_i + 1) % CORPSE_CAP
	if corpse_n < CORPSE_CAP:
		corpse_n += 1
	if randf() < 0.3:
		fx.decal(Vector3(p.x, 0.0, p.y), randf_range(1.0, 2.4), 0.62, 0.29, 25.0)


## Remove every farm dummy without a trace: no corpse, no kill, no requisition.
func clear_farm() -> void:
	for i in high:
		if z_alive[i] == 1 and z_type[i] == FARM:
			_remove(i)
	farm_alive = 0


## Take zombie i off the map without a corpse or a kill (it escaped, or was a farm dummy).
func _remove(i: int) -> void:
	if z_alive[i] == 0:
		return
	_grid_remove(i)
	if z_arrived[i] == 1:
		var w := _weight(i)
		var p := pos_of(i)
		var sec := sector_of(p.x, p.y)
		arrived_count -= 1
		arrived_weight = maxf(0.0, arrived_weight - w)
		sector_w[sec] = maxf(0.0, sector_w[sec] - w)
		z_arrived[i] = 0
	if z_type[i] == FARM:
		farm_alive -= 1
	z_alive[i] = 0
	alive_count -= 1
	mm.set_instance_transform(i, Transform3D(dead_basis, Vector3.ZERO))
	free_list.append(i)


## How hard a zombie at the wall hits the refuge.
func _weight(i: int) -> float:
	if z_type[i] == 2:
		return 4.0
	if z_type[i] == BOSS:
		for b in bosses:
			if int(b["i"]) == i:
				return float(b["def"]["weight"])
		return 100.0
	return 1.0


# ---------------------------------------------------------------- bosses
## A boss joins the horde at (x, z). Returns its zombie index, or -1 if the horde is full.
func spawn_boss(def: Dictionary, x: float, z: float, arrive_r: float, hp: float) -> int:
	if not spawn(x, z, float(def["speed"]), BOSS, arrive_r, float(def["scale"]), hp):
		return -1
	var i := last_spawned
	bosses.append({"i": i, "def": def, "max_hp": hp, "next_brood": time + float(def.get("brood_t", 0.0)), "pos": Vector3(x, 0.0, z)})
	return i


func _update_bosses() -> void:
	for k in range(bosses.size() - 1, -1, -1):
		var b: Dictionary = bosses[k]
		var i: int = b["i"]
		if z_alive[i] == 0 or z_type[i] != BOSS:
			bosses.remove_at(k)
			continue
		var def: Dictionary = b["def"]
		var p := pos_of(i)
		b["pos"] = Vector3(p.x, 0.0, p.y)
		# the Broodmother sheds a new clutch every few seconds while she walks
		if def.has("brood") and z_arrived[i] == 0 and time >= float(b["next_brood"]):
			b["next_brood"] = time + float(def["brood_t"])
			var ar: Vector2 = main.arrive
			for j in int(def["brood"]):
				var off := Vector2.from_angle(randf() * TAU) * randf_range(5.0, 18.0)
				spawn(p.x + off.x, p.y + off.y, randf_range(1.0, 1.6), 0, randf_range(ar.x, ar.y))
			boss_events.append({"type": "brood", "def": def, "pos": b["pos"]})
		# the Bloat King bursts the moment it reaches the wall
		if def.has("burst") and z_arrived[i] == 1:
			_breaching = i
			_kill_with(i, p, Vector3.ZERO)
			_breaching = -1
		# the pinata just gets away, and takes its requisition with it
		elif def.has("escape") and z_arrived[i] == 1:
			boss_events.append({"type": "escaped", "def": def, "pos": b["pos"]})
			_remove(i)
			bosses.remove_at(k)


func _boss_down(i: int, p: Vector2) -> void:
	for k in bosses.size():
		var b: Dictionary = bosses[k]
		if int(b["i"]) == i:
			bosses.remove_at(k)
			boss_events.append({"type": "breach" if i == _breaching else "dead", "def": b["def"], "pos": Vector3(p.x, 0.0, p.y)})
			return


## Extra damage to any boss whose body is within r of center: a penetrating round going off
## inside it. Returns how many it killed.
func boss_hit(center: Vector3, r: float, dmg: float) -> int:
	if dmg <= 0.0:
		return 0
	var dead := 0
	for b in bosses.duplicate():
		var i: int = b["i"]
		if z_alive[i] == 0:
			continue
		var p := pos_of(i)
		if Vector2(p.x - center.x, p.y - center.z).length() < r + z_scale[i] * 0.6:
			z_hp[i] -= dmg
			if z_hp[i] <= 0.0:
				_kill_with(i, p, Vector3.UP * 8.0)
				dead += 1
	return dead


## 0-1 health of a boss record.
func boss_hp(b: Dictionary) -> float:
	return clampf(z_hp[int(b["i"])] / maxf(float(b["max_hp"]), 1.0), 0.0, 1.0)


# ---------------------------------------------------------------- the Chrono Cannon
## Everything within r of center is thrown `back` metres further out along its own path,
## as though it had never walked that far. Returns how many were sent back.
func rewind(center: Vector3, r: float, back: float) -> int:
	var hit := PackedInt32Array()
	var R := r + SLACK
	var cx0 := clampi(int((center.x - R + GRID_HALF) / CELL), 0, GN - 1)
	var cx1 := clampi(int((center.x + R + GRID_HALF) / CELL), 0, GN - 1)
	var cz0 := clampi(int((center.z - R + GRID_HALF) / CELL), 0, GN - 1)
	var cz1 := clampi(int((center.z + R + GRID_HALF) / CELL), 0, GN - 1)
	for cz in range(cz0, cz1 + 1):
		for cx in range(cx0, cx1 + 1):
			var i := head[cz * GN + cx]
			while i >= 0:
				var p := pos_of(i)
				if Vector2(p.x - center.x, p.y - center.z).length() < r:
					hit.append(i)
				i = z_next[i]
	for i in hit:
		var p := pos_of(i)
		var rr := maxf(p.length(), 1.0)
		var nr := minf(rr + back, GRID_HALF - 150.0)
		_relocate(i, p.x / rr * nr, p.y / rr * nr)
	return hit.size()


## The outer edge of a shock wave: everything between r_in and r_out is thrown `dist` metres
## outward from the blast and gets up and walks on from there. Bosses are too heavy to move.
func shove(center: Vector3, r_in: float, r_out: float, dist: float) -> void:
	var hit := PackedInt32Array()
	var R := r_out + SLACK
	var cx0 := clampi(int((center.x - R + GRID_HALF) / CELL), 0, GN - 1)
	var cx1 := clampi(int((center.x + R + GRID_HALF) / CELL), 0, GN - 1)
	var cz0 := clampi(int((center.z - R + GRID_HALF) / CELL), 0, GN - 1)
	var cz1 := clampi(int((center.z + R + GRID_HALF) / CELL), 0, GN - 1)
	for cz in range(cz0, cz1 + 1):
		for cx in range(cx0, cx1 + 1):
			var i := head[cz * GN + cx]
			while i >= 0:
				if z_type[i] != BOSS and z_type[i] != FARM:
					var p := pos_of(i)
					var d := Vector2(p.x - center.x, p.y - center.z).length()
					if d >= r_in and d < r_out:
						hit.append(i)
				i = z_next[i]
	for i in hit:
		var p := pos_of(i)
		var away := Vector2(p.x - center.x, p.y - center.z)
		away = away.normalized() if away.length_squared() > 0.01 else Vector2.from_angle(randf() * TAU)
		var np := p + away * dist * randf_range(0.7, 1.1)
		if np.length() > 1.0 and np.length() < GRID_HALF - 150.0:
			_relocate(i, np.x, np.y)


## Start zombie i walking again from (x, z), keeping its kind, health, speed and stopping distance.
func _relocate(i: int, x: float, z: float) -> void:
	var arrive_r := clampf(sqrt(z_sx[i] * z_sx[i] + z_sz[i] * z_sz[i]) - z_L[i], 30.0, 400.0)
	_grid_remove(i)
	if z_arrived[i] == 1:
		var w := _weight(i)
		arrived_count -= 1
		arrived_weight = maxf(0.0, arrived_weight - w)
		var sec := sector_of(x, z)
		sector_w[sec] = maxf(0.0, sector_w[sec] - w)
		z_arrived[i] = 0
	var r := sqrt(x * x + z * z)
	var dx := -x / r
	var dz := -z / r
	z_sx[i] = x
	z_sz[i] = z
	z_dx[i] = dx
	z_dz[i] = dz
	z_t0[i] = time
	z_L[i] = maxf(r - arrive_r, 0.0)
	var s := z_scale[i]
	mm.set_instance_transform(i, Transform3D(Basis(Vector3(-dz, 0, dx) * s, Vector3(0, s, 0), Vector3(-dx, 0, -dz) * s), Vector3(x, 0, z)))
	mm.set_instance_custom_data(i, Color(z_t0[i], z_v[i], z_L[i], z_seed[i]))
	var p := pos_of(i)
	_grid_insert(i, _cell_of(p.x, p.y))


## Danger-zone summary for the HUD and radio: weight of zombies at each wall sector.
func worst_sector() -> int:
	var best := -1
	var bw := 0.0
	for k in 8:
		if sector_w[k] > bw:
			bw = sector_w[k]
			best = k
	return best
