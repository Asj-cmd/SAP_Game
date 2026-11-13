class_name FigureAnimator
extends RefCounted
## Drives one drawn figure from the simulation's state (P2-3).
##
## PRESENTATION ONLY. It reads a SimEntity and never writes one; nothing in the
## simulation reads anything here. What it reads is the state MovementSystem
## owns (motion_state, is_grounded, stance, velocity) and the carry/capture
## flags; it never infers motion by differencing drawn positions (SimEntity's
## MotionState comment says why).
##
## One AnimationTree per figure, advanced by hand from GreyBoxMain._render so the
## pose is current when the carried bundle is placed between the hands:
##
##   loco (Transition: every base clip, cross-faded)
##     -> rate (TimeScale: playback from the clip's stride_speed, so feet do not slide)
##     -> action (OneShot, ARMS ONLY: throw / grab / interact over whatever the legs do)
##     -> output
##
## The base clip is chosen by `base_clip` (a pure function of the state, so the
## rules for it are in one place). Clips and their deadpan picks are P2-2's
## (`tools/build_figure_anims.gd`).

## Horizontal speed (world units/s) under which a body counts as standing still.
## D9: standing still is fully motionless, so below this the idle frame holds.
const STILL_SPEED: float = 20.0
## Below this fraction of move_speed a standing body walks; above, it jogs.
## Keyboard input goes 0 -> move_speed at once, so this is for slow drifts (a
## bot easing into a spot, a stick held half-way).
const WALK_FRACTION: float = 0.45
## Above this fraction of move_speed it is a panic run (arms up). The sim's
## panic run (P4-1) is a real speed boost; reading the speed means it shows up
## here with no change.
const PANIC_FRACTION: float = 1.05
## A body off the ground for less than this is a step down a stair or a kerb,
## not a fall: the legs keep walking.
const AIR_GRACE: float = 0.12
## Cross-fade between base clips, seconds.
const XFADE: float = 0.15
## Playback-rate limits, so a near-still drift does not freeze mid-stride and a
## clip is never driven absurdly fast.
const MIN_RATE: float = 0.35
const MAX_RATE: float = 3.2
## One-shots: playback speed for each (interact is a 2 s clip; seize and free
## are instant in the sim, D9, so the reach is brief).
const ACTION_SPEED: Dictionary[StringName, float] = {
	&"throw": 1.2, &"grab": 1.6, &"interact": 2.2,
}

## The base clips the Transition holds. Order is the input order.
const BASE_CLIPS: Array[StringName] = [
	&"idle", &"walk", &"jog", &"panic_run", &"crouch_idle", &"crouch_walk",
	&"jump_start", &"jump_air", &"jump_land",
	&"carry_idle", &"carry_walk", &"carry_jog", &"carry_crouch_idle",
	&"carry_crouch_walk", &"carry_jump_start", &"carry_jump_air", &"carry_jump_land",
]
## Bones the one-shot layer may move. Legs, pelvis and spine stay with the base
## clip, so a throw on the run keeps running.
const ARM_BONES: Array[String] = [
	"clavicle_l", "upperarm_l", "lowerarm_l", "hand_l",
	"clavicle_r", "upperarm_r", "lowerarm_r", "hand_r",
]

var tree: AnimationTree = null
var skeleton: Skeleton3D = null
## The drawn figure (the node ArtTheme.shape_figure scaled): its scale turns a
## clip's stride_speed (model units) into world units.
var art: Node3D = null
var clip: StringName = &"idle"
var _act_clip: AnimationNodeAnimation = null
var _hand_l: int = -1
var _hand_r: int = -1
var _airborne_for: float = 0.0
var _jump_for: float = 0.0
var _land_left: float = 0.0
var _was_airborne: bool = false
var _was_carrying: bool = false
var _strides: Dictionary[StringName, float] = {}

## A driver for `art` (an instanced, shaped figure, already in the tree or about
## to be). Null when the animation set is not built or the figure has no
## skeleton where the set expects one: the figure then stands in its rest pose.
static func attach(art_root: Node3D) -> FigureAnimator:
	var clips: AnimationLibrary = FigureAnimation.library()
	if clips == null:
		return null
	var skeleton_path: String = String(clips.get_meta(&"skeleton_path", "Armature/Skeleton3D"))
	var bones: Skeleton3D = art_root.get_node_or_null(skeleton_path) as Skeleton3D
	if bones == null:
		return null
	for name: StringName in BASE_CLIPS:
		if not clips.has_animation(name):
			return null
	var made: FigureAnimator = FigureAnimator.new()
	made.art = art_root
	made.skeleton = bones
	made._hand_l = bones.find_bone("hand_l")
	made._hand_r = bones.find_bone("hand_r")
	for name: StringName in BASE_CLIPS:
		made._strides[name] = float(clips.get_animation(name).get_meta(&"stride_speed", 0.0))
	made._build_tree(clips, skeleton_path)
	return made

func _build_tree(clips: AnimationLibrary, skeleton_path: String) -> void:
	var root: AnimationNodeBlendTree = AnimationNodeBlendTree.new()
	var loco: AnimationNodeTransition = AnimationNodeTransition.new()
	loco.xfade_time = XFADE
	loco.input_count = BASE_CLIPS.size()
	for i: int in BASE_CLIPS.size():
		loco.set_input_name(i, String(BASE_CLIPS[i]))
		var play: AnimationNodeAnimation = AnimationNodeAnimation.new()
		play.animation = BASE_CLIPS[i]
		root.add_node(BASE_CLIPS[i], play, Vector2(0, i * 60))
	root.add_node(&"loco", loco, Vector2(300, 0))
	for i: int in BASE_CLIPS.size():
		root.connect_node(&"loco", i, BASE_CLIPS[i])
	var rate: AnimationNodeTimeScale = AnimationNodeTimeScale.new()
	root.add_node(&"rate", rate, Vector2(500, 0))
	root.connect_node(&"rate", 0, &"loco")

	_act_clip = AnimationNodeAnimation.new()
	_act_clip.animation = &"throw"
	root.add_node(&"act_clip", _act_clip, Vector2(300, 400))
	var act_rate: AnimationNodeTimeScale = AnimationNodeTimeScale.new()
	root.add_node(&"act_rate", act_rate, Vector2(500, 400))
	root.connect_node(&"act_rate", 0, &"act_clip")
	var action: AnimationNodeOneShot = AnimationNodeOneShot.new()
	action.fadein_time = 0.1
	action.fadeout_time = 0.2
	action.filter_enabled = true
	for bone: String in ARM_BONES:
		action.set_filter_path(NodePath("%s:%s" % [skeleton_path, bone]), true)
	root.add_node(&"action", action, Vector2(700, 0))
	root.connect_node(&"action", 0, &"rate")
	root.connect_node(&"action", 1, &"act_rate")
	root.connect_node(&"output", 0, &"action")

	tree = AnimationTree.new()
	tree.name = "FigureAnimator"
	tree.add_animation_library(&"", clips)
	tree.tree_root = root
	# Advanced by hand (`update`), so the pose is current when it is read.
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	art.add_child(tree)
	tree.root_node = NodePath("..")
	tree.active = true
	tree.set(&"parameters/rate/scale", 1.0)

## The base clip for a body in `entity`'s state, moving at `speed` horizontally
## (world units/s), against the tuning's `move_speed`. `airborne_for` is how
## long it has been off the ground (AIR_GRACE), `jump_for` how long since it
## left it upward, `land_left` how much of a landing is still to play.
## Static and pure: the whole choice in one place.
static func base_clip(entity: SimEntity, carrying: bool, captured: bool, speed: float,
		move_speed: float, airborne_for: float, jump_for: float, land_left: float) -> StringName:
	var carry: String = "carry_" if carrying else ""
	var crouched: bool = entity.stance == SimEntity.Stance.CROUCHED
	if captured or entity.motion_state == SimEntity.MotionState.HELD:
		# P4-3 drives a jailed body's run-in-place from its input; until then
		# it stands.
		return StringName(carry + "idle")
	if not entity.is_grounded and airborne_for >= AIR_GRACE:
		var rising: bool = entity.velocity.y > 0.0
		if rising and jump_for < 0.33:
			return StringName(carry + "jump_start")
		return StringName(carry + "jump_air")
	if land_left > 0.0 and speed < STILL_SPEED:
		return StringName(carry + "jump_land")
	if crouched:
		return StringName(carry + ("crouch_idle" if speed < STILL_SPEED else "crouch_walk"))
	if speed < STILL_SPEED:
		return StringName(carry + "idle")
	if speed < move_speed * WALK_FRACTION:
		return StringName(carry + "walk")
	if speed > move_speed * PANIC_FRACTION and carry == "":
		# Carrying, the arms already hold the cash overhead (D9): a panicking
		# carrier is a faster carry_jog.
		return &"panic_run"
	return StringName(carry + "jog")

## Advances the figure by `delta` seconds. `entity` gives the MOTION to draw
## (for your own body the predicted one, so a jump or crouch answers the key at
## once); `carrying` and `captured` are OUTCOMES and come from the confirmed
## world (GreyBoxMain._render: a guest never guesses at an outcome).
func update(entity: SimEntity, carrying: bool, captured: bool, move_speed: float,
		delta: float) -> void:
	if tree == null:
		return
	var speed: float = Vector2(entity.velocity.x, entity.velocity.z).length()
	var airborne: bool = not entity.is_grounded and not captured
	if airborne:
		_airborne_for += delta
		if entity.velocity.y > 0.0 or _jump_for > 0.0:
			_jump_for += delta
	else:
		# A real fall or jump just ended: play the landing (if it stays still).
		if _was_airborne and _airborne_for >= AIR_GRACE:
			_land_left = tree.get_animation(&"jump_land").length
		_airborne_for = 0.0
		_jump_for = 0.0
	_was_airborne = airborne
	_land_left = maxf(0.0, _land_left - delta)

	var wanted: StringName = base_clip(entity, carrying, captured, speed, move_speed,
		_airborne_for, _jump_for, _land_left)
	if wanted != clip:
		clip = wanted
		tree.set(&"parameters/loco/transition_request", String(wanted))
	var stride: float = _strides.get(wanted, 0.0) * absf(art.scale.x)
	var rate: float = 1.0
	if stride > 0.0:
		rate = clampf(speed / stride, MIN_RATE, MAX_RATE)
	tree.set(&"parameters/rate/scale", rate)

	# Grab: the arms reach down as the bundle is taken, then go overhead.
	if carrying and not _was_carrying:
		act(&"grab")
	_was_carrying = carrying
	tree.advance(delta)

## Plays a one-shot over the arms: throw, grab or interact (seize / free).
func act(name: StringName) -> void:
	if tree == null or not tree.has_animation(name):
		return
	_act_clip.animation = name
	tree.set(&"parameters/act_rate/scale", ACTION_SPEED.get(name, 1.0))
	tree.set(&"parameters/action/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

## Where the carried bundle sits: between the two hands, in world space, as
## posed this frame. Null-safe: Vector3.INF when there is no skeleton.
func hands_point() -> Vector3:
	if skeleton == null or _hand_l < 0 or _hand_r < 0:
		return Vector3.INF
	var mid: Vector3 = (skeleton.get_bone_global_pose(_hand_l).origin
		+ skeleton.get_bone_global_pose(_hand_r).origin) * 0.5
	return skeleton.global_transform * mid
