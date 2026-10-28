extends Node3D
## CAS mode. You fly Hawg 1-1, an A-10C, in close support of Spectre 2-1: the gunship, flown by
## the AI now, orbiting the refuge and working the big hordes. Spectre hands you the jobs it
## can't do: the boss its guns barely scratch, the crowd it can't see past the high-rises, the
## runners slipping past, the people on the ground.
##
## You go where you look. The mouse turns your head and the aircraft follows it: an instructor
## rolls toward wherever you're looking and pulls, and levels the wings when you're close. A / D
## roll it yourself.
##
## The threats are the ones a Hog pilot worries about when nobody's shooting back: running out of
## ammunition, flying into the ground (or a building), and not getting back to the FARP before the
## tanks run dry. One FARP does everything: land on its runway, stop, and you're rearmed and
## refuelled.

const Arsenal = preload("res://scripts/arsenal.gd")
const MeshKit = preload("res://scripts/mesh_kit.gd")
const G := 9.8
const MASS := 14000.0
const THRUST := 82000.0
const WING := 47.0
const RHO := 1.225
const CD0 := 0.07
const K_IND := 0.07
const CL_A := 5.5
const A_STALL := 0.27
const MAX_ROLL := 2.4
const MAX_PITCH := 0.85
const MAX_YAW := 0.3
const G_LIMIT := 7.0
const GEAR_H := 1.9
const FULL_THROTTLE_SECONDS := 420.0
const REARM_SECONDS := 18.0

var main
var node: MeshInstance3D
var gunship: MeshInstance3D
var pos := Vector3.ZERO
var prev_pos := Vector3.ZERO
var vel := Vector3.ZERO
var att := Basis()
var rate := Vector3.ZERO
var throttle := 0.8
var fuel := 1.0
var on_ground := false
var gear := false
var brakes := false
var crashed := false
var crash_t := 0.0
var look_yaw := 0.0
var look_pitch := -0.12
var look := Vector3.FORWARD
var steer := Vector3.FORWARD
var free_look := false
var fov := 68.0
var gload := 1.0
var alpha := 0.0
var agl := 1000.0
var pull_up := false
var stall := false
var bingo := false
var bingo_called := false
var winchester_called := false
var rearm := -1.0
var warn_cd := 0.0

# weapons: [GAU-8, Mk-82, GBU-12, AGM-65, Hydra]
var weapons: Array = []
var cur := 0
var gun_spin := 0.0
var gun_acc := 0.0
var gun_looping := false
var rocket_cd := 0.0
var drop_cd := 0.0
var bombs: Array = []
var mavs: Array = []
var lock_i := -1
var lock_p := Vector3.INF
var gun_pipper := Vector3.INF
var ccip := Vector3.INF
var mat_bomb: ShaderMaterial
var mat_hot: ShaderMaterial

# the AI gunship
var ai_acc40 := 0.0
var ai_acc105 := 2.0
var ai_acc25 := 0.0
var ai_burst := 0
var masked_spots: Array = []

# taskings from Spectre
var task: Dictionary = {}
var next_task := 25.0
# test only (the autotest): fly the approach and the landing by itself
var autoland := false
var autoland_end: Dictionary = {}


func begin() -> void:
	mat_bomb = ShaderMaterial.new()
	mat_bomb.shader = load("res://shaders/solid.gdshader")
	mat_bomb.set_shader_parameter("heat", 0.62)
	mat_bomb.set_shader_parameter("albedo", Vector3(0.4, 0.42, 0.36))
	mat_hot = ShaderMaterial.new()
	mat_hot.shader = load("res://shaders/solid.gdshader")
	mat_hot.set_shader_parameter("heat", 1.2)
	node = MeshInstance3D.new()
	node.mesh = MeshKit.a10()
	node.material_override = main.arsenal.mat_world
	add_child(node)
	gunship = MeshInstance3D.new()
	gunship.mesh = main.arsenal.gunship_mesh
	gunship.material_override = main.arsenal.mat_world
	add_child(gunship)
	weapons = [
		{"id": "gun", "name": "GAU-8/A AVENGER", "short": "GUN", "ammo": 1150, "max": 1150,
			"w": Arsenal._w({"id": "gau8", "name": "GAU-8/A", "short": "30MM", "kind": "rotary", "r_kill": 3.0, "r_frag": 6.0, "dmg": 6.0, "fling": 9.0,
				"fx": 0, "ff": 0.3, "snd": "exp_small", "vol": -2.0, "snd_every": 3})},
		{"id": "mk82", "name": "MK-82 500 LB", "short": "MK82", "ammo": 4, "max": 4,
			"w": Arsenal._w({"id": "cas_mk82", "name": "MK-82", "short": "MK82", "kind": "bomb", "r_kill": 14.0, "r_frag": 32.0, "dmg": 34.0, "fling": 22.0,
				"fx": 4, "ff": 12.0, "snd": "exp_large", "vol": 10.0})},
		{"id": "gbu12", "name": "GBU-12 PAVEWAY II", "short": "GBU12", "ammo": 2, "max": 2,
			"w": Arsenal._w({"id": "cas_gbu12", "name": "GBU-12", "short": "GBU12", "kind": "bomb", "r_kill": 18.0, "r_frag": 42.0, "dmg": 45.0, "fling": 26.0,
				"fx": 4, "ff": 15.0, "snd": "exp_large", "vol": 12.0})},
		{"id": "agm65", "name": "AGM-65 MAVERICK", "short": "AGM65", "ammo": 2, "max": 2,
			"w": Arsenal._w({"id": "cas_agm65", "name": "AGM-65", "short": "AGM65", "kind": "missile", "r_kill": 10.0, "r_frag": 24.0, "dmg": 60.0, "fling": 20.0,
				"fx": 3, "ff": 8.0, "snd": "exp_large", "vol": 9.0})},
		{"id": "rockets", "name": "LAU-131 HYDRA", "short": "FFAR", "ammo": 14, "max": 14,
			"w": Arsenal._w({"id": "cas_hydra", "name": "HYDRA", "short": "FFAR", "kind": "rockets", "r_kill": 3.5, "r_frag": 9.0, "dmg": 6.0, "fling": 10.0,
				"fx": 1, "ff": 1.5, "snd": "exp_med", "vol": 0.0, "snd_every": 2, "mv": 700.0})},
	]
	# off the FARP, inbound to the AO
	var af: Dictionary = main.world["airfield"]
	var c: Vector3 = af["center"]
	var to_ao := (Vector3.ZERO - c)
	to_ao.y = 0.0
	to_ao = to_ao.normalized()
	pos = c + to_ao * 1500.0 + Vector3.UP * 700.0
	vel = to_ao * 150.0
	att = Basis.looking_at(to_ao, Vector3.UP)
	look_yaw = atan2(-to_ao.x, -to_ao.z)
	look_pitch = -0.12
	prev_pos = pos
	main.sfx.start_engine()


# ---------------------------------------------------------------- input
func on_look(rel: Vector2) -> void:
	var k: float = 0.0022 * float(main.mouse_sens)
	if main.invert_y:
		rel.y = -rel.y
	look_yaw -= rel.x * k
	look_pitch = clampf(look_pitch - rel.y * k, -1.45, 1.45)


func on_wheel(f: float) -> void:
	fov = clampf(fov * f, 22.0, 75.0)


func select(i: int) -> void:
	if i < 0 or i >= weapons.size() or i == cur:
		return
	cur = i
	main.sfx.play("switch", -4.0)


func cycle(step: int) -> void:
	select(posmod(cur + step, weapons.size()))


func cycle_fuze() -> void:
	var w: Dictionary = weapons[cur]["w"]
	var f: Array = main.arsenal.fuzes_of(w)
	if f.size() < 2:
		main.sfx.play("switch", -10.0, 0.7)
		return
	w["fuze"] = (int(w.get("fuze", 0)) + 1) % f.size()
	main.sfx.play("clip", -8.0, 1.4)


## RMB: lock a Maverick onto whatever's under the look: a boss, a brute, or the thickest crowd.
func lock() -> void:
	var ap: Vector3 = main.aim_point
	lock_i = -1
	lock_p = Vector3.INF
	var bd := 120.0
	for b in main.horde.bosses:
		var bp: Vector3 = b["pos"]
		var d := Vector2(bp.x - ap.x, bp.z - ap.z).length()
		if d < bd:
			bd = d
			lock_i = int(b["i"])
	if lock_i < 0:
		var best := Vector3.INF
		var bn := 0
		for k in 10:
			var p := ap + Vector3(randf_range(-40, 40), 0.0, randf_range(-40, 40))
			var n: int = main.horde.count_near(p, 12.0, true)
			if n > bn:
				bn = n
				best = p
		lock_p = best if bn > 0 else ap
	main.sfx.play("lock", -6.0, 1.2)


# ---------------------------------------------------------------- per frame
func update(dt: float) -> void:
	if dt <= 0.0:
		return
	_ai_gunship(dt)
	_update_task(dt)
	_update_bombs(dt)
	_update_mavs(dt)
	if crashed:
		crash_t += dt
		if crash_t > 3.0 and main.is_playing():
			main._game_over("HAWG 1-1 IS DOWN", "Hawg one-one is down. No chute. Spectre's still up there, but you're not.")
		return
	_inputs(dt)
	var steps := maxi(1, int(ceil(dt / 0.008)))
	var h := dt / steps
	prev_pos = pos
	for k in steps:
		if on_ground:
			_roll_on_ground(h)
		else:
			_controls(h)
			_fly(h)
	_check_ground_and_obstacles()
	if crashed:
		return
	node.global_position = pos
	node.global_transform = Transform3D(att, pos)
	main.fx.particle(true, pos + att.z * 6.0 + att.y * 1.2, -(-att.z) * 20.0 + vel * 0.5, 0.2, 1.2, 2.5, 0.85 + 0.3 * throttle, 1)
	_weapons(dt)
	_systems(dt)


func _inputs(dt: float) -> void:
	if main.autotest:
		return
	var ks: Dictionary = main.keys
	if Input.is_key_pressed(ks["throttle_up"]):
		throttle = minf(1.0, throttle + 0.45 * dt)
	if Input.is_key_pressed(ks["throttle_down"]):
		throttle = maxf(0.0, throttle - 0.45 * dt)
	brakes = Input.is_key_pressed(KEY_SPACE)
	free_look = Input.is_key_pressed(ks["orbit_here"])


func _controls(dt: float) -> void:
	look = Vector3(-sin(look_yaw) * cos(look_pitch), sin(look_pitch), -cos(look_yaw) * cos(look_pitch))
	if autoland:
		steer = _autoland_steer()
	elif not free_look:
		steer = look
	# With the gear down it's the flight path that matters, not the nose: aim the nose above
	# where you're looking by the angle of attack, so the aircraft goes where you look.
	var aim_dir := steer
	if gear and not stall:
		aim_dir = steer.rotated(att.x, clampf(alpha, -0.1, 0.25))
	var lt := att.inverse() * aim_dir
	var off := rad_to_deg((-att.z).angle_to(aim_dir))
	var in_yaw := clampf(lt.x * 4.0, -1.0, 1.0)
	var in_pitch := clampf(lt.y * 4.0, -1.0, 1.0)
	# roll toward the target and pull when it's well off the nose; wings level when it's close
	var aggressive := clampf(lt.x * 4.0, -1.0, 1.0)
	if lt.z > 0.0:
		# it's behind us: roll hard toward it and pull through
		aggressive = 1.0 if lt.x >= 0.0 else -1.0
		in_pitch = 1.0
	var level := clampf(att.x.y * 3.0, -1.0, 1.0)
	var in_roll := lerpf(level, aggressive, clampf(off / 12.0, 0.0, 1.0))
	if not main.autotest:
		if Input.is_key_pressed(main.keys["orbit_in"]):
			in_roll = -1.0
		if Input.is_key_pressed(main.keys["orbit_out"]):
			in_roll = 1.0
	# stall protection: let the nose fall through rather than hang it on the stall
	if stall:
		in_pitch = minf(in_pitch, -0.3)
	var speed := vel.length()
	var auth := clampf(speed / 90.0, 0.15, 1.0)
	var max_pitch := minf(MAX_PITCH, G_LIMIT * G / maxf(speed, 20.0)) * auth
	var want := Vector3(in_pitch * max_pitch, -in_yaw * MAX_YAW * auth, in_roll * MAX_ROLL * auth)
	rate = rate.lerp(want, 1.0 - exp(-dt / 0.12))
	att = (att * Basis(Vector3.RIGHT, rate.x * dt) * Basis(Vector3.UP, rate.y * dt) * Basis(Vector3.FORWARD, rate.z * dt)).orthonormalized()


## Test only: steer down a three-degree glide path onto the nearer end of the strip, holding
## about 140 knots, and flare over the threshold.
func _autoland_steer() -> Vector3:
	var af: Dictionary = main.world["airfield"]
	var c: Vector3 = af["center"]
	var d: Vector3 = af["dir"]
	var hl: float = float(af["length"]) * 0.5
	if not autoland_end.has("near"):
		var a_end := c - d * hl
		var b_end := c + d * hl
		autoland_end = {"near": a_end if pos.distance_to(a_end) < pos.distance_to(b_end) else b_end}
	var near: Vector3 = autoland_end["near"]
	var land_dir := (c - near).normalized()
	var along := (pos - near).dot(land_dir)
	var aim := near + land_dir * (along + 450.0)
	var to_go := maxf(-(along + 450.0), 0.0)
	aim.y = to_go * tan(deg_to_rad(3.0)) + 1.0
	throttle = clampf(0.55 + (74.0 - vel.length()) * 0.08, 0.1, 1.0)
	if along > 0.0:
		# over the threshold: power off and let it settle onto the runway
		throttle = 0.0
		aim.y = -4.0
	return (aim - pos).normalized()


## The airframe: lift up to the stall, the fin keeping the nose into the airflow, drag (more with
## the speed brakes or the gear out), thrust while there's fuel, gravity.
func _fly(dt: float) -> void:
	var right := att.x
	var up := att.y
	var fwd := -att.z
	var speed := vel.length()
	var vdir := vel / speed if speed > 0.5 else fwd
	var q := 0.5 * RHO * speed * speed
	var vb := att.inverse() * vel
	alpha = atan2(-vb.y, -vb.z) if speed > 1.0 else 0.0
	var beta := atan2(vb.x, -vb.z) if speed > 1.0 else 0.0
	var cl := CL_A * alpha
	stall = absf(alpha) > A_STALL
	if stall:
		cl = signf(alpha) * CL_A * A_STALL * clampf(1.0 - (absf(alpha) - A_STALL) * 2.5, 0.25, 1.0)
	var ld := up - vdir * up.dot(vdir)
	var f := Vector3.ZERO
	if ld.length() > 0.001:
		f += ld.normalized() * q * WING * cl
	f += -right * q * WING * 0.9 * beta
	var cd := CD0 + K_IND * cl * cl + (0.09 if brakes else 0.0) + (0.025 if gear else 0.0)
	f += -vdir * q * WING * cd
	if fuel > 0.0:
		f += fwd * THRUST * throttle
	f += Vector3.DOWN * MASS * G
	var acc := f / MASS
	vel += acc * dt
	gload = (acc + Vector3.UP * G).dot(up) / G
	pos += vel * dt
	fuel = maxf(0.0, fuel - dt * (0.12 + 0.88 * throttle) / FULL_THROTTLE_SECONDS)


## On the runway: thrust against rolling drag and the brakes, the nosewheel steering toward
## where you're looking, and off the ground once there's flying speed and you look up.
func _roll_on_ground(dt: float) -> void:
	look = Vector3(-sin(look_yaw) * cos(look_pitch), sin(look_pitch), -cos(look_yaw) * cos(look_pitch))
	var fwd := -att.z
	var hdir := Vector3(fwd.x, 0.0, fwd.z).normalized()
	var speed := vel.dot(hdir)
	var q := 0.5 * RHO * speed * speed
	if autoland:
		throttle = 0.0
		brakes = true
	var acc: float = (THRUST * throttle if fuel > 0.0 else 0.0) / MASS - 0.02 * G - q * WING * CD0 / MASS
	if brakes or throttle < 0.08:
		acc -= 6.0
	speed = maxf(0.0, speed + acc * dt)
	var lh := Vector3(look.x, 0.0, look.z).normalized()
	var turn := clampf(hdir.signed_angle_to(lh, Vector3.UP), -1.0, 1.0) * clampf(1.2 - speed / 80.0, 0.15, 1.0) * dt
	hdir = hdir.rotated(Vector3.UP, turn)
	att = Basis.looking_at(hdir, Vector3.UP)
	vel = hdir * speed
	pos += vel * dt
	pos.y = _ground_at(pos) + GEAR_H
	fuel = maxf(0.0, fuel - dt * (0.12 + 0.88 * throttle) / FULL_THROTTLE_SECONDS)
	# rotate and fly
	if speed > 72.0 and look_pitch > -0.02:
		on_ground = false
		gear = true
		att = att * Basis(Vector3.RIGHT, 0.12)
		vel.y = 3.0
		pos.y += 0.6
		main.radio("HAWG 1-1", "Hawg one-one, airborne.")
	# stopped on the strip: rearm and refuel
	if speed < 6.0 and _on_runway(pos):
		if rearm < 0.0:
			rearm = 0.0
			main.radio("CREW CHIEF", "Hawg's in. Hot pits: fuel and bombs, %d seconds." % int(REARM_SECONDS))
		rearm = minf(1.0, rearm + dt / REARM_SECONDS)
		fuel = minf(1.0, fuel + dt / REARM_SECONDS)
		if rearm >= 1.0 and not bool(weapons[0].get("refilled", false)):
			for wd in weapons:
				wd["ammo"] = wd["max"]
				wd["refilled"] = true
			bingo_called = false
			winchester_called = false
			main.radio("CREW CHIEF", "You're full up, sir. Cleared to go back out.")
	else:
		if rearm >= 0.0 and speed > 6.0:
			rearm = -1.0
			for wd in weapons:
				wd["refilled"] = false


func _ground_at(p: Vector3) -> float:
	var hit: Dictionary = main.raycast(p + Vector3.UP * 30.0, p + Vector3.DOWN * 500.0)
	return float((hit.get("position", Vector3(p.x, 0.0, p.z)) as Vector3).y)


func _on_runway(p: Vector3) -> bool:
	var af: Dictionary = main.world["airfield"]
	var c: Vector3 = af["center"]
	var d: Vector3 = af["dir"]
	var rel := Vector2(p.x - c.x, p.z - c.z)
	var d2 := Vector2(d.x, d.z)
	if absf(rel.dot(d2)) < float(af["length"]) * 0.5 + 20.0 and absf(rel.cross(d2)) < float(af["width"]) * 0.5 + 8.0:
		return true
	# or parked on the apron
	var ap: Vector3 = af["apron"]
	return Vector2(p.x - ap.x, p.z - ap.z).length() < 120.0


## Touching down, or flying into something. The wheels can take a firm landing on the strip;
## anything else that meets the aircraft is the end of it.
func _check_ground_and_obstacles() -> void:
	if on_ground:
		return
	var right := att.x
	var fwd := -att.z
	var gh := _ground_at(pos)
	agl = pos.y - gh
	# wheels on the ground
	if agl <= GEAR_H:
		var bank := asin(clampf(-right.y, -1.0, 1.0))
		var nose := asin(clampf(fwd.y, -1.0, 1.0))
		var speed := vel.length()
		if _on_runway(pos) and vel.y > -7.5 and absf(bank) < 0.35 and nose > -0.14 and speed < 115.0:
			on_ground = true
			vel.y = 0.0
			var h := Vector3(fwd.x, 0.0, fwd.z).normalized()
			att = Basis.looking_at(h, Vector3.UP)
			pos.y = gh + GEAR_H
			main.sfx.play("clip", -2.0, 0.6)
			main.kick(0.3)
			main.radio("HAWG 1-1", "Hawg's down. %s" % ("Nice and smooth." if vel.y > -3.0 else "Firm one."))
			return
		_crash("flew into the ground" if not _on_runway(pos) else "landed too hard")
		return
	# buildings, hills, masts: the nose and both wingtips
	for off: Vector3 in [fwd * 7.0, right * 8.5, -right * 8.5]:
		var hit: Dictionary = main.raycast(prev_pos + off, pos + off)
		if not hit.is_empty():
			_crash("hit %s" % ("a building" if (hit["position"] as Vector3).y > 2.0 else "the ground"))
			return


func _crash(why: String) -> void:
	crashed = true
	crash_t = 0.0
	node.visible = false
	main.fx.explosion(pos, 5, 300.0)
	main.fx.particle(true, pos, Vector3.ZERO, 0.4, 10.0, 60.0, 2.6, 0)
	for k in 30:
		main.fx.particle(true, pos, Vector3(randf_range(-1, 1), randf_range(0.2, 1.4), randf_range(-1, 1)).normalized() * randf_range(20, 70) + vel * 0.3, randf_range(1.5, 3.5), 1.4, 1.0, 1.8, 3, 1.0, 0.2)
	main.sfx.play("exp_huge", 4.0, 0.8)
	main.sfx.gun_cease()
	main.kick(2.0)
	main.flash = 0.6
	main.radio("SPECTRE 2-1", "Hawg one-one %s! Hawg's down, Hawg's down!" % why, true)
	main.horde.blast(pos, 12.0, 30.0, 40.0, 20.0)


## Fuel, warnings, the gear.
func _systems(dt: float) -> void:
	warn_cd -= dt
	var speed := vel.length()
	# the gear comes down by itself low, slow and descending, and comes up again climbing out
	gear = on_ground or (agl < 250.0 and speed < 100.0 and vel.y < 1.0)
	# what the radar altimeter and the flight path say about the ground ahead
	pull_up = false
	if not on_ground and speed > 30.0:
		var ahead: Dictionary = main.raycast(pos, pos + vel * 4.0)
		var landing: bool = gear and _on_runway(pos + vel * 4.0) and vel.y > -8.0
		pull_up = not ahead.is_empty() and not landing
	if pull_up and warn_cd <= 0.0:
		warn_cd = 0.6
		main.sfx.play("alarm", -6.0, 1.6)
	# bingo: just enough to get home, with a little in reserve
	var af: Dictionary = main.world["airfield"]
	var home: float = pos.distance_to(af["center"])
	var need := home / 150.0 * (0.12 + 0.88 * 0.6) / FULL_THROTTLE_SECONDS + 0.05
	bingo = fuel < need and not on_ground
	if bingo and not bingo_called:
		bingo_called = true
		main.radio("HAWG 1-1", "Bingo fuel. Hawg's RTB.", true)
		main.sfx.play("alarm", -4.0, 0.9)
	if fuel <= 0.0 and not on_ground and warn_cd <= 0.0:
		warn_cd = 4.0
		main.radio("HAWG 1-1", "Flameout! Both engines! Gliding for the strip!", true)
	var empty := true
	for wd in weapons:
		if int(wd["ammo"]) > 0:
			empty = false
	if empty and not winchester_called:
		winchester_called = true
		main.radio("HAWG 1-1", "Hawg's Winchester. RTB for rearm.", true)


# ---------------------------------------------------------------- weapons
func _weapons(dt: float) -> void:
	var firing := false
	if not main.autotest:
		firing = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not main.tac_open
	else:
		firing = main.cas_auto_fire
	drop_cd -= dt
	rocket_cd -= dt
	_gun(dt, firing and cur == 0 and not on_ground)
	if on_ground:
		return
	gun_pipper = _gun_impact()
	ccip = _bomb_impact()
	if not firing:
		return
	var wd: Dictionary = weapons[cur]
	if int(wd["ammo"]) <= 0:
		return
	match String(wd["id"]):
		"mk82", "gbu12":
			if drop_cd <= 0.0:
				drop_cd = 0.35
				_drop(wd)
		"agm65":
			if drop_cd <= 0.0:
				drop_cd = 1.0
				_fire_mav(wd)
		"rockets":
			if rocket_cd <= 0.0:
				rocket_cd = 0.12
				_fire_rocket(wd)


func _bore() -> Vector3:
	return (-att.z).rotated(att.x, -deg_to_rad(1.0))


func _gun(dt: float, want: bool) -> void:
	var wd: Dictionary = weapons[0]
	var can := want and int(wd["ammo"]) > 0
	if can:
		if gun_spin <= 0.0:
			main.sfx.play("gau8_spinup", -3.0, 1.0)
		gun_spin = minf(1.0, gun_spin + dt / 0.35)
	else:
		gun_spin = maxf(0.0, gun_spin - dt / 0.5)
	if can and gun_spin > 0.3:
		gun_looping = true
		main.sfx.gun_loop("gau8_loop", 0.65 + 0.35 * gun_spin)
		gun_acc += 65.0 * dt * clampf((gun_spin - 0.2) / 0.8, 0.0, 1.0)
		while gun_acc >= 1.0 and int(wd["ammo"]) > 0:
			gun_acc -= 1.0
			wd["ammo"] = int(wd["ammo"]) - 1
			_gun_round(wd)
		# ten thousand pounds of recoil: the gun really does slow the aircraft down
		vel -= (-att.z) * 3.2 * dt
		main.kick(0.06)
	elif gun_looping:
		gun_looping = false
		main.sfx.gun_cease()
		main.sfx.play("gau8_spindown", -3.0, 1.0)


func _gun_round(wd: Dictionary) -> void:
	var bore := _bore()
	var muzzle := pos + bore * 8.0 - att.y * 0.6
	var v0 := bore * 1013.0 + vel
	var sig := 0.004
	v0 = (v0 + Vector3(randfn(0.0, sig), randfn(0.0, sig), randfn(0.0, sig)) * v0.length())
	var ip := _arc_hit(muzzle, v0, 4.0)
	if ip == Vector3.INF:
		return
	main.arsenal.launch_shell(muzzle, ip, v0.length(), wd["w"], 1.25, 0.1, 0.025, false, "")
	main.shots_fired += 1


## Where a projectile leaving p0 at v0 comes down: the gravity arc against the ground and
## anything standing on it, out to tmax seconds.
func _arc_hit(p0: Vector3, v0: Vector3, tmax: float) -> Vector3:
	var a := -0.5 * G
	var disc := v0.y * v0.y - 4.0 * a * p0.y
	var tg := tmax
	if disc >= 0.0:
		var t1 := (-v0.y - sqrt(disc)) / (2.0 * a)
		if t1 > 0.0:
			tg = minf(t1 + 0.3, tmax)
	var prev := p0
	for k in 4:
		var tt := tg * float(k + 1) / 4.0
		var p := p0 + v0 * tt + Vector3(0.0, a * tt * tt, 0.0)
		var hit: Dictionary = main.raycast(prev, p)
		if not hit.is_empty():
			return hit["position"]
		prev = p
	return Vector3.INF


func _gun_impact() -> Vector3:
	if cur != 0 and cur != 4:
		return Vector3.INF
	var bore := _bore()
	var mv := 1013.0 if cur == 0 else 700.0
	return _arc_hit(pos + bore * 8.0, bore * mv + vel, 6.0 if cur == 0 else 8.0)


## CCIP: where a bomb let go right now would land.
func _bomb_impact() -> Vector3:
	if cur != 1 and cur != 2:
		return Vector3.INF
	var p := pos - att.y * 1.5
	var v := vel
	var prev := p
	var t := 0.0
	while t < 40.0:
		var h := 0.25
		v += Vector3.DOWN * G * h - v * (0.0004 * v.length()) * h
		p += v * h
		t += h
		if p.y < 300.0 or t > 39.0:
			var hit: Dictionary = main.raycast(prev, p)
			if not hit.is_empty():
				return hit["position"]
			if p.y < -20.0:
				return Vector3(p.x, 0.0, p.z)
		prev = p
	return Vector3.INF


func _fuze(wd: Dictionary) -> String:
	return main.arsenal.fuze_of(wd["w"])


func _drop(wd: Dictionary) -> void:
	wd["ammo"] = int(wd["ammo"]) - 1
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.45, 0.45, 2.6)
	var p0 := pos - att.y * 1.6
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = mat_bomb
	add_child(n)
	n.global_position = p0
	bombs.append({"pos": p0, "vel": vel - att.y * 2.0, "wd": wd, "fuze": _fuze(wd), "guided": wd["id"] == "gbu12", "node": n, "t": 0.0})
	main.sfx.play("bomb_release", -2.0)
	main.kick(0.2)


func _update_bombs(dt: float) -> void:
	for k in range(bombs.size() - 1, -1, -1):
		var b: Dictionary = bombs[k]
		b["t"] = float(b["t"]) + dt
		var p: Vector3 = b["pos"]
		var v: Vector3 = b["vel"]
		v += Vector3.DOWN * G * dt - v * (0.0004 * v.length()) * dt
		if b["guided"] and float(b["t"]) > 0.8:
			# the laser spot is wherever you're looking
			var spot: Vector3 = main.aim_point
			var want := (spot - p).normalized()
			if v.normalized().angle_to(want) < deg_to_rad(35.0):
				v = v.slerp(want * v.length(), minf(1.0, 1.4 * dt))
		var np := p + v * dt
		var node_b: MeshInstance3D = b["node"]
		var hit: Dictionary = main.raycast(p, np)
		if not hit.is_empty() or float(b["t"]) > 60.0:
			var ip: Vector3 = hit.get("position", np)
			node_b.queue_free()
			bombs.remove_at(k)
			var wd: Dictionary = b["wd"]
			main.arsenal._impact(ip, wd["w"], false, Vector3(v.x, 0.0, v.z).normalized(), String(b["fuze"]))
			continue
		b["pos"] = np
		b["vel"] = v
		node_b.global_position = np
		if absf(v.normalized().y) < 0.995:
			node_b.look_at(np + v, Vector3.UP)


func _fire_mav(wd: Dictionary) -> void:
	if lock_i < 0 and lock_p == Vector3.INF:
		main.sfx.play("switch", -6.0, 0.6)
		main.radio("HAWG 1-1", "No lock. Right mouse to lock the Maverick.")
		return
	wd["ammo"] = int(wd["ammo"]) - 1
	var side := 1.0 if int(wd["ammo"]) % 2 == 0 else -1.0
	var p0 := pos + att.x * 3.5 * side - att.y * 1.2
	var n := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.35, 0.35, 2.5)
	n.mesh = mesh
	n.material_override = mat_hot
	add_child(n)
	n.global_position = p0
	mavs.append({"pos": p0, "vel": vel, "t": 0.0, "lock_i": lock_i, "lock_p": lock_p, "wd": wd, "fuze": _fuze(wd), "node": n})
	main.sfx.play("hellfire_launch", -1.0, 0.85)
	main.radio("HAWG 1-1", "Rifle.")


func _update_mavs(dt: float) -> void:
	for k in range(mavs.size() - 1, -1, -1):
		var m: Dictionary = mavs[k]
		m["t"] = float(m["t"]) + dt
		var t: float = m["t"]
		var p: Vector3 = m["pos"]
		var v: Vector3 = m["vel"]
		if t < 0.4:
			v += Vector3.DOWN * G * dt
		else:
			var tgt: Vector3 = m["lock_p"]
			var li: int = m["lock_i"]
			if li >= 0 and main.horde.z_alive[li] == 1:
				var tgo := p.distance_to(tgt if tgt != Vector3.INF else p) / 320.0
				var zp: Vector2 = main.horde.pos_at(li, main.t + tgo)
				tgt = Vector3(zp.x, 1.0, zp.y)
				m["lock_p"] = tgt
			if tgt == Vector3.INF:
				tgt = p + v
			var speed := minf(320.0, v.length() + 180.0 * dt)
			var want := (tgt - p).normalized()
			var cd := v.normalized()
			var ang := cd.angle_to(want)
			var nd := cd if ang < 0.0001 else cd.slerp(want, minf(1.0, 3.0 * dt / ang))
			v = nd * speed
			main.fx.particle(true, p - v.normalized() * 1.5, -v.normalized() * 20.0, 0.12, 1.2, 0.6, 1.7, 1)
		var np := p + v * dt
		var n: MeshInstance3D = m["node"]
		var hit: Dictionary = main.raycast(p, np + v.normalized())
		if not hit.is_empty() or t > 30.0:
			var ip: Vector3 = hit.get("position", np)
			n.queue_free()
			mavs.remove_at(k)
			var wd: Dictionary = m["wd"]
			main.arsenal._impact(ip, wd["w"], false, Vector3(v.x, 0.0, v.z).normalized(), String(m["fuze"]))
			continue
		m["pos"] = np
		m["vel"] = v
		n.global_position = np
		if absf(v.normalized().y) < 0.995:
			n.look_at(np + v, Vector3.UP)


func _fire_rocket(wd: Dictionary) -> void:
	wd["ammo"] = int(wd["ammo"]) - 1
	var side := 1.0 if int(wd["ammo"]) % 2 == 0 else -1.0
	var p0 := pos + att.x * 4.5 * side - att.y * 1.0
	var v0 := _bore() * 700.0 + vel + Vector3(randfn(0.0, 8.0), randfn(0.0, 6.0), randfn(0.0, 8.0))
	main.arsenal.missiles.append({"pos": p0, "vel": v0, "t": 0.0, "node": main.arsenal._node(main.arsenal.missile_mesh, main.arsenal.mat_hot, p0),
		"w": wd["w"], "guided": false, "fuze": _fuze(wd)})
	main.sfx.play("rocket", -6.0, randf_range(0.9, 1.1))


# ---------------------------------------------------------------- the AI gunship
## Spectre 2-1 flies its orbit over the refuge and works the horde: first whatever is at or near
## the wall, then the thickest crowd it can see. What it can't see past the buildings, it
## remembers, and hands to you.
func _ai_gunship(dt: float) -> void:
	var gp: Vector3 = main.air_pos
	var fwd: Vector3 = main.air_fwd
	gunship.global_position = gp
	gunship.look_at(gp + fwd, Vector3.UP.rotated(fwd, -deg_to_rad(float(main.bank))))
	if not main.wave_active and int(main.horde.alive_count) == 0:
		return
	ai_acc40 += dt
	ai_acc105 += dt
	ai_acc25 += dt
	if ai_acc40 >= 0.55:
		ai_acc40 = 0.0
		var tp := _ai_target(gp)
		if tp != Vector3.INF:
			_ai_shot(gp, tp, main.arsenal.by_id("bofors"), 0.0012)
	if ai_acc105 >= 4.5:
		ai_acc105 = 0.0
		var tp := _ai_target(gp)
		if tp != Vector3.INF:
			_ai_shot(gp, tp, main.arsenal.by_id("m102"), 0.0007)
			main.sfx.play_at("howitzer", gp, main.cam.global_position, -2.0, 0.95)
	if ai_acc25 >= 0.11:
		ai_acc25 = 0.0
		ai_burst -= 1
		if ai_burst < -14:
			ai_burst = 10
		if ai_burst > 0:
			var tp := _ai_target(gp, true)
			if tp != Vector3.INF:
				_ai_shot(gp, tp, main.arsenal.by_id("gau12"), 0.003)


func _ai_target(gp: Vector3, near_only := false) -> Vector3:
	var h = main.horde
	var thr: PackedInt32Array = h.threats
	if not thr.is_empty():
		for k in 6:
			var i: int = thr[randi() % thr.size()]
			if h.z_alive[i] == 1:
				var p: Vector2 = h.pos_of(i)
				var tp := Vector3(p.x, 1.0, p.y)
				if main.los_blocked(gp, tp) == Vector3.INF:
					return tp
	if near_only:
		return Vector3.INF
	var best := Vector3.INF
	var bs := -1.0
	for k in 8:
		var p: Vector3 = h.random_alive_pos()
		if p == Vector3.INF:
			continue
		var s: float = float(h.count_near(p, 14.0, true)) / (1.0 + Vector2(p.x, p.z).length() / 700.0)
		if s < 3.0:
			continue
		if main.los_blocked(gp, p + Vector3.UP) != Vector3.INF:
			# a crowd it can't see: the A-10's job
			if masked_spots.size() < 8 and s > 6.0:
				masked_spots.append(p)
			continue
		if s > bs:
			bs = s
			best = p
	return best


func _ai_shot(gp: Vector3, target: Vector3, gun: Dictionary, disp: float) -> void:
	var muzzle := gp + Vector3.DOWN * 3.0
	var dist := muzzle.distance_to(target)
	var aim := target + Vector3(randfn(0.0, disp * dist), 0.0, randfn(0.0, disp * dist))
	var hit: Dictionary = main.raycast(muzzle, muzzle + (aim - muzzle) * 1.4)
	if hit.is_empty():
		return
	main.arsenal.launch_shell(muzzle, hit["position"], float(gun["mv"]), gun, float(gun["heat"]), float(gun["tw"]), float(gun["streak"]), true)


# ---------------------------------------------------------------- taskings
## Spectre gives you a job every half-minute or so: a boss, the teams on the ground, a crowd it
## can't see, runners getting past, or just the thickest crowd on an approach.
func _update_task(dt: float) -> void:
	if task.is_empty():
		next_task -= dt
		if next_task <= 0.0 and main.wave_active:
			_new_task()
		return
	task["t"] = float(task["t"]) + dt
	var done := false
	match String(task["kind"]):
		"boss":
			var i: int = task["i"]
			done = main.horde.z_alive[i] == 0 or main.horde.z_type[i] != main.horde.BOSS
			if not done:
				var bp: Vector2 = main.horde.pos_of(i)
				task["pos"] = Vector3(bp.x, 0.0, bp.y)
		"nest":
			done = not bool((task["lm"] as Dictionary)["alive"])
		_:
			done = int(task["kills"]) >= int(task["need"])
	if done:
		var pay := int(round(float(task["pay"]) * (1.0 + float(main.wave) * 0.05) * float(main.stat("rp"))))
		main.rp += pay
		main.rp_total += pay
		main.radio("SPECTRE 2-1", ["Good hits, Hawg. That's what I needed.", "Shack. Nice work, Hawg.", "That's done. Thanks, Hawg.", "Beautiful. Spectre owes you one."].pick_random(), true)
		main.banner = "TASKING COMPLETE  //  +%s RP" % main.hud.commas(pay)
		main.banner_t = main.real_t
		main._feed("TASKING  +%s RP" % main.hud.commas(pay))
		task = {}
		next_task = randf_range(20.0, 40.0)
	elif float(task["t"]) > 150.0:
		main.radio("SPECTRE 2-1", "Forget that last one, Hawg. I'll find you something else.")
		task = {}
		next_task = 15.0


func _new_task() -> void:
	var h = main.horde
	var sec := func(p: Vector3) -> String: return String(main.SECTORS[h.sector_of(p.x, p.z)]).to_lower()
	# a boss its guns barely scratch
	if not h.bosses.is_empty():
		var b: Dictionary = h.bosses[0]
		var bp: Vector3 = b["pos"]
		task = {"kind": "boss", "i": int(b["i"]), "pos": bp, "t": 0.0, "pay": 4000.0, "text": "%s, %s" % [String(b["def"]["name"]), sec.call(bp)]}
		main.radio("SPECTRE 2-1", "Hawg, Spectre. There's a %s on the %s approach and my guns are just making it angry. Mavericks, delay fuzes, whatever you've got." % [String(b["def"]["name"]).to_lower(), sec.call(bp)], true)
		return
	# the people on the ground
	var mo: Dictionary = main.missions.obj
	if not mo.is_empty():
		match String(mo["kind"]):
			"nest":
				var lm: Dictionary = mo["lm"]
				task = {"kind": "nest", "lm": lm, "pos": lm["pos"], "t": 0.0, "pay": 3000.0, "text": "BRING DOWN %s" % String(lm["name"])}
				main.radio("SPECTRE 2-1", "Hawg, I can't drop %s with what I've got. Set your five-hundreds to delay and put them through the roof." % String(lm["name"]).to_lower(), true)
				return
			"hold", "engineers":
				task = {"kind": "support", "pos": mo["pos"], "r": 140.0, "kills": 0, "need": 30, "t": 0.0, "pay": 2500.0, "text": "COVER %s" % ("RANGER 6" if mo["kind"] == "hold" else "THE ENGINEERS")}
				main.radio("SPECTRE 2-1", "Hawg, the team on the ground needs a gun run, I'm busy on the far side. Clear them a hundred metres round.", true)
				return
			"medevac":
				var lzs: Array = mo["lzs"]
				var i: int = mo["i"]
				if i < lzs.size():
					task = {"kind": "support", "pos": lzs[i], "r": 90.0, "kills": 0, "need": 15, "t": 0.0, "pay": 2000.0, "text": "CLEAR LZ %d" % (i + 1)}
					main.radio("SPECTRE 2-1", "Hawg, the dustoff's LZ is hot. Clear it for him.", true)
					return
	# a crowd it can't see past the buildings
	if not masked_spots.is_empty():
		var p: Vector3 = masked_spots.pop_back()
		masked_spots.clear()
		if h.count_near(p, 40.0, true) >= 10:
			task = {"kind": "masked", "pos": p, "r": 90.0, "kills": 0, "need": 25, "t": 0.0, "pay": 2500.0, "text": "MASKED CROWD, %s" % sec.call(p).to_upper()}
			main.radio("SPECTRE 2-1", "Hawg, I'm masked by the buildings on the %s side. Big crowd in the streets I can't see into. Get down in there." % sec.call(p), true)
			return
	# runners getting past
	var thr: PackedInt32Array = h.threats
	for k in mini(thr.size(), 40):
		var i: int = thr[randi() % thr.size()]
		if h.z_alive[i] == 1 and h.z_type[i] == 1:
			var rp: Vector2 = h.pos_of(i)
			var p := Vector3(rp.x, 0.0, rp.y)
			task = {"kind": "runners", "pos": p, "r": 120.0, "kills": 0, "need": 8, "t": 0.0, "pay": 2000.0, "text": "RUNNERS, %s" % sec.call(p).to_upper()}
			main.radio("SPECTRE 2-1", "Runners slipping past on the %s side, %d metres from the wall. Gun run, now, Hawg!" % [sec.call(p), int(rp.length())], true)
			return
	# the thickest crowd out on the approaches
	var c: Vector3 = main.defences._crowd(1100.0, 2700.0)
	if c != Vector3.INF:
		task = {"kind": "crowd", "pos": c, "r": 110.0, "kills": 0, "need": 40, "t": 0.0, "pay": 1500.0, "text": "INTERDICT, %s %.1f KM" % [sec.call(c).to_upper(), Vector2(c.x, c.z).length() / 1000.0]}
		main.radio("SPECTRE 2-1", "Hawg, big crowd forming %.1f klicks %s. Break it up before it gets here." % [Vector2(c.x, c.z).length() / 1000.0, sec.call(c)], true)
	else:
		next_task = 15.0


## Every one of our own detonations: it counts toward the tasking if it's in the right place.
func on_player_impact(p: Vector3, k: int) -> void:
	if task.is_empty() or not task.has("kills") or k <= 0:
		return
	var tp: Vector3 = task["pos"]
	if Vector2(p.x - tp.x, p.z - tp.z).length() < float(task["r"]):
		task["kills"] = int(task["kills"]) + k


# ---------------------------------------------------------------- camera
func update_camera(cam: Camera3D, delta: float) -> void:
	look = Vector3(-sin(look_yaw) * cos(look_pitch), sin(look_pitch), -cos(look_yaw) * cos(look_pitch))
	var anchor := pos + Vector3.UP * 4.0
	var dist := 30.0 if not crashed else 90.0
	var cp := anchor - look * dist + Vector3.UP * 3.0
	# don't put the camera through the ground
	var gh := _ground_at(cp)
	cp.y = maxf(cp.y, gh + 2.5)
	var j: float = 0.0004 + float(main.shake) * 0.003
	cam.look_at_from_position(cp, anchor + look * 600.0, Vector3.UP)
	cam.rotate_object_local(Vector3.RIGHT, randf_range(-j, j))
	cam.rotate_object_local(Vector3.UP, randf_range(-j, j))
	main.shake = float(main.shake) * exp(-delta * 4.0)
	main._apply_fov(cam, fov)


# ---------------------------------------------------------------- HUD
func draw_hud(h, sz: Vector2, c: Vector2) -> void:
	var cam: Camera3D = main.cam
	var FG: Color = h.FG
	var WARN: Color = h.WARN
	var GOOD: Color = h.GOOD
	var DIM: Color = h.DIM
	var hud_col := Color(0.55, 1.0, 0.6)
	var fwd := -att.z
	var speed := vel.length()
	# where you're steering: the mouse circle at the centre
	h.draw_arc(c, 11.0, 0, TAU, 24, Color(0, 0, 0, 0.6), 3.0)
	h.draw_arc(c, 11.0, 0, TAU, 24, Color(FG, 0.8), 1.2)
	if crashed:
		return
	# the nose: the gun cross
	var nose := pos + fwd * 1500.0
	if not cam.is_position_behind(nose):
		var s: Vector2 = h.proj(nose)
		h.ln(s + Vector2(-14, 0), s + Vector2(-5, 0), hud_col, 1.5)
		h.ln(s + Vector2(5, 0), s + Vector2(14, 0), hud_col, 1.5)
		h.ln(s + Vector2(0, -12), s + Vector2(0, -5), hud_col, 1.5)
	# the flight path marker, and a pitch ladder round it
	if speed > 5.0:
		var fp := pos + vel.normalized() * 1500.0
		if not cam.is_position_behind(fp):
			var s: Vector2 = h.proj(fp)
			h.draw_arc(s, 6.0, 0, TAU, 16, hud_col, 1.5)
			h.ln(s + Vector2(-18, 0), s + Vector2(-6, 0), hud_col, 1.5)
			h.ln(s + Vector2(6, 0), s + Vector2(18, 0), hud_col, 1.5)
			h.ln(s + Vector2(0, -6), s + Vector2(0, -13), hud_col, 1.5)
		var hd := Vector3(vel.x, 0.0, vel.z).normalized()
		if hd.length() > 0.5:
			var side := hd.cross(Vector3.UP).normalized()
			for e in range(-30, 31, 10):
				var er := deg_to_rad(float(e))
				var dirc := hd * cos(er) + Vector3.UP * sin(er)
				var pa := pos + (dirc + side * 0.05) * 1500.0
				var pb := pos + (dirc + side * 0.12) * 1500.0
				var pc := pos + (dirc - side * 0.05) * 1500.0
				var pd := pos + (dirc - side * 0.12) * 1500.0
				if cam.is_position_behind(pa) or cam.is_position_behind(pd):
					continue
				var col := Color(hud_col, 0.75 if e == 0 else 0.45)
				h.ln(h.proj(pa), h.proj(pb), col, 1.2 if e != 0 else 1.6)
				h.ln(h.proj(pc), h.proj(pd), col, 1.2 if e != 0 else 1.6)
				if e != 0:
					h.txt(h.proj(pb) + Vector2(6, 4), "%d" % e, col, 10)
	# the selected weapon's aiming symbology
	var wd: Dictionary = weapons[cur]
	match String(wd["id"]):
		"gun", "rockets":
			if gun_pipper != Vector3.INF and not cam.is_position_behind(gun_pipper):
				var s: Vector2 = h.proj(gun_pipper)
				var rng: float = pos.distance_to(gun_pipper)
				h.draw_arc(s, 16.0, 0, TAU, 32, Color(0, 0, 0, 0.6), 3.5)
				h.draw_arc(s, 16.0, 0, TAU, 32, hud_col, 1.5)
				h.draw_arc(s, 21.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(1.0 - rng / 4000.0, 0.0, 1.0), 24, hud_col, 2.0)
				h.draw_circle(s, 1.8, hud_col)
				h.txt(s + Vector2(24, 4), "%.1f" % (rng / 1000.0), hud_col, 11)
		"mk82", "gbu12":
			if ccip != Vector3.INF and not cam.is_position_behind(ccip):
				var s: Vector2 = h.proj(ccip)
				var fp2 := pos + vel.normalized() * 1500.0
				if not cam.is_position_behind(fp2):
					h.ln(h.proj(fp2), s, Color(hud_col, 0.6), 1.0)
				h.draw_arc(s, 10.0, 0, TAU, 24, Color(0, 0, 0, 0.6), 3.5)
				h.draw_arc(s, 10.0, 0, TAU, 24, hud_col, 1.5)
				h.draw_circle(s, 2.0, hud_col)
				h.txt(s + Vector2(14, 4), "CCIP", hud_col, 11, 0, h.font_b)
			if wd["id"] == "gbu12":
				var ap: Vector3 = main.aim_point
				if not cam.is_position_behind(ap):
					var s2: Vector2 = h.proj(ap)
					var dia := PackedVector2Array([s2 + Vector2(0, -8), s2 + Vector2(8, 0), s2 + Vector2(0, 8), s2 + Vector2(-8, 0), s2 + Vector2(0, -8)])
					h.draw_polyline(dia, WARN, 1.5)
					h.txt(s2 + Vector2(12, 4), "LASER", WARN, 11)
		"agm65":
			var lp := lock_p
			if lock_i >= 0 and main.horde.z_alive[lock_i] == 1:
				var zp: Vector2 = main.horde.pos_of(lock_i)
				lp = Vector3(zp.x, 1.0, zp.y)
			if lp != Vector3.INF and not cam.is_position_behind(lp):
				var s: Vector2 = h.proj(lp)
				h.draw_rect(Rect2(s - Vector2(14, 14), Vector2(28, 28)), Color(0, 0, 0, 0.6), false, 3.5)
				h.draw_rect(Rect2(s - Vector2(14, 14), Vector2(28, 28)), hud_col, false, 1.5)
				h.txt(s + Vector2(0, -20), "LOCKED", hud_col, 11, 1, h.font_b)
			else:
				h.txt(c + Vector2(0, 40), "RMB  LOCK MAVERICK", DIM, 12, 1, h.font_b)
	# left: speed, G, throttle, fuel
	var x := 60.0
	var y := c.y - 70.0
	h.txt(Vector2(x, y), "%d KT" % int(speed * 1.944), hud_col, 22, 0, h.font_b)
	h.txt(Vector2(x, y + 22), "G %.1f   AOA %d" % [gload, int(rad_to_deg(alpha))], hud_col, 13)
	h.txt(Vector2(x, y + 44), "THR %d%%%s" % [int(throttle * 100.0), "   SPD BRK" if brakes else ""], hud_col, 13)
	h.bar(Rect2(Vector2(x, y + 52), Vector2(140, 6)), throttle, hud_col)
	var fcol := WARN if bingo or fuel < 0.15 else hud_col
	h.txt(Vector2(x, y + 78), "FUEL %d%%%s" % [int(fuel * 100.0), "   BINGO" if bingo else ""], fcol, 14, 0, h.font_b)
	h.bar(Rect2(Vector2(x, y + 86), Vector2(140, 6)), fuel, fcol)
	if gear:
		h.txt(Vector2(x, y + 112), "GEAR DOWN", hud_col, 12, 0, h.font_b)
	# right: altitude, radar altitude, climb
	var xr := sz.x - 60.0
	h.txt(Vector2(xr, y), "%s FT" % h.commas(int(pos.y * 3.281)), hud_col, 22, 2, h.font_b)
	h.txt(Vector2(xr, y + 22), "RALT %s" % h.commas(int(agl * 3.281)), WARN if agl < 60.0 and not on_ground else hud_col, 13, 2)
	h.txt(Vector2(xr, y + 44), "VS %+d FPM" % int(vel.y * 196.85), hud_col, 13, 2)
	# heading tape
	var hdg := fposmod(rad_to_deg(atan2(fwd.x, -fwd.z)), 360.0)
	h.txt(Vector2(c.x, 52), "%03d" % int(hdg), hud_col, 18, 1, h.font_b)
	for d in range(-30, 31, 10):
		var hx := c.x + d * 6.0
		var hv := int(round(hdg / 10.0)) * 10 + d
		h.ln(Vector2(hx - fposmod(hdg, 10.0) * 6.0, 60), Vector2(hx - fposmod(hdg, 10.0) * 6.0, 68), Color(hud_col, 0.6), 1.0)
		if d != 0:
			h.txt(Vector2(hx - fposmod(hdg, 10.0) * 6.0, 82), "%02d" % int(posmod(hv, 360) / 10), Color(hud_col, 0.5), 10, 1)
	# stores
	var ys := sz.y - 220.0
	for i in weapons.size():
		var w: Dictionary = weapons[i]
		var sel: bool = i == cur
		var fz: String = _fuze(w)
		var line := "%d %-18s %4d%s" % [i + 1, String(w["name"]), int(w["ammo"]), ("  " + String(main.arsenal.fuze_fx(fz)["tag"])) if fz != "" else ""]
		h.txt(Vector2(sz.x - 330.0, ys + i * 20.0), line, (WARN if int(w["ammo"]) <= 0 else (hud_col if sel else DIM)), 13, 0, h.font_b if sel else h.font)
	# warnings
	var wy := c.y + 80.0
	var blink := fmod(float(main.real_t), 0.5) < 0.32
	if pull_up and blink:
		h.txt(Vector2(c.x, wy), "PULL UP", WARN, 30, 1, h.font_b)
		wy += 34.0
	if stall and blink:
		h.txt(Vector2(c.x, wy), "STALL", WARN, 24, 1, h.font_b)
		wy += 28.0
	if fuel <= 0.0:
		h.txt(Vector2(c.x, wy), "FLAMEOUT  //  GLIDE TO THE FARP", WARN, 18, 1, h.font_b)
		wy += 24.0
	elif bingo:
		h.txt(Vector2(c.x, wy), "BINGO FUEL  //  RTB", WARN, 18, 1, h.font_b)
		wy += 24.0
	if winchester_called:
		h.txt(Vector2(c.x, wy), "WINCHESTER  //  RTB TO REARM", WARN, 16, 1, h.font_b)
		wy += 22.0
	if rearm >= 0.0:
		h.txt(Vector2(c.x, wy), "HOT PITS  //  REARM AND REFUEL %d%%" % int(rearm * 100.0), GOOD, 16, 1, h.font_b)
		h.bar(Rect2(Vector2(c.x - 120, wy + 8), Vector2(240, 6)), rearm, GOOD)
		wy += 30.0
		if rearm >= 1.0:
			h.txt(Vector2(c.x, wy), "FULL UP  //  THROTTLE UP AND LOOK UP TO TAKE OFF", GOOD, 13, 1, h.font_b)
	# the FARP: always marked, with the fuel it'll take to get there
	var af: Dictionary = main.world["airfield"]
	var farp: Vector3 = af["center"]
	h._mark(cam, farp + Vector3.UP * 5.0, "FARP", sz, c, true, GOOD if not bingo else WARN)
	_landing_aid(h, cam, af)
	# Spectre, and the tasking
	h._mark(cam, main.air_pos, "SPECTRE 2-1", sz, c, false, Color(GOOD, 0.7))
	if not task.is_empty():
		var tp: Vector3 = task["pos"]
		h._mark(cam, tp + Vector3.UP * 3.0, "TASK", sz, c, true, Color(1.0, 0.72, 0.26))
		var prog := ""
		if task.has("need"):
			prog = "  //  %d / %d" % [int(task["kills"]), int(task["need"])]
		h.txt(Vector2(c.x, 112), "SPECTRE TASKING  //  %s%s  //  %.1f KM" % [String(task["text"]), prog, pos.distance_to(tp) / 1000.0], Color(1.0, 0.72, 0.26), 15, 1, h.font_b)
	# the refuge and the wave, along the bottom left
	h.txt(Vector2(60, sz.y - 70), "%s %d%%  //  DAY %d WAVE %d  //  CONTACTS %s  //  REQ %s" % [String(main.refuge_name), int(ceil(float(main.integrity))), main.day(), int(main.wave), h.commas(int(main.horde.alive_count) + int(main.to_spawn)), h.commas(int(main.rp))], FG, 14, 0, h.font_b)
	h.bar(Rect2(Vector2(60, sz.y - 62), Vector2(240, 6)), float(main.integrity) / 100.0, FG if float(main.integrity) > 35.0 else WARN)


## Within a few kilometres of the strip and coming down: the runway outlined, and where you are
## against a three-degree glide path.
func _landing_aid(h, cam: Camera3D, af: Dictionary) -> void:
	var c: Vector3 = af["center"]
	var d: Vector3 = af["dir"]
	var dist := Vector2(pos.x - c.x, pos.z - c.z).length()
	if dist > 7000.0 or agl > 900.0 or on_ground:
		return
	var p := Vector3(-d.z, 0.0, d.x)
	var hl: float = float(af["length"]) * 0.5
	var hw: float = float(af["width"]) * 0.5
	var corners := [c + d * hl + p * hw, c + d * hl - p * hw, c - d * hl - p * hw, c - d * hl + p * hw]
	var pts := PackedVector2Array()
	for q in corners:
		if cam.is_position_behind(q):
			return
		pts.append(h.proj(q))
	pts.append(pts[0])
	h.draw_polyline(pts, Color(h.GOOD, 0.8), 1.5)
	# the nearer threshold, and the glide path to it
	var near_end := c - d * hl if (pos - (c - d * hl)).length() < (pos - (c + d * hl)).length() else c + d * hl
	var gd := Vector2(pos.x - near_end.x, pos.z - near_end.z).length()
	var want := gd * tan(deg_to_rad(3.0)) + 15.0
	var dev := pos.y - want
	var word := "ON GLIDEPATH" if absf(dev) < 30.0 else ("HIGH" if dev > 0.0 else "LOW")
	h.txt(Vector2(h.vsz.x * 0.5, h.vsz.y * 0.5 + 150.0), "APPROACH  //  %s  //  %.1f KM  //  %d KT" % [word, gd / 1000.0, int(vel.length() * 1.944)], h.GOOD if word == "ON GLIDEPATH" else h.WARN, 14, 1, h.font_b)
