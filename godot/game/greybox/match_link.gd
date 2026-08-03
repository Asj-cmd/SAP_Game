class_name MatchLink
extends RefCounted
## Runs the match, whichever end of it you are on.
##
## Three roles behind one interface, so presentation asks the same questions
## regardless: where do I draw this body, what is actually true about it, whose
## body am I driving.
##
##   LOCAL  one machine, no transport. The slice as it always was.
##   HOST   authoritative. Runs the bots, applies everyone's input, broadcasts.
##   GUEST  predicts its own movement, is told everything else.
##
## The split presentation depends on is exposed as two methods, deliberately
## named for what they are FOR rather than for which world they come from:
## predicted_world() is where a body is drawn, outcome_world() is what is true
## about it. On a host they are the same object; on a guest they are not, and
## the day someone collapses them is the day a jailing appears on screen and is
## taken back.

enum Role { LOCAL, HOST, GUEST }

var role: Role = Role.LOCAL
var lobby: Lobby = null
var crew: BotCrew = null
var transport: SessionTransport = null
var session: PredictedSession = null
var failure: String = ""

## Which body this machine drives. Assigned by the host; a guest is told.
var actor_id: int = SimEntity.NO_ENTITY

var _level: GreyBoxLevel = null
var _authoritative: SimWorld = null
## Guest input that has arrived at the host but is not yet due (§ input delay).
var _held: Array[SimCommand] = []
## peer -> lobby seat, so a guest's commands can be checked against its own body.
var _seat_of_peer: Dictionary[int, LobbySeat] = {}
var _last_snapshot_tick: int = 0
## The address put into the session code. See host().
var _advertised: String = "127.0.0.1"
var _seeded: bool = false

# ---- construction ----

static func local(level: GreyBoxLevel, world: SimWorld, bots: bool) -> MatchLink:
	var link: MatchLink = MatchLink.new()
	link.role = Role.LOCAL
	link._level = level
	link._authoritative = world
	link._start_lobby(world, bots)
	return link

## `advertise` is the address the code should carry - the one OTHER machines can
## reach this one at, which is not the one it binds to.
##
## Over a mesh VPN this machine answers on 100.x.y.z while still binding every
## interface, and a code containing 127.0.0.1 is a code that only works on the
## desk it was generated on. Steam removes the question entirely by handing out
## a lobby id instead of an address; until then somebody has to say which
## address is the reachable one, and only the person running the host knows.
static func host(
	level: GreyBoxLevel,
	world: SimWorld,
	bots: bool,
	backend: String,
	advertise: String = ""
) -> MatchLink:
	var link: MatchLink = MatchLink.new()
	link.role = Role.HOST
	if advertise != "":
		link._advertised = advertise
	link._level = level
	link._authoritative = world
	link._start_lobby(world, bots)
	link.transport = _transport(backend)
	var handle: SessionHandle = link.transport.host_session()
	if not handle.is_valid():
		link.failure = "could not open a session: %s" % link.transport.failure()
	return link

static func guest(level: GreyBoxLevel, worlds: Array[SimWorld], backend: String, code: String) -> MatchLink:
	var link: MatchLink = MatchLink.new()
	link.role = Role.GUEST
	link._level = level
	link._authoritative = worlds[0]
	link.session = PredictedSession.create(
		worlds[0], worlds[1], level.tuning.input_delay_ticks, worlds[2]
	)
	link.transport = _transport(backend)

	# A pasted code, a handle from an invite, or nothing at all - which means
	# the session on this machine, which is what makes a two-window test on one
	# desktop a single flag rather than a copy-paste dance.
	var handle: SessionHandle = SessionHandle.new()
	if code == "":
		handle = SessionHandle.new(StringName(backend), "127.0.0.1:24545")
	elif code.contains(":"):
		handle = SessionHandle.parse(code)
	else:
		handle = LobbyCode.decode(code)
	if not handle.is_valid():
		link.failure = "that is not a session code"
		return link
	link.transport.join_session(handle)
	return link

static func _transport(backend: String) -> SessionTransport:
	return LoopbackTransport.new() if backend == "loopback" else ENetTransport.new()

func _start_lobby(world: SimWorld, bots: bool) -> void:
	lobby = Lobby.create(
		SimWorld.seconds_to_ticks(_level.tuning.reconnect_grace_seconds), bots
	)
	lobby.seat_roster(world)
	crew = BotCrew.create(_level.bot_profile, NavGraph.of(world.surface), world.rng.state)

## Claims a seat for the player sitting at this machine.
##
## The host has to sit down BEFORE anyone else arrives. It was not doing so, and
## the lobby - correctly, knowing only what it had been told - handed the host's
## own body to the first guest, so both machines drove one actor and each drew
## the other's corrections as jitter on itself.
func seat_local(display_name: String) -> int:
	if role == Role.GUEST or lobby == null:
		return SimEntity.NO_ENTITY
	var seated: LobbyEvent = lobby.admit(
		"local", SessionTransport.HOST_PEER, display_name, 0
	)
	if seated.seat == null:
		return SimEntity.NO_ENTITY
	_seat_of_peer[SessionTransport.HOST_PEER] = seated.seat
	actor_id = seated.seat.actor_id
	return actor_id

# ---- what presentation asks ----

## Where a body is DRAWN. Predicted on a guest, so your own movement is
## immediate; authoritative everywhere else, where there is nothing to predict.
func predicted_world() -> SimWorld:
	return session.predicted if role == Role.GUEST else _authoritative

## What is TRUE about a body: carrying, captured, sheltered, and the score.
## Never predicted, on any role.
func outcome_world() -> SimWorld:
	return session.confirmed if role == Role.GUEST else _authoritative

## Actions asked for and not yet answered, for presentation to start an
## animation on. Empty on a host, which has nothing to wait for.
func awaiting() -> Array[SimCommand]:
	return session.pending_actions() if role == Role.GUEST else [] as Array[SimCommand]

func is_ready() -> bool:
	if failure != "":
		return false
	if role == Role.GUEST:
		return actor_id != SimEntity.NO_ENTITY
	return true

func session_code() -> String:
	if role != Role.HOST or transport == null:
		return ""
	return LobbyCode.encode(SessionHandle.new(
		transport.backend_name(), _host_token()
	))

func _host_token() -> String:
	return "%s:24545" % _advertised

# ---- the tick ----

## Advances the match one simulation tick with this machine's own input.
func advance(local_commands: Array[SimCommand]) -> void:
	match role:
		Role.LOCAL:
			var batch: Array[SimCommand] = local_commands.duplicate()
			batch.append_array(crew.drain(_authoritative, _authoritative.tick))
			_authoritative.step(batch)
		Role.HOST:
			_advance_host(local_commands)
		Role.GUEST:
			_advance_guest(local_commands)

func _advance_host(local_commands: Array[SimCommand]) -> void:
	var batch: Array[SimCommand] = local_commands.duplicate()

	# Guest input waits for the tick it was stamped with, so both machines apply
	# it on the same one. Anything that arrived late is applied now rather than
	# dropped - a correction beats a lost input.
	var not_yet: Array[SimCommand] = []
	for command: SimCommand in _held:
		if command.issued_tick <= _authoritative.tick:
			batch.append(command)
		else:
			not_yet.append(command)
	_held = not_yet

	batch.append_array(crew.drain(_authoritative, _authoritative.tick))
	_authoritative.step(batch)

	for event: LobbyEvent in lobby.advance(_authoritative.tick):
		if event.kind == LobbyEvent.Kind.TAKEOVER_DUE:
			crew.take_over(_authoritative, event.seat.actor_id)

	transport.broadcast(MatchChannel.frame(
		MatchChannel.TAG_COMMANDS, CommandCodec.encode_batch(batch)
	))

	# A keyframe, for anyone who has quietly fallen behind.
	var interval: int = maxi(1, _level.tuning.snapshot_interval_ticks)
	if _authoritative.tick - _last_snapshot_tick >= interval:
		_last_snapshot_tick = _authoritative.tick
		transport.broadcast(MatchChannel.frame(
			MatchChannel.TAG_SNAPSHOT, WorldSnapshot.capture(_authoritative)
		))

func _advance_guest(local_commands: Array[SimCommand]) -> void:
	for command: SimCommand in local_commands:
		var stamped: SimCommand = session.submit(command)
		transport.send(SessionTransport.HOST_PEER, MatchChannel.frame(
			MatchChannel.TAG_INPUT, CommandCodec.encode_batch([stamped] as Array[SimCommand])
		))
	session.predict()

# ---- the wire ----

func poll_network() -> void:
	if transport == null:
		return
	for event: NetEvent in transport.poll():
		match event.kind:
			NetEvent.Kind.PEER_JOINED:
				_admit(event.peer)
			NetEvent.Kind.PEER_LEFT:
				_depart(event.peer)
			NetEvent.Kind.PAYLOAD:
				_receive(event.peer, event.payload)
			NetEvent.Kind.SESSION_FAILED:
				failure = event.reason

func _admit(peer: int) -> void:
	if role != Role.HOST:
		return
	# One identity per peer for now. Reconnect matching wants something stable
	# that survives the connection, which is a Steam id or a client-supplied
	# token; until then a peer is its own identity and a rejoin reads as a new
	# player. The lobby already handles the stable case (tests/lobby_test.gd).
	var seated: LobbyEvent = lobby.admit("peer:%d" % peer, peer, "Player %d" % peer, _authoritative.tick)
	if seated.seat == null:
		# Genuinely full. Told rather than left guessing - a client that hears
		# nothing cannot tell a full lobby from a broken connection.
		transport.send(peer, MatchChannel.frame_seat(SimEntity.NO_ENTITY))
		return
	_seat_of_peer[peer] = seated.seat
	# Whether they reclaimed a held seat or displaced a filler bot, a human
	# sitting down means the bot lets go.
	if crew.drives(seated.seat.actor_id):
		crew.release(_authoritative, seated.seat.actor_id)

	# The world first, then who they are in it. Both are needed before a guest
	# can draw anything, and the seat is meaningless without the world.
	transport.send(peer, MatchChannel.frame(
		MatchChannel.TAG_SNAPSHOT, WorldSnapshot.capture(_authoritative)
	))
	transport.send(peer, MatchChannel.frame_seat(seated.seat.actor_id))

	# Bots re-fill around whoever is now seated: still opt-in, still symmetric,
	# still declining rather than tilting the sides.
	if lobby.bots_enabled:
		lobby.note_fill(
			crew.fill_lobby(_authoritative, lobby.human_actor_ids(), _authoritative.actor_ids().size()),
			crew.declined_reason
		)

func _depart(peer: int) -> void:
	if role != Role.HOST:
		if peer == SessionTransport.HOST_PEER:
			failure = "the host left"
		return
	for event: LobbyEvent in lobby.note_absence(peer, _authoritative.tick):
		if event.kind == LobbyEvent.Kind.ENDED:
			failure = event.reason
	_seat_of_peer.erase(peer)

func _receive(peer: int, payload: PackedByteArray) -> void:
	var body: PackedByteArray = MatchChannel.body_of(payload)
	match MatchChannel.tag_of(payload):
		MatchChannel.TAG_COMMANDS:
			if role == Role.GUEST:
				session.confirm(CommandCodec.decode_batch(body))
		MatchChannel.TAG_SNAPSHOT:
			if role == Role.GUEST:
				session.reconcile(body)
				_seeded = true
		MatchChannel.TAG_SEAT:
			if role == Role.GUEST:
				actor_id = MatchChannel.seat_of(body)
		MatchChannel.TAG_INPUT:
			if role == Role.HOST:
				_accept_input(peer, body)

## Takes a guest's input, having checked it is theirs to give.
##
## A client may only move its OWN body. Nothing downstream would catch this -
## the simulation validates whether a command is legal, not whether the person
## sending it is entitled to - so it is checked at the only place that knows
## which seat a connection belongs to.
func _accept_input(peer: int, body: PackedByteArray) -> void:
	var seat: LobbySeat = _seat_of_peer.get(peer, null)
	if seat == null:
		return
	for command: SimCommand in CommandCodec.decode_batch(body):
		if command.actor_id != seat.actor_id:
			continue # not their body; dropped without comment
		_held.append(command)

func close() -> void:
	if transport != null:
		transport.close()
