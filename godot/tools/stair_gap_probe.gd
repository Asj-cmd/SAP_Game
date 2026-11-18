extends SceneTree
## PT4-1: where the DRAWN shell lets light through at the top of each flight.
## Builds the real shell meshes (ShellBuilder, as the game does), finds every
## top tread (a tread whose top is the upper floor), and casts rays straight
## down on a grid round its top edge and its sides. A ray whose first front
## face (Godot culls back faces) is far below the tread top is a hole a player
## standing on the landing can see through.
##   node autobuild/run_tool.mjs stair_gap_probe

const STEP_SAMPLE: float = 4.0
const MARGIN: float = 60.0
const DEEP: float = 50.0 ## a first hit this far under the tread top is a hole

var _tris: PackedVector3Array = PackedVector3Array()
var _near: PackedVector3Array = PackedVector3Array()

func _initialize() -> void:
	var level: GreyBoxLevel = GreyBoxLevel.new()
	var theme: ArtTheme = ArtTheme.current()
	var blockers: Array[AABB] = level.collision.blockers
	var lot_ground: AABB = WorldBackdrop.widest_blocker(blockers)
	var shells: Array[MeshInstance3D] = ShellBuilder.build(level, theme, blockers.find(lot_ground))
	for shell: MeshInstance3D in shells:
		var mesh: ArrayMesh = shell.mesh as ArrayMesh
		for s: int in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var raw: Variant = arrays[Mesh.ARRAY_INDEX]
			var index: PackedInt32Array = raw if raw != null else PackedInt32Array()
			if index.is_empty():
				_tris.append_array(verts)
			else:
				for i: int in index:
					_tris.append(verts[i])
	print("shell triangles: %d" % (_tris.size() / 3))
	var top_y: float = -INF
	for box: AABB in blockers:
		if ShellBuilder._shape(box) == ShellBuilder.Shape.TREAD:
			top_y = maxf(top_y, box.end.y)
	var holes_total: int = 0
	for box: AABB in blockers:
		if ShellBuilder._shape(box) != ShellBuilder.Shape.TREAD or absf(box.end.y - top_y) > 0.5:
			continue
		holes_total += _probe(box)
	print("TOTAL hole samples: %d" % holes_total)
	for shell: MeshInstance3D in shells:
		shell.free()
	quit(0)

## Rays over the tread grown by MARGIN; reports the hole cells as runs.
func _probe(tread: AABB) -> int:
	var region: AABB = tread.grow(MARGIN)
	print("top tread %s..%s (top %.0f)" % [tread.position, tread.end, tread.end.y])
	_near = PackedVector3Array()
	for i: int in range(0, _tris.size(), 3):
		var a: Vector3 = _tris[i]
		var b: Vector3 = _tris[i + 1]
		var c: Vector3 = _tris[i + 2]
		if maxf(a.x, maxf(b.x, c.x)) < region.position.x or minf(a.x, minf(b.x, c.x)) > region.end.x:
			continue
		if maxf(a.z, maxf(b.z, c.z)) < region.position.z or minf(a.z, minf(b.z, c.z)) > region.end.z:
			continue
		# Only faces a downward ray sees from the front (Godot: clockwise fronts).
		if (b - a).cross(c - a).y >= -0.0001:
			continue
		_near.append_array([a, b, c])
	print("  %d candidate faces" % (_near.size() / 3))
	if "--map" in OS.get_cmdline_user_args():
		var mz: float = region.position.z + STEP_SAMPLE * 0.5
		while mz < region.end.z:
			var row: String = "  z%5.0f " % mz
			var mx: float = region.position.x + STEP_SAMPLE * 0.5
			while mx < region.end.x:
				var h: float = _first_hit(Vector3(mx, tread.end.y + 40.0, mz))
				row += "#" if h >= 655.0 else ("t" if h >= 620.0 else ("." if h >= 590.0 else ("o" if h > -1000.0 else " ")))
				mx += STEP_SAMPLE * 2.0
			print(row)
			mz += STEP_SAMPLE * 2.0
	var holes: int = 0
	var lowest: Dictionary = {}
	var hx: Array[float] = []
	var hz: Array[float] = []
	var x: float = region.position.x + STEP_SAMPLE * 0.5
	while x < region.end.x:
		var z: float = region.position.z + STEP_SAMPLE * 0.5
		while z < region.end.z:
			var hit: float = _first_hit(Vector3(x, tread.end.y + 40.0, z))
			if hit < tread.end.y - DEEP:
				holes += 1
				hx.append(x)
				hz.append(z)
				var key: int = int(round(hit))
				lowest[key] = int(lowest.get(key, 0)) + 1
			z += STEP_SAMPLE
		x += STEP_SAMPLE
	if holes == 0:
		print("  no hole")
		return 0
	var lo: Vector2 = Vector2(INF, INF)
	var hi: Vector2 = Vector2(-INF, -INF)
	for i: int in hx.size():
		lo = lo.min(Vector2(hx[i], hz[i]))
		hi = hi.max(Vector2(hx[i], hz[i]))
	print("  HOLE samples %d, x %.0f..%.0f z %.0f..%.0f, first-hit heights %s" % [holes,
		lo.x, hi.x, lo.y, hi.y, lowest])
	return holes

## Height of the first front-facing triangle straight down from `from`, or -INF.
func _first_hit(from: Vector3) -> float:
	var best: float = -INF
	var down: Vector3 = Vector3.DOWN
	for i: int in range(0, _near.size(), 3):
		var a: Vector3 = _near[i]
		var b: Vector3 = _near[i + 1]
		var c: Vector3 = _near[i + 2]
		if maxf(a.y, maxf(b.y, c.y)) <= best or minf(a.y, minf(b.y, c.y)) > from.y:
			continue
		if from.x < minf(a.x, minf(b.x, c.x)) or from.x > maxf(a.x, maxf(b.x, c.x)):
			continue
		if from.z < minf(a.z, minf(b.z, c.z)) or from.z > maxf(a.z, maxf(b.z, c.z)):
			continue
		var p: Variant = Geometry3D.ray_intersects_triangle(from, down, a, b, c)
		if p != null and (p as Vector3).y > best:
			best = (p as Vector3).y
	return best
