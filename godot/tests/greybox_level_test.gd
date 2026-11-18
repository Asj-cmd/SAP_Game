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

const EXPECTED_CHECKS: int = 35

var _passed: int = 0
var _failed: int = 0
var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	print("=== Grey-box level ===")
	_test_both_variants_load()
	_test_playable()
	_test_spawn_lineup()
	_test_tuning_tracks_defaults()

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
	# Through the countdown (3 s since PT4-2) and into play.
	for i: int in 150:
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

## PT4-2: each family starts in one row on its own front lawn. Per team size the
## spawns must be the turned twin of the other house's (about the lot centre),
## keep every body two radii from every other, start no body inside a blocker,
## and come out the same on a second load.
const LOT_CENTRE: Vector2 = Vector2(3640.0, 1860.0)

func _spawns(team_size: int) -> Dictionary[StringName, Array]:
	var level: GreyBoxLevel = GreyBoxLevel.new(GreyBoxLevel.SafeVariant.B,
		GreyBoxLevel.LEVEL_PATH, team_size)
	var out: Dictionary[StringName, Array] = {}
	for team: TeamDef in level.teams:
		var points: Array = []
		for slot: int in team_size:
			points.append(team.spawn_point_for_slot(slot))
		out[team.id] = points
	return out

func _test_spawn_lineup() -> void:
	var level: GreyBoxLevel = GreyBoxLevel.new()
	var radius: float = level.tuning.actor_radius
	var height: float = level.tuning.actor_height
	for team_size: int in [2, 3, 4]:
		var label: String = "spawn/%dv%d" % [team_size, team_size]
		var spawns: Dictionary[StringName, Array] = _spawns(team_size)
		var a: Array = spawns.get(&"team_a", [])
		var b: Array = spawns.get(&"team_b", [])
		var unmirrored: PackedStringArray = PackedStringArray()
		for slot: int in mini(a.size(), b.size()):
			var pa: Vector3 = a[slot]
			var pb: Vector3 = b[slot]
			var twin: Vector3 = Vector3(2.0 * LOT_CENTRE.x - pa.x, pa.y, 2.0 * LOT_CENTRE.y - pa.z)
			if not pb.is_equal_approx(twin):
				unmirrored.append("slot %d: %s vs %s" % [slot, pa, pb])
		_check("%s one point per seat" % label, [a.size(), b.size()], [team_size, team_size])
		_check("%s mirrored" % label, ", ".join(unmirrored), "")
		var everyone: Array = a + b
		var crowded: PackedStringArray = PackedStringArray()
		var walled: PackedStringArray = PackedStringArray()
		for i: int in everyone.size():
			var p: Vector3 = everyone[i]
			for j: int in range(i + 1, everyone.size()):
				var q: Vector3 = everyone[j]
				if Vector2(p.x, p.z).distance_to(Vector2(q.x, q.z)) < 2.0 * radius:
					crowded.append("%s / %s" % [p, q])
			var body: AABB = AABB(Vector3(p.x - radius, p.y, p.z - radius),
				Vector3(2.0 * radius, height, 2.0 * radius))
			for box: AABB in level.collision.blockers:
				if box.intersects(body):
					walled.append("%s in %s" % [p, box])
			if not level.collision.contains(p, radius):
				walled.append("%s outside the shell" % p)
		_check("%s no two bodies overlap" % label, ", ".join(crowded), "")
		_check("%s no body starts in a blocker" % label, ", ".join(walled), "")
		_check("%s same points on a second load" % label, _spawns(team_size), spawns)

## The grey box may only DIFFER from TuningDef's defaults on purpose.
##
## A restated value silently stops tracking the thing it restates, and this one
## did: carry_speed_scale sat at 1.0 here for months after the default became
## 0.85, so carrying cash cost nothing and the tuning file said otherwise. The
## test names the intended exceptions, so adding a fourth is a deliberate act
## and re-stating a matching value fails.
func _test_tuning_tracks_defaults() -> void:
	var live: TuningDef = GreyBoxLevel.build_tuning()
	var stock: TuningDef = TuningDef.new()
	# Deliberately tighter: the grey box is a small, dense space.
	var intended: Dictionary[String, float] = {
		"pickup_range": 70.0, "capture_range": 80.0, "rescue_range": 80.0,
	}
	var checked: PackedStringArray = PackedStringArray([
		"move_speed", "carry_speed_scale", "actor_radius", "actor_height",
		"crouch_speed_scale", "jump_speed", "throw_speed", "throw_lift",
		"gravity", "terminal_fall_speed", "step_up_height",
		"vault_height", "crouch_gap", "max_drop_height",
		"pickup_range", "capture_range", "rescue_range",
	])
	var unexpected: PackedStringArray = PackedStringArray()
	for field: String in checked:
		var mine: float = live.get(field)
		if intended.has(field):
			if mine != intended[field]:
				unexpected.append("%s should be %s, is %s" % [field, intended[field], mine])
			continue
		if mine != stock.get(field):
			unexpected.append("%s drifted from the default %s, is %s" % [
				field, stock.get(field), mine])
	_check("tuning/only the intended values differ", ", ".join(unexpected), "")
	_check("tuning/carrying actually costs something", live.carry_speed_scale < 1.0, true)
