class_name BotTask
extends RefCounted
## One thing a bot might decide to do. A value, not a behaviour.
##
## Tasks carry no logic at all: no conditions, no scoring, no execution. The
## director enumerates them, the scorer ranks them, and the director turns the
## winner into the same commands a player's input produces. Keeping them inert
## is what stops "the bot does X" from ever becoming a branch somewhere.
##
## The kinds are named for INTENT rather than mechanism, and every one of them
## resolves to ordinary commands: DEFEND is a capture, RESCUE is a release, and
## the simulation never learns which of the two a bot thought it was doing.

enum Kind {
	NONE, ## Nothing worth doing.
	STEAL, ## Fetch a carriable that is not already scoring for us.
	DEPOSIT, ## Carry what we hold to a cash room of our own.
	RESCUE, ## Free a team-mate from the pen holding them.
	DEFEND, ## Seize an intruder standing on ground we own.
	PATROL, ## Nothing pressing: go somewhere and look.
}

var kind: Kind = Kind.NONE
## Entity acted upon: the cash, the ally, the intruder. NO_ENTITY for tasks
## about a place rather than a thing.
var target_id: int = SimEntity.NO_ENTITY
var destination: Vector3 = Vector3.ZERO
## Where the task happens, when that is a room rather than a point.
var zone_id: StringName = &""

static func none() -> BotTask:
	return BotTask.new()

static func make(
	task_kind: Kind,
	target: int,
	where: Vector3,
	zone: StringName = &""
) -> BotTask:
	var task: BotTask = BotTask.new()
	task.kind = task_kind
	task.target_id = target
	task.destination = where
	task.zone_id = zone
	return task

func is_none() -> bool:
	return kind == Kind.NONE

## Identity for commitment and for squad coordination.
##
## Two bots heading for the same cash produce the same key, which is what lets
## one of them notice and go elsewhere - with no assignment authority anywhere
## and nothing shared between them but a table of what has been claimed.
func key() -> String:
	return "%d:%d:%s" % [kind, target_id, zone_id]

func matches(other: BotTask) -> bool:
	return other != null and key() == other.key()
