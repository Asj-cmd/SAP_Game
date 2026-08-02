class_name PredictedSession
extends RefCounted
## A guest's view of a match: what the host has confirmed, and what we guess is
## true now. See ARCHITECTURE.md §1.
##
## Two worlds, and the difference between them is the whole design:
##
##   CONFIRMED is authoritative. It is stepped only with command batches the
##   host actually sent, so it is always some ticks behind and always right.
##   Every OUTCOME is read from here - who is carrying, who is jailed, what the
##   score is. Nothing in this world was ever guessed.
##
##   PREDICTED runs ahead by the round trip, stepped with the local player's own
##   movement so their input feels immediate. Only POSITION should ever be read
##   from it (PredictionPolicy).
##
## Rollback is unconditional rather than conditional. Every confirmation throws
## the predicted world away, adopts the confirmed one, and replays the local
## inputs that have not been confirmed yet. Detecting whether a correction was
## needed would cost a comparison and save nothing, and "we thought we were
## right" is exactly the state where a desync hides.
##
## The guest NEVER runs a bot director. Bots are host-side only and their
## commands arrive in the same stream as every other player's, so a guest cannot
## tell a bot from a human and cannot disagree with the host about what one
## decided. See BotCrew.

## Authoritative. Read outcomes from here.
var confirmed: SimWorld = null
## Runs ahead. Read POSITIONS from here, and nothing else.
var predicted: SimWorld = null
## Ticks a local input waits before being applied, from content.
var input_delay: int = 0

## Local commands issued but not yet seen coming back from the host, in issue
## order. Predictable ones are replayed after every rollback; the rest are here
## purely so presentation can show that something was asked for.
var _pending: Array[SimCommand] = []

static func create(
	authoritative: SimWorld,
	local_view: SimWorld,
	delay_ticks: int
) -> PredictedSession:
	var session: PredictedSession = PredictedSession.new()
	session.confirmed = authoritative
	session.predicted = local_view
	session.input_delay = maxi(0, delay_ticks)
	session.predicted.adopt_state(session.confirmed)
	return session

## How far ahead of the host we are guessing.
func lead() -> int:
	return predicted.tick - confirmed.tick

# ---- local input ----

## Stamps a local command with the tick it should apply on and records it.
##
## The stamp is what makes input delay work at both ends: the client predicts it
## at that tick and the host applies it at that tick, so the two agree about the
## client's OWN actions even though they are running at different moments. The
## caller is responsible for sending the returned command to the host.
func submit(command: SimCommand) -> SimCommand:
	command.issued_tick = predicted.tick + input_delay
	_pending.append(command)
	return command

## Advances the predicted world one tick.
##
## `remote` is anything already known about other participants for this tick -
## normally empty, since a guest learns about everyone else only from
## confirmations. Movement only, always: see PredictionPolicy.
func predict(remote: Array[SimCommand] = []) -> void:
	var due: Array[SimCommand] = PredictionPolicy.predictable(_due_at(predicted.tick))
	due.append_array(PredictionPolicy.predictable(remote))
	predicted.step(due)

## Local commands stamped for exactly this tick.
func _due_at(tick: int) -> Array[SimCommand]:
	var due: Array[SimCommand] = []
	for command: SimCommand in _pending:
		if command.issued_tick == tick:
			due.append(command)
	return due

# ---- what the host says ----

## Applies one authoritative tick, then rebuilds the prediction on top of it.
##
## Order matters and is not negotiable: step the truth, forget what was guessed,
## adopt the truth, guess again from there. Anything that tried to patch the
## predicted world in place would be reconciling two states neither of which is
## authoritative.
func confirm(batch: Array[SimCommand]) -> void:
	# Where prediction had reached, remembered BEFORE anything moves.
	#
	# Expressed as a target tick rather than as a lead, because a lead is
	# measured against a confirmed tick that is about to change: computing it
	# first and replaying that many ticks afterwards gains one tick on every
	# confirmation, and the prediction runs away from the host at a steady drift
	# that looks like latency and is not.
	var target: int = maxi(predicted.tick, confirmed.tick + 1)
	confirmed.step(batch)

	# Anything the host has now had its chance to apply is no longer pending -
	# whether it took effect or was refused. A command kept past its tick would
	# be replayed forever.
	#
	# The boundary is >=, not >. A command is applied during the step FROM its
	# stamped tick, so one stamped for the tick just reached has not had its turn
	# yet; dropping it there loses exactly one tick of that input. It showed up
	# as a misprediction of 14.67 units - one tick of travel at full speed - on a
	# couple of percent of ticks, with everything else looking perfectly correct.
	var still_waiting: Array[SimCommand] = []
	for command: SimCommand in _pending:
		if command.issued_tick >= confirmed.tick:
			still_waiting.append(command)
	_pending = still_waiting

	predicted.adopt_state(confirmed)
	while predicted.tick < target:
		predict()

# ---- what presentation is allowed to read ----

## Where a body should be DRAWN. Predicted, so the local player's own movement
## responds immediately.
func view_position(entity_id: int) -> Vector3:
	var entity: SimEntity = predicted.get_entity(entity_id)
	return entity.position if entity != null else Vector3.ZERO

## The state an OUTCOME should be drawn from: carrying, captured, sheltered,
## scores. Confirmed, always.
##
## Separate from view_position on purpose. Reading both off one world is how a
## codebase ends up predicting outcomes by accident - it is one line, it looks
## tidier, and it puts a jailing on screen that may be taken back.
func outcome_state(entity_id: int) -> SimEntity:
	return confirmed.get_entity(entity_id)

## Everything issued locally and not yet answered, predictable or not.
func pending() -> Array[SimCommand]:
	return _pending.duplicate()

## Actions asked for and not yet answered.
##
## This is how the latency on outcomes is covered: presentation starts the reach,
## the grab, the lunge the moment one of these appears, and commits the RESULT
## only when outcome_state says so. The player gets an immediate response to
## their input without anything ever being undone on screen.
func pending_actions() -> Array[SimCommand]:
	return PredictionPolicy.confirmed_only(_pending)

## True while the local player has asked for something the host has not answered.
func is_awaiting_outcome() -> bool:
	return not pending_actions().is_empty()
