class_name CarryEvent
extends SimEvent
## What the carry system did. See ARCHITECTURE.md §5.
##
## No prop attaching, no sound, no flash - presentation subscribes and owns
## every bit of that.

const KIND_PICKED_UP: StringName = &"CashPickedUp"
const KIND_DROPPED: StringName = &"CashDropped"

## The carriable concerned. `actor_id` is who acted on it.
var carriable_id: int = SimEntity.NO_ENTITY

static func picked_up(tick: int, actor: int, carriable: int) -> CarryEvent:
	var event: CarryEvent = CarryEvent.new(KIND_PICKED_UP, tick, actor)
	event.carriable_id = carriable
	return event

static func dropped(tick: int, actor: int, carriable: int) -> CarryEvent:
	var event: CarryEvent = CarryEvent.new(KIND_DROPPED, tick, actor)
	event.carriable_id = carriable
	return event

func to_digest_string() -> String:
	return "%s|c%d" % [super(), carriable_id]
