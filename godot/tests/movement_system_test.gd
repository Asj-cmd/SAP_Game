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
	_test_collision_content()
	_test_overlap_recovery()
	_test_kinematic_ground()
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

## The two-room box from WORLD_AUTHORING.md §8: a 200x100x100 shell split by a
## 4-thick wall at x=98..102 with one doorway at z=40..60.
##
## Zones still cover the space, but they no longer decide passability - that is
## the conflation the retired placeholder was built on. Solidity comes from
## WorldCollisionDef alone, so an actor crosses at the doorway and nowhere else.
func _collision(radius_source: TuningDef) -> WorldCollisionDef:
	var collision: WorldCollisionDef = WorldCollisionDef.new()
	collision.bounds = AABB(Vector3(0, 0, 0), Vector3(200, 100, 100))
	collision.blockers = [
		AABB(Vector3(98, 0, 0), Vector3(4, 100, 40)),
		AABB(Vector3(98, 0, 60), Vector3(4, 100, 40)),
	]
	return collision

func _build_world(actor_radius: float = 0.0) -> SimWorld:
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
	tuning.actor_radius = actor_radius
	# Horizontal rules only: gravity is exercised by _test_kinematic_ground.
	tuning.gravity = 0.0

	var world: SimWorld = SimWorld.new(1)
	world.configure(GameModeDef.new(), tuning, [room_a, room_b], [], _collision(tuning))
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

# ---- containment, sliding, and swept traversal ----

func _test_containment_and_sliding() -> void:
	# Straight into the shell: no movement at all.
	var world: SimWorld = _build_world()
	var actor: SimEntity = _add_actor(world, Vector3(0.5, 50, 50))
	_step(world, [MoveCommand.move(actor.id, Vector3(-1, 0, 0))])
	_check("contain/cannot leave the shell", actor.position, Vector3(0.5, 50, 50))

	# Diagonally into that same wall: the blocked axis is dropped and the free
	# one is kept, so the actor slides along it rather than sticking.
	var world_slide: SimWorld = _build_world()
	var slider: SimEntity = _add_actor(world_slide, Vector3(0.5, 50, 50))
	_step(world_slide, [MoveCommand.move(slider.id, Vector3(-0.7071, 0, 0.7071))])
	_check("slide/keeps the unblocked axis", slider.position.z > 50.0, true)
	_close("slide/drops the blocked axis", slider.position.x, 0.5)
	_check("slide/counts as moving", slider.motion_state, SimEntity.MotionState.MOVING)

	# The doorway is passable...
	var world_door: SimWorld = _build_world()
	var doorway: SimEntity = _add_actor(world_door, Vector3(95, 50, 50))
	_step(world_door, [MoveCommand.move(doorway.id, Vector3(1, 0, 0))])
	_check("wall/passes through the doorway", doorway.position.x > 102.0, true)

	# ...and the wall either side of it is not. This case is ALSO the
	# tunnelling test: one tick at MOVE_SPEED covers 10 units against a wall
	# only 4 thick, so the destination lands clear on the far side. An
	# endpoint-only test would wave it straight through; the swept segment
	# test is what stops it (WORLD_AUTHORING.md §4).
	var world_wall: SimWorld = _build_world()
	var walled: SimEntity = _add_actor(world_wall, Vector3(95, 50, 10))
	_step(world_wall, [MoveCommand.move(walled.id, Vector3(1, 0, 0))])
	_check("wall/solid away from the doorway", walled.position, Vector3(95, 50, 10))
	_check("wall/reports blocked", walled.motion_state, SimEntity.MotionState.BLOCKED)

	# The same again at absurd speed, so the step dwarfs the wall entirely.
	var world_fast: SimWorld = _build_world()
	world_fast.tuning.move_speed = MOVE_SPEED * 100.0
	var sprinter: SimEntity = _add_actor(world_fast, Vector3(95, 50, 10))
	_step(world_fast, [MoveCommand.move(sprinter.id, Vector3(1, 0, 0))])
	_check("wall/no tunnelling at any speed", sprinter.position, Vector3(95, 50, 10))

	# A body too wide for the gap does not fit through it.
	var world_fat: SimWorld = _build_world(11.0)
	var fat: SimEntity = _add_actor(world_fat, Vector3(95, 50, 50))
	_step(world_fat, [MoveCommand.move(fat.id, Vector3(1, 0, 0))])
	_check("wall/a 20-wide gap refuses a 22-wide body", fat.position, Vector3(95, 50, 50))

	# ...while a body that does fit still gets through the same gap.
	var world_thin: SimWorld = _build_world(8.0)
	var thin: SimEntity = _add_actor(world_thin, Vector3(95, 50, 50))
	_step(world_thin, [MoveCommand.move(thin.id, Vector3(1, 0, 0))])
	_check("wall/and admits one that fits", thin.position.x > 102.0, true)

## The authored fixture must parse and carry the geometry, since collision is
## content and a designer edits it without touching code.
func _test_collision_content() -> void:
	var collision: WorldCollisionDef = load("res://content/collision/two_room_box.tres") as WorldCollisionDef
	_check("content/two-room box loads", collision != null, true)
	if collision == null:
		return
	_check("content/has both wall segments", collision.blockers.size(), 2)
	_check("content/shell is authored", collision.bounds.size, Vector3(200, 100, 100))
	_check("content/doorway is an absence of blocker",
		collision.blocks_segment(Vector3(95, 50, 50), Vector3(105, 50, 50)), false)
	_check("content/wall is solid",
		collision.blocks_segment(Vector3(95, 50, 10), Vector3(105, 50, 10)), true)

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

# ---- overlap recovery ----

## An actor that ends up INSIDE geometry must always be able to get out.
##
## Blocking every direction while overlapping is the obvious reading of a
## collision test and it is a trap: the escape direction gets blocked along
## with everything else and the actor is stranded for good. Walking cannot
## reach that state today, but knockback and ragdolls exist to shove bodies
## into walls, so the recovery has to be in place before they land.
func _test_overlap_recovery() -> void:
	var collision: WorldCollisionDef = WorldCollisionDef.new()
	collision.bounds = AABB(Vector3(0, 0, 0), Vector3(200, 100, 100))
	# One wall: x 98..102, z 0..40.
	collision.blockers = [AABB(Vector3(98, 0, 0), Vector3(4, 100, 40))]

	# Buried at x=99, so the nearest face is 1 unit away in -x.
	var buried: Vector3 = Vector3(99, 50, 20)
	_check("overlap/detects penetration",
		WorldCollisionDef.penetration_depth(buried, collision.blockers[0]) > 0.0, true)

	_check("overlap/escaping is permitted",
		collision.blocks_segment(buried, Vector3(97, 50, 20)), false)
	_check("overlap/going deeper is refused",
		collision.blocks_segment(buried, Vector3(100, 50, 20)), true)
	_check("overlap/sliding at the same depth is refused",
		collision.blocks_segment(buried, Vector3(99, 50, 30)), true)

	# Flush against the far face: contact, not penetration.
	var flush: Vector3 = Vector3(102, 50, 20)
	_check("overlap/a face touch is not penetration",
		WorldCollisionDef.penetration_depth(flush, collision.blockers[0]), 0.0)
	_check("overlap/sliding along a face is free",
		collision.blocks_segment(flush, Vector3(102, 50, 35)), false)
	_check("overlap/leaving a face is free",
		collision.blocks_segment(flush, Vector3(110, 50, 20)), false)
	_check("overlap/re-entering from a face is refused",
		collision.blocks_segment(flush, Vector3(100, 50, 20)), true)

	# End to end through MovementSystem: an actor placed inside walks free.
	var world: SimWorld = _build_world()
	var stuck: SimEntity = _add_actor(world, Vector3(99, 50, 20))
	_step(world, [MoveCommand.move(stuck.id, Vector3(-1, 0, 0))])
	_check("overlap/an embedded actor can walk out", stuck.position.x < 99.0, true)
	_check("overlap/and is clear of the wall",
		world.collision.blocks_segment(stuck.position, stuck.position), false)

# ---- kinematic ground ----

const GROUND_RADIUS: float = 4.0
const FLOOR_TOP: float = 10.0
const STEP_TOP: float = 15.0

## A floor, a low step an actor walks over, and a wall it cannot.
##   floor  y 0..10   across the whole shell
##   step   y 10..15  at x 100..120
##   wall   y 10..60  at x 150..170
## A resting actor's centre sits radius above whatever it stands on.
func _build_ground_world() -> SimWorld:
	var room: ZoneDef = ZoneDef.new()
	room.id = &"room"
	room.role = ZoneDef.Role.NEUTRAL
	room.bounds = AABB(Vector3(0, 0, 0), Vector3(200, 100, 100))

	var collision: WorldCollisionDef = WorldCollisionDef.new()
	collision.bounds = AABB(Vector3(0, 0, 0), Vector3(200, 100, 100))
	collision.blockers = [
		AABB(Vector3(0, 0, 0), Vector3(200, FLOOR_TOP, 100)),
		AABB(Vector3(100, FLOOR_TOP, 0), Vector3(20, STEP_TOP - FLOOR_TOP, 100)),
		AABB(Vector3(150, FLOOR_TOP, 0), Vector3(20, 50, 100)),
	]

	var tuning: TuningDef = TuningDef.new()
	tuning.move_speed = MOVE_SPEED
	tuning.actor_radius = GROUND_RADIUS
	tuning.gravity = 2000.0
	tuning.step_up_height = 30.0

	var world: SimWorld = SimWorld.new(1)
	world.configure(GameModeDef.new(), tuning, [room], [], collision)
	world.add_system(MovementSystem.new())
	world.match_phase = SimWorld.MatchPhase.PLAYING
	return world

func _test_kinematic_ground() -> void:
	# Dropped from height, an actor falls and comes to rest ON the floor -
	# centre one radius above it, because the body has a half-height.
	var world: SimWorld = _build_ground_world()
	var faller: SimEntity = _add_actor(world, Vector3(50, 80, 50))
	_step(world)
	_check("ground/falls when unsupported", faller.position.y < 80.0, true)
	_check("ground/is airborne while falling", faller.is_grounded, false)

	for i: int in 60:
		_step(world)
	_close("ground/lands on the floor", faller.position.y, FLOOR_TOP + GROUND_RADIUS, 0.5)
	_check("ground/reports grounded", faller.is_grounded, true)
	_check("ground/stops falling", faller.velocity.y, 0.0)

	# And stays there rather than creeping down.
	var rested: float = faller.position.y
	for i: int in 30:
		_step(world)
	_close("ground/does not sink", faller.position.y, rested, 0.001)

	# A low step is walked over without a jump. Two ticks at MOVE_SPEED covers
	# 20 units, which puts the actor squarely on top of the 20-wide sill -
	# walking further would carry it off the far side and back to floor level,
	# which is correct behaviour and simply not what this case is about.
	var world_step: SimWorld = _build_ground_world()
	var climber: SimEntity = _add_actor(world_step, Vector3(90, FLOOR_TOP + GROUND_RADIUS, 50))
	for i: int in 2:
		_step(world_step, [MoveCommand.move(climber.id, Vector3(1, 0, 0))])
	_check("ground/steps over a low sill", climber.position.x > 105.0, true)
	_check("ground/is on top of the sill", climber.position.x < 120.0, true)
	_close("ground/ends up standing on it", climber.position.y, STEP_TOP + GROUND_RADIUS, 0.5)
	_check("ground/is grounded on the sill", climber.is_grounded, true)

	# ...but a wall too tall to step is not.
	var world_wall: SimWorld = _build_ground_world()
	var blocked: SimEntity = _add_actor(world_wall, Vector3(140, FLOOR_TOP + GROUND_RADIUS, 50))
	for i: int in 10:
		_step(world_wall, [MoveCommand.move(blocked.id, Vector3(1, 0, 0))])
	_check("ground/cannot step a full wall", blocked.position.x < 150.0, true)
	_check("ground/reports blocked at the wall", blocked.motion_state, SimEntity.MotionState.BLOCKED)

	# Intent has no vertical component: aiming up does not fly.
	var world_fly: SimWorld = _build_ground_world()
	var flier: SimEntity = _add_actor(world_fly, Vector3(50, FLOOR_TOP + GROUND_RADIUS, 50))
	for i: int in 20:
		_step(world_fly, [MoveCommand.move(flier.id, Vector3(0, 1, 0))])
	_close("ground/cannot fly by aiming up", flier.position.y, FLOOR_TOP + GROUND_RADIUS, 0.5)

	# With no gravity authored, nothing falls and everything counts as standing.
	var world_flat: SimWorld = _build_world()
	var floater: SimEntity = _add_actor(world_flat, Vector3(50, 50, 50))
	_step(world_flat)
	_check("ground/no gravity authored means no falling", floater.position.y, 50.0)
	_check("ground/and nothing reads as airborne", floater.is_grounded, true)
