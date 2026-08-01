class_name SimEntity
extends RefCounted
## An actor or a carriable. See ARCHITECTURE.md §3.
##
## State only - no rules. Every field here is read and written by systems;
## the entity itself decides nothing. The few methods below are derived
## queries over its own fields, not decisions.
##
## Positions are Vector3 from the first commit (§6).

enum Kind {
	ACTOR, ## A player or bot: moves, carries, captures, is captured.
	CARRIABLE, ## Cash: picked up, carried, deposited, returned.
}

## Sentinel for "no entity" in id-valued fields. Real ids start at 1, assigned
## by SimWorld, so 0 is unambiguous.
const NO_ENTITY: int = 0

var id: int = NO_ENTITY
var kind: Kind = Kind.ACTOR
## Owning team for an actor; for a carriable, the team it originally belongs to.
var team: StringName = &""
## Roster slot within its team, for spawn placement. Meaningless for carriables.
var slot: int = 0
var is_bot: bool = false

var position: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
## Zone containing `position`, refreshed by the system that moves this entity
## so downstream rules need not re-resolve it.
var zone_id: StringName = &""

## ACTOR: the carriable it holds. CARRIABLE: NO_ENTITY (see carried_by).
var carrying_id: int = NO_ENTITY
## CARRIABLE: the actor holding it, or NO_ENTITY when at rest.
var carried_by: int = NO_ENTITY
## CARRIABLE: zone whose score it currently counts toward, empty when in transit.
var scored_for_team: StringName = &""

var is_captured: bool = false
## Ticks of lockup remaining. Counted down by the capture system; never a clock (§3).
var capture_ticks_remaining: int = 0
## Tick on which this actor was seized, -1 when free.
##
## Commands resolve before per-tick updates, so without this the countdown
## would take its first step on the very tick of the capture and a two-second
## sentence would run 1.967s. The sentence starts the tick AFTER the grab.
var captured_on_tick: int = -1

## Sentinel for protection that has no time limit (ZoneDef.safe_duration_seconds == 0).
const SAFE_UNLIMITED: int = -1

## Safe-room protection, owned entirely by CaptureSystem.
##
## The zone currently granting protection, empty when unprotected. Held as an
## id rather than a bool so that leaving and re-entering restarts the grant -
## which is what makes a timed safe room a repeatable tactic rather than a
## once-per-round consumable.
var safe_zone_id: StringName = &""
## Ticks of protection left: SAFE_UNLIMITED for no limit, 0 once lapsed.
var safe_ticks_remaining: int = 0
## Protection given up early (by pickup) rather than run out. Cleared on
## re-entry, so it records this visit only.
var safe_forfeited: bool = false

func _init(entity_id: int = NO_ENTITY, entity_kind: Kind = Kind.ACTOR) -> void:
	id = entity_id
	kind = entity_kind

func is_actor() -> bool:
	return kind == Kind.ACTOR

func is_carriable() -> bool:
	return kind == Kind.CARRIABLE

func is_carrying() -> bool:
	return carrying_id != NO_ENTITY

func is_held() -> bool:
	return carried_by != NO_ENTITY

## Can this actor act at all this tick? Captured actors are inert until freed.
func is_active() -> bool:
	return not is_captured

## Is this actor currently shielded from capture by a safe room?
func is_protected() -> bool:
	if safe_zone_id == &"" or safe_forfeited:
		return false
	return safe_ticks_remaining != 0

## Drops all safe-room protection. Called on leaving a safe zone, and on being
## captured, so a released actor never carries a stale grant back out.
func clear_safety() -> void:
	safe_zone_id = &""
	safe_ticks_remaining = 0
	safe_forfeited = false

## Field-by-field copy. SimWorld snapshots through this, so a stored state
## cannot alias the live one and drift as the simulation continues.
func duplicate_entity() -> SimEntity:
	var copy: SimEntity = SimEntity.new(id, kind)
	copy.team = team
	copy.slot = slot
	copy.is_bot = is_bot
	copy.position = position
	copy.velocity = velocity
	copy.zone_id = zone_id
	copy.carrying_id = carrying_id
	copy.carried_by = carried_by
	copy.scored_for_team = scored_for_team
	copy.is_captured = is_captured
	copy.capture_ticks_remaining = capture_ticks_remaining
	copy.captured_on_tick = captured_on_tick
	copy.safe_zone_id = safe_zone_id
	copy.safe_ticks_remaining = safe_ticks_remaining
	copy.safe_forfeited = safe_forfeited
	return copy

## Scratch buffer for float_bits(). Reused rather than allocated per call:
## the digest walks six floats per entity and may run every tick as a desync
## check. The simulation is single-threaded, so sharing one buffer is safe.
static var _float_scratch: PackedByteArray = _new_float_scratch()

static func _new_float_scratch() -> PackedByteArray:
	var buffer: PackedByteArray = PackedByteArray()
	buffer.resize(8)
	return buffer

## Exact IEEE-754 bit pattern of `value`, as a signed 64-bit integer.
##
## The digest compares these rather than a rounded decimal. A %.4f rendering
## hides every divergence below 1e-4 - which is the scale cross-platform float
## drift STARTS at, and precisely what the digest exists to catch. A digest
## that rounds away the errors it is looking for is worse than no digest,
## because it reports agreement that was never verified.
static func float_bits(value: float) -> int:
	_float_scratch.encode_double(0, value)
	return _float_scratch.decode_s64(0)

## Canonical text form, fed into SimWorld's state digest. Floats appear as raw
## bits; use to_debug_string() when a human needs to read it.
func to_digest_string() -> String:
	return "E%d|k%d|t%s|s%d|p%d,%d,%d|v%d,%d,%d|z%s|c%d|h%d|f%s|x%d|r%d|o%d|S%s,%d,%d" % [
		id, kind, team, slot,
		float_bits(position.x), float_bits(position.y), float_bits(position.z),
		float_bits(velocity.x), float_bits(velocity.y), float_bits(velocity.z),
		zone_id, carrying_id, carried_by, scored_for_team,
		1 if is_captured else 0, capture_ticks_remaining, captured_on_tick,
		safe_zone_id, safe_ticks_remaining, 1 if safe_forfeited else 0,
	]

## Human-readable rendering for logs and debugging. Deliberately NOT what the
## digest hashes: rounded decimals are for eyes, exact bits are for
## correctness. Changing this cannot affect desync detection.
func to_debug_string() -> String:
	return "E%d|k%d|t%s|s%d|p%.4f,%.4f,%.4f|v%.4f,%.4f,%.4f|z%s|c%d|h%d|f%s|x%d|r%d" % [
		id, kind, team, slot,
		position.x, position.y, position.z,
		velocity.x, velocity.y, velocity.z,
		zone_id, carrying_id, carried_by, scored_for_team,
		1 if is_captured else 0, capture_ticks_remaining,
	]
