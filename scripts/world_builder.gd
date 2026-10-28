extends RefCounted
## Procedurally builds each area of operations (AO). Every AO is a refuge at the origin with
## corridors radiating out of it; the horde walks straight radial lines down those corridors,
## so buildings, water and terrain are always kept clear of them.
##   city    - gridded city, stadium refuge, eight avenues
##   desert  - FOB in a mountain valley, open sand, a mud-brick village, a highway
##   port    - container terminal and hospital ship, sea to the south, attacks from the land only
##   river   - island prison, four bridges as the only way in
##   arctic  - polar research station on the ice, mountains, blowing snow

const MeshKit = preload("res://scripts/mesh_kit.gd")

# Variants reuse a base AO's builder ("base") with their own approaches ("lay": ["a", deg, half
# width] avenues and ["w", deg, half angle] open wedges) and their own tuning ("tune", merged
# into the world info). "paths" is how many ways in there are; the title screen groups AOs by it.
# The list is in title-screen order: by category, then threat.
const AOS := [
	{"id": "heaven", "name": "FOR GOD, FOR HEAVEN", "refuge": "FIREBASE GABRIEL", "kind": "HIGHLANDS", "threat": 5, "paths": 1,
		"approaches": "One valley. All of them.", "terrain": "Forested hills, real terrain",
		"desc": "Forested hills and one way in. The entire horde comes down a single valley.",
		"brief": "Firebase Gabriel holds the mouth of the valley. Everything in it is coming for us. For God, for heaven."},
	{"id": "needle", "base": "city", "name": "AO NEEDLE", "refuge": "STADIUM", "kind": "URBAN", "threat": 3, "paths": 1,
		"lay": [["a", 90.0, 34.0]], "tune": {"horde_mult": 1.2},
		"approaches": "One boulevard", "terrain": "Downtown towers on every side",
		"desc": "One wide boulevard through downtown, and every one of them is on it.",
		"brief": "The towers have fallen across every street but one. They're coming down the boulevard."},
	{"id": "chute", "base": "desert", "name": "AO CHUTE", "refuge": "FOB CHUTE", "kind": "DESERT", "threat": 3, "paths": 1,
		"lay": [["w", 0.0, 9.0]], "tune": {"horde_mult": 1.2},
		"approaches": "One wadi", "terrain": "Sand, rock, a dry riverbed",
		"desc": "A dry riverbed is the only way through the rocks. They fill it bank to bank.",
		"brief": "FOB Chute sits at the mouth of the wadi. Nothing else can get through the rocks."},
	{"id": "pincer", "base": "desert", "name": "AO PINCER", "refuge": "FOB PINCER", "kind": "DESERT", "threat": 2, "paths": 2,
		"lay": [["w", 60.0, 16.0], ["w", 300.0, 16.0]],
		"approaches": "2 sand wedges", "terrain": "Open desert, mud-brick village",
		"desc": "Two arms of sand close on the base from either side.",
		"brief": "They're coming at FOB Pincer from two sides. Watch both arms."},
	{"id": "twingates", "base": "arctic", "name": "AO TWIN GATES", "refuge": "KEPLER STATION", "kind": "ARCTIC", "threat": 2, "paths": 2,
		"lay": [["a", 20.0, 26.0], ["a", 200.0, 26.0]],
		"approaches": "2 ice roads", "terrain": "Ice sheet, mountains",
		"desc": "Two ice roads run straight through the station, one from each end.",
		"brief": "Two ice roads, two gates. Everything out on the ice is on one of them."},
	{"id": "saltflats", "base": "desert", "name": "AO SALT FLATS", "refuge": "FOB SALT", "kind": "DESERT", "threat": 3, "paths": 3,
		"lay": [["w", 30.0, 20.0], ["w", 150.0, 20.0], ["w", 270.0, 20.0]],
		"approaches": "3 broad wedges", "terrain": "Salt pan, open sand",
		"desc": "Three broad fans of open salt pan. Nowhere for them to hide.",
		"brief": "FOB Salt is out on the flats. Three ways in, and all of them wide open."},
	{"id": "river", "name": "AO GALLOWS", "refuge": "BLACKWATER PRISON", "kind": "RIVERINE", "threat": 3, "paths": 4,
		"approaches": "4 bridges", "terrain": "River island, towns on both banks",
		"desc": "An island prison in a wide river. Four bridges, and every one is a killing ground.",
		"brief": "Blackwater is the only dry ground for miles. They're coming over the bridges."},
	{"id": "oldtown", "base": "city", "name": "AO OLD TOWN", "refuge": "STADIUM", "kind": "URBAN", "threat": 2, "paths": 4,
		"lay": [["a", 0.0, 18.0], ["a", 90.0, 18.0], ["a", 180.0, 18.0], ["a", 270.0, 18.0]],
		"approaches": "4 avenues", "terrain": "Old city blocks, farmland beyond",
		"desc": "The old town's four main streets, one from each point of the compass.",
		"brief": "Four streets into the old town. Hold the crossroads at the stadium."},
	{"id": "desert", "name": "AO ANVIL", "refuge": "FOB ANVIL", "kind": "DESERT", "threat": 2, "paths": 6,
		"approaches": "Highway, 4 broad sand wedges", "terrain": "Open desert, mud-brick village, mountains",
		"desc": "A firebase in a mountain valley. They come across the open sand in broad waves.",
		"brief": "FOB Anvil has two hundred souls behind the HESCO. The whole valley is crawling."},
	{"id": "sprawl", "base": "city", "name": "AO SPRAWL", "refuge": "STADIUM", "kind": "URBAN", "threat": 3, "paths": 6,
		"lay": [["a", 30.0, 16.0], ["a", 90.0, 16.0], ["a", 150.0, 16.0], ["a", 210.0, 16.0], ["a", 270.0, 16.0], ["a", 330.0, 16.0]],
		"approaches": "6 avenues", "terrain": "Suburban sprawl, farmland",
		"desc": "Six avenues out through the suburbs, evenly spaced. No quiet side.",
		"brief": "The suburbs are lost. Six avenues lead in, and they're on all of them."},
	{"id": "port", "name": "AO TRIDENT", "refuge": "PORT TERMINAL", "kind": "COASTAL", "threat": 3, "paths": 7,
		"approaches": "5 roads and 2 yard lanes, landward only", "terrain": "Container yards, cranes, sea",
		"desc": "A container port. A hospital ship at the quay and the sea at your back.",
		"brief": "The hospital ship can't sail until it's loaded. Hold the terminal and the quay."},
	{"id": "arctic", "name": "AO FROSTBITE", "refuge": "KEPLER STATION", "kind": "ARCTIC", "threat": 3, "paths": 7,
		"approaches": "Skiway, 5 ice fields", "terrain": "Ice sheet, frozen lake, mountains",
		"desc": "A polar station on the ice. Nothing out here is warm except them.",
		"brief": "Kepler Station is all that's left on the ice. Nothing out there is warm except them."},
	{"id": "city", "name": "AO HOMEFIELD", "refuge": "STADIUM", "kind": "URBAN", "threat": 2, "paths": 10,
		"approaches": "8 avenues, 2 city parks", "terrain": "Dense city grid, farmland beyond",
		"desc": "A gridded city. Eight avenues funnel the horde into the last stadium.",
		"brief": "The stadium is the last safe zone in the city. Anything outside the wall is hostile."},
	{"id": "starfall", "base": "arctic", "name": "AO STARFALL", "refuge": "KEPLER STATION", "kind": "ARCTIC", "threat": 4, "paths": 12,
		"lay": [["a", 0.0, 14.0], ["a", 45.0, 14.0], ["a", 90.0, 14.0], ["a", 135.0, 14.0], ["a", 180.0, 14.0], ["a", 225.0, 14.0], ["a", 270.0, 14.0], ["a", 315.0, 14.0],
			["w", 22.5, 8.0], ["w", 112.5, 8.0], ["w", 202.5, 8.0], ["w", 292.5, 8.0]], "tune": {"horde_mult": 1.3},
		"approaches": "8 ice roads, 4 ice fields", "terrain": "Open ice in every direction",
		"desc": "A star of ice roads. They come from every point of the compass at once.",
		"brief": "Starfall station is a crossroads on the ice, and the ice is full of them."},
	{"id": "gridlock", "base": "city", "name": "AO GRIDLOCK", "refuge": "STADIUM", "kind": "URBAN", "threat": 4, "paths": 12,
		"lay": [["a", 0.0, 14.0], ["a", 30.0, 12.0], ["a", 60.0, 12.0], ["a", 90.0, 14.0], ["a", 120.0, 12.0], ["a", 150.0, 12.0],
			["a", 180.0, 14.0], ["a", 210.0, 12.0], ["a", 240.0, 12.0], ["a", 270.0, 14.0], ["a", 300.0, 12.0], ["a", 330.0, 12.0]], "tune": {"horde_mult": 1.3},
		"approaches": "12 streets", "terrain": "A city cut to pieces by roads",
		"desc": "Twelve streets, every one of them jammed. You can't watch them all.",
		"brief": "Gridlock: twelve streets into the stadium and every one is moving."},
	{"id": "theopen", "base": "desert", "name": "AO THE OPEN", "refuge": "FOB OPEN", "kind": "DESERT", "threat": 4, "paths": 10,
		"lay": [["w", 0.0, 12.0], ["w", 36.0, 12.0], ["w", 72.0, 12.0], ["w", 108.0, 12.0], ["w", 144.0, 12.0],
			["w", 180.0, 12.0], ["w", 216.0, 12.0], ["w", 252.0, 12.0], ["w", 288.0, 12.0], ["w", 324.0, 12.0]], "tune": {"horde_mult": 1.3},
		"approaches": "10 sand wedges", "terrain": "Open desert all the way round",
		"desc": "A base in the open desert. They come across the sand from every side.",
		"brief": "FOB Open is the only thing standing for fifty kilometres. They're coming from everywhere."},
	{"id": "sott", "base": "desert", "name": "SMOKE OF THEIR TORMENT", "refuge": "THE LAST LIGHT", "kind": "CHALLENGE", "threat": 5, "paths": 1, "challenge": true,
		"lay": [["w", 0.0, 35.0]], "torment": true,
		"tune": {"horde_mult": 4.0, "mega_from": 999, "haze_heat": 0.34, "haze_dist": 8000.0,
			"sun": Vector3(-0.8, 0.22, 0.4), "sky": Vector3(0.42, 0.24, 0.18), "tv_fog": 5000.0},
		"approaches": "One front, horizon to horizon", "terrain": "A burnt plain under smoke",
		"desc": "Every wave rolls in from the horizon as one tide of the dead, three bosses in it, at blood-moon pace. Hold as long as you can.",
		"brief": "There is no rescue coming. Hold the last light as long as you can."},
	{"id": "sott_iron", "base": "desert", "name": "SOTT  //  IRON TORMENT", "refuge": "THE LAST LIGHT", "kind": "CHALLENGE", "threat": 5, "paths": 1, "challenge": true,
		"lay": [["w", 0.0, 35.0]], "torment": true, "iron": true,
		"tune": {"horde_mult": 4.0, "mega_from": 999, "haze_heat": 0.34, "haze_dist": 8000.0,
			"sun": Vector3(-0.8, 0.22, 0.4), "sky": Vector3(0.42, 0.24, 0.18), "tv_fog": 5000.0},
		"approaches": "One front, horizon to horizon", "terrain": "A burnt plain under smoke",
		"desc": "Smoke of Their Torment with nothing but a GAU-8. Earn and buy everything else wave by wave. Nothing comes in with you and nothing leaves but XP.",
		"brief": "One gun, no upgrades, no career. Everything you buy dies with the sortie."},
]
const PITCH := 70.0
const STREET := 14.0

var ao := "city"
var corridors: Array = []
var lock_corridors := false
var bodies: Array[RID] = []
var survivor_spots: Array = []
var defender_spots: Array[Vector3] = []
var rng := RandomNumberGenerator.new()
var root: Node3D
var space: RID
var mat_world: ShaderMaterial
var st: SurfaceTool
var tree_xf: Array[Transform3D] = []
var trunk_xf: Array[Transform3D] = []
var car_xf: Array[Transform3D] = []
var car_cd: Array[Color] = []
var bus_xf: Array[Transform3D] = []
var bus_cd: Array[Color] = []
var lorry_xf: Array[Transform3D] = []
var lorry_cd: Array[Color] = []
var lamp_xf: Array[Transform3D] = []
# things that keep burning (wrecks, barrel fires, rooftop campfires): main keeps the flames going
var fires: Array[Vector3] = []
# lots kept clear of the procedural blocks: landmarks and the airstrip
var reserved: Array[Rect2] = []
var info := {}


static func ao_info(id: String) -> Dictionary:
	for a in AOS:
		if a["id"] == id:
			return a
	return AOS[0]


## The AO whose builder, story and weather an AO uses.
static func base_of(id: String) -> String:
	return String(ao_info(id).get("base", id))


func build(parent: Node3D, id: String) -> Dictionary:
	root = parent
	var spec := ao_info(id)
	ao = base_of(id)
	rng.seed = 7741 + hash(id)
	space = parent.get_world_3d().space
	mat_world = ShaderMaterial.new()
	mat_world.shader = load("res://shaders/world.gdshader")
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	info = {
		"wall_r": 58.0, "arrive": Vector2(60.0, 84.0), "attract": Vector3(260, 0, 30),
		"haze_heat": 0.30, "haze_dist": 11000.0, "ground": 0, "refuge_h": 24.0,
		"horde_mult": 1.0, "mega_from": 4, "garrison": 1.0,
		# daylight colour camera: sun direction, horizon haze colour, haze distance
		"sun": Vector3(-0.45, 0.78, 0.43), "sky": Vector3(0.66, 0.74, 0.84), "tv_fog": 7000.0,
	}
	MeshKit.tag = MeshKit.TAG_AUTO
	# a variant lays its own approaches first, and the base builder's are ignored
	if spec.has("lay"):
		for l in spec["lay"]:
			if String(l[0]) == "a":
				_avenue(float(l[1]), float(l[2]))
			else:
				_wedge(float(l[1]), float(l[2]))
		lock_corridors = true
	match ao:
		"desert":
			_desert()
		"port":
			_port()
		"river":
			_river()
		"arctic":
			_arctic()
		"heaven":
			_heaven()
		_:
			_city()
	lock_corridors = false
	if spec.has("tune"):
		info.merge(spec["tune"], true)
	if spec.get("torment", false):
		_torment()
	_ground(int(info["ground"]))
	MeshKit.tag = MeshKit.TAG_AUTO
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat_world
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)

	if not tree_xf.is_empty():
		var tree := SphereMesh.new()
		tree.radius = 1.0
		tree.height = 2.0
		tree.radial_segments = 7
		tree.rings = 3
		_static_multimesh(tree, tree_xf, "res://shaders/tree.gdshader")
	if not trunk_xf.is_empty():
		_static_multimesh(MeshKit.trunk(), trunk_xf, "res://shaders/world.gdshader")
	if not car_xf.is_empty():
		_static_multimesh(MeshKit.car(), car_xf, "res://shaders/car.gdshader", car_cd)
	if not bus_xf.is_empty():
		_static_multimesh(MeshKit.bus(false), bus_xf, "res://shaders/car.gdshader", bus_cd)
	if not lorry_xf.is_empty():
		_static_multimesh(MeshKit.bus(true), lorry_xf, "res://shaders/car.gdshader", lorry_cd)
	if not lamp_xf.is_empty():
		_static_multimesh(MeshKit.streetlight(), lamp_xf, "res://shaders/lamp.gdshader")
		# and the pool of light each one throws on the road
		var pool := PlaneMesh.new()
		pool.size = Vector2(24, 24)
		pool.center_offset = Vector3(0, 0.22, -2.3)
		_static_multimesh(pool, lamp_xf, "res://shaders/lamp_pool.gdshader")

	var a := ao_info(id)
	info.merge({
		"id": id, "base": ao, "name": a["name"], "refuge": a["refuge"], "brief": a["brief"],
		"torment": bool(a.get("torment", false)), "iron": bool(a.get("iron", false)),
		"corridors": corridors, "bodies": bodies,
		"survivor_spots": survivor_spots, "defender_spots": defender_spots,
		"fires": fires, "landmarks": landmarks,
	}, true)
	return info


# --------------------------------------------------------------- corridors
func _avenue(deg: float, hw: float) -> Dictionary:
	var c := {"type": 0, "ang": deg_to_rad(deg), "hw": hw, "rmin": 0.0, "rmax": 100000.0}
	if not lock_corridors:
		corridors.append(c)
	return c


func _wedge(deg: float, half_deg: float) -> Dictionary:
	var c := {"type": 1, "ang": deg_to_rad(deg), "half": deg_to_rad(half_deg), "rmin": 0.0, "rmax": 100000.0}
	if not lock_corridors:
		corridors.append(c)
	return c


## Smoke of Their Torment: the plain the tide comes across is burnt, and still burning.
func _torment() -> void:
	MeshKit.tag = MeshKit.TAG_DIRT
	for k in 120:
		var p := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(250.0, 3200.0)
		var s := rng.randf_range(0.8, 2.0)
		MeshKit.box(st, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(p.x, 0.3, p.y)), Vector3(s, 0.6, s), Color(1.5, 0.0, 0.0, 1.0))
		fires.append(Vector3(p.x, 0.9, p.y))
	MeshKit.tag = MeshKit.TAG_AUTO


func blocked(p: Vector2, margin: float) -> bool:
	for c in corridors:
		var ang: float = c["ang"]
		var d := Vector2(cos(ang), sin(ang))
		if int(c["type"]) == 0:
			if p.dot(d) > 0.0 and absf(p.cross(d)) < float(c["hw"]) + margin:
				return true
		else:
			var r := p.length()
			if r > 60.0 and absf(angle_difference(ang, p.angle())) < float(c["half"]) + margin / maxf(r, 1.0):
				return true
	return false


func in_wedge(p: Vector2) -> bool:
	for c in corridors:
		if int(c["type"]) == 1 and absf(angle_difference(float(c["ang"]), p.angle())) < float(c["half"]) + 0.05:
			return true
	return false


# --------------------------------------------------------------- landmarks
# A few big buildings beside the approaches. They're nodes of their own with their own collision,
# so a mission can infest one and the player can bring it down.
const LANDMARK_NAMES := {
	"city": ["THE OLD HOSPITAL", "CENTRAL MALL", "THE HIGH SCHOOL", "THE PARKING GARAGE"],
	"desert": ["THE CEMENT WORKS", "THE PUMP STATION", "THE OLD MOSQUE"],
	"port": ["WAREHOUSE NINE", "THE COLD STORE", "THE CUSTOMS HOUSE"],
	"river": ["THE CANNERY", "THE COURTHOUSE", "THE OLD MILL"],
	"arctic": ["THE DRILL HANGAR", "THE FUEL DEPOT", "THE SEISMIC HUT"],
	"heaven": ["THE HUNTING LODGE", "THE SAWMILL", "THE RANGER STATION"],
}
var landmarks: Array = []


## Find sites for landmarks beside the approaches, between r0 and r1 from the refuge, and keep
## their lots clear (snap: on the city block grid).
func _plan_landmarks(n: int, r0: float, r1: float, snap: bool) -> Array[Vector2]:
	var sites: Array[Vector2] = []
	var tries := 0
	while sites.size() < n and tries < 600:
		tries += 1
		var c: Dictionary = corridors[rng.randi() % corridors.size()]
		var a: float = c["ang"]
		var r := rng.randf_range(maxf(r0, float(c["rmin"]) + 80.0), r1)
		var d := Vector2(cos(a), sin(a))
		var perp := Vector2(-d.y, d.x)
		var off := float(c["hw"]) + 38.0 if int(c["type"]) == 0 else r * tan(float(c["half"])) + 40.0
		var p := d * r + perp * off * (1.0 if rng.randf() < 0.5 else -1.0)
		if snap:
			p = (p / PITCH).floor() * PITCH + Vector2(PITCH * 0.5, PITCH * 0.5)
		if blocked(p, 30.0) or is_water(p) or is_water(p + Vector2(30, 30)) or is_water(p - Vector2(30, 30)) or _reserved_at(p):
			continue
		if terrain_noise != null and terrain_h(p) > 0.3:
			continue
		var crowded := false
		for s in sites:
			if s.distance_to(p) < 300.0:
				crowded = true
		if crowded:
			continue
		sites.append(p)
		reserved.append(Rect2(p - Vector2(PITCH, PITCH) * 0.5, Vector2(PITCH, PITCH)))
	return sites


func _build_landmark(p: Vector2, lname: String) -> void:
	var lst := SurfaceTool.new()
	lst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var heat := rng.randf_range(0.33, 0.38)
	var size := Vector3(44.0, rng.randf_range(18.0, 28.0), 40.0)
	var tag := MeshKit.TAG_BUILDING
	match ao:
		"desert":
			size = Vector3(40.0, 10.0, 34.0)
			tag = MeshKit.TAG_MUD
		"port":
			size = Vector3(50.0, 15.0, 30.0)
			tag = MeshKit.TAG_STEEL
		"arctic":
			size = Vector3(40.0, 14.0, 30.0)
			tag = MeshKit.TAG_RED
		"heaven":
			size = Vector3(32.0, 10.0, 22.0)
			tag = MeshKit.TAG_TIMBER
		"river":
			size = Vector3(40.0, 16.0, 28.0)
	var yaw := 0.0 if ao in ["city", "river", "port"] else rng.randf() * TAU
	var b := Basis(Vector3.UP, yaw)
	var prev := MeshKit.tag
	MeshKit.tag = tag
	MeshKit.box(lst, Transform3D(b, Vector3(0, size.y * 0.5, 0)), size, Color(heat, 1.0, 1.0, 0.4))
	MeshKit.tag = MeshKit.TAG_CONCRETE
	for e: Array in [[Vector3(0, 0, -size.z * 0.5 + 0.25), Vector3(size.x, 1.2, 0.5)], [Vector3(0, 0, size.z * 0.5 - 0.25), Vector3(size.x, 1.2, 0.5)],
			[Vector3(-size.x * 0.5 + 0.25, 0, 0), Vector3(0.5, 1.2, size.z)], [Vector3(size.x * 0.5 - 0.25, 0, 0), Vector3(0.5, 1.2, size.z)]]:
		MeshKit.box(lst, Transform3D(b, Vector3(0, size.y + 0.6, 0) + b * (e[0] as Vector3)), e[1], Color(heat, 1.0, 1.0, 1.0))
	MeshKit.tag = MeshKit.TAG_STEEL
	for k in 5:
		MeshKit.box(lst, Transform3D(b, Vector3(rng.randf_range(-size.x * 0.35, size.x * 0.35), size.y + 0.8, rng.randf_range(-size.z * 0.35, size.z * 0.35))), Vector3(3.0, 1.6, 3.0), Color(rng.randf_range(0.5, 0.75), 0.2, 0.4, 1.0))
	if ao == "heaven":
		MeshKit.tag = MeshKit.TAG_TIMBER
		MeshKit.gable(lst, Vector3.ZERO, size.x, size.z, size.y, 5.0, yaw, Color(heat - 0.03, 0.8, 0.6, 1.0))
	elif ao == "desert":
		MeshKit.tag = MeshKit.TAG_MUD
		MeshKit.dome(lst, Vector3(0, size.y, 0), 9.0, Color(heat, 0.4, 0.8, 1.0))
	MeshKit.tag = prev
	var mi := MeshInstance3D.new()
	mi.mesh = lst.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/world.gdshader")
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.position = Vector3(p.x, 0.0, p.y)
	# collision of its own, kept out of `bodies`: a mission may knock it down
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	var sh := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(sh, size * 0.5)
	PhysicsServer3D.body_add_shape(body, sh)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(b, Vector3(p.x, size.y * 0.5, p.y)))
	PhysicsServer3D.body_set_space(body, space)
	landmarks.append({"pos": Vector3(p.x, 0.0, p.y), "size": size, "yaw": yaw, "node": mi, "mat": mat, "body": body, "shape": sh, "name": lname, "alive": true})


func _landmarks(n: int, r0: float, r1: float, snap: bool) -> void:
	var names: Array = (LANDMARK_NAMES.get(ao, LANDMARK_NAMES["city"]) as Array).duplicate()
	var sites := _plan_landmarks(mini(n, names.size()), r0, r1, snap)
	for i in sites.size():
		_build_landmark(sites[i], String(names[i]))


# --------------------------------------------------------------- the airstrip
## The FARP the A-10 flies from in CAS mode: a runway out past the approaches, an apron with a
## hangar, fuel bowsers and bombs on trolleys, a tower and a windsock. Rearm and refuel happen
## anywhere on it once you've stopped.
func _airfield(center: Vector2, dir: Vector2, length := 1600.0, width := 45.0) -> void:
	var perp := Vector2(-dir.y, dir.x)
	var apron := center - dir * (length * 0.5 - 140.0) + perp * (width * 0.5 + 75.0)
	# keep the blocks, trees and farms off it
	var corners: Array[Vector2] = []
	for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		corners.append(center + dir * (length * 0.5 + 60.0) * s.x + perp * (width * 0.5 + 170.0) * s.y)
	var lo := corners[0]
	var hi := corners[0]
	for q in corners:
		lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
		hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
	reserved.append(Rect2(lo, hi - lo))
	info["airfield"] = {"center": Vector3(center.x, 0.0, center.y), "dir": Vector3(dir.x, 0.0, dir.y), "length": length, "width": width,
		"apron": Vector3(apron.x, 0.0, apron.y)}
	var asphalt := Color(0.4, 0.0, 0.6, 1.0)
	MeshKit.tag = MeshKit.TAG_ASPHALT
	_flat(center, Vector2(length * 0.5, width * 0.5), dir, 0.11, asphalt)
	_flat(apron, Vector2(110.0, 60.0), dir, 0.1, asphalt)
	# a taxiway from the apron to the runway
	var tw := (apron + center - dir * (length * 0.5 - 140.0)) * 0.5
	_flat(tw, Vector2(12.0, (width * 0.5 + 75.0) * 0.5 + 6.0), perp, 0.105, asphalt)
	# markings: centreline dashes, threshold piano keys, touchdown bars
	MeshKit.tag = MeshKit.TAG_WHITE
	var paint := Color(0.4, 0.0, 0.6, 1.0)
	var x := -length * 0.5 + 120.0
	while x < length * 0.5 - 120.0:
		_flat(center + dir * x, Vector2(9.0, 0.45), dir, 0.12, paint)
		x += 36.0
	for end: float in [-1.0, 1.0]:
		for k in 8:
			var lat := (float(k) - 3.5) * 4.6
			_flat(center + dir * (length * 0.5 - 30.0) * end + perp * lat, Vector2(15.0, 0.9), dir, 0.12, paint)
		for k in 3:
			for s: float in [-1.0, 1.0]:
				_flat(center + dir * (length * 0.5 - 150.0 - k * 60.0) * end + perp * 9.0 * s, Vector2(11.0, 1.6), dir, 0.12, paint)
	# edge lights, lamps that glow after dark
	MeshKit.tag = MeshKit.TAG_WHITE
	x = -length * 0.5
	while x <= length * 0.5:
		for s: float in [-1.0, 1.0]:
			var lp := center + dir * x + perp * (width * 0.5 + 2.0) * s
			MeshKit.box(st, Transform3D(Basis(), Vector3(lp.x, 0.35, lp.y)), Vector3(0.4, 0.7, 0.4), Color(1.12, 0.8, 0.0, 1.0))
		x += 60.0
	# the apron: a hangar, the tower, fuel bowsers, bombs on trolleys, tents, a windsock
	var yaw := -dir.angle()
	var b := Basis(Vector3.UP, yaw)
	var ap3 := Vector3(apron.x, 0.0, apron.y)
	MeshKit.tag = MeshKit.TAG_STEEL
	_solid(ap3 + b * Vector3(-40.0, 8.0, 40.0), Vector3(46.0, 16.0, 34.0), Color(0.37, 1.0, 1.0, 1.0), yaw)
	MeshKit.tag = MeshKit.TAG_DARK
	MeshKit.box(st, Transform3D(b, ap3 + b * Vector3(-40.0, 6.0, 22.9)), Vector3(36.0, 12.0, 0.3), Color(0.3, 0.0, 0.0, 1.0))
	MeshKit.tag = MeshKit.TAG_CONCRETE
	_solid(ap3 + b * Vector3(55.0, 9.0, 45.0), Vector3(6.0, 18.0, 6.0), Color(0.38, 1.0, 1.0, 1.0), yaw)
	MeshKit.tag = MeshKit.TAG_GLASS
	MeshKit.box(st, Transform3D(b, ap3 + b * Vector3(55.0, 19.5, 45.0)), Vector3(8.0, 3.0, 8.0), Color(0.42, 1.0, 1.0, 0.4))
	MeshKit.tag = MeshKit.TAG_OLIVE
	for k in 6:
		MeshKit.box(st, Transform3D(b, ap3 + b * Vector3(-5.0 + k * 3.0, 0.5, 30.0)), Vector3(2.2, 1.0, 3.6), Color(0.3, 0.3, 0.5, 1.0))
	for k in 3:
		_big_vehicle(ap3 + b * Vector3(20.0 + k * 9.0, 0.0, 34.0), yaw, true)
	MeshKit.tag = MeshKit.TAG_TENT
	for k in 5:
		MeshKit.box(st, Transform3D(b, ap3 + b * Vector3(80.0 + (k % 3) * 9.0, 1.4, 20.0 + int(k / 3) * 10.0)), Vector3(6.0, 2.8, 8.0), Color(0.5, 0.0, 0.6, 1.0))
	var ws := ap3 + b * Vector3(95.0, 0.0, -50.0)
	MeshKit.tag = MeshKit.TAG_DARK
	MeshKit.box(st, Transform3D(Basis(), ws + Vector3.UP * 4.0), Vector3(0.2, 8.0, 0.2), Color(0.26, 0.0, 0.0, 1.0))
	MeshKit.tag = MeshKit.TAG_YELLOW
	MeshKit.box(st, Transform3D(b, ws + Vector3.UP * 7.6 + b * Vector3(1.5, 0.0, 0.0)), Vector3(3.0, 0.5, 0.5), Color(0.3, 0.0, 0.0, 1.0))
	MeshKit.tag = MeshKit.TAG_AUTO
	for k in 4:
		var lp := apron + perp * (-55.0 + k * 36.0) - dir * 62.0
		_lamp(lp, lp + dir * 10.0)


## How much of the forest terrain is left standing at p: zero on and around the airstrip.
func _airstrip_clear(p: Vector2) -> float:
	if not info.has("airfield"):
		return 1.0
	var af: Dictionary = info["airfield"]
	var c: Vector3 = af["center"]
	var d: Vector3 = af["dir"]
	var rel := Vector2(p.x - c.x, p.y - c.z)
	var along := absf(rel.dot(Vector2(d.x, d.z))) - float(af["length"]) * 0.5
	var lat := absf(rel.cross(Vector2(d.x, d.z))) - float(af["width"]) * 0.5 - 200.0
	return smoothstep(0.0, 160.0, maxf(along, lat))


## Must agree with water_mask() in ground.gdshader.
func is_water(p: Vector2) -> bool:
	match ao:
		"port":
			return p.y > 40.0
		"river":
			var m := 25.0 * sin(p.x * 0.004)
			var island := (p.x / 230.0) * (p.x / 230.0) + (p.y / 160.0) * (p.y / 160.0) < 1.0
			return absf(p.y - m) < 270.0 and not island
	return false


# --------------------------------------------------------------- helpers
func _body(center: Vector3, size: Vector3, basis := Basis()) -> void:
	var b := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(b, PhysicsServer3D.BODY_MODE_STATIC)
	var sh := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(sh, size * 0.5)
	PhysicsServer3D.body_add_shape(b, sh)
	PhysicsServer3D.body_set_state(b, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(basis, center))
	PhysicsServer3D.body_set_space(b, space)
	bodies.append(b)
	bodies.append(sh)


## A solid box with collision. `yaw` rotates it about the vertical.
func _solid(center: Vector3, size: Vector3, col: Color, yaw := 0.0, collide := true) -> void:
	var b := Basis(Vector3.UP, yaw)
	MeshKit.box(st, Transform3D(b, center), size, col)
	if collide:
		_body(center, size, b)


func _flat(c: Vector2, half: Vector2, axis: Vector2, y: float, col: Color) -> void:
	var u := axis * half.x
	var v := Vector2(-axis.y, axis.x) * half.y
	var p := [c - u - v, c + u - v, c + u + v, c - u + v]
	var q: Array[Vector3] = []
	for k in 4:
		q.append(Vector3(p[k].x, y, p[k].y))
	MeshKit.quad(st, q[0], q[1], q[2], q[3], Vector3.UP, col)


## A wall segment between two ground points.
func _wall(a: Vector2, b: Vector2, h: float, thick: float, col: Color, collide := true) -> void:
	var mid := (a + b) * 0.5
	var d := b - a
	_solid(Vector3(mid.x, h * 0.5, mid.y), Vector3(d.length(), h, thick), col, -d.angle(), collide)


func _ground(kind: int) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(17000, 17000)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/ground.gdshader")
	mat.set_shader_parameter("kind", kind)
	mi.material_override = mat
	root.add_child(mi)

	var b := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(b, PhysicsServer3D.BODY_MODE_STATIC)
	var sh := PhysicsServer3D.world_boundary_shape_create()
	PhysicsServer3D.shape_set_data(sh, Plane(Vector3.UP, 0.0))
	PhysicsServer3D.body_add_shape(b, sh)
	PhysicsServer3D.body_set_space(b, space)
	bodies.append(b)
	bodies.append(sh)


## An abandoned car (pos.y is the old box centre height; the car sits on the ground under it).
## Some are burnt-out wrecks, a handful still burning, a few with a warm engine.
func _car(pos: Vector3, yaw: float, burnt_p := 0.12) -> void:
	car_xf.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, pos.y - 0.72, pos.z)))
	car_cd.append(_wreck_state(Vector3(pos.x, 0.0, pos.z), burnt_p))


## A bus or a lorry, sitting on the ground at pos.
func _big_vehicle(pos: Vector3, yaw: float, lorry: bool, basis := Basis()) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw) * basis, pos)
	if lorry:
		lorry_xf.append(xf)
		lorry_cd.append(_wreck_state(pos, 0.2))
	else:
		bus_xf.append(xf)
		bus_cd.append(_wreck_state(pos, 0.2))


## (burnt out, still burning, paint seed, warm engine) for car.gdshader.
func _wreck_state(pos: Vector3, burnt_p: float) -> Color:
	var burnt := rng.randf() < burnt_p
	var burning := burnt and rng.randf() < 0.14
	if burning:
		fires.append(pos + Vector3.UP * 1.5)
	return Color(1.0 if burnt else 0.0, 1.0 if burning else 0.0, rng.randf(), 1.0 if rng.randf() < 0.14 else 0.0)


func _tree(p: Vector2, scale := 1.0) -> void:
	if _reserved_at(p):
		return
	var r := rng.randf_range(2.4, 5.5) * scale
	var cy := r + 1.5 * scale
	tree_xf.append(Transform3D(Basis().scaled(Vector3(r, r * rng.randf_range(0.8, 1.1), r)), Vector3(p.x, cy, p.y)))
	var th := cy - r * 0.5
	var tw := 0.7 + scale * 0.5
	trunk_xf.append(Transform3D(Basis().scaled(Vector3(tw, th, tw)), Vector3(p.x, 0.0, p.y)))


## A streetlight at p with its arm reaching toward `toward` (the middle of the road).
func _lamp(p: Vector2, toward: Vector2) -> void:
	var d := toward - p
	var yaw := atan2(-d.x, -d.y) if d.length() > 0.01 else 0.0
	lamp_xf.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, 0.0, p.y)))


func _static_multimesh(mesh: Mesh, xfs: Array[Transform3D], shader_path: String, customs: Array[Color] = []) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = not customs.is_empty()
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		if i < customs.size():
			mm.set_instance_custom_data(i, customs[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = load(shader_path)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## Road surface down every avenue corridor between r0 and r1, skipping water.
func _avenue_roads(r0: float, r1: float, heat := 0.42) -> void:
	for c in corridors:
		if int(c["type"]) != 0:
			continue
		var a: float = c["ang"]
		var d := Vector2(cos(a), sin(a))
		var r := r0
		while r < r1:
			var seg := 40.0
			if not is_water(d * (r + seg * 0.5)):
				MeshKit.tag = MeshKit.TAG_SNOW if ao == "arctic" else MeshKit.TAG_ASPHALT
				_flat(d * (r + seg * 0.5), Vector2(seg * 0.5 + 0.5, float(c["hw"])), d, 0.08, Color(heat, 0.0, 0.7, 1.0))
				# painted centre line, dashed
				if ao != "arctic" and int(r / seg) % 2 == 0:
					MeshKit.tag = MeshKit.TAG_WHITE
					_flat(d * (r + seg * 0.5), Vector2(seg * 0.25, 0.18), d, 0.09, Color(heat, 0.0, 0.7, 1.0))
			r += seg
	MeshKit.tag = MeshKit.TAG_AUTO


## City blocks (streets + buildings) everywhere `in_district` allows.
func _district(in_district: Callable, clear_r: float, town := false) -> void:
	var asphalt := Color(0.39, 0.0, 0.7, 1.0)
	var bs := PITCH - STREET
	for bx in range(-19, 19):
		for bz in range(-19, 19):
			var sx := bx * PITCH
			var sz := bz * PITCH
			var center := Vector2(sx + PITCH * 0.5, sz + PITCH * 0.5)
			if not in_district.call(center):
				continue
			MeshKit.tag = MeshKit.TAG_ASPHALT
			_flat(Vector2(sx, sz + PITCH * 0.5), Vector2(PITCH * 0.5 + STREET * 0.5, STREET * 0.5), Vector2(0, 1), 0.06, asphalt)
			_flat(Vector2(sx + PITCH * 0.5, sz), Vector2(PITCH * 0.5 + STREET * 0.5, STREET * 0.5), Vector2(1, 0), 0.06, asphalt)
			var r := center.length()
			if r < clear_r or _reserved_at(center):
				continue
			# the block itself: kerbed pavement (or a garden, out in the suburbs)
			if not blocked(center, bs * 0.5):
				MeshKit.tag = MeshKit.TAG_GRASS if (town and rng.randf() < 0.5) else MeshKit.TAG_CONCRETE
				_flat(center, Vector2(bs * 0.5, bs * 0.5), Vector2(1, 0), 0.07, Color(0.34, 0.0, 0.6, 1.0))
			var x0 := sx + STREET * 0.5
			var z0 := sz + STREET * 0.5
			var div := 3 if town else (1 if r < 380.0 else (2 if r < 760.0 else 3))
			var lot := bs / div
			for i in div:
				for j in div:
					if rng.randf() < (0.06 if div == 1 else 0.16):
						continue
					var setback := 2.5 if div == 3 else 3.0
					var w := lot - setback * 2.0 - rng.randf_range(0.0, lot * 0.22)
					var dd := lot - setback * 2.0 - rng.randf_range(0.0, lot * 0.22)
					var cx := x0 + lot * (i + 0.5)
					var cz := z0 + lot * (j + 0.5)
					var hx := w * 0.5 + 2.0
					var hz := dd * 0.5 + 2.0
					var ok := true
					for corner in [Vector2(cx - hx, cz - hz), Vector2(cx + hx, cz - hz), Vector2(cx + hx, cz + hz), Vector2(cx - hx, cz + hz), Vector2(cx, cz)]:
						if blocked(corner, 3.0) or not in_district.call(corner):
							ok = false
							break
					if not ok:
						continue
					var h: float
					if div == 1:
						h = rng.randf_range(14.0, 34.0) * clampf(1.5 - r / 800.0, 0.7, 1.4)
						if rng.randf() < 0.22:
							h *= 1.7
					elif div == 2:
						h = rng.randf_range(7.0, 18.0)
					else:
						h = rng.randf_range(4.5, 8.0)
					var heat := rng.randf_range(0.31, 0.39) if div < 3 else rng.randf_range(0.3, 0.36)
					# the street sides of this lot, for shopfront awnings and balconies
					var faces: Array[Vector2] = []
					if i == 0:
						faces.append(Vector2.LEFT)
					if i == div - 1:
						faces.append(Vector2.RIGHT)
					if j == 0:
						faces.append(Vector2.UP)
					if j == div - 1:
						faces.append(Vector2.DOWN)
					if div < 3:
						# a few blocks have already burnt out: lower, gutted, rubble round the foot
						var burnt := rng.randf() < 0.07
						if burnt:
							h *= rng.randf_range(0.45, 0.8)
							heat = rng.randf_range(0.26, 0.3)
							MeshKit.tag = MeshKit.TAG_BURNT
						else:
							MeshKit.tag = MeshKit.TAG_GLASS if (div == 1 and h > 38.0 and rng.randf() < 0.7) else MeshKit.TAG_BUILDING
						_solid(Vector3(cx, h * 0.5, cz), Vector3(w, h, dd), Color(heat, 1.0, 1.0, 0.35))
						_rooftop(Vector2(cx, cz), w, dd, h, heat, r, burnt, div)
						if burnt:
							_rubble(Vector2(cx, cz), w, dd)
						elif not faces.is_empty():
							_street_face(Vector2(cx, cz), w, dd, h, faces[rng.randi() % faces.size()], r, div)
					else:
						# a house: walls, a pitched roof, a chimney now and then, a car in the drive
						MeshKit.tag = MeshKit.TAG_BUILDING
						_solid(Vector3(cx, h * 0.5, cz), Vector3(w, h, dd), Color(heat, 1.0, 1.0, 1.0))
						MeshKit.gable(st, Vector3(cx, 0.0, cz), w, dd, h, minf(w, dd) * 0.32, 0.0, Color(heat - 0.02, 0.8, 0.6, 1.0))
						if rng.randf() < 0.4:
							MeshKit.box(st, Transform3D(Basis(), Vector3(cx + w * 0.3, h + minf(w, dd) * 0.25, cz)), Vector3(0.8, 1.8, 0.8), Color(rng.randf_range(0.5, 0.75), 0.2, 0.3, 1.0))
						if rng.randf() < 0.5:
							_car(Vector3(cx + w * 0.5 + 2.2, 0.72, cz), rng.randf_range(-0.2, 0.2))
			# streetlights down both streets of the block
			if r > clear_r * 0.8:
				var pa := Vector2(sx + 7.8, sz + PITCH * 0.5)
				var pb := Vector2(sx + PITCH * 0.5, sz + 7.8)
				if not blocked(pa, 2.0) and in_district.call(pa):
					_lamp(pa, Vector2(sx, pa.y))
				if not blocked(pb, 2.0) and in_district.call(pb):
					_lamp(pb, Vector2(pb.x, sz))
			# street trees and parked cars
			if r > 300.0:
				for k in 3:
					var p := Vector2(sx + rng.randf_range(-5, 5) + (8.5 if rng.randf() < 0.5 else -8.5), sz + rng.randf_range(0, PITCH))
					if in_district.call(p) and not blocked(p, 2.0) and (town or r > 520.0):
						_tree(p)
				if rng.randf() < 0.7:
					var p := Vector2(sx + (5.0 if rng.randf() < 0.5 else -5.0), sz + rng.randf_range(0, PITCH))
					if not blocked(p, 1.0):
						_car(Vector3(p.x, 0.72, p.y), 0.0)
	MeshKit.tag = MeshKit.TAG_AUTO


## A flat roof's furniture: a parapet round the edge, stair and lift housings, air handlers, old
## water tanks on legs, solar panels, masts with obstruction lights on the tall ones. Near the
## refuge, some roofs have people holding out on them: tents, a fire, SOS painted on the roof.
## A burnt-out block just gets the broken stumps of its top floors.
func _rooftop(c: Vector2, w: float, d: float, h: float, heat: float, r: float, burnt: bool, div: int) -> void:
	var pc := Color(heat, 1.0, 1.0, 1.0)
	MeshKit.tag = MeshKit.TAG_BURNT if burnt else MeshKit.TAG_CONCRETE
	for e: Array in [[Vector3(0, 0, -d * 0.5 + 0.2), Vector3(w, 1.1, 0.4)], [Vector3(0, 0, d * 0.5 - 0.2), Vector3(w, 1.1, 0.4)],
			[Vector3(-w * 0.5 + 0.2, 0, 0), Vector3(0.4, 1.1, d - 0.8)], [Vector3(w * 0.5 - 0.2, 0, 0), Vector3(0.4, 1.1, d - 0.8)]]:
		var off: Vector3 = e[0]
		MeshKit.box(st, Transform3D(Basis(), Vector3(c.x, h + 0.55, c.y) + off), e[1], pc)
	if burnt:
		for k in rng.randi_range(1, 3):
			var bw := rng.randf_range(w * 0.2, w * 0.5)
			var bh := rng.randf_range(2.0, 6.0)
			MeshKit.box(st, Transform3D(Basis(), Vector3(c.x + rng.randf_range(-w * 0.3, w * 0.3), h + bh * 0.5, c.y + rng.randf_range(-d * 0.3, d * 0.3))), Vector3(bw, bh, rng.randf_range(0.4, 2.0)), pc)
		return
	# stair and lift housing
	if h > 10.0:
		MeshKit.box(st, Transform3D(Basis(), Vector3(c.x + w * 0.22, h + 1.6, c.y - d * 0.2)), Vector3(3.8, 3.2, 3.4), pc)
	# a stepped crown on the tallest
	if h > 30.0 and rng.randf() < 0.5:
		MeshKit.box(st, Transform3D(Basis(), Vector3(c.x, h + 2.5, c.y)), Vector3(w * 0.55, 5.0, d * 0.55), pc)
	# air handlers
	MeshKit.tag = MeshKit.TAG_STEEL
	for k in rng.randi_range(0, 4):
		var ac := Vector3(c.x + rng.randf_range(-w * 0.32, w * 0.32), h + 0.6, c.y + rng.randf_range(-d * 0.32, d * 0.32))
		MeshKit.box(st, Transform3D(Basis(), ac), Vector3(2.2, 1.2, 2.2), Color(rng.randf_range(0.5, 0.78), 0.2, 0.4, 1.0))
	# an old timber water tank on legs, on the mid-rises
	if div == 2 and rng.randf() < 0.35:
		var tp := Vector3(c.x - w * 0.22, h, c.y + d * 0.2)
		MeshKit.tag = MeshKit.TAG_DARK
		for s: Vector2 in [Vector2(-1.4, -1.4), Vector2(1.4, -1.4), Vector2(1.4, 1.4), Vector2(-1.4, 1.4)]:
			MeshKit.box(st, Transform3D(Basis(), tp + Vector3(s.x, 1.5, s.y)), Vector3(0.25, 3.0, 0.25), Color(0.3, 0.2, 0.3, 1.0))
		MeshKit.tag = MeshKit.TAG_TIMBER
		MeshKit.cylinder(st, tp + Vector3.UP * 3.0, 2.0, 3.6, Color(0.33, 0.3, 0.5, 1.0), Color(0.3, 0.3, 0.5, 1.0), 10)
	# solar panels in rows
	if rng.randf() < 0.2 and w > 12.0:
		MeshKit.tag = MeshKit.TAG_SOLAR
		for k in 3:
			MeshKit.box(st, Transform3D(Basis(Vector3.RIGHT, -0.4), Vector3(c.x - w * 0.15, h + 0.7, c.y - d * 0.25 + k * 2.6)), Vector3(w * 0.45, 0.08, 1.8), Color(0.42, 0.9, 0.3, 1.0))
	# a mast with an obstruction light on the tall ones
	if h > 30.0 and rng.randf() < 0.45:
		MeshKit.tag = MeshKit.TAG_DARK
		MeshKit.box(st, Transform3D(Basis(), Vector3(c.x - w * 0.3, h + 7.0, c.y - d * 0.3)), Vector3(0.3, 14.0, 0.3), Color(0.24, 0.0, 0.0, 1.0))
		MeshKit.box(st, Transform3D(Basis(), Vector3(c.x - w * 0.3, h + 14.3, c.y - d * 0.3)), Vector3(0.6, 0.6, 0.6), Color(1.2, 0.5, 0.0, 1.0))
	# people holding out on the roof
	if r < 700.0 and rng.randf() < 0.07:
		MeshKit.tag = MeshKit.TAG_TENT
		for k in rng.randi_range(1, 3):
			MeshKit.box(st, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(c.x + rng.randf_range(-w * 0.25, w * 0.25), h + 1.1, c.y + rng.randf_range(-d * 0.25, d * 0.25))), Vector3(3.0, 2.2, 4.0), Color(rng.randf_range(0.5, 0.62), 0.0, 0.6, 1.0))
		var fp := Vector3(c.x + rng.randf_range(-w * 0.2, w * 0.2), h + 0.3, c.y + rng.randf_range(-d * 0.2, d * 0.2))
		MeshKit.tag = MeshKit.TAG_DARK
		MeshKit.box(st, Transform3D(Basis(), fp), Vector3(1.0, 0.6, 1.0), Color(1.45, 0.0, 0.0, 1.0))
		fires.append(fp + Vector3.UP * 0.5)
		if w > 16.0 and d > 10.0 and rng.randf() < 0.5:
			_sos(Vector3(c.x, h + 0.08, c.y), minf(w, 22.0))
	MeshKit.tag = MeshKit.TAG_AUTO


## SOS painted big on a roof: white strokes a couple of metres long.
func _sos(c: Vector3, span: float) -> void:
	MeshKit.tag = MeshKit.TAG_WHITE
	var col := Color(0.34, 0.0, 0.0, 1.0)
	var lw := span / 3.6
	var lh := lw * 1.3
	var s := 0.45
	for k in 3:
		var x := c.x + (float(k) - 1.0) * lw * 1.2
		var top := c.z - lh * 0.5
		if k == 1:
			# O: four sides
			MeshKit.box(st, Transform3D(Basis(), Vector3(x, c.y, top)), Vector3(lw, 0.1, s), col)
			MeshKit.box(st, Transform3D(Basis(), Vector3(x, c.y, top + lh)), Vector3(lw, 0.1, s), col)
			MeshKit.box(st, Transform3D(Basis(), Vector3(x - lw * 0.5, c.y, c.z)), Vector3(s, 0.1, lh), col)
			MeshKit.box(st, Transform3D(Basis(), Vector3(x + lw * 0.5, c.y, c.z)), Vector3(s, 0.1, lh), col)
		else:
			# S: three bars and two half-uprights
			for f: float in [0.0, 0.5, 1.0]:
				MeshKit.box(st, Transform3D(Basis(), Vector3(x, c.y, top + lh * f)), Vector3(lw, 0.1, s), col)
			MeshKit.box(st, Transform3D(Basis(), Vector3(x - lw * 0.5, c.y, top + lh * 0.25)), Vector3(s, 0.1, lh * 0.5), col)
			MeshKit.box(st, Transform3D(Basis(), Vector3(x + lw * 0.5, c.y, top + lh * 0.75)), Vector3(s, 0.1, lh * 0.5), col)


## What faces the street: a striped awning over the shopfronts, and balconies stacked up the
## residential mid-rises. `face` points from the building toward the street.
func _street_face(c: Vector2, w: float, d: float, h: float, face: Vector2, r: float, div: int) -> void:
	var along := Vector2(-face.y, face.x)
	var half := (w if absf(face.x) < 0.5 else d) * 0.5
	var depth := (d if absf(face.x) < 0.5 else w) * 0.5
	var yaw := -face.angle() + PI * 0.5
	if r < 900.0 and rng.randf() < 0.5:
		MeshKit.tag = MeshKit.TAG_AWNING
		var ap := c + face * (depth + 0.9)
		MeshKit.box(st, Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, 0.28), Vector3(ap.x, 3.6, ap.y)), Vector3(half * 1.4, 0.12, 1.9), Color(rng.randf_range(0.32, 0.38), 0.6, 0.3, 1.0))
	if div == 2 and rng.randf() < 0.45:
		MeshKit.tag = MeshKit.TAG_CONCRETE
		var bp := c + face * (depth + 0.65)
		var floors := int(h / 3.4)
		for f in range(1, floors):
			MeshKit.box(st, Transform3D(Basis(Vector3.UP, yaw), Vector3(bp.x, f * 3.4 + 0.5, bp.y)), Vector3(half * 1.1, 1.0, 1.3), Color(0.33, 0.6, 1.0, 1.0))
	MeshKit.tag = MeshKit.TAG_AUTO


## Rubble spilled round the foot of a burnt-out block.
func _rubble(c: Vector2, w: float, d: float) -> void:
	MeshKit.tag = MeshKit.TAG_CONCRETE
	for k in rng.randi_range(3, 7):
		var a := rng.randf() * TAU
		var p := c + Vector2(cos(a) * (w * 0.5 + rng.randf_range(0.5, 3.0)), sin(a) * (d * 0.5 + rng.randf_range(0.5, 3.0)))
		var s := rng.randf_range(1.0, 3.2)
		MeshKit.box(st, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).rotated(Vector3.RIGHT, rng.randf_range(-0.4, 0.4)), Vector3(p.x, s * 0.25, p.y)), Vector3(s, s * 0.55, s * 1.2), Color(rng.randf_range(0.28, 0.33), 1.0, 0.6, 1.0))
	MeshKit.tag = MeshKit.TAG_AUTO


## Streetlights down both sides of every avenue between r0 and r1, every `spacing` metres.
func _avenue_lights(r0: float, r1: float, spacing: float) -> void:
	for c in corridors:
		if int(c["type"]) != 0:
			continue
		var d := Vector2(cos(float(c["ang"])), sin(float(c["ang"])))
		var perp := Vector2(-d.y, d.x)
		var hw: float = c["hw"]
		var r := r0
		while r < r1:
			for s: float in [-1.0, 1.0]:
				var p := d * r + perp * (hw + 1.6) * s
				if not is_water(p) and not is_water(d * r) and not _reserved_at(p):
					_lamp(p, d * r)
			r += spacing


## Traffic that never made it out: lines of cars nose to tail in the lanes of the avenues, facing
## out of town, with the odd crash, bus or lorry in among them.
func _jams(per_avenue: int, r0: float, r1: float) -> void:
	for c in corridors:
		if int(c["type"]) != 0:
			continue
		var d := Vector2(cos(float(c["ang"])), sin(float(c["ang"])))
		var perp := Vector2(-d.y, d.x)
		var hw: float = c["hw"]
		var out_yaw := atan2(-d.x, -d.y)
		for k in per_avenue:
			var r := rng.randf_range(maxf(r0, float(c["rmin"]) + 30.0), r1)
			var lanes := [-0.62, -0.22, 0.22, 0.62]
			lanes.shuffle()
			for li in rng.randi_range(1, 3):
				var lat: float = float(lanes[li]) * hw
				var rr := r + rng.randf_range(-20.0, 20.0)
				for n in rng.randi_range(5, 16):
					var p := d * rr + perp * (lat + rng.randf_range(-0.6, 0.6))
					if is_water(p):
						break
					var big := rng.randf() < 0.1
					if big:
						_big_vehicle(Vector3(p.x, 0.0, p.y), out_yaw + rng.randf_range(-0.1, 0.1), rng.randf() < 0.5)
						rr -= 13.0
					else:
						var crash := rng.randf() < 0.08
						_car(Vector3(p.x, 0.72, p.y), out_yaw + (rng.randf_range(-0.9, 0.9) if crash else rng.randf_range(-0.12, 0.12)), 0.18)
						rr -= rng.randf_range(5.6, 7.2)
					if rng.randf() < 0.06:
						rr -= rng.randf_range(10.0, 30.0)


## What the survivors threw across the side streets round the refuge: concrete barriers,
## sandbags, a car dragged sideways, wire, and a fire in a barrel to keep warm by.
func _barricades(ring: float, limit: float) -> void:
	for k in range(-19, 20):
		var x := k * PITCH
		if absf(x) >= ring:
			continue
		var y := sqrt(ring * ring - x * x)
		for p: Vector2 in [Vector2(x, y), Vector2(x, -y), Vector2(y, x), Vector2(-y, x)]:
			if blocked(p, 8.0) or maxf(absf(p.x), absf(p.y)) > limit:
				continue
			# across the street: the street here runs along z for the first two, along x for the others
			var along_z := absf(p.x - x) < 0.01
			var across := Vector2(1, 0) if along_z else Vector2(0, 1)
			var yaw := 0.0 if along_z else PI * 0.5
			MeshKit.tag = MeshKit.TAG_CONCRETE
			for b in 3:
				var bp := p + across * (-4.4 + 4.4 * b) + Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3))
				MeshKit.box(st, Transform3D(Basis(Vector3.UP, yaw + rng.randf_range(-0.12, 0.12)), Vector3(bp.x, 0.48, bp.y)), Vector3(3.6, 0.95, 0.7), Color(0.32, 0.6, 0.8, 1.0))
			MeshKit.tag = MeshKit.TAG_HESCO
			var inward := -p.normalized() * 3.0
			for b in 2:
				var sp := p + inward + across * (-2.0 + 4.0 * b)
				MeshKit.box(st, Transform3D(Basis(Vector3.UP, yaw), Vector3(sp.x, 0.6, sp.y)), Vector3(3.0, 1.2, 1.0), Color(0.31, 0.6, 1.0, 1.0))
			MeshKit.tag = MeshKit.TAG_DARK
			MeshKit.box(st, Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, 1.25, p.y) - Vector3(inward.x, 0.0, inward.y) * 0.8), Vector3(13.0, 0.5, 0.5), Color(0.26, 0.0, 0.0, 1.0))
			if rng.randf() < 0.5:
				var cp := p - inward * 1.6 + across * rng.randf_range(-4.0, 4.0)
				_car(Vector3(cp.x, 0.72, cp.y), yaw + PI * 0.5 + rng.randf_range(-0.3, 0.3), 0.5)
			var fp := p + inward * 2.4 + across * rng.randf_range(-5.0, 5.0)
			MeshKit.box(st, Transform3D(Basis(), Vector3(fp.x, 0.45, fp.y)), Vector3(0.7, 0.9, 0.7), Color(1.45, 0.0, 0.0, 1.0))
			fires.append(Vector3(fp.x, 1.0, fp.y))
	MeshKit.tag = MeshKit.TAG_AUTO


## Abandoned checkpoints on a few avenues: sandbagged positions either side of the road, a guard
## hut, a Humvee, a tent, the boom raised for good, and the cars that didn't get through.
func _checkpoints(n: int, r: float) -> void:
	var avenues: Array = corridors.filter(func(c: Dictionary) -> bool: return int(c["type"]) == 0 and float(c["rmin"]) < r - 50.0)
	avenues.shuffle()
	for c in avenues.slice(0, n):
		var d := Vector2(cos(float(c["ang"])), sin(float(c["ang"])))
		var perp := Vector2(-d.y, d.x)
		var hw: float = c["hw"]
		var yaw := atan2(-d.x, -d.y)
		var base := d * r
		if is_water(base):
			continue
		for s: float in [-1.0, 1.0]:
			var side := base + perp * (hw + 4.5) * s
			MeshKit.tag = MeshKit.TAG_HESCO
			MeshKit.box(st, Transform3D(Basis(Vector3.UP, yaw), Vector3(side.x, 0.7, side.y) - Vector3(perp.x, 0.0, perp.y) * 2.0 * s), Vector3(1.0, 1.4, 6.0), Color(0.31, 0.6, 1.0, 1.0))
			MeshKit.box(st, Transform3D(Basis(Vector3.UP, yaw + PI * 0.5), Vector3(side.x, 0.7, side.y) + Vector3(d.x, 0.0, d.y) * 3.0), Vector3(1.0, 1.4, 4.0), Color(0.31, 0.6, 1.0, 1.0))
			MeshKit.tag = MeshKit.TAG_OLIVE
			var hut := side + perp * 5.0 * s
			MeshKit.box(st, Transform3D(Basis(Vector3.UP, yaw), Vector3(hut.x, 1.3, hut.y)), Vector3(3.0, 2.6, 3.0), Color(0.3, 0.4, 0.6, 0.6))
		# the boom, raised and left that way
		MeshKit.tag = MeshKit.TAG_AWNING
		var post := base + perp * (hw + 1.2)
		MeshKit.box(st, Transform3D(Basis(), Vector3(post.x, 4.5, post.y)), Vector3(0.25, 9.0, 0.25), Color(0.3, 0.4, 0.3, 1.0))
		# a Humvee and a tent
		var hv := base + perp * (hw + 9.0) - d * 8.0
		MeshKit.tag = MeshKit.TAG_OLIVE
		MeshKit.box(st, Transform3D(Basis(Vector3.UP, yaw), Vector3(hv.x, 1.0, hv.y)), Vector3(2.2, 1.9, 4.6), Color(0.29, 0.3, 0.4, 1.0))
		MeshKit.tag = MeshKit.TAG_TENT
		var tent := base - perp * (hw + 10.0) - d * 6.0
		MeshKit.box(st, Transform3D(Basis(Vector3.UP, yaw), Vector3(tent.x, 1.4, tent.y)), Vector3(5.0, 2.8, 7.0), Color(0.5, 0.0, 0.6, 1.0))
		# the queue that never got through, nose to tail outbound of the boom
		for k in 7:
			var p := base + d * (10.0 + k * 6.4) + perp * hw * (0.3 if k % 2 == 0 else -0.3)
			_car(Vector3(p.x, 0.72, p.y), yaw + PI + rng.randf_range(-0.15, 0.15), 0.3)
	MeshKit.tag = MeshKit.TAG_AUTO


## Power lines across the farmland on timber poles, along the field boundaries.
func _power_lines(xs: Array, inner: float, outer: float) -> void:
	for xv in xs:
		var x: float = xv
		var prev := Vector3.INF
		var z := -outer
		while z <= outer:
			var p := Vector2(x, z)
			var ok := maxf(absf(p.x), absf(p.y)) > inner and not blocked(p, 8.0) and not _reserved_at(p)
			if ok:
				MeshKit.tag = MeshKit.TAG_TIMBER
				MeshKit.box(st, Transform3D(Basis(), Vector3(p.x, 4.5, p.y)), Vector3(0.3, 9.0, 0.3), Color(0.24, 0.4, 0.5, 1.0))
				MeshKit.box(st, Transform3D(Basis(), Vector3(p.x, 8.6, p.y)), Vector3(2.4, 0.15, 0.15), Color(0.24, 0.4, 0.5, 1.0))
				var top := Vector3(p.x, 8.7, p.y)
				if prev != Vector3.INF:
					MeshKit.tag = MeshKit.TAG_DARK
					for wx: float in [-1.0, 0.0, 1.0]:
						var a := prev + Vector3(wx, 0.0, 0.0)
						var b := top + Vector3(wx, 0.0, 0.0)
						MeshKit.box(st, Transform3D(Basis(), (a + b) * 0.5 - Vector3(0, 0.3, 0)), Vector3(0.06, 0.06, a.distance_to(b)), Color(0.22, 0.0, 0.0, 1.0))
				prev = top
			else:
				prev = Vector3.INF
			z += 55.0
	MeshKit.tag = MeshKit.TAG_AUTO


func _reserved_at(p: Vector2) -> bool:
	for rr in reserved:
		if rr.has_point(p):
			return true
	return false


## Ring of ridged mountains around the valley, well outside the orbit.
func _mountains(r0: float, r1: float, hmax: float, heat_lo: float, heat_hi: float) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.0007
	noise.fractal_octaves = 5
	var rings := 26
	var segs := 150
	var grid: Array = []
	MeshKit.tag = MeshKit.TAG_ROCK
	for i in rings + 1:
		var r := lerpf(r0, r1, pow(float(i) / rings, 1.3))
		var row: Array[Vector3] = []
		for j in segs:
			var a := TAU * j / segs
			var x := cos(a) * r
			var z := sin(a) * r
			var env := smoothstep(r0, r0 + 1400.0, r)
			var n := noise.get_noise_2d(x, z) * 0.5 + 0.5
			var ridge := 1.0 - absf(noise.get_noise_2d(x * 0.45 + 977.0, z * 0.45))
			row.append(Vector3(x, env * hmax * (0.3 * n + 0.7 * ridge * ridge) - 3.0, z))
		grid.append(row)
	for i in rings:
		var ra: Array = grid[i]
		var rb: Array = grid[i + 1]
		for j in segs:
			var a: Vector3 = ra[j]
			var b: Vector3 = ra[(j + 1) % segs]
			var c: Vector3 = rb[(j + 1) % segs]
			var d: Vector3 = rb[j]
			var hk := clampf((a.y + c.y) * 0.5 / hmax, 0.0, 1.0)
			var col := Color(lerpf(heat_lo, heat_hi, hk) + rng.randf_range(-0.015, 0.015), 2.6, 1.0, 1.0)
			MeshKit.tri(st, a, b, c, col)
			MeshKit.tri(st, a, c, d, col)
	MeshKit.tag = MeshKit.TAG_AUTO


func _survivors(n: int, r_max: float, y := 0.3, wander := 4.0, center := Vector2.ZERO, half := Vector2.ZERO) -> void:
	for k in n:
		var p: Vector2
		if half != Vector2.ZERO:
			p = center + Vector2(rng.randf_range(-half.x, half.x), rng.randf_range(-half.y, half.y))
		else:
			p = center + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * r_max
		survivor_spots.append([Vector3(p.x, y, p.y), rng.randf_range(wander * 0.3, wander)])


# ================================================================ AO HOMEFIELD
func _city() -> void:
	for i in 8:
		_avenue(i * 45.0, 20.0 if i % 2 == 0 else 15.0)
	_wedge(112.5, 13.0)
	_wedge(292.5, 13.0)
	info.merge({"wall_r": 58.0, "arrive": Vector2(60.0, 84.0), "refuge_h": 24.0, "ground": 0, "attract": Vector3(260, 0, 30)}, true)

	_airfield(Vector2.from_angle(deg_to_rad(22.5)) * 4200.0, Vector2.from_angle(deg_to_rad(22.5)))
	_landmarks(4, 520.0, 1020.0, true)
	_district(func(p: Vector2) -> bool: return maxf(absf(p.x), absf(p.y)) < 1150.0, 150.0)
	_avenue_roads(55.0, 3300.0)
	var lot := Color(0.38, 0.0, 0.6, 1.0)
	MeshKit.tag = MeshKit.TAG_ASPHALT
	for i in 72:
		var a0 := TAU * i / 72
		var a1 := TAU * (i + 1) / 72
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var y := Vector3(0, 0.05, 0)
		MeshKit.quad(st, d0 * 56.0 + y, d1 * 56.0 + y, d1 * 135.0 + y, d0 * 135.0 + y, Vector3.UP, lot)
	_stadium()
	for ring: float in [72.0, 82.0, 96.0, 106.0, 120.0, 128.0]:
		var n := int(TAU * ring / 3.1)
		for k in n:
			if rng.randf() < 0.5:
				var a := TAU * k / n
				_car(Vector3(cos(a) * ring, 0.72, sin(a) * ring), -a + PI * 0.5 + rng.randf_range(-0.08, 0.08))
	_abandoned_cars(150.0, 1100.0, 34)
	_avenue_lights(80.0, 1150.0, 38.0)
	_jams(4, 220.0, 1100.0)
	_barricades(230.0, 1150.0)
	_checkpoints(3, 950.0)
	_power_lines([1600.0, -1600.0, 2400.0, -2400.0], 1250.0, 3000.0)
	# the two wedges are city parks: lawns under the trees
	MeshKit.tag = MeshKit.TAG_GRASS
	for c in corridors:
		if int(c["type"]) != 1:
			continue
		var a: float = c["ang"]
		var hf: float = c["half"]
		for k in 22:
			var r0 := 170.0 + k * 45.0
			var r1 := r0 + 45.0
			var e0 := Vector3(cos(a - hf), 0, sin(a - hf))
			var e1 := Vector3(cos(a + hf), 0, sin(a + hf))
			var y := Vector3(0, 0.065, 0)
			MeshKit.quad(st, e0 * r0 + y, e1 * r0 + y, e1 * r1 + y, e0 * r1 + y, Vector3.UP, Color(0.25, 0.0, 0.6, 1.0))
	MeshKit.tag = MeshKit.TAG_AUTO
	for k in 1500:
		var p := Vector2(rng.randf_range(-1150, 1150), rng.randf_range(-1150, 1150))
		if p.length() > 160.0 and in_wedge(p) and rng.randf() < 0.9:
			_tree(p)
	_farmsteads(70, 1350.0, 3000.0)
	for k in 1800:
		var p := Vector2(rng.randf_range(-3000, 3000), rng.randf_range(-3000, 3000))
		if maxf(absf(p.x), absf(p.y)) < 1200.0:
			continue
		if rng.randf() < 0.5:
			p.x = round(p.x / 160.0) * 160.0 + rng.randf_range(-3, 3)
		else:
			p.y = round(p.y / 160.0) * 160.0 + rng.randf_range(-3, 3)
		_tree(p)


## Farms out in the patchwork beyond town: a house, a red barn, a silo and a few trees.
func _farmsteads(n: int, r0: float, r1: float) -> void:
	var placed := 0
	var tries := 0
	while placed < n and tries < n * 30:
		tries += 1
		var p := Vector2(rng.randf_range(-r1, r1), rng.randf_range(-r1, r1))
		if maxf(absf(p.x), absf(p.y)) < r0 or blocked(p, 40.0) or _reserved_at(p):
			continue
		# set back from a field corner, so they line up with the hedgerows
		p = (p / 160.0).floor() * 160.0 + Vector2(rng.randf_range(20, 50), rng.randf_range(20, 50))
		if blocked(p, 40.0):
			continue
		var yaw := rng.randf_range(-0.1, 0.1) + (PI * 0.5 if rng.randf() < 0.5 else 0.0)
		var b := Basis(Vector3.UP, yaw)
		MeshKit.tag = MeshKit.TAG_BUILDING
		var hp := Vector3(p.x, 3.0, p.y)
		MeshKit.box(st, Transform3D(b, hp), Vector3(11.0, 6.0, 8.0), Color(rng.randf_range(0.3, 0.36), 1.0, 1.0, 0.5))
		_body(hp, Vector3(11.0, 6.0, 8.0), b)
		MeshKit.tag = MeshKit.TAG_RED
		var bp := Vector3(p.x, 4.5, p.y) + b * Vector3(18.0, 0, 6.0)
		MeshKit.box(st, Transform3D(b, bp), Vector3(12.0, 9.0, 20.0), Color(rng.randf_range(0.27, 0.31), 1.0, 1.0, 1.0))
		_body(bp, Vector3(12.0, 9.0, 20.0), b)
		MeshKit.tag = MeshKit.TAG_STEEL
		var sp := Vector3(p.x, 0.0, p.y) + b * Vector3(28.0, 0, -4.0)
		MeshKit.cylinder(st, sp, 3.0, 14.0, Color(0.27, 0.4, 0.6, 1.0), Color(0.25, 0.2, 0.5, 1.0), 12)
		MeshKit.tag = MeshKit.TAG_AUTO
		for k in rng.randi_range(2, 5):
			_tree(p + Vector2(rng.randf_range(-20, 12), rng.randf_range(-24, -12)))
		placed += 1


func _abandoned_cars(r0: float, r1: float, per: int) -> void:
	for c in corridors:
		if int(c["type"]) != 0:
			continue
		var a: float = c["ang"]
		var d := Vector2(cos(a), sin(a))
		var pp := Vector2(-d.y, d.x)
		for k in per:
			var p := d * rng.randf_range(maxf(r0, float(c["rmin"]) - 200.0), r1) + pp * rng.randf_range(-float(c["hw"]) + 3.0, float(c["hw"]) - 3.0)
			_car(Vector3(p.x, 0.72, p.y), rng.randf() * TAU)


func _stadium() -> void:
	var seg := 64
	var up := Vector3.UP
	var wall := Color(0.37, 1.0, 1.0, 0.55)
	var rim := Color(0.35, 0.4, 0.6, 1.0)
	var bowl := Color(0.45, 0.3, 1.0, 1.0)
	var field := Color(0.33, 0.0, 0.8, 1.0)
	var R := 52.0
	var F := 34.0
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var nm := ((d0 + d1) * 0.5).normalized()
		MeshKit.tag = MeshKit.TAG_CONCRETE
		MeshKit.quad(st, d0 * R, d1 * R, d1 * R + up * 21.0, d0 * R + up * 21.0, nm, wall)
		MeshKit.quad(st, d0 * R + up * 21.0, d1 * R + up * 21.0, d1 * 49.0 + up * 21.0, d0 * 49.0 + up * 21.0, up, rim)
		var bn := (-nm * 18.0 + up * 15.0).normalized()
		MeshKit.tag = MeshKit.TAG_SEATS
		MeshKit.quad(st, d0 * 49.0 + up * 21.0, d1 * 49.0 + up * 21.0, d1 * F + up * 3.0, d0 * F + up * 3.0, bn, bowl)
		MeshKit.tag = MeshKit.TAG_CONCRETE
		MeshKit.quad(st, d0 * F + up * 3.0, d1 * F + up * 3.0, d1 * F, d0 * F, -nm, wall)
		var y := up * 0.3
		MeshKit.tag = MeshKit.TAG_GRASS
		MeshKit.quad(st, y, y, d1 * F + y, d0 * F + y, up, field)
		if i % 2 == 0:
			var mid := TAU * (i + 1) / seg
			var dm := Vector3(cos(mid), 0, sin(mid))
			_body(dm * 43.0 + up * 10.5, Vector3(2.0 * R * sin(TAU / seg) + 0.5, 21.0, 18.0), Basis(Vector3.UP, -(mid + PI * 0.5)))
	MeshKit.tag = MeshKit.TAG_STEEL
	for k in 4:
		var a := PI * 0.25 + k * PI * 0.5
		var d := Vector3(cos(a), 0, sin(a))
		MeshKit.box(st, Transform3D(Basis(), d * 56.0 + up * 21.0), Vector3(1.6, 42.0, 1.6), Color(0.3, 0.0, 0.3, 1.0))
		MeshKit.box(st, Transform3D(Basis(Vector3.UP, -a), d * 56.0 + up * 43.0), Vector3(1.4, 3.0, 6.0), Color(1.15, 0.8, 0.0, 1.0))
	# pitch markings: halfway line and centre circle
	MeshKit.tag = MeshKit.TAG_WHITE
	_flat(Vector2.ZERO, Vector2(0.3, 30.0), Vector2(1, 0), 0.33, Color(0.33, 0.0, 0.8, 1.0))
	_camp(27.0, 22, 9, 7, 0.0)
	MeshKit.tag = MeshKit.TAG_CONTAINER
	for k in 30:
		var a := TAU * k / 30.0 + rng.randf_range(-0.02, 0.02)
		var d := Vector3(cos(a), 0, sin(a))
		MeshKit.box(st, Transform3D(Basis(Vector3.UP, -(a + PI * 0.5)), d * 58.5 + up * 1.3), Vector3(12.2, 2.6, 2.45), Color(rng.randf_range(0.22, 0.27), 0.6, 0.3, 1.0))
	MeshKit.tag = MeshKit.TAG_AUTO
	_survivors(260, 30.0, 0.3, 6.0)
	for k in 70:
		var a := rng.randf() * TAU
		var rr := rng.randf_range(37.0, 47.0)
		survivor_spots.append([Vector3(cos(a) * rr, 3.0 + (rr - F) / 15.0 * 18.0, sin(a) * rr), 0.4])
	for k in 24:
		var a := TAU * k / 24.0
		defender_spots.append(Vector3(cos(a) * 50.5, 21.2, sin(a) * 50.5))


## Refugee camp: tents, trucks with warm engines and cooking fires within radius r.
func _camp(r: float, tents: int, trucks: int, fires: int, y: float, center := Vector2.ZERO) -> void:
	var prev := MeshKit.tag
	MeshKit.tag = MeshKit.TAG_TENT
	for k in tents:
		var p := center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(3.0, r)
		MeshKit.box(st, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(p.x, y + 1.3, p.y)), Vector3(4.0, 2.6, 6.0), Color(rng.randf_range(0.5, 0.64), 0.0, 0.6, 1.0))
	MeshKit.tag = MeshKit.TAG_OLIVE
	for k in trucks:
		var p := center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(5.0, r)
		var b := Basis(Vector3.UP, rng.randf() * TAU)
		MeshKit.box(st, Transform3D(b, Vector3(p.x, y + 1.4, p.y)), Vector3(2.5, 2.8, 7.5), Color(0.3, 0.2, 0.4, 1.0))
		MeshKit.box(st, Transform3D(b, Vector3(p.x, y + 1.1, p.y) + b * Vector3(0, 0, -3.3)), Vector3(2.2, 1.2, 1.0), Color(0.8, 0.0, 0.0, 1.0))
	for k in fires:
		var p := center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(2.0, r * 0.9)
		MeshKit.box(st, Transform3D(Basis(), Vector3(p.x, y + 0.3, p.y)), Vector3(1.2, 0.6, 1.2), Color(1.5, 0.0, 0.0, 1.0))
		self.fires.append(Vector3(p.x, y + 0.9, p.y))
	MeshKit.tag = prev


# ================================================================ AO ANVIL
func _desert() -> void:
	_avenue(0.0, 14.0)
	_avenue(180.0, 14.0)
	for a: float in [50.0, 125.0, 235.0, 305.0]:
		_wedge(a, 18.0)
	info.merge({"wall_r": 82.0, "arrive": Vector2(88.0, 110.0), "refuge_h": 14.0, "ground": 1,
		"attract": Vector3(-220, 0, 260), "haze_heat": 0.24, "haze_dist": 15000.0,
		"sun": Vector3(-0.3, 0.85, 0.42), "sky": Vector3(0.8, 0.76, 0.68), "tv_fog": 9000.0}, true)

	_airfield(Vector2(0.0, 2400.0), Vector2(0.0, 1.0))
	_landmarks(3, 600.0, 1400.0, false)
	# the highway and its wrecks
	_avenue_roads(84.0, 6000.0, 0.36)
	_abandoned_cars(150.0, 1600.0, 40)
	_avenue_lights(110.0, 700.0, 60.0)
	_jams(3, 300.0, 1600.0)
	_checkpoints(1, 1200.0)

	# FOB Anvil: an octagon of HESCO bastions with guard towers at every corner
	var rv := 75.0 / cos(PI / 8.0)
	var hesco := Color(0.33, 0.8, 1.0, 1.0)
	MeshKit.tag = MeshKit.TAG_DIRT
	_flat(Vector2.ZERO, Vector2(rv * 0.92, rv * 0.92), Vector2(1, 0), 0.03, Color(0.3, 0.0, 0.6, 1.0))
	for k in 8:
		var a0 := PI / 8.0 + k * PI / 4.0
		var a1 := a0 + PI / 4.0
		var v0 := Vector2(cos(a0), sin(a0)) * rv
		var v1 := Vector2(cos(a1), sin(a1)) * rv
		MeshKit.tag = MeshKit.TAG_HESCO
		_wall(v0, v1, 2.4, 1.4, hesco)
		_wall(v0 * 0.985, v1 * 0.985, 3.6, 0.7, Color(0.31, 0.6, 1.0, 1.0), false)
		MeshKit.tag = MeshKit.TAG_TIMBER
		_solid(Vector3(v0.x, 4.5, v0.y), Vector3(4.0, 9.0, 4.0), Color(0.3, 0.4, 0.8, 1.0))
		MeshKit.tag = MeshKit.TAG_OLIVE
		MeshKit.box(st, Transform3D(Basis(), Vector3(v0.x, 9.8, v0.y)), Vector3(4.6, 2.2, 4.6), Color(0.55, 0.2, 0.5, 1.0))
		defender_spots.append(Vector3(v0.x * 0.98, 10.0, v0.y * 0.98))
		var mid := (v0 + v1) * 0.5
		defender_spots.append(Vector3(mid.x * 0.97, 2.6, mid.y * 0.97))
	# inside the wire
	MeshKit.tag = MeshKit.TAG_TENT
	for row in 3:
		for k in 6:
			_solid(Vector3(-36.0 + k * 11.0, 1.8, -40.0 + row * 9.0), Vector3(9.0, 3.6, 5.0), Color(rng.randf_range(0.5, 0.6), 0.0, 0.6, 1.0))
	MeshKit.tag = MeshKit.TAG_CONCRETE
	_solid(Vector3(20, 3.0, 10), Vector3(22.0, 6.0, 12.0), Color(0.42, 1.0, 1.0, 0.4))
	MeshKit.tag = MeshKit.TAG_STEEL
	_solid(Vector3(-15, 7.0, 25), Vector3(4.0, 14.0, 4.0), Color(0.33, 0.4, 0.6, 1.0))
	MeshKit.cylinder(st, Vector3(-15, 14, 25), 4.0, 5.0, Color(0.35, 0.4, 0.6, 1.0), Color(0.3, 0.2, 0.6, 1.0))
	MeshKit.tag = MeshKit.TAG_OLIVE
	for k in 8:
		var p := Vector2(rng.randf_range(-30, 50), rng.randf_range(30, 55))
		var b := Basis(Vector3.UP, rng.randf() * TAU)
		MeshKit.box(st, Transform3D(b, Vector3(p.x, 1.6, p.y)), Vector3(3.0, 3.2, 7.0), Color(0.29, 0.3, 0.4, 1.0))
		MeshKit.box(st, Transform3D(b, Vector3(p.x, 1.4, p.y) + b * Vector3(0, 0, -3.0)), Vector3(2.4, 1.4, 1.0), Color(0.8, 0.0, 0.0, 1.0))
	# helipad with a parked Black Hawk
	MeshKit.tag = MeshKit.TAG_CONCRETE
	_flat(Vector2(-45, -5), Vector2(13, 13), Vector2(1, 0), 0.07, Color(0.38, 0.0, 0.5, 1.0))
	_helicopter(Vector2(-45, -5), 0.0)
	# generators and the burn pit
	MeshKit.tag = MeshKit.TAG_OLIVE
	for k in 3:
		_solid(Vector3(45.0, 1.2, -20.0 + k * 6.0), Vector3(2.5, 2.4, 4.5), Color(0.85, 0.2, 0.2, 1.0))
	MeshKit.box(st, Transform3D(Basis(), Vector3(48, 0.3, -48)), Vector3(7.0, 0.6, 7.0), Color(1.6, 0.0, 0.0, 1.0))
	MeshKit.tag = MeshKit.TAG_AUTO
	_survivors(220, 58.0, 0.0, 5.0)

	# a mud-brick village in the gaps between the approach wedges
	var placed := 0
	var tries := 0
	while placed < 70 and tries < 2000:
		tries += 1
		var p := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(260.0, 1150.0)
		var size := rng.randf_range(18.0, 34.0)
		if blocked(p, size) or blocked(p + Vector2(size, size) * 0.5, 5.0) or blocked(p - Vector2(size, size) * 0.5, 5.0) or _reserved_at(p):
			continue
		_compound(p, size)
		placed += 1
		if rng.randf() < 0.5:
			_tree(p + Vector2(size * 0.8, rng.randf_range(-size, size)), 0.6)
	# boulders that hold the day's heat
	MeshKit.tag = MeshKit.TAG_ROCK
	for k in 900:
		var p := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(130.0, 2600.0)
		if _reserved_at(p):
			continue
		var s := rng.randf_range(1.0, 4.5)
		MeshKit.box(st, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).rotated(Vector3.RIGHT, rng.randf_range(-0.3, 0.3)), Vector3(p.x, s * 0.3, p.y)), Vector3(s, s * 0.7, s * 1.2), Color(rng.randf_range(0.28, 0.35), 1.0, 0.6, 1.0))
	MeshKit.tag = MeshKit.TAG_AUTO
	for k in 260:
		_tree(Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(200.0, 2500.0), 0.35)
	_mountains(3300.0, 8000.0, 950.0, 0.29, 0.4)


## A walled qalat compound: courtyard wall and rooms of sun-baked mud brick.
func _compound(c: Vector2, size: float) -> void:
	MeshKit.tag = MeshKit.TAG_MUD
	var yaw := rng.randf() * TAU
	var b := Basis(Vector3.UP, yaw)
	var h := size * 0.5
	var mud := Color(rng.randf_range(0.33, 0.37), 1.0, 1.0, 1.0)
	# swept-earth courtyard
	MeshKit.tag = MeshKit.TAG_DIRT
	MeshKit.box(st, Transform3D(b, Vector3(c.x, 0.04, c.y)), Vector3(size, 0.08, size), Color(mud.r - 0.02, 0.0, 0.6, 1.0))
	MeshKit.tag = MeshKit.TAG_MUD
	for side in [[Vector3(0, 0, -h), size], [Vector3(0, 0, h), size], [Vector3(-h, 0, 0), size], [Vector3(h, 0, 0), size]]:
		var off: Vector3 = side[0]
		var along_x := absf(off.z) > 0.0
		var sz := Vector3(size, 3.2, 0.7) if along_x else Vector3(0.7, 3.2, size)
		MeshKit.box(st, Transform3D(b, Vector3(c.x, 1.6, c.y) + b * off), sz, mud)
	for k in rng.randi_range(1, 3):
		var off := Vector3(rng.randf_range(-h + 4, h - 4), 0, -h + 3.0) if k % 2 == 0 else Vector3(-h + 3.0, 0, rng.randf_range(-h + 4, h - 4))
		var rs := Vector3(rng.randf_range(5, 9), rng.randf_range(3.5, 5.0), 5.0)
		var center := Vector3(c.x, rs.y * 0.5, c.y) + b * off
		MeshKit.box(st, Transform3D(b, center), rs, Color(rng.randf_range(0.36, 0.41), 1.0, 1.0, 0.6))
		_body(center, rs, b)
	MeshKit.tag = MeshKit.TAG_AUTO


# ================================================================ AO TRIDENT
func _port() -> void:
	for a: float in [200.0, 235.0, 305.0, 340.0]:
		_avenue(a, 16.0)
	_avenue(270.0, 22.0)
	_wedge(252.5, 6.0)
	_wedge(287.5, 6.0)
	info.merge({"wall_r": 100.0, "arrive": Vector2(104.0, 124.0), "refuge_h": 30.0, "ground": 2,
		"attract": Vector3(-60, 0, -330)}, true)

	# quay apron along the waterline
	MeshKit.tag = MeshKit.TAG_CONCRETE
	_flat(Vector2(0, 5), Vector2(1600, 35), Vector2(1, 0), 0.05, Color(0.37, 0.0, 0.5, 1.0))
	# the container yard is paved too
	MeshKit.tag = MeshKit.TAG_ASPHALT
	_flat(Vector2(0, -300), Vector2(830, 265), Vector2(1, 0), 0.04, Color(0.35, 0.0, 0.5, 1.0))
	_airfield(Vector2(2500.0, -150.0), Vector2(1.0, 0.0))
	_landmarks(3, 650.0, 1350.0, true)
	_district(func(p: Vector2) -> bool: return p.y < -540.0 and p.length() < 1500.0, 0.0)
	_avenue_roads(100.0, 3300.0)
	_abandoned_cars(150.0, 1300.0, 26)
	_avenue_lights(110.0, 1500.0, 38.0)
	_jams(3, 300.0, 1300.0)

	# the hospital ship alongside the quay: white hull, red crosses
	MeshKit.tag = MeshKit.TAG_WHITE
	_solid(Vector3(0, 6.5, 78), Vector3(250.0, 13.0, 32.0), Color(0.33, 1.0, 0.6, 1.0))
	_solid(Vector3(-92, 23.0, 78), Vector3(30.0, 20.0, 28.0), Color(0.4, 1.0, 1.0, 0.4))
	MeshKit.box(st, Transform3D(Basis(), Vector3(-75, 30.0, 78)), Vector3(4.0, 3.0, 34.0), Color(0.38, 0.4, 1.0, 1.0))
	MeshKit.tag = MeshKit.TAG_RED
	MeshKit.box(st, Transform3D(Basis(), Vector3(-92, 38.0, 78)), Vector3(8.0, 10.0, 8.0), Color(0.95, 0.0, 0.0, 1.0))
	for side: float in [-1.0, 1.0]:
		for x: float in [-30.0, 60.0]:
			MeshKit.box(st, Transform3D(Basis(), Vector3(x, 7.0, 78 + 16.1 * side)), Vector3(10.0, 2.6, 0.2), Color(0.33, 1.0, 0.6, 1.0))
			MeshKit.box(st, Transform3D(Basis(), Vector3(x, 7.0, 78 + 16.1 * side)), Vector3(2.6, 10.0, 0.2), Color(0.33, 1.0, 0.6, 1.0))
	MeshKit.tag = MeshKit.TAG_DARK
	_flat(Vector2(102, 78), Vector2(13, 13), Vector2(1, 0), 13.05, Color(0.36, 0.0, 0.5, 1.0))
	MeshKit.tag = MeshKit.TAG_CONTAINER
	for k in 6:
		MeshKit.box(st, Transform3D(Basis(), Vector3(-40.0 + k * 22.0, 13.8, 78)), Vector3(14.0, 1.6, 18.0), Color(rng.randf_range(0.28, 0.32), 0.2, 0.5, 1.0))
	MeshKit.tag = MeshKit.TAG_AUTO
	_survivors(180, 0.0, 13.2, 3.0, Vector2(15, 78), Vector2(85, 12))
	_survivors(90, 0.0, 0.1, 5.0, Vector2(0, 22), Vector2(110, 12))

	# terminal building and a container barricade around the landward side
	MeshKit.tag = MeshKit.TAG_GLASS
	_solid(Vector3(0, 8.0, -42), Vector3(70.0, 16.0, 26.0), Color(0.4, 1.0, 1.0, 0.4))
	MeshKit.tag = MeshKit.TAG_CONTAINER
	for k in 34:
		var a := deg_to_rad(184.0 + k * 5.2)
		var d := Vector3(cos(a), 0, sin(a))
		_solid(d * 98.0 + Vector3.UP * 1.3, Vector3(12.2, 2.6, 2.45), Color(rng.randf_range(0.22, 0.27), 0.6, 0.3, 1.0), -(a + PI * 0.5))
		if k % 2 == 0:
			defender_spots.append(d * 97.0 + Vector3.UP * 2.8)
	for k in 6:
		defender_spots.append(Vector3(-30.0 + k * 12.0, 16.4, -45.0))

	# gantry cranes along the quay
	for x: float in [-380.0, -260.0, -150.0, 150.0, 260.0, 380.0]:
		var steel := Color(0.27, 0.4, 0.3, 1.0)
		MeshKit.tag = MeshKit.TAG_YELLOW
		for lx: float in [-10.0, 10.0]:
			for lz: float in [15.0, 38.0]:
				_solid(Vector3(x + lx, 21.0, lz), Vector3(1.6, 42.0, 1.6), steel)
		MeshKit.box(st, Transform3D(Basis(), Vector3(x, 43.0, 45.0)), Vector3(22.0, 2.5, 100.0), steel)
		MeshKit.tag = MeshKit.TAG_WHITE
		MeshKit.box(st, Transform3D(Basis(), Vector3(x, 46.0, 30.0)), Vector3(8.0, 4.0, 10.0), Color(0.5, 0.3, 0.6, 1.0))
	MeshKit.tag = MeshKit.TAG_AUTO

	# container stacks in yard blocks between the avenues
	MeshKit.tag = MeshKit.TAG_CONTAINER
	for gx in range(-6, 6):
		for gz in range(0, 9):
			var bx := gx * 138.0 + 6.0
			var bz := -130.0 - gz * 40.0
			var block_center := Vector2(bx + 63.0, bz - 8.0)
			if blocked(block_center, 70.0) or block_center.length() < 130.0:
				continue
			var tallest := 0.0
			for row in 6:
				for bay in 10:
					if rng.randf() > 0.85:
						continue
					var p := Vector2(bx + bay * 12.8 + 6.1, bz - row * 2.8)
					if blocked(p, 3.0):
						continue
					var hgt := rng.randi_range(1, 5)
					tallest = maxf(tallest, hgt * 2.6)
					var heat := rng.randf_range(0.2, 0.31)
					if rng.randf() < 0.08:
						heat = rng.randf_range(0.45, 0.55)
					MeshKit.box(st, Transform3D(Basis(), Vector3(p.x, hgt * 1.3, p.y)), Vector3(12.2, hgt * 2.6, 2.44), Color(heat, 0.5, 0.3, 1.0))
			if tallest > 0.0:
				_body(Vector3(bx + 63.0, 3.9, bz - 7.0), Vector3(128.0, 7.8, 17.0))
	# fuel tank farm to the east
	MeshKit.tag = MeshKit.TAG_WHITE
	for k in 8:
		var c := Vector2(820.0 + (k % 4) * 45.0, -90.0 - int(k / 4) * 50.0)
		if blocked(c, 25.0):
			continue
		MeshKit.cylinder(st, Vector3(c.x, 0, c.y), 17.0, 14.0, Color(0.37, 1.0, 0.6, 1.0), Color(0.31, 0.3, 0.5, 1.0))
		_body(Vector3(c.x, 7.0, c.y), Vector3(30.0, 14.0, 30.0))
	# a breakwater out to sea, and its light
	MeshKit.tag = MeshKit.TAG_STONE
	MeshKit.box(st, Transform3D(Basis(), Vector3(-200, 1.5, 520)), Vector3(1400.0, 3.0, 12.0), Color(0.31, 0.5, 1.0, 1.0))
	MeshKit.tag = MeshKit.TAG_RED
	MeshKit.box(st, Transform3D(Basis(), Vector3(500, 10.0, 520)), Vector3(5.0, 20.0, 5.0), Color(0.45, 0.2, 0.5, 1.0))
	MeshKit.tag = MeshKit.TAG_AUTO
	for k in 400:
		var p := Vector2(rng.randf_range(-1500, 1500), rng.randf_range(-1500, -560))
		if not blocked(p, 3.0) and rng.randf() < 0.4:
			_tree(p)


# ================================================================ AO GALLOWS
func _river() -> void:
	var bridges := [[90.0, 10.0], [250.0, 10.0], [290.0, 10.0], [25.0, 8.0]]
	for b in bridges:
		var c := _avenue(float(b[0]), float(b[1]))
		var d := Vector2(cos(float(c["ang"])), sin(float(c["ang"])))
		var r_isl := 0.0
		while not is_water(d * r_isl) and r_isl < 400.0:
			r_isl += 2.0
		var r_land := r_isl
		while is_water(d * r_land) and r_land < 1500.0:
			r_land += 2.0
		c["rmin"] = r_land + 25.0
		c["bridge"] = Vector2(r_isl - 6.0, r_land + 12.0)
	info.merge({"wall_r": 100.0, "arrive": Vector2(108.0, 126.0), "refuge_h": 20.0, "ground": 3,
		"attract": Vector3(-30, 0, -360)}, true)

	# Blackwater Prison
	var wall := Color(0.35, 0.8, 1.0, 1.0)
	var hx := 85.0
	var hz := 60.0
	var corners := [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(hx, hz), Vector2(-hx, hz)]
	MeshKit.tag = MeshKit.TAG_GRASS
	_flat(Vector2.ZERO, Vector2(225, 155), Vector2(1, 0), 0.02, Color(0.24, 0.0, 0.6, 1.0))
	MeshKit.tag = MeshKit.TAG_CONCRETE
	_flat(Vector2.ZERO, Vector2(hx, hz), Vector2(1, 0), 0.03, Color(0.32, 0.0, 0.6, 1.0))
	for k in 4:
		var a: Vector2 = corners[k]
		var b: Vector2 = corners[(k + 1) % 4]
		_wall(a, b, 7.0, 1.4, wall)
		for t: float in [0.0, 0.5]:
			var p := a.lerp(b, t)
			_solid(Vector3(p.x, 7.0, p.y), Vector3(5.0, 14.0, 5.0), Color(0.33, 0.4, 0.8, 1.0))
			MeshKit.box(st, Transform3D(Basis(), Vector3(p.x, 15.0, p.y)), Vector3(6.0, 3.0, 6.0), Color(0.58, 0.2, 0.5, 1.0))
			defender_spots.append(Vector3(p.x * 0.97, 16.6, p.y * 0.97))
		for t: float in [0.25, 0.75]:
			var p := a.lerp(b, t)
			defender_spots.append(Vector3(p.x * 0.98, 7.3, p.y * 0.98))
	for k in 3:
		_solid(Vector3(-45.0 + k * 30.0, 7.0, -28.0), Vector3(14.0, 14.0, 52.0) if k != 1 else Vector3(14.0, 18.0, 52.0), Color(0.39, 1.0, 1.0, 0.4))
	MeshKit.tag = MeshKit.TAG_BUILDING
	_solid(Vector3(45, 6.0, 30), Vector3(40.0, 12.0, 20.0), Color(0.4, 1.0, 1.0, 0.45))
	MeshKit.tag = MeshKit.TAG_STEEL
	_solid(Vector3(60, 9.0, -35), Vector3(4.0, 18.0, 4.0), Color(0.33, 0.3, 0.6, 1.0))
	MeshKit.cylinder(st, Vector3(60, 18, -35), 5.0, 6.0, Color(0.34, 0.4, 0.6, 1.0), Color(0.3, 0.2, 0.6, 1.0))
	MeshKit.tag = MeshKit.TAG_DARK
	_wall(Vector2(-78, -54), Vector2(78, -54), 4.0, 0.3, Color(0.26, 0.2, 0.3, 1.0), false)
	_wall(Vector2(-78, 54), Vector2(78, 54), 4.0, 0.3, Color(0.26, 0.2, 0.3, 1.0), false)
	MeshKit.tag = MeshKit.TAG_ASPHALT
	_flat(Vector2(-20, 28), Vector2(42, 20), Vector2(1, 0), 0.06, Color(0.36, 0.0, 0.6, 1.0))
	_camp(18.0, 10, 3, 4, 0.0, Vector2(-20, 28))
	MeshKit.tag = MeshKit.TAG_AUTO
	_survivors(220, 0.0, 0.1, 4.0, Vector2(-20, 28), Vector2(40, 18))
	_survivors(60, 0.0, 0.1, 3.0, Vector2(0, -8), Vector2(70, 8))
	for k in 160:
		var p := Vector2(rng.randf_range(-225, 225), rng.randf_range(-155, 155))
		if not is_water(p) and (absf(p.x) > hx + 12.0 or absf(p.y) > hz + 12.0) and not blocked(p, 4.0):
			_tree(p, 0.8)

	# the bridges
	for c in corridors:
		var a: float = c["ang"]
		var d := Vector2(cos(a), sin(a))
		var span: Vector2 = c["bridge"]
		var hw: float = c["hw"]
		var mid := d * (span.x + span.y) * 0.5
		MeshKit.tag = MeshKit.TAG_ASPHALT
		_flat(mid, Vector2((span.y - span.x) * 0.5, hw + 1.0), d, 0.12, Color(0.36, 0.0, 0.6, 1.0))
		var side := Vector2(-d.y, d.x)
		MeshKit.tag = MeshKit.TAG_CONCRETE
		for s: float in [-1.0, 1.0]:
			var a0 := d * span.x + side * (hw + 0.8) * s
			var a1 := d * span.y + side * (hw + 0.8) * s
			_wall(a0, a1, 1.3, 0.35, Color(0.3, 0.3, 0.3, 1.0), false)
		var length := span.y - span.x
		MeshKit.tag = MeshKit.TAG_STEEL if hw < 9.0 else MeshKit.TAG_CONCRETE
		if hw < 9.0:
			# rail bridge: steel truss
			var n := int(length / 14.0)
			for k in n:
				var p := d * (span.x + (k + 0.5) * length / n)
				for s: float in [-1.0, 1.0]:
					var q := p + side * (hw + 0.5) * s
					MeshKit.box(st, Transform3D(Basis(Vector3.UP, -d.angle()).rotated(Vector3(-d.y, 0, d.x).normalized(), 0.7 if k % 2 == 0 else -0.7), Vector3(q.x, 6.0, q.y)), Vector3(17.0, 0.6, 0.6), Color(0.26, 0.3, 0.3, 1.0))
				MeshKit.box(st, Transform3D(Basis(Vector3.UP, -d.angle()), Vector3(p.x, 11.5, p.y)), Vector3(length / n, 0.8, hw * 2.0 + 1.0), Color(0.25, 0.3, 0.3, 1.0))
		else:
			# road bridges: two towers with cable stays
			for f: float in [0.3, 0.7]:
				var p := d * lerpf(span.x, span.y, f)
				for s: float in [-1.0, 1.0]:
					var q := p + side * (hw + 2.0) * s
					MeshKit.box(st, Transform3D(Basis(), Vector3(q.x, 22.0, q.y)), Vector3(2.5, 44.0, 2.5), Color(0.3, 0.4, 0.5, 1.0))
					for k in 4:
						for dirs: float in [-1.0, 1.0]:
							var anchor := p + d * dirs * (12.0 + k * 14.0) + side * (hw + 2.0) * s
							var top := Vector3(q.x, 42.0 - k * 2.0, q.y)
							var bot := Vector3(anchor.x, 1.0, anchor.y)
							var cm := (top + bot) * 0.5
							var lb := Basis.looking_at(top - bot, Vector3.UP)
							MeshKit.tag = MeshKit.TAG_DARK
							MeshKit.box(st, Transform3D(lb, cm), Vector3(0.25, 0.25, top.distance_to(bot)), Color(0.24, 0.0, 0.0, 1.0))
							MeshKit.tag = MeshKit.TAG_CONCRETE
		MeshKit.tag = MeshKit.TAG_AUTO
		for k in 4:
			var p := d * rng.randf_range(span.x + 10.0, span.y - 10.0) + side * rng.randf_range(-hw + 2.0, hw - 2.0)
			_car(Vector3(p.x, 0.72, p.y), rng.randf() * TAU)

	# towns on both banks
	_airfield(Vector2(-3200.0, -900.0), Vector2(1.0, 0.0))
	_landmarks(3, 600.0, 1300.0, true)
	_district(func(p: Vector2) -> bool: return p.length() < 1450.0 and absf(p.y - 25.0 * sin(p.x * 0.004)) > 300.0, 0.0, true)
	_avenue_roads(150.0, 3300.0)
	_abandoned_cars(300.0, 1300.0, 20)
	_avenue_lights(300.0, 1450.0, 40.0)
	_jams(2, 400.0, 1300.0)
	_checkpoints(2, 900.0)
	for k in 1400:
		var p := Vector2(rng.randf_range(-2200, 2200), 0.0)
		var m := 25.0 * sin(p.x * 0.004)
		p.y = m + (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(276.0, 300.0)
		if not blocked(p, 3.0):
			_tree(p)


# ================================================================ AO FROSTBITE
func _arctic() -> void:
	_avenue(20.0, 25.0)
	_avenue(175.0, 10.0)
	for a: float in [75.0, 135.0, 215.0, 268.0, 325.0]:
		_wedge(a, 15.0)
	info.merge({"wall_r": 72.0, "arrive": Vector2(78.0, 98.0), "refuge_h": 18.0, "ground": 4,
		"attract": Vector3(-150, 0, -280), "haze_heat": 0.12, "haze_dist": 6500.0,
		"sun": Vector3(-0.6, 0.35, 0.72), "sky": Vector3(0.82, 0.87, 0.94), "tv_fog": 5000.0}, true)

	_avenue_roads(70.0, 3300.0, 0.13)
	_airfield(Vector2.from_angle(deg_to_rad(40.0)) * 2500.0, Vector2.from_angle(deg_to_rad(40.0)))
	_landmarks(3, 500.0, 1400.0, false)
	# skiway edge lights
	MeshKit.tag = MeshKit.TAG_WHITE
	var skd := Vector2(cos(deg_to_rad(20.0)), sin(deg_to_rad(20.0)))
	var skp := Vector2(-skd.y, skd.x)
	for k in 24:
		for s: float in [-1.0, 1.0]:
			var lp := skd * (110.0 + k * 60.0) + skp * 27.0 * s
			MeshKit.box(st, Transform3D(Basis(), Vector3(lp.x, 0.4, lp.y)), Vector3(0.5, 0.8, 0.5), Color(1.12, 0.8, 0.0, 1.0))
	MeshKit.tag = MeshKit.TAG_AUTO

	# Kepler Station: red modules on stilts around a white hub
	var stilt := Color(0.15, 0.0, 0.0, 1.0)
	MeshKit.tag = MeshKit.TAG_WHITE
	_solid(Vector3(0, 7.0, 0), Vector3(20.0, 7.0, 20.0), Color(0.46, 1.0, 1.0, 0.4))
	for k in 5:
		var a := TAU * k / 5.0 + 0.3
		var d := Vector2(cos(a), sin(a))
		var c := d * 30.0
		MeshKit.tag = MeshKit.TAG_RED
		_solid(Vector3(c.x, 6.0, c.y), Vector3(28.0, 5.0, 9.0), Color(0.43, 1.0, 1.0, 0.4), -a)
		MeshKit.tag = MeshKit.TAG_WHITE
		MeshKit.box(st, Transform3D(Basis(Vector3.UP, -a), Vector3(d.x * 12.0, 6.0, d.y * 12.0)), Vector3(8.0, 3.0, 3.0), Color(0.4, 0.5, 1.0, 1.0))
		MeshKit.tag = MeshKit.TAG_DARK
		for s: float in [-10.0, 0.0, 10.0]:
			var q := c + d * s
			MeshKit.box(st, Transform3D(Basis(), Vector3(q.x, 1.8, q.y)), Vector3(0.6, 3.6, 0.6), stilt)
	MeshKit.tag = MeshKit.TAG_WHITE
	MeshKit.box(st, Transform3D(Basis(), Vector3(48, 6.0, -38)), Vector3(4.0, 12.0, 4.0), Color(0.18, 0.2, 0.6, 1.0))
	MeshKit.dome(st, Vector3(48, 12.0, -38), 8.0, Color(0.24, 0.4, 0.8, 1.0))
	MeshKit.tag = MeshKit.TAG_OLIVE
	_solid(Vector3(-40, 3.0, 35), Vector3(12.0, 6.0, 10.0), Color(0.75, 0.3, 0.5, 1.0))
	MeshKit.box(st, Transform3D(Basis(), Vector3(-36, 9.0, 35)), Vector3(1.2, 6.0, 1.2), Color(1.05, 0.0, 0.0, 1.0))
	MeshKit.tag = MeshKit.TAG_DARK
	MeshKit.box(st, Transform3D(Basis(), Vector3(-10, 30.0, 52)), Vector3(1.0, 60.0, 1.0), Color(0.14, 0.0, 0.0, 1.0))
	MeshKit.tag = MeshKit.TAG_YELLOW
	for k in 6:
		MeshKit.box(st, Transform3D(Basis(), Vector3(-55.0 + (k % 3) * 12.0, 0.6, -40.0 - int(k / 3) * 9.0)), Vector3(10.0, 1.2, 6.0), Color(0.16, 0.0, 0.3, 1.0))
	MeshKit.tag = MeshKit.TAG_WHITE
	for k in 3:
		var a := TAU * k / 3.0 + 1.0
		var p := Vector2(cos(a), sin(a)) * 56.0
		MeshKit.box(st, Transform3D(Basis(), Vector3(p.x, 15.0, p.y)), Vector3(1.2, 30.0, 1.2), Color(0.15, 0.0, 0.0, 1.0))
		MeshKit.box(st, Transform3D(Basis(), Vector3(p.x, 30.5, p.y)), Vector3(2.0, 2.0, 4.0), Color(0.35, 0.0, 0.0, 1.0))
		for bl in 3:
			var ba := TAU * bl / 3.0
			MeshKit.box(st, Transform3D(Basis(Vector3.BACK, ba), Vector3(p.x, 30.5, p.y - 2.2) + Basis(Vector3.BACK, ba) * Vector3(0, 7.0, 0)), Vector3(0.8, 14.0, 0.2), Color(0.14, 0.0, 0.0, 1.0))
	# snowcats, red as they always are
	MeshKit.tag = MeshKit.TAG_RED
	for k in 8:
		var p := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(20.0, 58.0)
		var b := Basis(Vector3.UP, rng.randf() * TAU)
		MeshKit.box(st, Transform3D(b, Vector3(p.x, 1.3, p.y)), Vector3(2.6, 2.6, 5.0), Color(0.18, 0.2, 0.4, 1.0))
		MeshKit.box(st, Transform3D(b, Vector3(p.x, 1.2, p.y) + b * Vector3(0, 0, -2.0)), Vector3(2.0, 1.2, 1.0), Color(0.7, 0.0, 0.0, 1.0))
	# snow berm and vehicle barricade
	MeshKit.tag = MeshKit.TAG_SNOW
	for k in 36:
		var a := TAU * k / 36.0
		var d := Vector3(cos(a), 0, sin(a))
		_solid(d * 68.0 + Vector3.UP * 1.0, Vector3(12.5, 2.0, 3.5), Color(0.12, 0.3, 1.0, 1.0), -(a + PI * 0.5))
		if k % 2 == 0:
			defender_spots.append(d * 67.0 + Vector3.UP * 2.2)
	for k in 4:
		defender_spots.append(Vector3(-6.0 + (k % 2) * 12.0, 10.6, -6.0 + int(k / 2) * 12.0))
	_survivors(200, 55.0, 0.0, 4.0)
	# an LC-130 parked on the skiway
	var sd := Vector2(cos(deg_to_rad(20.0)), sin(deg_to_rad(20.0)))
	var pl := sd * 330.0 + Vector2(-sd.y, sd.x) * 14.0
	var pb := Basis(Vector3.UP, -sd.angle() + PI * 0.5)
	MeshKit.tag = MeshKit.TAG_WHITE
	MeshKit.box(st, Transform3D(pb, Vector3(pl.x, 3.0, pl.y)), Vector3(4.2, 4.2, 30.0), Color(0.15, 0.4, 0.6, 1.0))
	MeshKit.box(st, Transform3D(pb, Vector3(pl.x, 5.0, pl.y)), Vector3(40.0, 0.6, 4.0), Color(0.14, 0.4, 0.6, 1.0))
	MeshKit.box(st, Transform3D(pb, Vector3(pl.x, 7.0, pl.y) + pb * Vector3(0, 0, 13.0)), Vector3(0.6, 8.0, 4.0), Color(0.14, 0.4, 0.6, 1.0))
	MeshKit.tag = MeshKit.TAG_DARK
	for s: float in [-14.0, -7.5, 7.5, 14.0]:
		MeshKit.box(st, Transform3D(pb, Vector3(pl.x, 4.6, pl.y) + pb * Vector3(s, 0, -2.5)), Vector3(1.4, 1.4, 4.5), Color(0.3, 0.0, 0.0, 1.0))
	# rock outcrops poking through the ice
	MeshKit.tag = MeshKit.TAG_ROCK
	for k in 160:
		var p := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(250.0, 2800.0)
		if blocked(p, 10.0) or _reserved_at(p):
			continue
		var s := rng.randf_range(4.0, 18.0)
		MeshKit.box(st, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).rotated(Vector3.RIGHT, rng.randf_range(-0.4, 0.4)), Vector3(p.x, s * 0.25, p.y)), Vector3(s, s * 0.6, s * 0.8), Color(rng.randf_range(0.17, 0.23), 1.0, 0.6, 1.0))
	# fuel drums and marker flags along the approaches
	MeshKit.tag = MeshKit.TAG_RED
	for k in 200:
		var p := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(90.0, 900.0)
		MeshKit.box(st, Transform3D(Basis(), Vector3(p.x, 0.5, p.y)), Vector3(0.7, 1.0, 0.7), Color(0.14, 0.0, 0.0, 1.0))
	MeshKit.tag = MeshKit.TAG_AUTO
	_mountains(3300.0, 8000.0, 1150.0, 0.11, 0.2)


# ================================================================ FOR GOD, FOR HEAVEN
## Forested highlands with one way in: the whole horde funnels down a single valley from
## the north onto Firebase Gabriel. The hills are real terrain with collision, so rounds hit
## the hillsides; the valley floor and the firebase clearing stay flat, so the horde's
## straight-line walk still holds.
const VALLEY_DEG := 270.0
const VALLEY_HALF_DEG := 6.0

var terrain_noise: FastNoiseLite


## Distance from p to the edge of the approach valley (0 inside it).
func _valley_dist(p: Vector2) -> float:
	var d := Vector2(cos(deg_to_rad(VALLEY_DEG)), sin(deg_to_rad(VALLEY_DEG)))
	var along := p.dot(d)
	if along < -150.0:
		return 100000.0
	var hw := 70.0 + maxf(along, 0.0) * tan(deg_to_rad(VALLEY_HALF_DEG + 1.5))
	return maxf(0.0, absf(p.cross(d)) - hw)


## Ground height of the highlands; zero in the valley and the firebase clearing.
func terrain_h(p: Vector2) -> float:
	if terrain_noise == null:
		return 0.0
	var e := smoothstep(340.0, 650.0, p.length()) * smoothstep(0.0, 260.0, _valley_dist(p)) * _airstrip_clear(p)
	if e <= 0.0:
		return 0.0
	var n := terrain_noise.get_noise_2d(p.x, p.y) * 0.5 + 0.5
	var ridge := 1.0 - absf(terrain_noise.get_noise_2d(p.x * 0.6 + 731.0, p.y * 0.6 - 377.0))
	return e * (25.0 + 165.0 * (0.4 * n + 0.6 * ridge * ridge))


func _heaven() -> void:
	_wedge(VALLEY_DEG, VALLEY_HALF_DEG)
	_avenue(VALLEY_DEG, 8.0)
	info.merge({"wall_r": 105.0, "arrive": Vector2(106.0, 126.0), "refuge_h": 26.0, "ground": 5,
		"attract": Vector3(0, 0, -1500), "haze_heat": 0.22, "haze_dist": 8500.0,
		"horde_mult": 2.4, "mega_from": 1, "garrison": 2.0,
		"sun": Vector3(0.5, 0.55, 0.66), "sky": Vector3(0.72, 0.76, 0.78), "tv_fog": 6000.0}, true)
	_airfield(Vector2(0.0, 1060.0), Vector2(0.0, 1.0))
	_forest_terrain()
	_landmarks(3, 600.0, 1700.0, false)
	_avenue_roads(100.0, 4200.0, 0.3)
	_abandoned_cars(250.0, 2600.0, 30)
	_jams(2, 400.0, 2400.0)
	_checkpoints(1, 700.0)
	_firebase()
	# the forest: thousands of canopies over the hills, thinning out into the valley meadow
	for k in 11000:
		var p := Vector2(rng.randf_range(-4300, 4300), rng.randf_range(-4300, 4300))
		var h := terrain_h(p)
		if h < 3.0:
			continue
		var r := rng.randf_range(3.0, 7.0)
		tree_xf.append(Transform3D(Basis().scaled(Vector3(r, r * rng.randf_range(0.9, 1.3), r)), Vector3(p.x, h + r * 0.7, p.y)))
	for k in 900:
		var p := Vector2(rng.randf_range(-700, 700), rng.randf_range(-3800, -400))
		if _valley_dist(p) <= 0.0 and not blocked(p, 25.0):
			_tree(p, 0.8)
	_mountains(4300.0, 8500.0, 800.0, 0.2, 0.28)


func _forest_terrain() -> void:
	terrain_noise = FastNoiseLite.new()
	terrain_noise.seed = rng.randi()
	terrain_noise.frequency = 0.0011
	terrain_noise.fractal_octaves = 4
	var step := 50.0
	var n := 176
	var origin := -n * step * 0.5
	MeshKit.tag = MeshKit.TAG_FOREST
	var hs := PackedFloat32Array()
	hs.resize((n + 1) * (n + 1))
	for j in n + 1:
		for i in n + 1:
			hs[j * (n + 1) + i] = terrain_h(Vector2(origin + i * step, origin + j * step))
	var faces := PackedVector3Array()
	for j in n:
		for i in n:
			var h00 := hs[j * (n + 1) + i]
			var h10 := hs[j * (n + 1) + i + 1]
			var h01 := hs[(j + 1) * (n + 1) + i]
			var h11 := hs[(j + 1) * (n + 1) + i + 1]
			var hmax := maxf(maxf(h00, h10), maxf(h01, h11))
			if hmax < 0.5:
				continue
			var x0 := origin + i * step
			var z0 := origin + j * step
			if Vector2(x0 + step * 0.5, z0 + step * 0.5).length() > 4500.0:
				continue
			# sunk slightly so the flat valley floor (the ground plane) wins where they meet
			var a := Vector3(x0, h00 - 0.3, z0)
			var b := Vector3(x0 + step, h10 - 0.3, z0)
			var c := Vector3(x0 + step, h11 - 0.3, z0 + step)
			var d := Vector3(x0, h01 - 0.3, z0 + step)
			var hmin := minf(minf(h00, h10), minf(h01, h11))
			var hm := (h00 + h10 + h01 + h11) * 0.25
			# canopy; ridgelines sit above the cold air pooled in the valleys, so run warmer
			var heat := 0.19 + hm / 190.0 * 0.05 + rng.randf_range(-0.012, 0.012)
			if (hmax - hmin) / step > 0.9:
				heat = rng.randf_range(0.25, 0.29)
			var col := Color(heat, 1.2, 1.0, 1.0)
			MeshKit.tri(st, a, b, c, col)
			MeshKit.tri(st, a, c, d, col)
			for v in [a, b, c, a, c, d]:
				faces.append(v)
	MeshKit.tag = MeshKit.TAG_AUTO
	if faces.is_empty():
		return
	# collision, so rounds, missiles and bombs strike the hillsides
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	var sh := PhysicsServer3D.concave_polygon_shape_create()
	PhysicsServer3D.shape_set_data(sh, {"faces": faces, "backface_collision": true})
	PhysicsServer3D.body_add_shape(body, sh)
	PhysicsServer3D.body_set_space(body, space)
	bodies.append(body)
	bodies.append(sh)


## Firebase Gabriel: T-wall perimeter with a north gate facing the valley, towers, barracks,
## a hangar and helipads, a motor pool, artillery pits, and a chapel at its heart.
func _firebase() -> void:
	var hx := 130.0
	var hz := 100.0
	var tw := Color(0.34, 0.8, 1.0, 1.0)
	MeshKit.tag = MeshKit.TAG_DIRT
	_flat(Vector2.ZERO, Vector2(hx, hz), Vector2(1, 0), 0.04, Color(0.31, 0.0, 0.6, 1.0))
	# a gravel road from the gate down the middle of the base
	MeshKit.tag = MeshKit.TAG_CONCRETE
	_flat(Vector2(0, -40), Vector2(9, hz - 40.0), Vector2(1, 0), 0.05, Color(0.32, 0.0, 0.6, 1.0))
	# perimeter, with a 24 m gate in the north wall
	MeshKit.tag = MeshKit.TAG_CONCRETE
	_wall(Vector2(-hx, -hz), Vector2(-12.0, -hz), 4.2, 1.0, tw)
	_wall(Vector2(12.0, -hz), Vector2(hx, -hz), 4.2, 1.0, tw)
	_wall(Vector2(hx, -hz), Vector2(hx, hz), 4.2, 1.0, tw)
	_wall(Vector2(hx, hz), Vector2(-hx, hz), 4.2, 1.0, tw)
	_wall(Vector2(-hx, hz), Vector2(-hx, -hz), 4.2, 1.0, tw)
	# gate bunkers and a second line of HESCO behind the north wall
	MeshKit.tag = MeshKit.TAG_HESCO
	for s: float in [-1.0, 1.0]:
		_solid(Vector3(18.0 * s, 1.6, -hz - 5.0), Vector3(7.0, 3.2, 6.0), Color(0.36, 0.6, 1.0, 1.0))
		MeshKit.box(st, Transform3D(Basis(), Vector3(18.0 * s, 3.6, -hz - 5.0)), Vector3(3.0, 0.8, 1.0), Color(0.62, 0.2, 0.4, 1.0))
	MeshKit.tag = MeshKit.TAG_YELLOW
	_solid(Vector3(0, 0.6, -hz), Vector3(22.0, 1.2, 1.4), Color(0.27, 0.4, 0.6, 1.0))
	MeshKit.tag = MeshKit.TAG_HESCO
	_wall(Vector2(-70.0, -hz + 14.0), Vector2(70.0, -hz + 14.0), 2.6, 1.6, Color(0.33, 0.8, 1.0, 1.0))
	# watchtowers at the corners and along each wall
	for p: Vector2 in [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(hx, hz), Vector2(-hx, hz), Vector2(-60, -hz), Vector2(60, -hz), Vector2(hx, 0), Vector2(-hx, 0), Vector2(0, hz)]:
		MeshKit.tag = MeshKit.TAG_TIMBER
		_solid(Vector3(p.x, 5.0, p.y), Vector3(4.0, 10.0, 4.0), Color(0.3, 0.4, 0.8, 1.0))
		MeshKit.tag = MeshKit.TAG_OLIVE
		MeshKit.box(st, Transform3D(Basis(), Vector3(p.x, 10.8, p.y)), Vector3(4.6, 2.2, 4.6), Color(0.56, 0.2, 0.5, 1.0))
	# barracks rows (timber B-huts), the TOC and a hangar with a bird out front
	MeshKit.tag = MeshKit.TAG_TIMBER
	for row in 2:
		for k in 5:
			_solid(Vector3(-110.0 + k * 18.0, 2.6, 18.0 + row * 38.0), Vector3(13.0, 5.2, 30.0), Color(rng.randf_range(0.39, 0.41), 1.0, 1.0, 0.4))
	MeshKit.tag = MeshKit.TAG_CONCRETE
	_solid(Vector3(45, 5.0, 25), Vector3(30.0, 10.0, 20.0), Color(0.42, 1.0, 1.0, 0.35))
	MeshKit.tag = MeshKit.TAG_STEEL
	_solid(Vector3(92, 8.0, 62), Vector3(40.0, 16.0, 28.0), Color(0.38, 1.0, 1.0, 1.0))
	_helicopter(Vector2(92, 40), 0.0)
	for k in 3:
		var pad := Vector2(50.0 + k * 28.0, -55.0)
		MeshKit.tag = MeshKit.TAG_CONCRETE
		_flat(pad, Vector2(11, 11), Vector2(1, 0), 0.06, Color(0.37, 0.0, 0.5, 1.0))
		if k != 1:
			_helicopter(pad, 0.3 * k)
	# motor pool
	MeshKit.tag = MeshKit.TAG_OLIVE
	for k in 16:
		var p := Vector2(-115.0 + (k % 8) * 9.0, -70.0 + int(k / 8) * 14.0)
		var b := Basis(Vector3.UP, PI * 0.5)
		MeshKit.box(st, Transform3D(b, Vector3(p.x, 1.5, p.y)), Vector3(3.0, 3.0, 7.0), Color(0.29, 0.3, 0.4, 1.0))
		if k % 3 == 0:
			MeshKit.box(st, Transform3D(b, Vector3(p.x, 1.4, p.y) + b * Vector3(0, 0, -3.0)), Vector3(2.4, 1.4, 1.0), Color(0.8, 0.0, 0.0, 1.0))
	# artillery pits facing the valley
	for gx: float in [-30.0, 10.0]:
		MeshKit.tag = MeshKit.TAG_HESCO
		for k in 8:
			var a := TAU * k / 8.0
			MeshKit.box(st, Transform3D(Basis(Vector3.UP, -a), Vector3(gx + cos(a) * 8.0, 0.8, -35.0 + sin(a) * 8.0)), Vector3(6.0, 1.6, 1.4), Color(0.32, 0.6, 1.0, 1.0))
		MeshKit.tag = MeshKit.TAG_OLIVE
		MeshKit.box(st, Transform3D(Basis(Vector3.RIGHT, 0.35), Vector3(gx, 2.0, -38.0)), Vector3(0.6, 0.6, 7.0), Color(0.36, 0.3, 0.3, 1.0))
		MeshKit.box(st, Transform3D(Basis(), Vector3(gx, 1.0, -34.0)), Vector3(3.0, 2.0, 3.0), Color(0.33, 0.3, 0.4, 1.0))
	# fuel farm, comms mast, radar dome, floodlights
	MeshKit.tag = MeshKit.TAG_OLIVE
	for k in 4:
		MeshKit.cylinder(st, Vector3(100.0 + (k % 2) * 16.0, 0, -10.0 + int(k / 2) * 16.0), 6.0, 7.0, Color(0.36, 1.0, 0.6, 1.0), Color(0.3, 0.3, 0.5, 1.0))
	MeshKit.tag = MeshKit.TAG_DARK
	MeshKit.box(st, Transform3D(Basis(), Vector3(-112, 25.0, 85)), Vector3(1.5, 50.0, 1.5), Color(0.2, 0.0, 0.0, 1.0))
	MeshKit.box(st, Transform3D(Basis(), Vector3(-112, 50.5, 85)), Vector3(1.2, 1.2, 1.2), Color(1.2, 0.5, 0.0, 1.0))
	MeshKit.tag = MeshKit.TAG_WHITE
	MeshKit.box(st, Transform3D(Basis(), Vector3(-60, 5.0, 85)), Vector3(5.0, 10.0, 5.0), Color(0.3, 0.3, 0.6, 1.0))
	MeshKit.dome(st, Vector3(-60, 10.0, 85), 7.0, Color(0.26, 0.4, 0.8, 1.0))
	MeshKit.tag = MeshKit.TAG_DARK
	for p: Vector2 in [Vector2(-120, -90), Vector2(120, -90), Vector2(120, 90), Vector2(-120, 90)]:
		MeshKit.box(st, Transform3D(Basis(), Vector3(p.x, 9.0, p.y)), Vector3(0.8, 18.0, 0.8), Color(0.25, 0.0, 0.0, 1.0))
		MeshKit.box(st, Transform3D(Basis(), Vector3(p.x, 18.5, p.y)), Vector3(3.0, 1.4, 1.2), Color(1.15, 0.8, 0.0, 1.0))
	# the chapel: whitewashed, candle-lit windows, a steeple and a cross over the firebase
	MeshKit.tag = MeshKit.TAG_WHITE
	_solid(Vector3(0, 4.5, 40), Vector3(12.0, 9.0, 22.0), Color(0.42, 1.0, 1.0, 0.3))
	_solid(Vector3(0, 11.0, 27), Vector3(4.5, 22.0, 4.5), Color(0.38, 1.0, 1.0, 0.6))
	MeshKit.tag = MeshKit.TAG_TIMBER
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 24.5, 27)), Vector3(0.5, 5.0, 0.5), Color(0.4, 0.0, 0.0, 1.0))
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 25.6, 27)), Vector3(2.6, 0.5, 0.5), Color(0.4, 0.0, 0.0, 1.0))
	_camp(22.0, 10, 2, 4, 0.0, Vector2(-25, 75))
	# a cemetery outside the south wall: cold stone crosses in rows, on a mown lawn
	MeshKit.tag = MeshKit.TAG_GRASS
	_flat(Vector2(0, hz + 44.0), Vector2(76, 30), Vector2(1, 0), 0.03, Color(0.2, 0.0, 0.6, 1.0))
	MeshKit.tag = MeshKit.TAG_STONE
	for row in 6:
		for k in 12:
			var p := Vector2(-66.0 + k * 12.0, hz + 22.0 + row * 9.0)
			MeshKit.box(st, Transform3D(Basis(), Vector3(p.x, 0.9, p.y)), Vector3(0.25, 1.8, 0.25), Color(0.19, 0.0, 0.0, 1.0))
			MeshKit.box(st, Transform3D(Basis(), Vector3(p.x, 1.35, p.y)), Vector3(1.0, 0.25, 0.25), Color(0.19, 0.0, 0.0, 1.0))
	MeshKit.tag = MeshKit.TAG_AUTO
	# the garrison and the people they protect
	_survivors(200, 0.0, 0.1, 5.0, Vector2(0, 20), Vector2(110, 70))
	_survivors(60, 0.0, 0.1, 3.0, Vector2(-25, 75), Vector2(20, 18))
	for k in 36:
		var a := TAU * k / 36.0
		var d := Vector2(cos(a), sin(a))
		var tr := minf(hx / maxf(absf(d.x), 0.001), hz / maxf(absf(d.y), 0.001)) * 0.985
		defender_spots.append(Vector3(d.x * tr, 4.4, d.y * tr))


## A parked UH-60: cool airframe, hot engines, rotor blades.
func _helicopter(p: Vector2, yaw: float) -> void:
	var prev := MeshKit.tag
	var b := Basis(Vector3.UP, yaw)
	var c := Vector3(p.x, 0.0, p.y)
	MeshKit.tag = MeshKit.TAG_OLIVE
	MeshKit.box(st, Transform3D(b, c + Vector3(0, 1.7, 0)), Vector3(2.6, 2.6, 11.0), Color(0.33, 0.3, 0.4, 1.0))
	MeshKit.box(st, Transform3D(b, c + Vector3(0, 2.3, 0) + b * Vector3(0, 0, 7.5)), Vector3(0.6, 0.8, 5.0), Color(0.3, 0.3, 0.4, 1.0))
	MeshKit.box(st, Transform3D(b, c + Vector3(0, 3.3, 0) + b * Vector3(0, 0, -0.8)), Vector3(1.6, 0.9, 3.0), Color(0.85, 0.0, 0.0, 1.0))
	MeshKit.tag = MeshKit.TAG_DARK
	MeshKit.box(st, Transform3D(b, c + Vector3(0, 3.9, 0)), Vector3(16.0, 0.12, 0.5), Color(0.26, 0.0, 0.0, 1.0))
	MeshKit.box(st, Transform3D(b.rotated(Vector3.UP, PI * 0.5), c + Vector3(0, 3.9, 0)), Vector3(16.0, 0.12, 0.5), Color(0.26, 0.0, 0.0, 1.0))
	MeshKit.tag = prev
