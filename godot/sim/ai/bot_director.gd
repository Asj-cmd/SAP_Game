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
## The world's intent epoch as of the last command sent. A mismatch means what
## was last said no longer stands.
var _intent_epoch: int = -1
## Steering error for the current decision. Re-rolled per decision rather than
## per tick: fresh noise every tick would cancel itself out into a straight line
## and emit a new command each time on the way.
var _wobble: float = 0.0
## Where the body was when progress was last checked, and how long it has been
## going nowhere. See the give-way rule in _steer.
var _progress_mark: Vector3 = Vector3.ZERO
var _stuck_ticks: int = 0
## Ticks left of backing away to let somebody else through.
var _yield_ticks: int = 0

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

## The route being followed, for a debug overlay to draw.
##
## Behaviour that cannot be seen gets diagnosed by staring at capsules and
## guessing, which is how "the bot is stuck" becomes an argument about
## pathfinding when it is really about following.
func route() -> PackedVector3Array:
	return _route

## Index of the waypoint currently being steered towards.
func leg() -> int:
	return _leg

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

	# Nothing to say while play is stopped; the commands would be discarded.
	if not world.is_live():
		return commands

	# Intent is latched - an unchanged heading is not re-sent, because emitting
	# the same vector thirty times a second is noise. The world says when that
	# latch has gone stale rather than each sender guessing (§ invalidate_intent).
	if _intent_epoch != world.intent_epoch:
		_intent_epoch = world.intent_epoch
		_has_sent_intent = false

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

	commands.append_array(_steer(world, me, tick))
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
	# Re-rolled on every route, not only when the errand changes.
	#
	# Wobble is a CONSTANT angular error, and held for a whole journey it stops
	# being imprecision and becomes a bias. Threading a doorway needs a heading
	# correction of a fraction of a unit per tick; a fifth of a radian is worth
	# rather more than that, so a bot whose wobble happened to point into the
	# jamb was pinned against it for as long as it kept the errand - which is a
	# lone bot stalling two hundred times at one door, and never at any other.
	_wobble = _rng.next_signed(profile.steer_wobble)
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
func _steer(world: SimWorld, me: SimEntity, tick: int) -> Array[SimCommand]:
	while _leg < _route.size() and _flat_distance(me.position, _route[_leg]) <= profile.arrive_radius:
		_leg += 1
	if _leg >= _route.size():
		return _stop_if_moving(tick)

	# Aim at the FURTHEST waypoint still in clear view, not the next one.
	#
	# This is where "the bot is stuck in the doorway" actually lived. The route
	# was fine - it threaded the gap - but the follow walked at the nearest
	# waypoint, which sits just inside the opening. Walking at a point inside a
	# doorway means walking at its frame: the body clips the jamb, slides, re-
	# aims at the same point, and clips it again.
	#
	# Steering at the furthest visible point pulls the line taut through the
	# gap. It is the same funnel the route was smoothed with, applied
	# continuously as the body moves rather than once when the path was built -
	# which is what makes it work from wherever the bot has actually ended up
	# rather than from where the path assumed it would be.
	# Give way if nothing is working.
	#
	# Two bodies meeting in a doorway jam: neither can pass and neither can
	# slide, because the frame is exactly where the sidestep would go. The route
	# is not wrong and re-routing does not help - the obstruction is a person,
	# and the nav graph has never heard of people.
	#
	# So a bot that has stopped making progress backs off for a moment. Only the
	# HIGHER id yields, or both would retreat in step and meet again on the way
	# back in. Arbitrary, and arbitrary identically on every machine.
	if _yield_ticks > 0:
		_yield_ticks -= 1
		var retreat: Vector3 = me.position - _route[mini(_leg, _route.size() - 1)]
		retreat.y = 0.0
		if retreat.length_squared() > 0.0:
			return _send_intent(retreat.normalized(), tick)
	elif _crowded(world, me):
		_stuck_ticks += 1
		if _stuck_ticks >= profile.unstick_ticks():
			_stuck_ticks = 0
			_yield_ticks = profile.unstick_ticks()
	else:
		_stuck_ticks = 0

	var target: int = -1
	var horizon: int = mini(_route.size() - 1, _leg + maxi(1, profile.path_lookahead))
	for i: int in range(horizon, _leg - 1, -1):
		if nav.surface.is_clear_between(me.position, _route[i]):
			target = i
			break

	if target < 0:
		# NOTHING on the route is in sight, including the waypoint it was
		# already heading for. The body has drifted off the line - shoved by
		# another actor, or slid along a wall - and every remaining waypoint is
		# now behind geometry.
		#
		# This is where the doorway stall actually lived, and it is why looking
		# further AHEAD alone did not fix it: the bot was walking at a waypoint
		# it could no longer reach in a straight line, so it walked into the
		# wall in between, slid, and arrived nowhere while reporting MOVING.
		# A route is only worth following from a place it can be followed from,
		# so re-route from where the body actually is - but NO MORE OFTEN than
		# an ordinary repath. Re-routing on every stranded tick floods the whole
		# walkable surface per bot per tick, which is not a recovery: it is a
		# stall of a different kind, and it stopped a six-minute match from
		# finishing at all.
		if tick >= _next_repath_tick:
			_plan(world, me, tick)
			return _stop_if_moving(tick)
		# Re-routed recently and still boxed in. Keep walking at the waypoint it
		# already had; something else - gravity, a slide, the other body moving
		# on - usually frees it before the next repath comes due.
		target = _leg
	_leg = target

	var heading: Vector3 = _route[target] - me.position
	heading.y = 0.0
	if heading.length_squared() <= 0.0:
		return _stop_if_moving(tick)

	return _send_intent(heading.normalized().rotated(Vector3.UP, _wobble), tick)

func _send_intent(intent: Vector3, tick: int) -> Array[SimCommand]:
	if _has_sent_intent and intent.is_equal_approx(_last_intent):
		return []
	_last_intent = intent
	_has_sent_intent = true
	return [MoveCommand.move(actor_id, intent, tick)] as Array[SimCommand]

## Is this body going nowhere with somebody else in the way?
##
## Both halves matter. No progress alone is an ordinary pause - waiting out a
## countdown, standing in a safe room. No progress WITH a body pressed against
## it is the jam worth breaking, and only the higher id breaks it.
func _crowded(world: SimWorld, me: SimEntity) -> bool:
	var moved: float = me.position.distance_to(_progress_mark)
	_progress_mark = me.position
	if moved > profile.arrive_radius * 0.25:
		return false
	var reach: float = world.tuning.actor_radius * 2.5
	for entity_id: int in world.sorted_entity_ids():
		var other: SimEntity = world.entities[entity_id]
		if entity_id == actor_id or not other.is_actor() or other.is_captured:
			continue
		if actor_id < entity_id:
			continue # the lower id holds its ground
		if me.position.distance_to(other.position) <= reach:
			return true
	return false

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
