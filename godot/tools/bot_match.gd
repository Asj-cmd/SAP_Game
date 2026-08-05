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
## Bucket size for grouping stall positions. Doorways are 240 across, so a
## bucket this size tells clustering from scattering without smearing them.
const STALL_BUCKET: float = 120.0

## An ENCOUNTER is two opponents close enough that the round's core interaction
## - seizing somebody - was physically available. A SIGHTING is close enough to
## have noticed each other and changed plan.
##
## Counted as edge-triggered events, not ticks: two bodies circling each other
## for five seconds is one encounter, and counting ticks would make a single
## standoff outrank a match full of brief meetings. Released at 1.6x so a pair
## hovering on the boundary does not rack up a hundred of them.
const SIGHT_RANGE: float = 700.0
const RELEASE: float = 1.6
## Where encounters happen, on the same bucket as the stall map so the two can
## be read side by side.
const ENCOUNTER_BUCKET: float = 400.0

var _lone: bool = false
var _level_path: String = GreyBoxLevel.LEVEL_PATH

## `--lone` seats one idle human and one bot, which is the shape the playtest
## actually reported: a single bot in a doorway with one person about. Bot
## against bot is a different situation - two bodies competing for the same gap -
## and conflating them is how a congestion problem gets diagnosed as a
## navigation one.
func _initialize() -> void:
	_lone = OS.get_cmdline_user_args().has("--lone")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):
			_level_path = arg.trim_prefix("--level=")
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
	print("encounters  %d within reach, %d of them where a seizure was legal, %d within sight" % [
		first["encounters"], first["seizable"], first["sightings"]])
	print("raiding     %s" % _raiding(first))
	_report_places("encounters", first["encounter_map"], first["encounters"], ENCOUNTER_BUCKET)
	print("stalls      %d seconds trying to move and getting nowhere" % first["stalls"])
	print("idle        %d seconds standing still by choice" % first["idles"])
	for spot: String in first["stall_spots"]:
		print("              %s" % spot)
	_report_clustering(first["stall_map"], first["stalls"])
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
	var level: GreyBoxLevel = GreyBoxLevel.new(GreyBoxLevel.SafeVariant.B, _level_path)
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
	var seated: Array[int] = []
	if _lone:
		seated.append(world.actor_ids()[0]) # an idle human, holding a seat
	crew.fill_lobby(world, seated, world.actor_ids().size())

	var tally: Dictionary[StringName, int] = {}
	var hashes: PackedInt64Array = PackedInt64Array()

	# Stall detection. A bot that holds a task and does not move is stuck, and
	# "stuck in doorways" is a claim worth a number rather than an impression:
	# without one, a change to the steering can only be judged by watching.
	var anchor: Dictionary[int, Vector3] = {}
	var stalls: int = 0
	var idles: int = 0
	var stall_spots: Array[String] = []
	## Where stalls happen, bucketed. Clustered means doorways; scattered means
	## something else entirely, and they should not be chased together.
	var stall_map: Dictionary[Vector3i, int] = {}

	# Encounters. The layout metric that ways-in is blind to: a house nobody can
	# camp is worth nothing if the two teams never meet in it.
	var contact_range: float = level.tuning.capture_range
	var touching: Dictionary[Vector2i, bool] = {}
	var watching: Dictionary[Vector2i, bool] = {}
	var encounters: int = 0
	var seizable: int = 0
	var sightings: int = 0
	var encounter_map: Dictionary[Vector3i, int] = {}
	## Ticks each team spends standing on ground the other side owns. Separates
	## "they never leave home" from "they cross and never meet", which are
	## different problems with different fixes.
	var away: Dictionary[StringName, int] = {}
	var live_ticks: int = 0

	world.step([MatchCommand.start()])
	var ticks: int = 0
	while world.match_phase != SimWorld.MatchPhase.MATCH_END and ticks < TICK_LIMIT:
		if stop_at >= 0 and ticks >= stop_at:
			break
		for event: SimEvent in world.step(crew.drain(world, world.tick)):
			tally[event.kind] = tally.get(event.kind, 0) + 1
		hashes.append(world.state_hash())
		ticks += 1

		if world.is_live():
			live_ticks += 1
			var actors: Array[int] = world.actor_ids()
			for i: int in actors.size():
				var one: SimEntity = world.get_entity(actors[i])
				var standing: ZoneDef = world.zone_at(one.position)
				if standing != null and standing.owner_team != &"" 					and standing.owner_team != one.team:
					away[one.team] = away.get(one.team, 0) + 1
				for j: int in range(i + 1, actors.size()):
					var two: SimEntity = world.get_entity(actors[j])
					if two.team == one.team:
						continue
					var pair: Vector2i = Vector2i(actors[i], actors[j])
					var apart: float = one.position.distance_to(two.position)
					if _crossed(touching, pair, apart, contact_range):
						encounters += 1
						# Meeting is not the same as being able to do anything
						# about it. A seizure needs both bodies in ONE room and
						# that room owned by one of them - so every encounter in
						# the garden is a near miss by rule, not by skill.
						if _seizable(world, one, two):
							seizable += 1
						var midpoint: Vector3 = (one.position + two.position) * 0.5
						var bucket: Vector3i = Vector3i(
							int(midpoint.x / ENCOUNTER_BUCKET), 0,
							int(midpoint.z / ENCOUNTER_BUCKET))
						encounter_map[bucket] = encounter_map.get(bucket, 0) + 1
					if _crossed(watching, pair, apart, SIGHT_RANGE):
						sightings += 1

		# Sampled on a fixed cadence rather than every tick: a bot pausing to
		# think is not stuck, and a second of no progress while holding a task is.
		if world.is_live() and ticks % STALL_WINDOW == 0:
			for actor_id: int in crew.actor_ids():
				var body: SimEntity = world.get_entity(actor_id)
				var task: BotTask = crew.director_for(actor_id).current_task()
				if body == null or task == null or task.is_none():
					anchor.erase(actor_id)
					continue
				# IDLE is not stuck. A bot standing at the end of a patrol has
				# chosen to be there; counting it as a stall buries the ones
				# that are trying to move and failing, which are the only kind
				# worth chasing. Reported separately rather than dropped -
				# a bot idle for most of a match is its own problem.
				var trying: bool = body.motion_state != SimEntity.MotionState.IDLE
				if anchor.has(actor_id) and anchor[actor_id].distance_to(body.position) < STALL_DISTANCE:
					if not trying:
						idles += 1
						anchor[actor_id] = body.position
						continue
					stalls += 1
					var bucket: Vector3i = Vector3i(
						int(body.position.x / STALL_BUCKET),
						0,
						int(body.position.z / STALL_BUCKET)
					)
					stall_map[bucket] = stall_map.get(bucket, 0) + 1
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
		"encounters": encounters,
		"seizable": seizable,
		"sightings": sightings,
		"encounter_map": encounter_map,
		"away": away,
		"live_ticks": maxi(live_ticks, 1),
		"idles": idles,
		"stall_map": stall_map,
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

## Are the stalls in a few places, or everywhere?
##
## The distinction decides whether this counter is measuring the reported bug at
## all. A handful of buckets holding most of the stalls means doorways; stalls
## spread thinly over dozens of buckets means something that happens wherever a
## bot happens to be, which is a different problem wearing the same number.
func _report_clustering(stall_map: Dictionary, total: int) -> void:
	if total <= 0:
		print("clustering   no stalls to place")
		return
	var buckets: Array[Vector3i] = stall_map.keys()
	buckets.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		if stall_map[a] != stall_map[b]:
			return stall_map[a] > stall_map[b]
		return var_to_str(a) < var_to_str(b))

	var worst: int = 0
	for i: int in mini(5, buckets.size()):
		worst += stall_map[buckets[i]]
	print("clustering   %d places held stalls; the worst 5 hold %d of %d (%d%%)" % [
		buckets.size(), worst, total, int(100.0 * float(worst) / float(total)),
	])
	for i: int in mini(5, buckets.size()):
		var at: Vector3i = buckets[i]
		print("              %5d stalls near (%d, %d)" % [
			stall_map[at], int(at.x * STALL_BUCKET), int(at.z * STALL_BUCKET),
		])

## Did this pair just come inside `range`? Edge-triggered, with hysteresis, so a
## standoff on the boundary is one event rather than a hundred.
func _crossed(state: Dictionary[Vector2i, bool], pair: Vector2i,
		apart: float, range_limit: float) -> bool:
	var was: bool = state.get(pair, false)
	if not was and apart <= range_limit:
		state[pair] = true
		return true
	if was and apart > range_limit * RELEASE:
		state[pair] = false
	return false

## How much of the live match each side spent on the other side's ground.
##
## Near zero means the teams are not raiding at all and the encounter count says
## nothing about the layout. Healthy means they cross, and a low encounter count
## then IS a layout result.
func _raiding(result: Dictionary) -> String:
	var away: Dictionary = result["away"]
	var live: int = result["live_ticks"]
	var parts: PackedStringArray = PackedStringArray()
	var teams: Array = away.keys()
	teams.sort()
	if teams.is_empty():
		return "neither side set foot on enemy ground"
	for team: StringName in teams:
		parts.append("%s %d%%" % [team, int(round(100.0 * float(away[team]) / float(live)))])
	return "%s of the match on enemy ground (per body, summed)" % ", ".join(parts)

## Could either of these two have seized the other, standing where they are?
##
## The same conditions CaptureSystem enforces: one room, shared, owned by one of
## them, not a holding pen.
func _seizable(world: SimWorld, one: SimEntity, two: SimEntity) -> bool:
	var here: ZoneDef = world.zone_at(one.position)
	var there: ZoneDef = world.zone_at(two.position)
	if here == null or there == null or here.id != there.id:
		return false
	if here.role == ZoneDef.Role.JAIL:
		return false
	return here.is_owned_by(one.team) or here.is_owned_by(two.team)

## Where something happened, bucketed, worst first. Same shape as the stall
## clustering so a layout can be read on both at once.
func _report_places(label: String, places: Dictionary, total: int, bucket: float) -> void:
	if places.is_empty():
		print("%-11s nowhere to place" % label)
		return
	var keys: Array = places.keys()
	keys.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		if places[a] != places[b]:
			return places[a] > places[b]
		return a.x < b.x if a.x != b.x else a.z < b.z)
	var shown: int = mini(4, keys.size())
	var held: int = 0
	for i: int in shown:
		held += places[keys[i]]
	print("%-11s %d places; the worst %d hold %d of %d" % [label, keys.size(), shown, held, total])
	for i: int in shown:
		print("              %5d near (%d, %d)" % [
			places[keys[i]], int((float(keys[i].x) + 0.5) * bucket),
			int((float(keys[i].z) + 0.5) * bucket)])
