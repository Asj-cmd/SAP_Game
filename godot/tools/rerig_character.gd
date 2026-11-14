extends SceneTree
## P2-1b: puts a body from the Quaternius "Animated low poly men/women" packs
## (their own 42-bone rig) onto the figure skeleton the whole animation set is
## built for (the Universal Animation Library rig in `figure_male.gltf`), so the
## clips, the driver, the wristband and the bone nudges keep working and only
## the mesh changes.
##
##   node autobuild/run_tool.mjs rerig_character -- --src=<abs .fbx>
##        --rig=res://art/characters/figure_male.gltf --out=res://art/characters/x.gltf
##        [--normal-smooth=4] [--egg=1]
##
## In order:
##  1. Poses the source body, through its own skin, into the rig's rest stance:
##     each limb segment is turned (shortest arc, parents first) to point the way
##     the rig's matching segment points. Lengths stay the source's own, so the
##     body keeps its proportions (long limbs, small head, big hands).
##  2. Scales it to the rig's height, feet on the floor, pelvis over the rig's.
##  3. Moves the rig's joints to the posed body's joints (rest ROTATIONS kept, so
##     every clip's local rotations mean what they meant), fingers and leaf bones
##     carried along scaled.
##  4. Rebinds the source weights to the rig's bones by name (`MAP`).
##  5. Paints like `figure_bake.mjs` (vertex colour: bare / shirt / trousers /
##     shoes; anything weighted to a foot is a shoe), drops eyes and hair,
##     projects the head onto a fitted ellipsoid (blank, D2), and shades with
##     normals smoothed over the welded mesh.

const PAINT: Dictionary[String, Color] = {
	"bare": Color8(255, 255, 255),
	"shirt": Color8(160, 174, 190),
	"trousers": Color8(128, 122, 116),
	"shoes": Color8(80, 76, 72),
}

## Source bone -> rig bone, for the weights. Sides: ".L"/".R" -> "_l"/"_r".
const MAP: Dictionary[String, String] = {
	"Bone": "root", "Body": "pelvis", "Hips": "pelvis", "Abdomen": "spine_01",
	"Torso": "spine_03", "Neck": "neck_01", "Head": "Head", "Head_end": "Head",
	"Shoulder": "clavicle", "UpperArm": "upperarm", "LowerArm": "lowerarm",
	"Palm": "hand", "MiddleHand": "hand", "Fingers": "hand", "Fingers_end": "hand",
	"Thumb1": "hand", "Thumb2": "hand", "Thumb2_end": "hand",
	"UpperLeg": "thigh", "LowerLeg": "calf", "LowerLeg_end": "calf",
	"Foot": "foot", "Foot_end": "foot", "PoleTarget": "root", "PoleTarget_end": "root",
}

## Segments turned to the rig's stance: [source bone, source descendant, rig
## bone, rig descendant, flat]. Flat = only the horizontal direction (the
## source foot lies on the ground from an ankle AT the ground; the rig's foot
## slopes down from an ankle 8 cm up, which would push the toes into the floor).
const ALIGN: Array[Array] = [
	["Abdomen", "Torso", "spine_01", "spine_03", false],
	["Torso", "Neck", "spine_03", "neck_01", false],
	["Neck", "Head", "neck_01", "Head", false],
	["Shoulder.S", "UpperArm.S", "clavicle_s", "upperarm_s", false],
	["UpperArm.S", "LowerArm.S", "upperarm_s", "lowerarm_s", false],
	["LowerArm.S", "Palm.S", "lowerarm_s", "hand_s", false],
	["Palm.S", "Fingers.S", "hand_s", "middle_01_s", false],
	["UpperLeg.S", "LowerLeg.S", "thigh_s", "calf_s", false],
	["LowerLeg.S", "LowerLeg.S_end", "calf_s", "foot_s", false],
	["Foot.S", "Foot.S_end", "foot_s", "ball_leaf_s", true],
]

## Rig joint -> the posed source joint it moves to.
const JOINTS: Dictionary[String, String] = {
	"pelvis": "Body", "spine_01": "Abdomen", "spine_03": "Torso", "neck_01": "Neck",
	"Head": "Head", "clavicle_s": "Shoulder.S", "upperarm_s": "UpperArm.S",
	"lowerarm_s": "LowerArm.S", "hand_s": "Palm.S", "thigh_s": "UpperLeg.S",
	"calf_s": "LowerLeg.S", "foot_s": "LowerLeg.S_end",
}

var _opts: Dictionary[String, String] = {}

func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var eq: int = a.find("=")
			_opts[a.substr(2, eq - 2) if eq >= 0 else a.substr(2)] = a.substr(eq + 1) if eq >= 0 else "true"
	quit(_run())

func _read(path: String) -> Node:
	var fbx: bool = path.get_extension().to_lower() == "fbx"
	var reader: GLTFDocument = FBXDocument.new() if fbx else GLTFDocument.new()
	var state: GLTFState = FBXState.new() if fbx else GLTFState.new()
	if reader.append_from_file(path, state) != OK:
		push_error("cannot read %s" % path)
		return null
	return reader.generate_scene(state)

func _run() -> int:
	var src: Node = _read(_opts.get("src", ""))
	var rig_path: String = _opts.get("rig", "res://art/characters/figure_male.gltf")
	var rig: Node = _read(ProjectSettings.globalize_path(rig_path))
	var out: String = _opts.get("out", "")
	if src == null or rig == null or out == "":
		push_error("need --src, --rig and --out")
		return 1
	var smooth_passes: int = int(_opts.get("normal-smooth", "4"))
	var egg: bool = _opts.get("egg", "1") != "0"

	# --- The source: bones in bind space, to the scene root.
	var s_view: MeshInstance3D = _find(src, "MeshInstance3D") as MeshInstance3D
	var s_bones: Skeleton3D = s_view.get_node_or_null(s_view.skeleton) as Skeleton3D
	if s_bones == null or s_view.skin == null:
		push_error("source has no skinned mesh")
		return 1
	var s_root: Transform3D = _xf(s_bones)
	var bind: Dictionary[int, Transform3D] = {}  # bone -> bind global (root space)
	for b: int in s_view.skin.get_bind_count():
		var bone: int = s_view.skin.get_bind_bone(b)
		if bone < 0:
			bone = s_bones.find_bone(s_view.skin.get_bind_name(b))
		bind[bone] = s_root * s_view.skin.get_bind_pose(b).affine_inverse()
	var rest: Dictionary[int, Transform3D] = {}
	for b: int in _order(s_bones):
		var parent: int = s_bones.get_bone_parent(b)
		if bind.has(b):
			rest[b] = bind[b]
		elif parent >= 0:
			rest[b] = rest[parent] * s_bones.get_bone_rest(b)
		else:
			rest[b] = s_root * s_bones.get_bone_rest(b)

	# --- The rig: global rest, to the scene root.
	var r_bones: Skeleton3D = _find(rig, "Skeleton3D") as Skeleton3D
	var r_view: MeshInstance3D = _find(rig, "MeshInstance3D") as MeshInstance3D
	var r_root: Transform3D = _xf(r_bones)
	var r_rest: Dictionary[String, Transform3D] = {}
	for b: int in r_bones.get_bone_count():
		r_rest[r_bones.get_bone_name(b)] = r_root * r_bones.get_bone_global_rest(b)
	var r_height: float = (_xf(r_view) * r_view.get_aabb()).end.y

	# --- 1. Pose the source into the rig's stance.
	var aligns: Dictionary[String, Array] = {}
	for row: Array in ALIGN:
		for side: Array in [["L", "l"], ["R", "r"]]:
			aligns[_side(row[0], side)] = [_side(row[1], side), _side(row[2], side), _side(row[3], side), row[4]]
	var posed: Dictionary[int, Transform3D] = {}
	var deferred: Array[int] = []
	for b: int in _order(s_bones):
		var parent: int = s_bones.get_bone_parent(b)
		var bname: String = s_bones.get_bone_name(b)
		# The source's feet hang off the root (an IK rig): placed after the legs,
		# at the shin's end.
		if bname.begins_with("Foot.") or (parent >= 0 and deferred.has(parent)):
			deferred.append(b)
			continue
		_pose_bone(s_bones, b, rest, posed, aligns, r_rest)
	for b: int in deferred:
		var bname: String = s_bones.get_bone_name(b)
		_pose_bone(s_bones, b, rest, posed, aligns, r_rest)
		if bname.begins_with("Foot.") and not bname.ends_with("_end"):
			var shin_end: int = s_bones.find_bone("LowerLeg.%s_end" % bname.substr(5))
			var moved: Transform3D = posed[b]
			moved.origin = posed[shin_end].origin
			posed[b] = moved
	var skinning: Dictionary[int, Transform3D] = {}
	for b: int in posed:
		if rest.has(b):
			skinning[b] = posed[b] * rest[b].affine_inverse()

	# --- Source vertices: skinned into the pose, painted, weights rebound.
	var points: PackedVector3Array = []
	var weights_out: Array[Dictionary] = []  # per corner: rig bone index -> weight
	var colours: PackedColorArray = []
	var head_w: PackedFloat32Array = []
	var dropped: PackedStringArray = []
	var bind_bone: PackedInt32Array = []
	for b: int in s_view.skin.get_bind_count():
		var bone: int = s_view.skin.get_bind_bone(b)
		bind_bone.append(bone if bone >= 0 else s_bones.find_bone(s_view.skin.get_bind_name(b)))
	# A body with its own scalp (HairBase) has hair strands on top: drop those.
	var has_scalp: bool = false
	for s: int in s_view.mesh.get_surface_count():
		var m: Material = s_view.mesh.surface_get_material(s)
		has_scalp = has_scalp or (m != null and m.resource_name.to_lower().contains("hairbase"))
	for s: int in s_view.mesh.get_surface_count():
		var mat: Material = s_view.mesh.surface_get_material(s)
		var mat_name: String = mat.resource_name if mat != null else "-"
		var kind: String = _kind(mat_name)
		if has_scalp and mat_name.to_lower() == "hair":
			kind = "drop"
		if kind == "drop":
			dropped.append(mat_name)
			continue
		var arrays: Array = s_view.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var ids: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var wts: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var per: int = ids.size() / verts.size()
		if index.is_empty():
			index.resize(verts.size())
			for i: int in verts.size():
				index[i] = i
		for i: int in index:
			var at: Vector3 = Vector3.ZERO
			var rebound: Dictionary = {}
			var on_head: float = 0.0
			var on_foot: float = 0.0
			for k: int in per:
				var w: float = wts[i * per + k]
				if w <= 0.0:
					continue
				var bone: int = bind_bone[ids[i * per + k]]
				at += (skinning[bone] * (s_root * verts[i])) * w
				var src_name: String = s_bones.get_bone_name(bone)
				var to: String = _rig_name(src_name)
				var rb: int = r_bones.find_bone(to)
				rebound[rb] = float(rebound.get(rb, 0.0)) + w
				if src_name.begins_with("Head"):
					on_head += w
				if src_name.begins_with("Foot"):
					on_foot += w
			points.append(at)
			weights_out.append(rebound)
			# By weight, not material: the men's shoes share the eyes' material.
			colours.append(PAINT["shoes" if on_foot >= 0.5 else kind])
			head_w.append(on_head)

	# --- 2. Scale to the rig's height, feet down, pelvis over the rig's pelvis.
	var low: Vector3 = Vector3(INF, INF, INF)
	var high: Vector3 = -low
	for p: Vector3 in points:
		low = low.min(p)
		high = high.max(p)
	var scale: float = r_height / (high.y - low.y)
	var body: Vector3 = posed[s_bones.find_bone("Body")].origin
	var shift: Vector3 = Vector3(r_rest["pelvis"].origin.x - body.x * scale, -low.y * scale,
		r_rest["pelvis"].origin.z - body.z * scale)
	for i: int in points.size():
		points[i] = points[i] * scale + shift
	var joint: Dictionary[String, Vector3] = {}
	for b: int in posed:
		joint[s_bones.get_bone_name(b)] = posed[b].origin * scale + shift

	# --- 5a. The blank head: an ellipsoid fitted to the head points. The eyes and
	# nose FOLD onto it (their triangles end up back to back), so their smoothed
	# normals cancel and drew a ghost face by shading alone: egged points take
	# the ellipsoid's own normal instead (egg_normal, by egg_w).
	var egg_normal: PackedVector3Array = []
	var egg_w: PackedFloat32Array = []
	if egg:
		var made: Dictionary = _egg_head(points, joint["Head"].y, r_height)
		points = made["points"]
		egg_normal = made["normals"]
		egg_w = made["weights"]

	# --- 3. Move the rig's joints.
	var placed: Dictionary[String, Vector3] = {}
	var hand_k: Dictionary[String, float] = {}
	for side: Array in [["L", "l"], ["R", "r"]]:
		var palm: Vector3 = joint["Palm.%s" % side[0]]
		var tips: Vector3 = joint["Fingers.%s" % side[0]]
		var r_hand: String = "hand_%s" % side[1]
		hand_k[side[1]] = palm.distance_to(tips) / r_rest[r_hand].origin.distance_to(r_rest["middle_01_%s" % side[1]].origin)
	for b: int in r_bones.get_bone_count():  # parents come first in this rig
		var bname: String = r_bones.get_bone_name(b)
		var parent: int = r_bones.get_bone_parent(b)
		var side_l: bool = bname.ends_with("_l")
		var key: String = bname.substr(0, bname.length() - 1) + "s" if (side_l or bname.ends_with("_r")) else bname
		var cap: String = "L" if side_l else "R"
		if JOINTS.has(key):
			placed[bname] = joint[JOINTS[key].replace(".S", "." + cap)]
		elif bname == "spine_02":
			var a: Vector3 = r_rest["spine_01"].origin
			var m: Vector3 = r_rest["spine_02"].origin
			var c: Vector3 = r_rest["spine_03"].origin
			placed[bname] = placed["spine_01"].lerp(joint["Torso"], a.distance_to(m) / (a.distance_to(m) + m.distance_to(c)))
		elif parent < 0:
			placed[bname] = r_rest[bname].origin
		else:
			var pname: String = r_bones.get_bone_name(parent)
			var k: float = 1.0
			if bname.contains("index") or bname.contains("middle") or bname.contains("ring") \
					or bname.contains("pinky") or bname.contains("thumb"):
				k = hand_k["l" if side_l else "r"]
			placed[bname] = placed[pname] + (r_rest[bname].origin - r_rest[pname].origin) * k
	var to_skel: Transform3D = r_root.affine_inverse()
	var new_global: Array[Transform3D] = []
	for b: int in r_bones.get_bone_count():
		var g: Transform3D = r_bones.get_bone_global_rest(b)
		new_global.append(Transform3D(g.basis, to_skel * placed[r_bones.get_bone_name(b)]))
	for b: int in r_bones.get_bone_count():
		var parent: int = r_bones.get_bone_parent(b)
		var local: Transform3D = new_global[b] if parent < 0 else new_global[parent].affine_inverse() * new_global[b]
		r_bones.set_bone_rest(b, local)
	r_bones.reset_bone_poses()

	# --- 4/5b. The mesh in the rig's skeleton space, normals smoothed, skin.
	for i: int in points.size():
		points[i] = to_skel * points[i]
	# Triangles folded inside out by the egg (fully on it, facing in) go: they
	# still cast the sun's shadow onto the head, smudging a ghost face.
	if not egg_w.is_empty():
		var kept: PackedInt32Array = []
		var folded: int = 0
		for t: int in points.size() / 3:
			var a: int = t * 3
			if egg_w[a] >= 0.99 and egg_w[a + 1] >= 0.99 and egg_w[a + 2] >= 0.99:
				var face: Vector3 = (points[a + 2] - points[a]).cross(points[a + 1] - points[a])
				var out_n: Vector3 = egg_normal[a] + egg_normal[a + 1] + egg_normal[a + 2]
				if face.dot(to_skel.basis * out_n) <= 0.0:
					folded += 1
					continue
			kept.append_array([a, a + 1, a + 2])
		var p2: PackedVector3Array = []
		var c2: PackedColorArray = []
		var w2: Array[Dictionary] = []
		var en2: PackedVector3Array = []
		var ew2: PackedFloat32Array = []
		for i: int in kept:
			p2.append(points[i])
			c2.append(colours[i])
			w2.append(weights_out[i])
			en2.append(egg_normal[i])
			ew2.append(egg_w[i])
		points = p2
		colours = c2
		weights_out = w2
		egg_normal = en2
		egg_w = ew2
		print("egg: %d folded triangles dropped" % folded)
	var normals: PackedVector3Array = _smooth_normals(points, smooth_passes)
	for i: int in egg_w.size():
		if egg_w[i] > 0.0:
			var round_n: Vector3 = (to_skel.basis * egg_normal[i]).normalized()
			normals[i] = normals[i].lerp(round_n, egg_w[i]).normalized()
	var arrays_out: Array = []
	arrays_out.resize(Mesh.ARRAY_MAX)
	var bones_out: PackedInt32Array = []
	var wts_out: PackedFloat32Array = []
	for i: int in points.size():
		var pairs: Array = []
		for rb: int in weights_out[i]:
			pairs.append([float(weights_out[i][rb]), rb])
		pairs.sort_custom(func(x: Array, y: Array) -> bool: return x[0] > y[0])
		var total: float = 0.0
		for k: int in mini(4, pairs.size()):
			total += pairs[k][0]
		for k: int in 4:
			bones_out.append(pairs[k][1] if k < pairs.size() else 0)
			wts_out.append(pairs[k][0] / total if k < pairs.size() else 0.0)
	arrays_out[Mesh.ARRAY_VERTEX] = points
	arrays_out[Mesh.ARRAY_NORMAL] = normals
	arrays_out[Mesh.ARRAY_COLOR] = colours
	arrays_out[Mesh.ARRAY_BONES] = bones_out
	arrays_out[Mesh.ARRAY_WEIGHTS] = wts_out
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays_out)
	var figure_mat: StandardMaterial3D = StandardMaterial3D.new()
	figure_mat.resource_name = "figure"
	figure_mat.vertex_color_use_as_albedo = true
	mesh.surface_set_material(0, figure_mat)
	# Weld identical corners (position, normal, colour, weights) into an index.
	var tool: SurfaceTool = SurfaceTool.new()
	tool.create_from(mesh, 0)
	tool.index()
	mesh = tool.commit()
	mesh.surface_set_material(0, figure_mat)
	var skin: Skin = Skin.new()
	for b: int in r_bones.get_bone_count():
		skin.add_named_bind(r_bones.get_bone_name(b), new_global[b].affine_inverse())
	r_view.mesh = mesh
	r_view.skin = skin
	r_view.transform = Transform3D.IDENTITY
	if r_view.get_parent() != r_bones:
		push_warning("rig mesh is not a child of its skeleton; the skin is in skeleton space")

	var writer: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	if writer.append_from_scene(rig, state) != OK or writer.write_to_filesystem(state, ProjectSettings.globalize_path(out)) != OK:
		push_error("cannot write %s" % out)
		return 1
	_stamp_bin_hash(ProjectSettings.globalize_path(out))
	var leg: float = placed["thigh_l"].distance_to(placed["calf_l"]) + placed["calf_l"].distance_to(placed["foot_l"])
	var r_leg: float = r_rest["thigh_l"].origin.distance_to(r_rest["calf_l"].origin) \
		+ r_rest["calf_l"].origin.distance_to(r_rest["foot_l"].origin)
	print("dropped: %s" % ", ".join(dropped))
	print("wrote %s: %d triangles, height %.1f (rig %.1f), leg %.1f (rig %.1f), head joint %.1f (rig %.1f), hand x%.2f" % [
		out, mesh.surface_get_array_index_len(0) / 3, r_height, r_height, leg, r_leg,
		placed["Head"].y, r_rest["Head"].origin.y, hand_k["l"]])
	src.free()
	rig.free()
	return 0

## Godot re-imports a .gltf only when the .gltf itself changes, so a re-run that
## changed only vertex data never reached the game (P1-5). The buffers' SHA-1
## goes into `asset.extras.bin_sha1`, as `figure_bake.mjs` does.
func _stamp_bin_hash(gltf_path: String) -> void:
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(gltf_path))
	var hashing: HashingContext = HashingContext.new()
	hashing.start(HashingContext.HASH_SHA1)
	for buffer: Dictionary in doc.get("buffers", []):
		hashing.update(FileAccess.get_file_as_bytes(gltf_path.get_base_dir().path_join(buffer["uri"])))
	var asset: Dictionary = doc.get("asset", {})
	var extras: Dictionary = asset.get("extras", {})
	extras["bin_sha1"] = hashing.finish().hex_encode()
	asset["extras"] = extras
	doc["asset"] = asset
	var file: FileAccess = FileAccess.open(gltf_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(doc))
	file.close()

## Poses one source bone: follows its parent, then turns toward the rig.
func _pose_bone(bones: Skeleton3D, b: int, rest: Dictionary[int, Transform3D],
		posed: Dictionary[int, Transform3D], aligns: Dictionary[String, Array],
		r_rest: Dictionary[String, Transform3D]) -> void:
	var parent: int = bones.get_bone_parent(b)
	if parent < 0 or not posed.has(parent):
		posed[b] = rest[b]
	else:
		posed[b] = posed[parent] * (rest[parent].affine_inverse() * rest[b])
	var bname: String = bones.get_bone_name(b)
	if not aligns.has(bname):
		return
	var row: Array = aligns[bname]
	var child: int = bones.find_bone(row[0])
	if child < 0:
		return
	var now: Vector3 = (posed[b] * (rest[b].affine_inverse() * rest[child]).origin) - posed[b].origin
	var want: Vector3 = r_rest[row[2]].origin - r_rest[row[1]].origin
	if row[3]:
		now.y = 0.0
		want.y = 0.0
	if now.length() < 1e-6 or want.length() < 1e-6:
		return
	var turn: Quaternion = Quaternion(now.normalized(), want.normalized())
	posed[b] = Transform3D(Basis(turn) * posed[b].basis, posed[b].origin)

## The head is chosen by HEIGHT above the head joint, not by weight: these rigs
## share the face's weights with the neck, and a weight blend left the nose,
## brow and hairline half there. Fully on the ellipsoid from `rise` above the
## joint, blended over `blend` below that; nothing under the joint moves.
## Returns {points, normals (the ellipsoid's), weights (0 = untouched)}: a
## packed array argument is a copy in GDScript, so nothing is changed in place.
func _egg_head(source: PackedVector3Array, joint_y: float, height: float) -> Dictionary:
	var points: PackedVector3Array = source.duplicate()
	var normals: PackedVector3Array = []
	normals.resize(points.size())
	var weights: PackedFloat32Array = []
	weights.resize(points.size())
	var result: Dictionary = {"points": points, "normals": normals, "weights": weights}
	var rise: float = 0.03 * height
	var blend: float = 0.035 * height
	var low: Vector3 = Vector3(INF, INF, INF)
	var high: Vector3 = -low
	var n: int = 0
	for i: int in points.size():
		if points[i].y >= joint_y:
			low = low.min(points[i])
			high = high.max(points[i])
			n += 1
	if n == 0:
		return result
	var centre: Vector3 = (low + high) * 0.5
	var radii: Vector3 = (high - low) * 0.5
	for i: int in points.size():
		var w: float = smoothstep(joint_y + rise - blend, joint_y + rise, points[i].y)
		if w <= 0.0:
			continue
		var d: Vector3 = (points[i] - centre) / radii
		if d.length() < 1e-6:
			continue
		var on: Vector3 = centre + (d.normalized() * radii)
		points[i] = points[i].lerp(on, w)
		# The gradient of the ellipsoid at `on`.
		normals[i] = ((on - centre) / (radii * radii)).normalized()
		weights[i] = w
	result["points"] = points
	result["normals"] = normals
	result["weights"] = weights
	return result

## Area-weighted normals over the mesh welded by position, then averaged with
## their neighbours `passes` times (soft, plain shading; P2-1 did the same).
func _smooth_normals(points: PackedVector3Array, passes: int) -> PackedVector3Array:
	var weld: Dictionary[Vector3i, int] = {}
	var id: PackedInt32Array = []
	for p: Vector3 in points:
		var key: Vector3i = Vector3i(roundi(p.x * 1e5), roundi(p.y * 1e5), roundi(p.z * 1e5))
		if not weld.has(key):
			weld[key] = weld.size()
		id.append(weld[key])
	var count: int = weld.size()
	var acc: PackedVector3Array = []
	acc.resize(count)
	var links: Array[Dictionary] = []
	links.resize(count)
	for i: int in count:
		links[i] = {}
	for t: int in points.size() / 3:
		var a: int = t * 3
		# Godot's front faces wind clockwise: this order points outward.
		var face: Vector3 = (points[a + 2] - points[a]).cross(points[a + 1] - points[a])
		for k: int in 3:
			acc[id[a + k]] += face
			links[id[a + k]][id[a + (k + 1) % 3]] = true
			links[id[a + k]][id[a + (k + 2) % 3]] = true
	for i: int in count:
		acc[i] = acc[i].normalized()
	for _p: int in passes:
		var next: PackedVector3Array = acc.duplicate()
		for i: int in count:
			var sum: Vector3 = acc[i]
			for j: int in links[i]:
				sum += acc[j]
			next[i] = sum.normalized()
		acc = next
	var out: PackedVector3Array = []
	for i: int in points.size():
		out.append(acc[id[i]])
	return out

func _kind(mat_name: String) -> String:
	var key: String = mat_name.to_lower()
	# Eyes and hair close the head (it is open under them): kept, bare, and
	# folded into the egg with the rest of the head.
	if key.contains("skin") or key.contains("hair") or key.contains("eye"):
		return "bare"
	if key.contains("shoe") or key.contains("sock"):
		return "shoes"
	if key.contains("pant") or key.contains("short"):
		return "trousers"
	return "shirt"

func _rig_name(src_name: String) -> String:
	var side: String = ""
	var base: String = src_name
	for s: String in [".L", ".R"]:
		var at: int = src_name.find(s)
		if at >= 0:
			side = "_" + s.substr(1).to_lower()
			base = src_name.substr(0, at) + src_name.substr(at + 2)
	if not MAP.has(base):
		push_warning("no rig bone for %s, using root" % src_name)
		return "root"
	var to: String = MAP[base]
	return to + side if side != "" and to != "root" else to

func _side(name: String, side: Array) -> String:
	return name.replace(".S", "." + side[0]).replace("_s", "_" + side[1])

func _order(bones: Skeleton3D) -> Array[int]:
	var out: Array[int] = []
	var todo: Array[int] = []
	for b: int in bones.get_bone_count():
		if bones.get_bone_parent(b) < 0:
			todo.append(b)
	while not todo.is_empty():
		var b: int = todo.pop_front()
		out.append(b)
		for c: int in bones.get_bone_children(b):
			todo.append(c)
	return out

func _find(node: Node, type: String) -> Node:
	if node.is_class(type):
		return node
	for child: Node in node.get_children():
		var hit: Node = _find(child, type)
		if hit != null:
			return hit
	return null

func _xf(node: Node) -> Transform3D:
	var t: Transform3D = Transform3D.IDENTITY
	var n: Node = node
	while n != null:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t
