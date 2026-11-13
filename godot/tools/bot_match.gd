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
## `--team-size=N` seats N a side instead of the level's own count; 0 keeps it.
var _team_size: int = 0
## `--mode.<field>=<value>` overrides one GameModeDef number for this run, so a
## tuning sweep is a loop over arguments rather than an edit per try. Applied on
## top of the mode the team size loads.
var _mode_overrides: Dictionary[String, String] = {}
## `--seed=N` plays a different match. One seed is one match: tuning against it
## alone fits the numbers to that match, so a sweep runs several.
var _seed: int = 20260802
## `--once` skips the second, determinism-checking run. For sweeps only; the
## gate in verify.mjs always plays twice.
var _once: bool = false
## `--swap-houses` gives each team the other's house - spawns, cash and every
## room it owns - while the seating order stays by team name. A side bias that
## follows the name is seating; one that follows the house is the layout.
var _swap_houses: bool = false

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
		if arg.begins_with("--team-size="):
			_team_size = int(arg.trim_prefix("--team-size="))
		if arg.begins_with("--mode.") and arg.contains("="):
			var pair: PackedStringArray = arg.trim_prefix("--mode.").split("=", true, 1)
			_mode_overrides[pair[0]] = pair[1]
		if arg.begins_with("--seed="):
			_seed = int(arg.trim_prefix("--seed="))
	_once = OS.get_cmdline_user_args().has("--once")
	_swap_houses = OS.get_cmdline_user_args().has("--swap-houses")
	var first: Dictionary = _play()
	var second: Dictionary = first if _once else _play()

	if first["digest"] != second["digest"]:
		_locate_divergence(first["hashes"], second["hashes"])

	if _once:
		print("\n--- ONE RUN (determinism not checked) ---")
	else:
		print("\n--- %s ---" % ("DETERMINISTIC" if first["digest"] == second["digest"] else "DIVERGED"))
	print("seed        %d" % _seed)
	print("ticks       %d" % first["ticks"])
	print("surface     %d stances, %d ms to build" % [first["nodes"], first["build_ms"]])
	print("team size   %d a side" % first["team_size"])
	print("mode        %s" % first["mode"])
	print("rounds won  %s" % first["rounds"])
	for line: String in first["round_log"]:
		print("              %s" % line)
	print("cash held   %s" % first["scores"])
	print("carries     %d pick-ups, %d deposits" % [first["pickups"], first["deposits"]])
	print("captures    %d seizures, %d rescues" % [first["captures"], first["rescues"]])
	print("winner      %s" % ("none - not decided in regulation" if first["winner"] == &"" else first["winner"]))
	print("encounters  %d within reach, %d of them where a seizure was legal, %d within sight" % [
		first["encounters"], first["seizable"], first["sightings"]])
	print("raiding     %s" % _raiding(first))
	for team_id: StringName in first["by_team"]:
		var counts: Dictionary = first["by_team"][team_id]
		print("  %-9s %d pick-ups, %d drops, seized %d times, %d s stalled" % [
			team_id, counts["pickups"], counts["drops"], counts["seized"], counts["stalls"]])
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
	# The grey box seats 1v1 for development; the game ships 2v2 to 4v4 (D8),
	# and each size has its own mode file.
	var level: GreyBoxLevel = GreyBoxLevel.new(GreyBoxLevel.SafeVariant.B, _level_path,
		_team_size if _team_size > 0 else GreyBoxLevel.DEFAULT_TEAM_SIZE)
	if not level.is_loaded():
		print("no baked level - run tools/bake_blockout.gd")
		quit(1)
		return {}
	if _swap_houses and not level.swap_houses():
		print("--swap-houses needs exactly two teams")
		quit(1)
		return {}
	for field: String in _mode_overrides:
		var current: Variant = level.mode.get(field)
		if current == null:
			print("no mode field %s" % field)
			quit(1)
			return {}
		level.mode.set(field, type_convert(_mode_overrides[field], typeof(current)))
	var tick_limit: int = _regulation_ticks(level.mode)

	var started: int = Time.get_ticks_msec()
	var world: SimWorld = SimWorld.new(_seed)
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
	## The same counts split by the acting body's team, plus seizures SUFFERED
	## and stalls. A side bias is invisible in match totals; this is where it shows.
	var by_team: Dictionary[StringName, Dictionary] = {}
	for team_id: StringName in world.sorted_team_ids():
		by_team[team_id] = {"pickups": 0, "drops": 0, "seized": 0, "stalls": 0}
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

	## One line per round played, drawn rounds included: a match without a winner
	## is either rounds that run out of time level, or too few rounds fitting in
	## the limit, and the totals alone cannot tell those apart.
	var round_log: Array[String] = []
	var round_began: int = 0

	world.step([MatchCommand.start()])
	var ticks: int = 0
	while world.match_phase != SimWorld.MatchPhase.MATCH_END and ticks < tick_limit:
		if stop_at >= 0 and ticks >= stop_at:
			break
		for event: SimEvent in world.step(crew.drain(world, world.tick)):
			tally[event.kind] = tally.get(event.kind, 0) + 1
			var counted: String = _team_counter(event.kind)
			var doer: SimEntity = world.get_entity(event.actor_id) if counted != "" else null
			if doer != null and by_team.has(doer.team):
				by_team[doer.team][counted] += 1
			if event.kind == MatchEvent.KIND_ROUND_STARTED:
				round_began = event.tick
			elif event.kind == MatchEvent.KIND_ROUND_ENDED:
				var ended: MatchEvent = event as MatchEvent
				round_log.append("round %d  %3d s  %-7s %-14s cash %s" % [
					ended.round_number,
					int(float(ended.tick - round_began) / float(SimWorld.TICKS_PER_SECOND)),
					"draw" if ended.winner == &"" else String(ended.winner),
					ended.reason,
					_per_team(world, false),
				])
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
					if by_team.has(body.team):
						by_team[body.team]["stalls"] += 1
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
		"round_log": round_log,
		"team_size": world.mode.team_size,
		"mode": "round %d s, jail %d s +%d s per repeat, target %d of %d, first to %d rounds, limit %d s" % [
			int(world.mode.round_seconds), int(world.mode.capture_seconds),
			int(world.mode.capture_escalation_seconds), world.mode.score_to_win(),
			world.mode.cash_per_team * 2, world.mode.rounds_to_win,
			int(float(tick_limit) / float(SimWorld.TICKS_PER_SECOND))],
		"encounters": encounters,
		"seizable": seizable,
		"sightings": sightings,
		"encounter_map": encounter_map,
		"away": away,
		"by_team": by_team,
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

## Which per-team counter an event feeds, or "" for none. The actor on a
## pick-up or drop is the carrier; on a capture it is the one seized.
func _team_counter(kind: StringName) -> String:
	match kind:
		CarryEvent.KIND_PICKED_UP:
			return "pickups"
		CarryEvent.KIND_DROPPED:
			return "drops"
		CaptureEvent.KIND_CAPTURED:
			return "seized"
	return ""

## How long a match may run before "no winner" is the verdict: the most rounds a
## best-of can need, each at full length. A drawn round is replayed, so draws eat
## into this rather than extending it - a size that keeps drawing fails here,
## which is the point. Derived from the mode so a longer round is not cut off by
## a limit written for a shorter one.
func _regulation_ticks(mode: GameModeDef) -> int:
	var rounds: int = 2 * mode.rounds_to_win - 1
	var per_round: float = mode.pre_round_seconds + mode.round_seconds + mode.round_end_seconds
	return SimWorld.seconds_to_ticks(float(rounds) * per_round) + 1

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
