class_name CarryCommand
extends SimCommand
## An actor's intent to pick something up, or to let go of it.
##
## Picking a target is the caller's job - a human aims by walking near a
## thing, a bot by choosing one. The simulation re-checks every condition
## regardless, so a mis-aimed command is refused rather than trusted.

const KIND_PICK_UP: StringName = &"PickUp"
const KIND_DROP: StringName = &"Drop"

## The carriable being reached for. Ignored by a drop, which can only ever
## concern whatever the actor is already holding.
var target_id: int = SimEntity.NO_ENTITY

func _init(
	command_kind: StringName = &"",
	actor: int = SimEntity.NO_ENTITY,
	subject: int = SimEntity.NO_ENTITY,
	tick: int = 0
) -> void:
	super(command_kind, actor, tick)
	target_id = subject

static func pick_up(actor: int, subject: int, tick: int = 0) -> CarryCommand:
	return CarryCommand.new(KIND_PICK_UP, actor, subject, tick)

static func drop(actor: int, tick: int = 0) -> CarryCommand:
	return CarryCommand.new(KIND_DROP, actor, SimEntity.NO_ENTITY, tick)

func to_digest_string() -> String:
	return "%s|g%d" % [super(), target_id]
