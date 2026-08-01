extends SceneTree
## Rule regressions for ContentValidator. See godot/CLAUDE.md - this is sim-
## adjacent content logic and every case below is a decision.
##
##   godot --headless --path godot --script res://tests/content_validator_test.gd
##
## The two-room box is the passing fixture (WORLD_AUTHORING.md §8 step 2), and
## every other case is that same fixture with one defect seeded into it. A
## validator that only ever passes has proved nothing, so each row states the
## defect it must catch and the suite fails if the validator stays quiet.

var _passed: int = 0
var _failed: int = 0
var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	print("=== ContentValidator ===")
	_test_clean_fixture()
	_test_seeded_defects()
	_test_authored_content()

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

# ---- fixture ----

## The two-room box, with zones, teams and spawns that all fit inside it.
func _build(
	blockers: Array[AABB] = [],
	shell: AABB = AABB(Vector3(0, 0, 0), Vector3(200, 100, 100)),
	radius: float = 4.0
) -> SimWorld:
	var collision: WorldCollisionDef = WorldCollisionDef.new()
	collision.bounds = shell
	# Built through a typed local rather than a ternary: the two branches of a
	# ternary unify to plain Array, which will not assign to Array[AABB].
	var walls: Array[AABB] = blockers
	if walls.is_empty():
		walls = [
			AABB(Vector3(98, 0, 0), Vector3(4, 100, 40)),
			AABB(Vector3(98, 0, 60), Vector3(4, 100, 40)),
		]
	collision.blockers = walls

	var room_a: ZoneDef = ZoneDef.new()
	room_a.id = &"room_a"
	room_a.role = ZoneDef.Role.HOME
	room_a.owner_team = &"team_a"
	room_a.bounds = AABB(Vector3(0, 0, 0), Vector3(98, 100, 100))

	var room_b: ZoneDef = ZoneDef.new()
	room_b.id = &"room_b"
	room_b.role = ZoneDef.Role.CASH_ROOM
	room_b.owner_team = &"team_b"
	room_b.bounds = AABB(Vector3(102, 0, 0), Vector3(98, 100, 100))

	var team_a: TeamDef = TeamDef.new()
	team_a.id = &"team_a"
	team_a.home_zone = &"room_a"
	team_a.spawn_points = [Vector3(30, 50, 50)]

	var team_b: TeamDef = TeamDef.new()
	team_b.id = &"team_b"
	team_b.home_zone = &"room_b"
	team_b.spawn_points = [Vector3(170, 50, 50)]

	var tuning: TuningDef = TuningDef.new()
	tuning.actor_radius = radius

	var world: SimWorld = SimWorld.new(1)
	world.configure(GameModeDef.new(), tuning, [room_a, room_b], [team_a, team_b], collision)
	return world

func _mentions(failures: PackedStringArray, fragment: String) -> bool:
	for failure: String in failures:
		if failure.contains(fragment):
			return true
	return false

# ---- the fixture must pass ----

func _test_clean_fixture() -> void:
	var failures: PackedStringArray = ContentValidator.validate(_build())
	_check("clean/two-room box validates", failures.size(), 0)
	if failures.size() > 0:
		for failure: String in failures:
			_failures.append("clean/unexpected: %s" % failure)

# ---- and every seeded defect must be caught ----

func _test_seeded_defects() -> void:
	# A wall right across the doorway. The rooms look fine and the far one is
	# simply unreachable - the exact failure that is invisible by inspection.
	var sealed: SimWorld = _build([
		AABB(Vector3(98, 0, 0), Vector3(4, 100, 100)),
	])
	_check("defect/sealed doorway is caught",
		_mentions(ContentValidator.validate(sealed), "cannot be reached"), true)

	# A doorway narrower than the body that has to fit through it. 6 wide
	# against a radius of 4 - it looks like a door and admits nobody.
	var pinched: SimWorld = _build([
		AABB(Vector3(98, 0, 0), Vector3(4, 100, 47)),
		AABB(Vector3(98, 0, 53), Vector3(4, 100, 47)),
	])
	_check("defect/doorway too narrow for a body is caught",
		_mentions(ContentValidator.validate(pinched), "cannot be reached"), true)

	# A spawn buried in a wall.
	var buried: SimWorld = _build()
	buried.teams[&"team_a"].spawn_points = [Vector3(100, 50, 20)]
	_check("defect/spawn inside a blocker is caught",
		_mentions(ContentValidator.validate(buried), "inside a blocker"), true)

	# A spawn outside the shell entirely.
	var outside: SimWorld = _build()
	outside.teams[&"team_b"].spawn_points = [Vector3(500, 50, 50)]
	_check("defect/spawn outside the shell is caught",
		_mentions(ContentValidator.validate(outside), "outside the shell"), true)

	# Two rooms overlapping with nothing to decide between them.
	var ambiguous: SimWorld = _build()
	ambiguous.zones[&"room_b"].bounds = AABB(Vector3(50, 0, 0), Vector3(150, 100, 100))
	_check("defect/ambiguous overlap is caught",
		_mentions(ContentValidator.validate(ambiguous), "equal priority"), true)

	# ...and the same overlap is fine once someone decides.
	var decided: SimWorld = _build()
	decided.zones[&"room_b"].bounds = AABB(Vector3(50, 0, 0), Vector3(150, 100, 100))
	decided.zones[&"room_b"].priority = 1
	_check("defect/deliberate overlap passes",
		_mentions(ContentValidator.validate(decided), "equal priority"), false)

	# A degenerate blocker: authored, and stops nothing.
	var flat: SimWorld = _build([
		AABB(Vector3(98, 0, 0), Vector3(0, 100, 40)),
		AABB(Vector3(98, 0, 60), Vector3(4, 100, 40)),
	])
	_check("defect/degenerate blocker is caught",
		_mentions(ContentValidator.validate(flat), "degenerate"), true)

	# A blocker floating outside the world it is supposed to obstruct.
	var stray: SimWorld = _build([
		AABB(Vector3(98, 0, 0), Vector3(4, 100, 40)),
		AABB(Vector3(98, 0, 60), Vector3(4, 100, 40)),
		AABB(Vector3(900, 0, 0), Vector3(10, 10, 10)),
	])
	_check("defect/stray blocker outside the shell is caught",
		_mentions(ContentValidator.validate(stray), "outside the shell"), true)

	# No geometry at all.
	var bare: SimWorld = SimWorld.new(1)
	bare.configure(GameModeDef.new(), TuningDef.new(), [], [])
	_check("defect/missing collision content is caught",
		_mentions(ContentValidator.validate(bare), "no WorldCollisionDef"), true)

# ---- the shipped fixture ----

## The authored .tres must itself validate, since it is what §8 step 2
## calibrates against and what later steps build on.
func _test_authored_content() -> void:
	var collision: WorldCollisionDef = load("res://content/collision/two_room_box.tres") as WorldCollisionDef
	_check("authored/two-room box loads", collision != null, true)
	if collision == null:
		return
	var world: SimWorld = _build()
	world.collision = collision
	_check("authored/two-room box validates", ContentValidator.validate(world).size(), 0)
