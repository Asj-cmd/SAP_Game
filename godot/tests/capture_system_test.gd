extends SceneTree
## Rule regressions for CaptureSystem. See godot/CLAUDE.md - sim/ only, and
## only logic containing a decision: the capture and release conditions, the
## lockup timeout, and the two safe-room conditions.
##
##   godot --headless --path godot --script res://tests/capture_system_test.gd
##
## Table-driven throughout: one runner per rule family, iterating a list of
## cases. Adding a case is a row, not a function.

const TICKS_PER_SECOND: int = 30
const RANGE: float = 50.0
const HOLD_SECONDS: float = 2.0

## Safe-room variants, all reachable by editing a .tres and touching no code.
const VARIANT_NONE: int = 0 # offers no protection
const VARIANT_B: int = 1 # 5s, pickup-independent - what ships
const VARIANT_A: int = 2 # never expires on its own, ends on pickup
const VARIANT_BOTH: int = 3 # 5s AND ends on pickup

var _passed: int = 0
var _failed: int = 0
var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	print("=== CaptureSystem rules ===")
	_test_content_variants_load()
	_test_capture_conditions()
	_test_safe_room_variants()
	_test_release_conditions()
	_test_timeout()

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

# ---- world construction ----

## Six rooms in a row, each 100 wide, so a position's zone is just its x.
##   0..100 home_a | 100..200 corridor | 200..300 cash_a
##   300..400 home_b | 400..500 jail_a | 500..600 jail_b
## jail_a is owned by team_a and therefore holds team_b's prisoners.
func _make_zone(zone_id: StringName, role: ZoneDef.Role, owner: StringName, x: float) -> ZoneDef:
	var zone: ZoneDef = ZoneDef.new()
	zone.id = zone_id
	zone.role = role
	zone.owner_team = owner
	zone.bounds = AABB(Vector3(x, 0.0, 0.0), Vector3(100.0, 100.0, 100.0))
	return zone

func _apply_variant(zone: ZoneDef, variant: int) -> void:
	match variant:
		VARIANT_B:
			zone.safe_duration_seconds = 5.0
			zone.safe_ends_on_pickup = false
		VARIANT_A:
			zone.safe_duration_seconds = -1.0
			zone.safe_ends_on_pickup = true
		VARIANT_BOTH:
			zone.safe_duration_seconds = 5.0
			zone.safe_ends_on_pickup = true
		_:
			zone.safe_duration_seconds = 0.0
			zone.safe_ends_on_pickup = false

func _build_world(cash_variant: int) -> SimWorld:
	var cash: ZoneDef = _make_zone(&"cash_a", ZoneDef.Role.CASH_ROOM, &"team_a", 200.0)
	_apply_variant(cash, cash_variant)

	var zone_defs: Array[ZoneDef] = [
		_make_zone(&"home_a", ZoneDef.Role.HOME, &"team_a", 0.0),
		_make_zone(&"corridor", ZoneDef.Role.NEUTRAL, &"", 100.0),
		cash,
		_make_zone(&"home_b", ZoneDef.Role.HOME, &"team_b", 300.0),
		_make_zone(&"jail_a", ZoneDef.Role.JAIL, &"team_a", 400.0),
		_make_zone(&"jail_b", ZoneDef.Role.JAIL, &"team_b", 500.0),
	]

	var team_a: TeamDef = TeamDef.new()
	team_a.id = &"team_a"
	team_a.home_zone = &"home_a"
	team_a.jail_zone = &"jail_b" # team_a's captured members are held by team_b
	var team_b: TeamDef = TeamDef.new()
	team_b.id = &"team_b"
	team_b.home_zone = &"home_b"
	team_b.jail_zone = &"jail_a"

	var mode: GameModeDef = GameModeDef.new()
	mode.capture_seconds = HOLD_SECONDS
	var tuning: TuningDef = TuningDef.new()
	tuning.capture_range = RANGE
	tuning.rescue_range = RANGE

	var world: SimWorld = SimWorld.new(1)
	world.configure(mode, tuning, zone_defs, [team_a, team_b])
	world.add_system(CaptureSystem.new())
	# These suites exercise in-round rules, which only run in the live phase.
	world.match_phase = SimWorld.MatchPhase.PLAYING
	return world

func _add_actor(world: SimWorld, team: StringName, at: Vector3) -> SimEntity:
	var actor: SimEntity = SimEntity.new(SimEntity.NO_ENTITY, SimEntity.Kind.ACTOR)
	actor.team = team
	actor.position = at
	return world.add_entity(actor)

func _give_carriable(world: SimWorld, holder: SimEntity) -> void:
	var cash: SimEntity = SimEntity.new(SimEntity.NO_ENTITY, SimEntity.Kind.CARRIABLE)
	cash.position = holder.position
	world.add_entity(cash)
	cash.carried_by = holder.id
	holder.carrying_id = cash.id

func _run(world: SimWorld, commands: Array[SimCommand]) -> Array[SimEvent]:
	return world.step(commands)

func _idle(world: SimWorld, ticks: int) -> void:
	var none: Array[SimCommand] = []
	for i: int in ticks:
		world.step(none)

# ---- capture conditions ----

## Each row is one condition from the original handle_lock.
func _test_capture_conditions() -> void:
	var cases: Array[Dictionary] = [
		{"name": "captures intruder on own home ground",
		 "captor": Vector3(50, 50, 50), "target": Vector3(60, 50, 50),
		 "captor_team": &"team_a", "target_team": &"team_b", "expect": true},
		{"name": "rejects when in different zones",
		 "captor": Vector3(95, 50, 50), "target": Vector3(105, 50, 50),
		 "captor_team": &"team_a", "target_team": &"team_b", "expect": false},
		{"name": "rejects beyond capture range",
		 "captor": Vector3(5, 50, 50), "target": Vector3(95, 50, 50),
		 "captor_team": &"team_a", "target_team": &"team_b", "expect": false},
		{"name": "rejects a teammate",
		 "captor": Vector3(50, 50, 50), "target": Vector3(60, 50, 50),
		 "captor_team": &"team_a", "target_team": &"team_a", "expect": false},
		{"name": "rejects on neutral ground",
		 "captor": Vector3(150, 50, 50), "target": Vector3(160, 50, 50),
		 "captor_team": &"team_a", "target_team": &"team_b", "expect": false},
		{"name": "rejects on enemy ground",
		 "captor": Vector3(350, 50, 50), "target": Vector3(360, 50, 50),
		 "captor_team": &"team_a", "target_team": &"team_b", "expect": false},
		# Guards camping the pen would make rescue impossible by design.
		{"name": "rejects inside own jail",
		 "captor": Vector3(450, 50, 50), "target": Vector3(460, 50, 50),
		 "captor_team": &"team_a", "target_team": &"team_b", "expect": false},
	]

	for case: Dictionary in cases:
		var world: SimWorld = _build_world(VARIANT_NONE)
		var captor: SimEntity = _add_actor(world, case["captor_team"], case["captor"])
		var target: SimEntity = _add_actor(world, case["target_team"], case["target"])
		_run(world, [CaptureCommand.capture(captor.id, target.id)])
		_check("capture/%s" % case["name"], target.is_captured, case["expect"])

	# Conditions that need pre-existing capture state.
	var world_a: SimWorld = _build_world(VARIANT_NONE)
	var captor_a: SimEntity = _add_actor(world_a, &"team_a", Vector3(50, 50, 50))
	var target_a: SimEntity = _add_actor(world_a, &"team_b", Vector3(60, 50, 50))
	captor_a.is_captured = true
	_run(world_a, [CaptureCommand.capture(captor_a.id, target_a.id)])
	_check("capture/a held actor cannot capture", target_a.is_captured, false)

	var world_b: SimWorld = _build_world(VARIANT_NONE)
	var captor_b: SimEntity = _add_actor(world_b, &"team_a", Vector3(50, 50, 50))
	var target_b: SimEntity = _add_actor(world_b, &"team_b", Vector3(60, 50, 50))
	_run(world_b, [CaptureCommand.capture(captor_b.id, target_b.id)])
	var jailed_at: Vector3 = target_b.position
	_check("capture/moves target to the holding pen",
		world_b.zone_at(jailed_at).id, &"jail_a")
	_check("capture/sets the lockup clock",
		target_b.capture_ticks_remaining, int(HOLD_SECONDS * TICKS_PER_SECOND))

	# A held actor cannot keep hold of anything.
	var world_c: SimWorld = _build_world(VARIANT_NONE)
	var captor_c: SimEntity = _add_actor(world_c, &"team_a", Vector3(50, 50, 50))
	var target_c: SimEntity = _add_actor(world_c, &"team_b", Vector3(60, 50, 50))
	_give_carriable(world_c, target_c)
	var events: Array[SimEvent] = _run(world_c, [CaptureCommand.capture(captor_c.id, target_c.id)])
	_check("capture/breaks the target's grip", target_c.is_carrying(), false)
	_check("capture/announces the dropped carriable",
		_has_event(events, CaptureEvent.KIND_CARRIABLE_RELEASED), true)

func _has_event(events: Array[SimEvent], kind: StringName) -> bool:
	for event: SimEvent in events:
		if event.kind == kind:
			return true
	return false

# ---- safe rooms ----

## The three shipping-relevant configurations, each purely a content change.
## `wait` is seconds spent in the room before the capture attempt.
func _test_safe_room_variants() -> void:
	var cases: Array[Dictionary] = [
		# Variant B: 5s, pickup-independent. What ships.
		{"name": "B/protected on arrival", "variant": VARIANT_B,
		 "wait": 0.0, "carrying": false, "expect": false},
		{"name": "B/still protected just before expiry", "variant": VARIANT_B,
		 "wait": 4.9, "carrying": false, "expect": false},
		{"name": "B/capturable once the timer runs out", "variant": VARIANT_B,
		 "wait": 5.0, "carrying": false, "expect": true},
		{"name": "B/carrying does not end protection", "variant": VARIANT_B,
		 "wait": 1.0, "carrying": true, "expect": false},
		# Variant A: no timer at all, ended only by the grab.
		{"name": "A/protected indefinitely while empty-handed", "variant": VARIANT_A,
		 "wait": 30.0, "carrying": false, "expect": false},
		{"name": "A/the grab ends protection", "variant": VARIANT_A,
		 "wait": 0.0, "carrying": true, "expect": true},
		# Both conditions live at once: whichever fires first ends it.
		{"name": "both/protected while empty-handed and inside the timer",
		 "variant": VARIANT_BOTH, "wait": 1.0, "carrying": false, "expect": false},
		{"name": "both/the grab ends it early", "variant": VARIANT_BOTH,
		 "wait": 1.0, "carrying": true, "expect": true},
		{"name": "both/the timer ends it when no grab happens",
		 "variant": VARIANT_BOTH, "wait": 5.0, "carrying": false, "expect": true},
		# A room configured with neither condition protects nobody.
		{"name": "none/offers no protection at all", "variant": VARIANT_NONE,
		 "wait": 0.0, "carrying": false, "expect": true},
	]

	for case: Dictionary in cases:
		var world: SimWorld = _build_world(case["variant"])
		# cash_a is owned by team_a, so team_a may capture there; team_b's
		# raider is the one the room protects.
		var captor: SimEntity = _add_actor(world, &"team_a", Vector3(250, 50, 50))
		var target: SimEntity = _add_actor(world, &"team_b", Vector3(260, 50, 50))
		if case["carrying"]:
			_give_carriable(world, target)
		_idle(world, int(round(float(case["wait"]) * TICKS_PER_SECOND)))
		_run(world, [CaptureCommand.capture(captor.id, target.id)])
		_check("safe/%s" % case["name"], target.is_captured, case["expect"])

	# Leaving and returning restarts the grant: a timed room is a repeatable
	# tactic, not a once-per-round consumable.
	var world_r: SimWorld = _build_world(VARIANT_B)
	var captor_r: SimEntity = _add_actor(world_r, &"team_a", Vector3(250, 50, 50))
	var target_r: SimEntity = _add_actor(world_r, &"team_b", Vector3(260, 50, 50))
	_idle(world_r, 5 * TICKS_PER_SECOND) # burn the whole grant
	target_r.position = Vector3(150, 50, 50) # step out to the corridor
	_idle(world_r, 1)
	target_r.position = Vector3(260, 50, 50) # and back in
	_run(world_r, [CaptureCommand.capture(captor_r.id, target_r.id)])
	_check("safe/re-entry restarts protection", target_r.is_captured, false)

# ---- release ----

func _test_release_conditions() -> void:
	var cases: Array[Dictionary] = [
		{"name": "ally in the pen frees the prisoner",
		 "rescuer": Vector3(450, 50, 50), "team": &"team_b",
		 "rescuer_held": false, "target_held": true, "expect": true},
		{"name": "rejects from outside the pen",
		 "rescuer": Vector3(350, 50, 50), "team": &"team_b",
		 "rescuer_held": false, "target_held": true, "expect": false},
		{"name": "rejects an enemy opening the door",
		 "rescuer": Vector3(450, 50, 50), "team": &"team_a",
		 "rescuer_held": false, "target_held": true, "expect": false},
		{"name": "rejects when the target is not held",
		 "rescuer": Vector3(450, 50, 50), "team": &"team_b",
		 "rescuer_held": false, "target_held": false, "expect": false},
		{"name": "a held actor cannot free anyone",
		 "rescuer": Vector3(450, 50, 50), "team": &"team_b",
		 "rescuer_held": true, "target_held": true, "expect": false},
	]

	for case: Dictionary in cases:
		var world: SimWorld = _build_world(VARIANT_NONE)
		var prisoner: SimEntity = _add_actor(world, &"team_b", Vector3(455, 50, 50))
		var rescuer: SimEntity = _add_actor(world, case["team"], case["rescuer"])
		if case["target_held"]:
			prisoner.is_captured = true
			prisoner.capture_ticks_remaining = 999
		if case["rescuer_held"]:
			rescuer.is_captured = true
		_run(world, [CaptureCommand.release(rescuer.id, prisoner.id)])
		var freed: bool = case["target_held"] and not prisoner.is_captured
		_check("release/%s" % case["name"], freed, case["expect"])

	# Out of range, inside the same pen.
	var world_far: SimWorld = _build_world(VARIANT_NONE)
	var prisoner_far: SimEntity = _add_actor(world_far, &"team_b", Vector3(405, 50, 50))
	var rescuer_far: SimEntity = _add_actor(world_far, &"team_b", Vector3(495, 50, 50))
	prisoner_far.is_captured = true
	prisoner_far.capture_ticks_remaining = 999
	_run(world_far, [CaptureCommand.release(rescuer_far.id, prisoner_far.id)])
	_check("release/rejects beyond rescue range", prisoner_far.is_captured, true)

# ---- timeout ----

func _test_timeout() -> void:
	var hold_ticks: int = int(HOLD_SECONDS * TICKS_PER_SECOND)
	var world: SimWorld = _build_world(VARIANT_NONE)
	var captor: SimEntity = _add_actor(world, &"team_a", Vector3(50, 50, 50))
	var target: SimEntity = _add_actor(world, &"team_b", Vector3(60, 50, 50))
	_run(world, [CaptureCommand.capture(captor.id, target.id)])

	_idle(world, hold_ticks - 1)
	_check("timeout/still held one tick short", target.is_captured, true)
	var events: Array[SimEvent] = _run(world, [])
	_check("timeout/released when the clock runs out", target.is_captured, false)
	_check("timeout/announces the release",
		_has_event(events, CaptureEvent.KIND_RELEASED), true)

# ---- content ----

## The shipping .tres must actually parse and carry variant B, since the whole
## point of the two conditions is that a designer can retune them without code.
func _test_content_variants_load() -> void:
	var zone: ZoneDef = load("res://content/zones/cash_room_a.tres") as ZoneDef
	_check("content/cash room loads", zone != null, true)
	if zone == null:
		return
	_check("content/ships variant B duration", zone.safe_duration_seconds, 5.0)
	_check("content/ships variant B pickup rule", zone.safe_ends_on_pickup, false)
	_check("content/is a cash room", zone.role, ZoneDef.Role.CASH_ROOM)
	_check("content/grants safety", zone.grants_safety(), true)
