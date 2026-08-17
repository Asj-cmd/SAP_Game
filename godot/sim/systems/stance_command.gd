class_name StanceCommand
extends SimCommand
## An actor's intent to be crouched, or not.

const KIND_STANCE: StringName = &"Stance"

## True while the player wants to be low. Not a toggle and not "crouch now":
## the simulation decides whether the actor GETS to be crouched, and more
## importantly whether it gets to stand back up - a body under a counter that
## releases the key must stay down until it has walked out from under.
##
## Held rather than edge-triggered for the same reason move_intent is: a client
## emits at input rate, not tick rate, and a dropped packet must not leave an
## actor stuck in a stance nobody asked for. A late or repeated command carries
## the whole truth, so re-sending it is always safe.
var wants_crouch: bool = false

func _init(
	actor: int = SimEntity.NO_ENTITY,
	crouching: bool = false,
	tick: int = 0
) -> void:
	super(KIND_STANCE, actor, tick)
	wants_crouch = crouching

static func crouch(actor: int, tick: int = 0) -> StanceCommand:
	return StanceCommand.new(actor, true, tick)

static func stand(actor: int, tick: int = 0) -> StanceCommand:
	return StanceCommand.new(actor, false, tick)

func to_digest_string() -> String:
	return "%s|c%d" % [super(), 1 if wants_crouch else 0]
