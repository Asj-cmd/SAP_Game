class_name FigureAnimation
extends RefCounted
## The figures' one animation set (P2-2): `art/characters/figure_anims.res`,
## built by `tools/build_figure_anims.gd` from the Quaternius Universal
## Animation Library. One AnimationLibrary for every family member (one rig).
##
## Presentation only: nothing here reads or writes the simulation. Art stays
## optional - with no library built, `attach` returns null and the figure
## stands in its rest pose as before.
##
## Clips (names the driver plays; `carry_*` = the same with the cash held over
## the head): idle, walk, walk_loose, jog, sprint, panic_run, crouch_idle,
## crouch_walk, jump_start, jump_air, jump_land, grab, interact, throw, and
## the arm-only layers arms_carry / arms_panic. Locomotion loops carry a
## `stride_speed` meta (model units per second at playback speed 1).

const LIBRARY_PATH: String = "res://art/characters/figure_anims.res"

static var _library: AnimationLibrary = null
static var _looked: bool = false

static func library() -> AnimationLibrary:
	if not _looked:
		_looked = true
		if ResourceLoader.exists(LIBRARY_PATH):
			_library = load(LIBRARY_PATH) as AnimationLibrary
	return _library

## Adds an AnimationPlayer for the set under `art` (an instanced figure, the
## node ArtTheme.shape_figure sized). Null when the set is not built or the
## figure has no skeleton where the set expects one.
static func attach(art: Node3D) -> AnimationPlayer:
	var set: AnimationLibrary = library()
	if set == null:
		return null
	var skeleton: String = String(set.get_meta(&"skeleton_path", "Armature/Skeleton3D"))
	if art.get_node_or_null(skeleton) == null:
		return null
	var player: AnimationPlayer = AnimationPlayer.new()
	player.name = "FigureAnimation"
	art.add_child(player)
	player.root_node = NodePath("..")
	player.add_animation_library(&"", set)
	return player

## Holds `art` still in `clip` at `time` seconds (the capture tool's posed
## stand-ins, P2-2 contact sheets). Must be in the tree. False when the clip or
## the set is missing.
static func pose(art: Node3D, clip: StringName, time: float) -> bool:
	var player: AnimationPlayer = attach(art)
	if player == null or not player.has_animation(clip):
		return false
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.play(clip)
	player.seek(clamp(time, 0.0, player.get_animation(clip).length), true)
	return true
