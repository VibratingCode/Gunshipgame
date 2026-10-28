extends Node
## Sound playback. Onboard sounds (our guns, crew, radio) are plain 2D players.
## Anything on the ground is a 3D player that starts only after sound has had time
## to travel up to the aircraft at 343 m/s: you see the impacts, then you hear them.

const SPEED_OF_SOUND := 343.0
const VARIANTS := {"bofors": 3, "howitzer": 2, "exp_small": 4, "exp_med": 3, "exp_large": 3, "exp_huge": 2, "m2": 3}
const SINGLES := [
	"gau8_loop", "gau12_loop", "minigun_loop", "gau8_spinup", "gau8_spindown", "gau8_distant", "breech", "clip", "casing",
	"hellfire_launch", "engine_loop", "a10_flyby", "radio_on", "radio_off", "beep", "lock",
	"alarm", "switch", "zoom", "bomb_release", "cluster", "nuke", "buy",
	"laser_loop", "charge", "railgun", "rocket", "drone_launch", "arty", "barrage", "napalm", "neutron",
]
const LOOPS := ["gau8_loop", "gau12_loop", "minigun_loop", "engine_loop", "laser_loop"]
# Each sound goes through one of these buses (under Master), each with its own volume setting.
# Anything not listed is a weapon.
const BUSES := ["Weapons", "Explosions", "Aircraft", "Radio"]
const BUS_OF := {
	"exp_small": "Explosions", "exp_med": "Explosions", "exp_large": "Explosions", "exp_huge": "Explosions",
	"nuke": "Explosions", "napalm": "Explosions", "neutron": "Explosions", "cluster": "Explosions",
	"arty": "Explosions", "barrage": "Explosions",
	"engine_loop": "Aircraft", "a10_flyby": "Aircraft", "gau8_distant": "Aircraft",
	"radio_on": "Radio", "radio_off": "Radio", "beep": "Radio", "lock": "Radio", "alarm": "Radio",
	"switch": "Radio", "zoom": "Radio", "buy": "Radio",
}


static func bus_of(name: String) -> String:
	return String(BUS_OF.get(name, "Weapons"))

var beam_player: AudioStreamPlayer

var streams := {}
var pool2d: Array[AudioStreamPlayer] = []
var pool3d: Array[AudioStreamPlayer3D] = []
var delayed: Array = []
var clock := 0.0
var gau: AudioStreamPlayer
var engine: AudioStreamPlayer
var gau_tween: Tween


func _ready() -> void:
	for b in BUSES:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var bi := AudioServer.bus_count - 1
			AudioServer.set_bus_name(bi, b)
			AudioServer.set_bus_send(bi, "Master")
	for n in SINGLES:
		streams[n] = [load("res://sfx/%s.wav" % n)]
	for n in VARIANTS:
		var arr: Array = []
		for i in int(VARIANTS[n]):
			arr.append(load("res://sfx/%s_%d.wav" % [n, i + 1]))
		streams[n] = arr
	for n in LOOPS:
		_loopify(streams[n][0])
	beam_player = AudioStreamPlayer.new()
	beam_player.stream = streams["laser_loop"][0]
	beam_player.bus = "Weapons"
	add_child(beam_player)

	for i in 24:
		var p := AudioStreamPlayer.new()
		add_child(p)
		pool2d.append(p)
	for i in 40:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 260.0
		p.max_db = 4.0
		p.attenuation_filter_cutoff_hz = 3000.0
		p.attenuation_filter_db = -16.0
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(p)
		pool3d.append(p)

	gau = AudioStreamPlayer.new()
	gau.bus = "Weapons"
	add_child(gau)
	engine = AudioStreamPlayer.new()
	engine.stream = streams["engine_loop"][0]
	engine.volume_db = -13.0
	engine.bus = "Aircraft"
	add_child(engine)

	if AudioServer.get_bus_effect_count(0) == 0:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -0.5
		AudioServer.add_bus_effect(0, lim)


func _loopify(s: AudioStream) -> void:
	if s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)


func _pick(name: String) -> AudioStream:
	var arr: Array = streams.get(name, [])
	if arr.is_empty():
		return null
	return arr[randi() % arr.size()]


func start_engine() -> void:
	if not engine.playing:
		engine.play()


func tick(dt: float, t: float, throttle := 1.0) -> void:
	clock += dt
	engine.pitch_scale = throttle + sin(t * 0.13) * 0.004
	var i := 0
	while i < delayed.size():
		var d: Array = delayed[i]
		if float(d[0]) <= clock:
			delayed.remove_at(i)
			if d[2] == null:
				play(d[1], d[3], d[4])
			else:
				_play3d(d[1], d[2], d[3], d[4])
		else:
			i += 1


func play(name: String, vol_db := 0.0, pitch := 1.0, delay := 0.0) -> void:
	if delay > 0.0:
		delayed.append([clock + delay, name, null, vol_db, pitch])
		return
	var p: AudioStreamPlayer = null
	for q in pool2d:
		if not q.playing:
			p = q
			break
	if p == null:
		p = pool2d[randi() % pool2d.size()]
	p.stream = _pick(name)
	p.bus = bus_of(name)
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.play()


## A sound made at `pos` on the battlefield, heard from `listener` after the travel time.
func play_at(name: String, pos: Vector3, listener: Vector3, vol_db := 0.0, pitch := 1.0) -> void:
	var delay := pos.distance_to(listener) / SPEED_OF_SOUND
	delayed.append([clock + delay, name, pos, vol_db, pitch * randf_range(0.94, 1.06)])


func _play3d(name: String, pos: Vector3, vol_db: float, pitch: float) -> void:
	var p: AudioStreamPlayer3D = null
	for q in pool3d:
		if not q.playing:
			p = q
			break
	if p == null:
		p = pool3d[randi() % pool3d.size()]
	p.stream = _pick(name)
	p.bus = bus_of(name)
	p.global_position = pos
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.play()


## Rotary cannon fire loop; pitch_scale tracks the spin-up rate.
func gun_loop(name: String, pitch: float) -> void:
	if gau_tween:
		gau_tween.kill()
		gau_tween = null
	var s: AudioStream = streams[name][0]
	if gau.stream != s:
		gau.stop()
		gau.stream = s
	if not gau.playing:
		gau.volume_db = 0.0
		gau.play()
	gau.pitch_scale = pitch


func gun_cease() -> void:
	if gau.playing and gau_tween == null:
		gau_tween = create_tween()
		gau_tween.tween_property(gau, "volume_db", -50.0, 0.045)
		gau_tween.tween_callback(gau.stop)
		gau_tween.tween_callback(func() -> void: gau_tween = null)


## Directed-energy hum; called every frame with whether any beam is live.
func beam(on: bool, pitch := 1.0) -> void:
	if on:
		if not beam_player.playing:
			beam_player.volume_db = -3.0
			beam_player.play()
		beam_player.pitch_scale = pitch
	elif beam_player.playing:
		beam_player.stop()


func stop_all_guns() -> void:
	gau.stop()
	beam_player.stop()
