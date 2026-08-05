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
const EXPECTED_CHECKS: int = 35

var _passed: int = 0
var _failed: int = 0
var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	print("=== ContentValidator + load gate ===")
	_test_clean_fixture()
	_test_seeded_defects()
	_test_authored_content()
	_test_load_gate()
	_test_doorway_follows_the_body()
	_test_more_than_one_way_in()
	_test_getting_back_out()

	# Counted BEFORE the guard's own failure is added, or a suite that skipped a
	# case reports the total it was supposed to reach and reads as a paradox.
	var ran: int = _passed + _failed
	if ran != EXPECTED_CHECKS:
		_failed += 1
		_failures.append("harness: ran %d checks, expected %d - a case was skipped"
			% [ran, EXPECTED_CHECKS])
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
	collision.is_fixture = true # a rig, not a level
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

func _validate(bundle: Dictionary, advisories: Array[String] = []) -> PackedStringArray:
	return ContentValidator.validate(
		bundle["zones"], bundle["teams"], bundle["collision"], bundle["tuning"],
		null, advisories
	)

func _mentions_note(notes: Array[String], fragment: String) -> bool:
	for note: String in notes:
		if note.contains(fragment):
			return true
	return false

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

# ---- the door is measured against the body, not against a number ----

## Capsules become characters, and a character is wider.
##
## The whole point of the gate is that widening the body should FAIL any door
## that no longer fits, without anybody remembering to go and re-check the
## house. So the same geometry is validated twice with different bodies: the
## door that admits today's actor must refuse a wider one.
##
## If this ever passes for both, something has been pinned to a constant and the
## gate has stopped being about bodies at all.
func _test_doorway_follows_the_body() -> void:
	# The stock fixture: a 20-wide doorway in the dividing wall.
	_check("body/a 20-wide door admits a radius-4 body",
		_validate(_build([], 4.0)).size(), 0)

	# A radius-10 body is 20 across - exactly the doorway, no clearance at all.
	# Nothing about the level changed; only the thing walking through it.
	_check("body/and refuses one that is exactly as wide",
		_mentions(_validate(_build([], 10.0)), "cannot be reached"), true)

# ---- no important room may have a single approach ----

## Counted as a min cut from outdoors, so the assertions are numbers rather than
## the presence of a message.
##
## The garage case is the reason this is a min cut and not an articulation
## search. A room with one door straight onto the garden has no room in front of
## it to remove, so "is there a single room whose removal cuts this off" answers
## no and the level passes - while a defender stands in the only door.
func _test_more_than_one_way_in() -> void:
	# One route: through the yard door, along the passage, through the vault
	# door. Closing either door seals it.
	var single: Dictionary = _house_with_routes(1)
	_check("routes/one way in fails", _mentions(_validate(single), "'vault' has 1 way in"), true)

	# A garage off the garden: nothing between it and outdoors at all.
	var garage: Dictionary = _garage()
	_check("routes/a single door straight onto neutral ground fails",
		_mentions(_validate(garage), "'garage' has 1 way in"), true)

	# Two independent routes clears the floor and is still short of the target,
	# so it loads and says so. Both of these matter: a warning that failed would
	# be a failure, and a failure that stayed quiet would be nothing.
	var pair: Array[String] = []
	var two: Dictionary = _house_with_routes(2)
	_check("routes/two independent ways in passes", _validate(two, pair).size(), 0)
	_check("routes/and is advised it is short of three",
		_mentions_note(pair, "'vault' has 2 ways in"), true)

	# Three is the target, so nothing to say.
	var quiet: Array[String] = []
	var three: Dictionary = _house_with_routes(3)
	_check("routes/three passes silently", _validate(three, quiet).size(), 0)
	_check("routes/with nothing to advise", quiet.size(), 0)

	# Outdoors is the `outdoor` flag, not neutrality. The same three-route house
	# with its yard left unmarked has to fail: if neutrality still counted, open
	# ground could not be owned, and unowned ground is ground nobody can be
	# seized on - which is what emptied a whole match of captures.
	var unmarked: Dictionary = _house_with_routes(3)
	unmarked["collision"].is_fixture = false # judge it as a level, not a rig
	for zone: ZoneDef in unmarked["zones"]:
		zone.outdoor = false
	_check("routes/a neutral zone is not by itself an outdoors",
		_mentions(_validate(unmarked), "no zone is marked outdoor"), true)

	# A level with no outdoors is one this row cannot answer, so it is refused
	# rather than waved through. The two-room box passes only because it says on
	# itself that it is a rig; clear that and it stops being exempt.
	var undeclared: Dictionary = _build()
	undeclared["collision"].is_fixture = false
	_check("routes/content with no outdoors fails closed",
		_mentions(_validate(undeclared), "cannot validate routes"), true)

	# The floor is content, not a constant: the same two-route house refuses to
	# load once the level asks for three. If this ever stops biting, the
	# threshold has been pinned somewhere in code.
	var strict: Dictionary = _house_with_routes(2)
	strict["tuning"].routes_required = 3
	_check("routes/the floor is a content value",
		_mentions(_validate(strict), "'vault' has 2 ways in"), true)

## A yard, a vault at the far end, and `routes` separate passages between them.
##
## The passages are unzoned on purpose. Each one is a corridor rather than a
## room, and it is also the case that they must be regions in their own right
## for the count to come out - merge them into their neighbours and the whole
## house collapses into one adjacency.
func _house_with_routes(routes: int) -> Dictionary:
	var depth: float = 300.0
	var band: float = depth / float(routes)
	var collision: WorldCollisionDef = WorldCollisionDef.new()
	collision.is_fixture = true # a rig, not a level
	collision.bounds = AABB(Vector3(0, 0, 0), Vector3(400, 100, depth))

	var walls: Array[AABB] = []
	# The two cross-walls, each with one doorway per passage.
	for wall_x: float in [100.0, 250.0]:
		var cut: float = 0.0
		for i: int in routes:
			var door_from: float = band * float(i) + band * 0.5 - 20.0
			walls.append(AABB(Vector3(wall_x, 0, cut), Vector3(4, 100, door_from - cut)))
			cut = door_from + 40.0
		walls.append(AABB(Vector3(wall_x, 0, cut), Vector3(4, 100, depth - cut)))
	# ...and the partitions that keep the passages apart.
	for i: int in routes - 1:
		walls.append(AABB(Vector3(104, 0, band * float(i + 1) - 2.0), Vector3(146, 100, 4)))
	collision.blockers = walls

	var yard: ZoneDef = _zone(&"yard", ZoneDef.Role.NEUTRAL, &"",
		AABB(Vector3(0, 0, 0), Vector3(100, 100, depth)), true)
	var vault: ZoneDef = _zone(&"vault", ZoneDef.Role.CASH_ROOM, &"team_b",
		AABB(Vector3(254, 0, 0), Vector3(146, 100, depth)))
	return _bundle([yard, vault] as Array[ZoneDef], collision, depth)

## One room, one door, straight onto the garden.
func _garage() -> Dictionary:
	var depth: float = 300.0
	var collision: WorldCollisionDef = WorldCollisionDef.new()
	collision.is_fixture = true # a rig, not a level
	collision.bounds = AABB(Vector3(0, 0, 0), Vector3(400, 100, depth))
	collision.blockers = [
		AABB(Vector3(100, 0, 0), Vector3(4, 100, 130)),
		AABB(Vector3(100, 0, 170), Vector3(4, 100, 130)),
	] as Array[AABB]

	var yard: ZoneDef = _zone(&"yard", ZoneDef.Role.NEUTRAL, &"",
		AABB(Vector3(0, 0, 0), Vector3(100, 100, depth)), true)
	var garage: ZoneDef = _zone(&"garage", ZoneDef.Role.CASH_ROOM, &"team_b",
		AABB(Vector3(104, 0, 0), Vector3(296, 100, depth)))
	return _bundle([yard, garage] as Array[ZoneDef], collision, depth)

## Teams for the fixtures above. Both start in the yard, so the room under test
## is somewhere they walk to rather than somewhere they begin.
func _bundle(
	zones: Array[ZoneDef],
	collision: WorldCollisionDef,
	depth: float
) -> Dictionary:
	var team_a: TeamDef = TeamDef.new()
	team_a.id = &"team_a"
	team_a.home_zone = &"yard"
	team_a.spawn_points = [Vector3(50, 50, depth * 0.25)] as Array[Vector3]
	var team_b: TeamDef = TeamDef.new()
	team_b.id = &"team_b"
	team_b.home_zone = &"yard"
	team_b.spawn_points = [Vector3(50, 50, depth * 0.75)] as Array[Vector3]

	var tuning: TuningDef = TuningDef.new()
	tuning.actor_radius = 4.0

	return {
		"zones": zones,
		"teams": [team_a, team_b] as Array[TeamDef],
		"collision": collision,
		"tuning": tuning,
	}

# ---- and every room you can walk into, you can walk out of ----

## A ledge over a floor. Step off it and you are down; the way back up is a
## climb the game has no verb for, so the room below is a room you stay in.
##
## Reachability says it is fine, and it is: you can certainly get there. That is
## the whole reason this is a separate question - it became askable the moment
## edges stopped being symmetric, and nothing before it could see the failure.
func _test_getting_back_out() -> void:
	# 100 up is far past the 30 an actor steps over, and well inside the drop it
	# survives. One way, therefore.
	_check("escape/a room you can only fall into is caught",
		_mentions(_validate(_ledge_over(100.0)), "can be entered but not left"), true)

	# The identical level with the ledge lowered to a step. Same rooms, same
	# doorless shape; only the height changed, and now it is a floor.
	_check("escape/and a step down is not a trap",
		_mentions(_validate(_ledge_over(20.0)), "can be entered but not left"), false)

func _ledge_over(height: float) -> Dictionary:
	var collision: WorldCollisionDef = WorldCollisionDef.new()
	collision.is_fixture = true # a rig, not a level
	collision.bounds = AABB(Vector3(0, 0, 0), Vector3(300, 400, 100))
	collision.blockers = [
		AABB(Vector3(0, 0, 0), Vector3(200, height, 100)),
	] as Array[AABB]

	var ledge: ZoneDef = _zone(&"ledge", ZoneDef.Role.HOME, &"team_a",
		AABB(Vector3(0, 0, 0), Vector3(200, 400, 100)))
	# Starts clear of the drop, not at it. A stance is a body-width thing, so the
	# outermost places you can stand on the ledge sit slightly PAST its edge -
	# and a zone butted up against x=200 swallows them, reporting a room that can
	# be left because part of it was never down here.
	var below: ZoneDef = _zone(&"below", ZoneDef.Role.CASH_ROOM, &"team_b",
		AABB(Vector3(220, 0, 0), Vector3(80, 400, 100)))

	# Both spawns up top, because a spawn in the room under test would be asking
	# the validator to certify a level nobody could start.
	var team_a: TeamDef = TeamDef.new()
	team_a.id = &"team_a"
	team_a.home_zone = &"ledge"
	team_a.spawn_points = [Vector3(50, height + 10.0, 50)] as Array[Vector3]
	var team_b: TeamDef = TeamDef.new()
	team_b.id = &"team_b"
	team_b.home_zone = &"below"
	team_b.spawn_points = [Vector3(150, height + 10.0, 50)] as Array[Vector3]

	var tuning: TuningDef = TuningDef.new()
	tuning.actor_radius = 4.0

	return {
		"zones": [ledge, below] as Array[ZoneDef],
		"teams": [team_a, team_b] as Array[TeamDef],
		"collision": collision,
		"tuning": tuning,
	}

func _zone(id: StringName, role: ZoneDef.Role, owner: StringName, bounds: AABB,
		outdoor: bool = false) -> ZoneDef:
	var zone: ZoneDef = ZoneDef.new()
	zone.id = id
	zone.role = role
	zone.owner_team = owner
	zone.bounds = bounds
	zone.outdoor = outdoor
	return zone
