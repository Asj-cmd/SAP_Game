class_name MatchChannel
extends RefCounted
## What host and guest actually say to each other.
##
## The transport moves bytes and has no opinion about them; this is the one
## layer that decides what a message MEANS. Four kinds, and a tag byte in front
## so a snapshot can never be read as a command batch - the two are both "a
## PackedByteArray off the wire" and telling them apart by length or by trying
## each in turn is how a client ends up restoring a world from somebody's input.
##
## Framing lives here rather than in the game layer because it is protocol: two
## builds must agree on it, and a rule about what a byte means belongs next to
## the codec and the snapshot rather than next to the camera.

## Host to guest: everything applied on one tick.
const TAG_COMMANDS: int = 1
## Host to guest: a full world. Sent on join, periodically, and on repair.
const TAG_SNAPSHOT: int = 2
## Guest to host: one player's input, already stamped with the tick it belongs on.
const TAG_INPUT: int = 3
## Guest to host: who I am, across connections.
##
## Sent once the session is usable, and BEFORE a seat is assigned - the host
## cannot know whether an arriving connection is a new player or somebody
## returning until it has been told, and a peer id cannot tell it (a reconnect
## has a new one). See PlayerIdentity.
const TAG_HELLO: int = 5

## Host to guest: which actor you are driving.
##
## Sent once, after the first snapshot. A guest cannot work this out for itself
## - the roster is identical on both sides and nothing in it says "you" - and
## guessing by team or by slot would hand two guests the same body.
const TAG_SEAT: int = 4

static func frame(tag: int, payload: PackedByteArray) -> PackedByteArray:
	var framed: PackedByteArray = PackedByteArray([tag])
	framed.append_array(payload)
	return framed

## The tag, or 0 for anything too short to have one.
static func tag_of(bytes: PackedByteArray) -> int:
	return bytes[0] if bytes.size() >= 1 else 0

static func body_of(bytes: PackedByteArray) -> PackedByteArray:
	return bytes.slice(1) if bytes.size() >= 1 else PackedByteArray()

## A seat assignment is one integer, but it still gets a length check on the way
## back in - everything off the wire is untrusted, including our own protocol.
static func frame_seat(actor_id: int) -> PackedByteArray:
	var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	buffer.big_endian = false
	buffer.put_32(actor_id)
	return frame(TAG_SEAT, buffer.data_array)

static func seat_of(body: PackedByteArray) -> int:
	if body.size() < 4:
		return SimEntity.NO_ENTITY
	var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	buffer.big_endian = false
	buffer.data_array = body
	return buffer.get_32()

## A player's identity, as UTF-8. Length-checked on the way back in like
## everything else off the wire.
static func frame_hello(token: String) -> PackedByteArray:
	return frame(TAG_HELLO, token.to_utf8_buffer())

static func token_of(body: PackedByteArray) -> String:
	if body.is_empty() or body.size() > PlayerIdentity.MAX_LENGTH:
		return ""
	return body.get_string_from_utf8()
