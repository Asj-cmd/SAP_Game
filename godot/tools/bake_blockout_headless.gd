extends SceneTree
## Headless entry point for the blockout bake, so the pipeline can be run and
## checked without opening the editor.
##
##   godot --headless --path godot --script res://tools/bake_blockout_headless.gd
##
## Same BlockoutBaker and same gate as tools/bake_blockout.gd, which is the
## in-editor button. Two entry points, one implementation - a bake that only
## works when somebody is watching is not a pipeline.

## Which blockout to bake. Overridable so a new layout can be validated before
## it replaces the one the game is loading.
const SCENE_PATH: String = "res://game/blockout/greybox_house.tscn"
const OUTPUT_PATH: String = "res://content/levels/greybox_house.tres"
const LEVEL_ID: StringName = &"greybox_house"

func _initialize() -> void:
	var scene: String = SCENE_PATH
	var output: String = OUTPUT_PATH
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--scene="):
			scene = arg.trim_prefix("--scene=")
		elif arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
	var packed: PackedScene = load(scene) as PackedScene
	if packed == null:
		printerr("bake: cannot load %s" % scene)
		quit(1)
		return

	var root: Node3D = packed.instantiate() as Node3D
	# Parented so global_transform resolves against a real tree rather than
	# whatever a detached node reports.
	get_root().add_child(root)

	var baker: BlockoutBaker = BlockoutBaker.new()
	var level: LevelDef = baker.bake(root, LEVEL_ID, scene, GreyBoxLevel.build_tuning())
	if level == null:
		for failure: String in baker.failures:
			printerr("bake: %s" % failure)
		quit(1)
		return

	var advisories: Array[String] = []
	var problems: PackedStringArray = ContentValidator.validate(
		level.zones, level.teams, level.collision, GreyBoxLevel.build_tuning(), null, advisories
	)
	# Printed whether or not the bake succeeds: an advisory on a level that is
	# about to be refused for something else is still worth reading.
	for note: String in advisories:
		print("bake: note: %s" % note)
	if not problems.is_empty():
		for problem: String in problems:
			printerr("bake: %s" % problem)
		printerr("bake: level is not playable, nothing written")
		quit(1)
		return

	var result: int = ResourceSaver.save(level, output)
	if result != OK:
		printerr("bake: could not write %s (error %d)" % [output, result])
		quit(1)
		return

	print("baked %d zones, %d blockers, %d teams -> %s" % [
		level.zones.size(), level.collision.blockers.size(), level.teams.size(), output,
	])
	for zone: ZoneDef in level.zones:
		print("  zone %-12s role=%-9s owner=%-7s %s" % [
			zone.id, ZoneDef.Role.keys()[zone.role],
			zone.owner_team if zone.owner_team != &"" else "-", zone.bounds,
		])
	for team: TeamDef in level.teams:
		print("  team %-8s spawns=%d cash=%d" % [
			team.id, team.spawn_points.size(), team.cash_points.size(),
		])
	quit(0)
