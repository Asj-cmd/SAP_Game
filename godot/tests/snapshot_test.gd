extends SceneTree
## Snapshot capture, restore, and reconciliation.
##
##   godot --headless --path godot --script res://tests/snapshot_test.gd
##
## The load-bearing case is the DIGEST ROUND TRIP, and it is deliberately not a
## field-by-field comparison. Capture a world, restore it, and the two must
## digest identically - which makes rng.state, _next_entity_id and the intent
## epoch impossible to forget, because they are all in the digest, and which
## keeps holding as state is added: a field the digest covers and the snapshot
## omits fails this suite the day it appears.
##
## Every digest-covered field is set to an UNUSUAL value before capturing.
## Round-tripping a world of defaults proves nothing - an omitted field restores
## as its default and matches by accident, which is exactly the omission worth
## catching.

const EXPECTED_CHECKS: int = 18

var _passed: int = 0
var _failed: int = 0
var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	print("=== World snapshots ===")
	_test_round_trip_is_complete()
	_test_hostile_input()
	_test_reconciliation_uses_the_rollback_path()
	_test_late_join()

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
	room.id = &"vault"
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

	var world: SimWorld = SimWorld.new(9001)
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

## A world where nothing is left at its default, so an omitted field cannot
## restore correctly by coincidence.
func _awkward_world() -> SimWorld:
	var world: SimWorld = _world()
	var actor: SimEntity = world.get_entity(world.actor_ids()[0])
	var other: SimEntity = world.get_entity(world.actor_ids()[1])

	for i: int in 17:
		world.step([MoveCommand.move(actor.id, Vector3(0.3, 0, -0.7), world.tick)] as Array[SimCommand])

	var loot: SimEntity = SimEntity.new(SimEntity.NO_ENTITY, SimEntity.Kind.CARRIABLE)
	loot.position = Vector3(12.5, 0, -3.25)
	loot.origin_position = Vector3(1, 2, 3)
	world.add_entity(loot)
	actor.carrying_id = loot.id
	loot.carried_by = actor.id
	loot.scored_for_team = &"team_b"

	other.is_captured = true
	other.capture_ticks_remaining = 91
	other.captured_on_tick = 4
	other.safe_zone_id = &"vault"
	other.safe_ticks_remaining = SimEntity.SAFE_UNLIMITED
	other.safe_forfeited = true
	other.is_bot = true
	other.slot = 3

	world.round_number = 3
	world.round_wins = {&"team_a": 1, &"team_b": 2}
	world.scores = {&"team_a": 5, &"team_b": 7}
	world.round_winner = &"team_b"
	world.match_winner = &"team_a"
	world.phase_ticks_remaining = 123
	world.invalidate_intent() # moves the intent epoch off zero
	world.rng.next_raw() # and the rng off its seed
	return world

# ---- 1. completeness ----

func _test_round_trip_is_complete() -> void:
	var original: SimWorld = _awkward_world()
	var restored: SimWorld = _world()

	var bytes: PackedByteArray = WorldSnapshot.capture(original)
	_check("round trip/a snapshot is produced", bytes.size() > 0, true)
	_check("round trip/and restores", WorldSnapshot.restore(bytes, restored), true)
	_check("round trip/to an identical digest", restored.state_digest(), original.state_digest())

	# The digest does not cover is_bot, deliberately, so it is checked directly -
	# a joiner still has to learn who is a bot.
	var flagged: int = 0
	for entity_id: int in restored.sorted_entity_ids():
		if restored.entities[entity_id].is_bot:
			flagged += 1
	_check("round trip/and carries the bot labels the digest ignores", flagged, 1)

	# A restored world must be able to CONTINUE, not merely look right once.
	# This is what catches a next-entity-id that was dropped: two worlds agree
	# until something spawns, and then hand out different ids forever.
	var spawned_a: SimEntity = original.add_entity(SimEntity.new())
	var spawned_b: SimEntity = restored.add_entity(SimEntity.new())
	_check("round trip/the next spawn gets the same id", spawned_b.id, spawned_a.id)
	_check("round trip/and the worlds still agree", restored.state_digest(), original.state_digest())

# ---- 2. nothing off the wire is trusted ----

func _test_hostile_input() -> void:
	var target: SimWorld = _world()
	var before: String = target.state_digest()

	_check("hostile/empty input is refused",
		WorldSnapshot.restore(PackedByteArray(), target), false)
	_check("hostile/a wrong format is refused",
		WorldSnapshot.restore(PackedByteArray([99, 0, 0, 0, 0]), target), false)

	var truncated: PackedByteArray = WorldSnapshot.capture(_awkward_world())
	truncated.resize(20)
	_check("hostile/a truncated snapshot is refused",
		WorldSnapshot.restore(truncated, target), false)
	_check("hostile/and none of them was applied", target.state_digest(), before)

# ---- 3. one correction path ----

## A snapshot is a correction, and corrections go through the rollback. What is
## asserted here is the OUTCOME of sharing that path: local input predicted past
## the snapshot's tick survives it, exactly as it survives an ordinary
## confirmation. A separate restore routine would drop it.
func _test_reconciliation_uses_the_rollback_path() -> void:
	var host: SimWorld = _world()
	var session: PredictedSession = PredictedSession.create(_world(), _world(), 2, _world())
	var actor: int = host.actor_ids()[0]

	for i: int in 10:
		host.step([MoveCommand.move(actor, Vector3(1, 0, 0), host.tick)] as Array[SimCommand])

	_check("correction/a snapshot is accepted",
		session.reconcile(WorldSnapshot.capture(host)), true)
	_check("correction/confirmed becomes the host's state",
		session.confirmed.state_digest(), host.state_digest())

	# Local input the host has not answered yet, predicted ahead of it.
	session.submit(MoveCommand.move(actor, Vector3(0, 0, 1), 0))
	for i: int in 4:
		session.predict()
	var predicted_ahead: int = session.predicted.tick

	# A keyframe from a tick the guest has ALREADY predicted past - the ordinary
	# case for a periodic snapshot, and the one where sharing the rollback path
	# matters. Input still owed must survive it; a separate restore routine that
	# simply overwrote the world would silently eat it.
	host.step([] as Array[SimCommand])
	_check("correction/a later keyframe is accepted",
		session.reconcile(WorldSnapshot.capture(host)), true)
	_check("correction/prediction resumes where it had reached",
		session.predicted.tick, predicted_ahead)
	_check("correction/and input still owed survives it", session.pending().size(), 1)

# ---- 4. late join is the same thing ----

## A joiner is a client whose confirmed world happens to be empty. Nothing about
## the path is special, which is the point - reconnect and bot takeover reuse it
## unchanged.
func _test_late_join() -> void:
	var host: SimWorld = _world()
	var actor: int = host.actor_ids()[0]
	for i: int in 40:
		host.step([MoveCommand.move(actor, Vector3(1, 0, 0), host.tick)] as Array[SimCommand])

	# Fresh, at tick zero, having seen nothing at all.
	var joiner: PredictedSession = PredictedSession.create(_world(), _world(), 2, _world())
	_check("join/starts knowing nothing", joiner.confirmed.tick, 0)

	joiner.reconcile(WorldSnapshot.capture(host))
	_check("join/and is immediately up to date",
		joiner.confirmed.state_digest(), host.state_digest())

	# And then follows the ordinary command stream from there.
	for i: int in 10:
		var batch: Array[SimCommand] = [
			MoveCommand.move(actor, Vector3(0, 0, -1), host.tick)
		] as Array[SimCommand]
		host.step(batch)
		joiner.confirm(batch)
	_check("join/then keeps up on commands alone",
		joiner.confirmed.state_digest(), host.state_digest())
