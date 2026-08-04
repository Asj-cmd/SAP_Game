extends SceneTree
## Plays a whole match with bots on every seat, headless.
##
##   godot --headless --path godot --script res://tools/bot_match.gd
##
## The cheapest signal that the bots actually PLAY, as opposed to merely
## deciding things. A director that scores tasks correctly and never arrives
## anywhere passes every unit test in the suite and loses every match, and the
## only way to tell the difference is to let one run.
##
## Also a determinism probe: the same seed is played twice and the digests
## compared. Bots are simulation, so two runs of the same match must agree
## exactly - if they ever stop agreeing, replays and netcode are both already
## broken and this is where it should surface first.

const TICK_LIMIT: int = 30 * 60 * 6
## Ticks between stall samples, and how far a bot must travel in that time to
## count as making progress.
const STALL_WINDOW: int = 30
const STALL_DISTANCE: float = 60.0

func _initialize() -> void:
	var first: Dictionary = _play()
	var second: Dictionary = _play()

	if first["digest"] != second["digest"]:
		_locate_divergence(first["hashes"], second["hashes"])

	print("\n--- %s ---" % ("DETERMINISTIC" if first["digest"] == second["digest"] else "DIVERGED"))
	print("ticks       %d" % first["ticks"])
	print("surface     %d stances, %d ms to build" % [first["nodes"], first["build_ms"]])
	print("rounds won  %s" % first["rounds"])
	print("cash held   %s" % first["scores"])
	print("carries     %d pick-ups, %d deposits" % [first["pickups"], first["deposits"]])
	print("captures    %d seizures, %d rescues" % [first["captures"], first["rescues"]])
	print("winner      %s" % ("none - ran out of ticks" if first["winner"] == &"" else first["winner"]))
	print("stalls      %d second-long stalls while holding a task" % first["stalls"])
	for spot: String in first["stall_spots"]:
		print("              %s" % spot)
	quit(0 if first["digest"] == second["digest"] else 1)

## Finds the first tick two runs disagreed on, and shows what differed.
##
## The tick a desync is NOTICED is never the tick it happened; by the end of a
## match one divergent decision has moved every body on the board. Only the
## first disagreement says anything about the cause.
func _locate_divergence(left: PackedInt64Array, right: PackedInt64Array) -> void:
	var shared: int = mini(left.size(), right.size())
	for tick: int in shared:
		if left[tick] == right[tick]:
			continue
		print("first divergence at tick %d of %d" % [tick, shared])
		var before: Dictionary = _play(tick)
		var after: Dictionary = _play(tick)
		_show_difference(before["digest"], after["digest"])
		return
	print("hashes agree for %d ticks but final digests differ" % shared)

## Prints the entity records that disagree, rather than two long digests.
func _show_difference(left: String, right: String) -> void:
	var a: PackedStringArray = left.split(";")
	var b: PackedStringArray = right.split(";")
	var shown: int = 0
	for i: int in mini(a.size(), b.size()):
		if a[i] == b[i] or shown >= 4:
			continue
		print("  run 1: %s" % a[i])
		print("  run 2: %s" % b[i])
		shown += 1
	if shown == 0:
		print("  (records identical - the difference is in length: %d vs %d)" % [a.size(), b.size()])

func _play(stop_at: int = -1) -> Dictionary:
	var level: GreyBoxLevel = GreyBoxLevel.new()
	if not level.is_loaded():
		print("no baked level - run tools/bake_blockout.gd")
		quit(1)
		return {}

	var started: int = Time.get_ticks_msec()
	var world: SimWorld = SimWorld.new(20260802)
	if not world.configure(
		level.mode, level.tuning, level.zones, level.teams, level.collision, level.surface
	):
		for failure: String in world.content_failures:
			print("content rejected: %s" % failure)
		quit(1)
		return {}
	var build_ms: int = Time.get_ticks_msec() - started

	world.add_system(MovementSystem.new())
	world.add_system(CarrySystem.new())
	world.add_system(CaptureSystem.new())
	world.add_system(ScoringSystem.new())
	world.add_system(MatchFlowSystem.new())
	world.populate_roster()

	# Every seat, so the match is bot against bot. fill_lobby is handed no
	# humans at all, which is the case it has least to balance and the one that
	# exercises the directors hardest.
	var crew: BotCrew = BotCrew.create(level.bot_profile, NavGraph.of(world.surface), world.rng.state)
	crew.fill_lobby(world, [], world.actor_ids().size())

	var tally: Dictionary[StringName, int] = {}
	var hashes: PackedInt64Array = PackedInt64Array()

	# Stall detection. A bot that holds a task and does not move is stuck, and
	# "stuck in doorways" is a claim worth a number rather than an impression:
	# without one, a change to the steering can only be judged by watching.
	var anchor: Dictionary[int, Vector3] = {}
	var stalls: int = 0
	var stall_spots: Array[String] = []
	world.step([MatchCommand.start()])
	var ticks: int = 0
	while world.match_phase != SimWorld.MatchPhase.MATCH_END and ticks < TICK_LIMIT:
		if stop_at >= 0 and ticks >= stop_at:
			break
		for event: SimEvent in world.step(crew.drain(world, world.tick)):
			tally[event.kind] = tally.get(event.kind, 0) + 1
		hashes.append(world.state_hash())
		ticks += 1

		# Sampled on a fixed cadence rather than every tick: a bot pausing to
		# think is not stuck, and a second of no progress while holding a task is.
		if world.is_live() and ticks % STALL_WINDOW == 0:
			for actor_id: int in crew.actor_ids():
				var body: SimEntity = world.get_entity(actor_id)
				var task: BotTask = crew.director_for(actor_id).current_task()
				if body == null or task == null or task.is_none():
					anchor.erase(actor_id)
					continue
				if anchor.has(actor_id) and anchor[actor_id].distance_to(body.position) < STALL_DISTANCE:
					stalls += 1
					if stall_spots.size() < 6:
						# The position alone says WHERE but not WHY. A bot with
						# no route is a routing failure; one with a route it is
						# not following is a steering failure; one that is
						# BLOCKED is neither.
						var director: BotDirector = crew.director_for(actor_id)
						stall_spots.append("%s  %s  route %d leg %d  %s" % [
							body.position.round(),
							BotTask.Kind.keys()[task.kind],
							director.route().size(),
							director.leg(),
							SimEntity.MotionState.keys()[body.motion_state],
						])
				anchor[actor_id] = body.position

	return {
		"stalls": stalls,
		"stall_spots": stall_spots,
		"hashes": hashes,
		"digest": world.state_digest(),
		"ticks": ticks,
		"nodes": world.surface.size(),
		"build_ms": build_ms,
		"rounds": _per_team(world, true),
		"scores": _per_team(world, false),
		"pickups": tally.get(CarryEvent.KIND_PICKED_UP, 0),
		"deposits": tally.get(CarryEvent.KIND_DROPPED, 0),
		"captures": tally.get(CaptureEvent.KIND_CAPTURED, 0),
		"rescues": tally.get(CaptureEvent.KIND_RELEASED, 0),
		"winner": world.match_winner,
	}

func _per_team(world: SimWorld, rounds: bool) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for team_id: StringName in world.sorted_team_ids():
		parts.append("%s %d" % [
			team_id,
			world.round_wins_for(team_id) if rounds else world.score_for(team_id),
		])
	return "  ".join(parts)
