class_name SessionTransport
extends RefCounted
## Getting bytes between the machines in one session. See ARCHITECTURE.md §1.
##
## The interface is shaped around STEAM, not around ENet, because Steam is where
## this has to end up and the awkward model should be the one that fits natively:
##
##   - You JOIN A SESSION with an opaque handle. You do not connect to an
##     address. ENet interprets the handle as an address; that is the ENet
##     backend's business and nobody else's.
##   - Joining is ASYNCHRONOUS and join_session() returns nothing. Over a relay
##     there is no moment where a connection either works or does not - there is
##     a negotiation that may take seconds and may fail for reasons the caller
##     cannot act on. Callers watch for SESSION_READY or SESSION_FAILED.
##   - Peers are opaque IDs, not addresses. A relayed route may change mid-
##     session; the id survives it because it identifies a participant rather
##     than a location.
##   - Reachability is never assumed. Shipping is over Steam Datagram Relay
##     precisely because players behind home routers cannot accept direct
##     connections, so nothing above this may assume it can be reached, that it
##     knows its own address, or that any peer can be addressed directly.
##
## Every one of those is a constraint the ENet backend could ignore and the
## Steam backend could not. Writing them into the interface now is what keeps
## the swap a new file rather than a rewrite.
##
## Knows bytes. It does not know what a command is, and it does not know what a
## tick is - framing belongs above.

enum State {
	IDLE, ## Nothing started.
	OPENING, ## Hosting or joining is in progress. May stay here a while.
	READY, ## Usable.
	FAILED, ## Will never be usable. See failure().
	CLOSED, ## Was usable, is finished.
}

enum Delivery {
	RELIABLE, ## Arrives, and in order. For anything a match depends on.
	UNRELIABLE, ## May be dropped. For anything superseded by the next one.
}

## The peer id of whoever is running the session. Fixed by convention so a
## client can address the host before learning anything else.
const HOST_PEER: int = 1

func backend_name() -> StringName:
	return &""

## Opens a session and returns the handle others join by.
##
## The handle is available immediately even though the session may not be:
## Steam creates the lobby before anyone can route to it, and a caller needs
## something to put in an invite before it is usable.
func host_session() -> SessionHandle:
	return SessionHandle.new()

## Begins joining. Returns nothing, on purpose.
##
## There is no success to report yet and there may not be for some time. A
## caller that wants to know watches poll() for SESSION_READY or
## SESSION_FAILED. An interface that returned a bool here would be one every
## caller quietly treats as "connected", which is exactly the assumption a relay
## breaks.
func join_session(_handle: SessionHandle) -> void:
	pass

func state() -> State:
	return State.IDLE

## Why the session failed, for a human. Nothing may branch on this text: the
## backends genuinely cannot agree on why a relayed connection did not happen.
func failure() -> String:
	return ""

## This machine's id, or 0 before the session is ready.
##
## Zero until READY because over a relay you are not told who you are until the
## session accepts you. Anything that needs its own id needs to have waited.
func local_peer() -> int:
	return 0

func is_host() -> bool:
	return local_peer() == HOST_PEER

## Everyone else currently in the session, in ascending id order.
func peers() -> PackedInt32Array:
	return PackedInt32Array()

## Sends to one peer. Silently does nothing if the session is not ready or the
## peer has gone - a departure and a send race constantly, and making that an
## error would mean every caller handling a case it cannot prevent.
func send(_peer: int, _payload: PackedByteArray, _delivery: Delivery = Delivery.RELIABLE) -> void:
	pass

func broadcast(payload: PackedByteArray, delivery: Delivery = Delivery.RELIABLE) -> void:
	for peer: int in peers():
		send(peer, payload, delivery)

## Everything that happened since the last call. Never returns the same event
## twice.
func poll() -> Array[NetEvent]:
	return []

func close() -> void:
	pass
