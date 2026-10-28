extends RefCounted
## Helpers for building box-based meshes with per-vertex heat colours.
##
## `tag` is the material the daylight colour camera paints whatever is built next with: it is
## written into UV.x, and world.gdshader turns it into an albedo. World builders set it before
## each kind of thing they build and put it back to TAG_AUTO afterwards.

const TAG_AUTO := 0
const TAG_ASPHALT := 1
const TAG_CONCRETE := 2
const TAG_BUILDING := 3
const TAG_GLASS := 4
const TAG_MUD := 5
const TAG_STEEL := 6
const TAG_CONTAINER := 7
const TAG_OLIVE := 8
const TAG_HESCO := 9
const TAG_ROCK := 10
const TAG_SNOW := 11
const TAG_WHITE := 12
const TAG_RED := 13
const TAG_TIMBER := 14
const TAG_GRASS := 15
const TAG_FOREST := 16
const TAG_TENT := 17
const TAG_YELLOW := 18
const TAG_DIRT := 19
const TAG_SEATS := 20
const TAG_STONE := 21
const TAG_DARK := 22
const TAG_BURNT := 23
const TAG_SOLAR := 24
const TAG_AWNING := 25

static var tag := 0

const _CORNERS := [
	Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(-1, 1, -1),
	Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1),
]
const _FACES := [
	[[0, 1, 2, 3], Vector3(0, 0, -1)],
	[[5, 4, 7, 6], Vector3(0, 0, 1)],
	[[4, 0, 3, 7], Vector3(-1, 0, 0)],
	[[1, 5, 6, 2], Vector3(1, 0, 0)],
	[[3, 2, 6, 7], Vector3(0, 1, 0)],
	[[4, 5, 1, 0], Vector3(0, -1, 0)],
]


static func box(st: SurfaceTool, xf: Transform3D, size: Vector3, col: Color, uv := Vector2(-1.0, 0.0)) -> void:
	var h := size * 0.5
	if uv.x < 0.0:
		uv = Vector2(tag, 0.0)
	for f in _FACES:
		var idx: Array = f[0]
		var n: Vector3 = (xf.basis * (f[1] as Vector3)).normalized()
		var q: Array[Vector3] = []
		for k in 4:
			var c: Vector3 = _CORNERS[idx[k]]
			q.append(xf * (c * h))
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_color(col)
			st.set_normal(n)
			st.set_uv(uv)
			st.add_vertex(q[k])


static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
	for p in [a, b, c, a, c, d]:
		st.set_color(col)
		st.set_normal(n)
		st.set_uv(Vector2(tag, 0.0))
		st.add_vertex(p)


## One flat-shaded triangle. With up_facing the normal is flipped to point skyward (terrain).
static func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color, up_facing := true) -> void:
	var n := (b - a).cross(c - a).normalized()
	if up_facing and n.y < 0.0:
		n = -n
	for p in [a, b, c]:
		st.set_color(col)
		st.set_normal(n)
		st.set_uv(Vector2(tag, 0.0))
		st.add_vertex(p)


## Vertical cylinder standing on `base` (tanks, silos, towers).
static func cylinder(st: SurfaceTool, base: Vector3, r: float, h: float, col: Color, top_col: Color, segs := 18) -> void:
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var n := ((d0 + d1) * 0.5).normalized()
		quad(st, base + d0 * r, base + d1 * r, base + d1 * r + Vector3.UP * h, base + d0 * r + Vector3.UP * h, n, col)
		var top := base + Vector3.UP * h
		for p in [top, top + d0 * r, top + d1 * r]:
			st.set_color(top_col)
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(tag, 0.0))
			st.add_vertex(p)


## Low-poly hemisphere (radomes, domes).
static func dome(st: SurfaceTool, c: Vector3, r: float, col: Color, rings := 5, segs := 14) -> void:
	for i in rings:
		var p0 := PI * 0.5 * i / rings
		var p1 := PI * 0.5 * (i + 1) / rings
		for j in segs:
			var a0 := TAU * j / segs
			var a1 := TAU * (j + 1) / segs
			var v := [
				c + Vector3(cos(a0) * cos(p0), sin(p0), sin(a0) * cos(p0)) * r,
				c + Vector3(cos(a1) * cos(p0), sin(p0), sin(a1) * cos(p0)) * r,
				c + Vector3(cos(a1) * cos(p1), sin(p1), sin(a1) * cos(p1)) * r,
				c + Vector3(cos(a0) * cos(p1), sin(p1), sin(a0) * cos(p1)) * r,
			]
			var n: Vector3 = ((v[0] + v[2]) * 0.5 - c).normalized()
			quad(st, v[0], v[1], v[2], v[3], n, col)


## Low-poly humanoid facing -Z. UV.x tags parts for the shader:
## 0/1 legs, 2 torso, 3 head, 4 arms. Zombies reach forward; survivors/corpses don't.
static func humanoid(arms_forward: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := Color.WHITE
	box(st, Transform3D(Basis(), Vector3(0.11, 0.43, 0)), Vector3(0.15, 0.86, 0.16), w, Vector2(0, 0))
	box(st, Transform3D(Basis(), Vector3(-0.11, 0.43, 0)), Vector3(0.15, 0.86, 0.16), w, Vector2(1, 0))
	box(st, Transform3D(Basis(), Vector3(0, 1.15, 0)), Vector3(0.42, 0.62, 0.24), w, Vector2(2, 0))
	box(st, Transform3D(Basis(), Vector3(0, 1.6, -0.02)), Vector3(0.22, 0.26, 0.24), w, Vector2(3, 0))
	if arms_forward:
		box(st, Transform3D(Basis(), Vector3(0.25, 1.36, -0.3)), Vector3(0.1, 0.1, 0.62), w, Vector2(4, 0))
		box(st, Transform3D(Basis(), Vector3(-0.25, 1.36, -0.3)), Vector3(0.1, 0.1, 0.62), w, Vector2(4, 0))
	else:
		box(st, Transform3D(Basis(), Vector3(0.27, 1.12, 0)), Vector3(0.09, 0.6, 0.1), w, Vector2(5, 0))
		box(st, Transform3D(Basis(), Vector3(-0.27, 1.12, 0)), Vector3(0.09, 0.6, 0.1), w, Vector2(5, 0))
	return st.commit()


## A pitched roof over a w x d footprint whose eaves are at height h: two slopes rising to a
## ridge along the longer side, and the gable triangles at the ends.
static func gable(st: SurfaceTool, c: Vector3, w: float, d: float, h: float, rise: float, yaw: float, col: Color) -> void:
	# build it with the ridge along local x, swapping the axes when the footprint is deeper than wide
	var b := Basis(Vector3.UP, yaw) if w >= d else Basis(Vector3.UP, yaw + PI * 0.5)
	var hl := maxf(w, d) * 0.5 + 0.3
	var hs := minf(w, d) * 0.5 + 0.3
	var r0 := c + b * Vector3(-hl, h + rise, 0.0)
	var r1 := c + b * Vector3(hl, h + rise, 0.0)
	var a0 := c + b * Vector3(-hl, h, -hs)
	var a1 := c + b * Vector3(hl, h, -hs)
	var b0 := c + b * Vector3(-hl, h, hs)
	var b1 := c + b * Vector3(hl, h, hs)
	quad(st, a0, a1, r1, r0, b * Vector3(0.0, hs, -rise).normalized(), col)
	quad(st, b1, b0, r0, r1, b * Vector3(0.0, hs, rise).normalized(), col)
	tri_n(st, a0, r0, b0, b * Vector3.LEFT, col)
	tri_n(st, a1, b1, r1, b * Vector3.RIGHT, col)


static func tri_n(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
	for p in [a, b, c]:
		st.set_color(col)
		st.set_normal(n)
		st.set_uv(Vector2(tag, 0.0))
		st.add_vertex(p)


## A car with its origin on the ground, facing -Z. UV.x tags the parts for car.gdshader:
## 0 body, 1 glasshouse, 2 wheels and underside.
static func car() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := Color.WHITE
	box(st, Transform3D(Basis(), Vector3(0, 0.62, 0)), Vector3(1.82, 0.62, 4.45), w, Vector2(0, 0))
	box(st, Transform3D(Basis(), Vector3(0, 1.2, 0.25)), Vector3(1.6, 0.56, 2.3), w, Vector2(1, 0))
	for x: float in [-0.82, 0.82]:
		for z: float in [-1.4, 1.35]:
			box(st, Transform3D(Basis(), Vector3(x, 0.33, z)), Vector3(0.26, 0.64, 0.64), w, Vector2(2, 0))
	return st.commit()


## A bus or a box lorry (cab forward), origin on the ground, facing -Z. Same part tags as car().
static func bus(lorry: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := Color.WHITE
	if lorry:
		box(st, Transform3D(Basis(), Vector3(0, 1.3, -3.0)), Vector3(2.4, 2.1, 2.0), w, Vector2(0, 0))
		box(st, Transform3D(Basis(), Vector3(0, 1.7, -3.2)), Vector3(2.2, 0.7, 1.4), w, Vector2(1, 0))
		box(st, Transform3D(Basis(), Vector3(0, 2.0, 1.2)), Vector3(2.5, 2.9, 6.2), w, Vector2(0, 0))
	else:
		box(st, Transform3D(Basis(), Vector3(0, 1.75, 0)), Vector3(2.55, 2.7, 11.5), w, Vector2(0, 0))
		box(st, Transform3D(Basis(), Vector3(0, 2.25, 0)), Vector3(2.6, 0.9, 11.0), w, Vector2(1, 0))
	for z: float in ([-3.0, 0.4, 2.8] if lorry else [-3.8, 3.8]):
		for x: float in [-1.15, 1.15]:
			box(st, Transform3D(Basis(), Vector3(x, 0.5, z)), Vector3(0.35, 1.0, 1.0), w, Vector2(2, 0))
	return st.commit()


## A streetlight with its foot at the origin, the arm reaching out toward -Z. UV.x tags:
## 0 pole and arm, 1 the lamp head.
static func streetlight() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := Color.WHITE
	box(st, Transform3D(Basis(), Vector3(0, 4.5, 0)), Vector3(0.22, 9.0, 0.22), w, Vector2(0, 0))
	box(st, Transform3D(Basis(), Vector3(0, 8.95, -1.15)), Vector3(0.14, 0.14, 2.4), w, Vector2(0, 0))
	box(st, Transform3D(Basis(), Vector3(0, 8.85, -2.3)), Vector3(0.42, 0.22, 0.85), w, Vector2(1, 0))
	return st.commit()


## A tree trunk: a unit-tall post, scaled per tree.
static func trunk() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	box(st, Transform3D(Basis(), Vector3(0, 0.5, 0)), Vector3(0.35, 1.0, 0.35), Color(0.24, 0.3, 0.5, 1.0), Vector2(TAG_TIMBER, 0))
	return st.commit()


## A-10C Thunderbolt II silhouette facing -Z, hot TF34 engines.
static func a10() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grey := Vector2(TAG_STEEL, 0)
	var dark := Vector2(TAG_DARK, 0)
	var glass := Vector2(TAG_GLASS, 0)
	var body := Color(0.46, 0.0, 0.3, 1.0)
	var wing := Color(0.4, 0.0, 0.3, 1.0)
	var warm := Color(0.7, 0.0, 0.0, 1.0)
	var hot := Color(1.25, 0.0, 0.0, 1.0)
	# fuselage: the long centre section, a tapering nose with the gun under it, the tail cone
	box(st, Transform3D(Basis(), Vector3(0, 0, 0.5)), Vector3(1.7, 1.9, 9.5), body, grey)
	box(st, Transform3D(Basis(), Vector3(0, -0.1, -5.6)), Vector3(1.35, 1.5, 3.0), body, grey)
	box(st, Transform3D(Basis(), Vector3(0, -0.25, -7.6)), Vector3(0.9, 1.0, 1.4), body, grey)
	box(st, Transform3D(Basis(), Vector3(0, -0.55, -8.9)), Vector3(0.3, 0.3, 1.6), Color(0.5, 0.0, 0.0, 1.0), dark)
	box(st, Transform3D(Basis(), Vector3(0, 0.95, -5.2)), Vector3(1.0, 0.75, 2.4), Color(0.42, 0.0, 0.0, 1.0), glass)
	box(st, Transform3D(Basis(), Vector3(0, 0.15, 7.3)), Vector3(1.1, 1.3, 4.2), body, grey)
	# the straight wing, outer panels with a little dihedral, pylons and stores under it
	box(st, Transform3D(Basis(), Vector3(0, -0.35, -0.6)), Vector3(7.0, 0.38, 3.0), wing, grey)
	for s: float in [-1.0, 1.0]:
		box(st, Transform3D(Basis(Vector3.BACK, 0.08 * s), Vector3(6.4 * s, -0.12, -0.4)), Vector3(5.8, 0.3, 2.3), wing, grey)
		box(st, Transform3D(Basis(), Vector3(2.3 * s, -0.75, -0.2)), Vector3(0.7, 0.6, 2.4), body, grey)
		for x: float in [3.4, 5.2]:
			box(st, Transform3D(Basis(), Vector3(x * s, -0.85, -0.6)), Vector3(0.38, 0.38, 2.4), Color(0.6, 0.0, 0.0, 1.0), Vector2(TAG_OLIVE, 0))
		# the TF34s on their pylons over the rear fuselage
		box(st, Transform3D(Basis(), Vector3(1.55 * s, 1.0, 2.6)), Vector3(0.3, 0.6, 1.2), body, grey)
		box(st, Transform3D(Basis(), Vector3(1.55 * s, 1.35, 3.3)), Vector3(1.25, 1.25, 3.4), warm, grey)
		box(st, Transform3D(Basis(), Vector3(1.55 * s, 1.35, 5.15)), Vector3(0.95, 0.95, 0.4), hot, dark)
		# twin fins on the ends of the tailplane
		box(st, Transform3D(Basis(), Vector3(2.85 * s, 1.5, 8.2)), Vector3(0.22, 3.0, 1.8), wing, grey)
	box(st, Transform3D(Basis(), Vector3(0, 0.45, 8.3)), Vector3(5.9, 0.22, 1.7), wing, grey)
	return st.commit()
