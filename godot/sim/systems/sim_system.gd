class_name SimSystem
extends RefCounted
## One independent rule module. See ARCHITECTURE.md §5.
##
## Systems communicate only through world state and events - never by calling
## each other. A feature is a new system plus new content, plugged in here,
## rather than an edit inside an existing one.
##
## SimWorld orders systems explicitly and offers each command to whichever
## systems claim its kind. `handles` exists so that routing is declared rather
## than inferred: with `handle` returning void (per §5), the world would
## otherwise have no way to tell a command that was processed from one that
## silently fell through every system.

## When in a tick this system runs.
##
## Execution order is part of the simulation's definition - two machines
## running the same systems in different orders are running different games -
## so it is DECLARED here rather than left to the order someone happened to
## call add_system() in. A caller cannot get the wiring wrong, because the
## caller does not do the ordering.
##
## The sequence is the causal one: actors move, then act on where they ended
## up, then the consequences are counted, then the match decides what that
## means. Judging a capture range against where an actor STARTED the tick
## would be wrong, and this is what makes that unrepresentable rather than
## merely discouraged.
enum Phase {
	MOVEMENT, ## Positions settle.
	INTERACTION, ## Actors act on the world and each other.
	SCORING, ## Consequences are counted.
	FLOW, ## The match reads the count and decides.
}

## Which phase this system belongs to. Every system declares one.
##
## INTERACTION is the default because it is where a rule that acts on the
## world belongs; a system that needs to move things or count them is making a
## deliberate claim and says so.
func phase() -> Phase:
	return Phase.INTERACTION

## Does this system keep running while the match is not live?
##
## Declared for the same reason the phase is: the safe answer is the default,
## so a new system gets correct behaviour from its author doing nothing. The
## alternative - every system remembering an `if not world.is_live(): return`
## guard - fails the moment somebody forgets one, and the symptom is an actor
## creeping during a countdown or a sentence ticking down between rounds.
##
## Overriding to true is a claim that this system does no actor-triggered work
## and must stay correct while play is stopped: the match flow that has to run
## in order to restart play at all, and derived views like scoring, which
## would otherwise leave the board disagreeing with the state it summarises.
func runs_when_paused() -> bool:
	return false

## Does this system act on commands of `kind`?
func handles(_kind: StringName) -> bool:
	return false

## Apply one claimed command. Emit consequences with world.emit().
func handle(_world: SimWorld, _command: SimCommand) -> void:
	pass

## Per-tick update, run after all commands for this tick are handled.
func step(_world: SimWorld) -> void:
	pass

## Human-readable name, for debug output and the system-order dump.
func system_name() -> StringName:
	return &"SimSystem"
