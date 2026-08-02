extends SceneTree
## Plays a match on two worlds joined only by a transport.
##
##   godot --headless --path godot --script res://tools/net_loopback.gd
##   godot --headless --path godot --script res://tools/net_loopback.gd -- --backend=enet
##
## The reference result, and the bar every backend has to clear. A host running
## bots encodes its commands, hands them to a SessionTransport, and a guest that
## has never seen a director decodes and steps. If the two agree TICK FOR TICK
## then the transport is carrying everything the simulation depends on, and a
## real one that cannot reproduce this is wrong rather than merely slower.
##
## One harness, two backends, deliberately: loopback establishes what correct
## looks like with the wire out of the picture, and ENet then has to match it
## exactly. A separate socket test would only prove that sockets work.
##
## Compared per tick rather than at the end, because two matches that finish
## alike may have diverged and converged, and the tick a disagreement STARTS on
## is the only one that says anything about the cause.
##
## LOCKSTEP is the right shape for a reference and the wrong shape for play:
## the guest waits for each tick's packet, so a real network's latency would be
## felt directly. Prediction and rollback are what remove that, and they are
## next - this establishes the thing they have to preserve.

const TICKS: int = 30 * 90
## How long to wait for a session, and for each tick's packet, before giving up.
## Generous: a relayed session may genuinely take seconds, and a harness that
## times out faster than the transport connects tests nothing.
const SESSION_TIMEOUT_MS: int = 5000
const PACKET_TIMEOUT_MS: int = 2000

var _host_world: SimWorld = null
var _guest_world: SimWorld = null

func _initialize() -> void:
	var backend: String = "loopback"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--backend="):
			backend = arg.trim_prefix("--backend=")

	var level: GreyBoxLevel = GreyBoxLevel.new()
	if not level.is_loaded():
		print("no baked level - run tools/bake_blockout.gd")
		quit(1)
		return

	var server: SessionTransport = _transport(backend)
	var client: SessionTransport = _transport(backend)
	if server == null or client == null:
		print("unknown backend '%s' - try loopback or enet" % backend)
		quit(1)
		return

	var handle: SessionHandle = server.host_session()
	if not handle.is_valid():
		print("could not host: %s" % server.failure())
		quit(1)
		return
	client.join_session(handle)

	# Joining says nothing about having joined. Wait for the events.
	if not _await_session(server, client):
		print("session never became ready (server=%s client=%s)"
			% [server.failure(), client.failure()])
		quit(1)
		return

	_host_world = _world(level)
	_guest_world = _world(level)
	if _host_world == null or _guest_world == null:
		quit(1)
		return

	# Only the host has bots. The guest is TOLD what happened, exactly as a
	# client is - if it ran a director of its own the two would agree for the
	# wrong reason and prove nothing.
	var crew: BotCrew = BotCrew.create(
		level.bot_profile, NavGraph.of(_host_world.surface), _host_world.rng.state
	)
	crew.fill_lobby(_host_world, [], _host_world.actor_ids().size())

	var report: Dictionary = _play(server, client, crew)
	server.close()
	client.close()

	var diverged: int = report["diverged_at"]
	print("")
	print("--- %s over %s ---" % ["IN LOCKSTEP" if diverged < 0 else "DIVERGED", backend])
	print("ticks        %d" % _host_world.tick)
	print("commands     %d sent, %d bytes (%.1f bytes/tick)" % [
		report["sent"], report["bytes"],
		float(report["bytes"]) / maxf(1.0, float(_host_world.tick)),
	])
	print("host  score  %s" % _scores(_host_world))
	print("guest score  %s" % _scores(_guest_world))
	if diverged >= 0:
		print("first disagreement at tick %d" % diverged)
		_show_difference(_host_world.state_digest(), _guest_world.state_digest())
	quit(0 if diverged < 0 else 1)

func _transport(backend: String) -> SessionTransport:
	match backend:
		"loopback":
			return LoopbackTransport.new()
		"enet":
			return ENetTransport.new()
	return null

## Waits for both ends to report themselves usable.
##
## Polls rather than assuming, because that is the contract: join_session
## returned nothing and a relayed session is not ready when it is asked for.
func _await_session(server: SessionTransport, client: SessionTransport) -> bool:
	var deadline: int = Time.get_ticks_msec() + SESSION_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		for transport: SessionTransport in [server, client]:
			for event: NetEvent in transport.poll():
				if event.kind == NetEvent.Kind.SESSION_FAILED:
					return false
		if server.state() == SessionTransport.State.READY \
			and client.state() == SessionTransport.State.READY \
			and not server.peers().is_empty():
			return true
		OS.delay_msec(1)
	return false

func _play(server: SessionTransport, client: SessionTransport, crew: BotCrew) -> Dictionary:
	var sent: int = 0
	var bytes: int = 0
	var diverged_at: int = -1

	# The opening command goes over the wire like everything else.
	if not _exchange(server, client, [MatchCommand.start()] as Array[SimCommand]):
		return {"sent": 0, "bytes": 0, "diverged_at": 0}

	for tick: int in TICKS:
		var commands: Array[SimCommand] = crew.drain(_host_world, _host_world.tick)
		sent += commands.size()
		bytes += CommandCodec.encode_batch(commands).size()
		if not _exchange(server, client, commands):
			diverged_at = tick
			break
		if _host_world.state_hash() != _guest_world.state_hash():
			diverged_at = tick
			break
	return {"sent": sent, "bytes": bytes, "diverged_at": diverged_at}

## One tick across the wire: send, wait for arrival, step both.
##
## The guest steps only what actually arrived. Reconstructing a missing tick
## from what the host did would be the harness quietly repairing the thing it
## exists to detect.
func _exchange(
	server: SessionTransport,
	client: SessionTransport,
	commands: Array[SimCommand]
) -> bool:
	server.broadcast(CommandCodec.encode_batch(commands))
	var arrived: PackedByteArray = _await_packet(server, client)
	if arrived.is_empty():
		return false
	_host_world.step(commands)
	_guest_world.step(CommandCodec.decode_batch(arrived))
	return true

## An empty batch is still a batch - a tick where nobody did anything must
## arrive, or the guest cannot tell "nothing happened" from "nothing came".
func _await_packet(server: SessionTransport, client: SessionTransport) -> PackedByteArray:
	var deadline: int = Time.get_ticks_msec() + PACKET_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		server.poll()
		for event: NetEvent in client.poll():
			if event.kind == NetEvent.Kind.PAYLOAD:
				return event.payload
			if event.kind == NetEvent.Kind.PEER_LEFT:
				return PackedByteArray()
		OS.delay_msec(0)
	return PackedByteArray()

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
