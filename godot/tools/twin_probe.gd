extends SceneTree
## Plays one bot match twice - as baked, and with the houses swapped - and
## finds the first tick where the two stop being turned copies of each other.
##
##   godot --headless --path godot --script res://tools/twin_probe.gd -- --team-size=2 --seed=1
##
## Swapping the houses (GreyBoxLevel.swap_houses) keeps every entity id, every
## bot's random stream and the seating order, and moves each team to the other
## house. If every rule and every bot treated a turned situation as the same
## situation, the swapped match would be the baked one turned half a circle,
## tick for tick. symmetry_probe.gd checks the CONTENT and the router; this
## checks everything that runs on top of them. The first divergence names the
## body, what it was doing in each world, and where.
##
## Positions drift apart by float rounding (a body at x and one at 5400 - x
## round differently), so a position gap below TOLERANCE is noise, not a
## divergence. A different motion state, task, carry or capture is never noise.

const TOLERANCE: float = 1.0
const TICK_LIMIT: int = 30 * 120

var _pivot: Vector2 = Vector2.ZERO
var _no_noise: bool = false

func _initialize() -> void:
	var team_size: int = 2
	var match_seed: int = 20260802
	# `--no-noise` zeroes the bots' choice noise in both worlds. Each candidate
	# errand draws its noise in list order and rooms are listed by name, so the
	# draws land on the other house's rooms after a swap - unbiased, but it ends
	# the twin, and hides whatever would have diverged next.
	_no_noise = OS.get_cmdline_user_args().has("--no-noise")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--team-size="):
			team_size = int(arg.trim_prefix("--team-size="))
		if arg.begins_with("--seed="):
			match_seed = int(arg.trim_prefix("--seed="))
	var baked: Dictionary = _build(team_size, match_seed, false)
	var swapped: Dictionary = _build(team_size, match_seed, true)
	if baked.is_empty() or swapped.is_empty():
		quit(1)
		return
	var one: SimWorld = baked["world"]
	var two: SimWorld = swapped["world"]
	var shell: AABB = one.collision.bounds
	_pivot = Vector2(shell.position.x + shell.size.x * 0.5, shell.position.z + shell.size.z * 0.5)

	var worst: float = 0.0
	## The last few ticks of every body in both worlds, so a divergence shows
	## its run-up and not just its result.
	var history: Dictionary[int, PackedStringArray] = {}
	## Where each body stood before this tick, in both worlds - the last place
	## the two were still twins - so the divergence can be re-asked from there.
	var before: Dictionary[int, Array] = {}
	for tick: int in TICK_LIMIT:
		for entity_id: int in one.actor_ids():
			before[entity_id] = [one.get_entity(entity_id).position, two.get_entity(entity_id).position]
		one.step((baked["crew"] as BotCrew).drain(one, one.tick))
		two.step((swapped["crew"] as BotCrew).drain(two, two.tick))
		for entity_id: int in one.actor_ids():
			var mine: SimEntity = one.get_entity(entity_id)
			var theirs: SimEntity = two.get_entity(entity_id)
			var log: PackedStringArray = history.get(entity_id, PackedStringArray())
			log.append("    tick %d  baked %s intent %s | swapped %s intent %s" % [tick,
				_fmt(mine.position), _fmt(mine.move_intent),
				_fmt(_turn(theirs.position)), _fmt(-theirs.move_intent)])
			if log.size() > 6:
				log.remove_at(0)
			history[entity_id] = log
		for entity_id: int in one.sorted_entity_ids():
			var a: SimEntity = one.get_entity(entity_id)
			var b: SimEntity = two.get_entity(entity_id)
			var gap: float = INF if b == null else _turn(a.position).distance_to(b.position)
			worst = maxf(worst, gap if gap < TOLERANCE else 0.0)
			var why: String = _difference(a, b, gap)
			if why != "":
				print("FIRST DIVERGENCE at tick %d (%.1f s): entity %d (%s) - %s" % [
					tick, float(tick) / float(SimWorld.TICKS_PER_SECOND), entity_id, a.team, why])
				_describe("baked  ", a, baked["crew"], false)
				_describe("swapped", b, swapped["crew"], true)
				print("\n".join(history.get(entity_id, PackedStringArray())))
				if before.has(entity_id):
					_explain_reach(baked["crew"], swapped["crew"], entity_id, before[entity_id])
				print("largest sub-tolerance drift before it: %.4f" % worst)
				quit(1)
				return
	print("TWIN for %d ticks (largest drift %.4f)" % [TICK_LIMIT, worst])
	quit(0)

func _build(team_size: int, match_seed: int, swap: bool) -> Dictionary:
	var level: GreyBoxLevel = GreyBoxLevel.new(GreyBoxLevel.SafeVariant.B, GreyBoxLevel.LEVEL_PATH, team_size)
	if not level.is_loaded() or (swap and not level.swap_houses()):
		print("no two-team baked level")
		return {}
	var world: SimWorld = SimWorld.new(match_seed)
	if not world.configure(level.mode, level.tuning, level.zones, level.teams, level.collision, level.surface):
		for failure: String in world.content_failures:
			print("content rejected: %s" % failure)
		return {}
	world.add_system(MovementSystem.new())
	world.add_system(CarrySystem.new())
	world.add_system(CaptureSystem.new())
	world.add_system(ScoringSystem.new())
	world.add_system(MatchFlowSystem.new())
	world.populate_roster()
	var profile: BotProfileDef = level.bot_profile
	if _no_noise:
		profile = profile.duplicate() as BotProfileDef
		profile.choice_noise = 0.0
	var crew: BotCrew = BotCrew.create(profile, NavGraph.of(world.surface), world.rng.state)
	crew.fill_lobby(world, [] as Array[int], world.actor_ids().size())
	world.step([MatchCommand.start()])
	return {"world": world, "crew": crew}

## From where the body stood before the divergence, which route waypoints each
## world calls reachable - and, where they disagree, which blocker said no.
func _explain_reach(crew_one: BotCrew, crew_two: BotCrew, entity_id: int, stood: Array) -> void:
	var one: BotDirector = crew_one.director_for(entity_id)
	var two: BotDirector = crew_two.director_for(entity_id)
	if one == null or two == null:
		return
	var route_one: PackedVector3Array = one.route()
	var route_two: PackedVector3Array = two.route()
	var surface_one: WalkableSurface = one.nav.surface
	var surface_two: WalkableSurface = two.nav.surface
	print("  reachability from the last shared spot %s / twin %s:" % [_fmt(stood[0]), _fmt(stood[1])])
	var shared: int = mini(route_one.size(), route_two.size())
	for k: int in range(maxi(0, mini(one.leg(), two.leg()) - 1), shared):
		var here: bool = surface_one.is_reachable_between(stood[0], route_one[k])
		var there: bool = surface_two.is_reachable_between(stood[1], route_two[k])
		var flat_one: bool = surface_one.is_clear_between(stood[0], route_one[k])
		var flat_two: bool = surface_two.is_clear_between(stood[1], route_two[k])
		print("    waypoint %d %s  reachable %s/%s  clear %s/%s%s" % [k, route_one[k].round(),
			here, there, flat_one, flat_two, "   <-- DIFFERS" if here != there or flat_one != flat_two else ""])
		if flat_one != flat_two:
			_name_blocker("baked  ", one.nav.surface, stood[0], route_one[k])
			_name_blocker("swapped", two.nav.surface, stood[1], route_two[k])
		if k >= maxi(one.leg(), two.leg()) + 8:
			break

func _name_blocker(label: String, surface: WalkableSurface, from: Vector3, to: Vector3) -> void:
	var collision: WorldCollisionDef = surface._collision
	if not collision.contains(to, surface.radius):
		print("      %s: destination outside the shell" % label)
	for index: int in collision.blockers.size():
		var solid: AABB = collision.blockers[index].grow(surface.radius)
		var depth: float = WorldCollisionDef.penetration_depth(from, solid)
		var hits: bool = WorldCollisionDef.segment_hits_box(from, to, solid)
		if depth > 0.0 or hits:
			print("      %s: blocker %d %s  depth from %.6f to %.6f  slab hit %s" % [label, index,
				collision.blockers[index], depth, WorldCollisionDef.penetration_depth(to, solid), hits])

func _fmt(v: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [v.x, v.y, v.z]

func _turn(point: Vector3) -> Vector3:
	return Vector3(2.0 * _pivot.x - point.x, point.y, 2.0 * _pivot.y - point.z)

func _difference(a: SimEntity, b: SimEntity, gap: float) -> String:
	if b == null:
		return "missing in the swapped world"
	if a.motion_state != b.motion_state:
		return "motion %s against %s" % [
			SimEntity.MotionState.keys()[a.motion_state], SimEntity.MotionState.keys()[b.motion_state]]
	if a.is_captured != b.is_captured:
		return "captured %s against %s" % [a.is_captured, b.is_captured]
	if a.carrying_id != b.carrying_id or a.carried_by != b.carried_by:
		return "carry differs"
	if a.stance != b.stance:
		return "stance differs"
	# A bot's heading turned with the world. Compared before position, because a
	# different choice shows here a tick before it shows as distance.
	if a.move_intent.distance_to(Vector3(-b.move_intent.x, b.move_intent.y, -b.move_intent.z)) > 0.01:
		return "heading %s against %s turned" % [_fmt(a.move_intent), _fmt(-b.move_intent)]
	if gap >= TOLERANCE:
		return "%.2f apart after turning" % gap
	return ""

func _describe(label: String, body: SimEntity, crew: BotCrew, turned_back: bool) -> void:
	var at: Vector3 = _turn(body.position) if turned_back else body.position
	var line: String = "  %s at %s (in baked coordinates) zone %s motion %s" % [
		label, at, body.zone_id, SimEntity.MotionState.keys()[body.motion_state]]
	var director: BotDirector = crew.director_for(body.id)
	if director != null and director.current_task() != null:
		var route: PackedVector3Array = director.route()
		var shown: PackedStringArray = PackedStringArray()
		for k: int in mini(route.size(), 4):
			shown.append(str((_turn(route[k]) if turned_back else route[k]).round()))
		line += "\n           task %s, route %d legs at leg %d: %s" % [
			BotTask.Kind.keys()[director.current_task().kind], route.size(), director.leg(),
			", ".join(shown)]
	print(line)
