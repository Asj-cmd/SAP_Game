class_name LoopbackTransport
extends SessionTransport
## Two peers in one process, joined by an array.
##
## Not a stub. It is the REFERENCE the other backends are judged against: the
## per-tick lockstep result the loopback harness produces is what a real
## transport has to reproduce, and a backend that cannot is wrong rather than
## merely slower. Having it also means the whole layer above - framing,
## prediction, reconciliation - can be built and tested headless, with no
## sockets, no ports and no timing.
##
## It honours the awkward parts of the contract rather than shortcutting them,
## because a reference that is easier than reality validates nothing:
## join_session still returns nothing, the session still is not READY on the
## call that opened it, and local_peer() is still 0 until it is. Code written
## against this cannot acquire habits that break on a relay.

const _BACKEND: StringName = &"loopback"

## Sessions currently open in this process, by token. Static because the two
## ends of a loopback session are two objects that have to find each other.
static var _sessions: Dictionary[String, Array] = {}
static var _next_token: int = 1

var _token: String = ""
var _local: int = 0
var _state: State = State.IDLE
var _failure: String = ""
var _inbox: Array[NetEvent] = []
## Readiness is applied on the next poll(), never on the call that asked for it.
var _becomes_ready: bool = false

func backend_name() -> StringName:
	return _BACKEND

func host_session() -> SessionHandle:
	_token = "session-%d" % _next_token
	_next_token += 1
	_sessions[_token] = [self] as Array
	_local = HOST_PEER
	# OPENING, not READY, even though nothing actually has to happen here.
	#
	# The gap is kept deliberately. A reference that is EASIER than reality
	# validates nothing: if this went straight to READY, every caller written
	# against it would quietly assume a session is usable the moment it is
	# asked for, and every one of them would break on a relay. Readiness is
	# applied in poll(), so the polling shape is the only shape that works.
	_state = State.OPENING
	_becomes_ready = true
	return SessionHandle.new(_BACKEND, _token)

func join_session(handle: SessionHandle) -> void:
	if not handle.is_for(_BACKEND):
		_fail("handle is not a %s session" % _BACKEND)
		return
	if not _sessions.has(handle.token):
		_fail("no session %s in this process" % handle.token)
		return

	_state = State.OPENING
	_token = handle.token
	var members: Array = _sessions[_token]
	_local = members.size() + 1
	members.append(self)

	_becomes_ready = true
	for other: LoopbackTransport in members:
		if other == self:
			continue
		other._inbox.append(NetEvent.peer_joined(_local))
		_inbox.append(NetEvent.peer_joined(other._local))

func state() -> State:
	return _state

func failure() -> String:
	return _failure

func local_peer() -> int:
	return _local if _state == State.READY else 0

func peers() -> PackedInt32Array:
	var found: PackedInt32Array = PackedInt32Array()
	if not _sessions.has(_token):
		return found
	for other: LoopbackTransport in _sessions[_token]:
		if other != self and other._state == State.READY:
			found.append(other._local)
	found.sort()
	return found

## Delivery is immediate, and identical for both modes.
##
## No dropping and no reordering even for UNRELIABLE, because this is the
## reference: it establishes what correct looks like with the wire out of the
## picture. Loss and latency are the next harness's job, not this one's - a
## reference that also misbehaves cannot tell you which half is at fault.
func send(peer: int, payload: PackedByteArray, _delivery: Delivery = Delivery.RELIABLE) -> void:
	if _state != State.READY or not _sessions.has(_token):
		return
	for other: LoopbackTransport in _sessions[_token]:
		if other._local == peer and other._state == State.READY:
			other._inbox.append(NetEvent.payload_from(_local, payload.duplicate()))
			return

func poll() -> Array[NetEvent]:
	if _becomes_ready:
		_becomes_ready = false
		_state = State.READY
		_inbox.push_front(NetEvent.session_ready(_local))
	var drained: Array[NetEvent] = _inbox.duplicate()
	_inbox.clear()
	return drained

func close() -> void:
	if _sessions.has(_token):
		var members: Array = _sessions[_token]
		members.erase(self)
		for other: LoopbackTransport in members:
			other._inbox.append(NetEvent.peer_left(_local, "closed"))
		if members.is_empty():
			_sessions.erase(_token)
	_state = State.CLOSED
	_local = 0

func _fail(why: String) -> void:
	_failure = why
	_state = State.FAILED
	_inbox.append(NetEvent.session_failed(why))
