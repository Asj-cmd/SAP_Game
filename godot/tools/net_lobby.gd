extends SceneTree
## A player joins mid-match, drops out, is covered by a bot, and comes back.
##
##   godot --headless --path godot --script res://tools/net_lobby.gd
##   godot --headless --path godot --script res://tools/net_lobby.gd -- --backend=enet
##
## The integration proof. Every piece built so far has been shown to work on its
## own; this is the one that shows they connect, and it walks the sequence a
## real player actually produces:
##
##   invite -> join mid-match -> snapshot -> play
##   drop -> grace window (nothing happens) -> bot takes the seat
##   reconnect -> reclaim the SAME seat -> snapshot -> play on
##
## What it is really checking is that none of that needed a new mechanism. The
## takeover is BotCrew.take_over, unchanged since it was written with no caller.
## The rejoin is the snapshot path, unchanged. The seat, and therefore the actor
## in the world, is the same one throughout - so nothing downstream ever learns
## that the person driving it changed.

const TICKS: int = 30 * 40
const DROP_AT: int = 300
const RETURN_AT: int = 700

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

	var host: SimWorld = _world(level)
	var guest: PredictedSession = PredictedSession.create(
		_world(level), _world(level), level.tuning.input_delay_ticks, _world(level)
	)
	if host == null or guest.confirmed == null:
		quit(1)
		return

	# Authority is a ROLE. The host holds it here; nothing below asks who it is
	# by name, which is what keeps migration a later decision rather than a
	# rewrite.
	var lobby: Lobby = Lobby.create(
		SimWorld.seconds_to_ticks(level.tuning.reconnect_grace_seconds), true
	)
	lobby.seat_roster(host)
	lobby.authority = SessionTransport.HOST_PEER

	var crew: BotCrew = BotCrew.create(
		level.bot_profile, NavGraph.of(host.surface), host.rng.state
	)

	var report: Dictionary = _run(host, guest, lobby, crew, backend)
	var seat: LobbySeat = report["seat"]

	print("")
	print("--- %s over %s ---" % ["SEAT KEPT" if report["ok"] else "SEAT LOST", backend])
	print("session       %s" % report["code"])
	print("joined        tick %d, by snapshot (%d bytes)" % [report["joined_at"], report["snapshot"]])
	print("dropped       tick %d" % DROP_AT)
	print("grace         %d ticks, expired at %d" % [lobby.grace_ticks, report["takeover_at"]])
	print("covered by    a bot on %s[%d], actor %d" % [seat.team, seat.slot, seat.actor_id])
	print("reclaimed     tick %d, same actor %s" % [
		report["reclaim_at"], "yes" if report["same_actor"] else "NO",
	])
	print("bots now      %d" % crew.count())
	print("final         %s" % ("host and guest agree" if report["consistent"] else "DIVERGED"))
	quit(0 if report["ok"] else 1)

func _run(
	host: SimWorld,
	guest: PredictedSession,
	lobby: Lobby,
	crew: BotCrew,
	backend: String
) -> Dictionary:
	var server: SessionTransport = _transport(backend)
	var client: SessionTransport = _transport(backend)
	var handle: SessionHandle = server.host_session()
	# The code is the fallback; the handle itself is what an invite carries.
	var code: String = LobbyCode.encode(handle)
	client.join_session(handle)
	_settle(server, client)

	# The player's identity, stable across connections. Steam supplies one; here
	# it stands in for a SteamID. Matching on this rather than on a peer id is
	# what makes a reclaim possible at all.
	const WHO: String = "player:ana"

	var joined_at: int = -1
	var takeover_at: int = -1
	var reclaim_at: int = -1
	var snapshot_size: int = 0
	var seat: LobbySeat = null
	var same_actor: bool = false
	var connected: bool = false

	host.step([MatchCommand.start()] as Array[SimCommand])

	for tick: int in TICKS:
		# --- the lobby's own clock: grace windows, and nothing else ---
		for event: LobbyEvent in lobby.advance(host.tick):
			if event.kind != LobbyEvent.Kind.TAKEOVER_DUE:
				continue
			takeover_at = host.tick
			# The capability written with no caller, finally called.
			crew.take_over(host, event.seat.actor_id)

		# --- joining, mid-match, through the invite ---
		if tick == 60:
			var seated: LobbyEvent = lobby.admit(WHO, client.local_peer(), "Ana", host.tick)
			seat = seated.seat
			connected = true
			joined_at = host.tick
			# Opt-in bots fill whatever the humans did not take, symmetrically.
			lobby.note_fill(
				crew.fill_lobby(host, lobby.human_actor_ids(), host.actor_ids().size()),
				crew.declined_reason
			)
			var opening: PackedByteArray = WorldSnapshot.capture(host)
			snapshot_size = opening.size()
			guest.reconcile(opening)

		# --- the connection drops ---
		if tick == DROP_AT:
			connected = false
			for event: LobbyEvent in lobby.note_absence(client.local_peer(), host.tick):
				if event.kind == LobbyEvent.Kind.ENDED:
					break

		# --- and comes back, on a NEW connection ---
		if tick == RETURN_AT:
			var back: LobbyEvent = lobby.admit(WHO, client.local_peer() + 50, "Ana", host.tick)
			reclaim_at = host.tick
			same_actor = back.seat == seat
			if back.kind == LobbyEvent.Kind.RECLAIMED:
				crew.release(host, seat.actor_id)
			connected = true
			# Rejoining is the same snapshot path as joining. No new mechanism.
			guest.reconcile(WorldSnapshot.capture(host))

		var batch: Array[SimCommand] = crew.drain(host, host.tick)
		host.step(batch)

		if connected:
			server.broadcast(CommandCodec.encode_batch(batch))
			server.poll()
			for event: NetEvent in client.poll():
				if event.kind == NetEvent.Kind.PAYLOAD:
					guest.confirm(CommandCodec.decode_batch(event.payload))
		else:
			# Nothing is delivered while they are away. The guest simply stops,
			# and the snapshot on return is what catches it up.
			server.poll()
			client.poll()

	guest.reconcile(WorldSnapshot.capture(host))
	var consistent: bool = guest.confirmed.state_digest() == host.state_digest()
	server.close()
	client.close()

	return {
		"ok": same_actor and consistent and takeover_at > 0 and seat != null and seat.is_played(),
		"seat": seat,
		"code": code,
		"joined_at": joined_at,
		"takeover_at": takeover_at,
		"reclaim_at": reclaim_at,
		"snapshot": snapshot_size,
		"same_actor": same_actor,
		"consistent": consistent,
	}

func _transport(backend: String) -> SessionTransport:
	return LoopbackTransport.new() if backend == "loopback" else ENetTransport.new()

func _settle(server: SessionTransport, client: SessionTransport) -> void:
	var deadline: int = Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		server.poll()
		client.poll()
		if server.state() == SessionTransport.State.READY \
			and client.state() == SessionTransport.State.READY \
			and not server.peers().is_empty():
			return
		OS.delay_msec(1)

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
