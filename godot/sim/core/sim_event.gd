class_name SimEvent
extends RefCounted
## A record that something happened. See ARCHITECTURE.md §5.
##
## Events state WHAT HAPPENED and never HOW IT LOOKS. `CashPickedUp` carries no
## sound, no flash, no colour - presentation subscribes and owns all of that.
## That separation is what lets juice be iterated freely without any risk to
## correctness (§3 forbids presentation vocabulary inside sim/).
##
## This is a BASE class, like SimCommand: systems define typed subclasses
## (CashPickedUp, ActorCaptured, RoundEnded) with their own typed fields. The
## only concrete event core owns is the tick advance below.

## Emitted by SimWorld once per step. Presentation uses it to drive
## interpolation between the two most recent simulation states (§7).
const KIND_TICK_ADVANCED: StringName = &"TickAdvanced"

## Emitted when a command reaches the world with no system willing to handle
## it. Currently every command, because no systems exist yet - but this stays
## useful permanently as the signal for a malformed or stale client command.
const KIND_COMMAND_UNHANDLED: StringName = &"CommandUnhandled"

var kind: StringName = &""
## Tick on which this happened.
var tick: int = 0
## Primary entity concerned, where one applies.
var actor_id: int = SimEntity.NO_ENTITY

func _init(event_kind: StringName = &"", event_tick: int = 0, subject: int = SimEntity.NO_ENTITY) -> void:
	kind = event_kind
	tick = event_tick
	actor_id = subject

static func tick_advanced(world_tick: int) -> SimEvent:
	return SimEvent.new(KIND_TICK_ADVANCED, world_tick)

static func command_unhandled(world_tick: int, command: SimCommand) -> SimEvent:
	return SimEvent.new(KIND_COMMAND_UNHANDLED, world_tick, command.actor_id)

## Canonical text form, folded into the per-tick digest so that two runs
## disagreeing on what HAPPENED are caught, not just two runs disagreeing on
## final state.
func to_digest_string() -> String:
	return "V%s|t%d|a%d" % [kind, tick, actor_id]

func _to_string() -> String:
	return "SimEvent(%s)" % to_digest_string()
