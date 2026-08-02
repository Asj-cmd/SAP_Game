extends SceneTree
## Plays a match on two worlds joined only by the wire format.
##
##   godot --headless --path godot --script res://tools/net_loopback.gd
##
## The claim ARCHITECTURE.md §3 makes about netcode, tested before there is any
## netcode: record the seed and the command stream and a second machine
## re-simulates the same match. Here the "server" runs bots and its commands are
## ENCODED, handed over as bytes, DECODED, and fed to a second world that has
## never seen a director. If the two agree tick for tick, then the only thing a
## real transport adds is latency and loss - the correctness argument is already
## made, and made without a socket.
##
## Compared per tick rather than at the end. Two matches that end alike may have
## diverged and converged, and the tick a disagreement STARTS on is the only one
## that says anything about the cause.

func _initialize() -> void:
	var level: GreyBoxLevel = GreyBoxLevel.new()
	if not level.is_loaded():
		print("no baked level - run tools/bake_blockout.gd")
		quit(1)
		return

	var host: SimWorld = _world(level)
	var guest: SimWorld = _world(level)
	if host == null or guest == null:
		quit(1)
		return

	# Only the host has bots. The guest is told what happened, exactly as a
	# client is - it must never run a director of its own, or the two would
	# agree for the wrong reason.
	var crew: BotCrew = BotCrew.create(
		level.bot_profile, NavGraph.of(host.surface), host.rng.state
	)
	crew.fill_lobby(host, [], host.actor_ids().size())

	var sent: int = 0
	var bytes: int = 0
	var diverged_at: int = -1
	_both(host, guest, [MatchCommand.start()] as Array[SimCommand])

	for tick: int in 30 * 90:
		var commands: Array[SimCommand] = crew.drain(host, host.tick)
		sent += commands.size()

		# The only thing that crosses. Everything the guest knows, it learned
		# from these bytes.
		var packet: PackedByteArray = CommandCodec.encode_batch(commands)
		bytes += packet.size()

		host.step(commands)
		guest.step(CommandCodec.decode_batch(packet))

		if host.state_hash() != guest.state_hash():
			diverged_at = tick
			break

	print("")
	print("--- %s ---" % ("IN LOCKSTEP" if diverged_at < 0 else "DIVERGED"))
	print("ticks        %d" % host.tick)
	print("commands     %d sent, %d bytes (%.1f bytes/tick)"
		% [sent, bytes, float(bytes) / maxf(1.0, float(host.tick))])
	print("host  score  %s" % _scores(host))
	print("guest score  %s" % _scores(guest))
	if diverged_at >= 0:
		print("first disagreement at tick %d" % diverged_at)
		_show_difference(host.state_digest(), guest.state_digest())
	quit(0 if diverged_at < 0 else 1)

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

func _both(host: SimWorld, guest: SimWorld, commands: Array[SimCommand]) -> void:
	host.step(commands)
	guest.step(CommandCodec.decode_batch(CommandCodec.encode_batch(commands)))

func _scores(world: SimWorld) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for team_id: StringName in world.sorted_team_ids():
		parts.append("%s %d/%d" % [
			team_id, world.score_for(team_id), world.round_wins_for(team_id),
		])
	return "  ".join(parts)

func _show_difference(left: String, right: String) -> void:
	var a: PackedStringArray = left.split(";")
	var b: PackedStringArray = right.split(";")
	var shown: int = 0
	for i: int in mini(a.size(), b.size()):
		if a[i] == b[i] or shown >= 4:
			continue
		print("  host : %s" % a[i])
		print("  guest: %s" % b[i])
		shown += 1
