extends SceneTree
## P2-1b: what the blank head of a written figure is made of. For every vertex
## above the Head joint prints how far
## its normal turns from the fitted ellipsoid's, its colour, and how many
## triangles lie there, so a "face smudge" can be traced to normals, colour or
## geometry instead of guessed at.
##   node autobuild/run_tool.mjs head_probe -- --src=res://art/characters/figure_lp_male.gltf

func _initialize() -> void:
	var src: String = ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--src="):
			src = a.substr(6)
	var doc: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(src), state) != OK:
		print("FAIL cannot read %s" % src)
		quit(1)
		return
	var root: Node = doc.generate_scene(state)
	var view: MeshInstance3D = root.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var bones: Skeleton3D = view.get_node(view.skeleton) as Skeleton3D
	var head_y: float = bones.get_bone_global_rest(bones.find_bone("Head")).origin.y
	var arrays: Array = view.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var top: float = -INF
	for v: Vector3 in verts:
		top = maxf(top, v.y)
	var above: float = head_y
	var low: Vector3 = Vector3(INF, INF, INF)
	var high: Vector3 = -low
	for v: Vector3 in verts:
		if v.y >= head_y:
			low = low.min(v)
			high = high.max(v)
	var centre: Vector3 = (low + high) * 0.5
	var radii: Vector3 = (high - low) * 0.5
	print("head joint y %.2f, top %.2f, probe above %.2f; egg centre %s radii %s" % [head_y, top, above, centre, radii])
	var buckets: PackedInt32Array = [0, 0, 0, 0, 0]  # <2, <10, <30, <90, >=90 degrees
	var off_surface: int = 0
	var count: int = 0
	var colour_set: Dictionary = {}
	var worst: Array = []
	for i: int in verts.size():
		var v: Vector3 = verts[i]
		if v.y < above:
			continue
		count += 1
		var d: Vector3 = (v - centre) / radii
		if absf(d.length() - 1.0) > 0.02:
			off_surface += 1
		var want: Vector3 = ((v - centre) / (radii * radii)).normalized()
		var angle: float = rad_to_deg(normals[i].angle_to(want))
		var k: int = 0 if angle < 2.0 else (1 if angle < 10.0 else (2 if angle < 30.0 else (3 if angle < 90.0 else 4)))
		buckets[k] += 1
		if angle >= 10.0:
			worst.append([angle, v, normals[i]])
		colour_set[colours[i].to_html(false)] = int(colour_set.get(colours[i].to_html(false), 0)) + 1
	var tris: int = 0
	var facing_in: int = 0
	for t: int in index.size() / 3:
		var a: Vector3 = verts[index[t * 3]]
		var b: Vector3 = verts[index[t * 3 + 1]]
		var c: Vector3 = verts[index[t * 3 + 2]]
		if a.y < above or b.y < above or c.y < above:
			continue
		tris += 1
		var face: Vector3 = (c - a).cross(b - a)
		if face.dot((a + b + c) / 3.0 - centre) < 0.0:
			facing_in += 1
	print("vertices %d (off the egg by >2%%: %d); normal vs egg: <2deg %d, <10 %d, <30 %d, <90 %d, >=90 %d" % [
		count, off_surface, buckets[0], buckets[1], buckets[2], buckets[3], buckets[4]])
	print("triangles %d, facing in %d; colours %s" % [tris, facing_in, colour_set])
	worst.sort_custom(func(x: Array, y: Array) -> bool: return x[0] > y[0])
	for w: Array in worst.slice(0, 8):
		print("  %.0f deg at %s n %s" % [w[0], w[1], w[2]])
	root.free()
	quit(0)
