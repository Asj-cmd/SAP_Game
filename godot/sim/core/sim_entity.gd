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
	return copy

## Canonical text form, fed into SimWorld's state digest. Vectors are printed
## at fixed precision so the digest cannot wobble on float formatting.
func to_digest_string() -> String:
	return "E%d|k%d|t%s|s%d|p%.4f,%.4f,%.4f|v%.4f,%.4f,%.4f|z%s|c%d|h%d|f%s|x%d|r%d" % [
		id, kind, team, slot,
		position.x, position.y, position.z,
		velocity.x, velocity.y, velocity.z,
		zone_id, carrying_id, carried_by, scored_for_team,
		1 if is_captured else 0, capture_ticks_remaining,
	]
