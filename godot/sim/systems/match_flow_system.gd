class_name MatchFlowSystem
extends SimSystem
## Rounds, countdowns, and the end of the match. See ARCHITECTURE.md §5.
##
## Runs last (Phase.FLOW), so it decides against a tick that is already
## settled: actors have moved, interactions have resolved, and ScoringSystem
## has recounted. Reading a half-updated score to decide a round would be a
## way to lose a match on a technicality.
##
##   WAITING    -> COUNTDOWN   on StartMatch
##   COUNTDOWN  -> PLAYING     when the pre-round pause elapses
##   PLAYING    -> ROUND_END   on reaching the target, or on time
##   ROUND_END  -> COUNTDOWN   next round
##              -> MATCH_END   when someone has enough rounds
##
## Ported from the round/match flow in autoload/match_state.gd, including its
## draw handling: a tied round is replayed rather than awarded, and does not
## advance the round number.

func phase() -> SimSystem.Phase:
	return SimSystem.Phase.FLOW

## The system that decides when play resumes cannot itself be stopped by play
## being stopped.
func runs_when_paused() -> bool:
	return true

func system_name() -> StringName:
	return &"MatchFlowSystem"

func handles(kind: StringName) -> bool:
	return kind == MatchCommand.KIND_START_MATCH or kind == MatchCommand.KIND_REMATCH

func handle(world: SimWorld, command: SimCommand) -> void:
	match command.kind:
		MatchCommand.KIND_START_MATCH:
			# Only from the lobby. Restarting a running match would be a way to
			# wipe a losing scoreline.
			if world.match_phase == SimWorld.MatchPhase.WAITING:
				_begin_match(world)
		MatchCommand.KIND_REMATCH:
			if world.match_phase == SimWorld.MatchPhase.MATCH_END:
				_begin_match(world)

func step(world: SimWorld) -> void:
	match world.match_phase:
		SimWorld.MatchPhase.COUNTDOWN:
			_tick_countdown(world)
		SimWorld.MatchPhase.PLAYING:
			_tick_playing(world)
		SimWorld.MatchPhase.ROUND_END:
			_tick_round_end(world)
		_:
			pass # WAITING and MATCH_END are both terminal until commanded out.

# ---- transitions ----

func _begin_match(world: SimWorld) -> void:
	world.round_number = 1
	world.round_winner = &""
	world.match_winner = &""
	var wins: Dictionary[StringName, int] = {}
	for team_id: StringName in world.sorted_team_ids():
		wins[team_id] = 0
	world.round_wins = wins
	_start_round(world)

func _start_round(world: SimWorld) -> void:
	world.round_winner = &""
	_reset_entities(world)
	_enter(world, SimWorld.MatchPhase.COUNTDOWN, _ticks(world, _pre_round_seconds(world)))

func _tick_countdown(world: SimWorld) -> void:
	world.phase_ticks_remaining -= 1
	if world.phase_ticks_remaining > 0:
		return
	_enter(world, SimWorld.MatchPhase.PLAYING, _ticks(world, _round_seconds(world)))
	world.emit(MatchEvent.round_started(world.tick, world.round_number))

func _tick_playing(world: SimWorld) -> void:
	# The target is checked before the clock: reaching it on the very tick the
	# round runs out is a win, not a draw.
	var leader: StringName = _team_at_target(world)
	if leader != &"":
		_end_round(world, leader, MatchEvent.REASON_TARGET_REACHED)
		return

	world.phase_ticks_remaining -= 1
	if world.phase_ticks_remaining > 0:
		return
	world.phase_ticks_remaining = 0
	_end_round(world, _team_ahead(world), MatchEvent.REASON_TIME_EXPIRED)

func _tick_round_end(world: SimWorld) -> void:
	world.phase_ticks_remaining -= 1
	if world.phase_ticks_remaining > 0:
		return

	if world.match_winner != &"":
		_enter(world, SimWorld.MatchPhase.MATCH_END, 0)
		world.emit(MatchEvent.match_ended(world.tick, world.match_winner))
		return

	# A drawn round is replayed at the same number: nobody earned it.
	if world.round_winner != &"":
		world.round_number += 1
	_start_round(world)

func _end_round(world: SimWorld, winner: StringName, reason: StringName) -> void:
	world.round_winner = winner
	if winner != &"":
		world.round_wins[winner] = world.round_wins_for(winner) + 1
		if world.round_wins_for(winner) >= _rounds_to_win(world):
			world.match_winner = winner

	world.emit(MatchEvent.round_ended(world.tick, world.round_number, winner, reason))
	_enter(world, SimWorld.MatchPhase.ROUND_END, _ticks(world, _round_end_seconds(world)))

func _enter(world: SimWorld, next: SimWorld.MatchPhase, ticks: int) -> void:
	var previous: SimWorld.MatchPhase = world.match_phase
	world.match_phase = next
	world.phase_ticks_remaining = ticks
	if next != SimWorld.MatchPhase.PLAYING:
		_freeze_actors(world)
	if previous != next:
		world.emit(MatchEvent.phase_changed(world.tick, previous, next))

## Settles actors into a coherent resting state whenever play stops.
##
## MovementSystem is dormant outside PLAYING, so nothing else would clear a
## run cycle that was in progress when the whistle went - presentation reads
## motion_state and would animate the whole roster sprinting on the spot
## through the result screen. Held input is dropped too, so a round does not
## resume into a direction somebody was pressing a phase ago.
func _freeze_actors(world: SimWorld) -> void:
	for entity_id: int in world.sorted_entity_ids():
		var entity: SimEntity = world.entities[entity_id]
		if not entity.is_actor():
			continue
		entity.velocity = Vector3.ZERO
		entity.move_intent = Vector3.ZERO
		entity.motion_state = (
			SimEntity.MotionState.HELD if entity.is_captured
			else SimEntity.MotionState.IDLE
		)

# ---- round conditions ----

## The team holding enough to win outright, or empty.
##
## Ties are impossible to reach here: the target is more than half of all the
## cash in play, so at most one team can be at it.
func _team_at_target(world: SimWorld) -> StringName:
	var target: int = _score_to_win(world)
	if target <= 0:
		return &""
	for team_id: StringName in world.sorted_team_ids():
		if world.score_for(team_id) >= target:
			return team_id
	return &""

## Who is ahead when the clock runs out. Empty on a tie, which is a draw and
## replays the round.
func _team_ahead(world: SimWorld) -> StringName:
	var best: StringName = &""
	var best_score: int = -1
	var tied: bool = false
	for team_id: StringName in world.sorted_team_ids():
		var score: int = world.score_for(team_id)
		if score > best_score:
			best_score = score
			best = team_id
			tied = false
		elif score == best_score:
			tied = true
	return &"" if tied else best

## Puts every entity back where the round starts it.
##
## Positions come from origin_position, stamped when the entity was placed, so
## this needs no knowledge of the content layout - a mode with three teams or
## a house with a different floor plan resets correctly without changing here.
func _reset_entities(world: SimWorld) -> void:
	for entity_id: int in world.sorted_entity_ids():
		var entity: SimEntity = world.entities[entity_id]
		entity.position = entity.origin_position
		entity.velocity = Vector3.ZERO
		entity.zone_id = &""
		if entity.is_actor():
			entity.motion_state = SimEntity.MotionState.IDLE
			entity.move_intent = Vector3.ZERO
			entity.carrying_id = SimEntity.NO_ENTITY
			entity.is_captured = false
			entity.capture_ticks_remaining = 0
			entity.captured_on_tick = -1
			entity.clear_safety()
		else:
			entity.carried_by = SimEntity.NO_ENTITY
			entity.scored_for_team = &""

# ---- content ----

func _rounds_to_win(world: SimWorld) -> int:
	return world.mode.rounds_to_win if world.mode != null else 2

func _score_to_win(world: SimWorld) -> int:
	return world.mode.score_to_win() if world.mode != null else 0

func _round_seconds(world: SimWorld) -> float:
	return world.mode.round_seconds if world.mode != null else 0.0

func _pre_round_seconds(world: SimWorld) -> float:
	return world.mode.pre_round_seconds if world.mode != null else 0.0

func _round_end_seconds(world: SimWorld) -> float:
	return world.mode.round_end_seconds if world.mode != null else 0.0

func _ticks(_world: SimWorld, seconds: float) -> int:
	return maxi(1, SimWorld.seconds_to_ticks(seconds))
