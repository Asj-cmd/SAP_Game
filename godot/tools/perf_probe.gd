extends SceneTree
## Where the time goes, per tick, and how much of it is the blocker count.
##
##   godot --headless --path godot --script res://tools/perf_probe.gd
##
## "It feels laggy since the level got bigger" has two candidates that look
## identical from the chair - the simulation missing its tick budget, and the
## renderer missing its frame budget - and one of them is measurable here. The
## blocker sweep is the obvious suspect because WorldCollisionDef.blocks_segment
## is a linear scan and the house has twelve times the blockers the grey box
## had, but obvious is not measured.
##
## Blockers are DUPLICATED rather than removed to get a second data point. A
## smaller level would be a different level and the bots would play it
## differently; the same geometry listed twice is the same level costing twice
## as much to test, which isolates the count from everything else.

const TICKS: int = 600
const BUDGET_MS: float = 1000.0 / 30.0

func _initialize() -> void:
	var level: GreyBoxLevel = GreyBoxLevel.new()
	if not level.is_loaded():
		print("no baked level")
		quit(1)
		return

	print("tick budget  %.2f ms at 30 Hz" % BUDGET_MS)
	print("blockers     %d" % level.collision.blockers.size())
	_split(level)
	_route_cost(level)
	_blocker_slope(level)
	_raw_cost(level)
	quit(0)

## Where the tick actually goes: deciding what to do, or doing it.
func _split(level: GreyBoxLevel) -> void:
	var world: SimWorld = _world(level, level.collision, level.surface)
	var crew: BotCrew = BotCrew.create(level.bot_profile, NavGraph.of(world.surface), 11)
	crew.fill_lobby(world, [], world.actor_ids().size())
	print("actors       %d, of them bots %d" % [world.actor_ids().size(), crew.actor_ids().size()])
	world.step([MatchCommand.start()])
	for i: int in 90:
		world.step(crew.drain(world, world.tick))

	var think: int = 0
	var act: int = 0
	var each: PackedFloat32Array = PackedFloat32Array()
	for i: int in TICKS:
		var a: int = Time.get_ticks_usec()
		var commands: Array[SimCommand] = crew.drain(world, world.tick)
		var b: int = Time.get_ticks_usec()
		world.step(commands)
		var c: int = Time.get_ticks_usec()
		act += c - b
		think += b - a
		each.append(float(c - a) / 1000.0)
	var think_ms: float = float(think) / 1000.0 / float(TICKS)
	var act_ms: float = float(act) / 1000.0 / float(TICKS)
	print("bot thinking %6.3f ms/tick  %5.1f%% of budget" % [
		think_ms, 100.0 * think_ms / BUDGET_MS])
	print("simulation   %6.3f ms/tick  %5.1f%% of budget" % [
		act_ms, 100.0 * act_ms / BUDGET_MS])
	print("total        %6.3f ms/tick  %5.1f%% of budget" % [
		think_ms + act_ms, 100.0 * (think_ms + act_ms) / BUDGET_MS])

	# The mean is the wrong statistic for "it feels laggy". A stutter is one
	# tick that misses its budget while the average stays comfortable, and a
	# player feels the tick that missed, not the ninety-nine that did not.
	var sorted_ticks: Array[float] = []
	for value: float in each:
		sorted_ticks.append(value)
	sorted_ticks.sort()
	var over: int = 0
	for value: float in sorted_ticks:
		if value > BUDGET_MS:
			over += 1
	print("spread       p50 %.2f  p99 %.2f  worst %.2f ms   %d of %d ticks over budget" % [
		sorted_ticks[int(sorted_ticks.size() * 0.5)],
		sorted_ticks[int(sorted_ticks.size() * 0.99)],
		sorted_ticks[sorted_ticks.size() - 1], over, sorted_ticks.size()])

	# And the simulation on its own, with nobody issuing commands: what a tick
	# costs when the only thing happening is gravity and eight idle bodies.
	var quiet: SimWorld = _world(level, level.collision, level.surface)
	quiet.step([MatchCommand.start()])
	for i: int in 90:
		quiet.step([])
	var started: int = Time.get_ticks_usec()
	for i: int in TICKS:
		quiet.step([])
	var idle_ms: float = float(Time.get_ticks_usec() - started) / 1000.0 / float(TICKS)
	print("  of which, standing still and doing nothing: %.3f ms/tick" % idle_ms)

## Cost against blocker count, with the copies INTERLEAVED.
##
## Appending them measured nothing: blocks_segment returns on the first blocker
## it hits, so a test that was going to hit one exited before reaching any copy,
## and only the tests that hit nothing paid. Interleaved, a hit that was at
## position i is now at 3i, which is the thing being asked about.
func _blocker_slope(level: GreyBoxLevel) -> void:
	for factor: int in [1, 3]:
		var collision: WorldCollisionDef = WorldCollisionDef.new()
		collision.bounds = level.collision.bounds
		var blockers: Array[AABB] = []
		for blocker: AABB in level.collision.blockers:
			for i: int in factor:
				blockers.append(blocker)
		collision.blockers = blockers
		var world: SimWorld = _world(level, collision, level.surface if factor == 1 else null)
		if world == null:
			continue
		var crew: BotCrew = BotCrew.create(level.bot_profile, NavGraph.of(world.surface), 11)
		crew.fill_lobby(world, [], world.actor_ids().size())
		world.step([MatchCommand.start()])
		for i: int in 90:
			world.step(crew.drain(world, world.tick))
		var started: int = Time.get_ticks_usec()
		for i: int in TICKS:
			world.step(crew.drain(world, world.tick))
		print("x%d blockers (%4d, interleaved)  %6.3f ms/tick" % [
			factor, blockers.size(),
			float(Time.get_ticks_usec() - started) / 1000.0 / float(TICKS)])

func _world(level: GreyBoxLevel, collision: WorldCollisionDef,
		surface: WalkableSurfaceDef) -> SimWorld:
	var world: SimWorld = SimWorld.new(20260804)
	if not world.configure(level.mode, level.tuning, level.zones, level.teams,
		collision, surface):
		print("content rejected")
		return null
	world.add_system(MovementSystem.new())
	world.add_system(CarrySystem.new())
	world.add_system(CaptureSystem.new())
	world.add_system(ScoringSystem.new())
	world.add_system(MatchFlowSystem.new())
	world.populate_roster()
	return world

## What one swept test costs. Worst case on purpose: a move through open air
## hits nothing, so it scans the whole list.
func _raw_cost(level: GreyBoxLevel) -> void:
	var from: Vector3 = level.teams[0].spawn_points[0]
	var to: Vector3 = from + Vector3(14.7, 0.0, 0.0)
	var runs: int = 20000
	var started: int = Time.get_ticks_usec()
	for i: int in runs:
		level.collision.blocks_segment(from, to, level.tuning.actor_radius)
	print("one swept test that hits nothing, against %d blockers: %.1f us" % [
		level.collision.blockers.size(),
		float(Time.get_ticks_usec() - started) / float(runs)])

## What one re-route costs, and which part of it.
func _route_cost(level: GreyBoxLevel) -> void:
	var world: SimWorld = _world(level, level.collision, level.surface)
	if world == null:
		return
	var nav: NavGraph = NavGraph.of(world.surface)
	var from_point: Vector3 = level.teams[0].spawn_points[0]
	var to_point: Vector3 = level.teams[1].spawn_points[0]
	var runs: int = 20

	var started: int = Time.get_ticks_usec()
	for i: int in runs:
		world.surface.nearest(from_point)
		world.surface.nearest(to_point)
	var near_ms: float = float(Time.get_ticks_usec() - started) / 1000.0 / float(runs)

	started = Time.get_ticks_usec()
	var points: PackedVector3Array = PackedVector3Array()
	for i: int in runs:
		points = nav.route(from_point, to_point)
	var route_ms: float = float(Time.get_ticks_usec() - started) / 1000.0 / float(runs)

	print("one re-route  %.2f ms across %d stances, %d waypoints out, %d nodes settled" % [
		route_ms, world.surface.size(), points.size(), nav.last_expanded])
	print("  of which finding the two end stances: %.2f ms" % near_ms)
