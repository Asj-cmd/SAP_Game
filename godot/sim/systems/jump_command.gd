class_name JumpCommand
extends SimCommand
## An actor's intent to leave the ground.

const KIND_JUMP: StringName = &"Jump"

## EDGE-TRIGGERED, unlike StanceCommand's held bool, and the difference is the
## verb rather than the style. Crouch is a state you are in; a jump is a thing
## you do once. Sending it level-triggered would launch an actor again on every
## tick the button was down - the same fault the carry toggle had, where holding
## Q toggled n times and whether you ended up with the cash came down to the
## parity of how long you leaned on the key.
##
## Carries no payload for the same reason: there is nothing to say beyond "now".
## Height is tuning, direction is wherever the body was already travelling.
func _init(actor: int = SimEntity.NO_ENTITY, tick: int = 0) -> void:
	super(KIND_JUMP, actor, tick)

static func jump(actor: int, tick: int = 0) -> JumpCommand:
	return JumpCommand.new(actor, tick)
