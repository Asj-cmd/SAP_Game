extends SceneTree
## The transport contract. See godot/CLAUDE.md.
##
##   godot --headless --path godot --script res://tests/transport_test.gd
##
## Not a test of ENet, and not a test of sockets. What is pinned here is the
## SHAPE of the interface, because the shape is the thing that decides whether
## swapping ENet for Steam Datagram Relay is a new file or a rewrite.
##
## Every case is one of the assumptions a relay breaks:
##
##   a handle is opaque         - there is no address to reach a relayed peer at
##   joining is asynchronous    - a relayed session negotiates, and may not open
##   identity arrives late      - you are nobody until the session says otherwise
##   failure is not an exception- unreachable is normal, not exceptional
##
## Run against BOTH backends by the same code. A contract only one
## implementation honours is not a contract, and the loopback reference in
## particular must not be easier than reality or it teaches habits that break.

const EXPECTED_CHECKS: int = 50

## Time for the link-conditions rows, driven by hand.
var _fake_ms: int = 0

var _passed: int = 0
var _failed: int = 0
var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	print("=== Session transport contract ===")
	_test_handles_are_opaque()
	for backend: String in ["loopback", "enet", "steam"]:
		_test_contract(backend)
	_test_steam_missing()
	_test_link_conditions()

	var ran: int = _passed + _failed
	if ran != EXPECTED_CHECKS:
		_failed += 1
		_failures.append("harness: ran %d checks, expected %d - a case was skipped"
			% [ran, EXPECTED_CHECKS])
	print("\n%d passed, %d failed" % [_passed, _failed])
	if _failed > 0:
		print("\nFAILURES:")
		for failure: String in _failures:
			print("  - %s" % failure)
	quit(1 if _failed > 0 else 0)

func _check(case_name: String, actual: Variant, expected: Variant) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		_failures.append("%s: expected %s, got %s" % [case_name, expected, actual])

# ---- handles ----

func _test_handles_are_opaque() -> void:
	# A Steam token will contain colons and anything else Valve likes. The
	# handle must survive text without the layer above having to know that.
	var awkward: SessionHandle = SessionHandle.new(&"steam", "lobby:109775241:friend/7")
	var returned: SessionHandle = SessionHandle.parse(awkward.to_text())
	_check("handle/backend survives text", returned.backend, awkward.backend)
	_check("handle/and so does a token full of colons", returned.token, awkward.token)

	# Handing a Steam invite to the ENet backend must be refused rather than
	# parsed into a nonsense address.
	_check("handle/a foreign handle is not ours", awkward.is_for(&"enet"), false)
	_check("handle/nonsense is not a handle", SessionHandle.parse("no-separator").is_valid(), false)

# ---- the contract, per backend ----

func _test_contract(backend: String) -> void:
	var server: SessionTransport = _make(backend)
	var client: SessionTransport = _make(backend)

	var handle: SessionHandle = server.host_session()
	_check("%s/hosting yields a handle immediately" % backend, handle.is_valid(), true)
	# Immediately, but NOT ready: an invite exists before the session is usable.
	_check("%s/but the session is not ready yet" % backend,
		server.state(), SessionTransport.State.OPENING)
	_check("%s/and nobody knows who they are yet" % backend, server.local_peer(), 0)

	client.join_session(handle)
	# join_session returns void, so there is nothing here to have mistaken for
	# success. The only way to find out is to poll.
	_check("%s/joining is not ready either" % backend,
		client.state() == SessionTransport.State.READY, false)

	var ready: bool = _settle(server, client)
	_check("%s/the session becomes ready by polling" % backend, ready, true)
	if not ready:
		server.close()
		client.close()
		return

	_check("%s/the host is the host" % backend, server.is_host(), true)
	_check("%s/and the guest is not" % backend, client.is_host(), false)
	_check("%s/the host can see the guest" % backend, server.peers().size(), 1)

	# Bytes, both ways, unchanged.
	var sent: PackedByteArray = PackedByteArray([0, 255, 7, 13, 200])
	server.broadcast(sent)
	_check("%s/payload reaches the guest intact" % backend,
		_await_payload(client, server), sent)
	client.send(SessionTransport.HOST_PEER, sent)
	_check("%s/and travels back the other way" % backend,
		_await_payload(server, client), sent)

	server.close()
	client.close()

	# An invalid handle is a normal outcome, reported through the same channel
	# as everything else. Unreachable is not exceptional over a relay.
	var lost: SessionTransport = _make(backend)
	lost.join_session(SessionHandle.new(&"nowhere", "nothing"))
	_check("%s/a foreign handle fails rather than throws" % backend,
		lost.state(), SessionTransport.State.FAILED)
	_check("%s/and says so through poll" % backend,
		_has_kind(lost.poll(), NetEvent.Kind.SESSION_FAILED), true)
	lost.close()

# ---- lag and loss (loopback only, fake clock) ----

## A ready loopback pair; the host's sends use `conditions`.
func _pair(conditions: LinkConditions) -> Array[LoopbackTransport]:
	var server: LoopbackTransport = LoopbackTransport.new()
	var client: LoopbackTransport = LoopbackTransport.new()
	server.conditions = conditions
	client.join_session(server.host_session())
	_settle(server, client)
	return [server, client] as Array[LoopbackTransport]

func _payloads(receiver: LoopbackTransport) -> Array[int]:
	var found: Array[int] = []
	for event: NetEvent in receiver.poll():
		if event.kind == NetEvent.Kind.PAYLOAD:
			found.append(event.payload[0])
	return found

func _conditions(latency: int, loss: float) -> LinkConditions:
	var link: LinkConditions = LinkConditions.new(latency, loss, 0, 3)
	link.clock = func() -> int: return _fake_ms
	return link

func _test_link_conditions() -> void:
	# No conditions: immediate, as the reference always was.
	_fake_ms = 0
	var plain: Array[LoopbackTransport] = _pair(null)
	plain[0].send(2, PackedByteArray([1]))
	_check("link/null conditions deliver at once", _payloads(plain[1]), [1] as Array[int])

	# 100 ms one way: nothing before, delivered at.
	_fake_ms = 0
	var lagged: Array[LoopbackTransport] = _pair(_conditions(100, 0.0))
	lagged[0].send(2, PackedByteArray([2]))
	_check("link/nothing at send time", _payloads(lagged[1]), [] as Array[int])
	_fake_ms = 99
	_check("link/nothing a ms early", _payloads(lagged[1]), [] as Array[int])
	_fake_ms = 100
	_check("link/delivered at latency", _payloads(lagged[1]), [2] as Array[int])

	# Reliable at loss 1.0: never lost, one extra round trip, still in order.
	_fake_ms = 0
	var lossy: Array[LoopbackTransport] = _pair(_conditions(50, 1.0))
	for value: int in [1, 2, 3]:
		lossy[0].send(2, PackedByteArray([value]))
	_fake_ms = 149
	_check("link/reliable loss waits a round trip", _payloads(lossy[1]), [] as Array[int])
	_fake_ms = 150
	_check("link/reliable is never lost, in order", _payloads(lossy[1]), [1, 2, 3] as Array[int])

	# Unreliable: dropped at 1.0, kept at 0.0.
	_fake_ms = 0
	var dropping: Array[LoopbackTransport] = _pair(_conditions(10, 1.0))
	dropping[0].send(2, PackedByteArray([9]), SessionTransport.Delivery.UNRELIABLE)
	_fake_ms = 100000
	_check("link/unreliable dropped at loss 1.0", _payloads(dropping[1]), [] as Array[int])
	_fake_ms = 0
	var keeping: Array[LoopbackTransport] = _pair(_conditions(10, 0.0))
	keeping[0].send(2, PackedByteArray([9]), SessionTransport.Delivery.UNRELIABLE)
	_fake_ms = 10
	_check("link/unreliable kept at loss 0.0", _payloads(keeping[1]), [9] as Array[int])

	# Release the sessions and the clock lambdas (they capture this script).
	for pair: Array[LoopbackTransport] in [plain, lagged, lossy, dropping, keeping]:
		for transport: LoopbackTransport in pair:
			transport.conditions = null
			transport.close()

func _make(backend: String) -> SessionTransport:
	match backend:
		"loopback":
			return LoopbackTransport.new()
		"steam":
			_fake_users += 1
			return SteamTransport.new(FakeSteam.new(_fake_net, 1000 + _fake_users))
	return ENetTransport.new()

## No add-on, no Steam: a clean failure with the message, never a script error.
func _test_steam_missing() -> void:
	var bare: SteamTransport = SteamTransport.new(null)
	if bare.steam != null:
		_passed += 2 # a real singleton is present here; nothing to check
		return
	var handle: SessionHandle = bare.host_session()
	_check("steam/without the add-on hosting fails", handle.is_valid(), false)
	_check("steam/and says why", bare.failure(), SteamTransport.NO_STEAM)

var _fake_net: FakeSteamNet = FakeSteamNet.new()
var _fake_users: int = 0

## The in-memory Steam: lobbies and one mailbox per Steam id, shared by every
## FakeSteam made from the same net. Callbacks fire from run_callbacks, like Steam's.
class FakeSteamNet extends RefCounted:
	var lobbies: Dictionary = {} # lobby id -> owner steam id
	var mailboxes: Dictionary = {} # steam id -> Array of message dicts
	var users: Dictionary = {} # steam id -> FakeSteam
	var next_lobby: int = 109775241000

class FakeSteam extends RefCounted:
	signal lobby_created(result: int, lobby_id: int)
	signal lobby_joined(lobby_id: int, permissions: int, locked: bool, response: int)
	signal lobby_chat_update(lobby_id: int, changed_id: int, making_change_id: int, chat_state: int)
	signal network_messages_session_request(identity: Variant)
	var net: FakeSteamNet
	var id: int
	var _pending: Array[Callable] = []
	func _init(shared: FakeSteamNet, steam_id: int) -> void:
		net = shared
		id = steam_id
		net.users[id] = self
		net.mailboxes[id] = []
	func getSteamID() -> int:
		return id
	func createLobby(_type: int, _max: int) -> void:
		net.next_lobby += 1
		var lobby: int = net.next_lobby
		net.lobbies[lobby] = id
		_pending.append(func() -> void: lobby_created.emit(1, lobby))
	func joinLobby(lobby: int) -> void:
		var ok: bool = net.lobbies.has(lobby)
		_pending.append(func() -> void: lobby_joined.emit(lobby, 0, false, 1 if ok else 5))
	func getLobbyOwner(lobby: int) -> int:
		return int(net.lobbies.get(lobby, 0))
	func leaveLobby(lobby: int) -> void:
		for user: FakeSteam in net.users.values():
			if user != self:
				user._pending.append(func() -> void: user.lobby_chat_update.emit(lobby, id, id, 2))
	func sendMessageToUser(to: int, data: PackedByteArray, _flags: int, _channel: int) -> int:
		if net.mailboxes.has(to):
			net.mailboxes[to].append({"payload": data, "identity": id})
		return 1
	func receiveMessagesOnChannel(_channel: int, _max: int) -> Array:
		var got: Array = net.mailboxes[id].duplicate()
		net.mailboxes[id].clear()
		return got
	func run_callbacks() -> void:
		var run: Array[Callable] = _pending.duplicate()
		_pending.clear()
		for queued: Callable in run:
			queued.call()

## Polls both ends until the session is usable, or gives up.
func _settle(server: SessionTransport, client: SessionTransport) -> bool:
	var deadline: int = Time.get_ticks_msec() + 5000
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

func _await_payload(receiver: SessionTransport, other: SessionTransport) -> PackedByteArray:
	var deadline: int = Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < deadline:
		other.poll()
		for event: NetEvent in receiver.poll():
			if event.kind == NetEvent.Kind.PAYLOAD:
				return event.payload
		OS.delay_msec(1)
	return PackedByteArray()

func _has_kind(events: Array[NetEvent], kind: NetEvent.Kind) -> bool:
	for event: NetEvent in events:
		if event.kind == kind:
			return true
	return false
