class_name LobbyCode
extends RefCounted
## A short typable code for a session. THE FALLBACK, not the front door.
##
## The front door is an invite: a friend clicks it and lands in the lobby with
## nothing to read out, type, or confirm. Steam passes the lobby through a
## launch argument, the game turns it into a SessionHandle, and joining happens
## before the player has seen a menu. Every step between the click and the
## match is friction that costs real players, so there are none.
##
## This exists for the people that path does not cover: someone who is not on
## your friends list, a second machine, a bug report that needs reproducing.
## For those, a code you can read down a voice call is worth having - and it is
## worth being SHORT, because it will be read aloud.
##
## Crockford's alphabet: no I, L, O or U, so there is no 1/I or 0/O confusion
## and nothing accidentally spells anything. Decoding is case-insensitive and
## forgiving about the grouping dashes, because a player reading a code back has
## not agreed to be careful.
##
## No directory service anywhere. The code IS the handle, compressed - an
## address and port pack into six bytes, a Steam lobby id into eight - so there
## is no server to run, nothing to expire, and nothing to be down when someone
## wants to play.

const ALPHABET: String = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
## How the payload was packed. A marker rather than a guess, so a code minted by
## a later build is refused instead of decoded into something plausible.
const PACK_ADDRESS: int = 1 ## enet: four address bytes and a port
const PACK_NUMBER: int = 2 ## steam: one 64-bit id
const PACK_TEXT: int = 3 ## anything else, verbatim

static func encode(handle: SessionHandle) -> String:
	if not handle.is_valid():
		return ""
	var payload: PackedByteArray = _pack(handle)
	if payload.is_empty():
		return ""
	return _group(_to_base32(payload))

static func decode(code: String) -> SessionHandle:
	var cleaned: String = code.to_upper().replace("-", "").replace(" ", "")
	var payload: PackedByteArray = _from_base32(cleaned)
	if payload.size() < 2:
		return SessionHandle.new()
	return _unpack(payload)

# ---- packing ----

static func _pack(handle: SessionHandle) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()

	# An address and port, which is what ENet hands out. Six bytes, ten
	# characters, short enough to read down a phone.
	if handle.backend == &"enet":
		var split: int = handle.token.rfind(":")
		if split > 0:
			var quads: PackedStringArray = handle.token.substr(0, split).split(".")
			var port: int = int(handle.token.substr(split + 1))
			if quads.size() == 4 and port > 0 and port < 65536:
				out.append(PACK_ADDRESS)
				for quad: String in quads:
					out.append(clampi(int(quad), 0, 255))
				out.append(port & 0xFF)
				out.append((port >> 8) & 0xFF)
				return out

	# A bare number, which is what a Steam lobby id is.
	if handle.token.is_valid_int():
		var value: int = int(handle.token)
		out.append(PACK_NUMBER)
		out.append(_backend_code(handle.backend))
		for shift: int in 8:
			out.append((value >> (shift * 8)) & 0xFF)
		return out

	out.append(PACK_TEXT)
	out.append(_backend_code(handle.backend))
	out.append_array(handle.token.to_utf8_buffer())
	return out

static func _unpack(payload: PackedByteArray) -> SessionHandle:
	match payload[0]:
		PACK_ADDRESS:
			if payload.size() < 7:
				return SessionHandle.new()
			var port: int = payload[5] | (payload[6] << 8)
			return SessionHandle.new(&"enet", "%d.%d.%d.%d:%d" % [
				payload[1], payload[2], payload[3], payload[4], port,
			])
		PACK_NUMBER:
			if payload.size() < 10:
				return SessionHandle.new()
			var value: int = 0
			for shift: int in 8:
				value |= payload[2 + shift] << (shift * 8)
			return SessionHandle.new(_backend_name(payload[1]), "%d" % value)
		PACK_TEXT:
			if payload.size() < 3:
				return SessionHandle.new()
			return SessionHandle.new(
				_backend_name(payload[1]), payload.slice(2).get_string_from_utf8()
			)
	return SessionHandle.new()

## Backends get a number so the code does not have to spell their name out.
## Append only - renumbering makes every code in circulation mean something else.
static func _backend_code(backend: StringName) -> int:
	match backend:
		&"enet":
			return 1
		&"steam":
			return 2
		&"loopback":
			return 3
	return 0

static func _backend_name(code: int) -> StringName:
	match code:
		1:
			return &"enet"
		2:
			return &"steam"
		3:
			return &"loopback"
	return &""

# ---- base32 ----

static func _to_base32(bytes: PackedByteArray) -> String:
	var out: String = ""
	var buffer: int = 0
	var bits: int = 0
	for byte: int in bytes:
		buffer = (buffer << 8) | byte
		bits += 8
		while bits >= 5:
			bits -= 5
			out += ALPHABET[(buffer >> bits) & 31]
	if bits > 0:
		out += ALPHABET[(buffer << (5 - bits)) & 31]
	return out

static func _from_base32(text: String) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	var buffer: int = 0
	var bits: int = 0
	for i: int in text.length():
		var value: int = ALPHABET.find(text[i])
		if value < 0:
			return PackedByteArray() # a character that was never in a code
		buffer = (buffer << 5) | value
		bits += 5
		if bits >= 8:
			bits -= 8
			out.append((buffer >> bits) & 0xFF)
	return out

## Grouped for reading aloud. Dashes are cosmetic and decode ignores them.
static func _group(code: String) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var index: int = 0
	while index < code.length():
		parts.append(code.substr(index, 4))
		index += 4
	return "-".join(parts)
