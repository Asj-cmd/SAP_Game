class_name CaptureEvent
extends SimEvent
## What the capture system did. See ARCHITECTURE.md §5.
##
## States what happened and never how it looks: no ragdoll, no VFX, no sting.
## Presentation subscribes and owns all of that, which is why juice can be
## reworked freely without any risk to correctness.

const KIND_CAPTURED: StringName = &"ActorCaptured"
const KIND_RELEASED: StringName = &"ActorReleased"
## Safe-room protection ended while the actor was still standing in the room.
## Presentation wants this for the moment the shield drops; rules read the
## entity's own state rather than listening for it.
const KIND_SAFETY_LAPSED: StringName = &"SafetyLapsed"
## A captured actor was holding something. The carry system owns where it goes
## from here; capture only states that the hold was broken.
const KIND_CARRIABLE_RELEASED: StringName = &"CarriableReleased"

## Why a release or lapse happened.
const REASON_RESCUE: StringName = &"rescue"
const REASON_TIMEOUT: StringName = &"timeout"
const REASON_EXPIRED: StringName = &"expired"
const REASON_PICKUP: StringName = &"pickup"

## The other party: the captor for a capture, the rescuer for a rescue,
## NO_ENTITY when nobody caused it (a timer running out).
var agent_id: int = SimEntity.NO_ENTITY
## The carriable, for KIND_CARRIABLE_RELEASED.
var carriable_id: int = SimEntity.NO_ENTITY
var reason: StringName = &""
var zone_id: StringName = &""

func _init(
	event_kind: StringName = &"",
	event_tick: int = 0,
	subject: int = SimEntity.NO_ENTITY,
	other: int = SimEntity.NO_ENTITY,
	why: StringName = &"",
	zone: StringName = &""
) -> void:
	super(event_kind, event_tick, subject)
	agent_id = other
	reason = why
	zone_id = zone

static func captured(tick: int, subject: int, captor: int, jail_zone: StringName) -> CaptureEvent:
	return CaptureEvent.new(KIND_CAPTURED, tick, subject, captor, &"", jail_zone)

static func released(tick: int, subject: int, rescuer: int, why: StringName) -> CaptureEvent:
	return CaptureEvent.new(KIND_RELEASED, tick, subject, rescuer, why)

static func safety_lapsed(tick: int, subject: int, why: StringName, zone: StringName) -> CaptureEvent:
	return CaptureEvent.new(KIND_SAFETY_LAPSED, tick, subject, SimEntity.NO_ENTITY, why, zone)

static func carriable_released(tick: int, subject: int, carriable: int) -> CaptureEvent:
	var event: CaptureEvent = CaptureEvent.new(KIND_CARRIABLE_RELEASED, tick, subject)
	event.carriable_id = carriable
	return event

func to_digest_string() -> String:
	return "%s|g%d|c%d|w%s|z%s" % [super(), agent_id, carriable_id, reason, zone_id]
