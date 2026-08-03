extends SceneTree
## Late join, packet loss, and repair by snapshot.
##
##   godot --headless --path godot --script res://tools/net_reconcile.gd
##   godot --headless --path godot --script res://tools/net_reconcile.gd -- --loss=8 --join=400
##
## The command stream alone assumes a guest that has been present since tick 0
## and has missed nothing. Neither is true: players join late, players
## reconnect, and packets are lost. Snapshots are what close both gaps, and this
## exercises all three triggers against a running match.
##
##   ON JOIN      a guest that has seen nothing is handed the world
##   KEYFRAME     an unrequested snapshot every tuning.snapshot_interval_ticks
##   ON MISMATCH  the digest detector, reused as the repair trigger
##
## The last one is the interesting one. The desync detector was built to prove
## determinism; here it earns its keep a second time by deciding when a client
## needs repairing, which costs nothing extra because the digest was already
## being computed.
##
## Loss is deterministic - a seeded stream, not a wall clock - so a failure here
## can be re-run and will happen again.

const TICKS: int = 30 * 90

func _initialize() -> void:
	var loss_percent: int = 5
	var corrupt_percent: int = 2
	var join_tick: int = 300
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--loss="):
			loss_percent = clampi(int(arg.trim_prefix("--loss=")), 0, 90)
		elif arg.begins_with("--corrupt="):
			corrupt_percent = clampi(int(arg.trim_prefix("--corrupt=")), 0, 90)
		elif arg.begins_with("--join="):
			join_tick = maxi(0, int(arg.trim_prefix("--join=")))

	var level: GreyBoxLevel = GreyBoxLevel.new()
	if not level.is_loaded():
		print("no baked level - run tools/bake_blockout.gd")
		quit(1)
		return

	var host: SimWorld = _world(level)
	var guest: PredictedSession = PredictedSession.create(
		_world(level), _world(level), level.tuning.input_delay_ticks, _world(level)
	)
	if host == null or guest.confirmed == null:
		quit(1)
		return

	var crew: BotCrew = BotCrew.create(
		level.bot_profile, NavGraph.of(host.surface), host.rng.state
	)
	crew.fill_lobby(host, [] as Array[int], host.actor_ids().size())

	var report: Dictionary = _run(host, guest, crew, level, loss_percent, corrupt_percent, join_tick)

	print("")
	print("--- %s ---" % ("REPAIRED" if report["consistent"] else "STILL BROKEN"))
	print("joined at tick   %d of %d" % [join_tick, host.tick])
	print("packets lost     %d of %d (%d%% requested)" % [
		report["lost"], report["offered"], loss_percent,
	])
	print("packets mangled  %d (%d%% requested)" % [report["corrupted"], corrupt_percent])
	print("desyncs caught   %d" % report["desyncs"])
	print("snapshots sent   %d (%d on join, %d keyframes, %d repairs)" % [
		report["snapshots"], 1, report["keyframes"], report["desyncs"],
	])
	print("snapshot size    %d bytes, vs %.1f bytes/tick of commands" % [
		report["snapshot_bytes"], report["command_bytes_per_tick"],
	])
	print("final digests    %s" % ("identical" if report["consistent"] else "DIFFERENT"))
	quit(0 if report["consistent"] else 1)

func _run(
	host: SimWorld,
	guest: PredictedSession,
	crew: BotCrew,
	level: GreyBoxLevel,
	loss_percent: int,
	corrupt_percent: int,
	join_tick: int
) -> Dictionary:
	# Seeded, so a bad run reproduces exactly.
	var wire: SimRandom = SimRandom.new(SimWorld.hash_string("loss|%d" % loss_percent))
	var keyframe_every: int = maxi(1, level.tuning.snapshot_interval_ticks)

	var lost: int = 0
	var corrupted: int = 0
	var offered: int = 0
	var desyncs: int = 0
	var keyframes: int = 0
	var snapshots: int = 0
	var snapshot_bytes: int = 0
	var command_bytes: int = 0
	var joined: bool = false

	host.step([MatchCommand.start()] as Array[SimCommand])

	for tick: int in TICKS:
		var batch: Array[SimCommand] = crew.drain(host, host.tick)
		var encoded: PackedByteArray = CommandCodec.encode_batch(batch)
		command_bytes += encoded.size()
		host.step(batch)

		if tick < join_tick:
			continue

		# --- trigger 1: on join ---
		if not joined:
			joined = true
			var opening: PackedByteArray = WorldSnapshot.capture(host)
			snapshot_bytes = opening.size()
			snapshots += 1
			guest.reconcile(opening)
			continue

		# --- the ordinary stream, lossily ---
		offered += 1
		if wire.next_int(100) < loss_percent:
			lost += 1
		else:
			var delivered: Array[SimCommand] = CommandCodec.decode_batch(encoded)
			# A batch that ARRIVED but is not what was sent.
			#
			# Loss alone leaves a guest merely behind, never wrong, so it can
			# never trigger the digest check - the guest has not reached the tick
			# to disagree about. Divergence needs a guest that stepped the same
			# tick with different input, which is what a bug, a version mismatch
			# or a nondeterminism would produce. Without this the mismatch
			# trigger is code that has never once run.
			var mangle: bool = corrupt_percent > 0 and not delivered.is_empty()
			if mangle and wire.next_int(100) < corrupt_percent:
				delivered.remove_at(0)
				corrupted += 1
			guest.confirm(delivered)

		# --- trigger 2: on mismatch, using the detector already there ---
		#
		# Comparable only when both are standing on the same tick; a guest that
		# is merely BEHIND has not disagreed about anything yet.
		if guest.confirmed.tick == host.tick and guest.confirmed.state_hash() != host.state_hash():
			desyncs += 1
			snapshots += 1
			guest.reconcile(WorldSnapshot.capture(host))

		# --- trigger 3: the periodic keyframe ---
		#
		# Also what recovers a guest that has fallen BEHIND rather than diverged,
		# which is the shape dropped packets actually take: it cannot detect that
		# by digest, because it has not reached the tick to compare.
		if tick % keyframe_every == 0:
			keyframes += 1
			snapshots += 1
			guest.reconcile(WorldSnapshot.capture(host))

	# Settle: one last keyframe, as a reconnecting client would receive.
	guest.reconcile(WorldSnapshot.capture(host))
	return {
		"corrupted": corrupted,
		"consistent": guest.confirmed.state_digest() == host.state_digest(),
		"lost": lost,
		"offered": offered,
		"desyncs": desyncs,
		"keyframes": keyframes,
		"snapshots": snapshots,
		"snapshot_bytes": snapshot_bytes,
		"command_bytes_per_tick": float(command_bytes) / maxf(1.0, float(TICKS)),
	}

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
