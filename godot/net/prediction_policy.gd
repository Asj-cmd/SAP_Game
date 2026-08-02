class_name PredictionPolicy
extends RefCounted
## What a client is allowed to guess at, and what it must wait to be told.
##
## MOVEMENT ONLY. This is a FEEL decision, not a technical one, and it is
## written down here as a policy rather than scattered through the prediction
## code so that it cannot be quietly widened later.
##
## The asymmetry is the whole argument. A mispredicted position is a nudge of a
## few centimetres that corrects within a frame and that nobody notices. A
## mispredicted OUTCOME is a player watching an opponent get seized, jailed, and
## then snap back out again - or watching cash leave their hands and return. That
## is the worst artefact this game can produce, it is far more visible than the
## input latency it would have saved, and it makes the rules look broken rather
## than the network look slow.
##
## So capture, release, pickup, deposit and everything downstream of them wait
## for the host. There is no latency saving available here that is worth what it
## costs to see.
##
## HOW THE LATENCY IS HIDDEN INSTEAD, and this part matters as much as the rule:
## presentation starts the ANIMATION on input and commits the OUTCOME on
## confirmation. The reach begins the instant the button is pressed; whether it
## caught anybody arrives when the host says so. The player sees an immediate
## response to their input either way, and never sees a consequence undone.
## PredictedSession.pending_actions() exists to feed exactly that, and is the
## reason no one should ever need to predict an outcome to make the game feel
## responsive.
##
## tests/prediction_test.gd asserts this list against every command kind the
## codec can carry, so adding a new one does not silently make it predictable
## and moving one into this list fails the build.

## The only kinds a client may apply before the host has confirmed them.
const PREDICTED: Array[StringName] = [
	MoveCommand.KIND_MOVE,
]

static func may_predict(kind: StringName) -> bool:
	return PREDICTED.has(kind)

## The predictable subset of a batch, in the order given.
static func predictable(commands: Array[SimCommand]) -> Array[SimCommand]:
	var kept: Array[SimCommand] = []
	for command: SimCommand in commands:
		if may_predict(command.kind):
			kept.append(command)
	return kept

## The rest: sent to the host, shown as an animation, applied only when it comes
## back confirmed.
static func confirmed_only(commands: Array[SimCommand]) -> Array[SimCommand]:
	var kept: Array[SimCommand] = []
	for command: SimCommand in commands:
		if not may_predict(command.kind):
			kept.append(command)
	return kept
