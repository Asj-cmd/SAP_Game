class_name MatchCommand
extends SimCommand
## Instructions to the match itself rather than to an actor.
##
## Issued by whoever is running the lobby, not by a player in the world, so
## actor_id is NO_ENTITY - these are the system commands SimCommand.
## is_system_command() describes.

const KIND_START_MATCH: StringName = &"StartMatch"
## Reset scores and rounds and play again with the same roster.
const KIND_REMATCH: StringName = &"Rematch"

func _init(command_kind: StringName = &"", tick: int = 0) -> void:
	super(command_kind, SimEntity.NO_ENTITY, tick)

static func start(tick: int = 0) -> MatchCommand:
	return MatchCommand.new(KIND_START_MATCH, tick)

static func rematch(tick: int = 0) -> MatchCommand:
	return MatchCommand.new(KIND_REMATCH, tick)
