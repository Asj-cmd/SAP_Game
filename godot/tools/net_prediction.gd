extends SceneTree
## A predicting guest against a host, with latency you can dial.
##
##   godot --headless --path godot --script res://tools/net_prediction.gd
##   godot --headless --path godot --script res://tools/net_prediction.gd -- --latency=6
##   godot --headless --path godot --script res://tools/net_prediction.gd -- --latency=6 --delay=0
##
## Two questions, and they are different:
##
##   1. Is the match still the same match? The guest's CONFIRMED world is
##      compared against the host's digest for that tick, every tick, at every
##      latency. This is the lockstep invariant and prediction is not allowed to
##      touch it - at zero latency the guest must land exactly where the
##      lockstep harness said, and at any latency the confirmed history must be
##      identical, just later.
##
##   2. Is prediction buying anything? Reported as how far the guest's guess
##      about its OWN position was from the truth, in world units. That is the
##      error a player would see corrected, and the number that says whether the
##      input delay is set sensibly.
##
## Latency is applied in TICKS, symmetrically, to both directions. Crude on
## purpose: this is not a jitter model, it is a way to make the prediction path
## actually run.
##
## Bots are HOST-SIDE ONLY here, as they are everywhere. The guest never builds
## a BotCrew - it cannot tell a bot's commands from a human's, which is the
## property that stops two machines disagreeing about what a bot decided.

const TICKS: int = 30 * 60

func _initialize() -> void:
	var latency: int = 0
	var delay_override: int = -1
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--latency="):
			latency = maxi(0, int(arg.trim_prefix("--latency=")))
		elif arg.begins_with("--delay="):
			delay_override = maxi(0, int(arg.trim_prefix("--delay=")))

	var level: GreyBoxLevel = GreyBoxLevel.new()
	if not level.is_loaded():
		print("no baked level - run tools/bake_blockout.gd")
		quit(1)
		return
	if delay_override >= 0:
		level.tuning.input_delay_ticks = delay_override

	var host: SimWorld = _world(level)
	var session: PredictedSession = PredictedSession.create(
		_world(level), _world(level), level.tuning.input_delay_ticks
	)
	if host == null or session.confirmed == null:
		quit(1)
		return

	# The guest drives the first actor; bots take everything else, host-side.
	var seat: int = host.actor_ids()[0]
	var crew: BotCrew = BotCrew.create(
		level.bot_profile, NavGraph.of(host.surface), host.rng.state
	)
	crew.fill_lobby(host, [seat] as Array[int], host.actor_ids().size())

	var report: Dictionary = _run(host, session, crew, seat, latency)

	print("")
	print("--- %s at %d ticks latency ---" % [
		"CONSISTENT" if report["diverged_at"] < 0 else "DIVERGED", latency,
	])
	print("input delay    %d ticks" % session.input_delay)
	print("host ticks     %d" % host.tick)
	print("confirmed to   %d (guest ran %d ahead)" % [session.confirmed.tick, report["lead"]])
	print("bots           %d, all host-side" % crew.count())
	print("misprediction  max %.2f units, mean %.3f over %d compared ticks" % [
		report["worst"], report["mean"], report["compared"],
	])
	if report["diverged_at"] >= 0:
		print("first disagreement at confirmed tick %d" % report["diverged_at"])
	quit(0 if report["diverged_at"] < 0 else 1)

func _run(
	host: SimWorld,
	session: PredictedSession,
	crew: BotCrew,
	seat: int,
	latency: int
) -> Dictionary:
	# Both directions of the wire, as tick-stamped queues.
	var to_host: Array[Dictionary] = []
	var to_guest: Array[Dictionary] = []
	## Arrived at the host but not yet due. See the loop below.
	var held: Array[SimCommand] = []
	# What the host looked like at each tick, and what the guest guessed.
	var truth: Dictionary[int, String] = {}
	var guessed: Dictionary[int, Vector3] = {}

	var diverged_at: int = -1
	var worst: float = 0.0
	var total: float = 0.0
	var compared: int = 0

	# Opened through the same path as everything else, and recorded the same way.
	var opening: Array[SimCommand] = [MatchCommand.start()] as Array[SimCommand]
	host.step(opening)
	truth[host.tick] = host.state_digest()
	session.confirm(opening)

	for tick: int in TICKS:
		# --- the guest's own input, predicted at once and posted to the host ---
		var steering: SimCommand = session.submit(
			MoveCommand.move(seat, _wander(tick), 0)
		)
		to_host.append({"at": tick + latency, "command": steering})
		session.predict()
		# Keyed by the tick the state REPRESENTS, not the tick it was made on.
		# Both sides of the comparison below are indexed that way, or the guess
		# is checked against the truth from a neighbouring tick and the error is
		# whatever the actor happened to be doing.
		guessed[session.predicted.tick] = session.view_position(seat)

		# --- the host applies what has arrived AND is due, plus its bots ---
		#
		# Due, not merely arrived. A command carries the tick its sender
		# predicted it on, and the host honouring that stamp is the entire
		# mechanism of input delay: hold the command those extra ticks and both
		# machines apply it on the same tick, so the sender's own actions stop
		# mispredicting altogether. Applying on arrival instead makes the delay
		# a pure cost with no benefit - which is what this harness did first,
		# and it showed up as misprediction at zero latency.
		var still_flying: Array[Dictionary] = []
		for parcel: Dictionary in to_host:
			if parcel["at"] <= tick:
				held.append(parcel["command"])
			else:
				still_flying.append(parcel)
		to_host = still_flying

		var batch: Array[SimCommand] = []
		var not_yet: Array[SimCommand] = []
		for command: SimCommand in held:
			# A command whose tick has already passed arrived too late to be
			# honoured and is applied now. That is the misprediction the delay
			# exists to avoid, and it is correct to take it rather than drop it.
			if command.issued_tick <= host.tick:
				batch.append(command)
			else:
				not_yet.append(command)
		held = not_yet
		batch.append_array(crew.drain(host, host.tick))

		host.step(batch)
		truth[host.tick] = host.state_digest()
		# Encoded and decoded even in-process: the guest must only ever see what
		# would survive the wire.
		to_guest.append({"at": tick + latency, "bytes": CommandCodec.encode_batch(batch)})

		# --- the guest confirms whatever has come back ---
		var still_returning: Array[Dictionary] = []
		for parcel: Dictionary in to_guest:
			if parcel["at"] > tick:
				still_returning.append(parcel)
				continue
			session.confirm(CommandCodec.decode_batch(parcel["bytes"]))
			var settled: int = session.confirmed.tick

			if truth.has(settled) and session.confirmed.state_digest() != truth[settled]:
				if diverged_at < 0:
					diverged_at = settled
			if guessed.has(settled):
				var actual: Vector3 = session.outcome_state(seat).position
				var error: float = guessed[settled].distance_to(actual)
				worst = maxf(worst, error)
				total += error
				compared += 1
		to_guest = still_returning

	return {
		"diverged_at": diverged_at,
		"worst": worst,
		"mean": total / maxf(1.0, float(compared)),
		"compared": compared,
		"lead": session.lead(),
	}

## A path that turns, so prediction is exercised rather than a straight line
## that would be right by accident.
func _wander(tick: int) -> Vector3:
	var turn: float = float(tick) * 0.03
	return Vector3(cos(turn), 0.0, sin(turn))

func _world(level: GreyBoxLevel) -> SimWorld:
	var world: SimWorld = SimWorld.new(20260802)
	if not world.configure(
		level.mode, level.tuning, level.zones, level.teams, level.collision, level.surface
	):
		for failure: String in world.content_failures:
			print("content rejected: %s" % failure)
		return null
	world.add_system(MovementSystem.new())
	world.add_system(CarrySystem.new())
	world.add_system(CaptureSystem.new())
	world.add_system(ScoringSystem.new())
	world.add_system(MatchFlowSystem.new())
	world.populate_roster()
	return world
