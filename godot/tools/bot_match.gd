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
## `--tuning.<field>=<value>` does the same for one TuningDef number (P0-11:
## `--tuning.move_speed=440` replays the old pace beside the new one).
var _tuning_overrides: Dictionary[String, String] = {}
## `--bot.<field>=<value>` does the same for one BotProfileDef number (P3-3d:
## `--bot.risk_weight=900` asks whether the bots, not the rules, cause a result).
var _bot_overrides: Dictionary[String, String] = {}
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
## `--stall-log` prints every stall second as it happens (tick, body, place,
## task, leg, and what it was up against), not only the first six.
var _stall_log: bool = false
## `--why-idle` prints, for the first four bots that stand still this long, every
## errand open to them and what each scored (see _print_options).
var _why_idle: bool = false
const WHY_IDLE_AFTER: int = 20
## Floor-to-floor height, to tell a body on a flight from one on a floor.
const STOREY: float = 360.0
const GROUND: float = 300.0

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
		if arg.begins_with("--tuning.") and arg.contains("="):
			var pair: PackedStringArray = arg.trim_prefix("--tuning.").split("=", true, 1)
			_tuning_overrides[pair[0]] = pair[1]
		if arg.begins_with("--bot.") and arg.contains("="):
			var pair: PackedStringArray = arg.trim_prefix("--bot.").split("=", true, 1)
			_bot_overrides[pair[0]] = pair[1]
		if arg.begins_with("--seed="):
			_seed = int(arg.trim_prefix("--seed="))
	_once = OS.get_cmdline_user_args().has("--once")
	_stall_log = OS.get_cmdline_user_args().has("--stall-log")
	_why_idle = OS.get_cmdline_user_args().has("--why-idle")
	_swap_houses = OS.get_cmdline_user_args().has("--swap-houses")
	if Array(OS.get_cmdline_user_args()).any(func(a: String) -> bool: return a.begins_with("--chase")):
		_run_chases()
		quit(0)
		return
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
	var why: Dictionary = first["stall_why"]
	var notes: Array = why.keys()
	notes.sort_custom(func(a: String, b: String) -> bool:
		return why[a] > why[b] if why[a] != why[b] else a < b)
	print("stalled     " + ", ".join(notes.map(func(note: String) -> String: return "%s %d" % [note, why[note]])))
	var errands: Dictionary = first["stall_errands"]
	var worst: Array = errands.keys()
	worst.sort_custom(func(a: String, b: String) -> bool:
		return errands[a] > errands[b] if errands[a] != errands[b] else a < b)
	for i: int in mini(8, worst.size()):
		print("              %4d s  %s" % [errands[worst[i]], worst[i]])
	var waits: Dictionary = first["idle_errands"]
	var longest: Array = waits.keys()
	longest.sort_custom(func(a: String, b: String) -> bool:
		return waits[a] > waits[b] if waits[a] != waits[b] else a < b)
	print("idle for    (the 8 longest)")
	for i: int in mini(8, longest.size()):
		print("              %4d s  %s" % [waits[longest[i]], longest[i]])
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
	for field: String in _tuning_overrides:
		var current: Variant = level.tuning.get(field)
		if current == null:
			print("no tuning field %s" % field)
			quit(1)
			return {}
		level.tuning.set(field, type_convert(_tuning_overrides[field], typeof(current)))
	for field: String in _bot_overrides:
		var current: Variant = level.bot_profile.get(field)
		if current == null:
			print("no bot profile field %s" % field)
			quit(1)
			return {}
		level.bot_profile.set(field, type_convert(_bot_overrides[field], typeof(current)))
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
	# Zones patrolled somewhere other than their box's centre (NavGraph.zone_point).
	for zone_id: StringName in world.zone_ids_in_resolution_order():
		var zone: ZoneDef = world.zones[zone_id]
		var near_a: Vector3 = crew.nav.zone_point(world, zone, Vector3.ZERO)
		var near_b: Vector3 = crew.nav.zone_point(world, zone, Vector3(1.0e5, 0.0, 1.0e5))
		if near_a != zone.bounds.get_center():
			print("patrol      %s at %s%s, not its centre %s" % [zone_id, near_a.round(),
				"" if near_b == near_a else " / %s" % near_b.round(), zone.bounds.get_center().round()])

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
	## What each stalled body was up against (see _stall_company).
	var stall_why: Dictionary[String, int] = {}
	var stall_errands: Dictionary[String, int] = {}
	var idle_errands: Dictionary[String, int] = {}
	## Consecutive idle samples per bot, for --why-idle.
	var idle_run: Dictionary[int, int] = {}
	var why_shown: int = 0

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
						# What it is standing still FOR. A patroller at its post is
						# fine; a bot with cash to fetch that is not moving is not.
						var waiting: BotDirector = crew.director_for(actor_id)
						var idle_for: String = "%s %s near (%d, %d, %d)  leg %d of %d" % [
							BotTask.Kind.keys()[task.kind], task.zone_id,
							int(body.position.x / STALL_BUCKET) * int(STALL_BUCKET), int(body.position.y),
							int(body.position.z / STALL_BUCKET) * int(STALL_BUCKET),
							waiting.leg(), waiting.route().size()]
						idle_errands[idle_for] = idle_errands.get(idle_for, 0) + 1
						idle_run[actor_id] = idle_run.get(actor_id, 0) + 1
						if _why_idle and idle_run[actor_id] == WHY_IDLE_AFTER and why_shown < 4:
							why_shown += 1
							_print_options(world, crew, body, ticks)
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
					var why: String = _stall_company(world, crew, body, task, anchor, stall_why)
					var walking: BotDirector = crew.director_for(actor_id)
					var line: PackedVector3Array = walking.route()
					# The same errand stalling at the same place, counted: the first
					# six samples are whatever happened first, not what happened most.
					var errand: String = "%s %s near (%d, %d, %d)  leg %d of %d  to %s" % [
						BotTask.Kind.keys()[task.kind], task.zone_id,
						bucket.x * int(STALL_BUCKET), int(body.position.y), bucket.z * int(STALL_BUCKET),
						walking.leg(), line.size(),
						line[line.size() - 1].round() if not line.is_empty() else Vector3.ZERO]
					stall_errands[errand] = stall_errands.get(errand, 0) + 1
					if _stall_log:
						print("stall t%d  #%d %s  %s  %s %s leg %d/%d  %s" % [ticks, actor_id, body.team,
							body.position.round(), BotTask.Kind.keys()[task.kind], task.zone_id,
							walking.leg(), line.size(), why])
					if stall_spots.size() < 6:
						# The position alone says WHERE but not WHY. A bot with
						# no route is a routing failure; one with a route it is
						# not following is a steering failure; one that is
						# BLOCKED is neither.
						var director: BotDirector = crew.director_for(actor_id)
						# Where the route ENDS, and for which zone: a stall at leg 0
						# of a one-point route is a destination problem, and only
						# the destination says which one.
						var bound: PackedVector3Array = director.route()
						stall_spots.append("%s  %s %s  route %d leg %d  to %s  %s" % [
							body.position.round(),
							BotTask.Kind.keys()[task.kind],
							task.zone_id,
							bound.size(),
							director.leg(),
							bound[bound.size() - 1].round() if not bound.is_empty() else Vector3.ZERO,
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
		"stall_why": stall_why,
		"stall_errands": stall_errands,
		"idle_errands": idle_errands,
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

## Everything a bot could be doing and what each is worth to it, for a bot that
## has stood still for WHY_IDLE_AFTER seconds (`--why-idle`). The same sum
## UtilityScorer does, without the noise, with its parts shown: a bot standing
## at a patrol post while there is cash to fetch has a reason, and it is one of
## distance (-1 = no walk there), threats, or a team-mate's claim.
func _print_options(world: SimWorld, crew: BotCrew, body: SimEntity, ticks: int) -> void:
	var director: BotDirector = crew.director_for(body.id)
	var profile: BotProfileDef = director.profile
	var claims: Dictionary[String, int] = crew._claims()
	print("why idle    t%d  #%d %s at %s, on %s %s" % [ticks, body.id, body.team, body.position.round(),
		BotTask.Kind.keys()[director.current_task().kind], director.current_task().zone_id])
	var lines: Array[String] = []
	for task: BotTask in director._candidates(world, body):
		var node: int = director.nav.stance_near(task.destination)
		var distance: float = director.nav.distance_by_hops(director._hops, node)
		var threats: int = director._threats(world, body, task)
		var claimed: bool = claims.has(task.key()) and claims[task.key()] != body.id
		var score: float = UtilityScorer.score(profile, task.kind, distance, threats,
			task.matches(director.current_task()), claimed, 0.0, director._bonus(world, body, task))
		if task.kind == BotTask.Kind.PATROL and not task.matches(director.current_task()):
			continue
		lines.append("              %-8s %-14s score %8.0f  distance %6.0f  threats %d  %s to %s (stance %s)" % [
			BotTask.Kind.keys()[task.kind], task.zone_id, score, distance, threats,
			"claimed by #%d" % claims[task.key()] if claimed else "unclaimed", task.destination.round(),
			world.surface.nodes[node].round() if node >= 0 else Vector3.ZERO])
	for line: String in lines:
		print(line)

## What a stalled body is up against, tallied into `why` and returned as text.
##
## "Stalled at a stairwell" does not say whether the body is pushing at a wall,
## at a team-mate going the same way, or at an enemy coming the other way, and
## each of those has a different fix. Counted per stall second:
##   alone / by a team-mate / by an enemy (the nearest body within 2.5 radii);
##   whether that body is ALSO going nowhere (a mutual jam, not a queue);
##   whether this body is the lower id of the pair (the give-way rule in
##   BotDirector._steer has only the HIGHER id back off);
##   three or more bodies in one knot; off the two floor levels (on a flight).
func _stall_company(world: SimWorld, crew: BotCrew, body: SimEntity, task: BotTask,
		anchor: Dictionary[int, Vector3], why: Dictionary[String, int]) -> String:
	var reach: float = world.tuning.actor_radius * 2.5
	var nearest: SimEntity = null
	var nearest_gap: float = INF
	var company: int = 0
	for other_id: int in world.actor_ids():
		var other: SimEntity = world.get_entity(other_id)
		if other_id == body.id or other == null or other.is_captured:
			continue
		var gap: float = body.position.distance_to(other.position)
		if gap > reach:
			continue
		company += 1
		if gap < nearest_gap:
			nearest_gap = gap
			nearest = other
	var notes: PackedStringArray = PackedStringArray()
	notes.append("task " + String(BotTask.Kind.keys()[task.kind]))
	notes.append("state " + String(SimEntity.MotionState.keys()[body.motion_state]))
	var feet: float = body.position.y - world.tuning.actor_radius
	if absf(fposmod(feet - GROUND + 0.5 * STOREY, STOREY) - 0.5 * STOREY) > 20.0:
		notes.append("on a flight")
	if nearest == null:
		notes.append("alone")
	else:
		notes.append("by a team-mate" if nearest.team == body.team else "by an enemy")
		notes.append("the lower id" if body.id < nearest.id else "the higher id")
		# The other body's anchor is its position a window ago or (if already
		# visited this pass) now; either way a body still within STALL_DISTANCE of
		# it has gone nowhere.
		if anchor.has(nearest.id) and anchor[nearest.id].distance_to(nearest.position) < STALL_DISTANCE:
			notes.append("partner stuck too")
		var partner: BotDirector = crew.director_for(nearest.id)
		if partner != null and partner.current_task() != null:
			notes.append("partner " + String(BotTask.Kind.keys()[partner.current_task().kind]))
		if company >= 2:
			notes.append("3+ bodies")
	for note: String in notes:
		why[note] = why.get(note, 0) + 1
	return ", ".join(notes) + ("" if nearest == null else "  (#%d at %s)" % [nearest.id, nearest.position.round()])

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

# ---- staged chases (PT4-8) ----
#
# `--chase` plays short staged scenes on the real house instead of a match, to
# count how often a bot catches a thief and how often a human-like chaser
# catches a bot. 3v3 seats; the two bodies in the scene are the first of each
# family, everybody else stands still on the neutral lot, far away. The start
# spots are a fixed table drawn from the level (one per room of the robbed
# family's ground, the jail excepted), never random. `--chase=AB` plays only
# those scenes.
#
#   A  a scripted runner (the second family) carries the first family's cash
#      home along the nav route; a first-family bot starts 300-500 BEHIND it.
#   B  the same runner; the bot starts off to the SIDE of the runner's way
#      home, about 400 ahead along it (the cut-off case).
#   C  a first-family bot carrying the second family's cash home meets an
#      intruder 300 ahead on its way, walking the other way. Caught = seized,
#      kept = still holding the cash when it seized.
#   R  the reverse of A: a second-family bot carries the first family's cash
#      home and a scripted chaser that steers straight at it starts behind.
#
# A runner that reaches ground the chasing family does not own has escaped (a
# seizure there is not legal); CHASE_SECONDS without either is a miss.

const CHASE_SECONDS: float = 15.0
const CHASE_ARRIVE: float = 30.0
const CHASE_LOOKAHEAD: int = 8
## A human chaser re-aims this often, and runs straight at a target this close
## with nothing in between.
const HUMAN_REAIM_SECONDS: float = 0.25
const HUMAN_STRAIGHT: float = 350.0

func _run_chases() -> void:
	var level: GreyBoxLevel = GreyBoxLevel.new(GreyBoxLevel.SafeVariant.B, _level_path, 3)
	if not level.is_loaded():
		print("no baked level - run tools/bake_blockout.gd")
		return
	for field: String in _bot_overrides:
		var current: Variant = level.bot_profile.get(field)
		if current == null:
			print("no bot profile field %s" % field)
			return
		level.bot_profile.set(field, type_convert(_bot_overrides[field], typeof(current)))
	var probe: SimWorld = _chase_world(level)
	if probe == null:
		return
	var nav: NavGraph = NavGraph.of(probe.surface)
	var teams: Array[StringName] = probe.sorted_team_ids()
	var robbed: StringName = teams[0]
	var robber: StringName = teams[1]
	var plans: Dictionary[String, Array] = {
		"A": _plan_runs(probe, nav, robbed, robber, false),
		"B": _plan_runs(probe, nav, robbed, robber, true),
		"C": _plan_carries(probe, nav, robbed, robber),
	}
	plans["R"] = plans["A"]
	var only: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--chase="):
			only = arg.trim_prefix("--chase=")
	print("chase: %s robbed, %s robbing; %d s a scene" % [robbed, robber, int(CHASE_SECONDS)])
	for kind: String in ["A", "B", "C", "R"]:
		if only != "" and not only.contains(kind):
			continue
		var caught: int = 0
		var kept: int = 0
		var took: float = 0.0
		var scenes: Array = plans[kind]
		for i: int in scenes.size():
			var plan: Dictionary = scenes[i]
			var result: Dictionary = _stage(level, nav, kind, plan, robbed, robber)
			if result["caught"]:
				caught += 1
				took += float(result["seconds"])
				if result["kept"]:
					kept += 1
			print("  %s%d  thief %s  chaser %s  %s" % [kind, i + 1, (plan["thief"] as Vector3).round(),
				(plan["chaser"] as Vector3).round(), result["note"]])
		var held: String = (", %d of them still carrying" % kept) if kind == "C" else ""
		print("%s  caught %d of %d, mean %.1f s to catch%s" % [kind, caught, scenes.size(),
			took / float(maxi(caught, 1)), held])

## A fresh 3v3 world on `level`, played through its countdown to live play.
func _chase_world(level: GreyBoxLevel) -> SimWorld:
	var world: SimWorld = SimWorld.new(_seed)
	if not world.configure(level.mode, level.tuning, level.zones, level.teams, level.collision, level.surface):
		for failure: String in world.content_failures:
			print("content rejected: %s" % failure)
		return null
	world.add_system(MovementSystem.new())
	world.add_system(CarrySystem.new())
	world.add_system(CaptureSystem.new())
	world.add_system(ScoringSystem.new())
	world.add_system(MatchFlowSystem.new())
	world.populate_roster()
	world.step([MatchCommand.start()])
	var guard: int = 0
	while not world.is_live() and guard < 600:
		world.step([])
		guard += 1
	return world

## The robbed family's rooms and yard, one standing place each (the jail out).
## zone_point is a room's centre, in mid-air: the stance under it is the spot.
func _chase_starts(world: SimWorld, nav: NavGraph, robbed: StringName) -> Array[Vector3]:
	var starts: Array[Vector3] = []
	for zone_id: StringName in world.zone_ids_in_resolution_order():
		var zone: ZoneDef = world.zones[zone_id]
		if zone.is_owned_by(robbed) and zone.role != ZoneDef.Role.JAIL:
			starts.append(nav.surface.nodes[nav.stance_near(nav.zone_point(world, zone, Vector3.ZERO))])
	return starts

func _cash_points(world: SimWorld, nav: NavGraph, team: StringName) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for zone_id: StringName in world.zone_ids_in_resolution_order():
		var zone: ZoneDef = world.zones[zone_id]
		if zone.is_owned_by(team) and zone.role == ZoneDef.Role.CASH_ROOM:
			points.append(nav.zone_point(world, zone, Vector3.ZERO))
	return points

## The point of `homes` with the shortest route from `from`.
func _nearest_home(nav: NavGraph, from: Vector3, homes: Array[Vector3]) -> Vector3:
	var best: Vector3 = homes[0]
	var best_length: float = INF
	for home: Vector3 in homes:
		var length: float = _route_length(nav.route(from, home))
		if length < best_length:
			best_length = length
			best = home
	return best

func _route_length(route: PackedVector3Array) -> float:
	if route.is_empty():
		return INF
	var total: float = 0.0
	for i: int in range(1, route.size()):
		total += route[i - 1].distance_to(route[i])
	return total

## [the point `along` world units down `route` (its end if shorter), the flat
## direction of travel there].
func _along(route: PackedVector3Array, along: float) -> Array:
	var left: float = along
	for i: int in range(1, route.size()):
		var step: float = route[i - 1].distance_to(route[i])
		var dir: Vector3 = route[i] - route[i - 1]
		dir.y = 0.0
		if step >= left and step > 0.0:
			return [route[i - 1].lerp(route[i], left / step), dir.normalized()]
		left -= step
	var last: Vector3 = route[route.size() - 1]
	var tail: Vector3 = last - route[maxi(0, route.size() - 2)]
	tail.y = 0.0
	return [last, tail.normalized()]

## A stance `low`..`high` (flat) from `centre` on its floor and a short walk
## from it, best by `rank` (higher wins; ties to the lower index).
func _stance_by(nav: NavGraph, centre: Vector3, low: float, high: float, rank: Callable) -> Vector3:
	var hops: PackedInt32Array = nav.hops_from(nav.node_at(centre))
	var best: int = -1
	var best_rank: float = -INF
	for slack: float in [1.5, 2.5]:
		for i: int in nav.surface.size():
			var p: Vector3 = nav.surface.nodes[i]
			if absf(p.y - centre.y) > 120.0:
				continue
			var flat: float = _flat(p, centre)
			if flat < low or flat > high:
				continue
			var walk: float = nav.distance_by_hops(hops, i)
			if walk < 0.0 or walk > flat * slack:
				continue
			var r: float = float(rank.call(p))
			if r > best_rank:
				best_rank = r
				best = i
		if best >= 0:
			break
	return nav.surface.nodes[best] if best >= 0 else centre

func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

## A and B: the runner starts in each of the robbed family's rooms and heads
## for its own nearest cash room; the chaser stands behind it (A) or off to the
## side of its way ahead (B).
func _plan_runs(world: SimWorld, nav: NavGraph, robbed: StringName, robber: StringName,
		side: bool) -> Array:
	var plans: Array = []
	var homes: Array[Vector3] = _cash_points(world, nav, robber)
	for start: Vector3 in _chase_starts(world, nav, robbed):
		var goal: Vector3 = _nearest_home(nav, start, homes)
		# A route starts at its first waypoint, not at the body.
		var route: PackedVector3Array = PackedVector3Array([start]) + nav.route(start, goal)
		var dir: Vector3 = _along(route, 150.0)[1]
		var chaser: Vector3
		if side:
			var at: Array = _along(route, 400.0)
			var mid: Vector3 = at[0]
			var way: Vector3 = at[1]
			chaser = _stance_by(nav, mid, 250.0, 450.0, func(p: Vector3) -> float:
				if _flat(p, start) < 300.0:
					return -INF
				var off: Vector3 = p - mid
				off.y = 0.0
				return -absf(off.normalized().dot(way)))
		else:
			chaser = _stance_by(nav, start, 300.0, 500.0, func(p: Vector3) -> float:
				var off: Vector3 = p - start
				off.y = 0.0
				return -off.normalized().dot(dir))
		plans.append({"thief": start, "chaser": chaser, "goal": goal})
	return plans

## C: the bot carries the robber's cash home along the way a raider comes back
## (from the robber's cash room to each of its own), from four points on its own
## ground; the intruder stands 300 further along and walks back the other way.
func _plan_carries(world: SimWorld, nav: NavGraph, robbed: StringName, robber: StringName) -> Array:
	var plans: Array = []
	var raw: Vector3 = _cash_points(world, nav, robber)[0]
	var away: Vector3 = nav.surface.nodes[nav.stance_near(raw)]
	for home: Vector3 in _cash_points(world, nav, robbed):
		var route: PackedVector3Array = PackedVector3Array([away]) + nav.route(away, home)
		var total: float = _route_length(route)
		# Where the way home first reaches the bot's own ground.
		var entered: float = total
		var walked: float = 0.0
		for i: int in route.size():
			if i > 0:
				walked += route[i - 1].distance_to(route[i])
			var zone: ZoneDef = world.zone_at(route[i])
			if zone != null and zone.is_owned_by(robbed):
				entered = walked
				break
		var stop: float = total - 600.0
		for k: int in 4:
			var at: float = lerpf(entered + 50.0, maxf(entered + 50.0, stop), float(k) / 3.0)
			var start: Vector3 = _along(route, at)[0]
			var meet: Vector3 = _along(route, at + 300.0)[0]
			var carrier: Vector3 = nav.surface.nodes[nav.node_at(start)]
			var intruder: Vector3 = nav.surface.nodes[nav.node_at(meet)]
			plans.append({"thief": carrier, "chaser": intruder, "goal": carrier})
	return plans

## Plays one scene; {caught, seconds, kept, note}.
func _stage(level: GreyBoxLevel, nav: NavGraph, kind: String, plan: Dictionary,
		robbed: StringName, robber: StringName) -> Dictionary:
	var world: SimWorld = _chase_world(level)
	var guard: SimEntity = null # the robbed family's body in the scene
	var raider: SimEntity = null # the robbing family's
	var others: Array[SimEntity] = []
	for actor_id: int in world.actor_ids():
		var body: SimEntity = world.get_entity(actor_id)
		if body.team == robbed and guard == null:
			guard = body
		elif body.team == robber and raider == null:
			raider = body
		else:
			others.append(body)
	# C: the guard is the carrier at "thief"; the raider is the intruder at "chaser".
	var carrier: SimEntity = guard if kind == "C" else raider
	var chaser: SimEntity = raider if kind == "C" else guard
	_place(carrier, plan["thief"])
	_place(chaser, plan["chaser"])
	_park(world, nav, others, plan["thief"])
	var cash_team: StringName = robber if kind == "C" else robbed
	var cash: SimEntity = null
	for entity_id: int in world.sorted_entity_ids():
		var loot: SimEntity = world.entities[entity_id]
		if loot.is_carriable() and loot.team == cash_team and not loot.is_held():
			cash = loot
			break
	cash.position = carrier.position
	world.step([CarryCommand.pick_up(carrier.id, cash.id, world.tick)])
	if not carrier.is_carrying():
		return {"caught": false, "seconds": 0.0, "kept": false, "note": "SKIPPED: the pick-up was refused"}

	var crew: BotCrew = BotCrew.create(level.bot_profile, nav, world.rng.state)
	var bot: SimEntity = raider if kind == "R" else guard
	var scripted: SimEntity = guard if kind == "R" else raider
	crew.take_over(world, bot.id)
	var walk: Dictionary = {"route": PackedVector3Array(), "leg": 0, "repath": 0}
	var limit: int = SimWorld.seconds_to_ticks(CHASE_SECONDS)
	var began: int = world.tick
	var closest: float = INF
	var prey: SimEntity = bot if kind == "R" else scripted
	var hunter: SimEntity = scripted if kind == "R" else bot
	while world.tick - began < limit:
		var commands: Array[SimCommand] = crew.drain(world, world.tick)
		if kind == "R":
			commands.append_array(_hunt(world, nav, scripted, bot, walk))
		else:
			commands.append_array(_walk_to(world, nav, scripted, plan["goal"], walk,
				SimWorld.seconds_to_ticks(1.0)))
		world.step(commands)
		closest = minf(closest, hunter.position.distance_to(prey.position))
		var seconds: float = float(world.tick - began) / float(SimWorld.TICKS_PER_SECOND)
		if prey.is_captured:
			var holding: bool = kind == "C" and guard.is_carrying()
			var how: String = ""
			if kind == "C":
				how = " (still carrying)" if holding else " (cash gone)"
			return {"caught": true, "seconds": seconds, "kept": holding,
				"note": "CAUGHT after %.1f s%s" % [seconds, how]}
		if kind != "C":
			var ground: ZoneDef = world.zone_at(prey.position)
			if ground == null or not ground.is_owned_by(robbed):
				return {"caught": false, "seconds": seconds, "kept": false,
					"note": "escaped after %.1f s (closest %d)" % [seconds, int(closest)]}
		elif not guard.is_carrying():
			var banked: ZoneDef = world.zone_at(guard.position)
			var where: String = "banked it" if banked != null and banked.role == ZoneDef.Role.CASH_ROOM else "let go of the cash"
			return {"caught": false, "seconds": seconds, "kept": false,
				"note": "%s after %.1f s without a seizure (closest %d)" % [where, seconds, int(closest)]}
	var doing: BotTask = crew.director_for(bot.id).current_task()
	return {"caught": false, "seconds": CHASE_SECONDS, "kept": false,
		"note": "nothing in %d s (closest %d, bot doing %s)" % [int(CHASE_SECONDS), int(closest),
			BotTask.Kind.keys()[doing.kind]]}

func _place(body: SimEntity, at: Vector3) -> void:
	body.position = at
	body.velocity = Vector3.ZERO
	body.move_intent = Vector3.ZERO

## Everybody not in the scene, on the neutral lot as far from it as it goes.
func _park(world: SimWorld, nav: NavGraph, bodies: Array[SimEntity], scene: Vector3) -> void:
	var taken: Array[Vector3] = []
	var order: Array[int] = []
	for i: int in nav.surface.size():
		var zone: ZoneDef = world.zone_at(nav.surface.nodes[i])
		if zone != null and zone.owner_team == &"":
			order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		var da: float = _flat(nav.surface.nodes[a], scene)
		var db: float = _flat(nav.surface.nodes[b], scene)
		return da > db if da != db else a < b)
	for body: SimEntity in bodies:
		for i: int in order:
			var p: Vector3 = nav.surface.nodes[i]
			var clear: bool = true
			for t: Vector3 in taken:
				if _flat(t, p) < 200.0:
					clear = false
					break
			if clear:
				taken.append(p)
				_place(body, p)
				break

## Follows a nav route to `goal` the way a player holding a direction would:
## at the furthest waypoint in reach, re-routed every `repath` ticks.
func _walk_to(world: SimWorld, nav: NavGraph, body: SimEntity, goal: Vector3, state: Dictionary,
		repath: int) -> Array[SimCommand]:
	if body.is_captured:
		return []
	if world.tick >= int(state["repath"]) or (state["route"] as PackedVector3Array).is_empty():
		state["route"] = nav.route(body.position, goal)
		state["leg"] = 0
		state["repath"] = world.tick + repath
	var route: PackedVector3Array = state["route"]
	var leg: int = state["leg"]
	while leg < route.size() and _flat(body.position, route[leg]) <= CHASE_ARRIVE:
		leg += 1
	if leg >= route.size():
		state["leg"] = leg
		return [MoveCommand.stop(body.id, world.tick)] as Array[SimCommand]
	var target: int = nav.surface.furthest_reachable(body.position, route, leg,
		mini(route.size() - 1, leg + CHASE_LOOKAHEAD))
	if target < 0:
		target = leg
	state["leg"] = target
	var heading: Vector3 = route[target] - body.position
	heading.y = 0.0
	if heading.length_squared() <= 0.0:
		return []
	return [MoveCommand.move(body.id, heading.normalized(), world.tick)] as Array[SimCommand]

## A human chasing: straight at the target when it is close with nothing in
## between, otherwise along a route to where it is now, re-aimed often; seizes
## as soon as it is in range.
func _hunt(world: SimWorld, nav: NavGraph, body: SimEntity, prey: SimEntity, state: Dictionary) -> Array[SimCommand]:
	var commands: Array[SimCommand] = []
	if body.position.distance_to(prey.position) <= world.tuning.capture_range:
		commands.append(CaptureCommand.capture(body.id, prey.id, world.tick))
	var lift: Vector3 = Vector3(0.0, CaptureSystem.REACH_LIFT, 0.0)
	if _flat(body.position, prey.position) <= HUMAN_STRAIGHT and absf(body.position.y - prey.position.y) < 100.0 \
			and not world.collision.blocks_segment(body.position + lift, prey.position + lift):
		var heading: Vector3 = prey.position - body.position
		heading.y = 0.0
		if heading.length_squared() > 0.0:
			commands.append(MoveCommand.move(body.id, heading.normalized(), world.tick))
		return commands
	commands.append_array(_walk_to(world, nav, body, prey.position, state,
		SimWorld.seconds_to_ticks(HUMAN_REAIM_SECONDS)))
	return commands
