class_name CommandCodec
extends RefCounted
## Puts commands on the wire and takes them off again. See ARCHITECTURE.md §1.
##
## The first piece of the network layer, and deliberately the piece that needs
## no transport decision: whether this ends up on ENet, Steam sockets or a
## loopback, a command stream has to survive the trip EXACTLY. The whole design
## rests on it - clients predict by running the same step() locally and the
## server's result reconciles because both ran identical logic on identical
## commands. A codec that rounds a direction vector by one bit breaks that, and
## breaks it as a slow desync rather than as an error.
##
## So the round trip is lossless by construction. Vector3 components are already
## 32-bit floats (§6), so writing them as 32-bit floats returns the same bits;
## tests/command_codec_test.gd asserts that on the bit pattern, not on an
## approximate compare, because approximate is exactly what a desync looks like
## before it becomes obvious.
##
## Knows sim/, never scenes (§1). It is below presentation and above nothing.

## Wire codes. The index IS the code, so entries may only ever be APPENDED -
## inserting one renumbers every command after it and a client on the old build
## silently reads a Drop as a Capture. Removing one is equally forbidden; retire
## a command by leaving its slot dead.
const KINDS: Array[StringName] = [
	MoveCommand.KIND_MOVE,
	CarryCommand.KIND_PICK_UP,
	CarryCommand.KIND_DROP,
	CaptureCommand.KIND_CAPTURE,
	CaptureCommand.KIND_RELEASE,
	MatchCommand.KIND_START_MATCH,
	MatchCommand.KIND_REMATCH,
]

## Ceiling on how many commands one batch may claim to hold.
##
## Nothing legitimate approaches it - a tick carries a handful - and without it
## a malformed length field asks for an allocation the size of the number it
## happened to contain. Everything arriving here is untrusted.
const MAX_BATCH: int = 1024

## One command as bytes, or an empty buffer if it is not a kind we can send.
static func encode(command: SimCommand) -> PackedByteArray:
	var code: int = KINDS.find(command.kind)
	if code < 0:
		push_error("command codec: no wire code for '%s'" % command.kind)
		return PackedByteArray()

	var buffer: StreamPeerBuffer = _buffer()
	buffer.put_u8(code)
	buffer.put_32(command.actor_id)
	buffer.put_32(command.issued_tick)

	match command.kind:
		MoveCommand.KIND_MOVE:
			var move: MoveCommand = command as MoveCommand
			# 32-bit, matching the storage. Widening to a double here would be
			# a lie about the precision the simulation actually carries.
			buffer.put_float(move.intent.x)
			buffer.put_float(move.intent.y)
			buffer.put_float(move.intent.z)
		CarryCommand.KIND_PICK_UP:
			buffer.put_32((command as CarryCommand).target_id)
		CaptureCommand.KIND_CAPTURE, CaptureCommand.KIND_RELEASE:
			buffer.put_32((command as CaptureCommand).target_id)
		_:
			pass # Drop and the match commands carry nothing beyond the header
	return buffer.data_array

## One tick's worth of commands, length-prefixed.
static func encode_batch(commands: Array[SimCommand]) -> PackedByteArray:
	var buffer: StreamPeerBuffer = _buffer()
	buffer.put_32(commands.size())
	for command: SimCommand in commands:
		var encoded: PackedByteArray = encode(command)
		if encoded.is_empty():
			continue
		buffer.put_32(encoded.size())
		buffer.put_data(encoded)
	return buffer.data_array

## Reads a batch back. Returns what it could decode and reports the rest.
##
## Never trusts the buffer. A truncated or hostile packet yields fewer commands
## and an error, never a fabricated command and never a crash - the simulation
## downstream re-validates everything anyway, but a decoder that invents an
## actor id is handing it something to validate that nobody sent.
static func decode_batch(bytes: PackedByteArray) -> Array[SimCommand]:
	var commands: Array[SimCommand] = []
	var buffer: StreamPeerBuffer = _buffer()
	buffer.data_array = bytes
	if buffer.get_available_bytes() < 4:
		return commands

	var claimed: int = buffer.get_32()
	if claimed < 0 or claimed > MAX_BATCH:
		push_error("command codec: batch claims %d commands - refused" % claimed)
		return commands

	for i: int in claimed:
		if buffer.get_available_bytes() < 4:
			push_error("command codec: batch ended early, %d of %d read" % [i, claimed])
			return commands
		var length: int = buffer.get_32()
		if length <= 0 or length > buffer.get_available_bytes():
			push_error("command codec: command %d claims %d bytes - refused" % [i, length])
			return commands
		var command: SimCommand = decode(buffer.get_data(length)[1])
		if command != null:
			commands.append(command)
	return commands

## One command from bytes, or null if it cannot be read.
static func decode(bytes: PackedByteArray) -> SimCommand:
	if bytes.size() < 9: # kind + actor + tick
		return null
	var buffer: StreamPeerBuffer = _buffer()
	buffer.data_array = bytes

	var code: int = buffer.get_u8()
	if code < 0 or code >= KINDS.size():
		push_error("command codec: unknown wire code %d" % code)
		return null
	var kind: StringName = KINDS[code]
	var actor: int = buffer.get_32()
	var tick: int = buffer.get_32()

	match kind:
		MoveCommand.KIND_MOVE:
			if buffer.get_available_bytes() < 12:
				return null
			var intent: Vector3 = Vector3(
				buffer.get_float(), buffer.get_float(), buffer.get_float()
			)
			return MoveCommand.new(actor, intent, tick)
		CarryCommand.KIND_PICK_UP:
			if buffer.get_available_bytes() < 4:
				return null
			return CarryCommand.pick_up(actor, buffer.get_32(), tick)
		CarryCommand.KIND_DROP:
			return CarryCommand.drop(actor, tick)
		CaptureCommand.KIND_CAPTURE:
			if buffer.get_available_bytes() < 4:
				return null
			return CaptureCommand.capture(actor, buffer.get_32(), tick)
		CaptureCommand.KIND_RELEASE:
			if buffer.get_available_bytes() < 4:
				return null
			return CaptureCommand.release(actor, buffer.get_32(), tick)
		MatchCommand.KIND_START_MATCH:
			return MatchCommand.start(tick)
		MatchCommand.KIND_REMATCH:
			return MatchCommand.rematch(tick)
	return null

## Byte order is fixed rather than left to the platform. Two machines that
## disagree about it decode every integer backwards, and the symptom is a desync
## rather than anything that says "endianness".
static func _buffer() -> StreamPeerBuffer:
	var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	buffer.big_endian = false
	return buffer
