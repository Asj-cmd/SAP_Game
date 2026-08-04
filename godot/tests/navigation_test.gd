extends SceneTree
## Rule regressions for WalkableSurface and NavGraph. See godot/CLAUDE.md.
##
##   godot --headless --path godot --script res://tests/navigation_test.gd
##
## Every case here is a DECISION about traversal - whether a body can stand
## somewhere, whether it can step from one place to another, whether a route
## exists. The grid arithmetic underneath is not tested and should not be.
##
## The through-line is the difference between FITTING and STANDING, because
## that is the whole reason this replaced a volumetric flood. Air above a wall
## connects two rooms perfectly well if all you ask is whether a body fits in
## it; the old fill said so, and would have certified a level whose only route
## between two houses was over the roof.

const EXPECTED_CHECKS: int = 26

## Fixed rather than derived, so a case states the resolution it needs instead
## of depending on the heuristics that pick one for real content.
const CELL: float = 5.0
const RADIUS: float = 8.0
const STEP_UP: float = 30.0
const FLOOR_TOP: float = 10.0

var _passed: int = 0
var _failed: int = 0
var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	print("=== Walkable surface + navigation ===")
	_test_standing_not_fitting()
	_test_steps_and_drops()
	_test_stance_under()
	_test_routing()
	_test_baking()

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

# ---- fixtures ----

## A 200x200x100 box with a floor, plus whatever walls a case adds.
##
## Deliberately tall. A stance is found where there is a free cell ABOVE the
## thing being stood on, so a ledge within one layer of the ceiling is invisible
## to the fill - correct behaviour, since a shelf with no headroom is not
## somewhere to walk, but it makes for a fixture that tests the resolution
## instead of the rule.
func _surface(walls: Array[AABB], step_up: float = STEP_UP) -> WalkableSurface:
	var collision: WorldCollisionDef = WorldCollisionDef.new()
	collision.bounds = AABB(Vector3(0, 0, 0), Vector3(200, 200, 100))
	var blockers: Array[AABB] = [AABB(Vector3(0, 0, 0), Vector3(200, FLOOR_TOP, 100))]
	blockers.append_array(walls)
	collision.blockers = blockers
	# No drops in these fixtures: they predate one-way edges and test walking.
	return WalkableSurface.build(collision, RADIUS, step_up, 0.0, CELL)

## A wall across the whole width, `height` tall, standing on the floor.
func _wall(height: float) -> AABB:
	return AABB(Vector3(98, FLOOR_TOP, 0), Vector3(4, height, 100))

## Can a body walk from one place to the other? The question every case asks.
func _reaches(surface: WalkableSurface, from: Vector3, to: Vector3) -> bool:
	var start: int = surface.stance_under(from, CELL * 2.0)
	var goal: int = surface.stance_under(to, CELL * 2.0)
	if start < 0 or goal < 0:
		return false
	return surface.component_from(start).has(goal)

func _left() -> Vector3:
	return Vector3(40, 50, 50)

func _right() -> Vector3:
	return Vector3(160, 50, 50)

# ---- fitting is not standing ----

func _test_standing_not_fitting() -> void:
	var open: WalkableSurface = _surface([])
	_check("fill/an open floor is standable", open.size() > 0, true)
	_check("fill/and connected end to end", _reaches(open, _left(), _right()), true)

	# The case the volumetric fill got wrong. A 60-tall wall with 30 units of
	# open air above it: a body FITS in that air, and the old flood walked
	# straight through it from one room to the other. A body cannot STAND in it.
	var tall: WalkableSurface = _surface([_wall(60.0)])
	_check("fill/a wall taller than a step separates the rooms",
		_reaches(tall, _left(), _right()), false)

	# ...and the air above it is not nothing - it is a ledge, in its own
	# component. Proving it exists is what makes the previous case meaningful:
	# the rooms are apart because there is no WALK between them, not because the
	# fill failed to find anything up there.
	var ledge: int = tall.stance_under(Vector3(100, 95, 50), CELL * 2.0)
	_check("fill/the wall top is a stance", ledge >= 0, true)
	_check("fill/but not one connected to the floor",
		tall.component_from(ledge).size() < tall.size(), true)

	# A doorway is an absence of blocker, and the only way through.
	var doored: WalkableSurface = _surface([
		AABB(Vector3(98, FLOOR_TOP, 0), Vector3(4, 60, 30)),
		AABB(Vector3(98, FLOOR_TOP, 70), Vector3(4, 60, 30)),
	])
	_check("fill/a doorway reconnects them", _reaches(doored, _left(), _right()), true)

# ---- steps and drops ----

func _test_steps_and_drops() -> void:
	# A sill within the step allowance is walked over without a jump verb.
	var sill: WalkableSurface = _surface([_wall(20.0)])
	_check("step/a low sill is crossed", _reaches(sill, _left(), _right()), true)

	# The same sill with a smaller allowance is a wall. This is the pair that
	# proves the allowance is being read rather than assumed.
	var strict: WalkableSurface = _surface([_wall(20.0)], 10.0)
	_check("step/and is a wall when the allowance is lower",
		_reaches(strict, _left(), _right()), false)

	# Edges are symmetric by construction, so a drop too deep to climb back up
	# is not an edge in either direction. A route that only works downhill is
	# how a level ends up with a basement nobody can leave.
	var deep: WalkableSurface = _surface([
		AABB(Vector3(0, FLOOR_TOP, 0), Vector3(98, 60, 100)),
	])
	var high: int = deep.stance_under(Vector3(40, 90, 50), CELL * 2.0)
	var low: int = deep.stance_under(_right(), CELL * 2.0)
	_check("drop/a raised platform is a stance", high >= 0, true)
	_check("drop/and a deep drop off it is not a route", deep.component_from(high).has(low), false)

# ---- resolving a point to a stance ----

func _test_stance_under() -> void:
	var open: WalkableSurface = _surface([])
	var resting: float = FLOOR_TOP + RADIUS

	# A point in mid-air resolves to what it would fall onto, not to whatever
	# happens to be nearest in three dimensions. Spawn markers and room centres
	# are both authored well above the floor.
	var airborne: int = open.stance_under(Vector3(40, 90, 50), CELL * 2.0)
	_check("stance/mid-air resolves downward", airborne >= 0, true)
	_check("stance/onto the floor", is_equal_approx(open.nodes[airborne].y, resting), true)

	# Standing on the floor already resolves to itself.
	var standing: int = open.stance_under(Vector3(40, resting, 50), CELL * 2.0)
	_check("stance/a resting point resolves to its own stance", standing, airborne)

	# Nothing within reach horizontally is an honest failure, not a far guess.
	_check("stance/nothing within reach reports nothing",
		open.stance_under(Vector3(40, 50, 50), 0.001), -1)

# ---- routing ----

func _test_routing() -> void:
	var doored: WalkableSurface = _surface([
		AABB(Vector3(98, FLOOR_TOP, 0), Vector3(4, 60, 30)),
		AABB(Vector3(98, FLOOR_TOP, 70), Vector3(4, 60, 30)),
	])
	var nav: NavGraph = NavGraph.of(doored)
	var resting: float = FLOOR_TOP + RADIUS
	var from: Vector3 = Vector3(40, resting, 20)
	var to: Vector3 = Vector3(160, resting, 80)

	var path: PackedVector3Array = nav.route(from, to)
	_check("route/a way through the doorway is found", path.size() > 0, true)
	_check("route/and ends at the destination asked for", path[path.size() - 1], to)

	# It must go THROUGH the gap. A straight line from start to finish crosses
	# the wall, so a route that never approaches z=40..60 is not a route.
	var through: bool = false
	for point: Vector3 in path:
		if absf(point.x - 100.0) < 20.0 and point.z > 25.0 and point.z < 75.0:
			through = true
	_check("route/by way of the gap rather than the wall", through, true)

	# Smoothing: an open floor should not be walked in grid steps. Without the
	# string-pull this is one waypoint per cell, which at this resolution is
	# more than twenty.
	var open: NavGraph = NavGraph.of(_surface([]))
	var straight: PackedVector3Array = open.route(Vector3(20, resting, 50), Vector3(180, resting, 50))
	_check("route/an open run is not walked in grid steps", straight.size() <= 3, true)

	# A wall with no door has no route, and says so rather than returning a
	# path that stops short - a bot handed a partial route walks confidently
	# into the wall and stays there.
	var sealed: NavGraph = NavGraph.of(_surface([_wall(60.0)]))
	_check("route/no way through means no route",
		sealed.route(from, to).size(), 0)

	# Hop distance is the comparison the bots make between errands, so an
	# unreachable target has to be unreachable rather than merely expensive.
	var hops: PackedInt32Array = sealed.hops_from(sealed.node_at(from))
	_check("route/an unreachable target reports no distance",
		sealed.distance_by_hops(hops, sealed.node_at(to)), -1.0)
	_check("route/a reachable one reports some",
		open.distance_by_hops(open.hops_from(open.node_at(from)), open.node_at(to)) > 0.0, true)

# ---- baking ----

## A stored surface has to be the same graph as a built one.
##
## The whole point of baking is that loading skips the build, so nothing at
## runtime re-derives the answer and nothing would notice if the stored one were
## subtly different. The equivalence is therefore asserted here rather than
## assumed - and it is asserted on CONNECTIVITY and ROUTES, not just node count,
## because a surface with every node and no edges also has the right size.
func _test_baking() -> void:
	var built: WalkableSurface = _surface([
		AABB(Vector3(98, FLOOR_TOP, 0), Vector3(4, 60, 30)),
		AABB(Vector3(98, FLOOR_TOP, 70), Vector3(4, 60, 30)),
	])
	var stored: WalkableSurfaceDef = built.to_def()
	var loaded: WalkableSurface = WalkableSurface.from_def(stored, built._collision)

	_check("bake/every stance survives the round trip", loaded.size(), built.size())
	_check("bake/and so does what connects to what",
		loaded.component_from(0).size(), built.component_from(0).size())

	var resting: float = FLOOR_TOP + RADIUS
	var from: Vector3 = Vector3(40, resting, 20)
	var to: Vector3 = Vector3(160, resting, 80)
	_check("bake/and the route through the doorway is the same",
		NavGraph.of(loaded).route(from, to), NavGraph.of(built).route(from, to))

	# Staleness must be detected, not trusted. A bake that no longer describes
	# the level would have the load gate certifying a level that does not exist,
	# which is worse than having no bake at all.
	var moved: WorldCollisionDef = WorldCollisionDef.new()
	moved.bounds = built._collision.bounds
	moved.blockers = [AABB(Vector3(0, 0, 0), Vector3(200, FLOOR_TOP, 100))] as Array[AABB]
	_check("bake/a wall that moved invalidates it",
		stored.matches(moved, RADIUS, STEP_UP), false)
	_check("bake/and so does a differently sized body",
		stored.matches(built._collision, RADIUS * 2.0, STEP_UP), false)
