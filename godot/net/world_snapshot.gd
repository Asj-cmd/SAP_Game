class_name WorldSnapshot
extends RefCounted
## A whole world, as bytes. See ARCHITECTURE.md §1.
##
## FULL snapshots, never deltas. At eight actors and a handful of carriables a
## snapshot is a few hundred bytes against a command stream already costing ~32
## bytes a tick, so delta encoding would save little and would introduce the
## baseline-mismatch class of bug - a client decoding a delta against a state it
## never held, producing a world that is wrong in a way nothing detects because
## the delta applied cleanly. Revisit only if a measurement says otherwise.
##
## The same mechanism serves three situations that look different and are not:
##
##   LATE JOIN     - a player who was not there at tick 0 needs the world now
##   RECONNECT     - a player who fell out needs the world now
##   TAKEOVER      - a bot stepping into a seat needs nothing extra, because the
##                   world it inherits is already the one everyone else has
##
## All three are "here is the state, carry on from it", which is why none of
## them gets its own path.
##
## Completeness is proved by DIGEST ROUND TRIP rather than by review: capture,
## restore, and the two worlds must digest identically. That makes rng.state,
## _next_entity_id and the intent epoch impossible to forget - they are all in
## the digest - and it keeps holding as state is added, because a field the
## digest covers and the snapshot omits fails the build the day it appears.

## Bumped when the layout below changes. A peer reading a snapshot it does not
## understand must refuse it rather than decode nonsense into an authoritative
## world; there is no partial credit here.
const FORMAT: int = 1

## Captures everything step() can change. Content is NOT included - zones,
## teams, tuning and geometry are loaded locally from the same files, and
## shipping them would make a snapshot enormous and let a peer's content drift
## from its own level.
static func capture(world: SimWorld) -> PackedByteArray:
	var buffer: StreamPeerBuffer = _buffer()
	buffer.put_u8(FORMAT)
	buffer.put_32(world.tick)
	buffer.put_u8(world.match_phase)
	buffer.put_32(world.phase_ticks_remaining)
	buffer.put_32(world.round_number)
	buffer.put_utf8_string(String(world.round_winner))
	buffer.put_utf8_string(String(world.match_winner))
	buffer.put_32(world.intent_epoch)
	buffer.put_64(world.rng.state)
	buffer.put_32(world.next_entity_id())

	var teams: Array[StringName] = world.sorted_team_ids()
	buffer.put_32(teams.size())
	for team_id: StringName in teams:
		buffer.put_utf8_string(String(team_id))
		buffer.put_32(world.score_for(team_id))
		buffer.put_32(world.round_wins_for(team_id))

	var ids: Array[int] = world.sorted_entity_ids()
	buffer.put_32(ids.size())
	for entity_id: int in ids:
		_put_entity(buffer, world.entities[entity_id])
	return buffer.data_array

## Fills `into` with a captured world. Returns false and leaves `into`
## untouched-in-spirit if the bytes cannot be read.
##
## `into` must already be configured with the same content. It is a STAGING
## world, never the authoritative one: a snapshot arrives off the wire like
## everything else, and half-decoding a hostile packet directly into the world
## the match is being judged from is not a risk worth taking for the copy it
## saves.
static func restore(bytes: PackedByteArray, into: SimWorld) -> bool:
	var buffer: StreamPeerBuffer = _buffer()
	buffer.data_array = bytes
	if buffer.get_available_bytes() < 1:
		return false
	var format: int = buffer.get_u8()
	if format != FORMAT:
		push_error("snapshot: format %d, expected %d - refused" % [format, FORMAT])
		return false
	if buffer.get_available_bytes() < 33:
		return false

	into.tick = buffer.get_32()
	into.match_phase = buffer.get_u8() as SimWorld.MatchPhase
	into.phase_ticks_remaining = buffer.get_32()
	into.round_number = buffer.get_32()
	into.round_winner = StringName(buffer.get_utf8_string())
	into.match_winner = StringName(buffer.get_utf8_string())
	into.intent_epoch = buffer.get_32()
	into.rng.state = buffer.get_64()
	var next_id: int = buffer.get_32()

	var team_count: int = buffer.get_32()
	if team_count < 0 or team_count > 64:
		return false
	var scores: Dictionary[StringName, int] = {}
	var wins: Dictionary[StringName, int] = {}
	for i: int in team_count:
		if buffer.get_available_bytes() < 9:
			return false
		var team_id: StringName = StringName(buffer.get_utf8_string())
		scores[team_id] = buffer.get_32()
		wins[team_id] = buffer.get_32()
	into.scores = scores
	into.round_wins = wins

	var entity_count: int = buffer.get_32()
	if entity_count < 0 or entity_count > 4096:
		return false
	into.entities.clear()
	for i: int in entity_count:
		var entity: SimEntity = _take_entity(buffer)
		if entity == null:
			return false
		into.entities[entity.id] = entity
	# Set last: insert_entity would drag it forward past what was captured, and
	# two peers handing out different next ids is a desync waiting for a spawn.
	into.set_next_entity_id(next_id)
	return true

static func _put_entity(buffer: StreamPeerBuffer, entity: SimEntity) -> void:
	buffer.put_32(entity.id)
	buffer.put_u8(entity.kind)
	buffer.put_utf8_string(String(entity.team))
	buffer.put_32(entity.slot)
	# A label rather than state - no rule reads it and the digest omits it - but
	# carried so a joiner knows who is a bot without being told separately.
	buffer.put_u8(1 if entity.is_bot else 0)
	_put_vector(buffer, entity.position)
	_put_vector(buffer, entity.velocity)
	buffer.put_u8(entity.motion_state)
	buffer.put_u8(1 if entity.is_grounded else 0)
	_put_vector(buffer, entity.move_intent)
	buffer.put_utf8_string(String(entity.zone_id))
	buffer.put_32(entity.carrying_id)
	buffer.put_32(entity.carried_by)
	buffer.put_utf8_string(String(entity.scored_for_team))
	_put_vector(buffer, entity.origin_position)
	buffer.put_u8(1 if entity.is_captured else 0)
	buffer.put_32(entity.capture_ticks_remaining)
	buffer.put_32(entity.captured_on_tick)
	buffer.put_utf8_string(String(entity.safe_zone_id))
	buffer.put_32(entity.safe_ticks_remaining)
	buffer.put_u8(1 if entity.safe_forfeited else 0)

static func _take_entity(buffer: StreamPeerBuffer) -> SimEntity:
	if buffer.get_available_bytes() < 5:
		return null
	var entity: SimEntity = SimEntity.new(buffer.get_32(), buffer.get_u8() as SimEntity.Kind)
	entity.team = StringName(buffer.get_utf8_string())
	entity.slot = buffer.get_32()
	entity.is_bot = buffer.get_u8() == 1
	entity.position = _take_vector(buffer)
	entity.velocity = _take_vector(buffer)
	entity.motion_state = buffer.get_u8() as SimEntity.MotionState
	entity.is_grounded = buffer.get_u8() == 1
	entity.move_intent = _take_vector(buffer)
	entity.zone_id = StringName(buffer.get_utf8_string())
	entity.carrying_id = buffer.get_32()
	entity.carried_by = buffer.get_32()
	entity.scored_for_team = StringName(buffer.get_utf8_string())
	entity.origin_position = _take_vector(buffer)
	entity.is_captured = buffer.get_u8() == 1
	entity.capture_ticks_remaining = buffer.get_32()
	entity.captured_on_tick = buffer.get_32()
	entity.safe_zone_id = StringName(buffer.get_utf8_string())
	entity.safe_ticks_remaining = buffer.get_32()
	entity.safe_forfeited = buffer.get_u8() == 1
	return entity

## 32-bit, matching how the simulation stores them. Widening here would be a
## lie about the precision actually carried, and the digest compares raw bits.
static func _put_vector(buffer: StreamPeerBuffer, value: Vector3) -> void:
	buffer.put_float(value.x)
	buffer.put_float(value.y)
	buffer.put_float(value.z)

static func _take_vector(buffer: StreamPeerBuffer) -> Vector3:
	return Vector3(buffer.get_float(), buffer.get_float(), buffer.get_float())

static func _buffer() -> StreamPeerBuffer:
	var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	buffer.big_endian = false
	return buffer
