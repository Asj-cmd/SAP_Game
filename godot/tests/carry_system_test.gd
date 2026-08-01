extends SceneTree
## Rule regressions for CarrySystem, and the safe-room variant it unlocks.
## See godot/CLAUDE.md - sim/ only, table-driven, decisions only.
##
##   godot --headless --path godot --script res://tests/carry_system_test.gd

const EXPECTED_CHECKS: int = 16
const PICKUP_RANGE: float = 40.0

var _passed: int = 0
var _failed: int = 0
var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	print("=== CarrySystem rules ===")
	_test_pickup_conditions()
	_test_drop_and_follow()
	_test_variant_a_is_playable()

	if _passed + _failed != EXPECTED_CHECKS:
		_failed += 1
		_failures.append("harness: ran %d checks, expected %d - a case was skipped"
			% [_passed + _failed, EXPECTED_CHECKS])
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

func _build_world(safe_seconds: float = 0.0, ends_on_pickup: bool = false) -> SimWorld:
	var vault: ZoneDef = ZoneDef.new()
	vault.id = &"vault_b"
	vault.role = ZoneDef.Role.CASH_ROOM
	vault.owner_team = &"team_b"
	vault.bounds = AABB(Vector3(0, 0, 0), Vector3(200, 100, 100))
	vault.safe_duration_seconds = safe_seconds
	vault.safe_ends_on_pickup = ends_on_pickup

	var tuning: TuningDef = TuningDef.new()
	tuning.pickup_range = PICKUP_RANGE
	tuning.capture_range = PICKUP_RANGE
	tuning.actor_radius = 0.0

	var team_b: TeamDef = TeamDef.new()
	team_b.id = &"team_b"
	var team_a: TeamDef = TeamDef.new()
	team_a.id = &"team_a"

	var world: SimWorld = SimWorld.new(1)
	world.configure(GameModeDef.new(), tuning, [vault], [team_a, team_b])
	world.add_system(CarrySystem.new())
	world.add_system(CaptureSystem.new())
	world.match_phase = SimWorld.MatchPhase.PLAYING
	return world

func _add_actor(world: SimWorld, team: StringName, at: Vector3) -> SimEntity:
	var actor: SimEntity = SimEntity.new(SimEntity.NO_ENTITY, SimEntity.Kind.ACTOR)
	actor.team = team
	actor.position = at
	return world.add_entity(actor)

func _add_cash(world: SimWorld, at: Vector3) -> SimEntity:
	var cash: SimEntity = SimEntity.new(SimEntity.NO_ENTITY, SimEntity.Kind.CARRIABLE)
	cash.position = at
	return world.add_entity(cash)

# ---- pickup ----

func _test_pickup_conditions() -> void:
	var cases: Array[Dictionary] = [
		{"name": "picks up what is in reach", "cash_at": Vector3(60, 50, 50), "expect": true},
		{"name": "refuses what is out of reach", "cash_at": Vector3(150, 50, 50), "expect": false},
	]
	for case: Dictionary in cases:
		var world: SimWorld = _build_world()
		var actor: SimEntity = _add_actor(world, &"team_a", Vector3(50, 50, 50))
		var cash: SimEntity = _add_cash(world, case["cash_at"])
		world.step([CarryCommand.pick_up(actor.id, cash.id)])
		_check("carry/%s" % case["name"], actor.is_carrying(), case["expect"])

	# One pair of hands.
	var world_full: SimWorld = _build_world()
	var actor_full: SimEntity = _add_actor(world_full, &"team_a", Vector3(50, 50, 50))
	var first: SimEntity = _add_cash(world_full, Vector3(55, 50, 50))
	var second: SimEntity = _add_cash(world_full, Vector3(60, 50, 50))
	world_full.step([CarryCommand.pick_up(actor_full.id, first.id)])
	world_full.step([CarryCommand.pick_up(actor_full.id, second.id)])
	_check("carry/holds only one thing", actor_full.carrying_id, first.id)
	_check("carry/leaves the other alone", second.is_held(), false)

	# Nobody steals from somebody's hands.
	var thief: SimEntity = _add_actor(world_full, &"team_b", Vector3(50, 50, 50))
	world_full.step([CarryCommand.pick_up(thief.id, first.id)])
	_check("carry/cannot take what is held", thief.is_carrying(), false)

	# A held actor cannot pick anything up.
	var world_held: SimWorld = _build_world()
	var captive: SimEntity = _add_actor(world_held, &"team_a", Vector3(50, 50, 50))
	captive.is_captured = true
	var loose: SimEntity = _add_cash(world_held, Vector3(55, 50, 50))
	world_held.step([CarryCommand.pick_up(captive.id, loose.id)])
	_check("carry/a captured actor cannot pick up", captive.is_carrying(), false)

# ---- drop and follow ----

func _test_drop_and_follow() -> void:
	var world: SimWorld = _build_world()
	var actor: SimEntity = _add_actor(world, &"team_a", Vector3(50, 50, 50))
	var cash: SimEntity = _add_cash(world, Vector3(55, 50, 50))
	var events: Array[SimEvent] = world.step([CarryCommand.pick_up(actor.id, cash.id)])
	_check("carry/announces the pickup", _has(events, CarryEvent.KIND_PICKED_UP), true)

	# Carried things travel with the carrier.
	actor.position = Vector3(120, 50, 50)
	world.step([])
	_check("carry/follows the carrier", cash.position, Vector3(120, 50, 50))

	var dropped: Array[SimEvent] = world.step([CarryCommand.drop(actor.id)])
	_check("carry/drops on command", actor.is_carrying(), false)
	_check("carry/leaves it where the carrier stood", cash.position, Vector3(120, 50, 50))
	_check("carry/announces the drop", _has(dropped, CarryEvent.KIND_DROPPED), true)

	# Dropping empty-handed is simply nothing.
	var quiet: Array[SimEvent] = world.step([CarryCommand.drop(actor.id)])
	_check("carry/dropping nothing does nothing", _has(quiet, CarryEvent.KIND_DROPPED), false)

func _has(events: Array[SimEvent], kind: StringName) -> bool:
	for event: SimEvent in events:
		if event.kind == kind:
			return true
	return false

# ---- the point of the whole system ----

## Variant A is "sheltered indefinitely, until you grab something". Without a
## carry verb there is no way to trigger it, so the variant cannot be played
## and therefore cannot be settled by playing. These two cases are what make
## the grey-box's A/B question answerable at all.
func _test_variant_a_is_playable() -> void:
	# Variant A: no timer, ended only by the grab.
	var world: SimWorld = _build_world(-1.0, true)
	var raider: SimEntity = _add_actor(world, &"team_a", Vector3(50, 50, 50))
	var guard: SimEntity = _add_actor(world, &"team_b", Vector3(60, 50, 50))
	var cash: SimEntity = _add_cash(world, Vector3(55, 50, 50))

	world.step([])
	world.step([CaptureCommand.capture(guard.id, raider.id)])
	_check("variantA/sheltered while empty-handed", raider.is_captured, false)

	world.step([CarryCommand.pick_up(raider.id, cash.id)])
	_check("variantA/the grab happened", raider.is_carrying(), true)
	world.step([CaptureCommand.capture(guard.id, raider.id)])
	_check("variantA/the grab ends the shelter", raider.is_captured, true)

	# Variant B ignores the grab entirely, which is the whole comparison.
	var world_b: SimWorld = _build_world(5.0, false)
	var raider_b: SimEntity = _add_actor(world_b, &"team_a", Vector3(50, 50, 50))
	var guard_b: SimEntity = _add_actor(world_b, &"team_b", Vector3(60, 50, 50))
	var cash_b: SimEntity = _add_cash(world_b, Vector3(55, 50, 50))
	world_b.step([])
	world_b.step([CarryCommand.pick_up(raider_b.id, cash_b.id)])
	world_b.step([CaptureCommand.capture(guard_b.id, raider_b.id)])
	_check("variantB/the grab does not end the shelter", raider_b.is_captured, false)
