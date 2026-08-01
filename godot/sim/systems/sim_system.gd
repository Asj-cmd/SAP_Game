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
