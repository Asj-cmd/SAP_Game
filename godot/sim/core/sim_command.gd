class_name SimCommand
extends RefCounted
## An intent to change the world. See ARCHITECTURE.md §0.2 and §3.
##
## Nothing mutates the world directly - not a player, not a bot, not the
## server. Every change enters here. That single constraint is what makes
## netcode, replays and headless verification possible at all: record the seed
## and the command stream and the match re-simulates exactly.
##
## This is a BASE class. Systems define their own typed subclasses
## (MoveCommand, PickUpCommand, ...) carrying their own typed fields, rather
## than this class growing an untyped payload bag. No systems exist yet, so no
## subclasses exist yet.

## Who is asking. NO_ENTITY for commands issued by the match itself rather
## than by an actor (starting a round, ending a match).
var actor_id: int = SimEntity.NO_ENTITY
## Identifies the intent. Subclasses set this in their own _init.
var kind: StringName = &""
## Tick the issuer believed it was on. Networking compares this against the
## world's own tick to detect and correct for latency; it is never used as a
## clock (§3).
var issued_tick: int = 0

func _init(command_kind: StringName = &"", issuing_actor: int = SimEntity.NO_ENTITY, tick: int = 0) -> void:
	kind = command_kind
	actor_id = issuing_actor
	issued_tick = tick

## True for commands the match issues rather than an actor.
func is_system_command() -> bool:
	return actor_id == SimEntity.NO_ENTITY

## Canonical text form, for the command-stream log a replay is recorded from.
## Subclasses append their own fields.
func to_digest_string() -> String:
	return "C%s|a%d|t%d" % [kind, actor_id, issued_tick]

func _to_string() -> String:
	return "SimCommand(%s)" % to_digest_string()
