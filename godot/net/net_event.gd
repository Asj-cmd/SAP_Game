class_name NetEvent
extends RefCounted
## Something a transport noticed. Drained by polling, never by callback.
##
## Polling rather than signals because everything above this runs on the
## simulation's fixed tick, and a callback that fires between ticks would apply
## a peer's arrival at a moment the simulation has no name for. Events are
## collected and handed over when asked, so whatever consumes them decides when.

enum Kind {
	## The session is usable. NOT the same as "join_session returned" - that
	## returns immediately and means nothing (see SessionTransport).
	SESSION_READY,
	## The session will never be usable. `reason` is for a human; nothing above
	## the transport should branch on it, because the backends cannot agree on
	## why a relayed connection failed and should not pretend to.
	SESSION_FAILED,
	PEER_JOINED,
	PEER_LEFT,
	## Bytes from `peer`. Untrusted, like everything off the wire.
	PAYLOAD,
}

var kind: Kind = Kind.PAYLOAD
## Who it concerns. Zero for events about the session itself.
var peer: int = 0
var payload: PackedByteArray = PackedByteArray()
var reason: String = ""

static func session_ready(local_peer: int) -> NetEvent:
	var event: NetEvent = NetEvent.new()
	event.kind = Kind.SESSION_READY
	event.peer = local_peer
	return event

static func session_failed(why: String) -> NetEvent:
	var event: NetEvent = NetEvent.new()
	event.kind = Kind.SESSION_FAILED
	event.reason = why
	return event

static func peer_joined(who: int) -> NetEvent:
	var event: NetEvent = NetEvent.new()
	event.kind = Kind.PEER_JOINED
	event.peer = who
	return event

static func peer_left(who: int, why: String = "") -> NetEvent:
	var event: NetEvent = NetEvent.new()
	event.kind = Kind.PEER_LEFT
	event.peer = who
	event.reason = why
	return event

static func payload_from(who: int, bytes: PackedByteArray) -> NetEvent:
	var event: NetEvent = NetEvent.new()
	event.kind = Kind.PAYLOAD
	event.peer = who
	event.payload = bytes
	return event

func _to_string() -> String:
	return "NetEvent(%s peer=%d %dB %s)" % [Kind.keys()[kind], peer, payload.size(), reason]
