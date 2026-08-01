class_name CaptureCommand
extends SimCommand
## An actor's intent to capture an opponent, or to free an ally.
##
## Both are the same shape - one actor acting on another at range - so they
## share a class and differ by `kind`. A bot emits these exactly as a human's
## input does (§3): there is no path into the world that bypasses the rules.

const KIND_CAPTURE: StringName = &"Capture"
const KIND_RELEASE: StringName = &"Release"

## Who the acting actor is reaching for.
var target_id: int = SimEntity.NO_ENTITY

func _init(
	command_kind: StringName = &"",
	issuing_actor: int = SimEntity.NO_ENTITY,
	subject: int = SimEntity.NO_ENTITY,
	tick: int = 0
) -> void:
	super(command_kind, issuing_actor, tick)
	target_id = subject

## "I am seizing that opponent."
static func capture(captor_id: int, subject: int, tick: int = 0) -> CaptureCommand:
	return CaptureCommand.new(KIND_CAPTURE, captor_id, subject, tick)

## "I am freeing that ally."
static func release(rescuer_id: int, subject: int, tick: int = 0) -> CaptureCommand:
	return CaptureCommand.new(KIND_RELEASE, rescuer_id, subject, tick)

func to_digest_string() -> String:
	return "%s|g%d" % [super(), target_id]
