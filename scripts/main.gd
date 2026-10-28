extends Node3D
## Gunship: Overwatch. You are the sensor operator / fire-control officer of a gunship
## flying a left-hand pylon turn over a stadium full of survivors. The world is real 3D:
## the aircraft actually orbits, the sensor stays locked on a ground point, so the city
## turns beneath you with genuine parallax. You fly it too: throttle, altitude, orbit radius.

const WorldBuilder = preload("res://scripts/world_builder.gd")
const Horde = preload("res://scripts/horde.gd")
const Fx = preload("res://scripts/fx.gd")
const Arsenal = preload("res://scripts/arsenal.gd")
const Sfx = preload("res://scripts/sfx.gd")
const Hud = preload("res://scripts/hud.gd")
const Perks = preload("res://scripts/perks.gd")
const Defences = preload("res://scripts/defences.gd")
const Ops = preload("res://scripts/ops.gd")
const Missions = preload("res://scripts/missions.gd")
const Cas = preload("res://scripts/cas.gd")

const SECTORS :=["NORTH", "NORTHEAST", "EAST", "SOUTHEAST", "SOUTH", "SOUTHWEST", "WEST", "NORTHWEST"]
const FOV_PRESETS := [30.0, 9.0, 2.6, 1.0]
const TIME_SCALES := [1.0, 2.0, 4.0, 8.0]
const TRACK_LIMIT := 4000.0
const PALETTES := ["WHT", "BLK", "IRON", "DISCO"]
const SPEED_MIN := 55.0
const SPEED_MAX := 125.0
const ALT_MIN := 450.0
const ALT_MAX := 3600.0
const R_MAX := 3000.0
const MAX_BANK_DEG := 45.0
const REINFORCE_PRICE := 1500
const SAVE_PATH := "user://pilot.cfg"
const TEST_SAVE_PATH := "user://pilot_autotest.cfg"
const VERSION := "1.6"
# five waves make a day; surviving one repairs the refuge and pays out
const DAY_LEN := 5
const DAY_REPAIR := 20.0

enum State { TITLE, PLAYING, PAUSED, OVER, ARMORY, LOADOUT, PERK }

var state := State.TITLE
var t := 0.0
var real_t := 0.0
var cam: Camera3D

# flight
var theta := 2.2
var speed := 72.0
var cmd_speed := 72.0
var alt := 1150.0
var cmd_alt := 1150.0
var orbit_r := 1350.0
var cmd_r := 1350.0
var bank := 0.0
var bank_limited := false
var air_pos := Vector3.ZERO
var air_vel := Vector3.ZERO
var air_fwd := Vector3.FORWARD
var air_left := Vector3.LEFT
var orbit_center := Vector3.ZERO
var orbit_center_cmd := Vector3.ZERO
var time_scale := 1.0

# sensor
var track := Vector3(330, 0, 40)
var fov := 9.0
var fov_target := 9.0
var aim_point := Vector3.ZERO
var aim_range := 0.0
var shake := 0.0
var flash := 0.0
var whiteout := 0.0
var agc := 0.0
var palette := 0
# false: the IR imager; true: the daylight colour TV camera
var tv_mode := false
var env: Environment
# the settings panel over the title screen or the pause menu: "" or "settings"
var menu_panel := ""
var settings_tab := 0
# the action waiting for a key while rebinding, or ""
var rebinding := ""
# graphics
var fullscreen := false
var vsync := true
var render_scale := 1.0
var msaa := 2
var horde_cap := 80000
var weather_fx := true
# first-sortie tutorial
var tutorial_on := true
var tut_step := 0
var tut_t := 0.0
var tut_mark := 0.0
var tut_cur := -1
const TUT_STEPS := 10
# what the tutorial watches for
var slew_acc := 0.0
var tv_toggles := 0
var armory_opens := 0
# ground operations and the refuge's people
var ops
# objectives inside a wave, danger-close calls and the campaign (missions.gd)
var missions = null
# "gunship": you're Spectre's sensor operator. "cas": you fly the A-10 and the AI flies Spectre (cas.gd)
var mode := "gunship"
var cas = null
var cas_auto_fire := false


func is_playing() -> bool:
	return state == State.PLAYING
var population := 0
var pop0 := 0
# time of day (hours) and weather
var tod := 9.0
var weather := "clear"
var wx := {}              # the current weather's effects, eased toward the target
var wx_target := {}
var light := 1.0          # 0 night .. 1 full day, for the HUD
# controller
var joy_click_cd := 0.0

## Rebindable keys: action -> keycode. Number keys, Esc, F1 and F9 stay fixed.
const DEFAULT_KEYS := {
	"throttle_up": KEY_W, "throttle_down": KEY_S, "climb": KEY_SHIFT, "descend": KEY_CTRL,
	"orbit_in": KEY_A, "orbit_out": KEY_D, "prev_weapon": KEY_Q, "next_weapon": KEY_E,
	"reload": KEY_R, "a10": KEY_G, "armory": KEY_B, "track": KEY_T, "orbit_here": KEY_C,
	"orbit_home": KEY_H, "tac_map": KEY_TAB, "zoom": KEY_Z, "palette": KEY_F, "sensor": KEY_X,
	"declutter": KEY_V, "time_slower": KEY_COMMA, "time_faster": KEY_PERIOD, "fuze": KEY_Y,
}
const KEY_LABELS := {
	"throttle_up": "THROTTLE UP", "throttle_down": "THROTTLE DOWN", "climb": "CLIMB", "descend": "DESCEND",
	"orbit_in": "TIGHTEN ORBIT", "orbit_out": "WIDEN ORBIT", "prev_weapon": "PREVIOUS WEAPON", "next_weapon": "NEXT WEAPON",
	"reload": "RELOAD / RESTOCK", "a10": "A-10 GUN RUN", "armory": "ARMORY", "track": "POINT TRACK", "orbit_here": "ORBIT OVER SENSOR",
	"orbit_home": "ORBIT HOME", "tac_map": "TACTICAL MAP", "zoom": "ZOOM STEP", "palette": "IR PALETTE", "sensor": "IR / TV",
	"declutter": "HUD DECLUTTER", "time_slower": "TIME SLOWER", "time_faster": "TIME FASTER", "fuze": "FUZE MODE",
}
var keys := DEFAULT_KEYS.duplicate()

# weather: effect multipliers. ir: haze distance, gain: IR contrast, tv: TV visibility,
# sun: direct sunlight, fire: fire damage, precip: 0 none, 1 rain, 2 snow, 3 dust
const WEATHER := {
	"clear": {"name": "CLEAR", "ir": 1.0, "gain": 1.0, "tv": 1.0, "sun": 1.0, "fire": 1.0, "precip": 0, "sky": Vector3(1.0, 1.0, 1.0)},
	"overcast": {"name": "OVERCAST", "ir": 0.9, "gain": 0.95, "tv": 0.75, "sun": 0.25, "fire": 1.0, "precip": 0, "sky": Vector3(0.82, 0.84, 0.86)},
	"rain": {"name": "RAIN", "ir": 0.45, "gain": 0.8, "tv": 0.35, "sun": 0.15, "fire": 0.6, "precip": 1, "sky": Vector3(0.66, 0.69, 0.72)},
	"fog": {"name": "FOG", "ir": 0.7, "gain": 0.9, "tv": 0.15, "sun": 0.3, "fire": 0.9, "precip": 0, "sky": Vector3(0.9, 0.91, 0.92)},
	"snow": {"name": "SNOW", "ir": 0.5, "gain": 0.8, "tv": 0.3, "sun": 0.25, "fire": 0.7, "precip": 2, "sky": Vector3(0.92, 0.94, 0.97)},
	"dust": {"name": "SANDSTORM", "ir": 0.35, "gain": 0.75, "tv": 0.2, "sun": 0.35, "fire": 0.9, "precip": 3, "sky": Vector3(0.9, 0.72, 0.5)},
}
# how likely each kind of weather is on each AO
const WEATHER_ODDS := {
	"city": {"clear": 45, "overcast": 25, "rain": 20, "fog": 10},
	"port": {"clear": 40, "overcast": 25, "rain": 20, "fog": 15},
	"river": {"clear": 35, "overcast": 25, "rain": 20, "fog": 20},
	"desert": {"clear": 60, "overcast": 10, "dust": 30},
	"arctic": {"clear": 40, "overcast": 20, "snow": 30, "fog": 10},
	"heaven": {"clear": 35, "overcast": 25, "rain": 25, "fog": 15},
}
var mouse_sens := 1.0
var invert_y := false
var volume := 0.85
# per-channel volume under the master: weapons, explosions, aircraft, radio and alerts
var vol_bus := {"Weapons": 1.0, "Explosions": 1.0, "Aircraft": 1.0, "Radio": 1.0}
# the title screen's AO list: where it's scrolled to (-1 = keep the selected AO in view)
var ao_scroll := -1.0
var zoom_snd_cd := 0.0
var track_lock := -1
var lock_pos := Vector3.ZERO
var tac_open := false
var help_open := false
var hud_mode := 0
var feed: Array = []
var pip_vp: SubViewport
var pip_cam: Camera3D
var pip_rect: TextureRect
var pip_mat: ShaderMaterial
var pip_info: Dictionary = {}
# the munition the seeker camera rides: moved onto a render layer only the PIP camera skips
var pip_node = null
const PIP_HIDE_LAYER := 1 << 19
var refuge_fire_t := 0.0
var shock_at := -1.0
var shock_amp := 0.0

var world: Dictionary
var ao_id := "city"
var ao_base := "city"
var refuge_name := "STADIUM"
var wall_r := 58.0
var arrive := Vector2(60.0, 84.0)
var attract := Vector3.ZERO
var corridors: Array = []
var horde
var fx
var arsenal
var sfx
var hud
var defences
# this wave's record, for the end-of-wave summary
var wave_kills0 := 0
var wave_rp0 := 0
var wave_integrity0 := 100.0
var wave_summary: Dictionary = {}
var post_mat: ShaderMaterial

# campaign
var wave := 0
var wave_active := false
var to_spawn := 0
var spawn_rate := 0.0
var next_clump := 0.0
var intermission := 0.0
var active_corridors: Array = []
var runner_frac := 0.05
var brute_frac := 0.0
# 0-1: how far the late-wave flood has spread to every part of every approach
var flood := 0.0
# bosses due this wave: [sim time, boss definition]
var boss_queue: Array = []
# shenanigans: now and then a wave comes with a twist
const EVENTS := ["gold", "meteors", "supply", "blood", "pinata"]
var wave_event := ""
var event_until := 0.0
var event_acc := 0.0
var rp_event := 1.0
var speed_event := 1.0
# dev switches: a standing farm of dummies, and the two-click career wipe
const FARM_N := 10000
var dev_farm := false
var reset_armed := -100.0
var resetting := false
var integrity := 100.0
var rp := 0
var rp_total := 0
var kills := 0
var a10_kills := 0
var nukes_used := 0
var shots_fired := 0
var best_multi := 0
var over_t := 0.0
var over_reason := ""
var banner := ""
var banner_t := -100.0
var popups: Array = []
var armory_after_wave := false
var armory_tab := 0
var best: Dictionary = {}
var save_t := 0.0
var sortie_kills := 0

# progression modifiers: permanent aircraft upgrades and this sortie's roguelite perks
var stats: Dictionary = {}
var upg: Dictionary = {}
var perks_taken: Array = []
var perk_offers: Array = []
var reroll_cost := 400
var perk_rng := RandomNumberGenerator.new()

# radio
var radio_q: Array = []
var radio_cur: Dictionary = {}
var radio_t := 0.0
var praise_cd := 0.0
var danger_cd := 0.0
var breach_cd := 0.0
var low_cd := 0.0
var alarm_cd := 0.0

# automated smoke test: run with  -- --autotest [--stress]
var autotest := false
var auto_step := 0
var prof_horde := 0
var prof_arsenal := 0
var prof_frames := 0


func _ready() -> void:
	randomize()
	autotest = "--autotest" in OS.get_cmdline_user_args()
	scorch_img = Image.create_empty(SCORCH_N, SCORCH_N, false, Image.FORMAT_R8)
	scorch_tex = ImageTexture.create_from_image(scorch_img)
	RenderingServer.global_shader_parameter_set("scorch_map", scorch_tex)
	RenderingServer.global_shader_parameter_set("grid_power", 1.0)
	RenderingServer.global_shader_parameter_set("flare_a", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set("flare_b", Vector4.ZERO)
	_setup_env()
	cam = Camera3D.new()
	cam.near = 2.0
	cam.far = 16000.0
	_apply_fov(cam, fov)
	add_child(cam)
	cam.current = true

	ao_id = String(Engine.get_meta("ao", "city"))
	if Engine.has_meta("ao_scroll"):
		ao_scroll = float(Engine.get_meta("ao_scroll"))
		Engine.remove_meta("ao_scroll")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ao="):
			ao_id = arg.substr(5)
	var wb := WorldBuilder.new()
	world = wb.build(self, ao_id)
	ao_base = String(world["base"])
	corridors = world["corridors"]
	refuge_name = world["refuge"]
	wall_r = world["wall_r"]
	arrive = world["arrive"]
	# the title view looks out along the first approach, where the hordes mass
	var c0: Dictionary = corridors[0]
	var a0: float = c0["ang"]
	attract = Vector3(cos(a0), 0.0, sin(a0)) * maxf(1500.0, float(c0["rmin"]) + 300.0)
	track = attract
	RenderingServer.global_shader_parameter_set("haze_heat", float(world["haze_heat"]))
	RenderingServer.global_shader_parameter_set("haze_dist", float(world["haze_dist"]))
	RenderingServer.global_shader_parameter_set("sun_dir", (world["sun"] as Vector3).normalized())
	RenderingServer.global_shader_parameter_set("sky_col", world["sky"])
	RenderingServer.global_shader_parameter_set("tv_fog", float(world["tv_fog"]))
	RenderingServer.global_shader_parameter_set("ao_style", float(world["ground"]))

	fx = Fx.new()
	add_child(fx)
	horde = Horde.new()
	horde.fx = fx
	horde.main = self
	add_child(horde)
	horde.setup_stadium(world["survivor_spots"], world["defender_spots"])
	horde.garrison = float(world.get("garrison", 1.0))
	sfx = Sfx.new()
	add_child(sfx)
	arsenal = Arsenal.new()
	arsenal.main = self
	add_child(arsenal)
	defences = Defences.new()
	defences.main = self
	add_child(defences)
	ops = Ops.new()
	ops.main = self
	add_child(ops)
	missions = Missions.new()
	missions.main = self
	add_child(missions)
	pop0 = (world["survivor_spots"] as Array).size()
	population = pop0
	wx = (WEATHER["clear"] as Dictionary).duplicate()
	wx_target = wx.duplicate()
	_setup_screen()
	if autotest:
		DirAccess.remove_absolute(TEST_SAVE_PATH)
	perk_rng.randomize()
	recalc_stats()
	load_pilot()
	if bool(world.get("iron", false)):
		_iron_begin()
	_apply_sensor()
	_apply_graphics()

	_update_aircraft(0.0)
	# the hordes are already on the move when you arrive on station
	if bool(world.get("torment", false)):
		# out on the horizon, the next tide is already gathering
		_spawn_tide(3000, 2500.0, 2580.0)
	else:
		for k in 26:
			_spawn_clump(corridors[randi() % corridors.size()], randi_range(30, 90))
	sfx.start_engine()
	if autotest and "--tour" in OS.get_cmdline_user_args():
		return
	if autotest:
		_autotest_setup()


func _exit_tree() -> void:
	if state != State.TITLE:
		save_pilot()
	# let go of the scorch map, or the global shader parameter keeps it alive past exit
	RenderingServer.global_shader_parameter_set("scorch_map", null)
	scorch_tex = null
	scorch_img = null
	for rid in world.get("bodies", []):
		PhysicsServer3D.free_rid(rid)
	# the landmarks keep their own collision (a mission may already have knocked one down)
	for lm in world.get("landmarks", []):
		if lm["alive"]:
			PhysicsServer3D.free_rid(lm["body"])
			PhysicsServer3D.free_rid(lm["shape"])


# ---------------------------------------------------------------- pilot career
## Everything you buy is yours on every AO and survives quitting the game:
## requisition, lifetime clearance, owned systems, your loadout, your best waves.
func _save_path() -> String:
	return TEST_SAVE_PATH if autotest else SAVE_PATH


func load_pilot() -> void:
	var cf := ConfigFile.new()
	if cf.load(_save_path()) != OK:
		return
	rp = int(cf.get_value("pilot", "rp", 0))
	rp_total = int(cf.get_value("pilot", "rp_total", 0))
	best = cf.get_value("pilot", "best", {})
	for id in cf.get_value("pilot", "owned", PackedStringArray()):
		var w: Dictionary = arsenal.by_id(String(id))
		if not w.is_empty():
			w["owned"] = true
	upg = cf.get_value("pilot", "upgrades", {})
	pinned = String(cf.get_value("pilot", "pinned", ""))
	evacuated = cf.get_value("pilot", "evacuated", {})
	rank_shown = clearance()
	recalc_stats()
	var lo: Array = []
	for id in cf.get_value("pilot", "loadout", []):
		var w: Dictionary = arsenal.by_id(String(id))
		if not w.is_empty() and w["owned"] and lo.size() < arsenal.slots():
			lo.append(String(id))
	if not lo.is_empty():
		arsenal.loadout = lo
	mouse_sens = float(cf.get_value("settings", "mouse_sens", mouse_sens))
	invert_y = bool(cf.get_value("settings", "invert_y", invert_y))
	volume = float(cf.get_value("settings", "volume", volume))
	var vb: Dictionary = cf.get_value("settings", "vol_bus", {})
	for b in vb:
		if vol_bus.has(b):
			vol_bus[b] = clampf(float(vb[b]), 0.0, 1.0)
	palette = int(cf.get_value("settings", "palette", palette))
	dev_farm = bool(cf.get_value("settings", "dev_farm", dev_farm))
	tv_mode = bool(cf.get_value("settings", "tv_mode", tv_mode))
	fullscreen = bool(cf.get_value("settings", "fullscreen", fullscreen))
	vsync = bool(cf.get_value("settings", "vsync", vsync))
	render_scale = float(cf.get_value("settings", "render_scale", render_scale))
	msaa = int(cf.get_value("settings", "msaa", msaa))
	horde_cap = int(cf.get_value("settings", "horde_cap", horde_cap))
	weather_fx = bool(cf.get_value("settings", "weather_fx", weather_fx))
	tutorial_on = bool(cf.get_value("settings", "tutorial", tutorial_on))
	var saved_keys: Dictionary = cf.get_value("settings", "keys", {})
	for a in saved_keys:
		if keys.has(a):
			keys[a] = int(saved_keys[a])
	_apply_volume()


func _apply_volume() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.001)))
	for b in vol_bus:
		var bi := AudioServer.get_bus_index(String(b))
		if bi >= 0:
			AudioServer.set_bus_volume_db(bi, linear_to_db(maxf(float(vol_bus[b]), 0.001)))
			AudioServer.set_bus_mute(bi, float(vol_bus[b]) <= 0.0)


func save_pilot() -> void:
	if resetting:
		return
	if wave > int(best.get(ao_id, 0)):
		best[ao_id] = wave
	var cf := ConfigFile.new()
	# in Iron Torment the career waits outside: only the XP (lifetime RP) and the best wave go home
	var keep: Dictionary = iron_stash if iron else {"rp": rp, "owned": arsenal.owned_ids(), "loadout": arsenal.loadout, "upgrades": upg, "pinned": pinned}
	cf.set_value("pilot", "rp", keep["rp"])
	cf.set_value("pilot", "rp_total", rp_total)
	cf.set_value("pilot", "owned", keep["owned"])
	cf.set_value("pilot", "loadout", keep["loadout"])
	cf.set_value("pilot", "best", best)
	cf.set_value("pilot", "upgrades", keep["upgrades"])
	cf.set_value("pilot", "pinned", keep["pinned"])
	cf.set_value("pilot", "evacuated", evacuated)
	cf.set_value("settings", "mouse_sens", mouse_sens)
	cf.set_value("settings", "invert_y", invert_y)
	cf.set_value("settings", "volume", volume)
	cf.set_value("settings", "vol_bus", vol_bus)
	cf.set_value("settings", "palette", palette)
	cf.set_value("settings", "dev_farm", dev_farm)
	cf.set_value("settings", "tv_mode", tv_mode)
	cf.set_value("settings", "fullscreen", fullscreen)
	cf.set_value("settings", "vsync", vsync)
	cf.set_value("settings", "render_scale", render_scale)
	cf.set_value("settings", "msaa", msaa)
	cf.set_value("settings", "horde_cap", horde_cap)
	cf.set_value("settings", "weather_fx", weather_fx)
	cf.set_value("settings", "tutorial", tutorial_on)
	cf.set_value("settings", "keys", keys)
	cf.save(_save_path())


func _apply_graphics() -> void:
	if autotest:
		horde.max_alive = horde_cap
		return
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	var vp := get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if render_scale < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = render_scale
	vp.msaa_3d = Viewport.MSAA_DISABLED if msaa == 0 else (Viewport.MSAA_2X if msaa == 2 else Viewport.MSAA_4X)
	horde.max_alive = horde_cap


## The name of the key bound to an action, for the HUD and the tutorial.
func key_name(action: String) -> String:
	return OS.get_keycode_string(int(keys.get(action, KEY_NONE)))


func _key_action(code: int) -> String:
	for a in keys:
		if int(keys[a]) == code:
			return String(a)
	return ""


## Iron Torment: the career is set aside for the sortie. You fly with a GAU-8 and nothing else,
## no requisition and no upgrades, and buy everything else with what you earn wave by wave.
## None of it comes home: save_pilot() writes the stashed career, plus the XP you earned.
var iron := false
var iron_stash := {}


func _iron_begin() -> void:
	iron = true
	iron_stash = {"rp": rp, "owned": arsenal.owned_ids(), "loadout": arsenal.loadout.duplicate(), "upgrades": upg.duplicate(), "pinned": pinned}
	rp = 0
	for w in arsenal.weapons:
		w["owned"] = w["id"] == "gau8"
	arsenal.loadout = ["gau8"]
	arsenal.cur = 0
	upg = {}
	pinned = ""
	recalc_stats()
	arsenal.resupply()


## Smoke of Their Torment: they walk at the blood moon's pace, all of them, always.
const TORMENT_PACE := 1.4


## n infected spread evenly across the whole front, r0..r1 out, every one at the same pace, so
## the horde comes in as one tide instead of a scatter of crowds.
func _spawn_tide(n: int, r0: float, r1: float) -> void:
	var c: Dictionary = corridors[0]
	var ang0: float = c["ang"]
	var half: float = float(c.get("half", 0.4))
	var v := 1.15 * (1.0 + wave * 0.01) * stat("horde_speed") * TORMENT_PACE
	for i in n:
		var a := ang0 + randf_range(-half, half)
		var r := randf_range(r0, r1)
		var roll := randf()
		var kind := 2 if roll < 0.012 else (1 if roll < 0.1 else 0)
		if not horde.spawn(cos(a) * r, sin(a) * r, v * randf_range(0.97, 1.03), kind, randf_range(arrive.x, arrive.y)):
			return


## Wipe the career: requisition, clearance, owned systems, loadout, best waves and aircraft
## upgrades. Settings survive. Then start again from the title screen.
func reset_progress() -> void:
	resetting = true
	var cf := ConfigFile.new()
	cf.load(_save_path())
	if cf.has_section("pilot"):
		cf.erase_section("pilot")
	cf.save(_save_path())
	get_tree().reload_current_scene()


## Dev farm: keep FARM_N dummies standing on the approaches to be shot for requisition.
## They never move, never reach the wall and never hold up a wave.
func _farm_tick() -> void:
	if not dev_farm or corridors.is_empty():
		return
	var need: int = FARM_N - int(horde.farm_alive)
	for k in mini(need, 400):
		var c: Dictionary = corridors[randi() % corridors.size()]
		var ang: float = c["ang"]
		var lat := 0.0
		if int(c["type"]) == 0:
			var hw: float = c["hw"]
			lat = randf_range(-hw + 3.0, hw - 3.0)
		else:
			ang += randf_range(-float(c["half"]), float(c["half"]))
		var r := randf_range(maxf(float(c["rmin"]) + 20.0, 500.0), 2600.0)
		var radial := Vector2(cos(ang), sin(ang))
		var p := radial * r + Vector2(-radial.y, radial.x) * lat
		if not horde.spawn(p.x, p.y, 0.0, horde.FARM, arrive.y):
			return


## A progression stat: multipliers default to 1.0, "add_" stats to 0. See perks.gd.
func stat(k: String) -> float:
	if stats.has(k):
		return stats[k]
	return 0.0 if k.begins_with("add_") else 1.0


## Fold aircraft upgrades and this sortie's perks into `stats`.
func recalc_stats() -> void:
	var s := {}
	var apply := func(mods: Dictionary, times: int) -> void:
		if times <= 0:
			return
		for key in mods:
			var v: float = mods[key]
			if String(key).begins_with("add_"):
				s[key] = float(s.get(key, 0.0)) + v * times
			else:
				s[key] = float(s.get(key, 1.0)) * pow(maxf(1.0 + v, 0.05), times)
	for u in Perks.UPGRADES:
		apply.call(u["mods"], int(upg.get(u["id"], 0)))
	for u in Perks.REFUGE:
		apply.call(u["mods"], int(upg.get(u["id"], 0)))
	for pid in perks_taken:
		var p: Dictionary = Perks.perk(String(pid))
		if not p.is_empty():
			apply.call(p["mods"], 1)
	stats = s
	if horde:
		horde.chain_p = stat("add_chain")
	_apply_population()
	if defences:
		defences.rebuild()


## Everyone brought in joins the defence: a bigger garrison, more hands on the repairs,
## and more people visible inside the walls.
func add_population(n: int) -> void:
	population += n
	_apply_population()


func _apply_population() -> void:
	var extra := maxi(0, population - pop0)
	if horde:
		horde.garrison = float(world.get("garrison", 1.0)) * stat("garrison") * (1.0 + extra / 400.0)
	if defences:
		defences.set_people(extra)


func upgrade_level(id: String) -> int:
	return int(upg.get(id, 0))


func buy_upgrade(id: String) -> void:
	var u: Dictionary = Perks.upgrade(id)
	if u.is_empty():
		return
	var lvl := upgrade_level(id)
	var cost := Perks.upgrade_cost(u, lvl)
	if lvl >= int(u["max"]) or rp < cost:
		sfx.play("switch", -8.0, 0.7)
		return
	rp -= cost
	upg[id] = lvl + 1
	recalc_stats()
	sfx.play("buy", -2.0)
	if Perks.REFUGE.has(u):
		radio("ENGINEERS", "%s at level %d. It goes up at every refuge you defend." % [String(u["name"]), lvl + 1])
	else:
		radio("CREW CHIEF", "%s upgraded to level %d. She'll fly better for it." % [String(u["name"]), lvl + 1])
	save_pilot()


## After every wave: three roguelite perks, pick one. They last for the rest of the sortie.
func offer_perks(day_end := false) -> void:
	perk_offers = Perks.roll_offers(perk_rng, day_end)
	state = State.PERK
	sfx.stop_all_guns()
	if not autotest:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func take_perk(i: int) -> void:
	if i < 0 or i >= perk_offers.size():
		return
	var p: Dictionary = Perks.perk(String(perk_offers[i]))
	perks_taken.append(String(perk_offers[i]))
	recalc_stats()
	sfx.play("buy", -2.0, 1.2)
	radio("TOC", "%s. %s" % [String(p["name"]).capitalize(), String(p["desc"])])
	perk_offers = []
	open_armory(true)


func reroll_perks() -> void:
	if rp < reroll_cost:
		sfx.play("switch", -8.0, 0.7)
		return
	rp -= reroll_cost
	reroll_cost = int(reroll_cost * 1.6)
	perk_offers = Perks.roll_offers(perk_rng)
	sfx.play("switch", -6.0, 1.3)


## Clearance level 1-8, earned by lifetime requisition; gates what the armory will sell.
func clearance() -> int:
	var lvl := 1
	for i in arsenal.TIER_RP.size():
		if rp_total >= int(arsenal.TIER_RP[i]):
			lvl = i + 1
	return lvl


## IR imager or colour TV: shaders switch on a global, and the sky goes from cold black to daylight.
func _apply_sensor() -> void:
	RenderingServer.global_shader_parameter_set("color_mode", 1.0 if tv_mode else 0.0)
	if env:
		var sky: Vector3 = world.get("sky", Vector3(0.66, 0.74, 0.84))
		env.background_color = Color(sky.x, sky.y, sky.z) if tv_mode else Color(0.012, 0.012, 0.012)


func _setup_env() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.012, 0.012)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _setup_screen() -> void:
	var post_layer := CanvasLayer.new()
	post_layer.layer = 0
	add_child(post_layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_mat = ShaderMaterial.new()
	post_mat.shader = load("res://shaders/post.gdshader")
	rect.material = post_mat
	post_layer.add_child(rect)
	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 1
	add_child(hud_layer)
	hud = Hud.new()
	hud.main = self
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# picture-in-picture weapon view: a second camera riding the newest guided munition
	pip_vp = SubViewport.new()
	pip_vp.size = Vector2i(480, 300)
	pip_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	pip_vp.msaa_3d = Viewport.MSAA_2X
	# only the main sensor hears the battlefield; the seeker camera is silent
	pip_vp.audio_listener_enable_3d = false
	add_child(pip_vp)
	pip_cam = Camera3D.new()
	pip_cam.near = 0.5
	pip_cam.far = 16000.0
	pip_cam.fov = 20.0
	pip_cam.cull_mask = 0xFFFFF & ~PIP_HIDE_LAYER
	pip_vp.add_child(pip_cam)
	pip_cam.current = true
	pip_rect = TextureRect.new()
	pip_rect.texture = pip_vp.get_texture()
	pip_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pip_rect.stretch_mode = TextureRect.STRETCH_SCALE
	pip_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pip_mat = ShaderMaterial.new()
	pip_mat.shader = load("res://shaders/pip.gdshader")
	pip_rect.material = pip_mat
	pip_rect.visible = false
	hud_layer.add_child(pip_rect)
	hud_layer.add_child(hud)


func _update_pip() -> void:
	pip_info = arsenal.pip_target() if state == State.PLAYING else {}
	# the camera sits in the munition's nose, so hide that munition's own body from it
	_set_pip_node(pip_info.get("node", null))
	if pip_info.is_empty():
		if pip_rect.visible:
			pip_rect.visible = false
			pip_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	var s: float = hud.ui_scale()
	var sz := Vector2(360, 225) * s
	pip_rect.position = Vector2(get_viewport().get_visible_rect().size.x * 0.5 - sz.x * 0.5, 40.0 * s)
	pip_rect.size = sz
	pip_rect.visible = true
	pip_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var p: Vector3 = pip_info["pos"]
	var look: Vector3 = pip_info["look"]
	var d := look - p
	if d.length() > 1.0:
		var up := Vector3.UP if absf(d.normalized().y) < 0.98 else Vector3.FORWARD
		pip_cam.look_at_from_position(p, look, up)
	# the seeker zooms as it closes, keeping roughly 120 m of ground in view
	pip_cam.fov = clampf(rad_to_deg(2.0 * atan(60.0 / maxf(float(pip_info["range"]), 1.0))), 3.0, 50.0)
	pip_mat.set_shader_parameter("palette", palette)
	pip_mat.set_shader_parameter("t", real_t)


## Move the ridden munition onto the layer the seeker camera doesn't render (the main sensor
## still sees it), and put the previous one back.
func _set_pip_node(n) -> void:
	if is_instance_valid(pip_node):
		if pip_node == n:
			return
		pip_node.layers = 1
	pip_node = n
	if is_instance_valid(n):
		n.layers = PIP_HIDE_LAYER


# ---------------------------------------------------------------- aircraft
## The tightest orbit the aircraft can hold at this speed without exceeding the bank limit.
func min_radius(v: float) -> float:
	return maxf(450.0, v * v / (9.8 * tan(deg_to_rad(MAX_BANK_DEG))))


func _flight_input(dt: float) -> void:
	if state != State.PLAYING or autotest or mode == "cas":
		return
	if Input.is_key_pressed(keys["throttle_up"]) or Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_UP):
		cmd_speed = minf(SPEED_MAX * stat("speed"), cmd_speed + 18.0 * dt)
	if Input.is_key_pressed(keys["throttle_down"]) or Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_DOWN):
		cmd_speed = maxf(SPEED_MIN, cmd_speed - 18.0 * dt)
	if Input.is_key_pressed(keys["climb"]):
		cmd_alt = minf(ALT_MAX, cmd_alt + 260.0 * dt)
	if Input.is_key_pressed(keys["descend"]):
		cmd_alt = maxf(ALT_MIN, cmd_alt - 260.0 * dt)
	if Input.is_key_pressed(keys["orbit_in"]):
		cmd_r = maxf(min_radius(speed), cmd_r - 320.0 * dt)
	if Input.is_key_pressed(keys["orbit_out"]):
		cmd_r = minf(R_MAX, cmd_r + 320.0 * dt)
	# controller: right stick flies the aircraft (up/down altitude, left/right orbit radius)
	var rs := _stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y)
	if rs != Vector2.ZERO:
		cmd_alt = clampf(cmd_alt - rs.y * 260.0 * dt, ALT_MIN, ALT_MAX)
		cmd_r = clampf(cmd_r + rs.x * 320.0 * dt, min_radius(speed), R_MAX)


func _update_aircraft(dt: float) -> void:
	# a C-130 airframe: gentle acceleration, a sensible climb rate, wide turns at speed
	speed = move_toward(speed, cmd_speed, 4.0 * dt)
	alt = move_toward(alt, cmd_alt, 14.0 * stat("climb") * dt)
	var rmin := min_radius(speed)
	bank_limited = cmd_r < rmin
	if bank_limited:
		cmd_r = rmin
	orbit_r = move_toward(orbit_r, cmd_r, 30.0 * dt)
	bank = rad_to_deg(atan(speed * speed / (9.8 * orbit_r)))
	theta -= speed / orbit_r * dt
	# repositioning the orbit: the whole pylon turn drifts at most at the aircraft's speed
	orbit_center = orbit_center.move_toward(orbit_center_cmd, speed * 0.9 * dt)
	var c := Vector3(cos(theta), 0.0, sin(theta))
	air_pos = orbit_center + c * orbit_r + Vector3(0.0, alt + sin(t * 0.21) * 6.0, 0.0)
	air_fwd = Vector3(sin(theta), 0.0, -cos(theta))
	air_vel = air_fwd * speed
	air_left = -c


func sensor_pos() -> Vector3:
	return air_pos + air_fwd * 10.0 + air_left * 1.5 + Vector3.DOWN * 2.0


## Weapon mount in aircraft coordinates: x = toward the left wing, y = up, z = forward.
func mount_pos(_off: Vector3) -> Vector3:
	# every weapon fires from just under the sensor, so rounds leave from the middle of the picture
	return sensor_pos() + Vector3.DOWN * 3.0


func heading_deg() -> float:
	return fposmod(rad_to_deg(atan2(air_fwd.x, -air_fwd.z)), 360.0)


func kick(amount: float) -> void:
	shake = maxf(shake, amount)


## Godot's perspective camera refuses anything under 1 degree, and the sensor zooms deeper than
## that. A frustum projection of the same height gives an identical picture at any field of view.
func _apply_fov(c: Camera3D, deg: float) -> void:
	c.projection = Camera3D.PROJECTION_FRUSTUM
	c.frustum_offset = Vector2.ZERO
	c.size = 2.0 * c.near * tan(deg_to_rad(clampf(deg, 0.05, 170.0)) * 0.5)


func _update_camera(dt: float) -> void:
	fov = lerpf(fov, fov_target, 1.0 - exp(-dt * 6.0))
	_apply_fov(cam, fov)
	cam.look_at_from_position(sensor_pos(), track, Vector3.UP)
	# the turret is stabilised, not perfect: airframe vibration and turbulence leak through
	var j := 0.00009 + shake * 0.0035
	var jp := (sin(real_t * 1.3) * 0.5 + sin(real_t * 2.9 + 1.7) * 0.3 + randf_range(-1.0, 1.0) * 0.25) * j
	var jy := (sin(real_t * 1.1 + 0.4) * 0.5 + sin(real_t * 3.7) * 0.3 + randf_range(-1.0, 1.0) * 0.25) * j
	cam.rotate_object_local(Vector3.RIGHT, jp)
	cam.rotate_object_local(Vector3.UP, jy)
	shake *= exp(-dt * 4.0)


func _slew(rel: Vector2) -> void:
	slew_acc += rel.length()
	if track_lock >= 0:
		if rel.length() < 6.0:
			return
		_unlock(false)
	if invert_y:
		rel.y = -rel.y
	var h := get_viewport().get_visible_rect().size.y
	var k := deg_to_rad(fov) / h * mouse_sens
	var sp := sensor_pos()
	var dir := (track - sp).normalized()
	var right := dir.cross(Vector3.UP).normalized()
	dir = dir.rotated(Vector3.UP, -rel.x * k)
	dir = dir.rotated(right, -rel.y * k).normalized()
	if dir.y > -0.15:
		dir.y = -0.15
		dir = dir.normalized()
	var np := sp + dir * (-sp.y / dir.y)
	var flat := Vector2(np.x, np.z)
	if flat.length() > TRACK_LIMIT:
		flat = flat.normalized() * TRACK_LIMIT
	track = Vector3(flat.x, 0.0, flat.y)


# ---------------------------------------------------------------- fire control
## Where to send a weapon with time of flight `tof`. With a point track, the computer
## leads the target: the horde's motion is analytic, so the prediction is exact.
func fire_point(tof: float) -> Vector3:
	if track_lock < 0 or not horde.z_alive[track_lock]:
		return aim_point
	var now: Vector2 = horde.pos_of(track_lock)
	var then: Vector2 = horde.pos_at(track_lock, t + tof)
	return aim_point + Vector3(then.x - now.x, 0.0, then.y - now.y)


## T / middle mouse: lock the sensor onto the infected nearest the crosshair and follow it.
func toggle_track() -> void:
	if track_lock >= 0:
		_unlock(true)
		return
	var i: int = horde.nearest(aim_point, 40.0)
	if i < 0:
		sfx.play("switch", -8.0, 0.6)
		return
	track_lock = i
	sfx.play("lock", -8.0)


func _unlock(sound: bool) -> void:
	track_lock = -1
	if sound:
		sfx.play("switch", -8.0, 0.8)


func _update_track() -> void:
	if track_lock < 0:
		return
	if not horde.z_alive[track_lock]:
		# the target died: the tracker hands off to the nearest body in the same crowd
		var i: int = horde.nearest(lock_pos, 30.0)
		if i < 0:
			_unlock(true)
			return
		track_lock = i
	var p: Vector2 = horde.pos_of(track_lock)
	lock_pos = Vector3(p.x, 0.0, p.y)
	track = track.lerp(lock_pos, 0.35)


## C: fly the orbit over the sensor point. H: back over the refuge.
func set_orbit_center(p: Vector3) -> void:
	var flat := Vector2(p.x, p.z)
	if flat.length() > 3000.0:
		flat = flat.normalized() * 3000.0
	orbit_center_cmd = Vector3(flat.x, 0.0, flat.y)
	sfx.play("beep", -8.0, 0.9)
	radio("PILOT", "Copy, moving the orbit. %.1f kilometres to reposition." % (orbit_center.distance_to(orbit_center_cmd) / 1000.0))


func cycle_time(step: int) -> void:
	var i := TIME_SCALES.find(time_scale)
	var ni := clampi(i + step, 0, TIME_SCALES.size() - 1)
	if ni > 0 and horde.arrived_count > 0:
		ni = 0
		radio("PILOT", "Negative on time compression, they're at the wall.")
	time_scale = TIME_SCALES[ni]
	sfx.play("switch", -8.0, 0.8 + ni * 0.15)


func raycast(a: Vector3, b: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b)
	return get_world_3d().direct_space_state.intersect_ray(q)


func _update_aim() -> void:
	var from := cam.global_position
	var dir := -cam.global_transform.basis.z
	var hit := raycast(from, from + dir * 12000.0)
	if not hit.is_empty():
		aim_point = hit["position"]
		aim_normal = hit["normal"]
	else:
		aim_point = track
		aim_normal = Vector3.UP
	aim_range = from.distance_to(aim_point)


# ---------------------------------------------------------------- line of fire
## Can the guns actually reach what we're aiming at? A tracked target can walk behind a building,
## and a crowd can be standing in a street the sensor can only see the rooftops of. A few times a
## second: check the line from the gun to the target, mark where it's blocked, and look ahead
## round the orbit for where the line clears. orbit_vis holds that for 16 points round the orbit
## (1 = clear), for the radar.
var aim_normal := Vector3.UP
var los_masked := false
var los_reason := ""
var los_clear_in := -1.0
var los_block := Vector3.INF
var los_target := Vector3.INF
var los_t := 0.0
var orbit_vis := PackedByteArray()


func _update_los(delta: float) -> void:
	los_t -= delta
	if los_t > 0.0:
		return
	los_t = 0.2
	los_masked = false
	los_block = Vector3.INF
	los_clear_in = -1.0
	los_target = Vector3.INF
	if state != State.PLAYING:
		orbit_vis.clear()
		return
	var w: Dictionary = arsenal.current()
	if not (String(w["kind"]) in ["rotary", "auto", "cannon", "rail", "laser", "missile", "rockets", "davy"]):
		orbit_vis.clear()
		return
	var muzzle: Vector3 = mount_pos(w["off"])
	var target := aim_point
	if track_lock >= 0:
		target = lock_pos + Vector3.UP * 0.9
		var blk := los_blocked(muzzle, target)
		if blk != Vector3.INF:
			los_masked = true
			los_block = blk
			los_reason = "TRACK MASKED"
	elif aim_point.y > 1.5 and aim_normal.y < 0.95 and not _on_nest(aim_point):
		# the sensor's line ends on a structure; is there a crowd on the ground behind it?
		var from := cam.global_position
		var d := (aim_point - from).normalized()
		if d.y < -0.02:
			var g := from + d * (-from.y / d.y)
			if g.distance_to(aim_point) > 8.0 and horde.count_near(g, 25.0, true) > 0:
				target = g + Vector3.UP * 0.9
				los_masked = true
				los_block = aim_point
				los_reason = "TARGET BEHIND STRUCTURE"
	los_target = target
	# round the orbit, the way we're flying: where does the line clear?
	orbit_vis.resize(16)
	var first := -1
	for k in 16:
		var th := theta - TAU * float(k) / 16.0
		var p := orbit_center + Vector3(cos(th) * orbit_r, alt - 5.0, sin(th) * orbit_r)
		var clear := los_blocked(p, target) == Vector3.INF
		orbit_vis[k] = 1 if clear else 0
		if clear and first < 0 and k > 0:
			first = k
	if los_masked and first > 0:
		los_clear_in = TAU * float(first) / 16.0 * orbit_r / maxf(speed, 1.0)


## Is p on the building that's the nest right now? (Then the structure IS the target.)
func _on_nest(p: Vector3) -> bool:
	if missions.obj.get("kind", "") != "nest":
		return false
	var lm: Dictionary = missions.obj["lm"]
	var size: Vector3 = lm["size"]
	return Vector2(p.x - float(lm["pos"].x), p.z - float(lm["pos"].z)).length() < maxf(size.x, size.z) * 0.75


## Where the straight line from a to b first runs into something short of b, or Vector3.INF.
func los_blocked(a: Vector3, b: Vector3) -> Vector3:
	var hit := raycast(a, b)
	if hit.is_empty():
		return Vector3.INF
	var p: Vector3 = hit["position"]
	return Vector3.INF if p.distance_to(b) < 5.0 else p


# ---------------------------------------------------------------- input
func _unhandled_input(e: InputEvent) -> void:
	if autotest:
		return
	var motion := e as InputEventMouseMotion
	var button := e as InputEventMouseButton
	var key := e as InputEventKey
	var jb := e as InputEventJoypadButton
	# the unlock card: any click, key or button takes it away (after a beat, so it isn't skipped by accident)
	if not unlock_card.is_empty():
		var any_press := (button != null and button.pressed) or (key != null and key.pressed and not key.echo) or (jb != null and jb.pressed)
		if any_press and real_t - float(unlock_card["t"]) > 0.6:
			unlock_card = {}
			sfx.play("switch", -8.0, 1.1)
		if any_press:
			return
	if jb and jb.pressed:
		_joy_button(jb.button_index)
		return
	if mode == "cas" and state == State.PLAYING and _cas_input(motion, button, key):
		return
	if motion:
		if state == State.PLAYING and not tac_open and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_slew(motion.relative)
	elif button and button.pressed:
		if state == State.PLAYING and tac_open:
			# tactical map: left-click slews the sensor there, right-click moves the orbit there
			if button.button_index == MOUSE_BUTTON_LEFT:
				_menu_click(button.position)
			elif button.button_index == MOUSE_BUTTON_RIGHT:
				var g: Vector3 = hud.tac_to_world(button.position)
				if g != Vector3.INF:
					set_orbit_center(g)
			return
		match button.button_index:
			MOUSE_BUTTON_LEFT:
				_menu_click(button.position)
			MOUSE_BUTTON_RIGHT:
				if state == State.PLAYING:
					_cycle_zoom()
			MOUSE_BUTTON_MIDDLE:
				if state == State.PLAYING:
					toggle_track()
			MOUSE_BUTTON_WHEEL_UP:
				if state == State.PLAYING:
					_zoom(0.84)
				elif state == State.TITLE and menu_panel == "":
					ao_scroll = maxf(hud.ao_scroll_now - 60.0, 0.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				if state == State.PLAYING:
					_zoom(1.19)
				elif state == State.TITLE and menu_panel == "":
					ao_scroll = hud.ao_scroll_now + 60.0
	elif key and key.pressed and not key.echo:
		if rebinding != "":
			_rebind(key.keycode)
			return
		if state == State.PERK:
			if key.keycode >= KEY_1 and key.keycode <= KEY_3:
				take_perk(key.keycode - KEY_1)
			elif key.keycode == KEY_R:
				reroll_perks()
			return
		if state == State.ARMORY:
			if key.keycode in [keys["armory"], KEY_ESCAPE, KEY_ENTER, KEY_SPACE]:
				close_armory()
			elif key.keycode >= KEY_1 and key.keycode <= KEY_9:
				armory_tab = key.keycode - KEY_1
			elif key.keycode == KEY_0:
				armory_tab = 9
			return
		if state == State.LOADOUT:
			if key.keycode in [KEY_ENTER, KEY_SPACE]:
				menu_action("launch")
			elif key.keycode == KEY_ESCAPE:
				state = State.TITLE
			elif key.keycode >= KEY_1 and key.keycode <= KEY_9:
				armory_tab = key.keycode - KEY_1
			elif key.keycode == KEY_0:
				armory_tab = 9
			return
		if state == State.TITLE:
			var idx := ao_index()
			if menu_panel != "":
				if key.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_SPACE]:
					menu_panel = ""
					sfx.play("switch", -8.0, 0.9)
				elif key.keycode == KEY_X:
					menu_action("set:tv")
			elif key.keycode == KEY_C:
				_title_click("menu:cas")
			elif key.keycode in [KEY_UP, KEY_W, KEY_LEFT, KEY_A]:
				set_ao(String(WorldBuilder.AOS[posmod(idx - 1, WorldBuilder.AOS.size())]["id"]))
			elif key.keycode in [KEY_DOWN, KEY_S, KEY_RIGHT, KEY_D]:
				set_ao(String(WorldBuilder.AOS[posmod(idx + 1, WorldBuilder.AOS.size())]["id"]))
			elif key.keycode in [KEY_ENTER, KEY_SPACE]:
				open_loadout()
			elif key.keycode == KEY_X:
				menu_action("set:tv")
			elif key.keycode == KEY_ESCAPE:
				menu_panel = "settings"
			return
		if help_open and key.keycode in [KEY_F1, KEY_ESCAPE]:
			help_open = false
			return
		# fixed keys first, then whatever the player has bound
		match key.keycode:
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
				arsenal.select_slot(key.keycode - KEY_1)
				return
			KEY_0:
				arsenal.select_slot(9)
				return
			KEY_MINUS:
				arsenal.select_slot(10)
				return
			KEY_EQUAL:
				arsenal.select_slot(11)
				return
			KEY_F9:
				menu_action("dev:farm")
				return
			KEY_F1:
				help_open = not help_open
				return
			KEY_SPACE:
				if state == State.PLAYING:
					_cycle_zoom()
				return
			KEY_BRACKETLEFT:
				mouse_sens = maxf(0.2, mouse_sens - 0.1)
				return
			KEY_BRACKETRIGHT:
				mouse_sens = minf(3.0, mouse_sens + 0.1)
				return
			KEY_ESCAPE:
				_back()
				return
		_do_action(_key_action(key.keycode))


## In the A-10: the mouse is your head (the aircraft follows it), the wheel zooms, RMB locks a
## Maverick, the number keys and Q / E pick stores, Y the fuze. Returns true if it took the event.
func _cas_input(motion: InputEventMouseMotion, button: InputEventMouseButton, key: InputEventKey) -> bool:
	if tac_open:
		return false
	if motion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			cas.on_look(motion.relative)
		return true
	if button and button.pressed:
		match button.button_index:
			MOUSE_BUTTON_RIGHT:
				cas.lock()
				return true
			MOUSE_BUTTON_WHEEL_UP:
				cas.on_wheel(0.88)
				return true
			MOUSE_BUTTON_WHEEL_DOWN:
				cas.on_wheel(1.14)
				return true
			MOUSE_BUTTON_LEFT:
				if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				return true
		return false
	if key and key.pressed and not key.echo:
		if key.keycode >= KEY_1 and key.keycode <= KEY_5:
			cas.select(key.keycode - KEY_1)
			return true
		match _key_action(key.keycode):
			"prev_weapon":
				cas.cycle(-1)
				return true
			"next_weapon":
				cas.cycle(1)
				return true
			"fuze":
				cas.cycle_fuze()
				return true
			"armory", "a10", "track", "orbit_home", "zoom", "time_slower", "time_faster", "reload":
				# nothing to do in the cockpit: no armory, no gun runs to call, no sensor to slew
				return true
		if key.keycode == KEY_SPACE:
			return true
	return false


## A bound action, from the keyboard or the controller.
func _do_action(act: String) -> void:
	var playing := state == State.PLAYING
	match act:
		"prev_weapon":
			arsenal.cycle(-1)
		"next_weapon":
			arsenal.cycle(1)
		"tac_map":
			if playing:
				_set_tac(not tac_open)
		"palette":
			palette = (palette + 1) % PALETTES.size()
			sfx.play("switch", -8.0, 1.2)
		"reload":
			# guns reload for free; anything else is a paid restock of the selected system
			var cur_w: Dictionary = arsenal.current()
			if arsenal.restock_time(cur_w) <= 0.0:
				arsenal.reload()
			elif playing:
				buy_restock(String(cur_w["id"]))
		"a10":
			if playing:
				arsenal.quick_a10()
		"sensor":
			menu_action("set:tv")
		"armory":
			if playing:
				if tac_open:
					_set_tac(false)
				open_armory(false)
		"track":
			if playing:
				toggle_track()
		"orbit_here":
			if playing:
				set_orbit_center(track)
		"orbit_home":
			if playing:
				set_orbit_center(Vector3.ZERO)
		"time_slower":
			cycle_time(-1)
		"time_faster":
			cycle_time(1)
		"declutter":
			hud_mode = (hud_mode + 1) % 3
		"zoom":
			if playing:
				_cycle_zoom()
		"fuze":
			if playing:
				arsenal.cycle_fuze()


## Esc, or B on a controller: close whatever is open, else pause or resume.
func _back() -> void:
	if rebinding != "":
		rebinding = ""
	elif menu_panel != "":
		menu_panel = ""
		sfx.play("switch", -8.0, 0.9)
	elif tac_open:
		_set_tac(false)
	elif state == State.PLAYING:
		_pause()
	elif state == State.PAUSED:
		_resume()
	elif state == State.ARMORY:
		close_armory()
	elif state == State.LOADOUT:
		state = State.TITLE
	elif state == State.TITLE:
		menu_panel = "settings"


## Bind the action waiting for a key. Esc cancels; the fixed keys can't be taken; a key that
## already did something else swaps places with this action's old key.
func _rebind(code: int) -> void:
	var act := rebinding
	rebinding = ""
	if code == KEY_ESCAPE:
		return
	if code in [KEY_0, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_MINUS, KEY_EQUAL, KEY_F1, KEY_F9, KEY_SPACE, KEY_ENTER]:
		sfx.play("switch", -8.0, 0.6)
		return
	var old: int = keys[act]
	for a in keys:
		if int(keys[a]) == code and a != act:
			keys[a] = old
	keys[act] = code
	sfx.play("clip", -6.0, 1.2)
	save_pilot()


## A left click (or the controller's A) at a screen position, for everything that isn't flying.
func _menu_click(pos: Vector2) -> void:
	if state == State.PLAYING and tac_open:
		var g: Vector3 = hud.tac_to_world(pos)
		if g != Vector3.INF:
			_unlock(false)
			track = g
			sfx.play("beep", -10.0, 1.2)
		return
	if state == State.TITLE:
		_title_click(hud.hit_test(pos))
	elif state == State.PAUSED:
		var act: String = hud.hit_test(pos)
		if act == "" and menu_panel == "":
			_resume()
		else:
			menu_action(act)
	elif state == State.ARMORY or state == State.LOADOUT or state == State.PERK:
		menu_action(hud.hit_test(pos))
	elif state == State.OVER and over_t > 2.5:
		get_tree().reload_current_scene()
	elif state == State.PLAYING and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ---------------------------------------------------------------- controller
## A stick with a dead zone, rescaled so the edge of the dead zone is zero.
func _stick(ax: JoyAxis, ay: JoyAxis) -> Vector2:
	var v := Vector2(Input.get_joy_axis(0, ax), Input.get_joy_axis(0, ay))
	var l := v.length()
	if l < 0.18:
		return Vector2.ZERO
	return v / l * minf((l - 0.18) / 0.82, 1.0)


func _joy_button(b: JoyButton) -> void:
	var playing := state == State.PLAYING and not tac_open
	match b:
		JOY_BUTTON_A:
			if playing:
				toggle_track()
			elif state == State.TITLE and menu_panel == "" and hud.hit_test(get_viewport().get_mouse_position()) == "":
				open_loadout()
			else:
				_menu_click(get_viewport().get_mouse_position())
		JOY_BUTTON_B:
			if playing:
				_cycle_zoom()
			else:
				_back()
		JOY_BUTTON_X:
			if playing:
				_do_action("reload")
		JOY_BUTTON_Y:
			if state == State.PLAYING:
				_set_tac(not tac_open)
		JOY_BUTTON_LEFT_SHOULDER:
			if state == State.ARMORY or state == State.LOADOUT:
				armory_tab = posmod(armory_tab - 1, arsenal.CATS.size() + 2)
			else:
				arsenal.cycle(-1)
		JOY_BUTTON_RIGHT_SHOULDER:
			if state == State.ARMORY or state == State.LOADOUT:
				armory_tab = posmod(armory_tab + 1, arsenal.CATS.size() + 2)
			else:
				arsenal.cycle(1)
		JOY_BUTTON_BACK:
			if state == State.PLAYING:
				_do_action("armory")
			elif state == State.ARMORY:
				close_armory()
		JOY_BUTTON_START:
			match state:
				State.PLAYING:
					_pause()
				State.PAUSED:
					_resume()
				State.TITLE:
					open_loadout()
				State.LOADOUT:
					menu_action("launch")
				State.ARMORY:
					close_armory()
				State.OVER:
					get_tree().reload_current_scene()
		JOY_BUTTON_LEFT_STICK:
			if playing:
				set_orbit_center(track)
		JOY_BUTTON_RIGHT_STICK:
			if playing:
				set_orbit_center(Vector3.ZERO)
		JOY_BUTTON_DPAD_LEFT:
			if state == State.TITLE:
				set_ao(String(WorldBuilder.AOS[posmod(ao_index() - 1, WorldBuilder.AOS.size())]["id"]))
			elif playing:
				cycle_time(-1)
		JOY_BUTTON_DPAD_RIGHT:
			if state == State.TITLE:
				set_ao(String(WorldBuilder.AOS[posmod(ao_index() + 1, WorldBuilder.AOS.size())]["id"]))
			elif playing:
				cycle_time(1)
		JOY_BUTTON_DPAD_UP:
			if state == State.TITLE:
				set_ao(String(WorldBuilder.AOS[posmod(ao_index() - 1, WorldBuilder.AOS.size())]["id"]))
		JOY_BUTTON_DPAD_DOWN:
			if state == State.TITLE:
				set_ao(String(WorldBuilder.AOS[posmod(ao_index() + 1, WorldBuilder.AOS.size())]["id"]))


## Every frame: the left stick slews the sensor in flight and moves the pointer in menus;
## the left trigger zooms in.
func _joy_poll(delta: float) -> void:
	if Input.get_connected_joypads().is_empty():
		return
	var ls := _stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y)
	if state == State.PLAYING and not tac_open:
		if ls != Vector2.ZERO:
			_slew(ls * ls.length() * 900.0 * delta)
		var lt := Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
		if lt > 0.2:
			fov_target = clampf(fov_target * (1.0 - 1.4 * lt * delta), 0.8 / stat("zoom"), 40.0)
	elif ls != Vector2.ZERO and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.warp_mouse(get_viewport().get_mouse_position() + ls * 1100.0 * delta)


func joy_trigger() -> bool:
	return not Input.get_connected_joypads().is_empty() and Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) > 0.4


func _set_tac(open: bool) -> void:
	tac_open = open
	if not autotest:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
	sfx.play("switch", -10.0, 1.4 if open else 1.1)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == State.PLAYING and not autotest:
		_pause()


func _zoom(f: float) -> void:
	fov_target = clampf(fov_target * f, 0.8 / stat("zoom"), 40.0)
	if zoom_snd_cd <= 0.0:
		sfx.play("zoom", -10.0, randf_range(0.95, 1.05))
		zoom_snd_cd = 0.25


func _cycle_zoom() -> void:
	var idx := 0
	for i in FOV_PRESETS.size():
		if fov_target <= float(FOV_PRESETS[i]) * 1.05:
			idx = i
	fov_target = FOV_PRESETS[(idx + 1) % FOV_PRESETS.size()]
	sfx.play("zoom", -8.0)


func _pause() -> void:
	state = State.PAUSED
	tac_open = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	sfx.stop_all_guns()


func _resume() -> void:
	state = State.PLAYING
	save_pilot()
	if not autotest:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func aos() -> Array:
	return WorldBuilder.AOS


func ao_index() -> int:
	for i in WorldBuilder.AOS.size():
		if WorldBuilder.AOS[i]["id"] == ao_id:
			return i
	return 0


## Switch area of operations: the scene reloads and builds the new AO.
func set_ao(id: String) -> void:
	if id == ao_id:
		return
	Engine.set_meta("ao", id)
	sfx.play("switch", -4.0)
	get_tree().reload_current_scene()


## CAS mode: straight into the cockpit of Hawg 1-1, off the FARP and inbound to the AO, with
## the AI flying Spectre 2-1 over the refuge.
func _start_cas() -> void:
	mode = "cas"
	cas = Cas.new()
	cas.main = self
	add_child(cas)
	cas.begin()
	state = State.PLAYING
	if not autotest:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	intermission = 8.0
	var af: Dictionary = world["airfield"]
	var farp: Vector3 = af["center"]
	var sector := String(SECTORS[horde.sector_of(farp.x, farp.z)]).to_lower()
	radio("SPECTRE 2-1", "Hawg one-one, Spectre two-one. I've got the big crowds over %s. I'll hand you the jobs I can't do. Welcome to the party." % String(world["name"]), true)
	radio("TOC", "Hawg, your FARP is the strip %.1f klicks %s: fuel and bombs, same place. Watch your fuel, watch your height. The mouse flies the aircraft." % [Vector2(farp.x, farp.z).length() / 1000.0, sector])
	save_pilot()


func _start_game() -> void:
	state = State.PLAYING
	if not autotest:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	intermission = 3.0
	radio("TOC", "Spectre two-one, Overwatch, %s. %s You are cleared hot." % [String(world["name"]), String(world["brief"])])
	var names: Array = []
	for w in arsenal.equipped():
		names.append(String(w["short"]))
	radio("PILOT", "Two-one copies. Loaded with %s. Kills earn requisition, B for the armory." % ", ".join(names))
	save_pilot()


# ---------------------------------------------------------------- loadout & armory
func open_loadout() -> void:
	if iron:
		# Iron Torment: there's nothing to choose. One GAU-8, and go.
		_start_game()
		return
	state = State.LOADOUT
	armory_tab = arsenal.CATS.size()
	sfx.play("switch", -6.0)


## Clicks on the title screen: the main menu, the AO list and the settings panel.
func _title_click(pick: String) -> void:
	if pick == "":
		return
	if pick.begins_with("ao:"):
		if pick.substr(3) != ao_id:
			# clicked in the list: keep it scrolled where it is across the reload
			Engine.set_meta("ao_scroll", hud.ao_scroll_now)
			set_ao(pick.substr(3))
	elif pick == "menu:deploy":
		open_loadout()
	elif pick == "menu:cas":
		if iron:
			_start_game()
		else:
			_start_cas()
	else:
		menu_action(pick)


## Clicks in the loadout and armory screens. Actions come from hud.hit_test().
func menu_action(act: String) -> void:
	if act == "":
		return
	if act == "launch":
		_start_game()
	elif act == "deploy":
		close_armory()
	elif act == "resume":
		_resume()
	elif act == "menu:settings":
		menu_panel = "settings"
		sfx.play("switch", -6.0, 1.1)
	elif act == "menu:quit":
		save_pilot()
		get_tree().quit()
	elif act == "panel:close":
		menu_panel = ""
		rebinding = ""
		sfx.play("switch", -8.0, 0.9)
	elif act.begins_with("stab:"):
		settings_tab = int(act.substr(5))
		rebinding = ""
		sfx.play("switch", -10.0, 1.3)
	elif act.begins_with("bind:"):
		var what := act.substr(5)
		if what == "reset":
			keys = DEFAULT_KEYS.duplicate()
			save_pilot()
			sfx.play("switch", -6.0, 0.8)
		else:
			rebinding = what
			sfx.play("beep", -10.0, 1.4)
	elif act.begins_with("gfx:"):
		match act.substr(4):
			"full":
				fullscreen = not fullscreen
			"vsync":
				vsync = not vsync
			"scale-":
				render_scale = maxf(0.5, snappedf(render_scale - 0.1, 0.05))
			"scale+":
				render_scale = minf(1.0, snappedf(render_scale + 0.1, 0.05))
			"msaa":
				msaa = 0 if msaa == 4 else (2 if msaa == 0 else 4)
			"cap-":
				horde_cap = 30000 if horde_cap <= 50000 else 50000
			"cap+":
				horde_cap = 80000 if horde_cap >= 50000 else 50000
			"wx":
				weather_fx = not weather_fx
		_apply_graphics()
		sfx.play("switch", -8.0, 1.2)
		save_pilot()
	elif act == "title":
		menu_panel = ""
		save_pilot()
		get_tree().reload_current_scene()
	elif act.begins_with("set:"):
		if act.begins_with("set:bus:"):
			# set:bus:<name>:+ or -
			var parts := act.split(":")
			var b := parts[2]
			var step := (0.01 if Input.is_key_pressed(KEY_SHIFT) else 0.05) * (-1.0 if parts[3] == "-" else 1.0)
			vol_bus[b] = clampf(snappedf(float(vol_bus.get(b, 1.0)) + step, 0.01), 0.0, 1.0)
		match act.substr(4):
			"sens-":
				mouse_sens = maxf(0.2, snappedf(mouse_sens - 0.1, 0.1))
			"sens+":
				mouse_sens = minf(3.0, snappedf(mouse_sens + 0.1, 0.1))
			"inv":
				invert_y = not invert_y
			"vol-", "vol+":
				# 5% a click, 1% with Shift held
				var step := (0.01 if Input.is_key_pressed(KEY_SHIFT) else 0.05) * (-1.0 if act.ends_with("-") else 1.0)
				volume = clampf(snappedf(volume + step, 0.01), 0.0, 1.0)
			"pal":
				palette = (palette + 1) % PALETTES.size()
			"tv":
				tv_mode = not tv_mode
				tv_toggles += 1
				_apply_sensor()
				if state == State.PLAYING:
					radio("FCO", "Switching to the TV camera." if tv_mode else "Back on the IR imager.")
			"tut":
				tutorial_on = not tutorial_on
				if tutorial_on:
					tut_step = 0
					tut_cur = -1
		_apply_volume()
		sfx.play("switch", -8.0, 1.2)
		save_pilot()
	elif act.begins_with("tab:"):
		armory_tab = int(act.substr(4))
		sfx.play("switch", -10.0, 1.3)
	elif act.begins_with("buy:"):
		buy(act.substr(4))
	elif act.begins_with("upg:"):
		buy_upgrade(act.substr(4))
	elif act == "dev:farm":
		dev_farm = not dev_farm
		if not dev_farm:
			horde.clear_farm()
		sfx.play("switch", -6.0, 1.4 if dev_farm else 0.8)
		radio("DEV", "Zombie farm %s." % ("ON: 10,000 dummies standing on the approaches" if dev_farm else "OFF: dummies cleared"))
		save_pilot()
	elif act == "dev:reset":
		# two clicks within four seconds, so it can't happen by accident
		if real_t - reset_armed < 4.0:
			reset_progress()
		else:
			reset_armed = real_t
			sfx.play("alarm", -10.0, 1.2)
	elif act.begins_with("pin:"):
		var pid := act.substr(4)
		pinned = "" if pinned == pid else pid
		sfx.play("beep", -8.0, 1.3 if pinned != "" else 0.9)
		save_pilot()
	elif act.begins_with("restock:"):
		buy_restock(act.substr(8))
	elif act == "restock_all":
		buy_restock_all()
	elif act.begins_with("perk:"):
		take_perk(int(act.substr(5)))
	elif act == "reroll":
		reroll_perks()
	elif act.begins_with("eq:"):
		if arsenal.toggle_equip(act.substr(3)):
			sfx.play("clip", -8.0, 1.2)
			save_pilot()
		else:
			sfx.play("switch", -8.0, 0.7)


func open_armory(after_wave: bool) -> void:
	state = State.ARMORY
	armory_after_wave = after_wave
	armory_opens += 1
	sfx.stop_all_guns()
	if not autotest:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_armory() -> void:
	state = State.PLAYING
	if armory_after_wave:
		intermission = 8.0
		armory_after_wave = false
	if not autotest:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	sfx.play("switch", -6.0)


## One ladder of the catalogue, rung by rung, with each system's status for the armory screen.
## Status: OWNED / BUY / FUNDS (next in line but can't afford it) / LOCKED (buy the rung below first).
func armory_rows(cat: int) -> Array:
	var rows: Array = []
	var size: int = arsenal.ladder_size(cat)
	for w in arsenal.in_category(cat):
		var status := "OWNED"
		if not w["owned"]:
			if not arsenal.unlocked(w):
				status = "LOCKED"
			elif rp < int(w["price"]):
				status = "FUNDS"
			else:
				status = "BUY"
		var prev: Dictionary = arsenal.prev_of(w)
		rows.append({"id": w["id"], "name": w["name"], "desc": w["desc"], "price": w["price"], "tier": w["tier"],
			"rung": int(w.get("rung", 0)), "of": size, "capstone": int(w.get("rung", 0)) == size - 1,
			"next": status in ["BUY", "FUNDS"], "prev_name": String(prev.get("name", "")), "pinned": pinned == String(w["id"]),
			"status": status, "equipped": arsenal.is_equipped(String(w["id"])), "restock": arsenal.restock_price(w)})
	if cat == 4:
		var r_status := "BUY" if rp >= REINFORCE_PRICE else "FUNDS"
		if integrity >= 100.0 or state == State.LOADOUT:
			r_status = "FULL"
		rows.append({"id": "reinforce", "name": "REINFORCE THE WALLS", "desc": "Engineers and fresh volunteers. Restores 25% of the refuge's integrity.",
			"price": REINFORCE_PRICE, "tier": 1, "status": r_status, "equipped": false})
	return rows


func buy(id: String) -> void:
	var row: Dictionary = {}
	for cat in arsenal.CATS.size():
		for r in armory_rows(cat):
			if r["id"] == id:
				row = r
	if row.is_empty() or row["status"] != "BUY":
		sfx.play("switch", -8.0, 0.7)
		return
	rp -= int(row["price"])
	sfx.play("buy", -2.0)
	if id == "reinforce":
		integrity = minf(100.0, integrity + 25.0)
		radio("OVERWATCH", "Walls shored up. Thank you, Spectre.")
	else:
		var w: Dictionary = arsenal.by_id(id)
		w["owned"] = true
		w["ammo"] = arsenal.cap_of(w)
		if w.has("cap"):
			w["charge"] = w["cap"]
		var aboard: bool = arsenal.toggle_equip(id)
		if pinned == id:
			pinned = ""
		# the moment: a full-screen card, a fanfare, and the crew's reaction
		unlock_card = {"id": id, "t": real_t, "aboard": aboard}
		sfx.play("lock", -4.0, 1.2, 0.12)
		sfx.play("charge", -6.0, 1.7, 0.25)
		sfx.play("buy", 2.0, 0.75, 0.4)
		# straight onto the air, over whatever was playing: the radio holds still in the armory
		radio_cur = {"who": "CREW CHIEF", "text": String(ARRIVALS.get(id, "%s is aboard. Go break it in." % String(w["name"])))}
		radio_t = 0.0
		if not aboard:
			radio("TOC", "The aircraft is full: %s is in the hangar. Swap it in on the loadout tab." % String(w["name"]))
		if id in ["nuke", "davy", "neutron"]:
			radio("TOC", "Spectre, you have nuclear release authority. Mind the survivors and mind your own airframe.")
	save_pilot()


## What each new system's arrival sounds like over the intercom.
const ARRIVALS := {
	"m134": "Minigun's on the mount. Six thousand a minute. Hold it down and hose.",
	"gau12": "The Equalizer's mounted. Twenty-five mil: now we're a gunship.",
	"vulcan": "Vulcan's in. A fighter's gun on a cargo plane. I love this job.",
	"gau8": "The Avenger's bolted in. We had to reinforce the floor. She's beautiful.",
	"gsh630": "Six-barrel Russian thirty. Don't ask where we got it. Bursts, Spectre, bursts.",
	"smart": "Smart rounds loaded. Point it at the crowd and it does the rest.",
	"lasermg": "Pulse laser's online. Sixty shots a second and no bullets to load. My loaders are crying.",
	"tesla": "The coil's charged. Everyone stand clear of the door.",
	"auric": "Gold-plated thirty mil. Accounting is going to love you.",
	"chrono": "Science says the chrono cannon is safe. Science also says they don't know how it works.",
	"graviton": "Graviton's spun up. If you hear it whispering, that's normal. Probably.",
	"godgun": "A gatling in orbit. Sixteen rods a second. Someone up there really loves you.",
	"atomic": "I am not signing for this one, sir. Four micro-nukes a second. God help them.",
	"m102": "One-oh-five's in the door. Gunners, earplugs in. This is the real thing.",
	"pgk": "Precision kits on the one-oh-fives. Every shell lands where you put it.",
	"wp105": "Willie Pete's racked. Everything it touches burns.",
	"hellfire": "Hellfire rails are hot. Put the laser on something.",
	"switchblade": "Switchblades in the tubes. Little killers. They'll find the crowd.",
	"tomahawk": "The Arleigh Burke is yours, Spectre. Call for fire.",
	"jdam": "Two thousand pounders on the ramp. Somebody's intersection is about to disappear.",
	"daisy": "Daisy cutter's on the pallet. Fifteen thousand pounds. Clear a landing zone.",
	"moab": "The MOAB is on the ramp. Mother of all bombs. I'm not standing anywhere near it.",
	"b52": "A B-52 is on call for you. Arc Light, on request. Heads down.",
	"singularity": "The singularity projector is calibrated. Please don't point it at us.",
	"sol": "SOL is tasked to your crosshair. Draw something nice.",
	"nuke": "Nuclear release authority granted. B61, ten kilotons. God help us all.",
	"constellation": "THOR answers to you now. All twelve rods.",
	"titan": "Titan one is assigned to your flight. Forty metres of friend.",
	"moon": "We... have a moon on standby. Spectre, use this responsibly. Please.",
}
# the card on screen after a new system is bought: {id, t, aboard}
var unlock_card: Dictionary = {}
# the armory item the player is saving for ("" = the cheapest next rung anywhere)
var pinned := ""
const RANKS := ["SECOND LIEUTENANT", "FIRST LIEUTENANT", "CAPTAIN", "MAJOR", "LIEUTENANT COLONEL", "COLONEL", "BRIGADIER GENERAL", "MAJOR GENERAL"]
var rank_shown := 1
var goal_called := ""
var goal_check_t := 0.0


func rank_name() -> String:
	return String(RANKS[clampi(clearance() - 1, 0, RANKS.size() - 1)])


## What to save for: the pinned system, or else the cheapest next rung on any ladder.
func next_goal() -> Dictionary:
	if pinned != "":
		var pw: Dictionary = arsenal.by_id(pinned)
		if not pw.is_empty() and not pw["owned"]:
			return pw
		pinned = ""
	var best: Dictionary = {}
	for c in arsenal.CATS.size():
		for w in arsenal.in_category(c):
			if w["owned"]:
				continue
			if arsenal.unlocked(w) and (best.is_empty() or int(w["price"]) < int(best["price"])):
				best = w
			break
	return best


## Pay to top a system up right now instead of waiting for it to restock on its own.
func buy_restock(id: String) -> void:
	var w: Dictionary = arsenal.by_id(id)
	if w.is_empty():
		return
	var price: int = arsenal.restock_price(w)
	if price <= 0:
		sfx.play("switch", -10.0, 0.8)
		return
	if rp < price:
		sfx.play("switch", -8.0, 0.7)
		radio("TOC", "Negative, Spectre. A full load of %s costs %s RP." % [String(w["short"]), Hud.commas(price)])
		return
	rp -= price
	arsenal.fill(w)
	sfx.play("buy", -2.0)
	sfx.play("clip", -6.0, 1.0, 0.3)
	if w["kind"] in arsenal.SUPPORT_KINDS:
		radio("TOC", "Priority tasking approved: %s is rearmed and standing by." % String(w["name"]))
	else:
		radio("LOADMASTER", "Breaking out the reserve: full load of %s." % String(w["short"]))
	save_pilot()


## Top up everything aboard, in loadout order, for as long as the requisition lasts.
func buy_restock_all() -> void:
	var spent := 0
	var n := 0
	for w in arsenal.equipped():
		var price: int = arsenal.restock_price(w)
		if price > 0 and rp >= price:
			rp -= price
			spent += price
			n += 1
			arsenal.fill(w)
	if n == 0:
		sfx.play("switch", -8.0, 0.7)
		return
	sfx.play("buy", -2.0)
	sfx.play("clip", -6.0, 1.0, 0.3)
	radio("LOADMASTER", "Restocked %d system%s for %s RP." % [n, "" if n == 1 else "s", Hud.commas(spent)])
	save_pilot()


# ---------------------------------------------------------------- waves
func _begin_wave() -> void:
	wave += 1
	wave_kills0 = kills
	wave_rp0 = rp_total
	wave_integrity0 = integrity
	if (wave - 1) % DAY_LEN == 0:
		day_clock = 0.0
		_apply_grid()
		if wave > 1:
			radio("TOC", "Day %d, Spectre. Dawn's up and they're coming again." % day())
			radio("OVERWATCH", ["We've lost power to the east side. Streetlights are going dark out there.", "Another substation's gone. Half the city's dark tonight.", "Grid's all but gone. After dark it's candles and fires out there.", "Last of the power's gone outside the wire."][clampi(day() - 2, 0, 3)])
	elif (wave - 1) % DAY_LEN == 3:
		radio("PILOT", "Sun's down. IR's the only camera worth having now.")
	_pick_weather()
	ops.wave_started(wave)
	# Hordes start as a few hundred and grow ~55% every wave. By wave 12 or so the horde is at
	# the engine's cap and the spawner simply keeps it there: every approach packed out to the map edge.
	to_spawn = int(minf(220.0 * pow(1.55, wave - 1), 400000.0) * float(world.get("horde_mult", 1.0)))
	var torment := bool(world.get("torment", false))
	if torment:
		to_spawn = int(minf(30000.0 * pow(1.3, wave - 1), 600000.0))
	flood = clampf((wave - 6) / 7.0, 0.0, 1.0)
	var dur := 50.0 + wave * 12.0
	spawn_rate = to_spawn / dur
	if torment:
		# the rest of the tide follows on as fast as there's room for it
		spawn_rate = 900.0
	next_clump = t
	runner_frac = clampf(0.04 + 0.035 * wave, 0.0, 0.32)
	brute_frac = clampf(0.012 * (wave - 1), 0.0, 0.08)
	active_corridors = corridors.duplicate()
	active_corridors.shuffle()
	active_corridors.resize(mini(2 + wave, corridors.size()))
	wave_active = true
	arsenal.resupply()
	banner = "DAY %d  //  WAVE %d  //  %s CONTACTS" % [day(), wave, Hud.commas(to_spawn + horde.alive_count)]
	banner_t = real_t
	missions.wave_started(wave)
	var dirs: Array = []
	for c in active_corridors.slice(0, 3):
		var a: float = c["ang"]
		var dname := String(SECTORS[horde.sector_of(cos(a), sin(a))]).to_lower()
		if not dname in dirs:
			dirs.append(dname)
	var size_word := "Scattered" if to_spawn < 1000 else ("Heavy" if to_spawn < 8000 else "Massive")
	if torment:
		# the whole wave comes over the horizon at once, one tide from edge to edge of the front
		var n := mini(to_spawn, maxi(int(horde.max_alive) - horde.alive_count - 1500, 0))
		_spawn_tide(n, 1900.0, 2040.0)
		to_spawn -= n
		radio("TOC", "Wave %d. The tide's coming, Spectre: %s of them, horizon to horizon, and three of the big ones in it. Hold the line." % [wave, Hud.commas(n + to_spawn)], true)
		banner = "WAVE %d  //  THE TIDE  //  %s" % [wave, Hud.commas(n + to_spawn)]
		_schedule_bosses(dur)
		return
	if flood >= 1.0:
		radio("TOC", "Wave %d. Spectre, the whole AO is crawling. Every approach, wall to horizon. God speed." % wave)
	else:
		radio("TOC", "Wave %d. %s heat signatures two to three klicks out, moving in from the %s. Engage at range. Weapons free." % [wave, size_word, ", ".join(dirs)])
	if wave > 1:
		sfx.play("alarm", -12.0)
	_schedule_bosses(dur)
	# from wave 2, four waves in ten come with a twist
	if wave >= 2 and wave_event == "" and randf() < 0.4:
		_start_event(String(EVENTS[randi() % EVENTS.size()]))
	# a mega-horde masses far out (from wave 4, or from the start on the big AOs): a target worth a big weapon
	var mega_from := int(world.get("mega_from", 4))
	if wave >= mega_from:
		var c: Dictionary = corridors[randi() % corridors.size()]
		var n := clampi(int(to_spawn * 0.35), 300, 6000)
		_spawn_clump(c, n, maxf(randf_range(2300.0, 2900.0), float(c["rmin"]) + 300.0))
		var a: float = c["ang"]
		var s := String(SECTORS[horde.sector_of(cos(a), sin(a))])
		radio("TOC", "Be advised: mega-horde, %s plus, massing on the %s approach. Recommend heavy ordnance." % [Hud.commas(n), s.to_lower()], true)
		banner = "MEGA-HORDE  //  %s  //  %s" % [s, Hud.commas(n)]


## Bosses turn up now and then from wave 3, more often and in pairs later on.
func _schedule_bosses(dur: float) -> void:
	boss_queue.clear()
	var n := 0
	var torment := bool(world.get("torment", false))
	if wave >= 3 and randf() < 0.3 + 0.06 * wave:
		n = 1
	if wave >= 7:
		n += int(randf() < 0.5) + (wave - 7) / 4
	if torment:
		# three in every tide, from the first
		n = 3
	for k in mini(n, 5):
		var pool: Array = []
		var total := 0.0
		for d in horde.BOSSES:
			if d["id"] == "pinata":
				continue
			if wave >= int(d["min_wave"]) or (torment and d["id"] != "colossus") or (torment and wave >= 5):
				pool.append(d)
				total += float(d["odds"])
		var roll := randf() * total
		var pick: Dictionary = pool[0]
		for d in pool:
			roll -= float(d["odds"])
			if roll <= 0.0:
				pick = d
				break
		boss_queue.append([t + (randf_range(1.0, 4.0) if torment else randf_range(12.0, dur * 0.8)), pick])


func _update_bosses_due() -> void:
	for k in range(boss_queue.size() - 1, -1, -1):
		if t >= float(boss_queue[k][0]):
			var def: Dictionary = boss_queue[k][1]
			boss_queue.remove_at(k)
			spawn_boss(def)


## Put a boss on a random approach, two-odd klicks out, and tell everyone about it.
func spawn_boss(def: Dictionary, at := Vector3.INF) -> void:
	var c: Dictionary = active_corridors[randi() % active_corridors.size()] if not active_corridors.is_empty() else corridors[0]
	var pos := at
	if pos == Vector3.INF:
		var ang: float = c["ang"]
		if int(c["type"]) == 1:
			# anywhere across an open approach, not just down its middle
			ang += randf_range(-0.8, 0.8) * float(c["half"])
		var r := maxf(randf_range(1900.0, 2600.0), float(c["rmin"]) + 200.0)
		pos = Vector3(cos(ang), 0.0, sin(ang)) * r
	var hp := float(def["hp"]) * (1.0 + 0.15 * maxi(0, wave - int(def["min_wave"])))
	var i: int = horde.spawn_boss(def, pos.x, pos.z, arrive.y + float(def["scale"]) * 1.5, hp)
	if i < 0:
		return
	var s := String(SECTORS[horde.sector_of(pos.x, pos.z)])
	radio("TOC", "Be advised: %s-class contact on the %s approach, %.1f klicks. %s" % [String(def["name"]), s.to_lower(), Vector2(pos.x, pos.z).length() / 1000.0, String(def["brief"])], true)
	banner = "BOSS  //  %s  //  %s" % [String(def["name"]), s]
	banner_t = real_t
	sfx.play("alarm", -4.0, 0.6)
	time_scale = 1.0


## Boss deaths, wall breaches and broods reported by the horde this frame.
func _boss_events() -> void:
	for e in horde.boss_events:
		var def: Dictionary = e["def"]
		var pos: Vector3 = e["pos"]
		var name_s := String(def["name"])
		match String(e["type"]):
			"dead":
				var bounty := int(round(float(def["bounty"]) * (1.0 + wave * 0.1) * stat("rp") * rp_event))
				rp += bounty
				rp_total += bounty
				popups.append({"pos": pos + Vector3.UP * (float(def["scale"]) * 2.5 + 4.0), "text": "%s DOWN  +%s RP" % [name_s, Hud.commas(bounty)], "t": real_t, "big": true})
				_feed("%s KILLED  +%s RP" % [name_s, Hud.commas(bounty)])
				if def.has("pinata"):
					radio("TOC", "PINATA! Spectre, that's %s RP in candy and requisition!" % Hud.commas(bounty), true)
					# confetti, thermally speaking
					for c in 40:
						fx.particle(true, pos + Vector3.UP * 2.0, Vector3(randf_range(-1, 1), randf_range(0.6, 1.6), randf_range(-1, 1)) * randf_range(10, 30), randf_range(1.0, 2.5), 0.6, 0.4, randf_range(1.2, 2.4), 3, 0.6, 0.3)
					sfx.play("buy", 0.0, 1.3)
				else:
					radio("TOC", "Splash the %s! Hell of a kill, Spectre. Bounty of %s RP approved." % [name_s.to_lower(), Hud.commas(bounty)], true)
				fx.explosion(pos, 3)
				sfx.play_at("exp_large", pos, cam.global_position, 6.0, 0.6)
				if def.has("burst"):
					# it goes up and takes the crowd around it along
					var k: int = horde.blast(pos + Vector3.UP, 25.0, float(def["burst"]), 30.0, 26.0)
					add_kills(k, pos)
					fx.explosion(pos, 5)
					sfx.play_at("exp_huge", pos, cam.global_position, 10.0, 0.8)
			"breach":
				integrity -= 14.0
				horde.blast(pos + Vector3.UP, 20.0, float(def["burst"]) * 0.6, 30.0, 20.0)
				fx.explosion(pos, 5)
				sfx.play_at("exp_huge", pos, cam.global_position, 12.0, 0.7)
				flash = maxf(flash, 0.4)
				radio("OVERWATCH", "The %s burst against the wall! We've lost a whole section, Spectre!" % name_s.to_lower(), true)
			"brood":
				if randf() < 0.25:
					radio("TOC", "The broodmother is shedding more of them. Kill it before it fills the approach.")
			"escaped":
				radio("TOC", "The pinata got away. All that requisition, gone. Unbelievable.", true)
	horde.boss_events.clear()


# ---------------------------------------------------------------- time of day & weather
## Hours since the day's dawn (06:00). Each wave is a fifth of the day: the clock runs through
## the wave's slot while it's fought, and the last wave of a day ends at the next dawn.
var day_clock := 3.5
var precip_type := 0
var precip_amt := 0.0


func _pick_weather() -> void:
	var odds: Dictionary = WEATHER_ODDS.get(ao_base, WEATHER_ODDS["city"])
	var total := 0.0
	for k in odds:
		total += float(odds[k])
	var roll := randf() * total
	var pick := "clear"
	for k in odds:
		roll -= float(odds[k])
		if roll <= 0.0:
			pick = String(k)
			break
	if pick != weather:
		var reports := {
			"clear": "Weather's clearing. Unlimited visibility.",
			"overcast": "Cloud deck's coming in. Flat light on the TV, IR's fine.",
			"rain": "Rain moving over the AO. IR's going soft and the TV won't see far.",
			"fog": "Fog in the low ground. The TV's blind past a few hundred metres, IR cuts through it.",
			"snow": "Snow squalls rolling in. Both sensors are going to suffer.",
			"dust": "Sandstorm. Visibility's dropping fast on both cameras.",
		}
		radio("WEATHER", String(reports.get(pick, "")))
	weather = pick
	wx_target = (WEATHER[pick] as Dictionary).duplicate()


func _update_sky(delta: float, dt: float) -> void:
	# the clock
	if state == State.TITLE or state == State.LOADOUT:
		day_clock = 3.5
	elif wave > 0:
		var in_day := ((wave - 1) % DAY_LEN) + 1
		var target := float(in_day) * 24.0 / DAY_LEN
		if not wave_active and wave % DAY_LEN == 0:
			target = 24.0
		day_clock = move_toward(day_clock, target, dt * (0.032 if wave_active else 0.5))
	tod = fposmod(6.0 + day_clock, 24.0)
	# weather eases toward the forecast
	var k := 1.0 - exp(-delta * 0.08)
	for key in ["ir", "gain", "tv", "sun", "fire"]:
		wx[key] = lerpf(float(wx[key]), float(wx_target[key]), k)
	wx["sky"] = (wx["sky"] as Vector3).lerp(wx_target["sky"], k)
	var want_p: int = wx_target["precip"]
	if want_p != precip_type:
		precip_amt = move_toward(precip_amt, 0.0, delta * 0.25)
		if precip_amt <= 0.0:
			precip_type = want_p
	else:
		precip_amt = move_toward(precip_amt, 1.0 if want_p > 0 else 0.0, delta * 0.12)
	# the sun, the moon and the sky
	var elev := sin(PI * (tod - 6.0) / 12.0)
	var day_k := clampf(elev * 3.0 + 0.15, 0.0, 1.0)
	var warm := clampf(1.0 - elev * 3.0, 0.0, 1.0) * day_k
	var w_sun: float = wx["sun"]
	var az := PI * (tod - 6.0) / 12.0
	var sd := Vector3(-cos(az), maxf(elev, 0.08) * 1.3, -0.4).normalized() if day_k > 0.05 else Vector3(0.35, 0.8, -0.45).normalized()
	var sun_c := Vector3(1.0, 0.98, 0.92).lerp(Vector3(1.0, 0.6, 0.34), warm) * 0.85 * day_k * w_sun
	var moon_c := Vector3(0.1, 0.12, 0.18) * (1.0 - day_k) * (0.35 + 0.65 * w_sun)
	var amb := Vector3(0.025, 0.035, 0.06).lerp(Vector3(0.27, 0.31, 0.37), day_k) * (1.0 + (1.0 - w_sun) * 0.5)
	var base: Vector3 = world.get("sky", Vector3(0.66, 0.74, 0.84))
	var wsky: Vector3 = wx["sky"]
	var day_sky := Vector3(base.x * wsky.x, base.y * wsky.y, base.z * wsky.z)
	var sky := Vector3(0.02, 0.03, 0.06).lerp(day_sky.lerp(Vector3(0.86, 0.55, 0.38), warm * 0.65), day_k)
	light = day_k
	RenderingServer.global_shader_parameter_set("sun_dir", sd)
	RenderingServer.global_shader_parameter_set("sun_col", sun_c + moon_c)
	RenderingServer.global_shader_parameter_set("amb_col", amb)
	RenderingServer.global_shader_parameter_set("night", 1.0 - day_k)
	RenderingServer.global_shader_parameter_set("sky_col", sky)
	RenderingServer.global_shader_parameter_set("tv_fog", float(world["tv_fog"]) * float(wx["tv"]) * lerpf(0.6, 1.0, day_k))
	RenderingServer.global_shader_parameter_set("haze_dist", float(world["haze_dist"]) * float(wx["ir"]))
	if env and tv_mode:
		env.background_color = Color(sky.x, sky.y, sky.z)


## Thermal crossover: around dawn and dusk everything sits at the same temperature and the IR
## picture goes flat. Rain and dust flatten it too.
func ir_gain() -> float:
	var cross := exp(-pow(tod - 7.5, 2.0) / 1.5) + exp(-pow(tod - 18.5, 2.0) / 1.5)
	return 1.4 * float(wx["gain"]) * (1.0 - 0.3 * clampf(cross, 0.0, 1.0))


func weather_fire() -> float:
	return float(wx.get("fire", 1.0))


func clock_text() -> String:
	return "%02d:%02dL" % [int(tod), int(fposmod(tod, 1.0) * 60.0)]


func weather_name() -> String:
	return String((WEATHER[weather] as Dictionary)["name"])


# ---------------------------------------------------------------- first-sortie tutorial
func _tutorial(delta: float) -> void:
	if not tutorial_on or autotest or mode == "cas":
		return
	if tut_cur != tut_step:
		tut_cur = tut_step
		tut_t = 0.0
		match tut_step:
			0:
				tut_mark = slew_acc
			2:
				tut_mark = kills
			3:
				tut_mark = arsenal.cur
			6:
				tut_mark = tv_toggles
			7:
				tut_mark = armory_opens
	tut_t += delta
	var done := false
	match tut_step:
		0:
			done = slew_acc - tut_mark > 600.0
		1:
			done = fov < 6.0
		2:
			done = kills - tut_mark >= 5
		3:
			done = arsenal.cur != int(tut_mark)
		4:
			done = track_lock >= 0
		5:
			done = tac_open
		6:
			done = tv_toggles > int(tut_mark)
		7:
			done = armory_opens > int(tut_mark)
		_:
			done = tut_t > 14.0
	if done or tut_t > 50.0:
		tut_step += 1
		sfx.play("beep", -8.0, 1.5)
		if tut_step >= TUT_STEPS:
			tutorial_on = false
			radio("PILOT", "That's the job. Good hunting, Spectre.")
			save_pilot()


func tut_text() -> String:
	match tut_step:
		0:
			return "SLEW  //  Move the mouse (or left stick) to look around. The sensor stays locked on the ground while you orbit."
		1:
			return "ZOOM  //  Mouse wheel, right mouse button or left trigger to zoom in on the horde."
		2:
			return "FIRE  //  Hold the left mouse button or right trigger. The twin .50 fires at once; the GAU-19 gatling (%s) takes a moment to spin up. Kill five." % key_name("next_weapon")
		3:
			return "WEAPONS  //  Number keys select a weapon; %s / %s or the bumpers cycle. Try the twin .50s on 1." % [key_name("prev_weapon"), key_name("next_weapon")]
		4:
			return "POINT TRACK  //  Put the crosshair on an infected and press %s (or A). Your guns lead it." % key_name("track")
		5:
			return "TACTICAL MAP  //  %s (or Y) shows the whole AO: where they mass, and where they're going." % key_name("tac_map")
		6:
			return "SENSOR  //  %s switches between the IR imager and the colour TV camera. IR owns the night." % key_name("sensor")
		7:
			return "ARMORY  //  Kills earn requisition. %s (or Back) opens the armory: weapons, upgrades, defences." % key_name("armory")
		8:
			return "FLYING  //  %s/%s throttle, %s/%s altitude, %s/%s orbit. Low and slow is accurate; high and wide is safe." % [key_name("throttle_up"), key_name("throttle_down"), key_name("climb"), key_name("descend"), key_name("orbit_in"), key_name("orbit_out")]
		9:
			return "GROUND OPS  //  Watch the radio for flares and convoys. Keep them alive: big rewards, and more people in the refuge."
	return ""


## Wave events. Gold Rush and Meteor Shower run on a clock; Blood Moon lasts the wave;
## Supply Drop and the Golden Pinata happen once.
func _start_event(id: String) -> void:
	wave_event = id
	event_acc = 0.0
	event_until = t + 1.0
	match id:
		"gold":
			rp_event = 3.0
			event_until = t + 45.0
			banner = "GOLD RUSH  //  x3 REQUISITION  //  45 S"
			radio("TOC", "Spectre, Overwatch. Command just tripled the bounty for the next forty-five seconds. Make it rain.", true)
		"meteors":
			event_until = t + 30.0
			banner = "METEOR SHOWER  //  30 S"
			radio("TOC", "Uh, Spectre, NORAD reports a meteor shower coming down right on the AO. Enjoy the show.", true)
		"supply":
			for w in arsenal.weapons:
				if w["owned"]:
					arsenal.fill(w)
			banner = "SUPPLY DROP  //  EVERY RACK FULL"
			radio("LOADMASTER", "Resupply bird just topped us off. Every rack is full, Spectre.", true)
			sfx.play("buy", 0.0)
		"blood":
			rp_event = 2.0
			speed_event = 1.4
			event_until = INF
			banner = "BLOOD MOON  //  FASTER  //  x2 REQUISITION"
			radio("TOC", "Blood moon tonight, Spectre. They're moving faster, and the bounty's doubled.", true)
		"pinata":
			for d in horde.BOSSES:
				if d["id"] == "pinata":
					spawn_boss(d)
	if id != "pinata":
		banner_t = real_t
		sfx.play("alarm", -8.0, 1.5)


func _update_event(dt: float) -> void:
	if wave_event == "":
		return
	if wave_event == "meteors":
		event_acc += dt
		while event_acc >= 0.4:
			event_acc -= 0.4
			arsenal.meteor()
	if t >= event_until:
		_end_event()


func _end_event() -> void:
	if wave_event == "gold":
		radio("TOC", "Gold rush is over. Bounty's back to normal.")
	elif wave_event == "blood":
		radio("TOC", "The blood moon's setting.")
	wave_event = ""
	rp_event = 1.0
	speed_event = 1.0


## The HUD line for a running event, or "".
func event_text() -> String:
	match wave_event:
		"gold":
			return "GOLD RUSH  x3 REQUISITION  %d S" % int(event_until - t)
		"meteors":
			return "METEOR SHOWER  %d S" % int(event_until - t)
		"blood":
			return "BLOOD MOON  x2 REQUISITION  //  THEY'RE FASTER"
	return ""


## A moon has landed. The sensor saturates, the refuge suffers if it was close, the airframe rings.
func on_moon(pos: Vector3, w: Dictionary) -> void:
	whiteout = 1.0
	add_heat_source(pos + Vector3.UP * 100.0, 700.0, 40.0)
	scorch(pos, 1300.0, 1.0)
	hud.glitch = 4.0
	flash = 1.0
	var r := Vector2(pos.x, pos.z).length()
	var loss := float(w["ff_max"]) * clampf(1.0 - (r - wall_r) / float(w["ff_range"]), 0.0, 1.0)
	if loss > 0.0:
		integrity -= loss
		radio("OVERWATCH", "The impact hit the %s! Spectre, what did you DO?" % refuge_name.to_lower(), true)
	shock_at = t + air_pos.distance_to(pos) / 340.0
	shock_amp = 1.8
	radio("FCO", "IMPACT. The sensor's gone white... oh my God.", true)
	radio("TOC", "Spectre, Overwatch. Seismographs on three continents just called us. Confirm the herd is gone.")


## Extra requisition on top of the kill itself (the Auric Gatling's gold).
func bonus_rp(n: int, pos: Vector3) -> void:
	if n <= 0:
		return
	var g := int(round(n * stat("rp") * rp_event))
	rp += g
	rp_total += g
	if randf() < 0.3:
		popups.append({"pos": pos + Vector3(0, 6, 0), "text": "$%d" % g, "t": real_t, "big": false})


func _spawn_clump(c: Dictionary, n: int, r_at := -1.0, speed_scale := 1.0) -> void:
	# Hordes mass well outside the town, 1.2-2.8 km out, and walk in: a gunship engages them
	# on the approach, not at point blank. Some infected still emerge from the buildings.
	var lo := maxf(arrive.y + 30.0, float(c["rmin"]))
	var r := r_at
	if r < 0.0:
		# late waves flood every part of every approach, from the edge of town to the map edge
		if randf() < 0.15 + 0.2 * flood and lo < 650.0:
			r = randf_range(maxf(lo, 300.0), 800.0 + 600.0 * flood)
		else:
			var far_lo := maxf(lo, 1200.0 - 300.0 * flood)
			r = randf_range(far_lo, maxf(minf(2800.0 + 400.0 * flood, float(c["rmax"])), far_lo + 100.0))
	var ang: float = c["ang"]
	var lat := 0.0
	var spread_lat := 4.0
	if int(c["type"]) == 0:
		var hw: float = c["hw"]
		lat = randf_range(-hw + 5.0, hw - 5.0)
		spread_lat = maxf(1.0, minf(hw - 3.0 - absf(lat), 1.0 + sqrt(n) * 0.5))
		if n > 400:
			lat = 0.0
			spread_lat = hw - 3.0
	else:
		ang += randf_range(-float(c["half"]), float(c["half"]))
		spread_lat = 2.0 + sqrt(n) * 0.9
	var radial := Vector2(cos(ang), sin(ang))
	var perp := Vector2(-radial.y, radial.x)
	var kind := 0
	var roll := randf()
	if n <= 400:
		if roll < brute_frac:
			kind = 2
			n = mini(n, 14)
		elif roll < brute_frac + runner_frac:
			kind = 1
	# Human-scale gaits: a healthy adult walks ~1.3 m/s and jogs ~3 m/s.
	# The herd walks a steady human pace; runners manage a ragged jog; brutes lumber.
	var base_v := randf_range(0.9, 1.4) * (1.0 + wave * 0.01) * speed_scale * stat("horde_speed")
	if kind == 1:
		base_v = randf_range(2.4, 3.4)
	elif kind == 2:
		base_v = randf_range(0.6, 0.9)
	base_v *= speed_event
	var spread_r := 3.0 + sqrt(n) * 1.6
	for i in n:
		var rr := r + randfn(0.0, spread_r)
		var ll := lat + clampf(randfn(0.0, spread_lat * 0.6), -spread_lat, spread_lat)
		var p := radial * rr + perp * ll
		if not horde.spawn(p.x, p.y, base_v * randf_range(0.9, 1.1), kind, randf_range(arrive.x, arrive.y)):
			return


func _update_waves(dt: float) -> void:
	if not wave_active:
		intermission -= dt
		if intermission <= 0.0:
			_begin_wave()
		return
	_update_bosses_due()
	if to_spawn > 0:
		if horde.alive_count >= int(horde.max_alive) - 1500:
			# the horde is at the cap: hold the rest of the wave until there's room
			next_clump = t
		else:
			while t >= next_clump and to_spawn > 0:
				var n := mini(to_spawn, randi_range(20, 150 + wave * 25))
				if bool(world.get("torment", false)):
					# the back of the tide, still coming over the horizon
					_spawn_tide(n, 2040.0, 2120.0)
				else:
					_spawn_clump(active_corridors[randi() % active_corridors.size()], n)
				to_spawn -= n
				next_clump += n / spawn_rate
	elif horde.alive_count - horde.farm_alive <= 0 and boss_queue.is_empty() and not missions.evac_running():
		wave_active = false
		if wave_event == "blood":
			_end_event()
		_wave_cleared()


## Wave over: pay out, and every fifth wave, a day survived.
func _wave_cleared() -> void:
	var lines: Array = []
	var base := 600 + 400 * wave
	lines.append(["Wave %d cleared" % wave, base])
	var lost := wave_integrity0 - integrity
	if lost < 1.0:
		lines.append(["Flawless defence: the walls held", int(base * 0.5)])
	elif integrity >= 75.0:
		lines.append(["Refuge above 75%", int(base * 0.2)])
	var day_end := wave % DAY_LEN == 0
	var repaired := 0.0
	if day_end:
		var d := wave / DAY_LEN
		lines.append(["Day %d survived" % d, 2500 * d])
		repaired = minf(DAY_REPAIR * stat("day_repair"), 100.0 - integrity)
		integrity += repaired
		for w in arsenal.weapons:
			if w["owned"]:
				arsenal.fill(w)
		# the refuge builds out a little more with every day it survives
		defences.grow_day()
	var bonus := 0
	for l in lines:
		bonus += int(l[1])
	bonus = int(round(bonus * stat("rp")))
	rp += bonus
	rp_total += bonus
	wave_summary = {"wave": wave, "day": day(), "day_end": day_end, "kills": kills - wave_kills0,
		"earned": rp_total - wave_rp0, "lines": lines, "bonus": bonus, "repaired": repaired, "integrity": integrity}
	if day_end:
		banner = "DAY %d SURVIVED  //  REFUGE REPAIRED +%d%%  //  +%s RP" % [wave / DAY_LEN, int(round(repaired)), Hud.commas(bonus)]
		radio("OVERWATCH", "Sun's up, Spectre. Day %d done and we're still here. Engineers are patching the walls, and every rack aboard is full." % (wave / DAY_LEN), true)
		sfx.play("buy", 0.0, 0.8)
	else:
		banner = "WAVE %d CLEARED  //  +%s RP" % [wave, Hud.commas(bonus)]
		radio("TOC", "Spectre, Overwatch. Sector's cold. Requisition is open, rearm while you can.")
	banner_t = real_t
	arsenal.resupply()
	save_pilot()
	if mode == "cas":
		# no perk screen in the cockpit: a breather, then the next wave
		intermission = 12.0
		return
	offer_perks(day_end)


func day() -> int:
	return maxi(1, (maxi(wave, 1) - 1) / DAY_LEN + 1)


func _update_integrity(dt: float) -> void:
	integrity -= horde.arrived_weight * 0.0016 * dt * stat("wall_dmg") * float(missions.wall_k)
	integrity = minf(100.0, integrity + (stat("add_regen") + maxi(0, population - pop0) * 0.00015) * dt)
	if autotest:
		integrity = maxf(integrity, 50.0)
	breach_cd -= dt
	low_cd -= dt
	alarm_cd -= dt
	if horde.arrived_count > 20 and breach_cd <= 0.0:
		var s: int = horde.worst_sector()
		if s >= 0:
			radio("OVERWATCH", "They're at the %s wall! Put rounds on the wall, NOW!" % String(SECTORS[s]).to_lower(), true)
			breach_cd = 22.0
	if integrity < 35.0 and low_cd <= 0.0:
		radio("OVERWATCH", "We're being overrun! Spectre, we need everything you've got!", true)
		low_cd = 30.0
	if integrity < 35.0 and alarm_cd <= 0.0:
		sfx.play("alarm", -10.0)
		alarm_cd = 6.0
	if integrity <= 0.0:
		_game_over("THE %s HAS FALLEN" % refuge_name, "All stations... the %s has fallen." % refuge_name.to_lower())


## The last evacuation bird is out: this AO's campaign is won.
var over_victory := false
var evacuated: Dictionary = {}


func campaign_won() -> void:
	evacuated[ao_id] = true
	var bonus := int(round(25000.0 * stat("rp")))
	rp += bonus
	rp_total += bonus
	over_victory = true
	wave_summary = {"bonus": bonus}
	sfx.play("buy", 2.0, 0.7)
	_game_over("%s EVACUATED" % refuge_name, "All stations, Overwatch. The %s is empty. Everyone's out. Spectre, bring it home." % refuge_name.to_lower())


func _game_over(reason: String, line: String) -> void:
	if state == State.OVER:
		return
	integrity = maxf(integrity, 0.0)
	state = State.OVER
	over_t = 0.0
	over_reason = reason
	if not autotest:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	sfx.stop_all_guns()
	radio("OVERWATCH", line, true)
	save_pilot()


## Standoff bonus: the further from the refuge you stop them, the more requisition (up to 2x).
func standoff_mult(pos: Vector3) -> float:
	return 1.0 + clampf((Vector2(pos.x, pos.z).length() - 600.0) / 1800.0, 0.0, 1.0) * stat("standoff")


func add_kills(k: int, pos: Vector3, popup := true) -> void:
	if k <= 0:
		return
	var mult := standoff_mult(pos)
	var gain := int(round(k * mult * stat("rp") * rp_event))
	kills += k
	sortie_kills += k
	if stat("add_heal") > 0.0:
		integrity = minf(100.0, integrity + k * stat("add_heal"))
	rp += gain
	rp_total += gain
	best_multi = maxi(best_multi, k)
	if popup:
		var text := "+%d" % k
		if mult >= 1.15:
			text += "  x%.1f" % mult
		popups.append({"pos": pos + Vector3(0, 4, 0), "text": text, "t": real_t, "big": k >= 25})
		if popups.size() > 40:
			popups.pop_front()


func _feed(text: String) -> void:
	feed.append({"text": text, "t": real_t})
	while feed.size() > 7:
		feed.pop_front()


## Called by the arsenal for every detonation.
func on_impact(pos: Vector3, w: Dictionary, k: int, from_a10: bool) -> void:
	if not from_a10:
		missions.on_impact(pos, w, k)
		if mode == "cas":
			cas.on_player_impact(pos, k)
	if k > 0:
		var gun: bool = w["kind"] in ["rotary", "auto"] or w["id"] == "skeet"
		add_kills(k, pos, k >= 5 or not gun)
		# support assets share the flag; only the Hog's own 30 mm counts as a gun-run kill
		var hawg: bool = from_a10 and w["id"] == "gau8"
		if k >= (20 if mode == "cas" and from_a10 else 8):
			var who := "HAWG 1-1" if hawg else String(w.get("short", String(w["id"]).to_upper()))
			_feed("%s  +%d  @ %.1f KM" % [who, k, Vector2(pos.x, pos.z).length() / 1000.0])
		if hawg:
			a10_kills += k
		if k >= 40 and praise_cd <= 0.0:
			radio("FCO", ["Good hits, good hits!", "That's a lot of bodies.", "Splash. Whole pack just evaporated.", "Direct hit. Nothing moving there now."].pick_random())
			praise_cd = 12.0
	# fire on or near the stadium hurts the people we are protecting
	var r := Vector2(pos.x, pos.z).length()
	var reach := float(w["r_frag"]) * 0.6
	if r < wall_r + reach and not from_a10:
		var f := 1.0 if r < wall_r else 1.0 - (r - wall_r) / reach
		integrity -= float(w["ff"]) * f
		if danger_cd <= 0.0 and float(w["ff"]) * f > 0.1:
			radio("OVERWATCH", "CHECK FIRE! CHECK FIRE! You're hitting the %s!" % refuge_name.to_lower(), true)
			danger_cd = 8.0
	# the air over a big blast shimmers for a while, and the ground and buildings stay charred
	if float(w["r_frag"]) >= 14.0:
		add_heat_source(pos + Vector3.UP * 2.0, float(w["r_frag"]) * 0.45, clampf(float(w["r_frag"]) / 6.0, 3.0, 14.0))
	if float(w["r_frag"]) >= 9.0:
		scorch(pos, float(w["r_frag"]) * 0.75, clampf(0.3 + float(w["r_frag"]) / 120.0, 0.3, 0.95))
	# a big blast in the sensor's view blooms the detector and kicks the AGC
	if float(w["r_frag"]) >= 18.0 and cam.is_position_in_frustum(pos):
		var bloom := clampf(0.2 + 0.25 * 9.0 / fov * sqrt(float(w["r_frag"]) / 28.0), 0.2, 0.9)
		flash = maxf(flash, bloom)
	if float(w["r_frag"]) >= 80.0:
		kick(clampf(float(w["r_frag"]) / 100.0, 0.5, 1.6))


## A nuclear weapon has gone off (Davy Crockett, B61 or W70). Blast kills are applied by the
## horde's shock front as it expands; here we handle the sensor, the refuge and our own airframe.
func on_nuke(pos: Vector3, w: Dictionary) -> void:
	nukes_used += 1
	var sc: float = w["fx_scale"]
	var neutron: bool = w["kind"] == "neutron"
	add_heat_source(pos + Vector3.UP * 60.0 * sc, 260.0 * sc, 30.0)
	scorch(pos, float(w["r_kill"]) * 0.9, 1.0)
	if not neutron:
		scorch(pos, float(w["r_frag"]) * 0.6, 0.5)
	whiteout = clampf(sc * 1.3, 0.55, 1.0)
	hud.glitch = 3.5 * maxf(sc, 0.5)
	flash = 1.0
	var r := Vector2(pos.x, pos.z).length()
	var loss := float(w["ff_max"]) * clampf(1.0 - (r - wall_r) / float(w["ff_range"]), 0.0, 1.0)
	if loss > 0.0:
		integrity -= loss
		if neutron:
			radio("OVERWATCH", "Radiation alarms all over the %s! People are going down, Spectre!" % refuge_name.to_lower(), true)
		else:
			radio("OVERWATCH", "The blast hit the %s! We have casualties, Spectre, a lot of them!" % refuge_name.to_lower(), true)
	var d := air_pos.distance_to(pos)
	if d < float(w["air_lethal"]) * stat("nuke_safe"):
		if neutron:
			_game_over("SPECTRE 2-1 CREW INCAPACITATED", "Spectre two-one, radio check... Spectre two-one, respond...")
		else:
			_game_over("SPECTRE 2-1 LOST", "Spectre two-one is down... caught in its own detonation.")
		return
	var shock_range := 2800.0 * sqrt(sc)
	if d < shock_range and not neutron:
		shock_at = t + d / 340.0
		shock_amp = clampf((shock_range - d) / 1600.0, 0.4, 1.8)
	radio("FCO", "DETONATION. Sensor's washed out... recovering.", true)
	match String(w["id"]):
		"davy":
			radio("PILOT", "That was the small one. Small. Okay.")
		"neutron":
			radio("FCO", "Blast was tiny... wait. They're still walking. Give it a few seconds.")
			radio("FCO", "There they go. Every heat signature out there is dropping.")
		_:
			radio("PILOT", "Shock wave inbound, brace, brace, brace!" if d < shock_range else "Good separation. That's... a mushroom cloud over the city.")
			radio("TOC", "Spectre, Overwatch. We felt that from here. Confirm the herd is gone.")


func radio(who: String, text: String, urgent := false) -> void:
	var msg := {"who": who, "text": text}
	if urgent:
		radio_q.push_front(msg)
	else:
		radio_q.append(msg)
	while radio_q.size() > 5:
		radio_q.pop_back()


func _update_radio(dt: float) -> void:
	if radio_cur.is_empty():
		if radio_q.size() > 0:
			radio_cur = radio_q.pop_front()
			radio_t = 0.0
			sfx.play("radio_on", -6.0)
	else:
		radio_t += dt
		if radio_t > 1.6 + String(radio_cur["text"]).length() * 0.045:
			sfx.play("radio_off", -8.0)
			radio_cur = {}


# ---------------------------------------------------------------- frame
func _process(delta: float) -> void:
	real_t += delta
	zoom_snd_cd -= delta
	praise_cd -= delta
	danger_cd -= delta
	# time compression only while flying, and never with the infected at the wall
	if time_scale > 1.0 and (state != State.PLAYING or horde.arrived_count > 0):
		time_scale = 1.0
		if state == State.PLAYING:
			radio("PILOT", "Contact at the wall, dropping time compression.", true)
	var dt := 0.0 if state in [State.PAUSED, State.ARMORY, State.PERK] else delta * time_scale
	if state == State.OVER:
		over_t += delta
	if state == State.PLAYING and not tac_open and not autotest:
		# arrow keys: fine slew for precise holds at long range
		var fine := Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
		if fine != Vector2.ZERO:
			_slew(fine * 140.0 * delta)

	t += dt
	RenderingServer.global_shader_parameter_set("sim_time", t)
	horde.time = t
	fx.time = t
	_flight_input(delta)
	if not autotest:
		_joy_poll(delta)
	_update_aircraft(dt)
	_update_sky(delta, dt)
	_update_world_fires(dt)
	_update_flares(dt)
	if state == State.PLAYING:
		_update_waves(dt)
		_update_integrity(dt)
		_boss_events()
		_update_event(dt)
		_farm_tick()
		defences.update(dt)
		ops.update(dt)
		missions.update(dt)
		_tutorial(delta)
	if state == State.TITLE or state == State.LOADOUT:
		# attract mode: drift the sensor slowly along an avenue
		track = track.lerp(attract + Vector3(sin(real_t * 0.05) * 120.0, 0.0, 30.0 * sin(real_t * 0.07)), 1.0 - exp(-delta * 0.3))
	if shock_at > 0.0 and t >= shock_at:
		shock_at = -1.0
		kick(shock_amp)
		sfx.play("exp_huge", -2.0, 0.7)
		radio("PILOT", "Overpressure! Airframe's holding.", true)
	var us := Time.get_ticks_usec()
	horde.update_sim(dt, wave)
	prof_horde += Time.get_ticks_usec() - us
	add_kills(horde.take_rad_kills(), horde.rad_center, false)
	_update_track()
	if state == State.PLAYING:
		save_t += delta
		if save_t > 20.0:
			save_t = 0.0
			save_pilot()
		# lifetime requisition earns rank
		var rk := clearance()
		if rk > rank_shown:
			rank_shown = rk
			banner = "PROMOTED  //  %s" % rank_name()
			banner_t = real_t
			radio("TOC", "Spectre two-one, Overwatch. Congratulations, %s. You've earned it." % rank_name().capitalize(), true)
			sfx.play("buy", 0.0, 0.7)
		# the moment the next rung becomes affordable, the crew chief says so (once per system)
		goal_check_t -= delta
		if goal_check_t <= 0.0:
			goal_check_t = 1.0
			var g: Dictionary = next_goal()
			if not g.is_empty() and String(g["id"]) != goal_called and rp >= int(g["price"]) and arsenal.unlocked(g):
				goal_called = String(g["id"])
				radio("CREW CHIEF", "Requisition just came through for the %s. Say the word and it's aboard. [%s]" % [String(g["name"]), key_name("armory")], true)
		# a refuge under pressure starts to burn
		refuge_fire_t -= dt
		if integrity < 60.0 and refuge_fire_t <= 0.0:
			refuge_fire_t = lerpf(0.15, 1.2, integrity / 60.0)
			var p := Vector2.from_angle(randf() * TAU) * randf_range(0.0, wall_r * 0.8)
			fx.particle(true, Vector3(p.x, 2.0, p.y), Vector3.UP * 3.0, randf_range(6.0, 14.0), 3.0, 8.0, 1.4, 1, -0.02, 0.4)
			fx.particle(false, Vector3(p.x, 10.0, p.y), Vector3.UP * 6.0, randf_range(12.0, 20.0), 8.0, 28.0, 0.55, 2, -0.02, 0.2)
	var trigger := false
	if mode == "cas":
		# you fly the A-10; the gunship's weapons are the AI's
		if autotest:
			_autotest_trigger()
		if state == State.PLAYING:
			cas.update(dt)
		cas.update_camera(cam, delta)
		_update_aim()
		orbit_vis.clear()
		los_masked = false
	else:
		_update_camera(delta)
		_update_aim()
		_update_los(delta)
		trigger = state == State.PLAYING and not tac_open and ((Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED) or joy_trigger())
		if autotest:
			trigger = _autotest_trigger()
	us = Time.get_ticks_usec()
	arsenal.update(dt, trigger)
	prof_arsenal += Time.get_ticks_usec() - us
	prof_frames += 1
	var engine_pitch := 0.85 + 0.3 * (speed - SPEED_MIN) / (SPEED_MAX - SPEED_MIN)
	if mode == "cas":
		engine_pitch = 0.8 + 0.45 * float(cas.throttle) if not cas.crashed and float(cas.fuel) > 0.0 else 0.3
	sfx.tick(dt, t, engine_pitch)
	if state != State.PAUSED and state != State.ARMORY:
		_update_radio(delta)
	elif state == State.ARMORY and not radio_cur.is_empty():
		# type the current line out, then hold it on screen until the armory closes
		radio_t = minf(radio_t + delta, String(radio_cur["text"]).length() / 55.0 + 0.1)

	flash = maxf(0.0, flash - delta * 2.2)
	whiteout = maxf(0.0, whiteout - delta * 0.3)
	# a clean picture: no gain pumping, lag smear, interlace, shimmer or detector artefacts
	agc = 0.0
	post_mat.set_shader_parameter("smear", Vector2.ZERO)
	post_mat.set_shader_parameter("sensor_k", 0.0)
	post_mat.set_shader_parameter("haze_n", 0)
	_flush_scorch()
	post_mat.set_shader_parameter("palette", palette)
	post_mat.set_shader_parameter("flash", flash * 0.55)
	post_mat.set_shader_parameter("whiteout", smoothstep(0.0, 0.6, whiteout))
	post_mat.set_shader_parameter("agc", agc)
	post_mat.set_shader_parameter("t", real_t)
	post_mat.set_shader_parameter("blur", clampf(absf(fov - fov_target) / maxf(fov, 0.1) * 4.0, 0.0, 2.0))
	# the TV camera gets grainy as the light goes
	var tv_grain := (1.0 + 4.0 * (1.0 - light)) if tv_mode else 1.0
	post_mat.set_shader_parameter("noise_amt", (0.04 + 0.02 * clampf(9.0 / fov - 1.0, 0.0, 1.0)) * stat("noise") * tv_grain + whiteout * 0.25)
	post_mat.set_shader_parameter("gain", ir_gain())
	post_mat.set_shader_parameter("precip", precip_type if weather_fx else 0)
	post_mat.set_shader_parameter("precip_amt", precip_amt)
	_update_pip()
	hud.queue_redraw()


# ---------------------------------------------------------------- the sensor's own character
## Feeds post.gdshader: how far the picture moved since last frame (the detector's image lag
## trails along it, and the TV's interlaced fields comb with it), and where on screen heat is
## rising off something burning (the picture shimmers above it).
var prev_look := Vector3.ZERO
var smear_uv := Vector2.ZERO
var heat_sources: Array = []    # transient hot spots: {pos, r, t0, dur}
var haze_buf := PackedVector4Array()


func _update_sensor_fx(delta: float) -> void:
	var vp := get_viewport().get_visible_rect().size
	var fwd := -cam.global_transform.basis.z
	var motion := Vector2.ZERO
	if prev_look != Vector3.ZERO and delta > 0.0:
		var p0 := cam.global_position + prev_look * 1000.0
		if not cam.is_position_behind(p0):
			motion = (cam.unproject_position(p0) - vp * 0.5) / vp
	prev_look = fwd
	# the array's lag is ~25 ms whatever the frame rate: the smear is how far the picture moves in that
	var lag := motion / maxf(delta, 0.001) * 0.025
	if lag.length() > 0.05:
		lag = lag.normalized() * 0.05
	smear_uv = smear_uv.lerp(lag, 0.6)
	# from the A-10's cockpit it's your own eyes (or the HUD's FLIR): much less of the camera's character
	post_mat.set_shader_parameter("smear", smear_uv * (0.25 if mode == "cas" else 1.0))
	post_mat.set_shader_parameter("sensor_k", 0.25 if mode == "cas" else 1.0)
	# heat shimmer: fires burning down, the refuge if it's burning, and fresh blasts
	var srcs: Array = []
	for z in arsenal.zones:
		var frac := 1.0 - (t - float(z["t0"])) / float(z["dur"])
		if frac <= 0.0:
			continue
		var a: Vector3 = z["a"]
		var b: Vector3 = z["b"]
		srcs.append([(a + b) * 0.5, maxf(float(z["r"]), a.distance_to(b) * 0.5), frac])
	if integrity < 60.0:
		srcs.append([Vector3(0, 10, 0), wall_r * 0.7, (60.0 - integrity) / 60.0])
	for k in range(heat_sources.size() - 1, -1, -1):
		var hs: Dictionary = heat_sources[k]
		var age := t - float(hs["t0"])
		if age > float(hs["dur"]):
			heat_sources.remove_at(k)
			continue
		srcs.append([hs["pos"], hs["r"], 1.0 - age / float(hs["dur"])])
	var out: Array[Vector4] = []
	var right := cam.global_transform.basis.x
	for s in srcs:
		var p: Vector3 = s[0]
		if cam.is_position_behind(p):
			continue
		var sp := cam.unproject_position(p)
		var rv := (cam.unproject_position(p + right * float(s[1])) - sp).length() / vp.y
		if rv < 0.003 or sp.x < -vp.x * 0.3 or sp.x > vp.x * 1.3 or sp.y < -vp.y * 0.3 or sp.y > vp.y * 1.5:
			continue
		out.append(Vector4(sp.x / vp.x, sp.y / vp.y, rv, clampf(float(s[2]) * 1.4, 0.0, 1.4)))
	out.sort_custom(func(a: Vector4, b: Vector4) -> bool: return a.z * a.w > b.z * b.w)
	haze_buf.resize(12)
	for i in 12:
		haze_buf[i] = out[i] if i < out.size() else Vector4.ZERO
	post_mat.set_shader_parameter("haze_src", haze_buf)
	post_mat.set_shader_parameter("haze_n", mini(out.size(), 12))


## Persistent battle damage: blasts and fires char the ground and the buildings around them, and
## it stays that way for the rest of the sortie. A 512 x 512 map over the AO (13 m a texel) that
## ground.gdshader and world.gdshader read as scorch_map.
const SCORCH_N := 512
const SCORCH_HALF := 3400.0
var scorch_img: Image
var scorch_tex: ImageTexture
var scorch_dirty := false
var scorch_t := 0.0


func scorch(pos: Vector3, r: float, amount := 0.8) -> void:
	var k := float(SCORCH_N) / (2.0 * SCORCH_HALF)
	var px := (pos.x + SCORCH_HALF) * k
	var pz := (pos.z + SCORCH_HALF) * k
	var rr := r * k
	if rr < 0.45:
		return
	var x0 := maxi(0, int(px - rr - 1.0))
	var x1 := mini(SCORCH_N - 1, int(px + rr + 1.0))
	var y0 := maxi(0, int(pz - rr - 1.0))
	var y1 := mini(SCORCH_N - 1, int(pz + rr + 1.0))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var d := Vector2(x + 0.5 - px, y + 0.5 - pz).length() / maxf(rr, 0.5)
			if d >= 1.0:
				continue
			var v := amount * (1.0 - d * d)
			if v > scorch_img.get_pixel(x, y).r:
				scorch_img.set_pixel(x, y, Color(v, 0.0, 0.0))
	scorch_dirty = true


func _flush_scorch() -> void:
	if scorch_dirty and real_t - scorch_t > 0.3:
		scorch_t = real_t
		scorch_dirty = false
		scorch_tex.update(scorch_img)


# ---------------------------------------------------------------- the lived-in battlefield
## Fires that keep burning on their own (wrecks, barrel fires, rooftop campfires): keep the
## flames and the smoke coming wherever the sensor can see them.
var fire_acc := 0.0


func _update_world_fires(dt: float) -> void:
	var list: Array = world.get("fires", [])
	if list.is_empty() or dt <= 0.0:
		return
	fire_acc += dt
	if fire_acc < 0.12:
		return
	var step := fire_acc
	fire_acc = 0.0
	for p in list:
		var fp: Vector3 = p
		if not cam.is_position_in_frustum(fp):
			continue
		if randf() < step * 6.0:
			fx.particle(true, fp + Vector3(randf_range(-0.4, 0.4), 0.0, randf_range(-0.4, 0.4)), Vector3.UP * randf_range(1.5, 3.0), randf_range(0.6, 1.2), 1.0, 2.2, randf_range(1.25, 1.55), 1, -0.02, 0.6)
		if randf() < step * 1.2:
			fx.particle(false, fp + Vector3.UP * 2.0, Vector3(randf_range(-0.5, 0.5), randf_range(2.0, 3.5), randf_range(-0.5, 0.5)), randf_range(6.0, 10.0), 2.0, 9.0, 0.45, 2, -0.01, 0.3)


## The grid goes down a district at a time as the days go by: streetlights and lit windows
## (grid_power in the shaders). Day one has everything; by day five it's candles.
const GRID_BY_DAY := [1.0, 0.72, 0.48, 0.28, 0.14, 0.06]


func _apply_grid() -> void:
	var d := clampi(day() - 1, 0, GRID_BY_DAY.size() - 1) if wave > 0 else 0
	RenderingServer.global_shader_parameter_set("grid_power", float(GRID_BY_DAY[d]))


## Illumination flares: after dark, when the infected are pressing the walls, the refuge fires
## parachute flares out over the worst sector. They burn at ~3,000 K for half a minute and light
## the ground for the TV camera (flare_a / flare_b in the shaders); to the IR they're just
## blinding points.
var flares: Array = []
var flare_cd := 0.0


func _update_flares(dt: float) -> void:
	flare_cd -= dt
	var pressed: bool = integrity < 80.0 or horde.arrived_count > 15 or float(horde.nearest_r) < 450.0
	if state == State.PLAYING and wave_active and light < 0.45 and pressed and flare_cd <= 0.0 and flares.size() < 3:
		flare_cd = randf_range(9.0, 15.0)
		var s: int = horde.worst_sector()
		var bearing := deg_to_rad(s * 45.0) if s >= 0 else randf() * TAU
		var dir := Vector3(sin(bearing), 0.0, -cos(bearing))
		flares.append({"pos": Vector3(0, 25, 0), "vel": dir * randf_range(45.0, 70.0) + Vector3.UP * 95.0, "t": 0.0})
		sfx.play_at("rocket", Vector3(0, 20, 0), cam.global_position, -4.0, 0.7)
		if randf() < 0.3 and s >= 0:
			radio("OVERWATCH", "Popping illumination over the %s wall!" % String(SECTORS[s]).to_lower())
	var lit: Array = []
	for k in range(flares.size() - 1, -1, -1):
		var f: Dictionary = flares[k]
		f["t"] = float(f["t"]) + dt
		var ft: float = f["t"]
		var pos: Vector3 = f["pos"]
		var vel: Vector3 = f["vel"]
		if ft < 3.5:
			# coasting up on the rocket's momentum, trailing smoke
			vel += Vector3.DOWN * 9.8 * dt
			if randf() < 0.6:
				fx.particle(false, pos, Vector3.ZERO, 2.0, 0.8, 3.0, 0.5, 2, 0.0, 0.5)
		else:
			# under its parachute: drifting down, burning white
			vel = vel.lerp(Vector3(vel.x * 0.2 + 1.5, -4.0, vel.z * 0.2), 1.0 - exp(-dt * 1.5))
			fx.particle(true, pos, Vector3.ZERO, 0.12, 1.6, 2.4, 3.2, 0)
			if randf() < dt * 6.0:
				fx.particle(false, pos + Vector3.UP, Vector3.UP, 6.0, 1.0, 6.0, 0.5, 2, -0.01, 0.4)
			lit.append([pos, clampf(minf(ft - 3.5, 34.0 - ft) / 2.0, 0.0, 1.0)])
		pos += vel * dt
		f["pos"] = pos
		f["vel"] = vel
		if ft > 34.0 or pos.y < 2.0:
			flares.remove_at(k)
	var fa := Vector4.ZERO
	var fb := Vector4.ZERO
	if lit.size() > 0:
		var p0: Vector3 = lit[0][0]
		fa = Vector4(p0.x, p0.y, p0.z, 1.6 * float(lit[0][1]))
	if lit.size() > 1:
		var p1: Vector3 = lit[1][0]
		fb = Vector4(p1.x, p1.y, p1.z, 1.6 * float(lit[1][1]))
	RenderingServer.global_shader_parameter_set("flare_a", fa)
	RenderingServer.global_shader_parameter_set("flare_b", fb)


## Somewhere hot enough to make the air above it shimmer for a while.
func add_heat_source(pos: Vector3, r: float, dur: float) -> void:
	heat_sources.append({"pos": pos, "r": r, "t0": t, "dur": dur})
	while heat_sources.size() > 24:
		heat_sources.pop_front()


# ---------------------------------------------------------------- autotest
## Scripted session used to smoke-test the build: fires every system in the catalogue
## against a stress horde and saves screenshots to user://autotest/. Uses its own save file.
var aq: Array = []
var aq_wait := 0.0
var aq_hold := 0.0
var aq_slew := Vector3.ZERO
var aq_burst: Dictionary = {}
var aq_mark := 0.0


func _autotest_setup() -> void:
	if "--cas" in OS.get_cmdline_user_args() or "--cas-land" in OS.get_cmdline_user_args():
		_start_cas()
	else:
		_start_game()
	rp = 999999
	rp_total = 999999
	for w in arsenal.weapons:
		w["owned"] = true
	arsenal.resupply()
	if "--stress" in OS.get_cmdline_user_args():
		while horde.alive_count < 30000:
			_spawn_clump(corridors[randi() % corridors.size()], 150)
		_spawn_clump(corridors[0], 2500, maxf(820.0, float(corridors[0]["rmin"]) + 100.0))
		_spawn_clump(corridors[4 % corridors.size()], 2500, maxf(820.0, float(corridors[4 % corridors.size()]["rmin"]) + 100.0))
	var E := Vector3(250, 0, 0)
	aq = [
		["aim", E, 9.0], ["wait", 1.5],
		["load", ["m134", "gau8", "beehive", "hydra", "ahel", "rail"]],
		["sel", "m134"], ["hold", 2.0], ["wait", 1.6], ["shot", "m134"],
		["sel", "gau8"], ["hold", 1.5], ["wait", 1.8], ["shot", "gau8"],
		["sel", "beehive"], ["hold", 0.2], ["wait", 4.0], ["shot", "beehive"],
		["sel", "hydra"], ["hold", 0.2], ["wait", 2.6], ["shot", "hydra"],
		["sel", "ahel"], ["hold", 3.0], ["shot", "laser"],
		["sel", "rail"], ["hold", 1.35], ["wait", 0.8], ["shot", "rail"], ["wait", 1.0],
		["load", ["napalm", "lazydog", "gator", "switchblade", "arty", "tos", "wingman", "tomahawk", "sol", "thor"]],
		["aim", Vector3(0, 0, 250), 12.0], ["sel", "napalm"], ["hold", 0.2], ["wait", 9.0], ["shot", "napalm"],
		["aim", Vector3(-177, 0, 177), 12.0], ["sel", "lazydog"], ["hold", 0.2], ["wait", 7.5], ["shot", "lazydog"],
		["aim", Vector3(-250, 0, 0), 12.0], ["sel", "gator"], ["hold", 0.2], ["wait", 12.0], ["shot", "gator"],
		["aim", Vector3(-177, 0, -177), 12.0], ["sel", "switchblade"], ["hold", 0.2], ["wait", 13.0], ["shot", "switchblade"],
		["aim", Vector3(0, 0, -250), 14.0], ["sel", "arty"], ["hold", 0.2], ["wait", 15.0], ["shot", "arty"],
		["aim", Vector3(177, 0, -177), 14.0], ["sel", "tos"], ["hold", 0.2], ["wait", 10.5], ["shot", "tos"],
		["sel", "wingman"], ["hold", 0.2], ["aim", Vector3.ZERO, 30.0], ["wait", 9.0], ["shot", "wingman"],
		["aim", Vector3(177, 0, 177), 12.0], ["sel", "tomahawk"], ["hold", 0.2], ["wait", 12.5], ["shot", "tomahawk_inbound"], ["wait", 2.5], ["shot", "tomahawk"],
		["aim", E, 12.0], ["sel", "sol"], ["hold", 0.2], ["wait", 3.0], ["aim", Vector3(180, 0, 180), 12.0], ["wait", 4.0], ["shot", "sol"], ["wait", 6.0],
		["load", ["vulcan", "lasermg", "bushmaster", "wp105", "griffin", "micro", "thermite", "glocke", "singularity", "apache"]],
		["aim", Vector3(0, 0, 260), 9.0], ["sel", "vulcan"], ["hold", 1.5], ["wait", 1.2], ["shot", "vulcan"],
		["sel", "lasermg"], ["hold", 1.5], ["wait", 0.3], ["shot", "lasermg"],
		["aim", Vector3(-180, 0, 180), 9.0], ["sel", "bushmaster"], ["hold", 1.2], ["wait", 2.0], ["shot", "bushmaster"],
		["sel", "wp105"], ["hold", 0.2], ["wait", 5.5], ["shot", "wp105"], ["wait", 4.0], ["shot", "wp105_cooling"],
		["aim", Vector3(-260, 0, 0), 9.0], ["sel", "griffin"], ["hold", 0.2], ["wait", 6.0], ["shot", "griffin"],
		["aim", Vector3(-180, 0, -180), 14.0], ["sel", "micro"], ["hold", 0.2], ["wait", 7.0], ["shot", "micro"],
		["aim", Vector3(0, 0, -260), 12.0], ["sel", "thermite"], ["hold", 0.2], ["wait", 13.0], ["shot", "thermite"],
		["aim", Vector3(180, 0, -180), 16.0], ["sel", "glocke"], ["hold", 0.2], ["wait", 6.0], ["shot", "glocke"], ["aim", Vector3(260, 0, -60), 16.0], ["wait", 4.0], ["shot", "glocke_steer"],
		["aim", Vector3(180, 0, 180), 12.0], ["sel", "singularity"], ["hold", 0.2], ["wait", 4.0], ["shot", "singularity"], ["wait", 5.0], ["shot", "singularity_collapse"],
		["aim", Vector3(0, 0, 300), 18.0], ["sel", "apache"], ["hold", 0.2], ["wait", 10.0], ["shot", "apache"],
		["load", ["b52", "constellation", "daisy"]],
		["aim", Vector3(-300, 0, 0), 30.0], ["sel", "b52"], ["hold", 0.2], ["wait", 24.0], ["shot", "b52"],
		["aim", Vector3(0, 0, -400), 30.0], ["sel", "constellation"], ["hold", 0.2], ["wait", 11.0], ["shot", "constellation"],
		["aim", Vector3(300, 0, 300), 25.0], ["sel", "daisy"], ["hold", 0.2], ["wait", 20.0], ["shot", "daisy"], ["wait", 3.0],
		["load", ["smart", "ricochet", "scatter", "ripsaw", "tesla", "auric", "chrono", "graviton", "godgun", "atomic"]],
		["aim", Vector3(260, 0, 0), 9.0], ["sel", "smart"], ["hold", 1.5], ["wait", 2.5], ["shot", "smart"],
		["sel", "ricochet"], ["hold", 1.2], ["wait", 2.5], ["shot", "ricochet"],
		["sel", "scatter"], ["hold", 1.5], ["wait", 2.5], ["shot", "scatter"],
		["aim", Vector3(0, 0, 260), 9.0], ["sel", "ripsaw"], ["hold", 1.5], ["wait", 2.5], ["shot", "ripsaw"],
		["sel", "tesla"], ["hold", 1.2], ["shot", "tesla"],
		["sel", "auric"], ["hold", 1.5], ["wait", 2.0], ["shot", "auric"],
		["aim", Vector3(-260, 0, 0), 9.0], ["sel", "chrono"], ["hold", 1.2], ["wait", 2.0], ["shot", "chrono"],
		["sel", "graviton"], ["hold", 1.2], ["wait", 1.0], ["shot", "graviton"],
		["aim", Vector3(0, 0, -300), 14.0], ["sel", "godgun"], ["hold", 2.5], ["wait", 1.0], ["shot", "godgun"],
		["aim", Vector3(300, 0, -300), 18.0], ["sel", "atomic"], ["hold", 1.2], ["wait", 2.0], ["shot", "atomic"],
		["aim", Vector3(-400, 0, 400), 16.0], ["boss", "colossus"], ["boss", "brood"], ["wait", 1.5], ["shot", "boss"],
		["upgrades"], ["wait", 4.0], ["shot", "defences"],
		["load", ["gau19", "m197", "gsh630", "l70", "pgk", "apkws", "jagm", "gbu12", "stormbreaker", "hpm"]],
		["aim", Vector3(260, 0, 0), 9.0], ["sel", "gau19"], ["hold", 1.2], ["wait", 1.5], ["shot", "gau19"],
		["sel", "m197"], ["hold", 1.2], ["wait", 1.5], ["shot", "m197"],
		["sel", "gsh630"], ["hold", 1.5], ["wait", 1.5], ["shot", "gsh630"],
		["aim", Vector3(0, 0, 260), 9.0], ["sel", "l70"], ["hold", 1.5], ["wait", 2.0], ["shot", "l70"],
		["sel", "pgk"], ["hold", 0.2], ["wait", 5.0], ["shot", "pgk"],
		["sel", "apkws"], ["hold", 1.2], ["wait", 5.0], ["shot", "apkws"],
		["aim", Vector3(-260, 0, 0), 12.0], ["sel", "jagm"], ["hold", 0.2], ["wait", 6.0], ["shot", "jagm"],
		["sel", "gbu12"], ["hold", 0.2], ["wait", 10.0], ["shot", "gbu12"],
		["sel", "stormbreaker"], ["hold", 1.5], ["wait", 10.0], ["shot", "stormbreaker"],
		["aim", Vector3(-180, 0, -180), 12.0], ["sel", "hpm"], ["hold", 3.0], ["shot", "hpm"],
		["load", ["cas", "himars", "mop", "lrhw"]],
		["aim", Vector3(300, 0, 200), 25.0], ["sel", "cas"], ["hold", 0.2], ["wait", 12.0], ["shot", "cas"],
		["sel", "himars"], ["hold", 0.2], ["wait", 16.0], ["shot", "himars"],
		["aim", Vector3(-350, 0, 350), 25.0], ["sel", "lrhw"], ["hold", 0.2], ["wait", 7.0], ["shot", "lrhw"],
		["sel", "mop"], ["hold", 0.2], ["wait", 16.0], ["shot", "mop"],
		["tv"], ["aim", Vector3(0, 0, 0), 30.0], ["wait", 2.0], ["shot", "tv_wide"], ["aim", Vector3(260, 0, 30), 9.0], ["wait", 2.0], ["shot", "tv_close"], ["tv"],
		["load", ["cow", "piano", "boulder", "titan"]],
		["aim", Vector3(250, 0, 100), 12.0], ["sel", "cow"], ["hold", 1.5], ["wait", 9.0], ["shot", "cow"],
		["sel", "piano"], ["hold", 0.2], ["wait", 7.0], ["shot", "piano"],
		["aim", Vector3(-150, 0, 300), 16.0], ["sel", "boulder"], ["hold", 0.2], ["wait", 6.0], ["shot", "boulder"],
		["aim", Vector3(300, 0, -200), 18.0], ["sel", "titan"], ["hold", 0.2], ["wait", 8.0], ["shot", "titan"],
		["event", "meteors"], ["aim", Vector3.ZERO, 30.0], ["wait", 6.0], ["shot", "meteors"],
		["event", "pinata"], ["wait", 1.0],
		["load", ["davy", "neutron"]],
		["aim", Vector3(840, 0, 0), 20.0], ["sel", "davy"], ["hold", 1.3], ["wait", 7.0], ["shot", "davy_flash"], ["wait", 5.0], ["shot", "davy"],
		["aim", Vector3(-840, 0, 0), 25.0], ["sel", "neutron"], ["hold", 2.8], ["wait", 10.5], ["shot", "neutron_flash"], ["wait", 6.0], ["shot", "neutron"], ["wait", 6.0], ["shot", "neutron_late"],
		["load", ["moon"]], ["aim", Vector3(-1800, 0, 0), 30.0], ["sel", "moon"], ["hold", 2.2],
		["wait", 6.0], ["shot", "moon_inbound"], ["wait", 7.0], ["shot", "moon"], ["wait", 4.0], ["shot", "moon_after"],
		["loadout"], ["wait", 0.5], ["shot", "loadout"],
		["armory", 5], ["wait", 0.5], ["shot", "armory"],
		["armory", 0], ["buy", "gau8"], ["wait", 1.5], ["shot", "unlock_gau8"],
		["buy", "atomic"], ["wait", 1.5], ["shot", "unlock_atomic"], ["dismiss"],
		["perks"], ["wait", 0.5], ["shot", "perks"], ["take", 0],
		["armory", 9], ["wait", 0.5], ["shot", "aircraft"],
		["quit"],
	]
	if "--quick" in OS.get_cmdline_user_args():
		# guns and directed energy only
		aq = aq.slice(0, 23)
		aq.append(["quit"])
	elif "--cas" in OS.get_cmdline_user_args():
		# fly in, use every store, an automatic approach to the FARP, rearm, take off, then fly into the ground
		aq = [["wait", 2.0], ["shot", "cas_start"],
			["cas_look", attract + Vector3.UP * 450.0], ["wait", 6.0], ["shot", "cas_inbound"], ["cas_look", attract + Vector3.UP * 140.0], ["wait", 1.0],
			["cas_sel", 0], ["cas_fire", true], ["wait", 1.2], ["shot", "cas_guns"], ["cas_fire", false], ["cas_pull"], ["wait", 6.0],
			["cas_sel", 1], ["cas_fire", true], ["wait", 0.4], ["cas_fire", false], ["wait", 3.0], ["shot", "cas_bombs"],
			["cas_sel", 4], ["cas_fire", true], ["wait", 0.6], ["cas_fire", false], ["wait", 2.0],
			["cas_sel", 3], ["cas_lock"], ["cas_fire", true], ["wait", 0.2], ["cas_fire", false], ["wait", 5.0], ["shot", "cas_mav"],
			["tac"], ["wait", 0.5], ["shot", "cas_map"], ["tac"],
			["cas_rtb"], ["wait", 20.0], ["shot", "cas_approach"], ["wait", 30.0], ["shot", "cas_landed"], ["wait", 20.0], ["shot", "cas_rearm"],
			["cas_takeoff"], ["wait", 25.0], ["shot", "cas_airborne"],
			["cas_dive"], ["wait", 12.0], ["shot", "cas_crash"], ["quit"]]
	elif "--cas-land" in OS.get_cmdline_user_args():
		# just the FARP: a long final, the landing, hot pits, and away again
		aq = [["cas_rtb"], ["wait", 4.0], ["shot", "land_final"], ["wait", 20.0], ["shot", "land_short"], ["wait", 26.0], ["shot", "land_down"],
			["wait", 12.0], ["shot", "land_rearm"], ["wait", 18.0], ["shot", "land_full"], ["cas_takeoff"], ["wait", 22.0], ["shot", "land_takeoff"], ["quit"]]
	elif "--missions" in OS.get_cmdline_user_args():
		# every kind of objective, a danger-close call, the evacuation and the win
		aq = [["load", ["m134", "m102", "jdam"]],
			["mission", "hold"], ["wait", 4.0], ["aim_obj"], ["wait", 2.0], ["shot", "m_hold"], ["mission_end"], ["wait", 2.5], ["shot", "m_hold_done"],
			["mission", "nest"], ["wait", 3.0], ["aim_obj"], ["wait", 2.0], ["shot", "m_nest"], ["nest_hit"], ["wait", 3.0], ["shot", "m_nest_down"],
			["mission", "engineers"], ["wait", 3.0], ["aim_obj"], ["wait", 2.0], ["shot", "m_eng"], ["dc"], ["wait", 1.0], ["shot", "m_dc"],
			["dc_hit"], ["wait", 1.0], ["shot", "m_dc_done"], ["mission_end"], ["wait", 1.0],
			["mission", "medevac"], ["wait", 12.0], ["aim_obj"], ["wait", 2.0], ["shot", "m_medevac"], ["mission_end"],
			["evac"], ["wait", 12.0], ["aim", Vector3.ZERO, 20.0], ["wait", 2.0], ["shot", "m_evac"], ["won"], ["wait", 3.0], ["shot", "m_won"], ["quit"]]
	elif "--armory" in OS.get_cmdline_user_args():
		# the purchase ceremony, and a carpet of sub-munitions on the ordnance panel
		aq = [["load", ["b52", "gau8"]], ["aim", Vector3(-300, 0, 0), 30.0], ["sel", "b52"], ["hold", 0.2],
			["wait", 14.0], ["shot", "b52_a"], ["wait", 4.0], ["shot", "b52_b"], ["wait", 4.0], ["shot", "b52_c"],
			["armory", 0], ["buy", "gau8"], ["wait", 1.5], ["shot", "unlock_gau8"],
			["buy", "atomic"], ["wait", 1.5], ["shot", "unlock_atomic"], ["dismiss"], ["quit"]]
	elif "--demo" in OS.get_cmdline_user_args():
		# the sensor's character, one effect at a time: the horde's heat, bodies cooling, the AGC
		# pumping after a big blast, heat shimmer, image lag and interlace on a fast slew, the
		# detector's fixed pattern, and a night lit at the colour of its temperatures
		rank_shown = clearance()
		var c0: Dictionary = corridors[0]
		for c in corridors:
			if int(c["type"]) == 0:
				c0 = c
				break
		var dir := Vector3(cos(float(c0["ang"])), 0.0, sin(float(c0["ang"])))
		var side := Vector3(-dir.z, 0.0, dir.x)
		var P := dir * 700.0
		var Q := dir * 1150.0
		var Q2 := dir.rotated(Vector3.UP, 0.5) * 1100.0
		var H := dir.rotated(Vector3.UP, 1.3) * 650.0
		var N := dir.rotated(Vector3.UP, -1.2) * 260.0
		var S := P + dir * 200.0
		aq = [["clock", 6.0], ["crowd", P, 320], ["load", ["gau8"]], ["sel", "gau8"],
			["aim", P, 2.2], ["wait", 3.0], ["shot", "demo_horde"],
			["palette", 2], ["wait", 0.4], ["shot", "demo_horde_ironbow"], ["palette", 0],
			["aim", P, 1.0], ["wait", 1.5], ["shot", "demo_horde_close"],
			["aim", P, 5.0], ["wait", 1.2], ["hold", 1.0], ["mark"], ["wait", 2.0], ["shot", "demo_bodies_fresh"],
			["aim", Q, 9.0], ["wait", 2.0], ["shot", "demo_agc_0"],
			["detonate", Q, "jdam"], ["wait", 0.05], ["shot", "demo_agc_1"], ["wait", 0.55], ["shot", "demo_agc_2"], ["wait", 4.0], ["shot", "demo_agc_3"],
			# the same again, frame by frame
			["aim", Q2, 9.0], ["wait", 2.5], ["burst", "agc_a", 6, 960, 540], ["detonate", Q2, "jdam"], ["burst", "agc_b", 110, 960, 540],
			["napalm", H, dir], ["aim", H + Vector3.UP * 20.0, 3.5], ["wait", 4.0], ["shot", "demo_haze"], ["burst", "haze", 50, 800, 450],
			["aim", S, 9.0], ["wait", 1.5], ["slew", side * 420.0, 0.5], ["shot", "demo_slew_ir"],
			["aim", S, 9.0], ["wait", 1.0], ["slew", side * 420.0, 0.3], ["burst", "slew_ir", 30, 960, 540, side * 420.0],
			["tv"], ["aim", S, 9.0], ["wait", 1.5], ["slew", side * 420.0, 0.5], ["shot", "demo_slew_tv"],
			["aim", S, 9.0], ["wait", 1.0], ["slew", side * 420.0, 0.3], ["burst", "slew_tv", 30, 640, 360, side * 420.0], ["tv"],
			["aim", S, 9.0], ["wait", 1.5], ["shot", "demo_fixed_pattern"],
			["aim", P, 5.0], ["since", 60.0], ["shot", "demo_bodies_60s"],
			["clock", 15.5], ["tv"], ["flare", N], ["aim", N, 16.0], ["wait", 2.0],
			["napalm", N + side * 70.0, side], ["detonate", N - side * 90.0 + dir * 60.0, "jdam"], ["wait", 0.35], ["shot", "demo_night_blast"],
			["wait", 5.0], ["shot", "demo_night_tv"], ["tv"], ["wait", 0.5], ["shot", "demo_night_ir"], ["quit"]]


func _autotest_trigger() -> bool:
	if "--tour" in OS.get_cmdline_user_args():
		_tour()
		return false
	var dt := get_process_delta_time()
	if not aq_burst.is_empty():
		# a run of consecutive frames (the middle of the screen) for an animation
		track += aq_slew * dt
		var bi: int = aq_burst["i"]
		DirAccess.make_dir_recursive_absolute("user://autotest/burst")
		get_viewport().get_texture().get_image().get_region(aq_burst["rect"]).save_png("user://autotest/burst/%s_%03d.png" % [String(aq_burst["name"]), bi])
		aq_burst["i"] = bi + 1
		if bi + 1 >= int(aq_burst["n"]):
			aq_burst = {}
			aq_slew = Vector3.ZERO
		return false
	if aq_hold > 0.0:
		aq_hold -= dt
		return state == State.PLAYING
	if aq_wait > 0.0:
		aq_wait -= dt
		track += aq_slew * dt
		return false
	aq_slew = Vector3.ZERO
	while not aq.is_empty():
		var a: Array = aq.pop_front()
		match String(a[0]):
			"aim":
				track = a[1]
				fov_target = a[2]
			"slew":
				# sweep the sensor across the ground at this speed, like a fast flick of the mouse
				aq_slew = a[1]
				aq_wait = a[2]
				return false
			"burst":
				# [name, frames, width, height, slew]: save that many frames in a row from the middle of the screen
				var vs := Vector2i(get_viewport().get_texture().get_size())
				var bw := mini(int(a[3]), vs.x)
				var bh := mini(int(a[4]), vs.y)
				aq_burst = {"name": String(a[1]), "n": int(a[2]), "i": 0, "rect": Rect2i((vs.x - bw) / 2, (vs.y - bh) / 2, bw, bh)}
				aq_slew = a[5] if a.size() > 5 else Vector3.ZERO
				track += aq_slew * dt
				return false
			"clock":
				# hold the time of day here (no wave starts to reset it)
				day_clock = float(a[1])
				intermission = 9999.0
			"palette":
				palette = int(a[1])
			"mark":
				aq_mark = real_t
			"since":
				# wait until this long after the mark
				aq_wait = maxf(0.0, aq_mark + float(a[1]) - real_t)
				return false
			"crowd":
				# a mixed crowd for close-ups: walkers, a knot of runners and a few brutes
				var cp: Vector3 = a[1]
				for k in int(a[2]):
					var o := Vector2.from_angle(randf() * TAU) * sqrt(randf()) * 26.0
					var kind := 0
					var sp := randf_range(0.9, 1.3)
					if k % 9 == 0:
						kind = 1
						sp = randf_range(2.4, 3.2)
					elif k % 23 == 1:
						kind = 2
						sp = randf_range(0.5, 0.7)
					horde.spawn(cp.x + o.x, cp.z + o.y, sp, kind, randf_range(arrive.x, arrive.y))
			"detonate":
				arsenal._impact(a[1], arsenal.by_id(String(a[2])), false)
			"napalm":
				arsenal._napalm(a[1], a[2], arsenal.by_id("napalm"))
			"flare":
				var fd := Vector3((a[1] as Vector3).x, 0.0, (a[1] as Vector3).z).normalized()
				flares.append({"pos": Vector3(0, 25, 0), "vel": fd * 60.0 + Vector3.UP * 95.0, "t": 0.0})
			"load":
				arsenal.loadout = (a[1] as Array).duplicate()
				arsenal.cur = 0
			"sel":
				arsenal.select_id(String(a[1]))
			"hold":
				aq_hold = a[1]
				return state == State.PLAYING
			"wait":
				aq_wait = a[1]
				return false
			"loadout":
				state = State.LOADOUT
				armory_tab = arsenal.CATS.size()
			"event":
				_start_event(String(a[1]))
			"upgrades":
				for u in Perks.REFUGE:
					upg[u["id"]] = u["max"]
				recalc_stats()
			"tv":
				tv_mode = not tv_mode
				_apply_sensor()
			"armory":
				open_armory(false)
				armory_tab = a[1]
			"perks":
				offer_perks()
			"boss":
				for d in horde.BOSSES:
					if d["id"] == a[1]:
						spawn_boss(d, Vector3(track.x, 0.0, track.z) + Vector3(randf_range(-30, 30), 0.0, randf_range(-30, 30)))
			"take":
				take_perk(int(a[1]))
			"buy":
				arsenal.by_id(String(a[1]))["owned"] = false
				buy(String(a[1]))
			"dismiss":
				unlock_card = {}
			"mission":
				missions.obj = {}
				match String(a[1]):
					"hold":
						missions._start_hold()
					"nest":
						missions._start_nest()
					"engineers":
						missions._start_engineers()
					"medevac":
						missions._start_medevac()
			"aim_obj":
				var o: Dictionary = missions.obj
				if o.has("pos"):
					track = o["pos"]
				elif o.has("lm"):
					track = o["lm"]["pos"]
				elif o.has("lzs"):
					track = o["lzs"][0]
				fov_target = 6.0
			"mission_end":
				if missions.obj.has("dur"):
					missions.obj["t"] = float(missions.obj["dur"])
				elif not missions.obj.is_empty():
					missions._finish(false)
			"nest_hit":
				var lm: Dictionary = missions.obj.get("lm", {})
				if not lm.is_empty():
					missions.structure_hit((lm["pos"] as Vector3) + Vector3.UP * 5.0, 550.0, "DELAY")
			"dc":
				var fp: Vector3 = missions.obj.get("pos", Vector3(200, 0, 0))
				for k in 40:
					horde.spawn(fp.x + 30.0 + randf_range(-6, 6), fp.z + randf_range(-6, 6), 0.0, 0, arrive.y)
				missions.dc_cd = 0.0
				missions.request_dc(fp, "ENGINEERS", "the test wall", "team")
			"dc_hit":
				if not missions.dc.is_empty():
					missions.on_impact(missions.dc["target"], arsenal.by_id("gau8"), 60)
			"evac":
				missions._start_evac(missions.STORY["city"])
			"won":
				campaign_won()
			"cas_look":
				var to: Vector3 = (a[1] as Vector3) - cas.pos
				cas.look_yaw = atan2(-to.x, -to.z)
				cas.look_pitch = clampf(atan2(to.y, Vector2(to.x, to.z).length()), -1.2, 1.2)
			"cas_sel":
				cas.select(int(a[1]))
			"cas_fire":
				cas_auto_fire = bool(a[1])
			"cas_lock":
				cas.lock()
			"tac":
				tac_open = not tac_open
			"cas_rtb":
				# put the aircraft on a long final and let the test autopilot land it
				var af: Dictionary = world["airfield"]
				var c: Vector3 = af["center"]
				var d: Vector3 = af["dir"]
				var thr := c - d * float(af["length"]) * 0.5
				cas.pos = thr - d * 3500.0 + Vector3.UP * (3500.0 * tan(deg_to_rad(3.0)) + 20.0)
				cas.prev_pos = cas.pos
				cas.vel = d * 78.0
				cas.att = Basis.looking_at(d, Vector3.UP)
				cas.autoland = true
				cas.look_yaw = atan2(-d.x, -d.z)
				cas.look_pitch = -0.08
			"cas_takeoff":
				cas.autoland = false
				cas.brakes = false
				cas.throttle = 1.0
				var d2: Vector3 = -cas.att.z
				cas.look_yaw = atan2(-d2.x, -d2.z)
				cas.look_pitch = 0.12
			"cas_dive":
				cas.look_pitch = -1.3
			"cas_pull":
				cas.look_pitch = 0.25
			"shot":
				DirAccess.make_dir_recursive_absolute("user://autotest")
				get_viewport().get_texture().get_image().save_png("user://autotest/%s.png" % String(a[1]))
				var pf := maxi(prof_frames, 1)
				print("AUTOTEST %s t=%.1f fps=%d alive=%d kills=%d horde=%.2fms arsenal=%.2fms" % [String(a[1]), real_t, Engine.get_frames_per_second(), horde.alive_count, kills, prof_horde / 1000.0 / pf, prof_arsenal / 1000.0 / pf])
				prof_horde = 0
				prof_arsenal = 0
				prof_frames = 0
			"quit":
				save_pilot()
				print("AUTOTEST done kills=%d alive=%d integrity=%.0f state=%d clearance=%d owned=%d" % [kills, horde.alive_count, integrity, state, clearance(), arsenal.owned().size()])
				get_tree().quit()
	return false

## Quick visual tour of one AO: title card, a wide look, the approaches, the refuge.
func _tour() -> void:
	var steps := [[1.0, "shot_title"], [1.5, "start"], [2.0, "wide"], [5.5, "shot_wide"], [6.0, "med"],
		[9.0, "shot_med"], [9.5, "refuge"], [12.5, "shot_refuge"], [13.0, "town"], [16.0, "shot_town"],
		[16.5, "block"], [19.5, "shot_block"], [20.0, "quit"]]
	if auto_step >= steps.size() or real_t < float(steps[auto_step][0]):
		return
	var act: String = steps[auto_step][1]
	auto_step += 1
	match act:
		"start":
			_start_game()
			var args := OS.get_cmdline_user_args()
			if "--tv" in args:
				tv_mode = true
				_apply_sensor()
			# hold the clock where the shot wants it (the first wave would reset it to dawn)
			if "--night" in args:
				day_clock = 15.5
				intermission = 9999.0
			if "--noon" in args:
				day_clock = 6.0
				intermission = 9999.0
			for a in args:
				if a.begins_with("--day="):
					# the eve of day N: its first wave is next, and the grid is already down to day N's
					var dn := maxi(int(a.substr(6)), 1)
					wave = (dn - 1) * DAY_LEN
					RenderingServer.global_shader_parameter_set("grid_power", float(GRID_BY_DAY[mini(dn - 1, GRID_BY_DAY.size() - 1)]))
		"wide":
			track = Vector3.ZERO
			fov_target = 30.0
		"med":
			track = attract
			fov_target = 9.0
		"refuge":
			track = Vector3.ZERO
			fov_target = 4.0
		"town":
			# a few blocks out: streets, rooftops, the barricades
			track = Vector3(attract.z, 0.0, -attract.x).normalized() * 330.0 + attract.normalized() * 120.0
			fov_target = 6.0
		"block":
			track = attract.normalized() * 600.0 + Vector3(-attract.z, 0.0, attract.x).normalized() * 60.0
			fov_target = 3.0
		"quit":
			print("TOUR %s alive=%d fps=%d" % [ao_id, horde.alive_count, Engine.get_frames_per_second()])
			get_tree().quit()
		_:
			DirAccess.make_dir_recursive_absolute("user://autotest")
			get_viewport().get_texture().get_image().save_png("user://autotest/%s_%s.png" % [ao_id, act.substr(5)])
