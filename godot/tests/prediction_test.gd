extends SceneTree
## Prediction, rollback, and the policy that limits both.
##
##   godot --headless --path godot --script res://tests/prediction_test.gd
##
## The load-bearing cases:
##
##   1. Only movement is predicted. Asserted against EVERY command kind the
##      codec can carry, so a new kind is not silently predictable and moving an
##      outcome into the policy fails the build.
##   2. Rollback restores exactly. A world that adopts another's state must
##      digest identically - "almost restored" is a desync with extra steps.
##   3. At zero latency, prediction changes nothing. This is the invariant the
##      lockstep harness established, and prediction that cannot reproduce it is
##      wrong however good it feels.

const EXPECTED_CHECKS: int = 25

var _passed: int = 0
var _failed: int = 0
var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	print("=== Prediction + rollback ===")
	_test_policy()
	_test_rollback_restores_exactly()
	_test_zero_latency_matches_lockstep()
	_test_outcomes_wait()
	_test_delayed_input_is_not_lost()

	var ran: int = _passed + _failed
	if ran != EXPECTED_CHECKS:
		_failed += 1
		_failures.append("harness: ran %d checks, expected %d - a case was skipped"
			% [ran, EXPECTED_CHECKS])
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

# ---- fixture ----

func _world() -> SimWorld:
	var room: ZoneDef = ZoneDef.new()
	room.id = &"room"
	room.role = ZoneDef.Role.CASH_ROOM
	room.owner_team = &"team_a"
	room.bounds = AABB(Vector3(-500, -500, -500), Vector3(1000, 1000, 1000))

	var team_a: TeamDef = TeamDef.new()
	team_a.id = &"team_a"
	team_a.spawn_points = [Vector3(0, 0, 0)] as Array[Vector3]
	var team_b: TeamDef = TeamDef.new()
	team_b.id = &"team_b"
	team_b.spawn_points = [Vector3(100, 0, 0)] as Array[Vector3]

	var tuning: TuningDef = TuningDef.new()
	tuning.gravity = 0.0
	tuning.actor_radius = 10.0

	var mode: GameModeDef = GameModeDef.new()
	mode.team_size = 1

	var world: SimWorld = SimWorld.new(4242)
	var zones: Array[ZoneDef] = [room]
	var teams: Array[TeamDef] = [team_a, team_b]
	world.configure(mode, tuning, zones, teams, null)
	world.add_system(MovementSystem.new())
	world.add_system(CarrySystem.new())
	world.add_system(CaptureSystem.new())
	world.add_system(ScoringSystem.new())
	world.match_phase = SimWorld.MatchPhase.PLAYING
	world.populate_roster()
	return world

# ---- 1. the policy ----

## Checked against every kind the wire can carry, rather than against a list
## written here - a new command kind must be a deliberate decision to predict,
## not an omission.
func _test_policy() -> void:
	_check("policy/movement is predicted", PredictionPolicy.may_predict(MoveCommand.KIND_MOVE), true)

	# Every outcome, named individually so the failure says which one leaked.
	var outcomes: Array[StringName] = [
		CarryCommand.KIND_PICK_UP, CarryCommand.KIND_DROP,
		CaptureCommand.KIND_CAPTURE, CaptureCommand.KIND_RELEASE,
		MatchCommand.KIND_START_MATCH, MatchCommand.KIND_REMATCH,
	]
	for kind: StringName in outcomes:
		_check("policy/%s waits for the host" % kind, PredictionPolicy.may_predict(kind), false)

	# And nothing the codec can carry escaped the list above.
	var unaccounted: int = 0
	for kind: StringName in CommandCodec.KINDS:
		if kind != MoveCommand.KIND_MOVE and not outcomes.has(kind):
			unaccounted += 1
	_check("policy/every command kind is accounted for", unaccounted, 0)

	# Splitting a batch keeps order and loses nothing.
	var mixed: Array[SimCommand] = [
		MoveCommand.move(1, Vector3.RIGHT, 1),
		CarryCommand.pick_up(1, 2, 1),
		MoveCommand.stop(1, 2),
	]
	_check("policy/the predictable half is movement only",
		PredictionPolicy.predictable(mixed).size(), 2)
	_check("policy/and the rest waits", PredictionPolicy.confirmed_only(mixed).size(), 1)

# ---- 2. rollback ----

func _test_rollback_restores_exactly() -> void:
	var host: SimWorld = _world()
	var guest: SimWorld = _world()
	var actor: int = host.actor_ids()[0]

	for i: int in 20:
		host.step([MoveCommand.move(actor, Vector3(1, 0, 0), host.tick)] as Array[SimCommand])

	# Guest wandered off predicting something else entirely.
	for i: int in 12:
		guest.step([MoveCommand.move(actor, Vector3(0, 0, -1), guest.tick)] as Array[SimCommand])
	_check("rollback/the two disagree first", guest.state_digest() != host.state_digest(), true)

	guest.adopt_state(host)
	_check("rollback/adopting restores the digest exactly",
		guest.state_digest(), host.state_digest())

	# And they stay together: an adopted world must be able to continue, not
	# merely look right for one tick. A shallow copy passes the check above and
	# fails this one.
	for i: int in 10:
		var command: Array[SimCommand] = [
			MoveCommand.move(actor, Vector3(0, 0, 1), host.tick)
		] as Array[SimCommand]
		host.step(command)
		guest.step(command)
	_check("rollback/and keeps agreeing afterwards", guest.state_digest(), host.state_digest())

	# Entities must be copies, not aliases, or the "restored" world tracks the
	# one it was restored from and every comparison passes for the wrong reason.
	guest.get_entity(actor).position = Vector3(999, 0, 0)
	_check("rollback/entities were copied, not aliased",
		host.get_entity(actor).position != Vector3(999, 0, 0), true)

# ---- 3. the invariant ----

## At zero latency a predicting guest must land exactly where the lockstep
## harness said it would. Prediction is allowed to hide latency; it is not
## allowed to change the match.
func _test_zero_latency_matches_lockstep() -> void:
	var host: SimWorld = _world()
	var session: PredictedSession = PredictedSession.create(_world(), _world(), 0)
	var actor: int = host.actor_ids()[0]

	for tick: int in 60:
		var command: SimCommand = session.submit(MoveCommand.move(actor, Vector3(1, 0, 0), 0))
		# Predict locally, then the host applies the very same command and
		# confirms it in the same breath: zero latency.
		session.predict()
		session.confirm([command] as Array[SimCommand])
		host.step([command] as Array[SimCommand])

	_check("zero/confirmed matches the host", session.confirmed.state_digest(), host.state_digest())
	_check("zero/and so does the prediction", session.predicted.state_digest(), host.state_digest())
	_check("zero/with nothing left pending", session.pending_actions().size(), 0)

# ---- 4. outcomes wait ----

## The rule that this whole policy exists for: an outcome must never appear
## locally and then be taken back.
func _test_outcomes_wait() -> void:
	var session: PredictedSession = PredictedSession.create(_world(), _world(), 2)
	var actor: int = session.confirmed.actor_ids()[0]
	var loot: SimEntity = SimEntity.new(SimEntity.NO_ENTITY, SimEntity.Kind.CARRIABLE)
	loot.position = Vector3.ZERO
	session.confirmed.add_entity(loot)
	session.predicted.adopt_state(session.confirmed)

	var grab: SimCommand = session.submit(CarryCommand.pick_up(actor, loot.id, 0))
	for i: int in 4:
		session.predict()

	# Predicted several ticks past the grab, and still not carrying: the local
	# world has not guessed the outcome.
	_check("outcome/a grab is not predicted",
		session.predicted.get_entity(actor).is_carrying(), false)
	_check("outcome/but presentation is told it was asked for",
		session.pending_actions().size(), 1)
	_check("outcome/which is what covers the latency", session.is_awaiting_outcome(), true)

	# The host confirms it. Only now does it become true, and it becomes true in
	# the world outcomes are read from.
	while session.confirmed.tick < grab.issued_tick:
		session.confirm([] as Array[SimCommand])
	session.confirm([grab] as Array[SimCommand])
	_check("outcome/the host's answer is what makes it real",
		session.outcome_state(actor).is_carrying(), true)
	_check("outcome/and nothing is left waiting", session.is_awaiting_outcome(), false)

# ---- 5. input delay ----

## A command is applied during the step FROM its stamped tick, so it is still
## owed when that tick is merely REACHED.
##
## Pruning at the wrong side of that boundary silently drops one tick of input
## per command. Everything looks correct - the confirmed world is authoritative
## and stays right, the prediction re-converges immediately - and the only
## symptom is a misprediction of exactly one tick of travel on a small
## percentage of ticks. It was found by measuring against the host rather than
## by any assertion, which is why the boundary is pinned here now.
func _test_delayed_input_is_not_lost() -> void:
	var session: PredictedSession = PredictedSession.create(_world(), _world(), 3)
	var actor: int = session.confirmed.actor_ids()[0]
	var command: SimCommand = session.submit(MoveCommand.move(actor, Vector3(1, 0, 0), 0))
	_check("delay/the stamp is the local tick plus the delay", command.issued_tick, 3)

	# Confirm up to, but not through, its tick.
	while session.confirmed.tick < command.issued_tick:
		session.confirm([] as Array[SimCommand])
	_check("delay/still owed when its tick is merely reached",
		session.pending().has(command), true)

	# One more, and the host has had its turn.
	session.confirm([] as Array[SimCommand])
	_check("delay/and released once its tick has passed",
		session.pending().has(command), false)
