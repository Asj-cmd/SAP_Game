class_name MovementEvent
extends SimEvent
## What the movement system did. See ARCHITECTURE.md §5.
##
## Only TRANSITIONS are announced. Continuous facts - where an actor is, which
## state it is in - are read straight off the entity, because polling state is
## the right shape for something true on every tick. An event stream is for
## things that happen once: the footstep loop starting, the grunt of walking
## into a wall, the dust puff on setting off.
##
## States what changed and never how it sounds or looks.

const KIND_MOTION_CHANGED: StringName = &"MotionStateChanged"
## An actor crossed from one zone into another.
const KIND_ZONE_CHANGED: StringName = &"ActorChangedZone"

var from_state: SimEntity.MotionState = SimEntity.MotionState.IDLE
var to_state: SimEntity.MotionState = SimEntity.MotionState.IDLE
var from_zone: StringName = &""
var to_zone: StringName = &""

static func motion_changed(
	tick: int,
	actor: int,
	previous: SimEntity.MotionState,
	current: SimEntity.MotionState
) -> MovementEvent:
	var event: MovementEvent = MovementEvent.new(KIND_MOTION_CHANGED, tick, actor)
	event.from_state = previous
	event.to_state = current
	return event

static func zone_changed(
	tick: int,
	actor: int,
	previous: StringName,
	current: StringName
) -> MovementEvent:
	var event: MovementEvent = MovementEvent.new(KIND_ZONE_CHANGED, tick, actor)
	event.from_zone = previous
	event.to_zone = current
	return event

func to_digest_string() -> String:
	return "%s|s%d>%d|z%s>%s" % [super(), from_state, to_state, from_zone, to_zone]
