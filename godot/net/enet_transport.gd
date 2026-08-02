class_name ENetTransport
extends SessionTransport
## Sessions over ENet. The backend we can run today.
##
## Uses raw ENetConnection rather than ENetMultiplayerPeer, because the latter
## exists to drive Godot's high-level RPC - node paths, scene tree, replicated
## properties - and this layer must know none of that (§1). What is wanted here
## is a socket that carries bytes.
##
## Everything ENet makes easy that Steam will not, this backend hides:
##
##   - ENet connects to an address. That is what it reads the opaque token as,
##     and it is the only code in the project entitled to.
##   - ENet has no identity, so ids are MINTED here and told to the client in a
##     control packet. Steam has SteamIDs and will not need the handshake. The
##     model above stays the same either way, which is the point.
##   - ENet connects promptly on a LAN. The contract still says asynchronous,
##     and this backend still reports READY through poll() rather than from
##     join_session, so nothing above can come to depend on it being quick.
##
## Direct addressing is NOT the shipping plan. Players behind home routers
## cannot accept connections, so this is for development, LAN and a relay-less
## fallback - never the assumption anything above is written against.

const _BACKEND: StringName = &"enet"
const CHANNELS: int = 2
const MAX_PEERS: int = 8
## Control traffic is prefixed so a payload can never be mistaken for a
## handshake. Everything off the wire is untrusted, including our own protocol.
const _TAG_PAYLOAD: int = 0
const _TAG_WELCOME: int = 1

var _host: ENetConnection = null
var _local: int = 0
var _state: State = State.IDLE
var _failure: String = ""
var _inbox: Array[NetEvent] = []
## Applied on the next poll(), so hosting reports readiness the same way joining
## does. Binding a socket really is immediate; a Steam lobby is not, and callers
## must not be able to tell which backend they are on.
var _becomes_ready: bool = false
## peer id -> the ENet peer object. Ids are ours; ENet knows nothing of them.
var _peers: Dictionary[int, ENetPacketPeer] = {}
var _next_peer: int = HOST_PEER + 1
var _server: ENetPacketPeer = null

func backend_name() -> StringName:
	return _BACKEND

## Binds a listening socket and returns the handle to join it by.
##
## The address inside that handle is only meaningful on a network where this
## machine is reachable. That is exactly the assumption Steam Datagram Relay
## exists to remove, and the reason no caller is allowed to read it.
func host_session() -> SessionHandle:
	_state = State.OPENING
	_host = ENetConnection.new()
	var port: int = 24545
	var opened: Error = _host.create_host_bound("*", port, MAX_PEERS, CHANNELS)
	if opened != OK:
		_fail("could not bind port %d (error %d)" % [port, opened])
		return SessionHandle.new()
	_local = HOST_PEER
	_becomes_ready = true
	return SessionHandle.new(_BACKEND, "127.0.0.1:%d" % port)

func join_session(handle: SessionHandle) -> void:
	if not handle.is_for(_BACKEND):
		_fail("handle is not an %s session" % _BACKEND)
		return
	var split: int = handle.token.rfind(":")
	if split <= 0:
		_fail("malformed session token")
		return

	_state = State.OPENING
	_host = ENetConnection.new()
	if _host.create_host(1, CHANNELS) != OK:
		_fail("could not create client host")
		return
	_server = _host.connect_to_host(
		handle.token.substr(0, split), int(handle.token.substr(split + 1)), CHANNELS
	)
	if _server == null:
		_fail("could not reach the session")
		return
	# Deliberately NOT ready yet. The id arrives in a welcome packet, and until
	# it does this machine does not know who it is - the same shape as being
	# admitted to a relayed session.

func state() -> State:
	return _state

func failure() -> String:
	return _failure

func local_peer() -> int:
	return _local if _state == State.READY else 0

func peers() -> PackedInt32Array:
	var found: PackedInt32Array = PackedInt32Array()
	if _state != State.READY:
		return found
	if is_host():
		for peer_id: int in _peers:
			found.append(peer_id)
	elif _server != null:
		found.append(HOST_PEER)
	found.sort()
	return found

func send(peer: int, payload: PackedByteArray, delivery: Delivery = Delivery.RELIABLE) -> void:
	if _state != State.READY:
		return
	var target: ENetPacketPeer = _server if not is_host() else _peers.get(peer, null)
	if target == null:
		return # gone between deciding to send and sending; not an error
	var framed: PackedByteArray = PackedByteArray([_TAG_PAYLOAD])
	framed.append_array(payload)
	target.send(
		0 if delivery == Delivery.RELIABLE else 1,
		framed,
		ENetPacketPeer.FLAG_RELIABLE if delivery == Delivery.RELIABLE else 0
	)

func poll() -> Array[NetEvent]:
	# Before servicing, so a host is itself before it starts admitting anyone.
	if _becomes_ready:
		_becomes_ready = false
		_state = State.READY
		_inbox.append(NetEvent.session_ready(_local))
	if _host != null:
		# Zero timeout: this is called from a loop that has its own pacing, and
		# a transport that blocks would set the tick rate.
		var event: Array = _host.service(0)
		while event.size() > 0 and int(event[0]) != ENetConnection.EVENT_NONE:
			_handle(event)
			event = _host.service(0)
	var drained: Array[NetEvent] = _inbox.duplicate()
	_inbox.clear()
	return drained

func _handle(event: Array) -> void:
	var kind: int = int(event[0])
	var peer: ENetPacketPeer = event[1]
	match kind:
		ENetConnection.EVENT_CONNECT:
			if is_host():
				_admit(peer)
		ENetConnection.EVENT_DISCONNECT:
			_forget(peer)
		ENetConnection.EVENT_RECEIVE:
			_receive(peer)
		ENetConnection.EVENT_ERROR:
			_fail("transport error")

## Mints an id for an arriving peer and tells it what it is.
##
## The handshake exists only because ENet has no notion of who anyone is. Steam
## does, so its backend will delete this and change nothing above.
func _admit(peer: ENetPacketPeer) -> void:
	var assigned: int = _next_peer
	_next_peer += 1
	_peers[assigned] = peer

	var welcome: PackedByteArray = PackedByteArray([_TAG_WELCOME])
	welcome.append_array(PackedByteArray([assigned & 0xFF, (assigned >> 8) & 0xFF]))
	peer.send(0, welcome, ENetPacketPeer.FLAG_RELIABLE)
	_inbox.append(NetEvent.peer_joined(assigned))

func _forget(peer: ENetPacketPeer) -> void:
	if is_host():
		for peer_id: int in _peers.keys():
			if _peers[peer_id] == peer:
				_peers.erase(peer_id)
				_inbox.append(NetEvent.peer_left(peer_id))
				return
		return
	_server = null
	_state = State.CLOSED
	_inbox.append(NetEvent.peer_left(HOST_PEER, "host went away"))

func _receive(peer: ENetPacketPeer) -> void:
	var packet: PackedByteArray = peer.get_packet()
	if packet.is_empty():
		return
	var tag: int = packet[0]
	var body: PackedByteArray = packet.slice(1)

	if tag == _TAG_WELCOME:
		# Only meaningful to a client that has not been told who it is. A host
		# receiving one, or a second one arriving, is a peer talking nonsense.
		if is_host() or _state == State.READY or body.size() < 2:
			return
		_local = body[0] | (body[1] << 8)
		_state = State.READY
		_inbox.append(NetEvent.session_ready(_local))
		_inbox.append(NetEvent.peer_joined(HOST_PEER))
		return

	if tag != _TAG_PAYLOAD:
		return # unknown framing: dropped, never guessed at
	_inbox.append(NetEvent.payload_from(_peer_id_of(peer), body))

func _peer_id_of(peer: ENetPacketPeer) -> int:
	if not is_host():
		return HOST_PEER
	for peer_id: int in _peers:
		if _peers[peer_id] == peer:
			return peer_id
	return 0

func close() -> void:
	if _host != null:
		_host.destroy()
		_host = null
	_peers.clear()
	_server = null
	_local = 0
	_state = State.CLOSED

func _fail(why: String) -> void:
	_failure = why
	_state = State.FAILED
	_inbox.append(NetEvent.session_failed(why))
