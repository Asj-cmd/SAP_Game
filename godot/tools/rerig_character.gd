extends SceneTree
## P2-1b: puts a body from the Quaternius "Animated low poly men/women" packs
## (their own 42-bone rig) onto the figure skeleton the whole animation set is
## built for (the Universal Animation Library rig in `figure_male.gltf`), so the
## clips, the driver, the wristband and the bone nudges keep working and only
## the mesh changes.
##
##   node autobuild/run_tool.mjs rerig_character -- --src=<abs .fbx>
##        --rig=res://art/characters/figure_male.gltf --out=res://art/characters/x.gltf
##        [--normal-smooth=4] [--egg=1] [--egg-depth-max=1.45] [--kinds=Jacket:trim,Shirt:shirt]
##        [--hair=combover|beehive|mohawk|pigtails_long|pigtails_short] [--hair-height=8]
##        [--belly=9]
##
## --hair (P2-6) adds plain solid hair shapes on the blank head, painted `hair`
## and rigid on the Head bone; --belly pushes the front of the lower torso out
## by that many cm.
##
## --kinds overrides which paint region a source material becomes (exact
## material name -> bare | shirt | trim | trousers | shoes | drop).
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
	# A second colour on the top (two-tone sleeves, a jacket over a shirt): its
	# own region so the theme can colour it (ArtTheme.OUTFIT_REGIONS, P2-1b).
	"trim": Color8(200, 196, 160),
	"trousers": Color8(128, 122, 116),
	"shoes": Color8(80, 76, 72),
	# P2-6: plain hair shapes. A mid brown, so a figure drawn without the theme's
	# hair colours still has hair; the theme recolours it per member.
	"hair": Color8(122, 86, 58),
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
	var kinds: Dictionary[String, String] = {}
	for pair: String in _opts.get("kinds", "").split(",", false):
		kinds[pair.get_slice(":", 0)] = pair.get_slice(":", 1)
		if not PAINT.has(pair.get_slice(":", 1)) and pair.get_slice(":", 1) != "drop":
			push_error("--kinds: no paint region %s" % pair.get_slice(":", 1))
			return 1

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
	# Which way each bone's own axes point at rest (root space), for whoever
	# writes bone scales in the theme: only the two axes ACROSS a bone thicken it.
	for bname: String in ["pelvis", "spine_03", "neck_01", "clavicle_l", "upperarm_l", "lowerarm_l"]:
		var b: Basis = r_rest[bname].basis.orthonormalized()
		print("axes: %s x %s y %s z %s" % [bname, b.x.snapped(Vector3.ONE * 0.01),
			b.y.snapped(Vector3.ONE * 0.01), b.z.snapped(Vector3.ONE * 0.01)])

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
		var kind: String = kinds.get(mat_name, _kind(mat_name))
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

	# Which way the body faces along z: toes ahead of the ankle, by the joints and
	# by the mesh (they must agree, or hair and belly would go on the back).
	var cm: float = r_height / 180.0
	var toe_z: float = joint["Foot.L_end"].z - joint["Foot.L"].z
	var foot_bone: int = r_bones.find_bone("foot_l")
	var foot_sum: float = 0.0
	var foot_n: int = 0
	for i: int in points.size():
		if float(weights_out[i].get(foot_bone, 0.0)) >= 0.5:
			foot_sum += points[i].z
			foot_n += 1
	var mesh_z: float = (foot_sum / foot_n - joint["LowerLeg.L_end"].z) if foot_n > 0 else 0.0
	var fwd: float = 1.0 if mesh_z >= 0.0 else -1.0
	print("facing: z %+.0f (toes %.2f by joints, %.2f by mesh), 1 cm = %.4f" % [fwd, toe_z, mesh_z, cm])
	if (_opts.has("hair") or _opts.has("belly")) and (absf(mesh_z) < 0.5 * cm or toe_z * mesh_z < 0.0):
		push_error("cannot tell which way the body faces")
		return 1

	# --- 2b. The belly (P2-6): the front of the lower torso pushed forward, fading
	# out up, down and to the sides. A bone scale would widen the whole torso.
	var belly: float = float(_opts.get("belly", "0")) * cm
	if belly > 0.0:
		var torso: Array[int] = [r_bones.find_bone("pelvis"), r_bones.find_bone("spine_01"),
			r_bones.find_bone("spine_02"), r_bones.find_bone("spine_03")]
		# Fullest half way between the abdomen and chest joints (about the navel);
		# gone by the hip joints below and the chest above.
		var mid_y: float = lerpf(joint["Abdomen"].y, joint["Torso"].y, 0.5)
		var reach: float = (joint["Torso"].y - joint["Body"].y) * 0.8
		var mid: Vector3 = joint["Body"]
		var half_w: float = 0.0
		var depth: float = 0.0
		var on_torso: PackedFloat32Array = []
		for i: int in points.size():
			var tw: float = 0.0
			for rb: int in torso:
				tw += float(weights_out[i].get(rb, 0.0))
			on_torso.append(tw)
			if tw >= 0.5 and absf(points[i].y - mid_y) < reach * 0.5:
				half_w = maxf(half_w, absf(points[i].x - mid.x))
				depth = maxf(depth, (points[i].z - mid.z) * fwd)
		var moved: int = 0
		for i: int in points.size():
			if on_torso[i] <= 0.0 or half_w <= 0.0 or depth <= 0.0:
				continue
			var p: Vector3 = points[i]
			var gy: float = pow(cos(PI * 0.5 * minf(1.0, absf(p.y - mid_y) / reach)), 2.0)
			var gx: float = cos(PI * 0.5 * minf(1.0, absf(p.x - mid.x) / half_w))
			var gz: float = smoothstep(-0.2, 0.6, (p.z - mid.z) * fwd / depth)
			var push: float = belly * on_torso[i] * gy * gx * gz
			if push <= 0.0:
				continue
			p.z += push * fwd
			p.x += (p.x - mid.x) / half_w * push * 0.25
			points[i] = p
			moved += 1
		print("belly: %.1f out at y %.1f (reach %.1f, half width %.1f, depth %.1f), %d corners moved" % [
			belly, mid_y, reach, half_w, depth, moved])

	# --- 5a. The blank head: an ellipsoid fitted to the head points. The eyes and
	# nose FOLD onto it (their triangles end up back to back), so their smoothed
	# normals cancel and drew a ghost face by shading alone: egged points take
	# the ellipsoid's own normal instead (egg_normal, by egg_w).
	var egg_normal: PackedVector3Array = []
	var egg_w: PackedFloat32Array = []
	var egg_centre: Vector3 = Vector3.ZERO
	var egg_radii: Vector3 = Vector3.ONE
	if egg:
		# The egg's base is below the Head joint, at the chin: these heads hang
		# their jaw ~6 cm under the joint, and an egg fitted from the joint up
		# left the chin crumpled under it like a goatee (P2-1b rerig14).
		var base: float = float(_opts.get("egg-base", "0.035")) * r_height
		var made: Dictionary = _egg_head(points, joint["Head"].y - base, r_height, joint["Head"].z)
		points = made["points"]
		egg_normal = made["normals"]
		egg_w = made["weights"]
		egg_centre = made["centre"]
		egg_radii = made["radii"]
		# The egg is round only while every point on it moves together. These
		# rigs share the face's weights with the neck, so any clip that turns the
		# head against the neck pulled the folded eyes, nose and mouth back out
		# of the egg (the "face smudge" of P2-1b). Egged points follow the Head
		# bone alone, blended in by how far they are on the egg.
		var head_bone: int = r_bones.find_bone("Head")
		for i: int in egg_w.size():
			var w: float = egg_w[i]
			if w <= 0.0:
				continue
			var mixed: Dictionary = {}
			for rb: int in weights_out[i]:
				mixed[rb] = float(weights_out[i][rb]) * (1.0 - w)
			mixed[head_bone] = float(mixed.get(head_bone, 0.0)) + w
			weights_out[i] = mixed
		# The low-poly head is ~130 flat triangles still laid out like the face it
		# had (dense at eyes, nose and mouth). Facets that coarse shadow themselves
		# near the sun's terminator, and the shadow drew the old face (P2-1b
		# rerig11). Each subdivision level splits every triangle touching the egg
		# in four, new points on the egg: facet sag falls 4x per level.
		var levels: int = int(_opts.get("egg-subdiv", "1"))
		for _l: int in levels:
			var soup: Dictionary = _subdivide_egg({"points": points, "colours": colours,
				"weights": weights_out, "egg_normal": egg_normal, "egg_w": egg_w}, made["centre"], made["radii"])
			points = soup["points"]
			colours = soup["colours"]
			weights_out = soup["weights"]
			egg_normal = soup["egg_normal"]
			egg_w = soup["egg_w"]

	# --- 5c. Hair (P2-6): closed plain shapes placed from the egg, painted
	# `hair`, every corner on the Head bone alone, shaded with the rest.
	var hair_style: String = _opts.get("hair", "")
	if hair_style != "":
		if not egg:
			push_error("--hair needs the egg head")
			return 1
		_hc = egg_centre
		_hr = egg_radii
		_hf = fwd
		_hair.clear()
		if not _build_hair(hair_style, cm, float(_opts.get("hair-height", "8")) * cm,
				joint["UpperArm.L"].y):
			push_error("--hair: no style %s" % hair_style)
			return 1
		var hair_bone: int = r_bones.find_bone("Head")
		var h_low: Vector3 = Vector3(INF, INF, INF)
		var h_high: Vector3 = -h_low
		for p: Vector3 in _hair:
			points.append(p)
			colours.append(PAINT["hair"])
			weights_out.append({hair_bone: 1.0})
			egg_normal.append(Vector3.ZERO)
			egg_w.append(0.0)
			h_low = h_low.min(p)
			h_high = h_high.max(p)
		print("hair: %s, %d triangles, egg centre %s radii %s, hair box %s .. %s, crown %.1f, shoulder %.1f" % [
			hair_style, _hair.size() / 3, egg_centre, egg_radii, h_low, h_high,
			egg_centre.y + egg_radii.y, joint["UpperArm.L"].y])

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

# --- Hair (P2-6). Shapes are written in the head's own frame: a point `u` is in
# egg radii from the egg's centre (x across, y up, z toward the face), so 1 on
# an axis is the egg's surface. Everything is a triangle soup in root space.
var _hc: Vector3 = Vector3.ZERO
var _hr: Vector3 = Vector3.ONE
var _hf: float = 1.0
var _hair: PackedVector3Array = []

func _hp(u: Vector3, k: float = 1.0) -> Vector3:
	return _hc + Vector3(u.x * _hr.x, u.y * _hr.y, u.z * _hr.z * _hf) * k

## One triangle, wound so its front faces away from `inside`.
func _tri(a: Vector3, b: Vector3, c: Vector3, inside: Vector3) -> void:
	var face: Vector3 = (c - a).cross(b - a)
	if face.length_squared() < 1e-9:
		return
	if face.dot((a + b + c) / 3.0 - inside) < 0.0:
		_hair.append_array(PackedVector3Array([a, c, b]))
	else:
		_hair.append_array(PackedVector3Array([a, b, c]))

func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, inside: Vector3) -> void:
	_tri(a, b, c, inside)
	_tri(a, c, d, inside)

## A layer of hair lying on the egg wherever `on` (unit direction -> 0..1) says:
## a patch of a slightly larger egg whose edge dips under the head's surface, so
## it needs no rim and leaves no gap.
func _hair_cap(on: Callable, outer: float, rings: int = 12, segs: int = 16) -> void:
	var grid: Array[PackedVector3Array] = []
	var cover: Array[PackedFloat32Array] = []
	for i: int in rings + 1:
		var phi: float = PI * i / rings
		var row: PackedVector3Array = []
		var ms: PackedFloat32Array = []
		for j: int in segs:
			var th: float = TAU * j / segs
			var d: Vector3 = Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			var m: float = clampf(on.call(d), 0.0, 1.0)
			row.append(_hp(d, lerpf(0.95, outer, m)))
			ms.append(m)
		grid.append(row)
		cover.append(ms)
	for i: int in rings:
		for j: int in segs:
			var k: int = (j + 1) % segs
			if maxf(maxf(cover[i][j], cover[i][k]), maxf(cover[i + 1][j], cover[i + 1][k])) <= 0.0:
				continue
			_quad(grid[i][j], grid[i][k], grid[i + 1][k], grid[i + 1][j], _hc)

## A strip of hair over the head: side to side (round z, `offset` along z) or
## front to back (round x). Angles are from the crown, in degrees; `lift` (0..1
## along the strip -> root units) raises its top; `top_k` narrows the top.
func _hair_arc(front_to_back: bool, offset: float, half_w: float, from_deg: float, to_deg: float,
		lift: Callable, top_k: float, outer: float, segs: int) -> void:
	var rho: float = sqrt(maxf(0.0, 1.0 - offset * offset))
	var side: Vector3 = Vector3.RIGHT if front_to_back else Vector3.BACK
	var stations: Array[PackedVector3Array] = []  # base l, base r, top r, top l
	for k: int in segs + 1:
		var t: float = float(k) / segs
		var ang: float = deg_to_rad(lerpf(from_deg, to_deg, t))
		var mid: Vector3 = Vector3(rho * sin(ang), rho * cos(ang), offset)
		if front_to_back:
			mid = Vector3(offset, rho * cos(ang), rho * sin(ang))
		var up: Vector3 = (_hp(mid) - _hc).normalized() * float(lift.call(t))
		stations.append(PackedVector3Array([_hp(mid - side * half_w, 0.95), _hp(mid + side * half_w, 0.95),
			_hp(mid + side * half_w * top_k, outer) + up, _hp(mid - side * half_w * top_k, outer) + up]))
	for k: int in segs:
		var a: PackedVector3Array = stations[k]
		var b: PackedVector3Array = stations[k + 1]
		var inside: Vector3 = Vector3.ZERO
		for p: Vector3 in a + b:
			inside += p / 8.0
		_quad(a[0], a[3], b[3], b[0], inside)
		_quad(a[1], a[2], b[2], b[1], inside)
		_quad(a[3], a[2], b[2], b[3], inside)
		if k == 0:
			_quad(a[0], a[1], a[2], a[3], inside)
		if k == segs - 1:
			_quad(b[0], b[1], b[2], b[3], inside)

## A solid egg shape: `radii` along `turn`'s axes, about `at` (root space).
func _hair_blob(at: Vector3, radii: Vector3, turn: Basis, rings: int = 5, segs: int = 8) -> void:
	var grid: Array[PackedVector3Array] = []
	for i: int in rings + 1:
		var phi: float = PI * i / rings
		var row: PackedVector3Array = []
		for j: int in segs:
			var th: float = TAU * j / segs
			row.append(at + turn * (Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th)) * radii))
		grid.append(row)
	for i: int in rings:
		for j: int in segs:
			var k: int = (j + 1) % segs
			_quad(grid[i][j], grid[i][k], grid[i + 1][k], grid[i + 1][j], at)

## A column turned on a lathe: `profile` is [distance along `axis`, radius] rows
## from `base`; the last row closes it to a point.
func _hair_lathe(base: Vector3, axis: Vector3, profile: Array[Vector2], segs: int = 10) -> void:
	var across: Vector3 = axis.cross(Vector3.RIGHT).normalized()
	var other: Vector3 = axis.cross(across).normalized()
	var grid: Array[PackedVector3Array] = []
	for row: Vector2 in profile:
		var ring: PackedVector3Array = []
		for j: int in segs:
			var th: float = TAU * j / segs
			ring.append(base + axis * row.x + (across * cos(th) + other * sin(th)) * row.y)
		grid.append(ring)
	for i: int in profile.size() - 1:
		var inside: Vector3 = base + axis * (profile[i].x + profile[i + 1].x) * 0.5
		for j: int in segs:
			var k: int = (j + 1) % segs
			_quad(grid[i][j], grid[i][k], grid[i + 1][k], grid[i + 1][j], inside)

## Top and back of the head: the hairline runs from the top of the forehead,
## past the ears at the egg's middle height, down to the nape.
func _on_top_back(d: Vector3) -> float:
	return smoothstep(-0.08, 0.08, d.y - (0.55 * d.z + 0.02))

## A horseshoe round the sides and back: none on the forehead or the crown.
func _on_horseshoe(d: Vector3) -> float:
	var low: float = 0.4 * minf(d.z, 0.0) - 0.05
	return smoothstep(low - 0.08, low + 0.08, d.y) * (1.0 - smoothstep(0.42, 0.58, d.y)) \
		* (1.0 - smoothstep(0.2, 0.45, d.z))

func _flat(_t: float) -> float:
	return 0.0

var _crest: float = 0.0

func _crest_at(t: float) -> float:
	return _crest * sqrt(maxf(0.0, sin(PI * t)))

## The five styles (P2-6 brief). `cm` is one centimetre in root units, `height`
## the mohawk's, `shoulder_y` where the long pigtails must stop. False = unknown.
func _build_hair(style: String, cm: float, height: float, shoulder_y: float) -> bool:
	match style:
		"combover":
			_hair_cap(_on_horseshoe, 1.07)
			# Three thin slabs laid across the bald crown, bare head between them.
			for z: float in [0.38, 0.05, -0.28]:
				_hair_arc(false, z, 0.085, -64.0, 64.0, _flat, 1.0, 1.09, 6)
		"beehive":
			# PT2-8: a tall stiff tower, ~34 cm over the crown, fattest two thirds
			# up, a rounded top, leaning back 12 deg.
			_hair_cap(_on_top_back, 1.08)
			var lean: float = deg_to_rad(12.0)
			var axis: Vector3 = Vector3(0.0, cos(lean), -sin(lean) * _hf)
			var top: float = 0.55 * _hr.y
			var r: float = _hr.x
			var profile: Array[Vector2] = [Vector2(0.0, 0.92 * r), Vector2(top + 3.0 * cm, 0.96 * r),
				Vector2(top + 12.0 * cm, 1.01 * r), Vector2(top + 19.0 * cm, 1.05 * r),
				Vector2(top + 25.0 * cm, 1.0 * r), Vector2(top + 28.5 * cm, 0.9 * r),
				Vector2(top + 31.0 * cm, 0.72 * r), Vector2(top + 32.8 * cm, 0.46 * r),
				Vector2(top + 33.7 * cm, 0.22 * r), Vector2(top + 34.0 * cm, 0.0)]
			_hair_lathe(_hp(Vector3(0.0, 0.45, -0.12)), axis, profile, 12)
		"mohawk":
			# One ridge down the middle, top of the forehead to the nape, no cap.
			# PT2-8: a wider base (0.24 -> 0.32), height from --hair-height.
			_crest = height
			_hair_arc(true, 0.0, 0.32, 52.0, -125.0, _crest_at, 0.6, 1.0, 10)
		"pigtails_long":
			_hair_cap(_on_top_back, 1.05)
			# PT2-8: two shabby, uneven bunches from behind the ears. One side
			# hangs to just above the shoulder nearly straight; the other stops
			# 6 cm higher, thinner, and splays out. Each is two offset blobs.
			# (The member's Head scale in the theme stretches them ~17 % further down.)
			var top_y: float = _hc.y + 0.2 * _hr.y
			# [side, cm above the shoulder, tilt deg, radius k, wobble cm]
			for row: Array in [[-1.0, 8.0, 6.0, 1.08, 0.8], [1.0, 14.0, 22.0, 0.82, -0.9]]:
				var s: float = row[0]
				var pivot: Vector3 = _hp(Vector3(s * 0.85, 0.0, -0.45))
				pivot.x += s * 1.0 * cm
				pivot.y = top_y
				var length: float = top_y - (shoulder_y + float(row[1]) * cm)
				var tilt: float = deg_to_rad(float(row[2])) * s
				var k: float = row[3]
				var down: Vector3 = Basis(Vector3.BACK, tilt) * Vector3.DOWN
				_hair_blob(pivot + down * length * 0.3, Vector3(2.8 * cm * k, length * 0.33, 3.0 * cm * k),
					Basis(Vector3.BACK, tilt))
				# The lower blob kinks a little further out and back.
				var tilt2: float = tilt + deg_to_rad(7.0) * s
				var down2: Vector3 = Basis(Vector3.BACK, tilt2) * Vector3.DOWN
				var low: Vector3 = pivot + down * length * 0.5 + down2 * length * 0.22
				low += Vector3(s * float(row[4]) * cm, 0.0, -0.6 * cm * _hf)
				_hair_blob(low, Vector3(2.5 * cm * k, length * 0.27, 2.7 * cm * k), Basis(Vector3.BACK, tilt2))
		"pigtails_short":
			_hair_cap(_on_top_back, 1.05)
			# PT2-8: two short, uneven bunches set high: one sticks out 25 deg up,
			# the other sits a little lower, nearly flat (5 deg) and 30 % shorter.
			# Each is a bunch plus a smaller tuft kinked off its tip.
			# [side, up deg, length k, root height]
			for row: Array in [[-1.0, 25.0, 1.0, 0.42], [1.0, 5.0, 0.7, 0.34]]:
				var s: float = row[0]
				var up: float = row[1]
				var k: float = row[2]
				var out: Vector3 = Vector3(s * cos(deg_to_rad(up)), sin(deg_to_rad(up)), 0.0)
				var at: Vector3 = _hp(Vector3(s * 0.88, float(row[3]), -0.1)) + out * 4.0 * cm * k
				# The blob's long (y) axis is turned to lie along `out`.
				_hair_blob(at, Vector3(3.8 * cm, 5.5 * cm * k, 3.8 * cm),
					Basis(Vector3.BACK, -s * deg_to_rad(90.0 - up)))
				var up2: float = up - 18.0
				var out2: Vector3 = Vector3(s * cos(deg_to_rad(up2)), sin(deg_to_rad(up2)), 0.0)
				var tip: Vector3 = at + out * 4.2 * cm * k + out2 * 2.2 * cm + Vector3(0.0, 0.0, -0.8 * cm * _hf)
				_hair_blob(tip, Vector3(2.4 * cm, 3.2 * cm * k, 2.6 * cm),
					Basis(Vector3.BACK, -s * deg_to_rad(90.0 - up2)))
		_:
			return false
	return true

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
func _egg_head(source: PackedVector3Array, joint_y: float, height: float, joint_z: float = 0.0) -> Dictionary:
	var points: PackedVector3Array = source.duplicate()
	var normals: PackedVector3Array = []
	normals.resize(points.size())
	var weights: PackedFloat32Array = []
	weights.resize(points.size())
	var result: Dictionary = {"points": points, "normals": normals, "weights": weights,
		"centre": Vector3.ZERO, "radii": Vector3.ONE}
	# Fully on the egg from the joint itself: in the low-poly men the eyes sit
	# only ~7 cm, the nose ~4 and the mouth ~1 above the Head joint, so a rise
	# of 3 % of height left nose and mouth half-blended (the P2-1b smudge).
	var rise: float = float(_opts.get("egg-rise", "0")) * height
	var blend: float = float(_opts.get("egg-blend", "0.03")) * height
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
	# A bun or ponytail stretches the box backwards and the egg with it (the
	# dress body: a head like a loaf from the side). The depth is capped at
	# `egg-depth-max` times the width, about the Head joint.
	var deepest: float = float(_opts.get("egg-depth-max", "1.45")) * radii.x
	print("egg: radii %s, depth/width %.2f" % [radii, radii.z / radii.x])
	if deepest > 0.0 and radii.z > deepest:
		radii.z = deepest
		centre.z = clampf(joint_z, low.z + radii.z, high.z - radii.z)
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
	result["centre"] = centre
	result["radii"] = radii
	return result

## One level of 1-to-4 subdivision of every triangle with a corner on the egg
## (egg weight > 0), over the triangle soup. An edge's new point is its chord
## midpoint moved onto the egg by the mean egg weight of its ends, so an edge
## with both ends off the egg stays straight (no crack against an undivided
## neighbour) and both triangles sharing an edge make the same point.
func _subdivide_egg(soup: Dictionary, centre: Vector3, radii: Vector3) -> Dictionary:
	var points: PackedVector3Array = soup["points"]
	var colours: PackedColorArray = soup["colours"]
	var weights: Array[Dictionary] = soup["weights"]
	var en: PackedVector3Array = soup["egg_normal"]
	var ew: PackedFloat32Array = soup["egg_w"]
	var out: Dictionary = {"points": PackedVector3Array(), "colours": PackedColorArray(),
		"weights": [] as Array[Dictionary], "egg_normal": PackedVector3Array(), "egg_w": PackedFloat32Array()}
	var p_out: PackedVector3Array = []
	var c_out: PackedColorArray = []
	var w_out: Array[Dictionary] = []
	var n_out: PackedVector3Array = []
	var e_out: PackedFloat32Array = []
	for t: int in points.size() / 3:
		var a: int = t * 3
		var corners: Array = []
		for k: int in 3:
			corners.append([points[a + k], colours[a + k], weights[a + k], en[a + k], ew[a + k]])
		if ew[a] <= 0.0 and ew[a + 1] <= 0.0 and ew[a + 2] <= 0.0:
			for c: Array in corners:
				p_out.append(c[0]); c_out.append(c[1]); w_out.append(c[2]); n_out.append(c[3]); e_out.append(c[4])
			continue
		var mids: Array = []
		for k: int in 3:
			mids.append(_egg_mid(corners[k], corners[(k + 1) % 3], centre, radii))
		# Corners 0,1,2 with midpoints m01, m12, m20; same winding as the parent.
		for tri: Array in [[corners[0], mids[0], mids[2]], [mids[0], corners[1], mids[1]],
				[mids[2], mids[1], corners[2]], [mids[0], mids[1], mids[2]]]:
			for c: Array in tri:
				p_out.append(c[0]); c_out.append(c[1]); w_out.append(c[2]); n_out.append(c[3]); e_out.append(c[4])
	out["points"] = p_out
	out["colours"] = c_out
	out["weights"] = w_out
	out["egg_normal"] = n_out
	out["egg_w"] = e_out
	return out

## The new corner between two soup corners [point, colour, weights, egg normal,
## egg weight]. Symmetric in its two ends up to the order of the sums, which is
## made canonical so both sides of an edge agree exactly.
func _egg_mid(x: Array, y: Array, centre: Vector3, radii: Vector3) -> Array:
	var p: Vector3 = x[0]
	var q: Vector3 = y[0]
	if q < p:
		var swap: Array = x
		x = y
		y = swap
	var chord: Vector3 = ((x[0] as Vector3) + (y[0] as Vector3)) * 0.5
	var w: float = (float(x[4]) + float(y[4])) * 0.5
	var d: Vector3 = (chord - centre) / radii
	var on: Vector3 = centre + d.normalized() * radii if d.length() > 1e-6 else chord
	var at: Vector3 = chord.lerp(on, w)
	var normal: Vector3 = ((on - centre) / (radii * radii)).normalized()
	var mixed: Dictionary = {}
	for side: Dictionary in [x[2], y[2]]:
		for rb: int in side:
			mixed[rb] = float(mixed.get(rb, 0.0)) + float(side[rb]) * 0.5
	var colour: Color = (x[1] as Color).lerp(y[1] as Color, 0.5)
	return [at, colour, mixed, normal, w]

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
	if key.contains("jacket") or key.contains("shirt2") or key.contains("tie") or key.contains("detail"):
		return "trim"
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
