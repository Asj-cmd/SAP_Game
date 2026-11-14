extends SceneTree
## Prints what a character model is made of, read at runtime (glTF or FBX):
## skeleton bone names and parents, rest height, triangles per mesh and in all,
## surfaces/materials, and animation names. Used by P2-1b to compare packs.
##   node autobuild/run_tool.mjs probe_character -- --src=<abs path> [--bones] [--tail=N]

func _initialize() -> void:
	var src: String = ""
	var show_bones: bool = false
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--src="):
			src = a.substr(6)
		elif a == "--bones":
			show_bones = true
	quit(_probe(src, show_bones))

func _probe(src: String, show_bones: bool) -> int:
	var fbx: bool = src.get_extension().to_lower() == "fbx"
	var reader: GLTFDocument = FBXDocument.new() if fbx else GLTFDocument.new()
	var state: GLTFState = FBXState.new() if fbx else GLTFState.new()
	if reader.append_from_file(src, state) != OK:
		print("FAIL cannot read %s" % src)
		return 1
	var root: Node = reader.generate_scene(state)
	print("== %s" % src.get_file())
	var total: int = 0
	var low: Vector3 = Vector3(INF, INF, INF)
	var high: Vector3 = -low
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var view: MeshInstance3D = node as MeshInstance3D
		var tris: int = 0
		var mats: PackedStringArray = []
		for s: int in view.mesh.get_surface_count():
			var arrays: Array = view.mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			tris += (idx.size() if idx.size() > 0 else verts.size()) / 3
			var m: Material = view.mesh.surface_get_material(s)
			mats.append(m.resource_name if m != null else "-")
		total += tris
		print("mesh %s: %d tris, %d surfaces [%s]" % [view.name, tris, view.mesh.get_surface_count(), ", ".join(mats)])
	for node: Node in root.find_children("*", "Skeleton3D", true, false):
		var bones: Skeleton3D = node as Skeleton3D
		var to_root: Transform3D = _xf(bones)
		print("skeleton %s: %d bones, scale to root %s" % [bones.name, bones.get_bone_count(), to_root.basis.get_scale()])
		var names: PackedStringArray = []
		for b: int in bones.get_bone_count():
			var parent: int = bones.get_bone_parent(b)
			var at: Vector3 = (to_root * bones.get_bone_global_rest(b)).origin
			low = low.min(at)
			high = high.max(at)
			if show_bones:
				print("  %s <- %s  at %s" % [bones.get_bone_name(b), bones.get_bone_name(parent) if parent >= 0 else "-", at])
			else:
				names.append(bones.get_bone_name(b))
		if not show_bones:
			print("  " + ", ".join(names))
	print("triangles total %d; bone extent %s .. %s" % [total, low, high])
	for node: Node in root.find_children("*", "AnimationPlayer", true, false):
		var player: AnimationPlayer = node as AnimationPlayer
		print("animations (%d): %s" % [player.get_animation_list().size(), ", ".join(player.get_animation_list())])
	root.free()
	return 0

## Transform to the scene root, without being in the tree.
func _xf(node: Node) -> Transform3D:
	var t: Transform3D = Transform3D.IDENTITY
	var n: Node = node
	while n != null:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t
