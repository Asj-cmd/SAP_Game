extends SceneTree
## Rule regressions for ScoringSystem and MatchFlowSystem. See godot/CLAUDE.md
## - sim/ only, and only logic containing a decision: derived score, win
## detection, phase transitions, draw handling, round reset.
##
##   godot --headless --path godot --script res://tests/scoring_flow_test.gd

const TICKS_PER_SECOND: int = 30
const CASH_PER_TEAM: int = 3
const PRE_ROUND: float = 1.0
const ROUND_SECONDS: float = 2.0
const ROUND_END: float = 1.0
const ROUNDS_TO_WIN: int = 2

var _passed: int = 0
var _failed: int = 0
var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	print("=== Scoring + MatchFlow rules ===")
	_test_system_ordering()
	_test_derived_score()
	_test_phase_transitions()
	_test_round_outcomes()
	_test_round_reset()
	_test_full_match()
	_test_dormancy()

	print("\n%d passed, %d failed" % [_passed, _failed])
	if _failed > 0:
		print("\nFAILURES:")
		for failure: String in _failures:
			print("  - %s" % failure)
	quit(1 if _failed > 0 else 0)

func _check(case_name: String, actual: Variant, expected: Variant) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		_failures.append("%s: expected %s, got %s" % [case_name, expected, actual])

# ---- world ----

## Two vaults and a neutral middle:
##   vault_a  x 0..100    CASH_ROOM team_a
##   middle   x 100..200  NEUTRAL
##   vault_b  x 200..300  CASH_ROOM team_b
func _build_world() -> SimWorld:
	var vault_a: ZoneDef = ZoneDef.new()
	vault_a.id = &"vault_a"
	vault_a.role = ZoneDef.Role.CASH_ROOM
	vault_a.owner_team = &"team_a"
	vault_a.bounds = AABB(Vector3(0, 0, 0), Vector3(100, 100, 100))

	var middle: ZoneDef = ZoneDef.new()
	middle.id = &"middle"
	middle.role = ZoneDef.Role.NEUTRAL
	middle.bounds = AABB(Vector3(100, 0, 0), Vector3(100, 100, 100))

	var vault_b: ZoneDef = ZoneDef.new()
	vault_b.id = &"vault_b"
	vault_b.role = ZoneDef.Role.CASH_ROOM
	vault_b.owner_team = &"team_b"
	vault_b.bounds = AABB(Vector3(200, 0, 0), Vector3(100, 100, 100))

	var team_a: TeamDef = TeamDef.new()
	team_a.id = &"team_a"
	var team_b: TeamDef = TeamDef.new()
	team_b.id = &"team_b"

	var mode: GameModeDef = GameModeDef.new()
	mode.cash_per_team = CASH_PER_TEAM
	mode.rounds_to_win = ROUNDS_TO_WIN
	mode.pre_round_seconds = PRE_ROUND
	mode.round_seconds = ROUND_SECONDS
	mode.round_end_seconds = ROUND_END

	var world: SimWorld = SimWorld.new(1)
	world.configure(mode, TuningDef.new(), [vault_a, middle, vault_b], [team_a, team_b])
	world.add_system(ScoringSystem.new())
	world.add_system(MatchFlowSystem.new())
	return world

## Cash starts in its owner's vault, three a side.
func _stock_vaults(world: SimWorld) -> void:
	for i: int in CASH_PER_TEAM:
		_add_cash(world, Vector3(10.0 + i * 10.0, 50, 50))
		_add_cash(world, Vector3(210.0 + i * 10.0, 50, 50))

func _add_cash(world: SimWorld, at: Vector3) -> SimEntity:
	var cash: SimEntity = SimEntity.new(SimEntity.NO_ENTITY, SimEntity.Kind.CARRIABLE)
	cash.position = at
	cash.origin_position = at
	return world.add_entity(cash)

func _step(world: SimWorld, commands: Array[SimCommand] = []) -> Array[SimEvent]:
	return world.step(commands)

func _run(world: SimWorld, ticks: int) -> Array[SimEvent]:
	var seen: Array[SimEvent] = []
	for i: int in ticks:
		seen.append_array(world.step([]))
	return seen

## Advances to the live phase of the current round.
##
## The start command is not optional: WAITING is terminal by design, so a
## world that is merely stepped never begins. Leaving it out silently parks
## every later assertion in WAITING, where scoring still runs and only the
## flow rules look broken.
func _reach_play(world: SimWorld) -> void:
	if world.match_phase == SimWorld.MatchPhase.WAITING:
		_step(world, [MatchCommand.start()])
	var guard: int = 0
	while world.match_phase != SimWorld.MatchPhase.PLAYING and guard < 1000:
		_step(world)
		guard += 1

func _count(events: Array[SimEvent], kind: StringName) -> int:
	var total: int = 0
	for event: SimEvent in events:
		if event.kind == kind:
			total += 1
	return total

# ---- system ordering ----

## Order comes from declared phase, never from registration order.
func _test_system_ordering() -> void:
	var world: SimWorld = SimWorld.new(1)
	world.configure(GameModeDef.new(), TuningDef.new(), [], [])
	# Registered deliberately backwards.
	world.add_system(MatchFlowSystem.new())
	world.add_system(ScoringSystem.new())
	world.add_system(CaptureSystem.new())
	world.add_system(MovementSystem.new())

	var order: Array[StringName] = []
	for system: SimSystem in world.systems:
		order.append(system.system_name())
	_check("order/sorts by declared phase regardless of registration order",
		order, [&"MovementSystem", &"CaptureSystem", &"ScoringSystem", &"MatchFlowSystem"])

# ---- derived score ----

func _test_derived_score() -> void:
	var world: SimWorld = _build_world()
	_stock_vaults(world)
	_reach_play(world)

	_check("score/starts level", world.score_for(&"team_a"), CASH_PER_TEAM)
	_check("score/counts both vaults", world.score_for(&"team_b"), CASH_PER_TEAM)

	# Lifting cash drops the victim's score on the same tick, with no
	# bookkeeping: the count follows the carriable.
	var stolen: SimEntity = null
	for entity_id: int in world.sorted_entity_ids():
		var entity: SimEntity = world.entities[entity_id]
		if entity.is_carriable() and entity.position.x > 200.0:
			stolen = entity
			break
	stolen.carried_by = 999
	var events: Array[SimEvent] = _step(world)
	_check("score/robbed the instant it is lifted", world.score_for(&"team_b"), CASH_PER_TEAM - 1)
	_check("score/announces the change", _count(events, ScoringEvent.KIND_SCORE_CHANGED), 1)

	# In transit it counts for nobody.
	stolen.position = Vector3(150, 50, 50)
	_step(world)
	_check("score/in transit counts for nobody", world.score_for(&"team_a"), CASH_PER_TEAM)

	# Dropped in the raider's own vault, it counts for them - a deposit is a
	# position, not an event.
	stolen.carried_by = SimEntity.NO_ENTITY
	stolen.position = Vector3(50, 50, 50)
	_step(world)
	_check("score/banked by position alone", world.score_for(&"team_a"), CASH_PER_TEAM + 1)
	_check("score/victim stays down", world.score_for(&"team_b"), CASH_PER_TEAM - 1)

	# Left on neutral ground it counts for nobody at all.
	stolen.position = Vector3(150, 50, 50)
	_step(world)
	_check("score/neutral ground scores for nobody", world.score_for(&"team_a"), CASH_PER_TEAM)

# ---- phases ----

func _test_phase_transitions() -> void:
	var world: SimWorld = _build_world()
	_stock_vaults(world)

	_check("phase/starts waiting", world.match_phase, SimWorld.MatchPhase.WAITING)

	_step(world)
	_check("phase/waiting needs a command", world.match_phase, SimWorld.MatchPhase.WAITING)

	_step(world, [MatchCommand.start()])
	_check("phase/start opens the countdown", world.match_phase, SimWorld.MatchPhase.COUNTDOWN)

	# Actions are refused until the countdown elapses.
	_check("phase/countdown is not live", world.is_live(), false)

	var events: Array[SimEvent] = _run(world, int(PRE_ROUND * TICKS_PER_SECOND))
	_check("phase/countdown reaches play", world.match_phase, SimWorld.MatchPhase.PLAYING)
	_check("phase/announces the round", _count(events, MatchEvent.KIND_ROUND_STARTED), 1)
	_check("phase/play is live", world.is_live(), true)

	# A second start cannot rewind a running match.
	_step(world, [MatchCommand.start()])
	_check("phase/start is refused mid-match", world.match_phase, SimWorld.MatchPhase.PLAYING)

# ---- round outcomes ----

func _test_round_outcomes() -> void:
	# Reaching the target ends the round immediately.
	var world: SimWorld = _build_world()
	_stock_vaults(world)
	_reach_play(world)
	# score_to_win is 2N-1 = 5; move three of team_b's into team_a's vault.
	var moved: int = 0
	for entity_id: int in world.sorted_entity_ids():
		var entity: SimEntity = world.entities[entity_id]
		if entity.is_carriable() and entity.position.x > 200.0 and moved < 2:
			entity.position = Vector3(50, 50, 50)
			moved += 1
	var events: Array[SimEvent] = _step(world)
	_check("round/target ends the round", world.match_phase, SimWorld.MatchPhase.ROUND_END)
	_check("round/awards the winner", world.round_winner, &"team_a")
	_check("round/announces the end", _count(events, MatchEvent.KIND_ROUND_ENDED), 1)
	_check("round/credits a round win", world.round_wins_for(&"team_a"), 1)

	# Ahead on the clock wins on time.
	var world_clock: SimWorld = _build_world()
	_stock_vaults(world_clock)
	_reach_play(world_clock)
	for entity_id: int in world_clock.sorted_entity_ids():
		var entity: SimEntity = world_clock.entities[entity_id]
		if entity.is_carriable() and entity.position.x > 200.0:
			entity.position = Vector3(50, 50, 50)
			break
	_run(world_clock, int(ROUND_SECONDS * TICKS_PER_SECOND) + 1)
	_check("round/leader wins on time", world_clock.round_winner, &"team_a")

	# Level on the clock is a draw, replayed at the same number.
	var world_draw: SimWorld = _build_world()
	_stock_vaults(world_draw)
	_reach_play(world_draw)
	var round_before: int = world_draw.round_number
	_run(world_draw, int(ROUND_SECONDS * TICKS_PER_SECOND) + 1)
	_check("round/level scores draw", world_draw.round_winner, &"")
	_check("round/draw credits nobody", world_draw.round_wins_for(&"team_a"), 0)
	_run(world_draw, int(ROUND_END * TICKS_PER_SECOND) + 1)
	_check("round/draw replays the same round", world_draw.round_number, round_before)

# ---- round reset ----

func _test_round_reset() -> void:
	var world: SimWorld = _build_world()
	_stock_vaults(world)
	var actor: SimEntity = SimEntity.new(SimEntity.NO_ENTITY, SimEntity.Kind.ACTOR)
	actor.team = &"team_a"
	actor.position = Vector3(50, 50, 50)
	actor.origin_position = Vector3(50, 50, 50)
	world.add_entity(actor)
	_reach_play(world)

	# Disturb everything a round can disturb.
	actor.position = Vector3(250, 50, 50)
	actor.is_captured = true
	actor.capture_ticks_remaining = 99
	var cash: SimEntity = null
	for entity_id: int in world.sorted_entity_ids():
		var entity: SimEntity = world.entities[entity_id]
		if entity.is_carriable():
			cash = entity
			break
	var cash_origin: Vector3 = cash.origin_position
	cash.position = Vector3(150, 50, 50)
	cash.carried_by = actor.id

	# End the round on the clock, then run through the interval.
	_run(world, int(ROUND_SECONDS * TICKS_PER_SECOND) + 1)
	_run(world, int(ROUND_END * TICKS_PER_SECOND) + 1)

	_check("reset/actor returns to spawn", actor.position, Vector3(50, 50, 50))
	_check("reset/actor is freed", actor.is_captured, false)
	_check("reset/cash returns home", cash.position, cash_origin)
	_check("reset/cash is dropped", cash.carried_by, SimEntity.NO_ENTITY)
	_check("reset/scores back to level", world.score_for(&"team_a"), CASH_PER_TEAM)

# ---- whole match ----

## Best-of-N terminates, and terminates on the right team.
func _test_full_match() -> void:
	var world: SimWorld = _build_world()
	_stock_vaults(world)
	_step(world, [MatchCommand.start()])

	var guard: int = 0
	var match_ended: int = 0
	while world.match_phase != SimWorld.MatchPhase.MATCH_END and guard < 5000:
		# Team A takes every round by hauling two bundles across on sight.
		if world.is_live():
			var moved: int = 0
			for entity_id: int in world.sorted_entity_ids():
				var entity: SimEntity = world.entities[entity_id]
				if entity.is_carriable() and entity.position.x > 200.0 and moved < 2:
					entity.position = Vector3(50, 50, 50)
					moved += 1
		match_ended += _count(world.step([]), MatchEvent.KIND_MATCH_ENDED)
		guard += 1

	_check("match/terminates", world.match_phase, SimWorld.MatchPhase.MATCH_END)
	_check("match/crowns the winner", world.match_winner, &"team_a")
	_check("match/took the required rounds", world.round_wins_for(&"team_a"), ROUNDS_TO_WIN)
	_check("match/announces the end once", match_ended, 1)
	_check("match/is not live once over", world.is_live(), false)

# ---- dormancy ----

## Systems declare whether they run while play is stopped, and SimWorld
## enforces it. These cases are about that enforcement, not about any one
## system remembering a guard.
func _test_dormancy() -> void:
	var world: SimWorld = _build_world()
	world.add_system(MovementSystem.new())
	var actor: SimEntity = SimEntity.new(SimEntity.NO_ENTITY, SimEntity.Kind.ACTOR)
	actor.team = &"team_a"
	actor.position = Vector3(50, 50, 50)
	actor.origin_position = Vector3(50, 50, 50)
	world.add_entity(actor)
	_stock_vaults(world)

	# Countdown: recognised, but its system is asleep.
	_step(world, [MatchCommand.start()])
	var paused: Array[SimEvent] = _step(world, [MoveCommand.move(actor.id, Vector3(1, 0, 0))])
	_check("dormant/no movement during the countdown", actor.position, Vector3(50, 50, 50))
	_check("dormant/reported as paused, not unhandled",
		_count(paused, SimEvent.KIND_COMMAND_IGNORED_PAUSED), 1)
	_check("dormant/not reported as unhandled",
		_count(paused, SimEvent.KIND_COMMAND_UNHANDLED), 0)

	# A kind nobody claims stays a genuine unhandled report - the distinction
	# exists so this signal is not buried under a countdown of the above.
	var junk: Array[SimEvent] = _step(world, [SimCommand.new(&"NoSuchCommand")])
	_check("dormant/unknown kinds still report unhandled",
		_count(junk, SimEvent.KIND_COMMAND_UNHANDLED), 1)
	_check("dormant/unknown kinds are not called paused",
		_count(junk, SimEvent.KIND_COMMAND_IGNORED_PAUSED), 0)

	# Scoring is a derived view and keeps running, so the board never
	# disagrees with the state it summarises.
	_check("dormant/scoring runs while paused", world.score_for(&"team_a"), CASH_PER_TEAM)

	# Once live, the same command is obeyed.
	_reach_play(world)
	_step(world, [MoveCommand.move(actor.id, Vector3(1, 0, 0))])
	_check("dormant/movement resumes when live", actor.position.x > 50.0, true)

	# The whistle leaves nobody stuck in a run cycle: movement is dormant from
	# here, so flow settles actors itself.
	_run(world, int(ROUND_SECONDS * TICKS_PER_SECOND) + 1)
	_check("dormant/actors settle when play stops", actor.motion_state, SimEntity.MotionState.IDLE)
	_check("dormant/held input is dropped", actor.move_intent, Vector3.ZERO)
