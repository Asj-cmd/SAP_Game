extends SceneTree
## The BAKED grey-box arena must pass the load gate and be playable, in BOTH
## safe-room configurations. See godot/CLAUDE.md.
##
## This is the guard on the blockout pipeline: the level is authored visually
## and baked, so nothing stops a dragged box from sealing a doorway. The gate
## catches that, and this suite is what runs the gate.
##
##   godot --headless --path godot --script res://tests/greybox_level_test.gd
##
## Not a test of the level's data - §7's gate is the decision under test, and
## shipped content that cannot load is the failure it exists to prevent. It
## also drives the sim the way the slice does, so "the grey box runs" is a
## claim with evidence rather than a screenshot nobody kept.

const EXPECTED_CHECKS: int = 18

var _passed: int = 0
var _failed: int = 0
var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	print("=== Grey-box level ===")
	_test_both_variants_load()
	_test_playable()

	if _passed + _failed != EXPECTED_CHECKS:
		_failed += 1
		_failures.append("harness: ran %d checks, expected %d - a case was skipped"
			% [_passed + _failed, EXPECTED_CHECKS])
	print("\n%d passed, %d failed" % [_passed, _failed])
	if _failed > 0:
		print("\nFAILURES:")
		for failure: String in _failures:
			print("  - %s" % failure)
	quit(1 if _failed > 0 else 0)

func _check(case_name: String, actual: Variant, expected: Variant) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		_failures.append("%s: expected %s, got %s" % [case_name, expected, actual])

func _world_for(variant: GreyBoxLevel.SafeVariant) -> Array:
	var level: GreyBoxLevel = GreyBoxLevel.new(variant)
	var world: SimWorld = SimWorld.new(7)
	var ok: bool = world.configure(level.mode, level.tuning, level.zones, level.teams, level.collision)
	return [level, world, ok]

# ---- the gate ----

func _test_both_variants_load() -> void:
	for variant: GreyBoxLevel.SafeVariant in [GreyBoxLevel.SafeVariant.A, GreyBoxLevel.SafeVariant.B]:
		var built: Array = _world_for(variant)
		var level: GreyBoxLevel = built[0]
		var world: SimWorld = built[1]
		var label: String = "A" if variant == GreyBoxLevel.SafeVariant.A else "B"
		_check("gate/variant %s is accepted" % label, built[2], true)
		_check("gate/variant %s reports no failures" % label, world.content_failures.size(), 0)
		# The variant must actually differ, or the comparison is theatre.
		var zone: ZoneDef = level.sheltered_zone()
		_check("gate/variant %s shelters somewhere" % label, zone != null and zone.grants_safety(), true)

	# The two configurations must be distinguishable as content alone.
	var a: GreyBoxLevel = GreyBoxLevel.new(GreyBoxLevel.SafeVariant.A)
	var b: GreyBoxLevel = GreyBoxLevel.new(GreyBoxLevel.SafeVariant.B)
	_check("gate/A has no timer", a.sheltered_zone().safety_is_timed(), false)
	_check("gate/A ends on the grab", a.sheltered_zone().safe_ends_on_pickup, true)
	_check("gate/B is timed", b.sheltered_zone().safety_is_timed(), true)
	_check("gate/B ignores the grab", b.sheltered_zone().safe_ends_on_pickup, false)

# ---- playability ----

## Drives the arena the way the slice does: same systems, same commands, same
## fixed step. If an actor cannot stand up and walk here, nobody can play it.
func _test_playable() -> void:
	var built: Array = _world_for(GreyBoxLevel.SafeVariant.B)
	var level: GreyBoxLevel = built[0]
	var world: SimWorld = built[1]
	world.add_system(MovementSystem.new())
	world.add_system(CarrySystem.new())
	world.add_system(CaptureSystem.new())
	world.add_system(ScoringSystem.new())
	world.add_system(MatchFlowSystem.new())

	world.populate_roster()

	world.step([MatchCommand.start()])
	# Through the countdown and into play.
	for i: int in 90:
		world.step([])
	_check("play/reaches the live phase", world.is_live(), true)
	# The win target is derived from the level, so a vault that lost a cash
	# marker in the blockout cannot silently describe a different game.
	var expected_cash: int = level.mode.cash_per_team
	_check("play/cash target came from the level", expected_cash > 0, true)
	_check("play/both vaults are stocked",
		[world.score_for(&"team_a"), world.score_for(&"team_b")],
		[expected_cash, expected_cash])

	var walker: SimEntity = world.get_entity(world.actor_ids()[0])
	_check("play/actor is standing on the floor", walker.is_grounded, true)
	# Standing height comes from the authored spawn, not a constant here.
	var spawn_y: float = level.teams[0].spawn_point_for_slot(0).y
	_check("play/at body height above it", is_equal_approx(walker.position.y, spawn_y), true)

	var started_at: float = walker.position.x
	for i: int in 15:
		world.step([MoveCommand.move(walker.id, Vector3(1, 0, 0), world.tick)])
	_check("play/walks when told to", walker.position.x > started_at, true)
	_check("play/stays on the floor while walking", walker.is_grounded, true)

	world.step([MoveCommand.stop(walker.id, world.tick)])
	var halted_at: float = walker.position.x
	world.step([])
	_check("play/stops when released", is_equal_approx(walker.position.x, halted_at), true)
