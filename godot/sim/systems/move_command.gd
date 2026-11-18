class_name MoveCommand
extends SimCommand
## An actor's intent to travel in a direction.
##
## Intent, never a position. A client that could name its own destination
## could name any destination; the simulation decides where that intent
## actually gets it, which is the whole point of §0.2. Magnitude carries
## analog-stick strength and is clamped to 1 on arrival, so an over-long
## vector buys no extra speed.

const KIND_MOVE: StringName = &"Move"

## World-space direction, magnitude 0..1. Zero means "stop".
var intent: Vector3 = Vector3.ZERO

func _init(
	actor: int = SimEntity.NO_ENTITY,
	direction: Vector3 = Vector3.ZERO,
	tick: int = 0
) -> void:
	super(KIND_MOVE, actor, tick)
	intent = direction

static func move(actor: int, direction: Vector3, tick: int = 0) -> MoveCommand:
	return MoveCommand.new(actor, direction, tick)

## Explicit stop. Intent persists between ticks, so halting is a command in
## its own right rather than the absence of one.
static func stop(actor: int, tick: int = 0) -> MoveCommand:
	return MoveCommand.new(actor, Vector3.ZERO, tick)

func to_digest_string() -> String:
	return "%s|d%d,%d,%d" % [
		super(),
		SimEntity.float_bits(intent.x),
		SimEntity.float_bits(intent.y),
		SimEntity.float_bits(intent.z),
	]
