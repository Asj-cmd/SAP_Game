extends SceneTree
## Builds the figures' one animation set (P2-2): `res://art/characters/figure_anims.res`,
## an AnimationLibrary for the baked figure rig, from the Quaternius Universal
## Animation Library (CC0, D10; same rig as the bodies).
##
##   node autobuild/run_tool.mjs build_figure_anims [-- --src=<UAL1_Standard.glb>] [--figure=res://….gltf] [--list]
##
## Reads the library at RUNTIME (GLTFDocument), so the 7.6 MB .glb never has to
## be in the project; it stays in the gitignored autobuild/Incoming/x/ (D10).
##
## What goes into every clip, and why:
##  - ROTATION tracks for the body's 21 big bones (pelvis, spine, neck, head,
##    arms, legs). Rotations apply as they are: the bake (autobuild/figure_bake.mjs)
##    put this library's own idle rotations into the bodies' rest pose, so the two
##    rigs agree. Fingers keep the rest pose (stiff hands, D2), leaf bones are
##    skipped.
##  - ONE position track, the pelvis, as a CHANGE from the library's idle frame 0
##    scaled by figure leg length / library leg length (the bodies' legs are ~7 %
##    longer), so a crouch drops the hips far enough for these legs. Every other
##    bone keeps the body's own bone lengths.
##  - NO scale tracks: the theme's "slightly off" nudges and the family's sizes
##    are bone POSE scales (ArtTheme.shape_figure) and must survive playback.
##  - Clips the sim moves vertically (jumps) may dip the pelvis but never raise
##    it: the sim owns the body's height (`no_lift`).
##  - Arm poses that are not in the library (cash held overhead like a brick,
##    the panic run's arms up, the two-handed push of a throw) are solved by
##    two-bone IK on the figure's own rest skeleton, stored as local rotations of
##    clavicle-relative arm bones, so they ride the torso of whatever clip they
##    are laid over.
##  - Metadata per locomotion clip: `stride_speed`, the speed (model units / s,
##    i.e. cm at the model's natural size, BEFORE ArtTheme.shape_figure scales it)
##    at which the feet do not slide, measured from the library's root-motion
##    copy. The driver (P2-3) sets playback speed = body speed / (stride_speed ×
##    figure scale).
##
## The table CLIPS is the whole set. Names are what the driver plays.

const FPS: float = 30.0
const OUT: String = "res://art/characters/figure_anims.res"
## The body whose skeleton the clips are built against (pelvis rest height, leg
## ratio, IK arm poses). P2-1b: the re-rigged low-poly man; `--figure=` to change.
const FIGURE: String = "res://art/characters/figure_lp_male.gltf"
const SRC_DIR: String = "../autobuild/Incoming/x/Universal Animation Library[Standard]/Unreal-Godot/"
const SRC_FILE: String = "UAL1_Standard.glb"
const RM_FILE: String = "UAL1_Standard_RM.glb"

const BONES: Array[String] = [
	"pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "Head",
	"clavicle_l", "upperarm_l", "lowerarm_l", "hand_l",
	"clavicle_r", "upperarm_r", "lowerarm_r", "hand_r",
	"thigh_l", "calf_l", "foot_l", "ball_l",
	"thigh_r", "calf_r", "foot_r", "ball_r",
]
const ARM_BONES: Array[String] = [
	"clavicle_l", "upperarm_l", "lowerarm_l", "hand_l",
	"clavicle_r", "upperarm_r", "lowerarm_r", "hand_r",
]

## One row per clip.
##   src      library clip; from/to trim it (seconds; to < 0 = its end)
##   still    true = one key at `from` (D9: standing still is fully motionless)
##   loop     loops
##   arms     "" (the clip's own), a pose name from _arm_poses, or keys
##            [[t, pose], ...] (seconds from the clip's start; "clip" = its own)
##   carry    also emit "carry_<name>" with the arms in the carry pose
##            (`carry_arms` names another pose, e.g. carry_crouch)
##   no_lift  the pelvis may dip, never rise (the sim moves the body up)
const CLIPS: Array[Dictionary] = [
	{"name": "idle", "src": "Idle_Loop", "still": true, "carry": true},
	{"name": "walk", "src": "Walk_Formal_Loop", "loop": true, "carry": true},
	{"name": "walk_loose", "src": "Walk_Loop", "loop": true},
	{"name": "jog", "src": "Jog_Fwd_Loop", "loop": true, "carry": true},
	# No carry_sprint: the sprint's lean tips overhead arms forward, and a
	# panicking carrier runs as carry_jog, faster (D9: the cash is already overhead).
	{"name": "sprint", "src": "Sprint_Loop", "loop": true},
	# The jog, not the sprint: the sprint's deep athletic lean is acting (D2).
	{"name": "panic_run", "src": "Jog_Fwd_Loop", "loop": true, "arms": "panic"},
	# Crouch: the library holds its hands up by the face, a sneak (acting, D2);
	# here the arms hang stiff ("rest" = the idle arms, riding the bent torso).
	{"name": "crouch_idle", "src": "Crouch_Idle_Loop", "still": true, "arms": "rest", "carry": true, "carry_arms": "carry_crouch"},
	{"name": "crouch_walk", "src": "Crouch_Fwd_Loop", "loop": true, "arms": "rest", "carry": true, "carry_arms": "carry_crouch"},
	# Jump, made deadpan (D2/D9): the library's is a superhero leap (a wind-up
	# crouch the instant sim jump would not wait for, one arm flung up, a deep
	# landing squat). Kept: lift-off to tuck, ONE held air pose, and the second
	# half of the landing (a shallow dip back to standing); arms stiff throughout.
	{"name": "jump_start", "src": "Jump_Start", "from": 0.27, "to": 0.6, "no_lift": true, "arms": "rest", "carry": true},
	{"name": "jump_air", "src": "Jump_Start", "from": 0.6, "still": true, "no_lift": true, "arms": "rest", "carry": true},
	{"name": "jump_land", "src": "Jump_Land", "from": 0.75, "to": -1.0, "no_lift": true, "arms": "rest", "carry": true},
	{"name": "grab", "src": "PickUp_Table"},
	{"name": "interact", "src": "Interact"},
	{"name": "throw", "src": "Idle_Loop", "still_body": true, "to": 0.9,
		"arms": [[0.0, "carry"], [0.12, "throw_back"], [0.3, "throw_push"], [0.5, "throw_push"], [0.9, "rest"]]},
	{"name": "arms_carry", "src": "Idle_Loop", "still": true, "arms": "carry", "arms_only": true},
	{"name": "arms_panic", "src": "Idle_Loop", "still": true, "arms": "panic", "arms_only": true},
]

var _opts: Dictionary[String, String] = {}

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var eq: int = arg.find("=")
			if eq < 0:
				_opts[arg.substr(2)] = "true"
			else:
				_opts[arg.substr(2, eq - 2)] = arg.substr(eq + 1)
	quit(_run())

func _run() -> int:
	var dir: String = ProjectSettings.globalize_path("res://").path_join(SRC_DIR)
	var src_path: String = _opts.get("src", dir.path_join(SRC_FILE))
	var rm_path: String = _opts.get("rm", dir.path_join(RM_FILE))
	var source: Node = _read(src_path)
	if source == null:
		return 1
	var source_player: AnimationPlayer = _find(source, "AnimationPlayer") as AnimationPlayer
	var source_bones: Skeleton3D = _find(source, "Skeleton3D") as Skeleton3D
	if _opts.has("list"):
		for clip: StringName in source_player.get_animation_list():
			print("  %s %.2f" % [clip, source_player.get_animation(clip).length])
		return 0
	var figure: Node = _read(ProjectSettings.globalize_path(_opts.get("figure", FIGURE)))
	if figure == null:
		return 1
	var bones: Skeleton3D = _find(figure, "Skeleton3D") as Skeleton3D
	var skeleton_path: String = String(_path_from(figure, bones))
	var leg_ratio: float = _leg(bones) / _leg(source_bones)
	print("figure skeleton at '%s', leg ratio %.3f (figure / library)" % [skeleton_path, leg_ratio])

	var rm: Node = _read(rm_path)
	var rm_player: AnimationPlayer = null if rm == null else _find(rm, "AnimationPlayer") as AnimationPlayer

	var poses: Dictionary[String, Dictionary] = _arm_poses(bones,
		source_player.get_animation(&"Crouch_Idle_Loop"))
	var idle: Animation = source_player.get_animation(&"Idle_Loop")
	var pelvis_zero: Vector3 = _position_at(idle, "pelvis", 0.0)
	var pelvis: int = bones.find_bone("pelvis")
	var pelvis_rest: Vector3 = bones.get_bone_rest(pelvis).origin
	# The pelvis track is in its parent's (root's) space: which way is up there.
	var root_rest: Basis = bones.get_bone_global_rest(bones.get_bone_parent(pelvis)).basis
	var up_local: Vector3 = (root_rest.inverse() * Vector3.UP).normalized()

	var library: AnimationLibrary = AnimationLibrary.new()
	var rows: Array[Dictionary] = []
	for row: Dictionary in CLIPS:
		rows.append(row)
		if row.get("carry", false):
			var carried: Dictionary = row.duplicate()
			carried["name"] = "carry_" + row["name"]
			carried["arms"] = row.get("carry_arms", "carry")
			carried.erase("carry")
			rows.append(carried)
	for row: Dictionary in rows:
		var from_clip: Animation = source_player.get_animation(StringName(row["src"]))
		if from_clip == null:
			push_error("no library clip %s" % row["src"])
			return 1
		var made: Animation = _build(row, from_clip, skeleton_path, poses,
			pelvis_rest, pelvis_zero, leg_ratio, up_local)
		if rm_player != null and row.get("loop", false) and rm_player.has_animation(StringName(row["src"])):
			var travel: float = _travel(rm_player.get_animation(StringName(row["src"])))
			if travel > 0.0:
				# Library metres -> the figure's model units (armature x100), legs scaled.
				made.set_meta(&"stride_speed", travel * 100.0 * leg_ratio)
		library.add_animation(StringName(row["name"]), made)
		print("  %-20s %5.2f s  %3d keys%s%s" % [row["name"], made.length,
			made.track_get_key_count(0), "  loop" if made.loop_mode != Animation.LOOP_NONE else "",
			"  stride %.0f/s" % made.get_meta(&"stride_speed") if made.has_meta(&"stride_speed") else ""])
	library.set_meta(&"skeleton_path", skeleton_path)
	var failed: Error = ResourceSaver.save(library, OUT)
	if failed != OK:
		push_error("could not save %s (%d)" % [OUT, failed])
		return 1
	# A readable summary next to it: what changed in a re-build shows in a diff,
	# and autobuild/anim_sheet.mjs reads the lengths from it.
	var summary: Dictionary = {}
	for clip: StringName in library.get_animation_list():
		var each: Animation = library.get_animation(clip)
		summary[String(clip)] = {"length": snappedf(each.length, 0.001),
			"loop": each.loop_mode != Animation.LOOP_NONE,
			"stride_speed": snappedf(float(each.get_meta(&"stride_speed", 0.0)), 0.1)}
	var notes: FileAccess = FileAccess.open(OUT.get_basename() + ".json", FileAccess.WRITE)
	notes.store_string(JSON.stringify(summary, "  ", false) + "\n")
	notes.close()
	print("wrote %s: %d clips" % [OUT, library.get_animation_list().size()])
	for node: Node in [source, figure, rm]:
		if node != null:
			node.free()
	return 0

func _build(row: Dictionary, source: Animation, skeleton_path: String,
		poses: Dictionary[String, Dictionary], pelvis_rest: Vector3, pelvis_zero: Vector3,
		leg_ratio: float, up_local: Vector3) -> Animation:
	var start: float = float(row.get("from", 0.0))
	var end: float = float(row.get("to", -1.0))
	if end < 0.0:
		end = source.length
	var still: bool = row.get("still", false)
	var still_body: bool = row.get("still_body", false)
	var loop: bool = row.get("loop", false)
	var arms_only: bool = row.get("arms_only", false)
	var length: float = 1.0 / FPS if still else end - start
	var count: int = 1 if still else (int(round(length * FPS)) if loop else int(round(length * FPS)) + 1)
	var made: Animation = Animation.new()
	made.length = length
	made.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var arms: Variant = row.get("arms", "")
	for bone: String in BONES:
		var is_arm: bool = ARM_BONES.has(bone)
		if arms_only and not is_arm:
			continue
		var track: int = made.add_track(Animation.TYPE_ROTATION_3D)
		made.track_set_path(track, NodePath("%s:%s" % [skeleton_path, bone]))
		for k: int in count:
			var t: float = minf(k / FPS, length)
			var at: float = start if (still or still_body) else start + t
			var turn: Quaternion = _rotation_at(source, bone, at)
			if is_arm and not (arms is String and arms == ""):
				turn = _arm_rotation(arms, bone, t, poses, source, start)
			made.rotation_track_insert_key(track, t, turn)
	if not arms_only:
		var track: int = made.add_track(Animation.TYPE_POSITION_3D)
		made.track_set_path(track, NodePath("%s:pelvis" % skeleton_path))
		for k: int in count:
			var t: float = minf(k / FPS, length)
			var at: float = start if (still or still_body) else start + t
			var change: Vector3 = (_position_at(source, "pelvis", at) - pelvis_zero) * leg_ratio
			if row.get("no_lift", false):
				var lift: float = change.dot(up_local)
				if lift > 0.0:
					change -= up_local * lift
			made.position_track_insert_key(track, t, pelvis_rest + change)
	return made

## The arm bone's rotation at `t` for an `arms` entry: one pose, or keys.
func _arm_rotation(arms: Variant, bone: String, t: float,
		poses: Dictionary[String, Dictionary], source: Animation, start: float) -> Quaternion:
	if arms is String:
		return _pose_rotation(String(arms), bone, poses, source, start + t)
	var keys: Array = arms
	var before: Array = keys[0]
	var after: Array = keys[keys.size() - 1]
	for i: int in keys.size():
		var key: Array = keys[i]
		if float(key[0]) <= t:
			before = key
			after = keys[mini(i + 1, keys.size() - 1)]
	var a: Quaternion = _pose_rotation(String(before[1]), bone, poses, source, start + t)
	var b: Quaternion = _pose_rotation(String(after[1]), bone, poses, source, start + t)
	var span: float = float(after[0]) - float(before[0])
	if span <= 0.0:
		return a
	# Smoothstep between keys: arms that move stiffly, without a snap at each key.
	var w: float = clampf((t - float(before[0])) / span, 0.0, 1.0)
	return a.slerp(b, w * w * (3.0 - 2.0 * w))

func _pose_rotation(pose: String, bone: String, poses: Dictionary[String, Dictionary],
		source: Animation, at: float) -> Quaternion:
	if pose == "clip":
		return _rotation_at(source, bone, at)
	var table: Dictionary = poses.get(pose, {})
	if not table.has(bone):
		push_error("no arm pose %s for %s" % [pose, bone])
		return Quaternion.IDENTITY
	return table[bone]

## The arm poses the library does not have, by two-bone IK on the figure's rest
## skeleton (the idle stance). Each is { bone name: local rotation }. Targets are
## in the skeleton's own space, measured from the body (shoulder height, reach).
func _arm_poses(bones: Skeleton3D, crouch: Animation) -> Dictionary[String, Dictionary]:
	bones.reset_bone_poses()
	var up: Vector3 = Vector3.UP
	var head: Vector3 = _at(bones, "Head")
	var pelvis: Vector3 = _at(bones, "pelvis")
	var forward: Vector3 = _at(bones, "ball_l") - _at(bones, "foot_l")
	forward = Vector3(forward.x, 0.0, forward.z).normalized()
	var reach: float = _at(bones, "upperarm_l").distance_to(_at(bones, "lowerarm_l")) \
		+ _at(bones, "lowerarm_l").distance_to(_at(bones, "hand_l"))
	print("arm reach %.3f, head %.3f, pelvis %.3f, forward %s" % [reach, head.y, pelvis.y, forward])
	var poses: Dictionary[String, Dictionary] = {}
	var rest: Dictionary = {}
	for bone: String in ARM_BONES:
		rest[bone] = bones.get_bone_rest(bones.find_bone(bone)).basis.get_rotation_quaternion()
	poses["rest"] = rest
	# Carrying while crouched: the arm poses are torso-relative, and the crouch
	# bends the torso ~80 degrees, so the standing carry pointed the arms straight
	# AHEAD like a battering ram (first sheet). Solved instead on the skeleton bent
	# into the crouch, hands just over the head in world up.
	_bend_into(bones, crouch, 0.0)
	var crouched_head: Vector3 = _at(bones, "Head")
	var low: Dictionary = {}
	for side: String in ["l", "r"]:
		var outward: Vector3 = Vector3(signf(_at(bones, "upperarm_" + side).x - pelvis.x), 0.0, 0.0)
		var target: Vector3 = crouched_head + outward * 0.09 + up * 0.24 + forward * 0.04
		_solve_arm(bones, side, target, outward - up * 0.2, low)
	poses["carry_crouch"] = low
	bones.reset_bone_poses()
	# Each pose: per side, hand target = shoulder + (out, up, forward) in reach
	# fractions, and the way the elbow points.
	var specs: Dictionary[String, Array] = {
		# Cash held stiffly over the head like a brick (D9): hands together a
		# hand-width apart above the crown, elbows out to the sides.
		"carry": [Vector3(-0.30, 0.86, 0.10), Vector3(1.0, -0.2, -0.3)],
		# Panic run (D9): both arms straight up and a little wide, as if chased.
		# Aimed a little BACK in the rest torso, so they stand upright over the
		# run's forward lean instead of reaching ahead.
		"panic": [Vector3(0.26, 0.95, -0.12), Vector3(1.0, 0.0, -0.4)],
		# Throw: hands drawn back behind the head, then pushed forward together.
		"throw_back": [Vector3(-0.28, 0.66, -0.22), Vector3(1.0, -0.3, -0.4)],
		"throw_push": [Vector3(-0.26, 0.20, 0.92), Vector3(1.0, -0.6, 0.0)],
	}
	for pose: String in specs:
		var table: Dictionary = {}
		for side: String in ["l", "r"]:
			var shoulder: Vector3 = _at(bones, "upperarm_" + side)
			var outward: Vector3 = Vector3(signf(shoulder.x - pelvis.x), 0.0, 0.0)
			var aim: Vector3 = specs[pose][0]
			var bend: Vector3 = specs[pose][1]
			var target: Vector3 = shoulder + (outward * aim.x + up * aim.y + forward * aim.z) * reach
			var pole: Vector3 = outward * bend.x + up * bend.y + forward * bend.z
			_solve_arm(bones, side, target, pole, table)
		poses[pose] = table
	return poses

## Poses the body (not the arms) as `clip` at `t`: rotations only, which is all
## the arm IK needs to know where the shoulders and head are.
func _bend_into(bones: Skeleton3D, clip: Animation, t: float) -> void:
	bones.reset_bone_poses()
	for bone: String in BONES:
		if not ARM_BONES.has(bone):
			bones.set_bone_pose_rotation(bones.find_bone(bone), _rotation_at(clip, bone, t))
	bones.force_update_all_bone_transforms()

## Two-bone IK for one arm on the skeleton's CURRENT pose (arms at rest): writes
## local rotations for clavicle (unchanged), upper arm, forearm and hand
## (unchanged) into `table`.
func _solve_arm(bones: Skeleton3D, side: String, target: Vector3, pole: Vector3, table: Dictionary) -> void:
	var clav: int = bones.find_bone("clavicle_" + side)
	var upper: int = bones.find_bone("upperarm_" + side)
	var lower: int = bones.find_bone("lowerarm_" + side)
	var hand: int = bones.find_bone("hand_" + side)
	var shoulder: Transform3D = bones.get_bone_global_pose(upper)
	var s: Vector3 = shoulder.origin
	var e: Vector3 = bones.get_bone_global_pose(lower).origin
	var w: Vector3 = bones.get_bone_global_pose(hand).origin
	var l1: float = s.distance_to(e)
	var l2: float = e.distance_to(w)
	var reach: Vector3 = target - s
	var d: float = clampf(reach.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var u: Vector3 = reach.normalized()
	var a: float = acos(clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0))
	var v: Vector3 = (pole - u * pole.dot(u)).normalized()
	var elbow: Vector3 = s + l1 * (u * cos(a) + v * sin(a))
	var wrist: Vector3 = s + u * d
	var upper_global: Basis = Basis(Quaternion((e - s).normalized(), (elbow - s).normalized())) * shoulder.basis
	var clav_global: Basis = bones.get_bone_global_pose(clav).basis
	var lower_rest: Transform3D = bones.get_bone_rest(lower)
	var lower_global: Basis = upper_global * lower_rest.basis
	var along: Vector3 = (lower_global * bones.get_bone_rest(hand).origin).normalized()
	lower_global = Basis(Quaternion(along, (wrist - elbow).normalized())) * lower_global
	table["clavicle_" + side] = bones.get_bone_rest(clav).basis.get_rotation_quaternion()
	table["upperarm_" + side] = (clav_global.inverse() * upper_global).get_rotation_quaternion()
	table["lowerarm_" + side] = (upper_global.inverse() * lower_global).get_rotation_quaternion()
	table["hand_" + side] = bones.get_bone_rest(hand).basis.get_rotation_quaternion()

## Root travel per second of a root-motion clip, library metres.
func _travel(clip: Animation) -> float:
	var track: int = _track(clip, "root", Animation.TYPE_POSITION_3D)
	if track < 0 or clip.length <= 0.0:
		return 0.0
	var first: Vector3 = clip.position_track_interpolate(track, 0.0)
	var last: Vector3 = clip.position_track_interpolate(track, clip.length)
	return first.distance_to(last) / clip.length

func _rotation_at(clip: Animation, bone: String, t: float) -> Quaternion:
	var track: int = _track(clip, bone, Animation.TYPE_ROTATION_3D)
	return Quaternion.IDENTITY if track < 0 else clip.rotation_track_interpolate(track, t)

func _position_at(clip: Animation, bone: String, t: float) -> Vector3:
	var track: int = _track(clip, bone, Animation.TYPE_POSITION_3D)
	return Vector3.ZERO if track < 0 else clip.position_track_interpolate(track, t)

func _track(clip: Animation, bone: String, kind: Animation.TrackType) -> int:
	for i: int in clip.get_track_count():
		if clip.track_get_type(i) == kind and String(clip.track_get_path(i)).get_slice(":", 1) == bone:
			return i
	return -1

## Where a bone is in the skeleton's current pose (the rest pose unless _bend_into).
func _at(bones: Skeleton3D, bone: String) -> Vector3:
	return bones.get_bone_global_pose(bones.find_bone(bone)).origin

## Hip to ankle, rest pose.
func _leg(bones: Skeleton3D) -> float:
	return _at(bones, "thigh_l").distance_to(_at(bones, "calf_l")) \
		+ _at(bones, "calf_l").distance_to(_at(bones, "foot_l"))

func _read(path: String) -> Node:
	if not FileAccess.file_exists(path):
		push_error("missing %s (extract the Quaternius zips into autobuild/Incoming/x/, D10)" % path)
		return null
	var reader: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	var failed: Error = reader.append_from_file(path, state)
	if failed != OK:
		push_error("could not read %s (%d)" % [path, failed])
		return null
	return reader.generate_scene(state)

func _find(root: Node, kind: String) -> Node:
	if root.is_class(kind):
		return root
	var found: Array[Node] = root.find_children("*", kind, true, false)
	return null if found.is_empty() else found[0]

## The path from `top` down to `node` (neither needs to be in the tree).
func _path_from(top: Node, node: Node) -> NodePath:
	var names: PackedStringArray = PackedStringArray()
	var walk: Node = node
	while walk != null and walk != top:
		names.insert(0, String(walk.name))
		walk = walk.get_parent()
	return NodePath("/".join(names))
