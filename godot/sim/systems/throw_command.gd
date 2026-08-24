class_name ThrowCommand
extends SimCommand
## An actor's intent to throw what it is carrying.

const KIND_THROW: StringName = &"Throw"

## Where to throw it, as a direction. Magnitude 0..1, clamped on arrival like
## MoveCommand's - an over-long vector buys no extra range.
##
## A DIRECTION, never a destination. A client that could name the landing spot
## could name any landing spot, including inside its own vault; the simulation
## decides where the arc actually ends (§0.2). It is also the honest shape for
## the verb: you throw a bundle THAT WAY, and where it comes down is the game's
## answer rather than yours.
##
## Low precision, high consequence (DESIGN_DIRECTION §5): the arc is fixed by
## tuning, so aim decides direction and nothing else. Nothing here rewards
## flicking a stick accurately.
var direction: Vector3 = Vector3.ZERO

func _init(
	actor: int = SimEntity.NO_ENTITY,
	aim: Vector3 = Vector3.ZERO,
	tick: int = 0
) -> void:
	super(KIND_THROW, actor, tick)
	direction = aim

static func throw(actor: int, aim: Vector3, tick: int = 0) -> ThrowCommand:
	return ThrowCommand.new(actor, aim, tick)

func to_digest_string() -> String:
	return "%s|a%d,%d,%d" % [
		super(),
		SimEntity.float_bits(direction.x),
		SimEntity.float_bits(direction.y),
		SimEntity.float_bits(direction.z),
	]
