@tool
extends EditorScript
## Bakes the open blockout scene into level content.
##
## Open game/blockout/greybox_house.tscn, then File > Run in the script editor.
## Everything the baker needs is in the scene; nothing is configured here.
##
## Deliberately a manual step rather than an import hook. Baking on every save
## would rewrite content while a level is half-moved, and a blockout spends
## most of its life half-moved.

const OUTPUT_PATH: String = "res://content/levels/greybox_house.tres"
const LEVEL_ID: StringName = &"greybox_house"

func _run() -> void:
	var spatial: Node3D = get_scene() as Node3D
	if spatial == null:
		push_error("bake: open the blockout scene first (its root must be a Node3D)")
		return

	var baker: BlockoutBaker = BlockoutBaker.new()
	var level: LevelDef = baker.bake(spatial, LEVEL_ID, spatial.scene_file_path)
	if level == null:
		for failure: String in baker.failures:
			push_error("bake: %s" % failure)
		return

	# The gate runs at bake time too, so a blockout that cannot be played is
	# caught while it is being authored rather than when someone tries to play
	# it (WORLD_AUTHORING.md §7).
	var tuning: TuningDef = GreyBoxLevel.build_tuning()
	var problems: PackedStringArray = ContentValidator.validate(
		level.zones, level.teams, level.collision, tuning
	)
	if not problems.is_empty():
		for problem: String in problems:
			push_error("bake: %s" % problem)
		push_error("bake: level is not playable, nothing written")
		return

	var result: int = ResourceSaver.save(level, OUTPUT_PATH)
	if result != OK:
		push_error("bake: could not write %s (error %d)" % [OUTPUT_PATH, result])
		return
	print("baked %d zones, %d blockers, %d teams -> %s" % [
		level.zones.size(), level.collision.blockers.size(), level.teams.size(), OUTPUT_PATH,
	])
