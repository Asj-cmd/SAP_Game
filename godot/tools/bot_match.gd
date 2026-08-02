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
	world.step([MatchCommand.start()])
	var ticks: int = 0
	while world.match_phase != SimWorld.MatchPhase.MATCH_END and ticks < TICK_LIMIT:
		if stop_at >= 0 and ticks >= stop_at:
			break
		for event: SimEvent in world.step(crew.drain(world, world.tick)):
			tally[event.kind] = tally.get(event.kind, 0) + 1
		hashes.append(world.state_hash())
		ticks += 1

	return {
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
