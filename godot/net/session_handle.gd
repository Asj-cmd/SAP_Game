class_name SessionHandle
extends RefCounted
## How you get into a session. Opaque above the transport.
##
## Deliberately NOT an address and a port. Shipping is over Steam Datagram
## Relay, where you reach a session through a lobby and a friend identity, the
## traffic is relayed, and there is no address anybody above the transport could
## usefully hold. If this type were "host and port", swapping ENet for Steam
## would be a rewrite of everything that touches it rather than a new backend.
##
## So: a backend tag and a token only that backend may interpret. ENet reads the
## token as "address:port". Steam will read it as a lobby id. Nothing above
## either is entitled to look inside, and nothing above either does.
##
## The corollaries matter as much as the type:
##
##   - Reachability is not assumed. A handle is an invitation, not a route, and
##     it may be unusable for reasons nobody above the transport can diagnose.
##   - Addressing is not stable. A relayed route can change mid-session; a
##     handle identifies a SESSION, never a machine.
##   - Joining is not synchronous. See SessionTransport.join_session.

## Which backend minted this. A handle is meaningless to any other.
var backend: StringName = &""
## Backend-private. Never parsed above the transport layer.
var token: String = ""

func _init(for_backend: StringName = &"", opaque: String = "") -> void:
	backend = for_backend
	token = opaque

func is_valid() -> bool:
	return backend != &"" and token != ""

## Round-trips through text so a handle can be pasted into a lobby, put on a
## command line, or sent in a Steam invite without anything in between having to
## understand it.
func to_text() -> String:
	return "%s:%s" % [backend, token]

static func parse(text: String) -> SessionHandle:
	var split: int = text.find(":")
	if split <= 0 or split >= text.length() - 1:
		return SessionHandle.new()
	return SessionHandle.new(StringName(text.substr(0, split)), text.substr(split + 1))

## True when this handle is one the given backend can act on. Checked rather
## than assumed, so handing a Steam invite to the ENet backend fails clearly
## instead of being parsed into a nonsense address.
func is_for(backend_name: StringName) -> bool:
	return is_valid() and backend == backend_name

func _to_string() -> String:
	return "SessionHandle(%s)" % to_text()
