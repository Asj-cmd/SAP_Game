extends SceneTree
## Rule regressions for MovementSystem. See godot/CLAUDE.md - sim/ only, and
## only logic containing a decision: the state-machine transitions, speed
## selection, intent clamping, and containment/sliding.
##
##   godot --headless --path godot --script res://tests/movement_system_test.gd

const TICKS_PER_SECOND: int = 30
const MOVE_SPEED: float = 300.0
const CARRY_SCALE: float = 0.5

var _passed: int = 0
var _failed: int = 0
var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	print("=== MovementSystem rules ===")
	_test_state_machine()
	_test_speed_and_intent()
	_test_containment_and_sliding()
	_test_zone_tracking()

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

func _close(case_name: String, actual: float, expected: float, tolerance: float = 0.001) -> void:
	if absf(actual - expected) <= tolerance:
		_passed += 1
	else:
		_failed += 1
		_failures.append("%s: expected ~%f, got %f" % [case_name, expected, actual])

# ---- world ----

## An L of two rooms, so sliding along a corner is expressible:
##   room_a  x 0..100,  z 0..100
##   room_b  x 100..200, z 0..100
## Everything outside those two boxes is off-map.
func _build_world() -> SimWorld:
	var room_a: ZoneDef = ZoneDef.new()
	room_a.id = &"room_a"
	room_a.role = ZoneDef.Role.NEUTRAL
	room_a.bounds = AABB(Vector3(0, 0, 0), Vector3(100, 100, 100))

	var room_b: ZoneDef = ZoneDef.new()
	room_b.id = &"room_b"
	room_b.role = ZoneDef.Role.NEUTRAL
	room_b.bounds = AABB(Vector3(100, 0, 0), Vector3(100, 100, 100))

	var tuning: TuningDef = TuningDef.new()
	tuning.move_speed = MOVE_SPEED
	tuning.carry_speed_scale = CARRY_SCALE

	var world: SimWorld = SimWorld.new(1)
	world.configure(GameModeDef.new(), tuning, [room_a, room_b], [])
	world.add_system(MovementSystem.new())
	# These suites exercise in-round rules, which only run in the live phase.
	world.match_phase = SimWorld.MatchPhase.PLAYING
	return world

func _add_actor(world: SimWorld, at: Vector3) -> SimEntity:
	var actor: SimEntity = SimEntity.new(SimEntity.NO_ENTITY, SimEntity.Kind.ACTOR)
	actor.position = at
	return world.add_entity(actor)

func _step(world: SimWorld, commands: Array[SimCommand] = []) -> Array[SimEvent]:
	return world.step(commands)

# ---- state machine ----

## Each row: an actor in a given condition, and the state it must end in.
func _test_state_machine() -> void:
	var cases: Array[Dictionary] = [
		{"name": "idle without intent", "intent": Vector3.ZERO,
		 "captured": false, "at": Vector3(50, 50, 50),
		 "expect": SimEntity.MotionState.IDLE},
		{"name": "idle inside the deadzone", "intent": Vector3(0.01, 0, 0),
		 "captured": false, "at": Vector3(50, 50, 50),
		 "expect": SimEntity.MotionState.IDLE},
		{"name": "moving with intent and room to move", "intent": Vector3(1, 0, 0),
		 "captured": false, "at": Vector3(50, 50, 50),
		 "expect": SimEntity.MotionState.MOVING},
		{"name": "blocked pushing off the map", "intent": Vector3(-1, 0, 0),
		 "captured": false, "at": Vector3(0.5, 50, 50),
		 "expect": SimEntity.MotionState.BLOCKED},
		{"name": "held while captured", "intent": Vector3(1, 0, 0),
		 "captured": true, "at": Vector3(50, 50, 50),
		 "expect": SimEntity.MotionState.HELD},
	]

	for case: Dictionary in cases:
		var world: SimWorld = _build_world()
		var actor: SimEntity = _add_actor(world, case["at"])
		actor.is_captured = case["captured"]
		_step(world, [MoveCommand.move(actor.id, case["intent"])])
		_check("state/%s" % case["name"], actor.motion_state, case["expect"])

	# A captured actor does not drift, however hard it pushes.
	var world_held: SimWorld = _build_world()
	var held: SimEntity = _add_actor(world_held, Vector3(50, 50, 50))
	held.is_captured = true
	_step(world_held, [MoveCommand.move(held.id, Vector3(1, 0, 0))])
	_step(world_held)
	_check("state/held actor does not move", held.position, Vector3(50, 50, 50))
	_check("state/held actor has no velocity", held.velocity, Vector3.ZERO)

	# Released, it resumes under intent it never stopped holding.
	held.is_captured = false
	_step(world_held)
	_check("state/resumes moving once released", held.motion_state, SimEntity.MotionState.MOVING)

	# Transitions are announced once, not every tick.
	var world_events: SimWorld = _build_world()
	var walker: SimEntity = _add_actor(world_events, Vector3(50, 50, 50))
	var first: Array[SimEvent] = _step(world_events, [MoveCommand.move(walker.id, Vector3(1, 0, 0))])
	var second: Array[SimEvent] = _step(world_events)
	_check("state/announces the transition", _count(first, MovementEvent.KIND_MOTION_CHANGED), 1)
	_check("state/stays quiet while unchanged", _count(second, MovementEvent.KIND_MOTION_CHANGED), 0)

func _count(events: Array[SimEvent], kind: StringName) -> int:
	var total: int = 0
	for event: SimEvent in events:
		if event.kind == kind:
			total += 1
	return total

# ---- speed and intent ----

func _test_speed_and_intent() -> void:
	var per_tick: float = MOVE_SPEED / float(TICKS_PER_SECOND)

	var world: SimWorld = _build_world()
	var actor: SimEntity = _add_actor(world, Vector3(10, 50, 50))
	_step(world, [MoveCommand.move(actor.id, Vector3(1, 0, 0))])
	_close("speed/one tick at full intent", actor.position.x, 10.0 + per_tick)

	# Half intent, half the distance: analog input is respected.
	var world_half: SimWorld = _build_world()
	var half: SimEntity = _add_actor(world_half, Vector3(10, 50, 50))
	_step(world_half, [MoveCommand.move(half.id, Vector3(0.5, 0, 0))])
	_close("speed/half intent travels half as far", half.position.x, 10.0 + per_tick * 0.5)

	# An over-long vector is clamped, so it buys nothing.
	var world_cheat: SimWorld = _build_world()
	var cheat: SimEntity = _add_actor(world_cheat, Vector3(10, 50, 50))
	_step(world_cheat, [MoveCommand.move(cheat.id, Vector3(50, 0, 0))])
	_close("speed/over-long intent is clamped to unit", cheat.position.x, 10.0 + per_tick)

	# Carrying is slower - the tension of hauling something valuable.
	var world_laden: SimWorld = _build_world()
	var laden: SimEntity = _add_actor(world_laden, Vector3(10, 50, 50))
	var cash: SimEntity = SimEntity.new(SimEntity.NO_ENTITY, SimEntity.Kind.CARRIABLE)
	world_laden.add_entity(cash)
	laden.carrying_id = cash.id
	cash.carried_by = laden.id
	_step(world_laden, [MoveCommand.move(laden.id, Vector3(1, 0, 0))])
	_close("speed/carrying is slower", laden.position.x, 10.0 + per_tick * CARRY_SCALE)

	# Intent persists across ticks: a dropped packet must not stutter an actor.
	var world_persist: SimWorld = _build_world()
	var runner: SimEntity = _add_actor(world_persist, Vector3(10, 50, 50))
	_step(world_persist, [MoveCommand.move(runner.id, Vector3(1, 0, 0))])
	_step(world_persist)
	_close("speed/intent persists without a new command", runner.position.x, 10.0 + per_tick * 2.0)

	# Stopping is an explicit command, not the absence of one.
	_step(world_persist, [MoveCommand.stop(runner.id)])
	_check("speed/explicit stop halts", runner.motion_state, SimEntity.MotionState.IDLE)

# ---- containment and sliding ----

func _test_containment_and_sliding() -> void:
	# Straight into the west wall: no movement at all.
	var world: SimWorld = _build_world()
	var actor: SimEntity = _add_actor(world, Vector3(0.5, 50, 50))
	_step(world, [MoveCommand.move(actor.id, Vector3(-1, 0, 0))])
	_check("contain/cannot leave the map", actor.position, Vector3(0.5, 50, 50))

	# Diagonally into that same wall: the blocked axis is dropped and the free
	# one is kept, so the actor slides along it rather than sticking.
	var world_slide: SimWorld = _build_world()
	var slider: SimEntity = _add_actor(world_slide, Vector3(0.5, 50, 50))
	_step(world_slide, [MoveCommand.move(slider.id, Vector3(-0.7071, 0, 0.7071))])
	_check("slide/keeps the unblocked axis", slider.position.z > 50.0, true)
	_close("slide/drops the blocked axis", slider.position.x, 0.5)
	_check("slide/counts as moving", slider.motion_state, SimEntity.MotionState.MOVING)

	# Adjacent rooms are a single continuous space to walk through.
	var world_cross: SimWorld = _build_world()
	var crosser: SimEntity = _add_actor(world_cross, Vector3(95, 50, 50))
	_step(world_cross, [MoveCommand.move(crosser.id, Vector3(1, 0, 0))])
	_check("contain/walks between adjacent rooms", crosser.position.x > 100.0, true)

# ---- zone tracking ----

func _test_zone_tracking() -> void:
	var world: SimWorld = _build_world()
	var actor: SimEntity = _add_actor(world, Vector3(95, 50, 50))
	_step(world)
	_check("zone/tracks the starting room", actor.zone_id, &"room_a")

	var events: Array[SimEvent] = _step(world, [MoveCommand.move(actor.id, Vector3(1, 0, 0))])
	_check("zone/updates on crossing", actor.zone_id, &"room_b")
	_check("zone/announces the crossing", _count(events, MovementEvent.KIND_ZONE_CHANGED), 1)

	var quiet: Array[SimEvent] = _step(world)
	_check("zone/stays quiet within a room", _count(quiet, MovementEvent.KIND_ZONE_CHANGED), 0)
