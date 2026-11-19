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
## What the current route was built to reach. A route is only worth rebuilding
## when the thing it leads to has moved - see _plan.
var _planned_for: Vector3 = Vector3.ZERO
var _planned_kind: int = -1
var _planned_target: int = SimEntity.NO_ENTITY
## Walking distances from roughly where the bot is standing, kept between
## decisions. See BotProfileDef.distance_refresh.
var _hops: PackedInt32Array = PackedInt32Array()
var _hops_measured_at: Vector3 = Vector3.ZERO
var _has_hops: bool = false
## A refresh of _hops under way, spread over ticks; null when there is none.
## See BotProfileDef.flood_stances_per_tick.
var _pending_hops: HopFlood = null
## Where the bot was when its route was last examined, to tell a route being
## walked from a route being failed at.
var _checked_at: Vector3 = Vector3.ZERO
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

	_refresh_distances(me)
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

## Keeps the walking-distance table roughly centred on the bot.
##
## Checked every tick rather than only when deciding, so a refresh that takes a
## few ticks to walk starts as soon as it is due instead of a decision later.
## The very first table is walked whole: a bot with no distances cannot decide.
func _refresh_distances(me: SimEntity) -> void:
	if _pending_hops == null:
		var refresh: float = profile.distance_refresh
		if _has_hops and me.position.distance_squared_to(_hops_measured_at) <= refresh * refresh:
			return
		_pending_hops = nav.start_hops(nav.node_at(me.position), me.position)
		if _pending_hops == null:
			return
	var budget: int = profile.flood_stances_per_tick if _has_hops else 0
	if not _pending_hops.advance(budget):
		return
	_hops = _pending_hops.hops()
	_hops_measured_at = _pending_hops.origin_point
	_has_hops = true
	_pending_hops = null

func _decide(world: SimWorld, me: SimEntity, tick: int, claims: Dictionary[String, int]) -> void:
	_next_decide_tick = tick + profile.decide_ticks() + _jitter_ticks()
	var hops: PackedInt32Array = _hops

	var best: BotTask = BotTask.none()
	var best_score: float = -INF
	for task: BotTask in _candidates(world, me):
		var node: int = nav.stance_near(task.destination)
		var distance: float = nav.distance_by_hops(hops, node)
		var claimed: bool = claims.has(task.key()) and claims[task.key()] != actor_id
		var score: float = UtilityScorer.score(
			profile,
			task.kind,
			distance,
			_threats(world, me, task),
			task.matches(_task),
			claimed,
			_rng.next_signed(profile.choice_noise),
			_bonus(world, me, task)
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
		# Holding something: banking it is the errand. The one exception is an
		# intruder close by (below, and _bonus).
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
			# Carrying, only the intruder close by (PT4-8): one across the house
			# is not worth turning round for with cash in hand.
			if me.is_carrying() and _flat_distance(me.position, other.position) > profile.alert_radius:
				continue
			if standing != null and standing.is_owned_by(me.team) and standing.role != ZoneDef.Role.JAIL:
				tasks.append(BotTask.make(
					BotTask.Kind.DEFEND, entity_id, other.position, standing.id
				))

	# A point IN the zone that can be walked to, not its box's centre: a yard's
	# centre is inside the house it wraps (NavGraph.zone_point).
	for zone_id: StringName in world.zone_ids_in_resolution_order():
		tasks.append(BotTask.make(
			BotTask.Kind.PATROL, SimEntity.NO_ENTITY,
			nav.zone_point(world, world.zones[zone_id], me.position), zone_id
		))
	return tasks

## What this task's particular target adds to its kind's value (PT4-8).
##
## Only DEFEND has any: a thief carrying our family's cash gets thief_bonus, and
## an intruder within alert_radius gets alert_bonus. A carrier only ever sees
## DEFENDs inside alert_radius (_candidates), and those get value_deposit on
## top, so dealing with the intruder beats banking; DEPOSIT comes straight back
## on the next decision. Whose cash it is: a carriable's `team` is the team it
## belongs to (SimEntity), which is exactly what a player sees on the bundle.
func _bonus(world: SimWorld, me: SimEntity, task: BotTask) -> float:
	if task.kind != BotTask.Kind.DEFEND:
		return 0.0
	var target: SimEntity = world.get_entity(task.target_id)
	if target == null:
		return 0.0
	var bonus: float = 0.0
	if target.is_carrying():
		var loot: SimEntity = world.get_entity(target.carrying_id)
		if loot != null and loot.team == me.team:
			bonus += profile.thief_bonus
	if _flat_distance(me.position, target.position) <= profile.alert_radius:
		bonus += profile.alert_bonus
		if me.is_carrying():
			bonus += profile.value_deposit
	return bonus

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

## Builds a route for the current task, or keeps the one already in hand.
##
## `force` is for the one caller that must not be talked out of it: the recovery
## when a bot has drifted off its line and can see none of its own waypoints.
## Everything else asks, and usually gets told the route it has is still the
## route it wants.
##
## Re-routing on a timer was costing a 21 ms flood of a fourteen-thousand-stance
## graph, several times a second, for a route that had not changed. That is the
## stutter: the median tick was 1.6 ms and the 99th over 100. Searching faster
## turned out not to be the lever - A* settles a quarter of the nodes and still
## lost to the flood in GDScript, three different queues deep. Searching LESS
## OFTEN is.
func _plan(world: SimWorld, me: SimEntity, tick: int, force: bool = false) -> void:
	# A chase re-aims more often (PT4-8): the target is a running body.
	var chasing: bool = _task.kind == BotTask.Kind.DEFEND
	_next_repath_tick = tick + (profile.chase_repath_ticks() if chasing else profile.repath_ticks())
	# Re-rolled on every route, not only when the errand changes.
	#
	# Wobble is a CONSTANT angular error, and held for a whole journey it stops
	# being imprecision and becomes a bias. Threading a doorway needs a heading
	# correction of a fraction of a unit per tick; a fifth of a radian is worth
	# rather more than that, so a bot whose wobble happened to point into the
	# jamb was pinned against it for as long as it kept the errand - which is a
	# lone bot stalling two hundred times at one door, and never at any other.
	#
	# Still re-rolled on the TIMER even when the route is kept, because that is
	# what the fix was for: a constant angular error held for a whole journey
	# stops being imprecision and becomes a bias into the door frame.
	_wobble = _rng.next_signed(profile.steer_wobble)
	if _task.is_none():
		_route = PackedVector3Array()
		_planned_kind = -1
		return

	var destination: Vector3 = _destination_of(world, me)
	# The world moves under a held task: cash gets picked up, prisoners get
	# moved to a pen. A route to where the target used to be is worse than no
	# route, because the bot walks it confidently. So the question is not "has
	# time passed" but "has the thing I am walking to moved" - and one arrival
	# radius is the distance at which the answer stops mattering.
	# Keep the route only while it is being WALKED.
	#
	# The periodic re-plan was not only a re-plan. It was the recovery for a bot
	# that cannot follow the line it has - jammed on a door frame, sliding along
	# a wall - because it threw the route away and asked again from wherever the
	# body had actually got to. Cache that away and the bot keeps confidently
	# re-aiming at a waypoint it will never reach: measured, every bot in the
	# match pinned at a french window, nought carries, nought encounters, and 662
	# seconds of a six-minute match trying to move and failing.
	#
	# So the test is progress, not time. A bot that has covered ground since the
	# last look is following its route and does not need a new one; a bot that
	# has not is stuck, whatever it believes it is doing.
	var reach: float = profile.arrive_radius * profile.arrive_radius
	var moved: bool = me.position.distance_squared_to(_checked_at) > reach
	_checked_at = me.position
	if not force and moved and _leg < _route.size() 		and _planned_kind == _task.kind and _planned_target == _task.target_id 		and destination.distance_squared_to(_planned_for) <= reach:
		return

	_leg = 0
	_planned_for = destination
	_planned_kind = _task.kind
	_planned_target = _task.target_id
	_route = nav.route(me.position, destination)

## Where the bot should physically go for its current task.
##
## Read fresh from the world rather than from the task, because the task was
## chosen up to a second ago and the thing it is about may have moved. A rescue
## is the clearest case: the prisoner was seized in a doorway and is now in a
## pen on the other side of the map.
func _destination_of(world: SimWorld, me: SimEntity) -> Vector3:
	if _task.target_id != SimEntity.NO_ENTITY:
		var target: SimEntity = world.get_entity(_task.target_id)
		if target != null and _task.kind == BotTask.Kind.DEFEND:
			return _lead_point(me, target, world.tuning.move_speed)
		if target != null and _task.kind != BotTask.Kind.DEPOSIT:
			return target.position
	return _task.destination

## Where to run to catch `target` (PT4-8): where it will be by the time this
## body covers the gap, not where it is. Aiming at the body itself is a pursuit
## that only ever arrives where the thief USED to be: at equal-ish speeds it
## trails behind to the fence. Leading it cuts across its way home instead.
##
## Lead time is the flat gap over `speed`, capped at lead_max_seconds, using the
## target's velocity - what anyone watching it run can see. The point is snapped
## to the nearest stance and kept only if the target could walk straight there;
## a lead through a wall or off a floor is no lead, and the body itself is.
## A target standing still is its own lead point.
func _lead_point(me: SimEntity, target: SimEntity, speed: float) -> Vector3:
	var run: Vector3 = Vector3(target.velocity.x, 0.0, target.velocity.z)
	if run.length_squared() <= 0.0 or speed <= 0.0:
		return target.position
	var ahead: float = clampf(_flat_distance(me.position, target.position) / speed, 0.0, profile.lead_max_seconds)
	var lead: Vector3 = target.position + run * ahead
	var node: int = nav.node_at(lead)
	if node < 0:
		return target.position
	var spot: Vector3 = nav.surface.nodes[node]
	if not nav.surface.is_reachable_between(target.position, spot):
		return target.position
	return spot

# ---- doing ----

## Follows the route, and reports travel as intent - never as a position.
func _steer(world: SimWorld, me: SimEntity, tick: int) -> Array[SimCommand]:
	# Closing in on a thief (PT4-8): near, on its floor, and a straight walk
	# away, the route has nothing more to say - run at where it is going.
	var straight: Vector3 = _close_in_heading(world, me)
	if straight != Vector3.ZERO:
		return _send_intent(straight, tick)
	while _leg < _route.size() and _has_reached(me, _route[_leg]):
		_leg += 1
	if _leg >= _route.size():
		return _stop_if_moving(tick)

	# A drop still to make: keep walking the way it was going until it has fallen.
	#
	# The landing spot of a drop is one cell out from the lip and a long way
	# down. Re-aiming at it every tick, as for any other waypoint, turns the
	# body round the moment it has stepped past it: measured at the top of a
	# stairwell, it stepped off, fell 2 units, turned, stepped back UP onto the
	# landing (the fall was still inside the step-up allowance), and did that
	# every other tick for as long as it held the errand. The heading it arrived
	# with is the one that leads off the edge, and intent is latched, so saying
	# nothing keeps it.
	if _has_sent_intent and _last_intent != Vector3.ZERO and _drop_pending(me, _route[_leg]):
		return []

	# Aim at the FURTHEST waypoint the body could actually reach, not the next one.
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

	# REACHABLE, not merely in clear sight. is_clear_between has no step-up
	# allowance by design - right for smoothing a route between two waypoints
	# already known to be standable, wrong for a body deciding where to walk.
	#
	# On a staircase the two disagree about everything. The line from a body
	# mid-flight to any waypoint above it passes through the treads in between,
	# so the sight test rejects the whole climb: measured on the main stair,
	# nine of the twelve positions on a thirteen-waypoint route had NO visible
	# waypoint ahead. That drops straight through to the "drifted off the line"
	# branch below on nearly every tick - the bot force-repaths, gets the same
	# good route back, stops, and on the ticks between repaths walks at _leg,
	# which by then is behind it. That is the bot stuck on the stairs.
	var horizon: int = mini(_route.size() - 1, _leg + maxi(1, profile.path_lookahead))
	var target: int = nav.surface.furthest_reachable(me.position, _route, _leg, horizon)

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
			# Forced: the route in hand is exactly what is not working.
			_plan(world, me, tick, true)
			return _stop_if_moving(tick)

		# Re-routed recently and still boxed in. Walking at the waypoint it
		# already had is the usual recovery: something else - gravity, a slide,
		# the other body moving on - frees it before the next repath comes due.
		#
		# That reasoning assumes the obstruction MOVES. On a staircase it does
		# not. A body a riser below the top tread has the stairwell wall exactly
		# where its next waypoint lies, so it pushes into masonry, reports
		# BLOCKED, and is in precisely the same place when the repath arrives -
		# which returns the same route, because the route was never wrong. In a
		# lone-bot match that one spot held 100% of the stalls.
		#
		# So take the way the stance graph already knows about. The body is
		# standing on a stance; that stance has neighbours the fill certified a
		# body can reach; and heading for whichever of them leads onward is a
		# step the geometry guarantees. It is a worse line than the route - one
		# cell at a time, no smoothing - and it only has to last until the body
		# is somewhere its route works from.
		var detour: int = _stance_step_toward(me, _route[_leg])
		if detour >= 0:
			var step: Vector3 = nav.surface.nodes[detour] - me.position
			step.y = 0.0
			if step.length_squared() > 0.0:
				return _send_intent(step.normalized(), tick)
		target = _leg
	_leg = target

	var heading: Vector3 = _route[target] - me.position
	heading.y = 0.0
	if heading.length_squared() <= 0.0:
		return _stop_if_moving(tick)

	return _send_intent(heading.normalized().rotated(Vector3.UP, _wobble), tick)

## The heading straight at a DEFEND target's lead point, or zero when the route
## should steer: the target is further than close_in_radius (flat), on another
## floor, or the line to the lead point is not a walk. Reachable rather than in
## sight, for the same reason as the route-follow below: a sight line has no
## step-up allowance and a walk does.
func _close_in_heading(world: SimWorld, me: SimEntity) -> Vector3:
	if _task.kind != BotTask.Kind.DEFEND:
		return Vector3.ZERO
	var target: SimEntity = world.get_entity(_task.target_id)
	if target == null or target.is_captured:
		return Vector3.ZERO
	if _flat_distance(me.position, target.position) > profile.close_in_radius:
		return Vector3.ZERO
	if absf(me.position.y - target.position.y) > nav.surface.step_up_height * 2.0:
		return Vector3.ZERO
	var aim: Vector3 = _lead_point(me, target, world.tuning.move_speed)
	if not nav.surface.is_reachable_between(me.position, aim):
		return Vector3.ZERO
	var heading: Vector3 = aim - me.position
	heading.y = 0.0
	if heading.length_squared() <= 0.0:
		return Vector3.ZERO
	return heading.normalized()

## The neighbouring stance that gets closest to `goal`, or -1.
##
## The escape hatch for a body whose route is fine but whose straight line to it
## is not. Only stances the body can actually reach are considered - the fill
## certified the edge, and is_reachable_between re-checks it from where the body
## has really ended up, which is not the stance centre the edge was built from.
##
## Two neighbours equally close to the goal - one each side of a straight line
## to it, which a grid makes common - break toward the SHORTER STEP from where
## the body actually is, then neighbour order. That used to be neighbour order
## alone, which is world-axis order: the same corner was left by the right in
## House A and by the left in its half-turned twin (P0-5b, tools/twin_probe.gd).
## Deterministic either way; the short step is also the one that turns with the
## house.
func _stance_step_toward(me: SimEntity, goal: Vector3) -> int:
	var surface: WalkableSurface = nav.surface
	var standing: int = surface.stance_under(me.position, surface.cell_size)
	if standing < 0:
		return -1
	var best: int = -1
	var best_gap: float = _flat_distance(me.position, goal)
	var best_step: float = INF
	for other: int in surface.neighbours(standing):
		var gap: float = _flat_distance(surface.nodes[other], goal)
		var step: float = _flat_distance(me.position, surface.nodes[other])
		if gap > best_gap or (gap == best_gap and step >= best_step):
			continue
		if best < 0 and gap >= best_gap:
			continue # no better than standing still
		if not surface.is_reachable_between(me.position, surface.nodes[other]):
			continue
		best = other
		best_gap = gap
		best_step = step
	return best

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

## Has the body got to this waypoint?
##
## Within the arrival radius horizontally (see _flat_distance for why height is
## not part of the distance) - unless the waypoint is a DROP below the body. A
## route may step off a ledge: off a landing into the stairwell, say, onto a
## flight that runs back underneath. Standing at the lip, the landing spot is
## within the radius and so is the waypoint after it, on the floor under the
## landing. Judged flat, both were ticked off before the body had stepped off;
## it then turned for the next waypoint, which is on the floor below and cannot
## be walked to from above, re-planned from where it stood, got the same route,
## and did it again. One bot paced a landing like that for 70 s at a time, on
## its own (P3-3c: 198 of the 283 stall seconds of 4v4 seed 5, which had been
## read as bodies jamming each other at the stairwells).
##
## More than two steps above a waypoint is not at it: the body has yet to
## fall. Two rather than one because a flight is walked a tread or two ahead of
## the body, and a tread is one step. A waypoint ABOVE the body still counts at
## any height - a room's centre is in mid-air, and nothing can rise to it.
func _has_reached(me: SimEntity, waypoint: Vector3) -> bool:
	if _flat_distance(me.position, waypoint) > profile.arrive_radius:
		return false
	return not _is_above(me, waypoint)

## More than two steps above the waypoint. Never on a surface without steps,
## which has no ledges worth the name.
func _is_above(me: SimEntity, waypoint: Vector3) -> bool:
	var step: float = nav.surface.step_up_height
	return step > 0.0 and me.position.y - waypoint.y > step * 2.0

## Is the body over a drop it has yet to finish: above the waypoint and either
## standing within arrival of it (at the lip) or already falling? Bots do not
## jump, so a bot in the air has walked off something.
func _drop_pending(me: SimEntity, waypoint: Vector3) -> bool:
	if not _is_above(me, waypoint):
		return false
	return not me.is_grounded or _flat_distance(me.position, waypoint) <= profile.arrive_radius

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
