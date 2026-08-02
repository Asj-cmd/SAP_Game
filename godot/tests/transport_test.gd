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

const EXPECTED_CHECKS: int = 28

var _passed: int = 0
var _failed: int = 0
var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	print("=== Session transport contract ===")
	_test_handles_are_opaque()
	for backend: String in ["loopback", "enet"]:
		_test_contract(backend)

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

func _make(backend: String) -> SessionTransport:
	return LoopbackTransport.new() if backend == "loopback" else ENetTransport.new()

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
