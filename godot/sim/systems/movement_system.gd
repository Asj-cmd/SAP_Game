class_name MovementSystem
extends SimSystem
## Turns travel intent into position, as an explicit state machine.
##
## The state machine is the point (§9): presentation READS SimEntity.
## motion_state to choose an animation and never decides it, and never infers
## it by differencing rendered positions either. Only this system writes it.
##
## Transitions, evaluated fresh every tick:
##
##   any    -> HELD     captured; inert until released
##   HELD   -> IDLE     released
##   *      -> IDLE     no intent, or intent below the deadzone
##   *      -> MOVING   intent, and somewhere to put the actor
##   *      -> BLOCKED  intent, but every axis is walled off
##
## Runs in Phase.MOVEMENT, so capture ranges and safe-room grants are judged
## on where actors ENDED the tick rather than where they started it. That
## ordering is declared, not left to the order someone registered systems in.

## Intent shorter than this counts as no intent. Stick drift and a
## near-stationary analog input should read as standing still, not as a
## permanent 0.01-speed creep.
const INTENT_DEADZONE: float = 0.05
const INTENT_DEADZONE_SQUARED: float = INTENT_DEADZONE * INTENT_DEADZONE

## Bisection steps used to find where a blocked move stops.
##
## Fixed rather than tolerance-driven, because a loop that runs until it is
## "close enough" runs a different number of times on different inputs, and
## the whole simulation is built on doing the same work every time.
const SWEEP_STEPS: int = 12

func phase() -> SimSystem.Phase:
	return SimSystem.Phase.MOVEMENT

func system_name() -> StringName:
	return &"MovementSystem"

func handles(kind: StringName) -> bool:
	return kind == MoveCommand.KIND_MOVE

## Records intent only. Nothing moves until step(), so every actor in a tick
## is integrated against the same world rather than against whatever the
## actors ahead of it in the command list happened to do first.
func handle(world: SimWorld, command: SimCommand) -> void:
	var move: MoveCommand = command as MoveCommand
	if move == null:
		return
	var actor: SimEntity = world.get_entity(move.actor_id)
	if actor == null or not actor.is_actor():
		return
	# A held actor may keep sending intent - it simply does not get to use it.
	actor.move_intent = _clamp_intent(move.intent)

## Clamps to unit length, so an over-long vector buys no extra speed.
##
## The square root only happens on the over-long path. Legitimate input is
## already within the unit sphere, so the common case stays inside the exactly
## representable subset (§6) and the normalise is reserved for input that is
## either malicious or malformed.
func _clamp_intent(intent: Vector3) -> Vector3:
	if intent.length_squared() <= 1.0:
		return intent
	return intent.normalized()

func step(world: SimWorld) -> void:
	for entity_id: int in world.sorted_entity_ids():
		var entity: SimEntity = world.entities[entity_id]
		if entity.is_actor():
			_advance(world, entity)

func _advance(world: SimWorld, actor: SimEntity) -> void:
	var previous_state: SimEntity.MotionState = actor.motion_state
	var previous_zone: StringName = actor.zone_id

	var next_state: SimEntity.MotionState = _resolve(world, actor)

	if next_state != previous_state:
		actor.motion_state = next_state
		world.emit(MovementEvent.motion_changed(world.tick, actor.id, previous_state, next_state))

	# Kept current here because this system is the one that moves actors, so
	# everything downstream can read the zone rather than re-resolving it.
	var zone: ZoneDef = world.zone_at(actor.position)
	actor.zone_id = zone.id if zone != null else &""
	if actor.zone_id != previous_zone:
		world.emit(MovementEvent.zone_changed(world.tick, actor.id, previous_zone, actor.zone_id))

## Runs one actor's transition and applies whatever displacement it earns.
## Bodies are solid to each other, resolved in ascending id order.
##
## Order matters and is the order everything else already uses: actors are
## advanced one at a time, so an actor meeting one that has already moved sees
## its NEW position and one that has not sees its old one. That is arbitrary but
## it is arbitrary in the same way on every machine, which is the only property
## required.
##
## A held actor neither blocks nor is blocked. Prisoners are all placed on the
## pen's single centre point, so making them solid would weld the whole pen into
## one lump and wall off the rescue they are waiting for.
##
## Tested at the DESTINATION rather than swept. Two actors closing head-on cover
## about 29 units a tick between them against a 40-unit diameter, so there is no
## room to pass through each other; a swept body-versus-body test would cost
## more than the case is worth. Revisit if bodies get faster or thinner.
func _blocked_by_actor(
	world: SimWorld,
	mover: SimEntity,
	from: Vector3,
	to: Vector3
) -> bool:
	return _blocking_actor(world, mover, from, to) != null

## The first body in the way, or null. Same rule as above; the caller needs to
## know WHICH one so it can slide around it rather than merely stop.
func _blocking_actor(
	world: SimWorld,
	mover: SimEntity,
	from: Vector3,
	to: Vector3
) -> SimEntity:
	if world.tuning == null or mover.is_captured:
		return null
	var span: float = world.tuning.actor_radius * 2.0
	if span <= 0.0:
		return null
	var span_squared: float = span * span

	for entity_id: int in world.sorted_entity_ids():
		var other: SimEntity = world.entities[entity_id]
		if entity_id == mover.id or not other.is_actor() or other.is_captured:
			continue
		var closing: float = to.distance_squared_to(other.position)
		if closing >= span_squared:
			continue
		# Already overlapping: allow anything that opens the gap. Without this a
		# pair nudged together by a spawn, a round reset or a release would be
		# stuck against each other for the rest of the round - the same trap
		# WorldCollisionDef avoids for geometry.
		if from.distance_squared_to(other.position) < span_squared \
			and closing > from.distance_squared_to(other.position):
			continue
		return other
	return null

func _resolve(world: SimWorld, actor: SimEntity) -> SimEntity.MotionState:
	if actor.is_captured:
		actor.velocity = Vector3.ZERO
		return SimEntity.MotionState.HELD

	# Travel intent is horizontal. Height is gravity's business, so an actor
	# cannot fly by aiming upward.
	var heading: Vector3 = Vector3(actor.move_intent.x, 0.0, actor.move_intent.z)
	var state: SimEntity.MotionState = SimEntity.MotionState.IDLE

	if heading.length_squared() >= INTENT_DEADZONE_SQUARED:
		var speed: float = _speed_for(world, actor)
		actor.velocity.x = heading.x * speed
		actor.velocity.z = heading.z * speed
		var moved: bool = _apply_displacement(world, actor, heading * speed * SimWorld.SECONDS_PER_TICK)
		# Wanted to move and could not: distinct from standing still, and
		# presentation wants to show it differently.
		state = SimEntity.MotionState.MOVING if moved else SimEntity.MotionState.BLOCKED
		if not moved:
			actor.velocity.x = 0.0
			actor.velocity.z = 0.0
	else:
		actor.velocity.x = 0.0
		actor.velocity.z = 0.0

	_apply_gravity(world, actor)
	return state

## Falls, and lands. See WORLD_AUTHORING.md §5.
##
## A minimal kinematic controller, not a physics engine and not a
## contradiction of §6: physics stays out of the rules, but standing on a
## floor IS a rule. Floors are ordinary blockers, so nothing here knows what a
## floor is - only that something solid stopped the fall.
func _apply_gravity(world: SimWorld, actor: SimEntity) -> void:
	var gravity: float = world.tuning.gravity if world.tuning != null else 0.0
	if gravity <= 0.0:
		# No gravity authored: a fixture testing horizontal rules. Everything
		# counts as standing, so nothing reads as permanently airborne.
		actor.velocity.y = 0.0
		actor.is_grounded = true
		return

	var terminal: float = world.tuning.terminal_fall_speed
	actor.velocity.y = maxf(actor.velocity.y - gravity * SimWorld.SECONDS_PER_TICK, -terminal)

	var fall: Vector3 = Vector3(0.0, actor.velocity.y * SimWorld.SECONDS_PER_TICK, 0.0)
	var landed: Vector3 = _sweep(world, actor, actor.position, fall)
	var stopped_short: bool = not landed.is_equal_approx(actor.position + fall)
	actor.position = landed

	# Only a fall that was cut short means ground underfoot. A rise that was
	# cut short is a ceiling, and leaves the actor airborne.
	if stopped_short and actor.velocity.y <= 0.0:
		actor.velocity.y = 0.0
		actor.is_grounded = true
	else:
		actor.is_grounded = false

## The furthest point along `delta` the actor may legally reach.
##
## Bisection rather than an exact solve: it works against whatever
## _can_traverse decides, so ground resolution stays correct when traversal
## grows locked doors or one-way edges (§9) without knowing about any of it.
func _sweep(world: SimWorld, mover: SimEntity, from: Vector3, delta: Vector3) -> Vector3:
	if delta == Vector3.ZERO:
		return from
	if _can_traverse(world, mover, from, from + delta):
		return from + delta
	var reachable: float = 0.0
	var blocked: float = 1.0
	for i: int in SWEEP_STEPS:
		var middle: float = (reachable + blocked) * 0.5
		if _can_traverse(world, mover, from, from + delta * middle):
			reachable = middle
		else:
			blocked = middle
	return from + delta * reachable

## Content decides pace. A laden actor is slower, which is the entire tension
## of carrying something valuable across open ground.
func _speed_for(world: SimWorld, actor: SimEntity) -> float:
	if world.tuning == null:
		return 0.0
	if actor.is_carrying():
		return world.tuning.carry_speed()
	return world.tuning.move_speed

## Moves as far as the world allows, sliding along whatever it cannot pass.
##
## The whole step is tried first; failing that, each axis is tried alone, in a
## fixed X, Y, Z order. Sliding is why an actor pressing diagonally into a wall
## beside a doorway slips through the gap instead of sticking to the wall - the
## 1:1 port did the same thing, and it was the difference between doorways
## feeling generous and feeling broken (WORLD_AUTHORING.md §4 keeps it).
func _apply_displacement(world: SimWorld, actor: SimEntity, delta: Vector3) -> bool:
	if delta == Vector3.ZERO:
		return false

	if _can_traverse(world, actor, actor.position, actor.position + delta):
		actor.position += delta
		return true

	# Another body in the way: go AROUND it rather than stopping dead.
	#
	# The axis-aligned fallback below is useless here. Two actors crossing the
	# yard meet with the contact normal along their direction of travel, so the
	# only axis that would help carries almost none of their movement: they
	# shuffle, re-approach, and shuffle again. Left like that the pair simply
	# stops - a bot match went from twelve pick-ups to zero, both of them stalled
	# in open ground within sight of each other.
	var blocker: SimEntity = _blocking_actor(world, actor, actor.position, actor.position + delta)
	if blocker != null and _slide_past(world, actor, blocker, delta):
		return true

	# Blocked head-on: try stepping over it. A sill or a stair tread should
	# not need a jump - possibly a verb this game never has - and gravity
	# settles the actor back down onto whatever it climbed.
	if _try_step_up(world, actor, delta):
		return true

	var moved: bool = false
	for axis: int in 3:
		var single_axis: Vector3 = Vector3.ZERO
		single_axis[axis] = delta[axis]
		if single_axis == Vector3.ZERO:
			continue
		if _can_traverse(world, actor, actor.position, actor.position + single_axis):
			actor.position += single_axis
			moved = true
	return moved

## Lifts by the step-up allowance, moves across, and settles back down.
##
## Three phases, all swept. The lift must itself be clear, or an actor under a
## low ceiling would climb into it; and the settle is what makes the allowance
## a MAXIMUM rather than a fixed hop. Without it an actor clears a 5-high sill
## by rising the full 30, then drifts forward while gravity brings it back -
## sailing over the step entirely and landing beyond it.
func _try_step_up(world: SimWorld, actor: SimEntity, delta: Vector3) -> bool:
	var rise: float = world.tuning.step_up_height if world.tuning != null else 0.0
	if rise <= 0.0:
		return false
	# You step over a sill, not over a person. Without this an actor blocked by
	# another simply climbs it: the lift clears the other body, the crossing is
	# unobstructed at head height, and it comes down on the far side having
	# walked straight through somebody.
	if _blocked_by_actor(world, actor, actor.position, actor.position + delta):
		return false
	var raised: Vector3 = actor.position + Vector3(0.0, rise, 0.0)
	if not _can_traverse(world, actor, actor.position, raised):
		return false
	if not _can_traverse(world, actor, raised, raised + delta):
		return false
	# Come back down onto whatever was climbed, in the same tick, so the actor
	# is never left hovering above a sill it merely stepped over.
	actor.position = _sweep(world, actor, raised + delta, Vector3(0.0, -rise, 0.0))
	return true

## Moves along the part of `delta` that does not push into `blocker`.
##
## The tangent to the contact, which is what lets two bodies brush past each
## other instead of arguing. A perfectly head-on approach has no tangent at all,
## so that case steps ASIDE, and which side is decided by entity id: the two
## actors involved always pick opposite ways, so they pass rather than mirroring
## each other into a fresh deadlock. Arbitrary, but arbitrary identically on
## every machine, which is the only property required.
func _slide_past(
	world: SimWorld,
	actor: SimEntity,
	blocker: SimEntity,
	delta: Vector3
) -> bool:
	var away: Vector3 = actor.position - blocker.position
	away.y = 0.0
	var tangent: Vector3 = Vector3.ZERO
	if away.length_squared() > 0.0:
		var normal: Vector3 = away.normalized()
		tangent = delta - normal * delta.dot(normal)

	if tangent.length_squared() <= INTENT_DEADZONE_SQUARED:
		var sidestep: Vector3 = Vector3(delta.z, 0.0, -delta.x)
		tangent = sidestep if actor.id < blocker.id else -sidestep
	if tangent.length_squared() <= 0.0:
		return false

	if _can_traverse(world, actor, actor.position, actor.position + tangent):
		actor.position += tangent
		return true
	return false

## May an actor travel from `from` to `to` this tick?
##
## Two independent questions, per WORLD_AUTHORING.md §2: the destination must
## be inside the world shell, and the path must not cross anything solid. The
## path test is swept rather than sampled at the endpoint (§4), so a fast
## actor cannot step over a thin wall.
##
## Zones are deliberately NOT consulted. They answer "what rules apply here",
## not "can I be here" - that was the conflation the retired placeholder was
## built on, and it made every shared zone face a walkable doorway.
func _can_traverse(world: SimWorld, mover: SimEntity, from: Vector3, to: Vector3) -> bool:
	if world.collision != null:
		var radius: float = world.tuning.actor_radius if world.tuning != null else 0.0
		if not world.collision.contains(to, radius):
			return false
		if world.collision.blocks_segment(from, to, radius):
			return false
	# Other bodies, last: geometry is the cheaper test and rules out most moves
	# before anyone has to be walked.
	return not _blocked_by_actor(world, mover, from, to)
