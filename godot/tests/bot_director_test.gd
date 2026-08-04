extends SceneTree
## Rule regressions for BotDirector and BotCrew. See godot/CLAUDE.md.
##
##   godot --headless --path godot --script res://tests/bot_director_test.gd
##
## Three properties are load-bearing and everything else here is ordinary:
##
##   1. Bots are REMOVABLE WITHOUT TRACE. A match with none must be
##      indistinguishable from one where they were never written. Proved by
##      digest equality, and by a scan asserting no rule mentions is_bot.
##   2. Behaviour is CONTENT. Two profiles must produce two different bots from
##      the same code and the same situation.
##   3. Filling a lobby is FAIR. A bot may never be the reason one side is
##      bigger, and declining to add one is a legitimate outcome.

const EXPECTED_CHECKS: int = 26

const RADIUS: float = 10.0
const FLOOR_TOP: float = 10.0

var _passed: int = 0
var _failed: int = 0
var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	print("=== BotDirector + BotCrew ===")
	_test_removability()
	_test_symmetric_fill()
	_test_profile_drives_choice()
	_test_decisions()
	_test_takeover()
	_test_intent_survives_a_countdown()

	# Counted BEFORE the guard's own failure is added, or a suite that skipped a
	# case reports the total it was supposed to reach and reads as a paradox.
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

## An open hall with a cash room at each end, plus any extra walls a case wants.
func _world(team_size: int = 1, extra: Array[AABB] = []) -> SimWorld:
	var collision: WorldCollisionDef = WorldCollisionDef.new()
	collision.is_fixture = true # a rig, not a level
	collision.bounds = AABB(Vector3(0, 0, 0), Vector3(400, 100, 200))
	var blockers: Array[AABB] = [AABB(Vector3(0, 0, 0), Vector3(400, FLOOR_TOP, 200))]
	blockers.append_array(extra)
	collision.blockers = blockers

	var vault_a: ZoneDef = _zone(&"vault_a", ZoneDef.Role.CASH_ROOM, &"team_a",
		AABB(Vector3(0, 0, 0), Vector3(100, 100, 200)))
	var yard: ZoneDef = _zone(&"yard", ZoneDef.Role.HOME, &"team_a",
		AABB(Vector3(100, 0, 0), Vector3(200, 100, 200)))
	var vault_b: ZoneDef = _zone(&"vault_b", ZoneDef.Role.CASH_ROOM, &"team_b",
		AABB(Vector3(300, 0, 0), Vector3(100, 100, 200)))

	var team_a: TeamDef = TeamDef.new()
	team_a.id = &"team_a"
	team_a.home_zone = &"vault_a"
	team_a.spawn_points = _spawns(50.0)
	var team_b: TeamDef = TeamDef.new()
	team_b.id = &"team_b"
	team_b.home_zone = &"vault_b"
	team_b.spawn_points = _spawns(350.0)

	var tuning: TuningDef = TuningDef.new()
	tuning.actor_radius = RADIUS
	tuning.step_up_height = 30.0
	tuning.gravity = 0.0

	var mode: GameModeDef = GameModeDef.new()
	mode.team_size = team_size

	var zones: Array[ZoneDef] = [vault_a, yard, vault_b]
	var teams: Array[TeamDef] = [team_a, team_b]
	var world: SimWorld = SimWorld.new(20260802)
	if not world.configure(mode, tuning, zones, teams, collision):
		_failed += 1
		_failures.append("fixture: world refused its content - %s"
			% ", ".join(world.content_failures))
	world.add_system(MovementSystem.new())
	world.match_phase = SimWorld.MatchPhase.PLAYING
	world.populate_roster()
	return world

func _zone(id: StringName, role: ZoneDef.Role, owner: StringName, bounds: AABB) -> ZoneDef:
	var zone: ZoneDef = ZoneDef.new()
	zone.id = id
	zone.role = role
	zone.owner_team = owner
	zone.bounds = bounds
	return zone

func _spawns(x: float) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for slot: int in 3:
		points.append(Vector3(x, FLOOR_TOP + RADIUS, 40.0 + 40.0 * float(slot)))
	return points

func _profile() -> BotProfileDef:
	var profile: BotProfileDef = BotProfileDef.new()
	# No hesitation, so a case can read a decision on the tick it is made rather
	# than stepping the world far enough for the reaction delay to elapse.
	profile.reaction_delay_seconds = 0.0
	profile.choice_noise = 0.0
	profile.steer_wobble = 0.0
	return profile

func _crew(world: SimWorld) -> BotCrew:
	return BotCrew.create(_profile(), NavGraph.of(world.surface), 99)

# ---- 1. removable without trace ----

func _test_removability() -> void:
	# The whole claim, stated as an equality: a world driven by an empty crew is
	# byte-identical to one that never heard of BotCrew.
	var bare: SimWorld = _world()
	for i: int in 30:
		bare.step([])

	var crewed: SimWorld = _world()
	var empty: BotCrew = _crew(crewed)
	for i: int in 30:
		crewed.step(empty.drain(crewed, crewed.tick))
	_check("removable/an empty crew changes nothing", crewed.state_digest(), bare.state_digest())
	_check("removable/and really is empty", empty.is_empty(), true)

	# Teeth. If a filled crew also produced an identical digest, the check above
	# would be measuring nothing.
	var driven: SimWorld = _world()
	var manned: BotCrew = _crew(driven)
	manned.fill_lobby(driven, [], 2)
	for i: int in 30:
		driven.step(manned.drain(driven, driven.tick))
	_check("removable/while a bot present does change it",
		driven.state_digest() != bare.state_digest(), true)

	# is_bot is a label, not state. Its absence from the digest is what lets a
	# takeover happen mid-match without a desync.
	var labelled: SimWorld = _world()
	var before: String = labelled.state_digest()
	for actor_id: int in labelled.actor_ids():
		labelled.get_entity(actor_id).is_bot = true
	_check("removable/is_bot is invisible to the digest", labelled.state_digest(), before)

	# Constructing a director must not draw from the world's stream. fork()
	# would have, and every roll in the match after it would shift.
	var untouched: SimWorld = _world()
	var rng_before: int = untouched.rng.state
	BotDirector.for_actor(untouched.actor_ids()[0], _profile(), NavGraph.of(untouched.surface), 7)
	_check("removable/a director does not disturb the world rng",
		untouched.rng.state, rng_before)

	_check("removable/no rule branches on is_bot", _rules_mentioning_is_bot(), PackedStringArray())

## Scans every rule module for the flag. Automated because the guarantee is
## exactly the kind that decays quietly: one `if actor.is_bot` inside a system
## would give bots a privilege, and nothing else in this suite would notice.
func _rules_mentioning_is_bot() -> PackedStringArray:
	var offenders: PackedStringArray = PackedStringArray()
	for directory: String in ["res://sim/systems", "res://sim/core", "res://content"]:
		for path: String in _scripts_under(directory):
			# sim_entity.gd declares the field and copies it; that is the
			# storage, not a decision made on it.
			if path.ends_with("sim_entity.gd"):
				continue
			var text: String = FileAccess.get_file_as_string(path)
			if text.contains("is_bot"):
				offenders.append(path)
	return offenders

func _scripts_under(directory: String) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	for entry: String in DirAccess.get_files_at(directory):
		if entry.ends_with(".gd"):
			found.append("%s/%s" % [directory, entry])
	for entry: String in DirAccess.get_directories_at(directory):
		found.append_array(_scripts_under("%s/%s" % [directory, entry]))
	return found

# ---- 2. filling a lobby fairly ----

## Each row: how many humans sit on each team, how many bots are allowed, and
## the occupancy every team must end up with. -1 means no bots may be placed.
func _test_symmetric_fill() -> void:
	var cases: Array[Dictionary] = [
		{"name": "an empty lobby fills both sides", "humans": [0, 0], "budget": 4, "each": 2},
		{"name": "one human is matched three ways", "humans": [1, 0], "budget": 3, "each": 2},
		{"name": "a lopsided lobby is levelled up", "humans": [2, 1], "budget": 1, "each": 2},
		# The case worth having. Two humans on one side, none on the other, and
		# only one bot: filling greedily gives 2v1. Declining is correct.
		{"name": "too few bots to level up places none", "humans": [2, 0], "budget": 1, "each": -1},
	]

	for case: Dictionary in cases:
		var world: SimWorld = _world(2)
		var humans: Array[int] = _seat_humans(world, case["humans"])
		var crew: BotCrew = _crew(world)
		var added: Array[int] = crew.fill_lobby(world, humans, case["budget"])

		var expected: int = case["each"]
		if expected < 0:
			_check("fill/%s" % case["name"], added.size(), 0)
			_check("fill/%s says why" % case["name"], crew.declined_reason != "", true)
			continue

		var per_team: Dictionary[StringName, int] = {}
		for team_id: StringName in world.sorted_team_ids():
			per_team[team_id] = 0
		for actor_id: int in humans + added:
			var team: StringName = world.get_entity(actor_id).team
			per_team[team] = per_team[team] + 1

		var even: bool = true
		for team_id: StringName in per_team:
			if per_team[team_id] != expected:
				even = false
		_check("fill/%s" % case["name"], even, true)
		_check("fill/%s stays within budget" % case["name"], added.size() <= case["budget"], true)

## Seats `counts[i]` humans on the i-th team, in sorted team order.
func _seat_humans(world: SimWorld, counts: Array) -> Array[int]:
	var humans: Array[int] = []
	var team_ids: Array[StringName] = world.sorted_team_ids()
	for i: int in team_ids.size():
		var wanted: int = counts[i]
		for actor_id: int in world.actor_ids():
			if wanted <= 0:
				break
			if world.get_entity(actor_id).team != team_ids[i] or humans.has(actor_id):
				continue
			humans.append(actor_id)
			wanted -= 1
	return humans

# ---- 3. behaviour is content ----

## The same code, the same situation, two profiles, two different bots. If this
## ever stops holding, a difficulty tier has become a build.
func _test_profile_drives_choice() -> void:
	var defender: BotProfileDef = _profile()
	defender.value_defend = 90000.0
	defender.value_steal = 100.0

	var thief: BotProfileDef = _profile()
	defender.value_patrol = 0.0
	thief.value_defend = 100.0
	thief.value_steal = 90000.0

	_check("content/a defend-weighted profile defends",
		_choice_with(defender), BotTask.Kind.DEFEND)
	_check("content/a steal-weighted one goes for the cash",
		_choice_with(thief), BotTask.Kind.STEAL)

## Puts a bot on team_a with both an intruder on its own ground and loose cash
## in the far vault, then reports which it picks.
func _choice_with(profile: BotProfileDef) -> BotTask.Kind:
	var world: SimWorld = _world()
	var mine: SimEntity = world.get_entity(world.actor_ids()[0])
	mine.position = Vector3(150, FLOOR_TOP + RADIUS, 100)

	var intruder: SimEntity = world.get_entity(world.actor_ids()[1])
	intruder.position = Vector3(200, FLOOR_TOP + RADIUS, 100) # in team_a's yard

	var loot: SimEntity = SimEntity.new(SimEntity.NO_ENTITY, SimEntity.Kind.CARRIABLE)
	loot.team = &"team_b"
	loot.position = Vector3(350, FLOOR_TOP + RADIUS, 100)
	world.add_entity(loot)

	var director: BotDirector = BotDirector.for_actor(
		mine.id, profile, NavGraph.of(world.surface), 5
	)
	director.drain(world, world.tick, {})
	return director.current_task().kind

# ---- 4. ordinary decisions ----

func _test_decisions() -> void:
	# Carrying something, the only sensible errand is banking it.
	var world: SimWorld = _world()
	var mine: SimEntity = world.get_entity(world.actor_ids()[0])
	mine.position = Vector3(200, FLOOR_TOP + RADIUS, 100)
	var loot: SimEntity = SimEntity.new(SimEntity.NO_ENTITY, SimEntity.Kind.CARRIABLE)
	loot.team = &"team_b"
	world.add_entity(loot)
	mine.carrying_id = loot.id
	loot.carried_by = mine.id

	var carrying: BotDirector = BotDirector.for_actor(
		mine.id, _profile(), NavGraph.of(world.surface), 5
	)
	var commands: Array[SimCommand] = carrying.drain(world, world.tick, {})
	_check("decide/carrying means depositing", carrying.current_task().kind, BotTask.Kind.DEPOSIT)

	# Whatever it decided, what comes out is the ordinary command vocabulary. A
	# bot with a command kind of its own would be a bot with a privilege.
	var ordinary: bool = true
	for command: SimCommand in commands:
		if command.kind != MoveCommand.KIND_MOVE and command.kind != CarryCommand.KIND_PICK_UP \
			and command.kind != CarryCommand.KIND_DROP:
			ordinary = false
	_check("decide/emits only the commands a player emits", ordinary, true)

	# Cash sealed behind a wall scores as impossible, not as distant. A bot that
	# merely finds it expensive will still pick it when nothing else is going on
	# and spend the round walking into masonry.
	#
	# Sealed as a CLOSET inside the yard rather than by walling off the far end
	# of the level, because walling off the far end is content the load gate
	# refuses outright - which it should, and which is why the first attempt at
	# this case could not be built. Every zone and every spawn stays reachable;
	# only the cash inside the closet is not.
	var closet: Array[AABB] = [
		AABB(Vector3(150, FLOOR_TOP, 50), Vector3(10, 60, 100)),
		AABB(Vector3(240, FLOOR_TOP, 50), Vector3(10, 60, 100)),
		AABB(Vector3(160, FLOOR_TOP, 50), Vector3(80, 60, 10)),
		AABB(Vector3(160, FLOOR_TOP, 140), Vector3(80, 60, 10)),
	]
	var walled: SimWorld = _world(1, closet)
	var seeker: SimEntity = walled.get_entity(walled.actor_ids()[0])
	seeker.position = Vector3(120, FLOOR_TOP + RADIUS, 100)
	var sealed_loot: SimEntity = SimEntity.new(SimEntity.NO_ENTITY, SimEntity.Kind.CARRIABLE)
	sealed_loot.team = &"team_b"
	sealed_loot.position = Vector3(200, FLOOR_TOP + RADIUS, 100)
	walled.add_entity(sealed_loot)
	var blocked: BotDirector = BotDirector.for_actor(
		seeker.id, _profile(), NavGraph.of(walled.surface), 5
	)
	blocked.drain(walled, walled.tick, {})
	_check("decide/unreachable cash is never chosen",
		blocked.current_task().kind != BotTask.Kind.STEAL, true)

	# A held actor decides nothing and pushes nowhere.
	var jailed: SimWorld = _world()
	var held: SimEntity = jailed.get_entity(jailed.actor_ids()[0])
	held.is_captured = true
	var idle: BotDirector = BotDirector.for_actor(
		held.id, _profile(), NavGraph.of(jailed.surface), 5
	)
	idle.drain(jailed, jailed.tick, {})
	_check("decide/a captured bot holds no task", idle.current_task().is_none(), true)

# ---- 5. the two seats ----

func _test_takeover() -> void:
	var world: SimWorld = _world(2)
	var crew: BotCrew = _crew(world)
	var humans: Array[int] = _seat_humans(world, [2, 2])
	for i: int in 20:
		world.step([])

	# Mid-match, with the world already running. The capability the disconnect
	# path will need, exercised at the point it will be needed from.
	var abandoned: int = humans[0]
	var before: String = world.state_digest()
	crew.take_over(world, abandoned)
	_check("seat/taking over mid-match perturbs nothing", world.state_digest(), before)
	_check("seat/and is recorded as a takeover", crew.seat_of(abandoned), BotCrew.Seat.TAKEOVER)

	# The other seat kind stays distinguishable, which is the point of having
	# two: one is optional and fair, the other is neither.
	var lobby: SimWorld = _world(2)
	var lobby_crew: BotCrew = _crew(lobby)
	var filled: Array[int] = lobby_crew.fill_lobby(lobby, [], 4)
	_check("seat/lobby fill is recorded as a lobby fill",
		lobby_crew.seat_of(filled[0]), BotCrew.Seat.LOBBY_FILL)

# ---- the latched-intent trap ----

## A sender that only speaks when its intent CHANGES, plus a phase that
## DISCARDS what it says, equals an actor that never moves again.
##
## This cost an entire match of bots standing still while every unit test in
## this file passed, so the case exists at the seam rather than in either half:
## the world invalidates intent on entering play, and anything that emits
## MoveCommands re-declares. A player holding one direction through the whistle
## had the same bug and would have blamed the controls.
func _test_intent_survives_a_countdown() -> void:
	var world: SimWorld = _world()
	world.add_system(MatchFlowSystem.new())
	world.match_phase = SimWorld.MatchPhase.WAITING
	var crew: BotCrew = _crew(world)
	crew.fill_lobby(world, [], 2)

	var before: int = world.intent_epoch
	world.step([MatchCommand.start()])
	# Through the countdown, where a dormant movement system throws commands away.
	var spoke_while_paused: int = 0
	while world.match_phase == SimWorld.MatchPhase.COUNTDOWN:
		spoke_while_paused += crew.drain(world, world.tick).size()
		world.step([])
	_check("intent/nothing is said into a dormant phase", spoke_while_paused, 0)
	_check("intent/entering play invalidates what stood", world.intent_epoch > before, true)

	# The tick play begins, every bot must re-declare rather than assume the
	# world still holds an intent it discarded.
	var declared: int = 0
	for command: SimCommand in crew.drain(world, world.tick):
		if command.kind == MoveCommand.KIND_MOVE:
			declared += 1
	_check("intent/and every bot re-declares", declared, crew.count())
