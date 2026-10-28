extends Control
## Sensor symbology, flight instruments and the armory, drawn every frame over the thermal image.

const FG := Color(0.93, 0.96, 0.93)
const DIM := Color(0.93, 0.96, 0.93, 0.6)
const WARN := Color(1.0, 0.38, 0.3)
const GOOD := Color(0.6, 1.0, 0.65)
const TITLE := 0
const PLAYING := 1
const PAUSED := 2
const OVER := 3
const ARMORY := 4
const LOADOUT := 5
const SLOT_KEYS := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="]
const PERK_STATE := 6
const Perks = preload("res://scripts/perks.gd")
const CONTROLS := [
	"MOUSE / ARROWS  slew sensor     LMB  fire (hold: charge / consent)     RMB / Z  zoom step     WHEEL  zoom",
	"T / MMB  point track + auto lead     TAB  tactical map     C  orbit over sensor point     H  orbit home     X  IR / TV",
	"1-9, 0, - = / Q E  loadout     R  reload / buy restock     Y  fuze     G  A-10     B  armory     , .  time     F  palette",
	"W / S  throttle     SHIFT / CTRL  climb / descend     A / D  orbit radius     V  declutter     F1  help",
]
const CAS_CONTROLS := [
	"MOUSE  look: the A-10 flies where you look     LMB  fire     RMB  lock Maverick     WHEEL  zoom",
	"W / S  throttle     A / D  roll     SPACE  speed brakes (and wheel brakes)     C (hold)  free look",
	"1-5 / Q E  stores: gun, Mk-82, GBU-12, Maverick, rockets     Y  fuze     TAB  map     X  IR / TV",
	"Land on the FARP strip (gear comes down by itself), stop, and you're rearmed and refuelled. Look up past 140 kt to take off.",
]
const HELP := [
	["SENSOR", ""],
	["Mouse / arrow keys", "Slew the sensor; it stays locked on the ground as you orbit"],
	["Wheel / RMB / Z", "Zoom: wide 30 deg to narrow 0.8 deg"],
	["T or middle mouse", "Point track: follow the infected under the crosshair; weapons lead it automatically"],
	["F", "Palette: white-hot, black-hot, ironbow false colour, DISCO"],
	["X", "Sensor: IR imager or the daylight colour TV camera"],
	["TAB", "Tactical map: left-click slews the sensor, right-click moves your orbit"],
	["WEAPONS", ""],
	["LMB", "Fire. Hold to spin up rotaries, charge the railgun, give nuclear consent"],
	["1-9, 0, - = / Q E", "Select loadout slot (- and = need the Weapon Stations upgrade)"],
	["R", "Reload a gun, or buy a full restock of anything else (spent ordnance also restocks itself over time)"],
	["Y", "Fuze: impact / airburst (crowds in the open) / delay (bosses and buildings), on cannons, missiles and bombs"],
	["G  /  B", "Call the A-10  /  armory, loadout, restocks and aircraft upgrades"],
	["After each wave", "Pick 1 of 3 perks (keys 1-3, R rerolls for requisition)"],
	["AIRCRAFT", ""],
	["W / S", "Throttle 107-243 kt"],
	["SHIFT / CTRL", "Climb / descend 1,500-11,800 ft"],
	["A / D", "Tighten / widen the orbit (45 deg bank limit)"],
	["C  /  H", "Move the orbit over the sensor point  /  back over the refuge"],
	[",  /  .", "Time compression x1 to x8 (drops to x1 when they reach the wall)"],
	["V", "HUD declutter: full / minimal / clean"],
	["Esc", "Pause and settings (dev farm switch, reset all progress)"],
	["F9", "Dev: zombie farm on/off (10,000 dummies that stand still to be shot)"],
]

var main
# where the title screen's AO list is scrolled to right now
var ao_scroll_now := 0.0
var font: SystemFont
var font_b: SystemFont
var font_ui: SystemFont
var font_ui_b: SystemFont
const ACCENT := Color(1.0, 0.72, 0.26)
var glitch := 0.0
var buttons: Array = []
var S := 1.0
var vsz := Vector2(1600, 900)
var tac_rect := Rect2()
var tac_k := 1.0


func _ready() -> void:
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "Lucida Console", "Courier New", "Monospace"])
	font_b = SystemFont.new()
	font_b.font_names = font.font_names
	font_b.font_weight = 700
	# the front end uses a clean condensed sans; the in-flight symbology stays monospace
	font_ui = SystemFont.new()
	font_ui.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial", "Liberation Sans", "Sans"])
	font_ui_b = SystemFont.new()
	font_ui_b.font_names = font_ui.font_names
	font_ui_b.font_weight = 700


static func commas(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


func txt(p: Vector2, s: String, col := FG, fsize := 15, align := 0, f: Font = null) -> void:
	var fo: Font = f if f else font
	var w := fo.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var x := p.x
	if align == 1:
		x -= w * 0.5
	elif align == 2:
		x -= w
	draw_string_outline(fo, Vector2(x, p.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 5, Color(0, 0, 0, col.a * 0.8))
	draw_string(fo, Vector2(x, p.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)


func ln(a: Vector2, b: Vector2, col := FG, w := 2.0) -> void:
	draw_line(a, b, Color(0, 0, 0, col.a * 0.8), w + 2.0)
	draw_line(a, b, col, w)


func bar(r: Rect2, frac: float, col: Color) -> void:
	draw_rect(r, Color(0, 0, 0, 0.6))
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(frac, 0.0, 1.0), r.size.y)), col)
	draw_rect(r, FG, false, 1.0)


## The HUD is laid out on a virtual canvas of ~900 px height and scaled to the window.
func ui_scale() -> float:
	return clampf(size.y / 900.0, 0.75, 1.8)


func hit_test(p: Vector2) -> String:
	var q := p / S
	for b in buttons:
		if (b[0] as Rect2).has_point(q):
			return b[1]
	return ""


func vmouse() -> Vector2:
	return get_local_mouse_position() / S


## World point to virtual HUD coordinates.
func proj(p: Vector3) -> Vector2:
	return main.cam.unproject_position(p) / S


func _process(dt: float) -> void:
	glitch = maxf(0.0, glitch - dt)


func _draw() -> void:
	if main == null:
		return
	S = ui_scale()
	vsz = size / S
	var sz := vsz
	var c := (sz * 0.5).floor()
	var st: int = main.state
	buttons.clear()
	# EMP / detector glitch: the symbology jumps and drops out for a few seconds
	var off := Vector2.ZERO
	if glitch > 0.0:
		if randf() < 0.25 * minf(glitch, 1.0):
			return
		off = Vector2(randf_range(-12, 12), randf_range(-6, 6)) * minf(glitch, 1.0)
	draw_set_transform(off, 0.0, Vector2(S, S))
	if st == ARMORY or st == LOADOUT:
		_menu(sz, st == LOADOUT)
		if not main.unlock_card.is_empty():
			_unlock_card(sz, c)
		_radio(sz)
		return
	var mode: int = main.hud_mode
	if st != TITLE and main.mode == "cas":
		# the A-10's HUD in place of the gunship's sensor symbology
		main.cas.draw_hud(self, sz, c)
		if mode < 2:
			_markers(sz, c)
			_ordnance(sz, c)
			_popups()
			_banner(sz)
			_killfeed(sz)
		main.missions.draw_story(self, sz)
	elif st != TITLE:
		_reticle(c)
		_reticle_notes(c)
		_track_symbology(c)
		if mode < 2:
			_right(sz)
			_markers(sz, c)
			_ordnance(sz, c)
			_popups()
			_banner(sz)
			_nuke_panel(sz, c)
			_pip_frame()
		if mode == 0:
			_frame(sz)
			_left(sz)
			_bottom(sz)
			_radar(Vector2(sz.x - 132.0, sz.y - 196.0))
			_killfeed(sz)
		elif mode == 1:
			_mini_status(sz)
		if st == PLAYING and main.tutorial_on and not main.autotest:
			_tutorial_panel(sz)
		if st == PLAYING:
			main.missions.draw_story(self, sz)
	if st != TITLE:
		_radio(sz)
	if main.tac_open and st == PLAYING:
		_tac_map(sz)
	if main.help_open:
		_help(sz)
	match st:
		TITLE:
			_title(sz, c)
			_radio(sz)
		PAUSED:
			_pause_menu(sz, c)
		OVER:
			_over(sz, c)
		PERK_STATE:
			_perk_screen(sz)


func _frame(sz: Vector2) -> void:
	var m := 36.0
	var L := 46.0
	for corner in [[Vector2(m, m), 1, 1], [Vector2(sz.x - m, m), -1, 1], [Vector2(sz.x - m, sz.y - m), -1, -1], [Vector2(m, sz.y - m), 1, -1]]:
		var p: Vector2 = corner[0]
		var dx: float = corner[1]
		var dy: float = corner[2]
		ln(p, p + Vector2(dx * L, 0))
		ln(p, p + Vector2(0, dy * L))


func _reticle(c: Vector2) -> void:
	var w: Dictionary = main.arsenal.current()
	match String(w["kind"]):
		"auto", "rotary":
			var big: bool = w["id"] == "gau8"
			var arm := 48.0 if big else 36.0
			for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
				ln(c + d * 9.0, c + d * arm)
			for k in ([20.0, 30.0, 40.0] if big else [18.0, 28.0]):
				for s in [-1.0, 1.0]:
					ln(c + Vector2(k * s, -4), c + Vector2(k * s, 4), FG, 1.5)
					ln(c + Vector2(-4, k * s), c + Vector2(4, k * s), FG, 1.5)
			var spin: float = w["spin"]
			if w["kind"] == "rotary" and spin > 0.01:
				draw_arc(c, 60.0, -PI * 0.5, -PI * 0.5 + TAU * spin, 48, Color(0, 0, 0, 0.8), 4.0)
				draw_arc(c, 60.0, -PI * 0.5, -PI * 0.5 + TAU * spin, 48, FG, 2.0)
		"cannon":
			if w["id"] == "bofors":
				var r := Rect2(c - Vector2(24, 24), Vector2(48, 48))
				draw_rect(r, Color(0, 0, 0, 0.8), false, 4.0)
				draw_rect(r, FG, false, 2.0)
				for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
					ln(c + d * 24.0, c + d * 70.0)
			else:
				_brackets(c, 120.0, 76.0, 24.0)
				ln(c + Vector2(-120, 0), c + Vector2(-14, 0))
				ln(c + Vector2(14, 0), c + Vector2(120, 0))
				ln(c + Vector2(0, -76), c + Vector2(0, -14))
				ln(c + Vector2(0, 14), c + Vector2(0, 76))
		"missile":
			var pts := [c + Vector2(0, -22), c + Vector2(22, 0), c + Vector2(0, 22), c + Vector2(-22, 0)]
			for i in 4:
				ln(pts[i], pts[(i + 1) % 4])
			for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
				ln(c + d * 30.0, c + d * 64.0)
			if main.arsenal.missiles.size() > 0:
				var pulse := 30.0 + fmod(main.real_t * 40.0, 24.0)
				draw_arc(c, pulse, 0, TAU, 40, Color(FG, 0.6), 1.5)
				if fmod(main.real_t, 0.5) < 0.3:
					txt(c + Vector2(0, 92), "LASER ON", FG, 15, 1, font_b)
		"laser", "sol":
			# directed energy: a fine ring at the beam spot and a charge gauge
			var rk := maxf(_ground_radius_px(float(w["r_kill"])), 6.0)
			draw_arc(c, rk, 0, TAU, 40, Color(0, 0, 0, 0.8), 3.5)
			draw_arc(c, rk, 0, TAU, 40, FG, 1.5)
			for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
				ln(c + d * (rk + 6.0), c + d * (rk + 40.0), FG, 1.5)
			var frac: float = float(w["ammo"]) / 100.0 if w["kind"] == "laser" else 1.0
			draw_arc(c, rk + 50.0, PI * 0.75, PI * 0.75 + PI * 1.5 * frac, 40, Color(0, 0, 0, 0.8), 5.0)
			draw_arc(c, rk + 50.0, PI * 0.75, PI * 0.75 + PI * 1.5 * frac, 40, WARN if w["hot"] else FG, 3.0)
			txt(c + Vector2(0, rk + 78.0), "BEAM" if main.arsenal.beam_on else ("RECHARGE" if w["hot"] else "BEAM READY"), FG, 13, 1, font_b)
		"rail":
			ln(c + Vector2(-90, 0), c + Vector2(-12, 0), FG, 1.5)
			ln(c + Vector2(12, 0), c + Vector2(90, 0), FG, 1.5)
			ln(c + Vector2(0, -12), c + Vector2(0, -50), FG, 1.5)
			draw_circle(c, 2.5, FG)
			var ch: float = clampf(main.arsenal.rail_charge / 1.2, 0.0, 1.0)
			if ch > 0.0:
				bar(Rect2(c + Vector2(-60, 26), Vector2(120, 8)), ch, WARN)
				txt(c + Vector2(0, 54), "CHARGING", WARN, 13, 1, font_b)
		"rockets", "drones", "cruise", "a10", "arty", "tos", "wingman", "apache", "b52", "cows", "cas", "himars":
			# designation box for call-ins and salvo weapons
			_brackets(c, 46.0, 46.0, 14.0)
			draw_circle(c, 3.0, FG)
			var spread := 0.0
			match String(w["kind"]):
				"rockets":
					spread = 0.012 * main.aim_range
				"arty":
					spread = 45.0
				"tos":
					spread = 80.0
				"drones":
					spread = 160.0
				"apache":
					spread = 120.0
				"cows":
					spread = 0.006 * main.aim_range
				"himars":
					spread = 55.0
			if w["kind"] == "b52":
				# the carpet runs along the approach, refuge to mark and on past it
				var cam: Camera3D = main.cam
				var ap: Vector3 = main.aim_point
				var dir := Vector3(ap.x, 0.0, ap.z).normalized()
				if dir.length() < 0.5:
					dir = Vector3.FORWARD
				var prev := Vector2.INF
				for k in 13:
					var wp := ap + dir * (-600.0 + 100.0 * k)
					var local := cam.global_transform.affine_inverse() * wp
					if local.z > -2.0:
						prev = Vector2.INF
						continue
					var p := proj(wp)
					if prev != Vector2.INF:
						ln(prev, p, Color(WARN, 0.8), 1.5)
					draw_circle(p, 2.5, WARN)
					prev = p
			if spread > 0.0:
				var rs := _ground_radius_px(spread)
				for i in 24:
					var a0 := TAU * i / 24.0
					draw_arc(c, rs, a0, a0 + TAU / 48.0, 4, Color(FG, 0.7), 1.5)
			txt(c + Vector2(0, 74), "%s  %s" % [String(w["short"]), "TTI %.1fS" % main.arsenal.time_of_flight()], FG, 13, 1, font_b)
		"bomb", "cluster", "nuke", "orbital", "neutron", "davy", "darts", "napalm", "mines", "thermite", "glocke", "singularity", "constellation", "boulder", "titan", "moon":
			# predicted footprint of the weapon, drawn in screen space around the aim point,
			# as the fuze will shape it
			var fm: Dictionary = main.arsenal.fuze_fx(main.arsenal.fuze_of(w))
			var rk := _ground_radius_px(float(w["r_kill"]) * float(fm["kill"]))
			var rf := _ground_radius_px(float(w["r_frag"]) * float(fm["frag"]))
			var col := WARN if w["kind"] in ["nuke", "neutron", "davy", "moon"] else FG
			draw_arc(c, rk, 0, TAU, 64, Color(0, 0, 0, 0.7), 3.0)
			draw_arc(c, rk, 0, TAU, 64, col, 1.5)
			if rf < 4000.0:
				for i in 32:
					var a0 := TAU * i / 32.0
					draw_arc(c, rf, a0, a0 + TAU / 64.0, 4, Color(col, 0.7), 1.5)
			for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
				ln(c + d * 6.0, c + d * 22.0)
			txt(c + Vector2(0, -minf(rk, 300.0) - 10.0), "%s  TTI %.1fS" % [String(w["short"]), main.arsenal.time_of_flight()], col, 13, 1)


## Under the reticle: the fuze the selected weapon is set to, and the masked-line-of-fire warning.
func _reticle_notes(c: Vector2) -> void:
	var ars = main.arsenal
	var w: Dictionary = ars.current()
	var fz: String = ars.fuze_of(w)
	var y := c.y + 112.0
	if fz != "":
		txt(Vector2(c.x, y), "FUZE %s   [%s]" % [fz, String(main.key_name("fuze"))], ACCENT if fz != "IMPACT" else DIM, 12, 1, font_b)
		y += 18.0
	if main.los_masked:
		var col := WARN if fmod(main.real_t, 0.6) < 0.4 else Color(WARN, 0.6)
		var clear: float = main.los_clear_in
		var tail := ("CLEAR IN %d S" % ceili(clear)) if clear >= 0.0 else "REPOSITION THE ORBIT"
		txt(Vector2(c.x, y), "%s  //  %s" % [String(main.los_reason), tail], col, 14, 1, font_b)
		# where the line of fire runs into something
		var bp: Vector3 = main.los_block
		if bp != Vector3.INF and not main.cam.is_position_behind(bp):
			var s := proj(bp)
			ln(s + Vector2(-7, -7), s + Vector2(7, 7), WARN, 2.0)
			ln(s + Vector2(-7, 7), s + Vector2(7, -7), WARN, 2.0)


func _brackets(c: Vector2, bx: float, by: float, k: float) -> void:
	for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var p := c + Vector2(bx * s.x, by * s.y)
		ln(p, p - Vector2(k * s.x, 0))
		ln(p, p - Vector2(0, k * s.y))


## Approximate on-screen radius of a ground circle centred on the aim point.
func _ground_radius_px(r: float) -> float:
	var ang := atan(r / maxf(main.aim_range, 1.0))
	return ang / deg_to_rad(main.fov) * vsz.y


func _left(sz: Vector2) -> void:
	var x := 56.0
	var y := 76.0
	var fov: float = main.fov
	var mode := "WFOV" if fov > 15.0 else ("MFOV" if fov > 5.0 else ("NFOV" if fov > 1.6 else "UFOV"))
	txt(Vector2(x, y), "TV" if main.tv_mode else String(main.PALETTES[main.palette]), FG, 18, 0, font_b)
	if main.track_lock >= 0:
		txt(Vector2(x + 60, y), "PT TRK", GOOD if fmod(main.real_t, 0.6) < 0.4 else FG, 16, 0, font_b)
	else:
		txt(Vector2(x + 60, y), "AREA", DIM, 14)
	txt(Vector2(x, y + 24), "%s  %s  %.1f°   [%s] %s" % ["EO/TV" if main.tv_mode else "IR", mode, fov, main.key_name("sensor"), "IR" if main.tv_mode else "TV"])
	# local time and the weather; the TV camera is all but useless after dark
	var night: bool = float(main.light) < 0.3
	txt(Vector2(x + 200, y), "%s  //  %s" % [main.clock_text(), main.weather_name()], WARN if (night and main.tv_mode) else DIM, 14, 0, font_b)
	if night and main.tv_mode and fmod(main.real_t, 1.6) < 1.1:
		txt(Vector2(x + 200, y - 20), "LOW LIGHT: SWITCH TO IR", WARN, 12, 0, font_b)
	txt(Vector2(x, y + 44), "ZOOM %.1fX" % (30.0 / fov))
	if main.time_scale > 1.0:
		txt(Vector2(x + 150, y + 44), "TIME x%d" % int(main.time_scale), WARN, 16, 0, font_b)

	# flight block
	var yf := y + 76
	var alt_ft := int(main.alt * 3.281)
	var cmd_ft := int(main.cmd_alt * 3.281)
	var trend := ""
	if cmd_ft > alt_ft + 30:
		trend = "  ^ %s" % commas(cmd_ft)
	elif cmd_ft < alt_ft - 30:
		trend = "  v %s" % commas(cmd_ft)
	txt(Vector2(x, yf), "ALT  %s FT%s" % [commas(alt_ft), trend], WARN if main.alt < 600.0 else FG)
	var kt := int(main.speed * 1.944)
	var cmd_kt := int(main.cmd_speed * 1.944)
	txt(Vector2(x, yf + 20), "GS   %d KT%s" % [kt, ("  > %d" % cmd_kt) if absi(cmd_kt - kt) > 2 else ""])
	txt(Vector2(x, yf + 40), "ORBIT %s M" % commas(int(main.orbit_r)))
	txt(Vector2(x, yf + 60), "BANK %d°%s" % [int(main.bank), "  LIMIT" if main.bank_limited else ""], WARN if main.bank_limited else FG)
	txt(Vector2(x, yf + 80), "HDG  %03d" % int(main.heading_deg()))
	var oc: Vector3 = main.orbit_center
	var ocmd: Vector3 = main.orbit_center_cmd
	if oc.distance_to(ocmd) > 5.0:
		txt(Vector2(x, yf + 100), "REPOSITIONING  %.1f KM" % (oc.distance_to(ocmd) / 1000.0), WARN, 13, 0, font_b)
	elif Vector2(oc.x, oc.z).length() > 20.0:
		txt(Vector2(x, yf + 100), "ORBIT OFFSET %.1f KM  [H] HOME" % (Vector2(oc.x, oc.z).length() / 1000.0), DIM, 12)
	var secs := int(main.t) + 9733
	txt(Vector2(x, yf + 122), "%02d:%02d:%02dZ   SENS %.1f   F1 HELP" % [(secs / 3600) % 24, (secs / 60) % 60, secs % 60, main.mouse_sens], DIM, 12)


func _right(sz: Vector2) -> void:
	var x := sz.x - 440.0
	var y := 76.0
	var ars = main.arsenal
	var list: Array = ars.equipped()
	var cw: Dictionary = ars.current()
	var rh := 22.0
	draw_rect(Rect2(Vector2(x - 12, y - 18), Vector2(sz.x - 44.0 - x, list.size() * rh + 14)), Color(0, 0, 0, 0.32))
	for i in list.size():
		var w: Dictionary = list[i]
		var sel: bool = w["id"] == cw["id"]
		var status: String = ars.status_text(w)
		var col := FG if sel else DIM
		if status == "OVERHEAT" or status == "WINCHESTER" or status.begins_with("RESTOCK"):
			col = WARN
		var ly := y + i * rh
		if sel:
			draw_rect(Rect2(Vector2(x - 10, ly - 15), Vector2(sz.x - 48.0 - x, rh - 2)), Color(1, 1, 1, 0.1))
		var key: String = SLOT_KEYS[i] if i < SLOT_KEYS.size() else " "
		var line := "%s %-24s %6s" % [key, String(w["name"]), ars.ammo_text(w)]
		txt(Vector2(x, ly), line, col, 14, 0, font_b if sel else font)
		txt(Vector2(sz.x - 56.0, ly), status, col, 12, 2)
		# the fuze each fuzed weapon is set to
		var fz: String = ars.fuze_of(w)
		if fz != "":
			# just past the ammo count, or tucked in left of a long status like RESTOCK 160S
			var tag := String(ars.fuze_fx(fz)["tag"])
			var tw := font_b.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			var sw := font.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			txt(Vector2(minf(x + 292.0, sz.x - 62.0 - sw - tw), ly), tag, Color(ACCENT, 1.0 if sel else 0.65), 11, 0, font_b)
		# readiness strip: cooldown, reload or clip change filling back up
		var frac := 1.0
		if float(w["rt"]) > 0.0 and float(w["reload"]) > 0.0:
			frac = 1.0 - float(w["rt"]) / float(w["reload"])
		elif float(w["cd"]) > 0.0 and float(w["interval"]) > 0.0:
			frac = 1.0 - float(w["cd"]) / float(w["interval"])
		elif int(w["ammo"]) <= 0:
			frac = ars.restock_frac(w)
		if frac < 1.0:
			draw_rect(Rect2(Vector2(x, ly + 3), Vector2((sz.x - 70.0 - x) * frac, 2)), Color(col, 0.8))
	var yb := y + list.size() * rh + 4
	var rprice: int = ars.restock_price(cw)
	if rprice > 0:
		var afford: bool = main.rp >= rprice
		txt(Vector2(x, yb + 11), "R  BUY FULL RESTOCK  %s RP" % commas(rprice), GOOD if afford else DIM, 12, 0, font_b)
		yb += 20
	if cw["kind"] == "rotary":
		txt(Vector2(x, yb + 11), "BARREL", DIM, 12)
		bar(Rect2(Vector2(x + 64, yb + 1), Vector2(200, 9)), float(cw["temp"]) / float(cw["overheat"]), WARN if cw["hot"] else FG)
		yb += 20
	var a10w: Dictionary = ars.by_id("a10")
	if a10w["owned"] and not ars.is_equipped("a10"):
		var a10s: String = ars.status_text(a10w)
		txt(Vector2(x, yb + 14), "G  HAWG 1-1  A-10C  GUNS   x%d" % int(a10w["ammo"]), FG if a10s == "READY" else DIM, 14)
		txt(Vector2(sz.x - 56.0, yb + 14), a10s, FG if a10s == "READY" else DIM, 12, 2)


func _bottom(sz: Vector2) -> void:
	var ars = main.arsenal
	var ap: Vector3 = main.aim_point
	var grid := "38S MB %05d %05d" % [int(44710 + ap.x), int(82130 - ap.z)]
	var line := "LRF %s M    TOF %.2f S    %s    BRG %03d" % [commas(int(main.aim_range)), ars.time_of_flight(), grid, int(fposmod(rad_to_deg(atan2(ap.x, -ap.z)), 360.0))]
	txt(Vector2(sz.x * 0.5, sz.y - 52.0), line, FG, 15, 1)

	var x := 56.0
	var y := sz.y - 176.0
	var h = main.horde
	var contacts: int = h.alive_count + main.to_spawn
	var day_len: int = main.DAY_LEN
	var in_day: int = ((maxi(main.wave, 1) - 1) % day_len) + 1
	txt(Vector2(x, y), "DAY %d   WAVE %d  (%d/%d)" % [main.day(), main.wave, in_day, day_len], FG, 18, 0, font_b)
	txt(Vector2(x, y + 24), "CONTACTS %s" % commas(contacts))
	txt(Vector2(x, y + 44), "KIA      %s" % commas(main.kills))
	var at_wall: int = h.arrived_count
	txt(Vector2(x, y + 64), "AT WALL  %s" % commas(at_wall), WARN if at_wall > 0 else FG)
	txt(Vector2(x, y + 88), "REQ %s RP" % commas(main.rp), GOOD, 15, 0, font_b)
	# what we're saving for: the pinned system, or the cheapest next rung
	var goal: Dictionary = main.next_goal()
	if not goal.is_empty():
		var gp: int = goal["price"]
		var gname := "%s  //  %s" % [String(ars.CATS[int(goal["cat"])]), String(goal["name"])]
		var gy := y + 156.0
		if main.rp >= gp and ars.unlocked(goal):
			if fmod(main.real_t, 1.0) < 0.7:
				txt(Vector2(x, gy), "READY  //  %s   [%s]" % [String(goal["name"]), String(main.key_name("armory"))], GOOD, 14, 0, font_b)
			bar(Rect2(Vector2(x, gy + 8), Vector2(240, 4)), 1.0, GOOD)
		else:
			var pin_mark := "PINNED " if main.pinned == String(goal["id"]) else "NEXT "
			txt(Vector2(x, gy), pin_mark + gname, DIM, 12, 0, font_b)
			txt(Vector2(x + 240, gy), commas(gp), DIM, 12, 2)
			bar(Rect2(Vector2(x, gy + 8), Vector2(240, 4)), float(main.rp) / maxf(float(gp), 1.0), ACCENT)
	if main.dev_farm:
		txt(Vector2(x, y - 48), "DEV FARM ON  //  %s DUMMIES  [F9]" % commas(int(h.farm_alive)), WARN, 13, 0, font_b)
	var integ: float = main.integrity
	var col := FG if integ > 35.0 else WARN
	txt(Vector2(x, y + 114), "%s %d%%   //   POP %s" % [String(main.refuge_name), int(ceil(integ)), commas(int(main.population))], col)
	bar(Rect2(Vector2(x, y + 122), Vector2(240, 10)), integ / 100.0, col)
	# the approach: how far out the leading edge is and how long until it reaches the wall
	var nr: float = h.nearest_r
	if nr < 100000.0 and at_wall == 0:
		var eta: float = h.nearest_eta
		txt(Vector2(x, y - 26), "LEAD CONTACT %.1f KM   ETA %d:%02d" % [nr / 1000.0, int(eta) / 60, int(eta) % 60], WARN if eta < 90.0 else FG, 14, 0, font_b)
	var mult: float = main.standoff_mult(main.aim_point)
	txt(Vector2(x + 250, y + 88), "STANDOFF x%.1f" % mult, GOOD if mult > 1.2 else DIM, 13)
	if at_wall > 20:
		var s: int = h.worst_sector()
		if s >= 0 and fmod(main.real_t, 0.8) < 0.5:
			txt(Vector2(sz.x * 0.5, 104.0), "BREACH  //  %s WALL" % String(main.SECTORS[s]), WARN, 22, 1, font_b)
	if not main.wave_active and main.wave > 0 and main.state == PLAYING and main.intermission > 0.0:
		txt(Vector2(sz.x * 0.5, 140.0), "NEXT WAVE IN %d" % int(ceil(main.intermission)), FG, 20, 1, font_b)


## Radar: a 3.2 km plan view centred on the refuge, rotated so the sensor's look direction
## is up. Horde density glows in it; the ring of sector bars shows where the mass is coming from.
func _radar(o: Vector2) -> void:
	var cam: Camera3D = main.cam
	var h = main.horde
	var f := -cam.global_transform.basis.z
	var fv := Vector2(f.x, f.z).normalized()
	var rv := Vector2(-fv.y, fv.x)
	var R := 104.0
	var range_m := 3200.0
	var k := R / range_m
	var to_screen := func(p: Vector3) -> Vector2:
		var v := Vector2(p.x, p.z)
		return o + Vector2(v.dot(rv), -v.dot(fv)) * k
	draw_circle(o, R + 4.0, Color(0, 0, 0, 0.5))
	for km in [1.0, 2.0, 3.0]:
		draw_arc(o, km * 1000.0 * k, 0, TAU, 48, Color(FG, 0.22), 1.0)
	draw_arc(o, R, 0, TAU, 64, DIM, 1.0)
	# horde density
	var dens: PackedInt32Array = h.density
	var dn: int = h.DN
	var dbin: float = h.DBIN
	var half: float = h.GRID_HALF
	var sector := PackedFloat32Array()
	sector.resize(8)
	for bz in dn:
		for bx in dn:
			var n := dens[bz * dn + bx]
			if n <= 0:
				continue
			var wp := Vector3((bx + 0.5) * dbin - half, 0.0, (bz + 0.5) * dbin - half)
			var r := Vector2(wp.x, wp.z).length()
			if r > range_m:
				continue
			var sp: Vector2 = to_screen.call(wp)
			var a := clampf(0.25 + n / 60.0, 0.25, 1.0)
			draw_rect(Rect2(sp - Vector2(1.6, 1.6), Vector2(3.2, 3.2)), Color(WARN.r, WARN.g, WARN.b, a))
			sector[h.sector_of(wp.x, wp.z)] += n * (1.6 - r / range_m)
	# sector threat bars around the rim
	var smax := 1.0
	for s in sector:
		smax = maxf(smax, s)
	for i in 8:
		if sector[i] <= 0.0:
			continue
		var bearing := deg_to_rad(i * 45.0)
		var wdir := Vector2(sin(bearing), -cos(bearing))
		var sdir := Vector2(wdir.dot(rv), -wdir.dot(fv))
		var a0 := sdir.angle() - 0.33
		draw_arc(o, R + 9.0, a0, a0 + 0.66, 8, Color(WARN, clampf(sector[i] / smax, 0.15, 1.0)), 5.0)
	draw_rect(Rect2(o - Vector2(3, 3), Vector2(6, 6)), FG)
	# bosses blink on the scope
	if fmod(main.real_t, 0.8) < 0.55:
		for b in h.bosses:
			var bpos: Vector3 = b["pos"]
			if Vector2(bpos.x, bpos.z).length() <= range_m:
				var bp: Vector2 = to_screen.call(bpos)
				draw_colored_polygon(PackedVector2Array([bp + Vector2(0, -5), bp + Vector2(5, 0), bp + Vector2(0, 5), bp + Vector2(-5, 0)]), WARN)
	# our orbit, the aircraft, the sensor line; round the orbit, where the line of fire is clear
	# (green) and where something is in the way (red)
	var oc: Vector2 = to_screen.call(main.orbit_center)
	var vis: PackedByteArray = main.orbit_vis
	if vis.size() == 16:
		for kk in 16:
			var th: float = main.theta - TAU * float(kk) / 16.0
			var seg := PackedVector2Array()
			for j in 5:
				var a: float = th + TAU / 32.0 - TAU / 16.0 * float(j) / 4.0
				seg.append(to_screen.call(main.orbit_center + Vector3(cos(a), 0.0, sin(a)) * float(main.orbit_r)))
			draw_polyline(seg, Color(GOOD, 0.75) if vis[kk] == 1 else Color(WARN, 0.9), 2.0)
	else:
		draw_arc(oc, float(main.orbit_r) * k, 0, TAU, 48, Color(FG, 0.35), 1.0)
	var ac: Vector2 = to_screen.call(main.air_pos)
	var tp: Vector2 = to_screen.call(main.track)
	ln(ac, tp, Color(FG, 0.6), 1.0)
	draw_circle(tp, 2.5, FG)
	draw_circle(ac, 4.0, GOOD)
	var n_pos: Vector2 = to_screen.call(Vector3(0, 0, -range_m * 1.1)) - o
	txt(o + n_pos.normalized() * (R + 22.0) + Vector2(0, 5), "N", FG, 13, 1, font_b)
	txt(o + Vector2(0, R + 34), "RANGE 3.2 KM   [TAB] MAP", DIM, 11, 1)


## Point track: a box on the target and, when the computer is leading it, a lead diamond.
func _track_symbology(c: Vector2) -> void:
	if main.track_lock < 0:
		return
	var cam: Camera3D = main.cam
	var lp: Vector3 = main.lock_pos + Vector3.UP
	if not cam.is_position_behind(lp):
		var s := proj(lp)
		var b := 14.0
		draw_rect(Rect2(s - Vector2(b, b), Vector2(b * 2, b * 2)), Color(0, 0, 0, 0.8), false, 3.5)
		draw_rect(Rect2(s - Vector2(b, b), Vector2(b * 2, b * 2)), GOOD, false, 1.5)
		txt(s + Vector2(0, -b - 6), "TRK", GOOD, 12, 1, font_b)
	var tof: float = main.arsenal.time_of_flight()
	var fp: Vector3 = main.fire_point(tof)
	if tof > 0.05 and not cam.is_position_behind(fp):
		var q := proj(fp)
		if (q - c).length() > 3.0:
			for i in 8:
				var t0 := float(i) / 8.0
				ln(c.lerp(q, t0), c.lerp(q, t0 + 0.06), Color(GOOD, 0.8), 1.0)
		var dpts := PackedVector2Array([q + Vector2(0, -7), q + Vector2(7, 0), q + Vector2(0, 7), q + Vector2(-7, 0), q + Vector2(0, -7)])
		draw_polyline(dpts, Color(0, 0, 0, 0.8), 3.5)
		draw_polyline(dpts, GOOD, 1.5)
		txt(q + Vector2(10, 4), "LEAD %.1fS" % tof, GOOD, 11)


func _killfeed(sz: Vector2) -> void:
	var y := sz.y * 0.5 + 20.0
	for e in main.feed:
		var age: float = main.real_t - float(e["t"])
		if age > 9.0:
			continue
		var a := clampf((9.0 - age) / 2.0, 0.0, 1.0)
		txt(Vector2(sz.x - 56.0, y), String(e["text"]), Color(FG, a), 13, 2, font_b)
		y += 18.0


func _mini_status(sz: Vector2) -> void:
	var w: Dictionary = main.arsenal.current()
	var line := "%s  %s  //  %s %d%%  //  CONTACTS %s" % [String(w["short"]), main.arsenal.ammo_text(w), String(main.refuge_name), int(main.integrity), commas(main.horde.alive_count + main.to_spawn)]
	if main.time_scale > 1.0:
		line += "  //  TIME x%d" % int(main.time_scale)
	txt(Vector2(sz.x * 0.5, sz.y - 40.0), line, FG, 14, 1, font_b)


## Frame and caption for the picture-in-picture weapon view.
func _pip_frame() -> void:
	if not main.pip_rect.visible or main.pip_info.is_empty():
		return
	var r := Rect2(main.pip_rect.position / S, main.pip_rect.size / S)
	draw_rect(r, Color(0, 0, 0, 0.9), false, 4.0)
	draw_rect(r, FG, false, 1.5)
	var c := r.get_center()
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		ln(c + d * 6.0, c + d * 18.0, FG, 1.0)
	txt(r.position + Vector2(8, 18), String(main.pip_info["label"]), FG, 12, 0, font_b)
	txt(r.position + Vector2(r.size.x - 8, 18), "RNG %s M" % commas(int(main.pip_info["range"])), FG, 12, 2)
	if fmod(main.real_t, 0.8) < 0.5:
		txt(r.position + Vector2(8, r.size.y - 8), "REC", WARN, 11, 0, font_b)


# ---------------------------------------------------------------- tactical map
## Full-screen plan view of the AO: corridors, horde density, our orbit, the sensor
## footprint and everything in flight. Left-click slews the sensor, right-click moves the orbit.
func _tac_map(sz: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, 0.78))
	var h = main.horde
	var ars = main.arsenal
	var span := 7000.0
	var side := minf(sz.x - 120.0, sz.y - 120.0)
	tac_k = side / span
	var c := sz * 0.5
	tac_rect = Rect2(c - Vector2(side, side) * 0.5, Vector2(side, side))
	var w2s := func(p: Vector3) -> Vector2:
		return c + Vector2(p.x, p.z) * tac_k
	draw_rect(tac_rect, Color(0.05, 0.06, 0.05, 0.9))
	draw_rect(tac_rect, DIM, false, 1.0)
	for km in [1, 2, 3]:
		draw_arc(c, km * 1000.0 * tac_k, 0, TAU, 96, Color(FG, 0.18), 1.0)
		txt(c + Vector2(km * 1000.0 * tac_k + 4, -4), "%d KM" % km, Color(FG, 0.4), 11)
	for cor in main.corridors:
		var a: float = cor["ang"]
		var d := Vector2(cos(a), sin(a))
		if int(cor["type"]) == 0:
			ln(c + d * 60.0 * tac_k, c + d * 3400.0 * tac_k, Color(FG, 0.25), maxf(1.0, float(cor["hw"]) * 2.0 * tac_k))
		else:
			var hf: float = cor["half"]
			for s in [-1.0, 1.0]:
				var e := Vector2(cos(a + hf * s), sin(a + hf * s))
				ln(c + e * 150.0 * tac_k, c + e * 3400.0 * tac_k, Color(FG, 0.15), 1.0)
	# density
	var dens: PackedInt32Array = h.density
	var dn: int = h.DN
	var dbin: float = h.DBIN
	var half: float = h.GRID_HALF
	var cell := maxf(dbin * tac_k, 2.0)
	for bz in dn:
		for bx in dn:
			var n := dens[bz * dn + bx]
			if n <= 0:
				continue
			var sp: Vector2 = w2s.call(Vector3((bx + 0.5) * dbin - half, 0.0, (bz + 0.5) * dbin - half))
			draw_rect(Rect2(sp - Vector2(cell, cell) * 0.5, Vector2(cell, cell)), Color(WARN.r, WARN.g, WARN.b, clampf(0.2 + n / 80.0, 0.2, 0.95)))
	# the refuge
	draw_arc(c, float(main.wall_r) * tac_k, 0, TAU, 32, GOOD, 2.0)
	txt(c + Vector2(0, -float(main.wall_r) * tac_k - 6), String(main.refuge_name), GOOD, 12, 1, font_b)
	# mines and fires
	for m in ars.mines:
		draw_circle(w2s.call(m["pos"]), 1.5, Color(FG, 0.7))
	for z in ars.zones:
		ln(w2s.call(z["a"]), w2s.call(z["b"]), Color(1.0, 0.6, 0.2, 0.9), maxf(2.0, float(z["r"]) * 2.0 * tac_k))
	# ordnance in flight
	for b in ars.bombs:
		var tp: Vector2 = w2s.call(b["target"])
		draw_arc(tp, maxf(4.0, float(b["w"]["r_kill"]) * tac_k), 0, TAU, 24, WARN, 1.5)
		txt(tp + Vector2(6, -6), "%s %.0fS" % [String(b["w"]["short"]), float(b["T"]) - float(b["t"])], WARN, 11)
	for r in ars.rods:
		var tp: Vector2 = w2s.call(r["target"])
		draw_arc(tp, maxf(4.0, 45.0 * tac_k), 0, TAU, 24, WARN, 1.5)
	for d in ars.drones:
		draw_circle(w2s.call(d["pos"]), 2.0, FG)
	# attack runs: the whole pattern, holding point to egress, with the IP marked
	if not ars.a10.is_empty():
		_tac_path(ars.a10["path"], w2s, ars.a10["ip"])
		draw_circle(w2s.call(ars.a10["pos"]), 3.0, GOOD)
		txt(w2s.call(ars.a10["pos"]) + Vector2(6, 4), "HAWG", GOOD, 11)
	for j in ars.jets:
		if j["lead"]:
			_tac_path(j["path"], w2s, j["ip"])
		if float(j["s"]) >= 0.0:
			draw_circle(w2s.call(j["pos"]), 3.0, GOOD)
			txt(w2s.call(j["pos"]) + Vector2(6, 4), "VIPER", GOOD, 11)
	for b in ars.bombs:
		if b.has("path"):
			_tac_path(b["path"], w2s, Vector3.INF)
	if not ars.wingman.is_empty():
		draw_circle(w2s.call(ars.wingman_pos()), 3.5, GOOD)
		txt(w2s.call(ars.wingman_pos()) + Vector2(6, 4), "2-2", GOOD, 11)
	# ground operations
	var ops = main.ops
	if not ops.rescue.is_empty():
		var rp2: Vector2 = w2s.call(ops.rescue["pos"])
		draw_arc(rp2, 7.0, 0, TAU, 16, GOOD, 2.0)
		txt(rp2 + Vector2(10, 4), "SURVIVORS %d" % int(ops.rescue["n"]), GOOD, 12, 0, font_b)
	if not ops.convoy.is_empty():
		for tr in ops.convoy["trucks"]:
			if tr["alive"]:
				draw_rect(Rect2(w2s.call((tr["node"] as Node3D).global_position) - Vector2(3, 3), Vector2(6, 6)), GOOD)
	main.missions.draw_tac(self, w2s)
	# the FARP, and us in the A-10
	var af: Dictionary = main.world.get("airfield", {})
	if not af.is_empty():
		var ac3: Vector3 = af["center"]
		var ad: Vector3 = af["dir"]
		var hl: float = float(af["length"]) * 0.5
		ln(w2s.call(ac3 - ad * hl), w2s.call(ac3 + ad * hl), Color(GOOD, 0.7), 3.0)
		txt(w2s.call(ac3) + Vector2(8, -8), "FARP", GOOD, 12, 0, font_b)
	if main.mode == "cas":
		var cp: Vector2 = w2s.call(main.cas.pos)
		draw_circle(cp, 4.5, ACCENT)
		txt(cp + Vector2(8, 4), "HAWG 1-1", ACCENT, 12, 0, font_b)
		if not main.cas.task.is_empty():
			var tp: Vector2 = w2s.call(main.cas.task["pos"])
			draw_arc(tp, 9.0, 0, TAU, 20, ACCENT, 2.0)
			txt(tp + Vector2(12, 4), "TASK", ACCENT, 12, 0, font_b)
	# the landmarks, standing or not
	for lm in main.world.get("landmarks", []):
		var lp: Vector2 = w2s.call(lm["pos"])
		draw_rect(Rect2(lp - Vector2(3, 3), Vector2(6, 6)), Color(FG, 0.5 if lm["alive"] else 0.2), false, 1.0)
	# shenanigans
	if not ars.titan.is_empty():
		var tpos: Vector2 = w2s.call(ars.titan["pos"])
		draw_circle(tpos, 5.0, GOOD)
		txt(tpos + Vector2(8, 4), "TITAN", GOOD, 11, 0, font_b)
	for bd in ars.boulders:
		draw_circle(w2s.call(bd["pos"]), 4.0, FG)
	if not ars.moon.is_empty():
		var moon_p: Vector2 = w2s.call(ars.moon["target"])
		draw_arc(moon_p, float(ars.moon["w"]["r_kill"]) * tac_k, 0, TAU, 64, WARN, 2.0)
		txt(moon_p + Vector2(8, -8), "MOON", WARN, 12, 0, font_b)
	# bosses
	for b in h.bosses:
		var bp: Vector2 = w2s.call(b["pos"])
		var q := 7.0
		var dia := PackedVector2Array([bp + Vector2(0, -q), bp + Vector2(q, 0), bp + Vector2(0, q), bp + Vector2(-q, 0), bp + Vector2(0, -q)])
		draw_colored_polygon(dia, Color(WARN, 0.85))
		draw_polyline(dia, FG, 1.0)
		txt(bp + Vector2(10, 4), "%s %d%%" % [String(b["def"]["name"]), int(ceil(float(h.boss_hp(b)) * 100.0))], WARN, 12, 0, font_b)
	# our orbit and the sensor footprint
	var oc: Vector2 = w2s.call(main.orbit_center)
	draw_arc(oc, float(main.orbit_r) * tac_k, 0, TAU, 64, Color(GOOD, 0.6), 1.5)
	if main.orbit_center.distance_to(main.orbit_center_cmd) > 5.0:
		var occ: Vector2 = w2s.call(main.orbit_center_cmd)
		draw_arc(occ, float(main.orbit_r) * tac_k, 0, TAU, 64, Color(GOOD, 0.3), 1.0)
		ln(oc, occ, Color(GOOD, 0.4), 1.0)
	var ac: Vector2 = w2s.call(main.air_pos)
	draw_circle(ac, 5.0, GOOD)
	txt(ac + Vector2(8, 4), "SPECTRE 2-1", GOOD, 11, 0, font_b)
	var foot := _footprint()
	if foot.size() == 4:
		var pts := PackedVector2Array()
		for p in foot:
			pts.append(w2s.call(p))
		pts.append(pts[0])
		draw_polyline(pts, Color(FG, 0.8), 1.5)
	var trk: Vector2 = w2s.call(main.track)
	ln(ac, trk, Color(FG, 0.5), 1.0)
	ln(trk - Vector2(8, 0), trk + Vector2(8, 0), FG, 1.5)
	ln(trk - Vector2(0, 8), trk + Vector2(0, 8), FG, 1.5)
	# hover readout
	var mp := vmouse()
	if tac_rect.has_point(mp):
		var wp := Vector3((mp.x - c.x) / tac_k, 0.0, (mp.y - c.y) / tac_k)
		var n_near: int = h.count_near(wp, 60.0)
		txt(mp + Vector2(14, -8), "%.2f KM  //  %d IN 60 M  //  x%.1f RP" % [Vector2(wp.x, wp.z).length() / 1000.0, n_near, main.standoff_mult(wp)], FG, 12, 0, font_b)
	txt(Vector2(c.x, tac_rect.position.y - 14), "TACTICAL MAP  //  %s  //  NORTH UP" % String(main.world["name"]), FG, 16, 1, font_b)
	txt(Vector2(c.x, tac_rect.end.y + 22), "LMB  slew sensor here      RMB  move orbit here      TAB / ESC  close", DIM, 13, 1)


func _tac_path(path: Dictionary, w2s: Callable, ip: Vector3) -> void:
	var pts: PackedVector3Array = path["pts"]
	var line := PackedVector2Array()
	for i in range(0, pts.size(), 3):
		line.append(w2s.call(pts[i]))
	line.append(w2s.call(pts[pts.size() - 1]))
	if line.size() >= 2:
		draw_polyline(line, Color(GOOD, 0.45), 1.0)
	if ip != Vector3.INF:
		var q: Vector2 = w2s.call(ip)
		draw_rect(Rect2(q - Vector2(3, 3), Vector2(6, 6)), Color(GOOD, 0.8), false, 1.5)
		txt(q + Vector2(6, -6), "IP", GOOD, 11, 0, font_b)


## Inverse of the tactical map projection, for clicks (real pixels in, ground point out).
func tac_to_world(p: Vector2) -> Vector3:
	var q := p / S
	if not tac_rect.has_point(q):
		return Vector3.INF
	var c := tac_rect.get_center()
	return Vector3((q.x - c.x) / tac_k, 0.0, (q.y - c.y) / tac_k)


## Where the corners of the sensor's view land on the ground.
func _footprint() -> Array:
	var cam: Camera3D = main.cam
	var vp := get_viewport().get_visible_rect().size
	var out: Array = []
	for corner in [Vector2(0, 0), Vector2(vp.x, 0), Vector2(vp.x, vp.y), Vector2(0, vp.y)]:
		var o := cam.project_ray_origin(corner)
		var d := cam.project_ray_normal(corner)
		if d.y > -0.01:
			return []
		out.append(o + d * (-o.y / d.y))
	return out


func _help(sz: Vector2) -> void:
	var w := 820.0
	var hgt := HELP.size() * 22.0 + 70.0
	var r := Rect2(Vector2((sz.x - w) * 0.5, (sz.y - hgt) * 0.5), Vector2(w, hgt))
	draw_rect(r, Color(0, 0, 0, 0.88))
	draw_rect(r, DIM, false, 1.0)
	txt(Vector2(r.get_center().x, r.position.y + 30), "CONTROLS  //  F1 TO CLOSE", FG, 18, 1, font_b)
	var y := r.position.y + 58.0
	for row in HELP:
		if String(row[1]) == "":
			txt(Vector2(r.position.x + 24, y), String(row[0]), GOOD, 13, 0, font_b)
		else:
			txt(Vector2(r.position.x + 40, y), String(row[0]), FG, 13, 0, font_b)
			txt(Vector2(r.position.x + 260, y), String(row[1]), DIM, 13)
		y += 22.0


## Rows of < value > settings, centred on cx from y down. Returns the y below them.
func _settings_rows(cx: float, y: float, mouse: Vector2, rows: Array) -> float:
	for row in rows:
		txt(Vector2(cx - 220, y + 20), String(row[0]), FG, 16, 0, font_b)
		var minus := Rect2(Vector2(cx + 60, y), Vector2(34, 30))
		var plus := Rect2(Vector2(cx + 190, y), Vector2(34, 30))
		for pair in [[minus, "<", row[2]], [plus, ">", row[3]]]:
			var br: Rect2 = pair[0]
			draw_rect(br, Color(1, 1, 1, 0.2 if br.has_point(mouse) else 0.08))
			draw_rect(br, DIM, false, 1.0)
			txt(br.get_center() + Vector2(0, 6), String(pair[1]), FG, 16, 1, font_b)
			buttons.append([br, String(pair[2])])
		txt(Vector2(cx + 142, y + 21), String(row[1]), GOOD, 16, 1, font_b)
		y += 42.0
	return y


func _pause_menu(sz: Vector2, c: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, 0.62))
	var mouse := vmouse()
	ui_txt(Vector2(c.x, c.y - 150), "SENSOR PAUSED", FG, 44, 1, true)
	ui_txt(Vector2(c.x, c.y - 116), "%s  //  DAY %d  WAVE %d  //  %s  %s" % [String(main.world["name"]), main.day(), main.wave, main.clock_text(), main.weather_name()], Color(FG, 0.6), 14, 1)
	var y := c.y - 80.0
	var open: bool = main.menu_panel == ""
	for item in [["RESUME", "resume"], ["SETTINGS", "menu:settings"], ["QUIT TO TITLE", "title"]]:
		var br := Rect2(Vector2(c.x - 170, y), Vector2(340, 46))
		var hot := open and br.has_point(mouse)
		draw_rect(br, Color(1, 1, 1, 0.16 if hot else 0.06))
		if hot:
			draw_rect(Rect2(br.position, Vector2(4, br.size.y)), ACCENT)
		ui_txt(Vector2(br.get_center().x, br.position.y + 31), String(item[0]), FG, 20, 1, true)
		if open:
			buttons.append([br, String(item[1])])
		y += 56.0
	y += 20.0
	for l in (CAS_CONTROLS if main.mode == "cas" else CONTROLS):
		txt(Vector2(c.x, y), String(l), DIM, 12, 1)
		y += 20.0
	if main.menu_panel == "settings":
		_settings_panel(sz, c)


## The settings: GENERAL, GRAPHICS and CONTROLS tabs, over the title screen or the pause menu.
func _settings_panel(sz: Vector2, c: Vector2) -> void:
	var mouse := vmouse()
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, 0.55))
	var panel := Rect2(c - Vector2(390, 300), Vector2(780, 600))
	draw_rect(panel, Color(0.04, 0.05, 0.06, 0.97))
	draw_rect(panel, Color(ACCENT, 0.6), false, 1.5)
	ui_txt(Vector2(panel.position.x + 28, panel.position.y + 44), "SETTINGS", FG, 28, 0, true)
	ui_txt(Vector2(panel.end.x - 28, panel.position.y + 44), "ESC TO CLOSE", Color(FG, 0.45), 12, 2)
	# tabs
	var tab_names := ["GENERAL", "AUDIO", "GRAPHICS", "CONTROLS"]
	var tw := (panel.size.x - 56.0) / tab_names.size()
	for i in tab_names.size():
		var tr := Rect2(Vector2(panel.position.x + 28 + i * tw, panel.position.y + 62), Vector2(tw - 6, 34))
		var sel: bool = main.settings_tab == i
		draw_rect(tr, Color(1, 1, 1, 0.14 if sel else (0.07 if tr.has_point(mouse) else 0.03)))
		if sel:
			draw_rect(Rect2(Vector2(tr.position.x, tr.end.y - 3), Vector2(tr.size.x, 3)), ACCENT)
		ui_txt(Vector2(tr.get_center().x, tr.position.y + 23), String(tab_names[i]), FG if sel else Color(FG, 0.6), 15, 1, true)
		buttons.append([tr, "stab:%d" % i])
	var y := panel.position.y + 120.0
	match int(main.settings_tab):
		0:
			y = _settings_rows(c.x, y, mouse, [
				["MOUSE SENSITIVITY", "%.1f" % main.mouse_sens, "set:sens-", "set:sens+"],
				["INVERT Y", "ON" if main.invert_y else "OFF", "set:inv", "set:inv"],
				["SENSOR", "COLOUR TV" if main.tv_mode else "IR", "set:tv", "set:tv"],
				["IR PALETTE", String(main.PALETTES[main.palette]), "set:pal", "set:pal"],
				["TUTORIAL", "ON" if main.tutorial_on else "OFF", "set:tut", "set:tut"],
				["DEV: ZOMBIE FARM  [F9]", "ON" if main.dev_farm else "OFF", "dev:farm", "dev:farm"],
			])
			_reset_button(Rect2(Vector2(c.x - 150, y + 16), Vector2(300, 36)), mouse)
		1:
			var vb: Dictionary = main.vol_bus
			y = _settings_rows(c.x, y, mouse, [
				["MASTER", "%d%%" % int(round(main.volume * 100.0)), "set:vol-", "set:vol+"],
				["WEAPONS", "%d%%" % int(round(float(vb["Weapons"]) * 100.0)), "set:bus:Weapons:-", "set:bus:Weapons:+"],
				["EXPLOSIONS", "%d%%" % int(round(float(vb["Explosions"]) * 100.0)), "set:bus:Explosions:-", "set:bus:Explosions:+"],
				["AIRCRAFT AND ENGINES", "%d%%" % int(round(float(vb["Aircraft"]) * 100.0)), "set:bus:Aircraft:-", "set:bus:Aircraft:+"],
				["RADIO AND ALERTS", "%d%%" % int(round(float(vb["Radio"]) * 100.0)), "set:bus:Radio:-", "set:bus:Radio:+"],
			])
			_wrap(Vector2(panel.position.x + 60, y + 24), "Each click moves a channel 5%. Hold SHIFT for 1% steps; 0% mutes it. Weapons is your own guns and launches, explosions is everything landing on the ground.", panel.size.x - 120.0, 13, Color(FG, 0.55))
		2:
			var caps := {30000: "30,000", 50000: "50,000", 80000: "80,000"}
			y = _settings_rows(c.x, y, mouse, [
				["DISPLAY", "FULLSCREEN" if main.fullscreen else "WINDOWED", "gfx:full", "gfx:full"],
				["VSYNC", "ON" if main.vsync else "OFF", "gfx:vsync", "gfx:vsync"],
				["RENDER SCALE", "%d%%" % int(round(float(main.render_scale) * 100.0)), "gfx:scale-", "gfx:scale+"],
				["ANTI-ALIASING", "OFF" if int(main.msaa) == 0 else "MSAA %dX" % int(main.msaa), "gfx:msaa", "gfx:msaa"],
				["MAX INFECTED ALIVE", String(caps.get(int(main.horde_cap), str(main.horde_cap))), "gfx:cap-", "gfx:cap+"],
				["WEATHER ON THE LENS", "ON" if main.weather_fx else "OFF", "gfx:wx", "gfx:wx"],
			])
			_wrap(Vector2(panel.position.x + 60, y + 24), "Render scale below 100% uses AMD FSR upscaling. Lower the infected cap if the late waves stutter: the spawner holds the rest of the wave back until there's room.", panel.size.x - 120.0, 13, Color(FG, 0.55))
		3:
			_controls_list(Rect2(Vector2(panel.position.x + 28, y - 12), Vector2(panel.size.x - 56, 400)), mouse)
	var cr := Rect2(Vector2(c.x - 150, panel.end.y - 58), Vector2(300, 40))
	draw_rect(cr, Color(1, 1, 1, 0.2 if cr.has_point(mouse) else 0.08))
	draw_rect(cr, FG, false, 1.5)
	ui_txt(Vector2(cr.get_center().x, cr.position.y + 27), "CLOSE", FG, 17, 1, true)
	buttons.append([cr, "panel:close"])


## Key bindings: click an action, then press the key you want for it.
func _controls_list(r: Rect2, mouse: Vector2) -> void:
	var acts: Array = main.DEFAULT_KEYS.keys()
	var per := ceili(acts.size() / 2.0)
	var cw := (r.size.x - 16.0) * 0.5
	for i in acts.size():
		var a := String(acts[i])
		var row := Rect2(Vector2(r.position.x + (i / per) * (cw + 16.0), r.position.y + (i % per) * 28.0), Vector2(cw, 25))
		var waiting: bool = main.rebinding == a
		var hot := row.has_point(mouse)
		draw_rect(row, Color(ACCENT, 0.25) if waiting else Color(1, 1, 1, 0.12 if hot else 0.04))
		ui_txt(row.position + Vector2(10, 18), String(main.KEY_LABELS.get(a, a)), FG, 13)
		var kn: String = "PRESS A KEY..." if waiting else String(main.key_name(a))
		ui_txt(Vector2(row.end.x - 10, row.position.y + 18), kn, ACCENT if waiting else GOOD, 13, 2, true)
		buttons.append([row, "bind:" + a])
	var by := r.position.y + per * 28.0 + 8.0
	var rr := Rect2(Vector2(r.get_center().x - 130, by), Vector2(260, 32))
	draw_rect(rr, Color(1, 1, 1, 0.16 if rr.has_point(mouse) else 0.06))
	draw_rect(rr, DIM, false, 1.0)
	ui_txt(Vector2(rr.get_center().x, rr.position.y + 22), "RESET TO DEFAULTS", FG, 14, 1, true)
	buttons.append([rr, "bind:reset"])
	_wrap(Vector2(r.position.x, by + 54), "Fixed: number keys select weapons, SPACE zooms, ESC pauses, F1 help, F9 dev farm. Controller: left stick look, right stick fly, RT fire, LT zoom, A track, B zoom out, X reload, Y map, bumpers weapons, D-pad throttle and time, Back armory, Start pause. In menus the left stick moves the pointer and A clicks.", r.size.x, 12, Color(FG, 0.5))


## NEW SYSTEM ACQUIRED: the moment a purchase lands. The card sweeps in over the armory with the
## system's name, where it sits on its ladder, what it does, how it stacks up, and what's next.
func _unlock_card(sz: Vector2, c: Vector2) -> void:
	var ars = main.arsenal
	var w: Dictionary = ars.by_id(String(main.unlock_card["id"]))
	if w.is_empty():
		return
	var age: float = main.real_t - float(main.unlock_card["t"])
	var k := clampf(age / 0.35, 0.0, 1.0)
	var ez := 1.0 - pow(1.0 - k, 3.0)
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, 0.78 * ez))
	# a sweep of light behind the card
	var sweep := fmod(age * 0.6, 1.0)
	draw_rect(Rect2(Vector2(-200 + (sz.x + 400) * sweep, 0), Vector2(160, sz.y)), Color(ACCENT, 0.05 * ez))
	var cw := 860.0
	var ch := 470.0
	var r := Rect2(c - Vector2(cw, ch) * 0.5 + Vector2(0, 40.0 * (1.0 - ez)), Vector2(cw, ch))
	draw_rect(r, Color(0.03, 0.04, 0.05, 0.97 * ez))
	draw_rect(Rect2(r.position, Vector2(cw, 4)), ACCENT)
	draw_rect(r, Color(ACCENT, 0.6 * ez), false, 1.5)
	var cat := int(w["cat"])
	var rung := int(w.get("rung", 0))
	var size: int = ars.ladder_size(cat)
	var capstone := rung == size - 1
	var x := r.position.x + 36.0
	var y := r.position.y + 50.0
	ui_txt(Vector2(x, y), "LADDER COMPLETE" if capstone else "NEW SYSTEM ACQUIRED", Color(ACCENT, ez), 16, 0, true)
	ui_txt(Vector2(r.end.x - 36, y), "%s  //  %d OF %d" % [String(ars.CATS[cat]), rung + 1, size], Color(FG, 0.6 * ez), 13, 2, true)
	# the name, big
	var fs := 50 if String(w["name"]).length() < 22 else 38
	ui_txt(Vector2(x, y + 62), String(w["name"]), Color(FG, ez), fs, 0, true)
	_wrap(Vector2(x, y + 98), String(w["desc"]), cw - 72.0, 17, Color(FG, 0.8 * ez))
	# how it stacks up against the rung below
	var prev: Dictionary = ars.prev_of(w)
	var by := y + 160.0
	if not prev.is_empty() and cat <= 3:
		var f0: float = ars.firepower(prev)
		var f1: float = ars.firepower(w)
		if f0 > 0.0 and f1 > f0 * 1.05:
			ui_txt(Vector2(x, by), "+%d%% FIREPOWER OVER YOUR %s" % [int(round((f1 / f0 - 1.0) * 100.0)), String(prev["name"])], Color(GOOD, ez), 20, 0, true)
			by += 34.0
	# stat bars against the best of its own ladder
	var stats := [
		["DAMAGE", float(w.get("dmg", 0.0)), "dmg"],
		["BLAST RADIUS", float(w.get("r_frag", 0.0)), "r_frag"],
		["RATE OF FIRE", float(w.get("rate", 1.0 / maxf(float(w.get("interval", 1.0)), 0.1))), "rate"],
		["CAPACITY", float(w.get("max", 1)), "max"],
	]
	for s in stats:
		var top := 0.0001
		for o in ars.in_category(cat):
			var v: float = float(o.get(String(s[2]), 0.0))
			if String(s[2]) == "rate" and not o.has("rate"):
				v = 1.0 / maxf(float(o.get("interval", 1.0)), 0.1)
			top = maxf(top, v)
		var frac := clampf(sqrt(float(s[1]) / top), 0.04, 1.0) * clampf((age - 0.3) / 0.6, 0.0, 1.0)
		ui_txt(Vector2(x, by + 14), String(s[0]), Color(FG, 0.55 * ez), 12, 0, true)
		draw_rect(Rect2(Vector2(x + 140, by + 4), Vector2(360, 10)), Color(1, 1, 1, 0.08 * ez))
		draw_rect(Rect2(Vector2(x + 140, by + 4), Vector2(360 * frac, 10)), Color(ACCENT, ez))
		by += 24.0
	# where it is, and what's next
	var aboard: bool = main.unlock_card.get("aboard", false)
	var slot: int = ars.loadout.find(String(w["id"]))
	var status := "LOADED ABOARD  //  KEY %s" % String(SLOT_KEYS[slot]) if (aboard and slot >= 0 and slot < SLOT_KEYS.size()) else "IN THE HANGAR  //  SWAP IT IN ON THE LOADOUT TAB"
	ui_txt(Vector2(r.end.x - 36, r.position.y + 230), status, Color(GOOD if aboard else ACCENT, ez), 13, 2, true)
	var nx: Dictionary = ars.next_of(w)
	var ny := r.end.y - 52.0
	draw_line(Vector2(x, ny - 26), Vector2(r.end.x - 36, ny - 26), Color(FG, 0.15 * ez), 1.0)
	if nx.is_empty():
		ui_txt(Vector2(x, ny), "THE TOP OF THE %s LADDER. THERE IS NOTHING BIGGER." % String(ars.CATS[cat]), Color(WARN, ez), 15, 0, true)
	else:
		ui_txt(Vector2(x, ny), "NEXT UP:  %s" % String(nx["name"]), Color(FG, 0.85 * ez), 16, 0, true)
		ui_txt(Vector2(x, ny + 22), "%s RP" % commas(int(nx["price"])), Color(ACCENT, 0.8 * ez), 13, 0, true)
	if age > 0.6 and fmod(main.real_t, 1.2) < 0.85:
		ui_txt(Vector2(r.end.x - 36, ny + 22), "CLICK TO CONTINUE", Color(FG, 0.6), 13, 2, true)


## The first-sortie tutorial: one instruction at a time, ticking over as you do each thing.
func _tutorial_panel(sz: Vector2) -> void:
	var text: String = main.tut_text()
	if text == "":
		return
	var w := 760.0
	var r := Rect2(Vector2(sz.x * 0.5 - w * 0.5, sz.y - 262.0), Vector2(w, 74))
	draw_rect(r, Color(0.02, 0.03, 0.04, 0.82))
	draw_rect(Rect2(r.position, Vector2(4, r.size.y)), ACCENT)
	ui_txt(r.position + Vector2(18, 22), "TRAINING  %d / %d" % [int(main.tut_step) + 1, int(main.TUT_STEPS)], ACCENT, 12, 0, true)
	ui_txt(Vector2(r.end.x - 14, r.position.y + 22), "SETTINGS > TUTORIAL TO TURN OFF", Color(FG, 0.4), 10, 2)
	_wrap(r.position + Vector2(18, 44), text, w - 36.0, 15, FG)
	for i in int(main.TUT_STEPS):
		draw_rect(Rect2(r.position + Vector2(170 + i * 12, 14), Vector2(8, 8)), ACCENT if i <= int(main.tut_step) else Color(1, 1, 1, 0.15))


## Wipe the career. The first click arms it; a second click within four seconds does it.
func _reset_button(br: Rect2, mouse: Vector2) -> void:
	var armed: bool = main.real_t - main.reset_armed < 4.0
	var hot := br.has_point(mouse)
	draw_rect(br, Color(WARN, (0.35 if armed else 0.12) + (0.1 if hot else 0.0)))
	draw_rect(br, WARN, false, 2.0 if armed else 1.5)
	var label := "CLICK AGAIN TO WIPE EVERYTHING" if armed and fmod(main.real_t, 0.5) < 0.35 else ("CONFIRM: WIPE ALL PROGRESS?" if armed else "RESET ALL PROGRESS")
	txt(br.get_center() + Vector2(0, 6), label, WARN if not armed else FG, 15, 1, font_b)
	buttons.append([br, "dev:reset"])


func _markers(sz: Vector2, c: Vector2) -> void:
	var cam: Camera3D = main.cam
	var ars = main.arsenal
	_mark(cam, Vector3(0, float(main.world["refuge_h"]), 0), String(main.refuge_name), sz, c, true)
	if not ars.a10.is_empty():
		_mark(cam, ars.a10["pos"], "HAWG 1-1", sz, c, false)
		if not ars.a10["at_ip"]:
			_mark(cam, ars.a10["ip"], "IP", sz, c, false, Color(GOOD, 0.8))
	if not ars.wingman.is_empty():
		_mark(cam, ars.wingman_pos(), "SPECTRE 2-2", sz, c, true)
	for m in ars.missiles:
		if m["guided"]:
			_mark(cam, m["pos"], "MSL", sz, c, false)
	for d in ars.drones:
		_mark(cam, d["pos"], "LM" if int(d["phase"]) == 0 else "DIVE", sz, c, false)
	for j in ars.jets:
		_mark(cam, j["pos"], "VIPER", sz, c, false)
	for b in main.horde.bosses:
		_boss_mark(cam, b, sz, c)


## Everything in flight or on the clock: bombs, rods, fire missions, the satellite, the minefields.
func _ordnance(sz: Vector2, c: Vector2) -> void:
	var cam: Camera3D = main.cam
	var ars = main.arsenal
	var y := 296.0
	var ev: String = main.event_text()
	if ev != "":
		txt(Vector2(sz.x * 0.5, y), ev, GOOD, 17, 1, font_b)
		y += 24.0
	# ground operations: the survivors waiting on the dustoff, the convoy fighting its way in
	var ops = main.ops
	if not ops.rescue.is_empty():
		var rp_pos: Vector3 = ops.rescue["pos"]
		var danger := clampf(float(ops.rescue["danger"]) / 6.0, 0.0, 1.0)
		var phase := String(ops.rescue["phase"])
		var status := {"call": "DUSTOFF SPINNING UP", "out": "DUSTOFF INBOUND", "land": "DUSTOFF LANDING", "load": "LOADING", "back": "DUSTOFF RTB"}
		_mark(cam, rp_pos + Vector3.UP * 3.0, "SURVIVORS %d" % int(ops.rescue["n"]), sz, c, true, GOOD if danger < 0.5 else WARN)
		txt(Vector2(sz.x * 0.5, y), "RESCUE  //  %d SURVIVORS  //  %s  //  DANGER %d%%" % [int(ops.rescue["n"]), String(status.get(phase, phase)), int(danger * 100.0)], WARN if danger > 0.5 else GOOD, 15, 1, font_b)
		y += 22.0
		if ops.rescue["heli"] != null:
			_mark(cam, (ops.rescue["heli"] as Node3D).global_position, "DUSTOFF", sz, c, false)
	if not ops.convoy.is_empty():
		var alive := 0
		var lead := INF
		for tr in ops.convoy["trucks"]:
			if tr["alive"]:
				alive += 1
				var tp: Vector3 = (tr["node"] as Node3D).global_position
				lead = minf(lead, Vector2(tp.x, tp.z).length())
				if not tr["in"]:
					var hp := float(tr["hp"])
					_mark(cam, tp + Vector3.UP * 4.0, "%d%%" % int(maxf(hp, 0.0)), sz, c, false, GOOD if hp > 50.0 else WARN)
		txt(Vector2(sz.x * 0.5, y), "CONVOY  //  %d OF 5 TRUCKS  //  %.1f KM OUT" % [alive, lead / 1000.0 if lead < INF else 0.0], GOOD, 15, 1, font_b)
		y += 22.0
	# objectives, danger-close calls and the evacuation
	y = main.missions.draw_hud(self, sz, c, y)
	if not ars.moon.is_empty():
		var mt := float(ars.moon["delay"]) - float(ars.moon["t"])
		_mark(cam, ars.moon["target"], "MOON %.1fS" % mt, sz, c, true, WARN)
		txt(Vector2(sz.x * 0.5, y), "LUNAR STRIKE  //  IMPACT %.1f S  //  BRACE" % mt, WARN, 17, 1, font_b)
		y += 24.0
	if not ars.titan.is_empty():
		_mark(cam, (ars.titan["pos"] as Vector3) + Vector3.UP * 44.0, "TITAN ONE", sz, c, true, GOOD)
		txt(Vector2(sz.x * 0.5, y), "TITAN ONE  //  %s KILLS" % commas(int(ars.titan["kills"])), GOOD, 15, 1, font_b)
		y += 22.0
	for bd in ars.boulders:
		_mark(cam, bd["pos"], "ROCK %d" % int(bd["kills"]), sz, c, false)
	# a carpet of sub-munitions (B-52, F-16s) gets one line, not fifty
	var n_sub := 0
	var sub_first := INF
	var sub_b: Dictionary = {}
	for b in ars.bombs:
		var w: Dictionary = b["w"]
		var tti := float(b["T"]) - float(b["t"])
		if w["kind"] == "sub":
			n_sub += 1
			if tti < sub_first:
				sub_first = tti
				sub_b = b
			continue
		_mark(cam, ars.bomb_pos(b, float(b["t"]) / float(b["T"])), String(w["short"]), sz, c, false)
		_mark(cam, b["target"], "%s %.1fS" % [String(w["short"]), tti], sz, c, false)
		txt(Vector2(sz.x * 0.5, y), "%s  TIME TO IMPACT %.1f S" % [String(w.get("name", w["short"])), tti], WARN if w["kind"] in ["nuke", "neutron"] else FG, 15, 1, font_b)
		y += 22.0
	if n_sub > 0:
		var sw: Dictionary = sub_b["w"]
		_mark(cam, sub_b["target"], "%s %.1fS" % [String(sw["short"]), sub_first], sz, c, false)
		txt(Vector2(sz.x * 0.5, y), "%d x %s FALLING  //  FIRST IMPACT %.1f S" % [n_sub, String(sw["short"]), sub_first], FG, 15, 1, font_b)
		y += 22.0
	for r in ars.rods:
		var tti := float(r["w"]["delay"]) - float(r["t"])
		_mark(cam, r["target"], "ROD %.1fS" % tti, sz, c, false)
		txt(Vector2(sz.x * 0.5, y), "THOR ROD  IMPACT %.1f S" % tti, FG, 15, 1, font_b)
		y += 22.0
	for m in ars.missions:
		var shots: Array = m["shots"]
		if shots.is_empty():
			continue
		var first := float(shots[0]["t"]) - float(main.t)
		var label: String = m.get("label", "TOS-1A SALVO" if m["tos"] else "155 FIRE MISSION")
		var line := "%s  FIRST IMPACT %.1f S" % [label, first] if first > 0.0 else "%s  ROUNDS IMPACTING" % label
		txt(Vector2(sz.x * 0.5, y), line, FG, 15, 1, font_b)
		y += 22.0
	if not ars.sol.is_empty():
		txt(Vector2(sz.x * 0.5, y), "SOL BEAM  %.1f S  -  STEER WITH THE CROSSHAIR" % (float(ars.sol["dur"]) - float(ars.sol["t"])), WARN, 15, 1, font_b)
		_mark(cam, ars.sol["spot"], "SOL", sz, c, false)
		y += 22.0
	if not ars.wingman.is_empty():
		txt(Vector2(sz.x * 0.5, y), "SPECTRE 2-2 ON STATION  %d S" % int(float(ars.wingman["dur"]) - float(ars.wingman["t"])), FG, 15, 1, font_b)
		y += 22.0
	var extras: Array = []
	if not ars.mines.is_empty():
		extras.append("MINES ACTIVE %d" % ars.mines.size())
	if not ars.zones.is_empty():
		extras.append("FIRES BURNING %d" % ars.zones.size())
	if not extras.is_empty():
		txt(Vector2(sz.x * 0.5, y), "  //  ".join(extras), DIM, 13, 1)


## Nuclear release panel: shows the clearances for whichever nuclear system is selected.
func _nuke_panel(sz: Vector2, c: Vector2) -> void:
	var w: Dictionary = main.arsenal.current()
	if not (w["kind"] in ["nuke", "neutron", "davy", "moon"]):
		return
	var is_moon: bool = w["kind"] == "moon"
	var air_d: float = main.air_pos.distance_to(main.aim_point)
	var stad_d := Vector2(main.aim_point.x, main.aim_point.z).length()
	var lethal: float = float(w["air_lethal"]) * main.stat("nuke_safe")
	var safe_air: bool = air_d > lethal * 1.4
	var safe_stad: bool = stad_d > float(main.wall_r) + float(w["ff_range"])
	var y := c.y + 130.0
	var yields := {"davy": "0.02 KT", "nuke": "10 KT", "neutron": "1 KT ERW", "moon": "7.3E19 KG"}
	txt(Vector2(c.x, y), "%s  //  %s  //  %s" % [String(w["short"]), yields.get(String(w["id"]), ""), "ARMED" if int(w["ammo"]) > 0 else "EXPENDED"], WARN, 18, 1, font_b)
	if is_moon:
		txt(Vector2(c.x, y + 24), "IMPACT ENERGY: YES", FG, 14, 1)
	else:
		txt(Vector2(c.x, y + 24), "AIRCRAFT CLEARANCE %.1f KM  (MIN %.1f)" % [air_d / 1000.0, lethal / 1000.0], FG if safe_air else WARN, 14, 1)
	txt(Vector2(c.x, y + 44), "%s %.2f KM  %s" % [String(main.refuge_name), stad_d / 1000.0, "CLEAR" if safe_stad else "FRIENDLY CASUALTIES EXPECTED"], FG if safe_stad else WARN, 14, 1)
	var consent: float = main.arsenal.consent
	var need: float = w["consent_t"]
	if consent > 0.0:
		txt(Vector2(c.x, y + 72), "RELEASE CONSENT  -  HOLD", WARN, 16, 1, font_b)
		bar(Rect2(Vector2(c.x - 150, y + 80), Vector2(300, 12)), consent / need, WARN)
	elif int(w["ammo"]) > 0:
		txt(Vector2(c.x, y + 72), "HOLD FIRE %.1f S FOR RELEASE CONSENT" % need, DIM, 14, 1)

func _mark(cam: Camera3D, p: Vector3, label: String, sz: Vector2, c: Vector2, edge_arrow: bool, col := FG) -> void:
	var local := cam.global_transform.affine_inverse() * p
	var behind := local.z > -2.0
	var s := c + Vector2(local.x, -local.y).normalized() * 10000.0
	if not behind:
		s = proj(p)
	var inside := not behind and s.x > 60 and s.x < sz.x - 60 and s.y > 60 and s.y < sz.y - 60
	if inside:
		var b := 9.0
		for q: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var corner := s + q * b
			ln(corner, corner - Vector2(q.x * 5, 0), col, 1.5)
			ln(corner, corner - Vector2(0, q.y * 5), col, 1.5)
		txt(s + Vector2(0, -16), label, col, 12, 1)
	elif edge_arrow:
		var d := s - c
		if d.length() < 1.0:
			return
		d = d.normalized()
		var ex := (sz.x * 0.5 - 70.0) / maxf(absf(d.x), 0.001)
		var ey := (sz.y * 0.5 - 70.0) / maxf(absf(d.y), 0.001)
		var e := c + d * minf(ex, ey)
		# slide in toward the centre until the arrow and its label are clear of the HUD's corner blocks
		var blocks := _edge_blocks(sz)
		for k in 40:
			var lab := Rect2(e - d * 26.0 - Vector2(58.0, 8.0), Vector2(116.0, 18.0))
			var clear := true
			for r: Rect2 in blocks:
				if r.grow(10.0).has_point(e) or r.intersects(lab):
					clear = false
					break
			if clear:
				break
			e -= d * 12.0
		var tip := e + d * 14.0
		var side := Vector2(-d.y, d.x) * 8.0
		draw_colored_polygon(PackedVector2Array([tip, e + side, e - side]), col)
		var dist := cam.global_position.distance_to(p) / 1000.0
		txt(e - d * 26.0 + Vector2(0, 5), "%s %.1fKM" % [label, dist], col, 12, 1)


## The full gunship HUD's corner blocks (flight data, status, weapons, radar), which the edge
## arrows keep out of.
## Title-screen grouping: by how many ways in an AO has, with the challenges on their own.
static func ao_category(a: Dictionary) -> String:
	if a.get("challenge", false):
		return "CHALLENGE"
	var n := int(a.get("paths", 1))
	if n <= 1:
		return "ONE PATH"
	if n <= 4:
		return "2 - 4 PATHS"
	if n <= 7:
		return "5 - 7 PATHS"
	return "8+ PATHS"


func _edge_blocks(sz: Vector2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if main.mode == "cas" or int(main.hud_mode) != 0:
		return out
	var n: int = main.arsenal.equipped().size()
	out.append(Rect2(40.0, 50.0, 360.0, 235.0))
	out.append(Rect2(40.0, sz.y - 222.0, 370.0, 187.0))
	out.append(Rect2(sz.x - 452.0, 55.0, 412.0, n * 22.0 + 90.0))
	out.append(Rect2(sz.x - 250.0, sz.y - 320.0, 230.0, 300.0))
	return out


## A boss: a bracket around the whole body with its name and health, or an edge arrow when off-screen.
func _boss_mark(cam: Camera3D, b: Dictionary, sz: Vector2, c: Vector2) -> void:
	var def: Dictionary = b["def"]
	var sc: float = def["scale"]
	var base: Vector3 = b["pos"]
	var top := base + Vector3.UP * sc * 1.9
	var hp: float = main.horde.boss_hp(b)
	var label := "%s  %d%%" % [String(def["name"]), int(ceil(hp * 100.0))]
	var inv := cam.global_transform.affine_inverse()
	if (inv * top).z < -2.0 and (inv * base).z < -2.0:
		var st := proj(top)
		var sb := proj(base)
		if st.x > 40 and st.x < sz.x - 40 and sb.y > 40 and st.y < sz.y - 40:
			var hh := maxf(absf(sb.y - st.y), 18.0)
			var cx := (st.x + sb.x) * 0.5
			var hw := maxf(hh * 0.35, 12.0)
			var r := Rect2(Vector2(cx - hw, minf(st.y, sb.y) - 4.0), Vector2(hw * 2.0, hh + 8.0))
			var k := minf(10.0, hw * 0.6)
			for q: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
				var corner := r.position + r.size * q
				var sx := 1.0 if q.x == 0.0 else -1.0
				var sy := 1.0 if q.y == 0.0 else -1.0
				ln(corner, corner + Vector2(k * sx, 0), WARN, 2.0)
				ln(corner, corner + Vector2(0, k * sy), WARN, 2.0)
			txt(Vector2(cx, r.position.y - 16), label, WARN, 13, 1, font_b)
			bar(Rect2(Vector2(cx - 40, r.position.y - 11), Vector2(80, 5)), hp, WARN)
			return
	_mark(cam, base, label, sz, c, true, WARN)


func _popups() -> void:
	var cam: Camera3D = main.cam
	for p in main.popups:
		var age: float = main.real_t - float(p["t"])
		if age > 1.6:
			continue
		var pos: Vector3 = p["pos"]
		if cam.is_position_behind(pos):
			continue
		var s := proj(pos) + Vector2(0, -age * 34.0)
		var big: bool = p["big"]
		txt(s, String(p["text"]), Color(FG, 1.0 - age / 1.6), 26 if big else 16, 1, font_b)


func _banner(sz: Vector2) -> void:
	var age: float = main.real_t - main.banner_t
	if age < 5.0:
		var a := clampf(minf(age * 3.0, (5.0 - age) * 1.5), 0.0, 1.0)
		txt(Vector2(sz.x * 0.5, sz.y * 0.37), main.banner, Color(FG, a), 30, 1, font_b)


func _radio(sz: Vector2) -> void:
	var rc: Dictionary = main.radio_cur
	if rc.is_empty():
		return
	var text := String(rc["text"])
	var shown := text.substr(0, int(main.radio_t * 55.0))
	var w := minf(760.0, sz.x - 200.0)
	var p := Vector2(sz.x * 0.5 - w * 0.5, sz.y - 150.0)
	draw_rect(Rect2(p - Vector2(12, 26), Vector2(w + 24, 74)), Color(0, 0, 0, 0.45))
	txt(p, "[%s]" % String(rc["who"]), FG, 14, 0, font_b)
	draw_multiline_string_outline(font, p + Vector2(0, 22), shown, HORIZONTAL_ALIGNMENT_LEFT, w, 15, 2, 5, Color(0, 0, 0, 0.8))
	draw_multiline_string(font, p + Vector2(0, 22), shown, HORIZONTAL_ALIGNMENT_LEFT, w, 15, 2, FG)


# ---------------------------------------------------------------- armory & loadout
## One screen serves both the pre-sortie loadout and the in-mission armory:
## the first tabs are the catalogue categories (buy), then the loadout (equip) and the aircraft (upgrades).
func _menu(sz: Vector2, preflight: bool) -> void:
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, 0.84))
	var ars = main.arsenal
	var mouse := vmouse()
	var w := minf(1180.0, sz.x - 60.0)
	var x0 := (sz.x - w) * 0.5
	var y0 := 34.0
	var title := "PRE-SORTIE LOADOUT  //  %s" % String(main.world["name"]) if preflight else "ARMORY  //  REQUISITION"
	txt(Vector2(x0, y0 + 26), title, FG, 26, 0, font_b)
	txt(Vector2(x0 + w, y0 + 26), "%s RP" % commas(main.rp), GOOD, 26, 2, font_b)
	txt(Vector2(x0 + w, y0 + 48), "%s  //  LIFETIME %s RP" % [String(main.rank_name()), commas(main.rp_total)], DIM, 13, 2)
	var nslots: int = ars.slots()
	var sub := "Choose up to %d systems for this sortie. Everything you own carries across every AO." % nslots
	if not preflight:
		sub = "WAVE %d CLEARED. Spend, swap the loadout, then deploy." % main.wave if main.armory_after_wave else "Sortie paused. The horde waits for no one."
	txt(Vector2(x0, y0 + 50), sub, DIM, 13)

	# the aircraft's weapon stations
	var sy := y0 + 66.0
	var sw := (w - (nslots - 1) * 6.0) / nslots
	var eq: Array = ars.equipped()
	for i in nslots:
		var r := Rect2(Vector2(x0 + i * (sw + 6.0), sy), Vector2(sw, 40))
		draw_rect(r, Color(1, 1, 1, 0.06))
		draw_rect(r, DIM, false, 1.0)
		txt(r.position + Vector2(6, 14), SLOT_KEYS[i], DIM, 11)
		if i < eq.size():
			var e: Dictionary = eq[i]
			txt(r.get_center() + Vector2(0, 4), String(e["short"]), FG, 14, 1, font_b)
			txt(r.get_center() + Vector2(0, 17), String(ars.CATS[int(e["cat"])]).substr(0, 10), DIM, 9, 1)
			buttons.append([r, "eq:" + String(e["id"])])

	# tabs
	var ty := sy + 52.0
	var tabs: Array = ars.CATS.duplicate()
	tabs.append("LOADOUT")
	tabs.append("UPGRADES")
	var tw := (w - (tabs.size() - 1) * 4.0) / tabs.size()
	for i in tabs.size():
		var r := Rect2(Vector2(x0 + i * (tw + 4.0), ty), Vector2(tw, 28))
		var sel: bool = main.armory_tab == i
		draw_rect(r, Color(1, 1, 1, 0.18 if sel else (0.08 if r.has_point(mouse) else 0.03)))
		draw_rect(r, FG if sel else DIM, false, 1.5 if sel else 1.0)
		var tname := String(tabs[i]).replace(" & MISSILES", "").replace("FIRE ", "")
		txt(r.get_center() + Vector2(0, 2), "%d %s" % [(i + 1) % 10, tname], FG if sel else DIM, 11, 1, font_b if sel else font)
		# how far up each ladder you are
		if i < ars.CATS.size():
			var have: int = ars.owned_in(i)
			var n_of: int = ars.ladder_size(i)
			draw_rect(Rect2(r.position + Vector2(4, r.size.y - 5), Vector2((r.size.x - 8) * float(have) / float(n_of), 2)), GOOD if have == n_of else ACCENT)
		buttons.append([r, "tab:%d" % i])

	var ry := ty + 40.0
	var rh := 46.0
	var n_cats: int = ars.CATS.size()
	if main.armory_tab == n_cats:
		_loadout_rows(Rect2(Vector2(x0, ry), Vector2(w, sz.y - ry - 90.0)), mouse)
	elif main.armory_tab == n_cats + 1:
		_upgrade_rows(x0, ry, w, mouse)
	else:
		# the ladder's progress, and the next rung up it
		var cat: int = main.armory_tab
		var have: int = ars.owned_in(cat)
		var n_of: int = ars.ladder_size(cat)
		var nxt := ""
		for wv in ars.in_category(cat):
			if not wv["owned"]:
				nxt = String(wv["name"])
				break
		txt(Vector2(x0, ry + 4), "%s  //  %d OF %d" % [String(ars.CATS[cat]), have, n_of], ACCENT, 13, 0, font_b)
		txt(Vector2(x0 + w, ry + 4), ("NEXT UP: %s" % nxt) if nxt != "" else "LADDER COMPLETE", GOOD if nxt == "" else FG, 13, 2, font_b)
		ry += 16.0
		# long categories fold into two columns; hover a row for its full description
		var rows: Array = main.armory_rows(main.armory_tab)
		var cols := 1 if rows.size() * rh <= sz.y - ry - 100.0 else 2
		var per_col := ceili(rows.size() / float(cols))
		var colw := (w - (cols - 1) * 10.0) / cols
		var hover := ""
		for i in rows.size():
			var row: Dictionary = rows[i]
			var r := Rect2(Vector2(x0 + (i / per_col) * (colw + 10.0), ry + (i % per_col) * rh), Vector2(colw, rh - 5))
			_armory_row(row, r, mouse)
			if cols > 1 and r.has_point(mouse):
				hover = "%s  -  %s" % [String(row["name"]), String(row["desc"])]
		if cols > 1:
			txt(Vector2(x0 + w * 0.5, ry + per_col * rh + 14.0), hover if hover != "" else "Hover a system for its full description.", FG if hover != "" else DIM, 13, 1)

	var label := "LAUNCH SORTIE  [ENTER]" if preflight else "DEPLOY  [SPACE]"
	var dr := Rect2(Vector2(x0 + w * 0.5 - 150, sz.y - 70), Vector2(300, 44))
	draw_rect(dr, Color(1, 1, 1, 0.22 if dr.has_point(mouse) else 0.1))
	draw_rect(dr, FG, false, 2.0)
	txt(Vector2(dr.get_center().x, dr.position.y + 29), label, FG, 18, 1, font_b)
	buttons.append([dr, "launch" if preflight else "deploy"])
	# top up everything aboard in one go
	var all_price: int = ars.restock_all_price()
	if all_price > 0:
		var rr := Rect2(Vector2(dr.end.x + 24, dr.position.y), Vector2(300, 44))
		var afford: bool = main.rp >= all_price
		draw_rect(rr, Color(GOOD, 0.22 if (afford and rr.has_point(mouse)) else 0.08))
		draw_rect(rr, GOOD if afford else DIM, false, 1.5)
		txt(Vector2(rr.get_center().x, rr.position.y + 28), "RESTOCK ALL ABOARD  %s RP" % commas(all_price), GOOD if afford else DIM, 14, 1, font_b)
		buttons.append([rr, "restock_all"])


## Permanent upgrades: the aircraft on the left, the refuge and its passive defences on the right.
func _upgrade_rows(x0: float, y: float, w: float, mouse: Vector2) -> void:
	var cw := (w - 16.0) * 0.5
	_upgrade_list(Perks.UPGRADES, "AIRCRAFT  //  EVERY SORTIE", x0, y, cw, mouse)
	_upgrade_list(Perks.REFUGE, "REFUGE & PASSIVE DEFENCES  //  EVERY AO", x0 + cw + 16.0, y, cw, mouse)


func _upgrade_list(list: Array, title: String, x0: float, y: float, w: float, mouse: Vector2) -> void:
	txt(Vector2(x0, y + 4), title, ACCENT, 13, 0, font_b)
	y += 14.0
	var max_chars := int((w - 170.0) / 6.6)
	for u in list:
		var id := String(u["id"])
		var lvl: int = main.upgrade_level(id)
		var mx := int(u["max"])
		var cost := Perks.upgrade_cost(u, lvl)
		var r := Rect2(Vector2(x0, y), Vector2(w, 42.0))
		var can: bool = lvl < mx and main.rp >= cost
		var hot := r.has_point(mouse)
		draw_rect(r, Color(1, 1, 1, 0.12 if (can and hot) else 0.04))
		var col := DIM if lvl >= mx else FG
		txt(r.position + Vector2(10, 17), String(u["name"]), col, 14, 0, font_b)
		var desc := String(u["desc"])
		if desc.length() > max_chars:
			desc = desc.substr(0, maxi(max_chars - 3, 8)) + "..."
		txt(r.position + Vector2(10, 34), desc, Color(col, col.a * 0.8), 11)
		for i in mx:
			var pip := Rect2(r.position + Vector2(w - 160.0 - (mx - i) * 15.0, 8), Vector2(11, 11))
			draw_rect(pip, GOOD if i < lvl else Color(1, 1, 1, 0.08))
			draw_rect(pip, DIM, false, 1.0)
		var label := "MAXED" if lvl >= mx else "%s RP" % commas(cost)
		var bcol := DIM if lvl >= mx else (GOOD if can else Color(WARN, 0.8))
		if can:
			var br := Rect2(Vector2(r.end.x - 150, r.position.y + 5), Vector2(142, 32))
			draw_rect(br, Color(GOOD, 0.22 if hot else 0.1))
			draw_rect(br, GOOD, false, 1.5)
			buttons.append([r, "upg:" + id])
		txt(Vector2(r.end.x - 79, r.position.y + 26), label, bcol, 13, 1, font_b)
		y += 46.0


## Between waves: the wave's summary and rewards, then pick one of three roguelite perks.
func _perk_screen(sz: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, 0.8))
	var c := sz * 0.5
	var mouse := vmouse()
	var ws: Dictionary = main.wave_summary
	var day_end: bool = ws.get("day_end", false)
	var head := "DAY %d SURVIVED" % (int(ws.get("wave", main.wave)) / int(main.DAY_LEN)) if day_end else "WAVE %d CLEARED" % main.wave
	txt(Vector2(c.x, 62), head, ACCENT if day_end else FG, 36, 1, font_ui_b)
	# the debrief: what this wave cost them, and what it paid
	var panel := Rect2(Vector2(c.x - 420, 80), Vector2(840, 150))
	draw_rect(panel, Color(1, 1, 1, 0.04))
	draw_rect(panel, Color(FG, 0.25), false, 1.0)
	var lx := panel.position.x + 24
	var ly := panel.position.y + 30
	txt(Vector2(lx, ly), "INFECTED KILLED", DIM, 12, 0, font_b)
	txt(Vector2(lx, ly + 26), commas(int(ws.get("kills", 0))), FG, 24, 0, font_ui_b)
	txt(Vector2(lx, ly + 62), "REQUISITION EARNED", DIM, 12, 0, font_b)
	txt(Vector2(lx, ly + 88), "%s RP" % commas(int(ws.get("earned", 0))), GOOD, 24, 0, font_ui_b)
	var rx := panel.position.x + 300
	var yy := ly
	for l in ws.get("lines", []):
		txt(Vector2(rx, yy), String(l[0]), FG, 14)
		txt(Vector2(panel.end.x - 24, yy), "+%s RP" % commas(int(l[1])), GOOD, 14, 2, font_b)
		yy += 22.0
	if day_end:
		txt(Vector2(rx, yy), "Refuge repaired +%d%%  //  every rack restocked" % int(round(float(ws.get("repaired", 0.0)))), ACCENT, 14, 0, font_b)
	txt(Vector2(c.x, 262), "CHOOSE A FIELD MODIFICATION FOR THE REST OF THIS SORTIE" + ("  //  DAY'S END: BETTER ODDS" if day_end else ""), DIM, 15, 1)
	var offers: Array = main.perk_offers
	var cw := 300.0
	var ch := 270.0
	var gap := 28.0
	var x := c.x - (offers.size() * cw + (offers.size() - 1) * gap) * 0.5
	var rcol := [FG, Color(0.55, 0.78, 1.0), Color(1.0, 0.82, 0.3)]
	for i in offers.size():
		var p: Dictionary = Perks.perk(String(offers[i]))
		var r := Rect2(Vector2(x, c.y - ch * 0.5), Vector2(cw, ch))
		var rar := int(p["rarity"])
		var col: Color = rcol[rar]
		var hot := r.has_point(mouse)
		draw_rect(r, Color(0, 0, 0, 0.6))
		draw_rect(r, Color(col, 0.18 if hot else 0.06))
		draw_rect(r, col, false, 2.5 if hot else 1.5)
		txt(r.position + Vector2(cw * 0.5, 30), "[%d]" % (i + 1), Color(col, 0.7), 14, 1, font_b)
		txt(r.position + Vector2(cw * 0.5, 74), String(p["name"]), col, 20, 1, font_b)
		txt(r.position + Vector2(cw * 0.5, 98), String(Perks.RARITY[rar]), Color(col, 0.75), 12, 1, font_b)
		var dp := r.position + Vector2(20, 140)
		draw_multiline_string_outline(font, dp, String(p["desc"]), HORIZONTAL_ALIGNMENT_CENTER, cw - 40, 15, 5, 5, Color(0, 0, 0, 0.8))
		draw_multiline_string(font, dp, String(p["desc"]), HORIZONTAL_ALIGNMENT_CENTER, cw - 40, 15, 5, FG)
		var stacks: int = main.perks_taken.count(String(p["id"]))
		if stacks > 0:
			txt(r.position + Vector2(cw * 0.5, ch - 18), "ALREADY TAKEN x%d  -  STACKS" % stacks, DIM, 11, 1)
		buttons.append([r, "perk:%d" % i])
		x += cw + gap
	var rr := Rect2(Vector2(c.x - 140, c.y + ch * 0.5 + 30), Vector2(280, 40))
	var can: bool = main.rp >= main.reroll_cost
	draw_rect(rr, Color(1, 1, 1, 0.18 if (can and rr.has_point(mouse)) else 0.06))
	draw_rect(rr, FG if can else DIM, false, 1.5)
	txt(Vector2(rr.get_center().x, rr.position.y + 26), "REROLL  %s RP  [R]" % commas(main.reroll_cost), FG if can else DIM, 15, 1, font_b)
	buttons.append([rr, "reroll"])
	if not main.perks_taken.is_empty():
		var names: Array = []
		for pid in main.perks_taken:
			names.append(String(Perks.perk(String(pid))["name"]))
		draw_multiline_string(font, Vector2(c.x - 450, sz.y - 90), "THIS SORTIE:  " + ",  ".join(names), HORIZONTAL_ALIGNMENT_CENTER, 900, 13, 3, DIM)


func _armory_row(row: Dictionary, r: Rect2, mouse: Vector2) -> void:
	var status: String = row["status"]
	var restock := int(row.get("restock", 0))
	var can_restock: bool = status == "OWNED" and restock > 0 and main.rp >= restock
	var hot := r.has_point(mouse) and (status == "BUY" or can_restock)
	var is_next: bool = row.get("next", false)
	var capstone: bool = row.get("capstone", false)
	draw_rect(r, Color(1, 1, 1, 0.12 if hot else 0.04))
	# the next rung up the ladder glows; the top of the ladder is marked
	if is_next:
		var pulse := 0.45 + 0.35 * sin(main.real_t * 4.0)
		draw_rect(r, Color(ACCENT, pulse), false, 2.0)
	var col := FG
	if status == "LOCKED":
		col = Color(FG, 0.3)
	elif status == "OWNED":
		col = DIM
	# the rung number doubles as the pin button: click it to save for this one
	var pin_r := Rect2(r.position, Vector2(40, r.size.y))
	var pinned: bool = row.get("pinned", false)
	if status != "OWNED" and row.has("rung"):
		if pin_r.has_point(mouse) or pinned:
			draw_rect(pin_r, Color(ACCENT, 0.25 if pinned else 0.12))
		buttons.append([pin_r, "pin:" + String(row["id"])])
	var rung_txt := "%d" % (int(row.get("rung", 0)) + 1) if row.has("rung") else "+"
	txt(r.position + Vector2(20, 18), rung_txt, ACCENT if is_next else Color(col, col.a * 0.7), 14, 1, font_b)
	if pinned:
		txt(r.position + Vector2(20, 36), "GOAL", ACCENT, 9, 1, font_b)
	elif status == "OWNED" and row.has("rung"):
		txt(r.position + Vector2(20, 36), "OK", Color(GOOD, 0.7), 9, 1, font_b)
	txt(r.position + Vector2(48, 18), String(row["name"]), ACCENT if is_next else col, 15, 0, font_b)
	var tag_x := 48 + font_b.get_string_size(String(row["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 14
	if capstone:
		txt(r.position + Vector2(tag_x, 18), "CAPSTONE", WARN if status != "OWNED" else Color(WARN, 0.6), 11, 0, font_b)
		tag_x += 80
	if bool(row["equipped"]):
		txt(r.position + Vector2(tag_x, 18), "EQUIPPED", GOOD, 11, 0, font_b)
	elif is_next:
		txt(r.position + Vector2(tag_x, 18), "NEXT", ACCENT, 11, 0, font_b)
	var desc := String(row["desc"])
	if status == "LOCKED":
		desc = "LOCKED: own the %s first.  %s" % [String(row.get("prev_name", "rung below")), desc]
	var max_chars := int((r.size.x - 48.0 - 170.0) / 6.8)
	if desc.length() > max_chars:
		desc = desc.substr(0, maxi(max_chars - 3, 8)) + "..."
	txt(r.position + Vector2(48, 36), desc, Color(col, col.a * 0.8), 12)
	var bx := r.end.x - 160.0
	var label := ""
	var bcol := col
	match status:
		"OWNED":
			label = "OWNED"
			if restock > 0:
				label = "RESTOCK %s" % commas(restock)
				bcol = GOOD if can_restock else Color(WARN, 0.8)
		"LOCKED":
			label = "%s RP" % commas(int(row["price"]))
			bcol = Color(FG, 0.3)
		"FULL":
			label = "N/A" if main.state == LOADOUT else "AT 100%"
			bcol = DIM
		"FUNDS":
			label = "%s RP" % commas(int(row["price"]))
			bcol = Color(WARN, 0.8)
		"BUY":
			label = "%s RP" % commas(int(row["price"]))
			bcol = GOOD
	if status == "BUY":
		var br := Rect2(Vector2(bx, r.position.y + 6), Vector2(148, r.size.y - 12))
		draw_rect(br, Color(GOOD, 0.25 if hot else 0.12))
		draw_rect(br, GOOD, false, 1.5)
		buttons.append([r, "buy:" + String(row["id"])])
	elif can_restock:
		var br := Rect2(Vector2(bx, r.position.y + 6), Vector2(148, r.size.y - 12))
		draw_rect(br, Color(GOOD, 0.25 if hot else 0.12))
		draw_rect(br, GOOD, false, 1.5)
		buttons.append([r, "restock:" + String(row["id"])])
	txt(Vector2(bx + 74, r.position.y + 26), label, bcol, 13, 1, font_b)


## Every owned system as a toggle tile, grouped by category.
func _loadout_rows(area: Rect2, mouse: Vector2) -> void:
	var ars = main.arsenal
	var cols: int = ars.CATS.size()
	var cw := (area.size.x - (cols - 1) * 6.0) / cols
	# tiles shrink to fit the longest category
	var most := 1
	for cat in cols:
		most = maxi(most, ars.in_category(cat).size())
	var step := minf(50.0, (area.size.y - 22.0) / most)
	var th := step - 6.0
	var small := th < 40.0
	for cat in cols:
		var x := area.position.x + cat * (cw + 6.0)
		txt(Vector2(x + cw * 0.5, area.position.y + 12), String(ars.CATS[cat]), DIM, 11, 1, font_b)
		var y := area.position.y + 22.0
		for wv in ars.in_category(cat):
			var w: Dictionary = wv
			var r := Rect2(Vector2(x, y), Vector2(cw, th))
			var owned: bool = w["owned"]
			var on: bool = ars.is_equipped(String(w["id"]))
			var col := FG if on else (DIM if owned else Color(FG, 0.22))
			draw_rect(r, Color(GOOD, 0.22) if on else Color(1, 1, 1, 0.1 if (owned and r.has_point(mouse)) else 0.03))
			draw_rect(r, GOOD if on else (DIM if owned else Color(FG, 0.15)), false, 1.5 if on else 1.0)
			txt(r.get_center() + Vector2(0, -2 if small else -3), String(w["short"]), col, 13 if small else 15, 1, font_b)
			var sub := "EQUIPPED" if on else ("OWNED" if owned else ("#%d  %s RP" % [int(w["tier"]), commas(int(w["price"]))] if ars.unlocked(w) else "#%d  LOCKED" % int(w["tier"])))
			txt(r.get_center() + Vector2(0, 11 if small else 14), sub, col, 9 if small else 10, 1)
			if owned:
				buttons.append([r, "eq:" + String(w["id"])])
			y += step
	var cur: Dictionary = {}
	for b in buttons:
		if String(b[1]).begins_with("eq:") and (b[0] as Rect2).has_point(mouse):
			cur = ars.by_id(String(b[1]).substr(3))
	if not cur.is_empty():
		txt(Vector2(area.get_center().x, area.end.y + 4), "%s  -  %s" % [String(cur["name"]), String(cur["desc"])], FG, 13, 1)
	else:
		txt(Vector2(area.get_center().x, area.end.y + 4), "Click owned systems to load or unload them. Buy new ones on the category tabs.", DIM, 13, 1)

func _overlay(sz: Vector2, c: Vector2, title: String, lines: Array) -> void:
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, 0.55))
	txt(c + Vector2(0, -60), title, FG, 40, 1, font_b)
	var y := c.y
	for l in lines:
		txt(Vector2(c.x, y), String(l), FG, 17, 1)
		y += 28.0
	y += 30.0
	for l in CONTROLS:
		txt(Vector2(c.x, y), String(l), DIM, 13, 1)
		y += 22.0


## Front-end text: the clean sans with a soft drop shadow instead of the HUD's heavy outline.
func ui_txt(p: Vector2, s: String, col: Color, fsize: int, align := 0, bold := false) -> void:
	var fo: Font = font_ui_b if bold else font_ui
	var w := fo.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var x := p.x - (w * 0.5 if align == 1 else (w if align == 2 else 0.0))
	draw_string(fo, Vector2(x + 1.5, p.y + 2.0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0, 0, 0, col.a * 0.7))
	draw_string(fo, Vector2(x, p.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)


func _wrap(p: Vector2, s: String, width: float, fsize: int, col: Color) -> void:
	draw_multiline_string(font_ui, p + Vector2(1.5, 2.0), s, HORIZONTAL_ALIGNMENT_LEFT, width, fsize, 4, Color(0, 0, 0, col.a * 0.7))
	draw_multiline_string(font_ui, p, s, HORIZONTAL_ALIGNMENT_LEFT, width, fsize, 4, col)


## Five pips for an AO's threat rating.
func _threat_pips(p: Vector2, n: int, right_align: bool) -> void:
	var x0 := p.x - (5 * 12.0 if right_align else 0.0)
	for i in 5:
		var r := Rect2(Vector2(x0 + i * 12.0, p.y - 8.0), Vector2(9, 9))
		draw_rect(r, (WARN if n >= 4 else ACCENT) if i < n else Color(1, 1, 1, 0.1))


## A live plan view of the loaded AO for the briefing: approaches, the refuge, and the horde.
func _mini_map(r: Rect2) -> void:
	draw_rect(r, Color(0.02, 0.03, 0.03, 0.85))
	draw_rect(r, Color(FG, 0.25), false, 1.0)
	var c := r.get_center()
	var k := r.size.x / 7000.0
	for cor in main.corridors:
		var a: float = cor["ang"]
		var d := Vector2(cos(a), sin(a))
		if int(cor["type"]) == 0:
			draw_line(c + d * 60.0 * k, c + d * 3400.0 * k, Color(FG, 0.3), maxf(1.0, float(cor["hw"]) * 2.0 * k))
		else:
			var hf: float = cor["half"]
			for s: float in [-1.0, 1.0]:
				var e := Vector2(cos(a + hf * s), sin(a + hf * s))
				draw_line(c + e * 150.0 * k, c + e * 3400.0 * k, Color(FG, 0.2), 1.0)
	var h = main.horde
	var dens: PackedInt32Array = h.density
	var dn: int = h.DN
	var dbin: float = h.DBIN
	var half: float = h.GRID_HALF
	var cell := maxf(dbin * k, 1.5)
	for bz in dn:
		for bx in dn:
			var n := dens[bz * dn + bx]
			if n <= 0:
				continue
			var sp := c + Vector2((bx + 0.5) * dbin - half, (bz + 0.5) * dbin - half) * k
			if r.has_point(sp):
				draw_rect(Rect2(sp - Vector2(cell, cell) * 0.5, Vector2(cell, cell)), Color(WARN.r, WARN.g, WARN.b, clampf(0.3 + n / 60.0, 0.3, 0.95)))
	draw_arc(c, maxf(float(main.wall_r) * k, 3.0), 0, TAU, 24, GOOD, 2.0)
	for km in [1.0, 2.0, 3.0]:
		draw_arc(c, km * 1000.0 * k, 0, TAU, 48, Color(FG, 0.12), 1.0)
	ui_txt(r.position + Vector2(8, r.size.y - 8), "LIVE  //  N UP  //  3 KM RINGS", Color(FG, 0.5), 10, 0, false)


## The front end: logo and menu on the left, the area-of-operations briefing on the right,
## the pilot record along the bottom. The live AO plays out behind it all.
func _title(sz: Vector2, c: Vector2) -> void:
	var mouse := vmouse()
	var open: bool = main.menu_panel == ""
	# a scrim, dark on the left and fading out over the live AO to the right
	var fade_w := sz.x * 0.8
	for k in 32:
		draw_rect(Rect2(Vector2(fade_w * k / 32.0, 0), Vector2(fade_w / 32.0 + 1.0, sz.y)), Color(0.015, 0.02, 0.025, 0.88 * (1.0 - pow(float(k) / 32.0, 1.8))))
	draw_rect(Rect2(Vector2.ZERO, Vector2(sz.x, 52)), Color(0, 0, 0, 0.5))
	draw_rect(Rect2(Vector2(0, sz.y - 66), Vector2(sz.x, 66)), Color(0, 0, 0, 0.72))
	draw_line(Vector2(0, sz.y - 66), Vector2(sz.x, sz.y - 66), Color(ACCENT, 0.45), 1.0)
	ui_txt(Vector2(48, 33), "SPECTRE 2-1   //   AC-130 OVERWATCH", Color(FG, 0.65), 13)
	ui_txt(Vector2(sz.x - 48, 33), "%s   //   SENSOR %s" % [Time.get_time_string_from_system(), "COLOUR TV" if main.tv_mode else "IR"], Color(FG, 0.65), 13, 2)

	# the logo
	var lx := 80.0
	var ly := 178.0
	ui_txt(Vector2(lx - 4, ly), "GUNSHIP", FG, 88, 0, true)
	draw_rect(Rect2(Vector2(lx, ly + 18), Vector2(70, 4)), ACCENT)
	ui_txt(Vector2(lx + 86, ly + 27), "O V E R W A T C H", ACCENT, 22, 0, true)
	ui_txt(Vector2(lx, ly + 64), "Hold the last refuges against a horde that never stops coming.", Color(FG, 0.72), 16)

	# the menu
	var my := ly + 160.0
	for it in [["DEPLOY", "menu:deploy", "ENTER"], ["FLY CAS  //  A-10C", "menu:cas", "C"], ["SETTINGS", "menu:settings", "ESC"], ["QUIT TO DESKTOP", "menu:quit", ""]]:
		var first: bool = it[1] == "menu:deploy"
		var r := Rect2(Vector2(lx - 20, my - (40.0 if first else 32.0)), Vector2(400, 54 if first else 46))
		var hot := open and r.has_point(mouse)
		if hot:
			draw_rect(r, Color(1, 1, 1, 0.07))
			draw_rect(Rect2(r.position, Vector2(4, r.size.y)), ACCENT)
		ui_txt(Vector2(lx + (12.0 if hot else 0.0), my), String(it[0]), ACCENT if (first and not hot) else FG, 38 if first else 26, 0, true)
		if String(it[2]) != "":
			ui_txt(Vector2(r.end.x - 14, my - 6), String(it[2]), Color(FG, 0.4), 12, 2)
		if open:
			buttons.append([r, String(it[1])])
		my += 66.0 if first else 56.0

	# the areas of operations, and the briefing for the one that's loaded behind us
	var px := maxf(600.0, sz.x * 0.42)
	var pw := maxf(sz.x - px - 56.0, 320.0)
	var py := 108.0
	ui_txt(Vector2(px, py), "AREA OF OPERATIONS", ACCENT, 14, 0, true)
	ui_txt(Vector2(px + pw, py), "W / S  TO CHANGE", Color(FG, 0.4), 11, 2)
	draw_line(Vector2(px, py + 10), Vector2(px + pw, py + 10), Color(FG, 0.22), 1.0)
	var aos: Array = main.aos()
	var lw := minf(330.0, pw * 0.4)
	var top := py + 28.0
	var view_h := maxf(sz.y - 90.0 - top, 200.0)
	# lay the list out first, grouped by how many ways in there are, then scroll it so the
	# selected AO stays in view
	var rows: Array = []
	var yy := 0.0
	var last_cat := ""
	var sel_y := 0.0
	for a in aos:
		var cat := ao_category(a)
		if cat != last_cat:
			rows.append([yy, "", cat])
			yy += 26.0
			last_cat = cat
		if a["id"] == main.ao_id:
			sel_y = yy
		rows.append([yy, "ao", a])
		yy += 44.0
	# the wheel scrolls it freely; otherwise it keeps the selected AO in view
	var max_scroll := maxf(yy - view_h, 0.0)
	var want: float = main.ao_scroll if float(main.ao_scroll) >= 0.0 else sel_y - view_h * 0.45
	var scroll := clampf(want, 0.0, max_scroll)
	if float(main.ao_scroll) >= 0.0:
		main.ao_scroll = scroll
	ao_scroll_now = scroll
	for row in rows:
		var ry: float = top + float(row[0]) - scroll
		if ry < top - 1.0 or ry + 40.0 > top + view_h + 1.0:
			continue
		if String(row[1]) == "":
			ui_txt(Vector2(px + 2, ry + 17), String(row[2]), Color(ACCENT, 0.85), 11, 0, true)
			draw_line(Vector2(px + 110, ry + 12), Vector2(px + lw, ry + 12), Color(FG, 0.12), 1.0)
			continue
		var a: Dictionary = row[2]
		var r := Rect2(Vector2(px, ry), Vector2(lw, 40))
		var sel: bool = a["id"] == main.ao_id
		var hot := open and r.has_point(mouse)
		draw_rect(r, Color(1, 1, 1, 0.14 if sel else (0.07 if hot else 0.03)))
		if sel:
			draw_rect(Rect2(r.position, Vector2(4, r.size.y)), ACCENT)
		ui_txt(r.position + Vector2(14, 18), String(a["name"]), FG if (sel or hot) else Color(FG, 0.72), 14, 0, true)
		ui_txt(r.position + Vector2(14, 33), "%s  //  %d PATH%s" % [String(a["refuge"]), int(a.get("paths", 1)), "" if int(a.get("paths", 1)) == 1 else "S"], Color(FG, 0.5), 10)
		var best_w: int = int(main.best.get(String(a["id"]), 0))
		var rec := "WAVE %d" % best_w if best_w > 0 else "NOT FLOWN"
		if main.evacuated.get(String(a["id"]), false):
			rec = "EVACUATED"
		ui_txt(r.position + Vector2(lw - 10, 18), rec, GOOD if best_w > 0 else Color(FG, 0.35), 10, 2)
		_threat_pips(r.position + Vector2(lw - 10, 32), int(a.get("threat", 2)), true)
		if open:
			buttons.append([r, "ao:" + String(a["id"])])
	if yy > view_h:
		# where we are in the list
		var tr := Rect2(Vector2(px + lw + 6, top), Vector2(3, view_h))
		draw_rect(tr, Color(FG, 0.08))
		draw_rect(Rect2(Vector2(tr.position.x, top + view_h * scroll / yy), Vector2(3, view_h * view_h / yy)), Color(ACCENT, 0.6))
	var cur: Dictionary = aos[main.ao_index()]
	var bx := px + lw + 24.0
	var bw := pw - lw - 24.0
	var by := py + 28.0
	var bh := minf(view_h, 560.0)
	draw_rect(Rect2(Vector2(bx, by), Vector2(bw, bh)), Color(0, 0, 0, 0.5))
	draw_rect(Rect2(Vector2(bx, by), Vector2(bw, bh)), Color(FG, 0.16), false, 1.0)
	var ix := bx + 20.0
	ui_txt(Vector2(ix, by + 38), String(cur["name"]), FG, 25, 0, true)
	ui_txt(Vector2(ix, by + 62), "REFUGE  //  %s" % String(cur["refuge"]), ACCENT, 13, 0, true)
	_wrap(Vector2(ix, by + 88), String(cur["desc"]), bw - 40.0, 15, FG)
	_wrap(Vector2(ix, by + 132), String(cur["brief"]), bw - 40.0, 13, Color(FG, 0.62))
	var fy := by + 190.0
	for f in [["THREAT", ""], ["TERRAIN", String(cur.get("terrain", ""))], ["APPROACHES", String(cur.get("approaches", ""))]]:
		ui_txt(Vector2(ix, fy), String(f[0]), Color(FG, 0.45), 11, 0, true)
		if String(f[0]) == "THREAT":
			_threat_pips(Vector2(ix + 104, fy + 1), int(cur.get("threat", 2)), false)
		else:
			ui_txt(Vector2(ix + 104, fy), String(f[1]), FG, 13)
		fy += 22.0
	var mapsz := minf(bw - 40.0, by + bh - fy - 16.0)
	if mapsz > 90.0:
		_mini_map(Rect2(Vector2(ix, fy + 4), Vector2(mapsz, mapsz)))

	# the pilot record along the bottom
	var ars = main.arsenal
	var fy2 := sz.y - 26.0
	ui_txt(Vector2(48, fy2), "%s RP" % commas(main.rp), GOOD, 22, 0, true)
	var lvl: int = main.clearance()
	var tiers: Array = ars.TIER_RP
	var cx := 250.0
	ui_txt(Vector2(cx, fy2 - 14), main.rank_name(), FG, 13, 0, true)
	if lvl < tiers.size():
		var lo := float(tiers[lvl - 1])
		var hi := float(tiers[lvl])
		bar(Rect2(Vector2(cx, fy2 - 6), Vector2(150, 6)), (float(main.rp_total) - lo) / maxf(hi - lo, 1.0), ACCENT)
		ui_txt(Vector2(cx + 160, fy2), "PROMOTION AT %s" % commas(int(hi)), Color(FG, 0.45), 11)
	else:
		ui_txt(Vector2(cx, fy2 + 2), "HIGHEST RANK", ACCENT, 11, 0, true)
	var lv_have := 0
	var lv_max := 0
	for u in Perks.UPGRADES + Perks.REFUGE:
		lv_have += int(main.upgrade_level(String(u["id"])))
		lv_max += int(u["max"])
	ui_txt(Vector2(545, fy2), "ARSENAL  %d / %d" % [ars.owned().size(), ars.weapons.size()], FG, 14, 0, true)
	ui_txt(Vector2(725, fy2), "UPGRADES  %d / %d" % [lv_have, lv_max], FG, 14, 0, true)
	ui_txt(Vector2(sz.x - 48, fy2), "W/S  AO      ENTER  DEPLOY      X  IR / TV      v%s" % String(main.VERSION), Color(FG, 0.45), 12, 2)

	if main.menu_panel == "settings":
		_settings_panel(sz, c)




func _over(sz: Vector2, c: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, clampf(main.over_t * 0.3, 0.0, 0.65)))
	var won: bool = main.over_victory
	if won:
		ui_txt(c + Vector2(0, -190), "CAMPAIGN COMPLETE", ACCENT, 22, 1, true)
		txt(c + Vector2(0, -130), main.over_reason, GOOD, 46, 1, font_b)
		txt(c + Vector2(0, -92), "+%s RP  //  %s EVACUATED" % [commas(int(main.wave_summary.get("bonus", 0))), String(main.world["name"])], GOOD, 18, 1, font_b)
	else:
		txt(c + Vector2(0, -130), main.over_reason, WARN, 46, 1, font_b)
	var lines := [
		"Reached wave %d" % main.wave,
		"Infected killed by Spectre  %s" % commas(main.kills),
		"Killed by Hawg gun runs     %s" % commas(main.a10_kills),
		"Killed by the garrison      %s" % commas(main.horde.defender_kills),
		"Biggest single impact       %s" % commas(main.best_multi),
		"Nuclear weapons used        %d" % main.nukes_used,
		"Requisition earned          %s" % commas(main.rp_total),
	]
	var y := c.y - 60.0
	for l in lines:
		txt(Vector2(c.x, y), String(l), FG, 18, 1)
		y += 28.0
	if main.over_t > 2.5 and fmod(main.real_t, 1.2) < 0.85:
		txt(Vector2(c.x, y + 40.0), "CLICK TO FLY AGAIN", FG, 22, 1, font_b)
