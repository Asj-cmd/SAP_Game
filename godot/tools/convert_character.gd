extends SceneTree
## P2-1b candidate preview: reads a character from a pack at runtime (glTF or
## FBX), holds it in one of its OWN clips at a time, bakes the skinned meshes in
## that pose into ONE static surface painted like the game's figures (vertex
## colour, the `figure_bake.mjs` PAINT colours, multiplied by the theme's putty
## material), drops eyes, hair and brows, scales it to `--height` cm with its feet
## at the origin, and writes a .glb. A STATIC model: it is for side-by-side
## frames against the current family (`--capture-figure=...,res://<out>`), not
## for play.
##   node autobuild/run_tool.mjs convert_character -- --src=<abs> --out=res://...glb
##        [--anim=Idle] [--time=0] [--height=180] [--paint=Shirt=shirt,Pants=trousers]
##
## Paint by source material name unless `--paint` says otherwise: eye/hair/brow
## dropped; skin bare; shoe/feet/boot shoes; pant/leg/trouser/jean/short trousers;
## anything else shirt.

const PAINT: Dictionary[String, Color] = {
	"bare": Color8(255, 255, 255),
	"shirt": Color8(160, 174, 190),
	"trousers": Color8(128, 122, 116),
	"shoes": Color8(80, 76, 72),
}

var _src: String = ""
var _out: String = ""
var _anim: String = "Idle"
var _time: float = 0.0
var _height: float = 180.0
var _paint: Dictionary[String, String] = {}
var _scene: Node = null
var _frames: int = 0

func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--src="):
			_src = a.substr(6)
		elif a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--anim="):
			_anim = a.substr(7)
		elif a.begins_with("--time="):
			_time = float(a.substr(7))
		elif a.begins_with("--height="):
			_height = float(a.substr(9))
		elif a.begins_with("--paint="):
			for pair: String in a.substr(8).split(","):
				_paint[pair.get_slice("=", 0).to_lower()] = pair.get_slice("=", 1)
	var fbx: bool = _src.get_extension().to_lower() == "fbx"
	var reader: GLTFDocument = FBXDocument.new() if fbx else GLTFDocument.new()
	var state: GLTFState = FBXState.new() if fbx else GLTFState.new()
	if reader.append_from_file(_src, state) != OK:
		print("FAIL cannot read %s" % _src)
		quit(1)
		return
	_scene = reader.generate_scene(state)
	root.add_child(_scene)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 2 or _scene == null:
		return false
	quit(_bake())
	return true

func _bake() -> int:
	var clip: String = ""
	for node: Node in _scene.find_children("*", "AnimationPlayer", true, false):
		var player: AnimationPlayer = node as AnimationPlayer
		for name: StringName in player.get_animation_list():
			if String(name) == _anim or String(name).ends_with("|" + _anim) or (clip == "" and String(name).contains(_anim)):
				clip = name
		if clip != "":
			player.play(clip)
			player.seek(_time, true)
	for node: Node in _scene.find_children("*", "Skeleton3D", true, false):
		(node as Skeleton3D).force_update_all_bone_transforms()
	print("pose: %s @ %.2f s" % [clip if clip != "" else "(rest)", _time])
	var points: PackedVector3Array = []
	var normals: PackedVector3Array = []
	var colours: PackedColorArray = []
	var dropped: PackedStringArray = []
	var used: PackedStringArray = []
	for node: Node in _scene.find_children("*", "MeshInstance3D", true, false):
		var view: MeshInstance3D = node as MeshInstance3D
		var posed: Mesh = view.mesh
		# Skinned: skinned on the CPU here (the headless renderer registers no skins,
		# so bake_mesh_from_current_skeleton_pose refuses). Bones index the skin's binds.
		var bones: Skeleton3D = view.get_node_or_null(view.skeleton) as Skeleton3D
		var binds: Array[Transform3D] = []
		var to_world: Transform3D = view.global_transform
		if view.skin != null and bones != null:
			to_world = bones.global_transform
			for b: int in view.skin.get_bind_count():
				var bone: int = view.skin.get_bind_bone(b)
				if bone < 0:
					bone = bones.find_bone(view.skin.get_bind_name(b))
				binds.append(bones.get_bone_global_pose(bone) * view.skin.get_bind_pose(b))
		for s: int in posed.get_surface_count():
			var source: Material = view.mesh.surface_get_material(s)
			var mat_name: String = source.resource_name if source != null else "-"
			var kind: String = _kind(mat_name, String(view.name))
			if kind == "drop":
				dropped.append(mat_name)
				continue
			used.append("%s=%s" % [mat_name, kind])
			var arrays: Array = posed.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if not binds.is_empty():
				var ids: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
				var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
				var per: int = ids.size() / verts.size()
				for v: int in verts.size():
					var cx: Vector3 = Vector3.ZERO
					var cy: Vector3 = Vector3.ZERO
					var cz: Vector3 = Vector3.ZERO
					var co: Vector3 = Vector3.ZERO
					for k: int in per:
						var w: float = weights[v * per + k]
						if w > 0.0:
							var m: Transform3D = binds[ids[v * per + k]]
							cx += m.basis.x * w
							cy += m.basis.y * w
							cz += m.basis.z * w
							co += m.origin * w
					var blend: Transform3D = Transform3D(Basis(cx, cy, cz), co)
					verts[v] = blend * verts[v]
					if norms.size() > v:
						norms[v] = blend.basis * norms[v]
			var order: PackedInt32Array = index
			if order.is_empty():
				order.resize(verts.size())
				for i: int in verts.size():
					order[i] = i
			for i: int in order:
				points.append(to_world * verts[i])
				normals.append((to_world.basis * norms[i]).normalized() if norms.size() > i else Vector3.UP)
				colours.append(PAINT[kind])
	if points.is_empty():
		print("FAIL nothing left to bake")
		return 1
	var low: Vector3 = Vector3(INF, INF, INF)
	var high: Vector3 = -low
	for p: Vector3 in points:
		low = low.min(p)
		high = high.max(p)
	var factor: float = _height / (high.y - low.y)
	var mid: Vector3 = Vector3((low.x + high.x) * 0.5, low.y, (low.z + high.z) * 0.5)
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in points.size():
		tool.set_color(colours[i])
		tool.set_normal(normals[i])
		tool.add_vertex((points[i] - mid) * factor)
	tool.index()
	var mesh: ArrayMesh = tool.commit()
	mesh.surface_set_material(0, StandardMaterial3D.new())
	mesh.surface_get_material(0).resource_name = "figure"
	var out_root: Node3D = Node3D.new()
	out_root.name = _out.get_file().get_basename()
	var out_view: MeshInstance3D = MeshInstance3D.new()
	out_view.name = "Figure"
	out_view.mesh = mesh
	out_root.add_child(out_view)
	out_view.owner = out_root
	var writer: GLTFDocument = GLTFDocument.new()
	var out_state: GLTFState = GLTFState.new()
	if writer.append_from_scene(out_root, out_state) != OK or writer.write_to_filesystem(out_state, ProjectSettings.globalize_path(_out)) != OK:
		print("FAIL cannot write %s" % _out)
		return 1
	out_root.free()
	print("used: %s" % ", ".join(used))
	print("dropped: %s" % ", ".join(dropped))
	print("wrote %s: %d triangles, source height %.3f -> %.0f, width %.0f, depth %.0f" % [
		_out, points.size() / 3, high.y - low.y, _height, (high.x - low.x) * factor, (high.z - low.z) * factor])
	return 0

func _kind(mat_name: String, mesh_name: String) -> String:
	var key: String = mat_name.to_lower()
	var part: String = mesh_name.to_lower()
	if _paint.has(key):
		return _paint[key]
	if key.contains("eye") or key.contains("hair"):
		return "drop"
	if key.contains("skin"):
		return "bare"
	# Modular packs name meshes by body part and materials by colour: on the head
	# anything not skin is brows, eyes or hair.
	if part.ends_with("head"):
		return "drop"
	if part.ends_with("feet"):
		return "shoes"
	if part.ends_with("legs"):
		return "trousers"
	if part.ends_with("body"):
		return "shirt"
	for word: String in ["shoe", "feet", "foot", "boot", "sock"]:
		if key.contains(word):
			return "shoes"
	for word: String in ["pant", "leg", "trouser", "jean", "short"]:
		if key.contains(word):
			return "trousers"
	return "shirt"
