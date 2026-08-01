extends SceneTree
## Rule regressions for ContentValidator and the load gate it backs.
## See godot/CLAUDE.md - every case below is a decision.
##
##   godot --headless --path godot --script res://tests/content_validator_test.gd
##
## The two-room box is the passing fixture (WORLD_AUTHORING.md §8 step 2), and
## every other case is that same fixture with one defect seeded into it. A
## validator that only ever passes has proved nothing, so each row states the
## defect it must catch and the suite fails if the validator stays quiet.

## Every check this suite is meant to run. See the harness guard below.
const EXPECTED_CHECKS: int = 22

var _passed: int = 0
var _failed: int = 0
var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	print("=== ContentValidator + load gate ===")
	_test_clean_fixture()
	_test_seeded_defects()
	_test_authored_content()
	_test_load_gate()

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

## A content bundle rather than a world: defective content never installs into
## a world now, so the validator has to be exercised on the content itself.
func _build(blockers: Array[AABB] = [], radius: float = 4.0) -> Dictionary:
	var collision: WorldCollisionDef = WorldCollisionDef.new()
	collision.bounds = AABB(Vector3(0, 0, 0), Vector3(200, 100, 100))
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

	var zones: Array[ZoneDef] = [room_a, room_b]
	var teams: Array[TeamDef] = [team_a, team_b]
	return {"zones": zones, "teams": teams, "collision": collision, "tuning": tuning}

func _validate(bundle: Dictionary) -> PackedStringArray:
	return ContentValidator.validate(
		bundle["zones"], bundle["teams"], bundle["collision"], bundle["tuning"]
	)

func _mentions(failures: PackedStringArray, fragment: String) -> bool:
	for failure: String in failures:
		if failure.contains(fragment):
			return true
	return false

# ---- the fixture must pass ----

func _test_clean_fixture() -> void:
	var failures: PackedStringArray = _validate(_build())
	_check("clean/two-room box validates", failures.size(), 0)
	for failure: String in failures:
		_failures.append("clean/unexpected: %s" % failure)

# ---- and every seeded defect must be caught ----

func _test_seeded_defects() -> void:
	# A wall right across the doorway. The rooms look fine and the far one is
	# simply unreachable - the exact failure that is invisible by inspection.
	var sealed: Dictionary = _build([AABB(Vector3(98, 0, 0), Vector3(4, 100, 100))])
	_check("defect/sealed doorway is caught",
		_mentions(_validate(sealed), "cannot be reached"), true)

	# A doorway narrower than the body that has to fit through it: 6 wide
	# against a radius of 4. It looks like a door and admits nobody.
	var pinched: Dictionary = _build([
		AABB(Vector3(98, 0, 0), Vector3(4, 100, 47)),
		AABB(Vector3(98, 0, 53), Vector3(4, 100, 47)),
	])
	_check("defect/doorway too narrow for a body is caught",
		_mentions(_validate(pinched), "cannot be reached"), true)

	# A spawn buried in a wall.
	var buried: Dictionary = _build()
	var buried_spawn: Array[Vector3] = [Vector3(100, 50, 20)]
	buried["teams"][0].spawn_points = buried_spawn
	_check("defect/spawn inside a blocker is caught",
		_mentions(_validate(buried), "inside a blocker"), true)

	# A spawn outside the shell entirely.
	var outside: Dictionary = _build()
	var outside_spawn: Array[Vector3] = [Vector3(500, 50, 50)]
	outside["teams"][1].spawn_points = outside_spawn
	_check("defect/spawn outside the shell is caught",
		_mentions(_validate(outside), "outside the shell"), true)

	# Two rooms overlapping with nothing to decide between them.
	var ambiguous: Dictionary = _build()
	ambiguous["zones"][1].bounds = AABB(Vector3(50, 0, 0), Vector3(150, 100, 100))
	_check("defect/ambiguous overlap is caught",
		_mentions(_validate(ambiguous), "equal priority"), true)

	# ...and the same overlap is fine once someone decides.
	var decided: Dictionary = _build()
	decided["zones"][1].bounds = AABB(Vector3(50, 0, 0), Vector3(150, 100, 100))
	decided["zones"][1].priority = 1
	_check("defect/deliberate overlap passes",
		_mentions(_validate(decided), "equal priority"), false)

	# A degenerate blocker: authored, and stops nothing.
	var flat: Dictionary = _build([
		AABB(Vector3(98, 0, 0), Vector3(0, 100, 40)),
		AABB(Vector3(98, 0, 60), Vector3(4, 100, 40)),
	])
	_check("defect/degenerate blocker is caught",
		_mentions(_validate(flat), "degenerate"), true)

	# A blocker floating outside the world it is supposed to obstruct.
	var stray: Dictionary = _build([
		AABB(Vector3(98, 0, 0), Vector3(4, 100, 40)),
		AABB(Vector3(98, 0, 60), Vector3(4, 100, 40)),
		AABB(Vector3(900, 0, 0), Vector3(10, 10, 10)),
	])
	_check("defect/stray blocker outside the shell is caught",
		_mentions(_validate(stray), "outside the shell"), true)

	# No geometry at all.
	var bare: Dictionary = _build()
	bare["collision"] = null
	_check("defect/missing collision content is caught",
		_mentions(_validate(bare), "no WorldCollisionDef"), true)

# ---- the shipped fixture ----

## The authored .tres must itself validate, since it is what §8 step 2
## calibrates against and what later steps build on.
func _test_authored_content() -> void:
	var collision: WorldCollisionDef = load("res://content/collision/two_room_box.tres") as WorldCollisionDef
	_check("authored/two-room box loads", collision != null, true)
	if collision == null:
		return
	var bundle: Dictionary = _build()
	bundle["collision"] = collision
	_check("authored/two-room box validates", _validate(bundle).size(), 0)

# ---- the gate ----

## §7 asks for a hard gate, not a report. Content that fails must not install,
## and a world that refused its content must not run - otherwise the match
## starts anyway inside an empty shell and the problem is still discovered
## mid-match, just later.
func _test_load_gate() -> void:
	var good: Dictionary = _build()
	var accepted: SimWorld = SimWorld.new(1)
	var ok: bool = accepted.configure(
		GameModeDef.new(), good["tuning"], good["zones"], good["teams"], good["collision"]
	)
	_check("gate/valid content is accepted", ok, true)
	_check("gate/and installs", accepted.zones.size(), 2)
	_check("gate/and reports healthy", accepted.has_valid_content(), true)
	_check("gate/and steps", accepted.step([]).is_empty(), false)

	var bad: Dictionary = _build([AABB(Vector3(98, 0, 0), Vector3(4, 100, 100))])
	var refused: SimWorld = SimWorld.new(1)
	var rejected: bool = refused.configure(
		GameModeDef.new(), bad["tuning"], bad["zones"], bad["teams"], bad["collision"]
	)
	_check("gate/broken content is refused", rejected, false)
	_check("gate/and does not install", refused.zones.size(), 0)
	_check("gate/and reports why", refused.content_failures.size() > 0, true)
	_check("gate/and the world will not step", refused.step([]).is_empty(), true)

	# A world with no geometry is an open plane, not a broken level: the rule
	# suites and determinism probes are built on exactly that shape.
	var plain: SimWorld = SimWorld.new(1)
	_check("gate/open-plane fixtures still configure",
		plain.configure(GameModeDef.new(), TuningDef.new(), [], []), true)
	_check("gate/and still step", plain.step([]).is_empty(), false)
