class_name BotDirector
extends RefCounted
## Drives one actor by emitting the commands a player's input would. See
## ARCHITECTURE.md §2 and §3.
##
## NOT A SYSTEM, and that is the load-bearing decision in this file. A system
## would run inside step() with the rules and could reach into world state
## directly; this sits exactly where LocalPlayerInput sits, reads the world, and
## returns commands. Every consequence follows from that:
##
##   - A bot cannot cheat, because there is no path into the world that skips
##     the rules. Every command it emits is validated exactly as a player's is,
##     and a bad guess is refused rather than trusted (§3).
##   - No rule branches on is_bot, because no rule can tell. The flag exists for
##     presentation and for the lobby; the simulation never reads it.
##   - Removing bots removes nothing else. A match with none behaves precisely
##     as it would if this file did not exist - no system consults it, and
##     nothing in the tick changes shape when the crew is empty.
##
## It lives in sim/ despite not being a system because it must be deterministic
## and headless: bots have to behave identically on every machine and inside the
## test harness, which rules out the presentation layer LocalPlayerInput is in.

var actor_id: int = SimEntity.NO_ENTITY
var profile: BotProfileDef = null
var nav: NavGraph = null

## Private randomness, seeded from the match seed and the actor id and drawn
## from nowhere else.
##
## Explicitly NOT world.rng.fork(), which would advance the world's stream. The
## requirement is that a match with zero bots runs identically to one where bots
## were never implemented, and a director that consumed a single draw at
## construction would shift every subsequent roll in the match. Deriving the
## seed by hashing instead touches nothing, so adding, removing or taking over a
## bot cannot perturb anything else in the world.
var _rng: SimRandom = null

var _task: BotTask = null
var _route: PackedVector3Array = PackedVector3Array()
var _leg: int = 0
var _next_decide_tick: int = 0
var _next_repath_tick: int = 0
## Chosen, but not yet acted on. Human hesitation, in ticks.
var _act_after_tick: int = 0
var _last_intent: Vector3 = Vector3.ZERO
var _has_sent_intent: bool = false
## Steering error for the current decision. Re-rolled per decision rather than
## per tick: fresh noise every tick would cancel itself out into a straight line
## and emit a new command each time on the way.
var _wobble: float = 0.0

static func for_actor(
	actor: int,
	bot_profile: BotProfileDef,
	graph: NavGraph,
	match_seed: int
) -> BotDirector:
	var director: BotDirector = BotDirector.new()
	director.actor_id = actor
	director.profile = bot_profile
	director.nav = graph
	director._rng = SimRandom.new(SimWorld.hash_string("bot|%d|%d" % [match_seed, actor]))
	director._task = BotTask.none()
	return director

func current_task() -> BotTask:
	return _task

## One tick's worth of commands, exactly as LocalPlayerInput.drain produces.
##
## `claims` is the squad's shared table of what has been spoken for this tick.
## It is the entire coordination mechanism: no bot is assigned anything, each
## simply prefers not to duplicate what a team-mate already picked.
func drain(world: SimWorld, tick: int, claims: Dictionary[String, int]) -> Array[SimCommand]:
	var commands: Array[SimCommand] = []
	if profile == null or nav == null:
		return commands
	var me: SimEntity = world.get_entity(actor_id)
	if me == null or not me.is_actor():
		return commands

	# Play is stopped: say nothing, and FORGET what was last said.
	#
	# Intent is latched - an unchanged heading is not re-sent, because a client
	# emitting the same vector thirty times a second is noise. But commands
	# issued while the movement system is dormant are discarded, so a bot that
	# spoke during a countdown would believe the world had heard it. Its heading
	# then never changes, because it never moves, so it never speaks again: the
	# bot stands still for the entire match while deciding flawlessly. Clearing
	# the latch here is what makes the first tick of play re-assert intent.
	if not world.is_live():
		_has_sent_intent = false
		return commands

	# Held actors decide nothing. Intent is cleared rather than left standing,
	# so a released actor does not resume walking into whatever it was pushing
	# against when it was seized.
	if me.is_captured:
		_task = BotTask.none()
		_route = PackedVector3Array()
		return _stop_if_moving(tick)

	if tick >= _next_decide_tick:
		_decide(world, me, tick, claims)
	elif tick >= _next_repath_tick and not _task.is_none():
		# The world moves under a held task: cash gets picked up, prisoners get
		# moved to a pen. A route to where the target used to be is worse than
		# no route, because the bot walks it confidently.
		_plan(world, me, tick)

	commands.append_array(_steer(me, tick))
	commands.append_array(_act(world, me, tick))
	return commands

# ---- deciding ----

func _decide(world: SimWorld, me: SimEntity, tick: int, claims: Dictionary[String, int]) -> void:
	_next_decide_tick = tick + profile.decide_ticks() + _jitter_ticks()

	var origin: int = nav.node_at(me.position)
	var hops: PackedInt32Array = nav.hops_from(origin)

	var best: BotTask = BotTask.none()
	var best_score: float = -INF
	for task: BotTask in _candidates(world, me):
		var node: int = nav.surface.nearest(task.destination)
		var distance: float = nav.distance_by_hops(hops, node)
		var claimed: bool = claims.has(task.key()) and claims[task.key()] != actor_id
		var score: float = UtilityScorer.score(
			profile,
			task.kind,
			distance,
			_threats(world, me, task),
			task.matches(_task),
			claimed,
			_rng.next_signed(profile.choice_noise)
		)
		if score > best_score:
			best_score = score
			best = task

	var changed: bool = not best.matches(_task)
	_task = best
	if changed:
		# Only a NEW decision costs reaction time. Re-confirming what it was
		# already doing must not make a bot hesitate every time it thinks.
		_act_after_tick = tick + profile.reaction_ticks()
		_wobble = _rng.next_signed(profile.steer_wobble)
	if not _task.is_none():
		claims[_task.key()] = actor_id
	_plan(world, me, tick)

## Everything worth considering, before any of it is judged.
##
## Enumeration is role-based throughout: no room is named, no team is named, and
## the same code produces sensible errands on a level with three houses or a
## central shared vault (§4, principle 4).
func _candidates(world: SimWorld, me: SimEntity) -> Array[BotTask]:
	var tasks: Array[BotTask] = []

	if me.is_carrying():
		# Holding something: the only thing worth doing is banking it.
		for zone_id: StringName in world.zone_ids_in_resolution_order():
			var zone: ZoneDef = world.zones[zone_id]
			if zone.role == ZoneDef.Role.CASH_ROOM and zone.is_owned_by(me.team):
				tasks.append(BotTask.make(
					BotTask.Kind.DEPOSIT, me.carrying_id, zone.bounds.get_center(), zone.id
				))
	else:
		for entity_id: int in world.sorted_entity_ids():
			var loot: SimEntity = world.entities[entity_id]
			if not loot.is_carriable() or loot.is_held():
				continue
			# Already banked with us. Carrying our own cash around our own vault
			# is motion without profit, and it looks exactly as silly as it is.
			if loot.scored_for_team == me.team:
				continue
			tasks.append(BotTask.make(
				BotTask.Kind.STEAL, entity_id, loot.position, loot.zone_id
			))

	for entity_id: int in world.sorted_entity_ids():
		var other: SimEntity = world.entities[entity_id]
		if not other.is_actor() or entity_id == actor_id:
			continue

		if other.team == me.team and other.is_captured:
			tasks.append(BotTask.make(
				BotTask.Kind.RESCUE, entity_id, other.position, other.zone_id
			))
			continue

		if other.team != me.team and not other.is_captured:
			# An intruder is only seizable on ground we own that is not a pen -
			# the same condition CaptureSystem enforces. Proposing it anywhere
			# else would have the bot charge across the map to bounce off a rule.
			var standing: ZoneDef = world.zone_at(other.position)
			if standing != null and standing.is_owned_by(me.team) and standing.role != ZoneDef.Role.JAIL:
				tasks.append(BotTask.make(
					BotTask.Kind.DEFEND, entity_id, other.position, standing.id
				))

	for zone_id: StringName in world.zone_ids_in_resolution_order():
		tasks.append(BotTask.make(
			BotTask.Kind.PATROL, SimEntity.NO_ENTITY, world.zones[zone_id].bounds.get_center(), zone_id
		))
	return tasks

## Enemies near enough to the destination to make going there expensive.
##
## The task's own target does not count against it. Otherwise every DEFEND is
## penalised for the presence of the very intruder it exists to deal with, and a
## cautious profile would never defend anything.
func _threats(world: SimWorld, me: SimEntity, task: BotTask) -> int:
	var seen: int = 0
	var reach: float = profile.vision_radius * profile.vision_radius
	for entity_id: int in world.sorted_entity_ids():
		if entity_id == task.target_id:
			continue
		var other: SimEntity = world.entities[entity_id]
		if not other.is_actor() or other.team == me.team or other.is_captured:
			continue
		if other.position.distance_squared_to(task.destination) <= reach:
			seen += 1
	return seen

func _plan(world: SimWorld, me: SimEntity, tick: int) -> void:
	_next_repath_tick = tick + profile.repath_ticks()
	_leg = 0
	# A fresh route re-asserts intent even when the new heading matches the old.
	# Belt and braces against the latch above: a round reset teleports actors
	# home, and an intent the world dropped on the way must not be assumed live.
	_has_sent_intent = false
	if _task.is_none():
		_route = PackedVector3Array()
		return
	_route = nav.route(me.position, _destination_of(world))

## Where the bot should physically go for its current task.
##
## Read fresh from the world rather than from the task, because the task was
## chosen up to a second ago and the thing it is about may have moved. A rescue
## is the clearest case: the prisoner was seized in a doorway and is now in a
## pen on the other side of the map.
func _destination_of(world: SimWorld) -> Vector3:
	if _task.target_id != SimEntity.NO_ENTITY:
		var target: SimEntity = world.get_entity(_task.target_id)
		if target != null and _task.kind != BotTask.Kind.DEPOSIT:
			return target.position
	return _task.destination

# ---- doing ----

## Follows the route, and reports travel as intent - never as a position.
func _steer(me: SimEntity, tick: int) -> Array[SimCommand]:
	while _leg < _route.size() and _flat_distance(me.position, _route[_leg]) <= profile.arrive_radius:
		_leg += 1
	if _leg >= _route.size():
		return _stop_if_moving(tick)

	var heading: Vector3 = _route[_leg] - me.position
	heading.y = 0.0
	if heading.length_squared() <= 0.0:
		return _stop_if_moving(tick)

	var intent: Vector3 = heading.normalized().rotated(Vector3.UP, _wobble)
	if _has_sent_intent and intent.is_equal_approx(_last_intent):
		return []
	_last_intent = intent
	_has_sent_intent = true
	return [MoveCommand.move(actor_id, intent, tick)] as Array[SimCommand]

## Horizontal only. A waypoint on the floor below a bot standing on a sill is
## still the waypoint it is heading for, and counting the height would leave it
## circling underneath one forever.
func _flat_distance(from: Vector3, to: Vector3) -> float:
	return Vector2(to.x - from.x, to.z - from.z).length()

func _stop_if_moving(tick: int) -> Array[SimCommand]:
	if _has_sent_intent and _last_intent == Vector3.ZERO:
		return []
	_last_intent = Vector3.ZERO
	_has_sent_intent = true
	return [MoveCommand.stop(actor_id, tick)] as Array[SimCommand]

## Fires the interaction the current task calls for, once close enough.
##
## Every condition tested here is also tested by the system that receives the
## command, and the system's answer is the one that counts. These checks exist
## to stop the bot emitting obviously hopeless commands every tick, not to
## decide anything - a bot that guesses wrong is refused, exactly as a player
## mashing a button in the wrong place is.
func _act(world: SimWorld, me: SimEntity, tick: int) -> Array[SimCommand]:
	if _task.is_none() or tick < _act_after_tick:
		return []

	var commands: Array[SimCommand] = []
	match _task.kind:
		BotTask.Kind.STEAL:
			if _within(world, me, world.tuning.pickup_range):
				commands.append(CarryCommand.pick_up(actor_id, _task.target_id, tick))
		BotTask.Kind.DEPOSIT:
			var here: ZoneDef = world.zone_at(me.position)
			if here != null and here.role == ZoneDef.Role.CASH_ROOM and here.is_owned_by(me.team):
				commands.append(CarryCommand.drop(actor_id, tick))
		BotTask.Kind.RESCUE:
			if _within(world, me, world.tuning.rescue_range):
				commands.append(CaptureCommand.release(actor_id, _task.target_id, tick))
		BotTask.Kind.DEFEND:
			if _within(world, me, world.tuning.capture_range):
				commands.append(CaptureCommand.capture(actor_id, _task.target_id, tick))
		_:
			pass

	if not commands.is_empty():
		# Back off for a think rather than retrying every tick. The attempt
		# either worked, in which case the next decision picks up the new
		# situation, or it did not, in which case hammering it will not help.
		_act_after_tick = tick + profile.decide_ticks()
	return commands

## Is the task's target close enough to act on, allowing for the profile's
## willingness to act at the edge of a range rather than well inside it?
func _within(world: SimWorld, me: SimEntity, full_range: float) -> bool:
	var target: SimEntity = world.get_entity(_task.target_id)
	if target == null:
		return false
	var usable: float = full_range * profile.action_range_scale
	return me.position.distance_squared_to(target.position) <= usable * usable

func _jitter_ticks() -> int:
	var spread: int = SimWorld.seconds_to_ticks(profile.decide_jitter_seconds)
	if spread <= 0:
		return 0
	return _rng.next_int_range(0, spread)
