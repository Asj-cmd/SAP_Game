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
	return kind == MoveCommand.KIND_MOVE 		or kind == StanceCommand.KIND_STANCE 		or kind == JumpCommand.KIND_JUMP

## Records intent only. Nothing moves until step(), so every actor in a tick
## is integrated against the same world rather than against whatever the
## actors ahead of it in the command list happened to do first.
func handle(world: SimWorld, command: SimCommand) -> void:
	var stance: StanceCommand = command as StanceCommand
	if stance != null:
		var who: SimEntity = world.get_entity(stance.actor_id)
		if who == null or not who.is_actor():
			return
		# Intent only. Whether the actor is ACTUALLY crouched is decided in
		# step(), where there is a world to ask about headroom.
		who.crouch_intent = stance.wants_crouch
		return

	if command.kind == JumpCommand.KIND_JUMP:
		var jumper: SimEntity = world.get_entity(command.actor_id)
		if jumper == null or not jumper.is_actor():
			return
		# Recorded, not acted on. Whether the jump HAPPENS is decided in step(),
		# where feet-on-the-ground can be asked about - and the flag is cleared
		# there too, so an unusable jump is dropped rather than queued up to
		# fire the moment the actor next lands.
		jumper.jump_intent = true
		return

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
		actor.stance = SimEntity.Stance.STANDING
		return SimEntity.MotionState.HELD

	_resolve_stance(world, actor)
	_resolve_jump(world, actor)

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

	# AIRBORNE outranks the horizontal states, and is decided AFTER gravity
	# because that is the only thing that knows whether the body found ground.
	# A player walking off a balcony is airborne without ever pressing jump, and
	# a jumping player is airborne while still steering - so this is a property
	# of where the body is, not of which button was pressed.
	#
	# BLOCKED survives it: pushing into a wall in mid-air is still the state
	# presentation needs to show, and it is the more specific of the two.
	if not actor.is_grounded and state != SimEntity.MotionState.BLOCKED:
		return SimEntity.MotionState.AIRBORNE
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
##
## Crouching and carrying MULTIPLY rather than taking the lower of the two. A
## player crawling through a hatch with the cash is doing two slow things at
## once and should feel it; picking the cheaper of the two penalties would make
## the second one free.
func _speed_for(world: SimWorld, actor: SimEntity) -> float:
	if world.tuning == null:
		return 0.0
	var speed: float = world.tuning.move_speed
	if actor.is_carrying():
		speed *= world.tuning.carry_speed_scale
	if actor.stance == SimEntity.Stance.CROUCHED:
		speed *= world.tuning.crouch_speed_scale
	return speed

## The collision radius this body presents right now.
##
## THE BODY IS A SPHERE, and that is the constraint this whole verb is built
## around. WorldCollisionDef grows blockers by one radius and tests a POINT -
## there is no height anywhere in the collision model, so "the same body, but
## shorter" is not something the predicate can express. A crouched actor is
## therefore a SMALLER actor: one radius, reduced.
##
## Which is the correct reading rather than a workaround. The radius is already
## documented as doubling for the body's half-height, so shrinking it lowers the
## body's top by exactly the amount it lowers the body's sides - and a gap that
## admits the smaller sphere is precisely a gap the standing sphere does not
## fit through. What it does NOT model is a crouched body being narrower than it
## is short; that costs a second axis in the collision def, and nothing in the
## house needs it yet (WORLD_AUTHORING §12 sizes crouch gaps by height alone).
func _radius_for(world: SimWorld, actor: SimEntity) -> float:
	if world.tuning == null:
		return 0.0
	var radius: float = world.tuning.actor_radius
	if actor != null and actor.stance == SimEntity.Stance.CROUCHED:
		return radius * _crouch_radius_scale(world)
	return radius

## Crouched radius as a fraction of standing.
##
## THE COLLISION BODY IS A SPHERE OF `actor_radius`, WITH NO HEIGHT. That is
## the fact this whole verb has to be built around, and it is worth stating
## plainly because it makes the obvious derivation wrong: crouch_gap (130) and
## the visual body height (180) describe a capsule the simulation does not
## have. A standing body here is 40 units tall, top to bottom - so a "130 clear
## opening" admits it standing, and sizing a crawl space to §12's number would
## produce a tunnel everybody walks through upright.
##
## So the ratio is authored against what collision actually is. Halving the
## radius halves the body's height AND its width, which is the shape a sphere
## can express - and it is enough to make a gap that admits one and refuses the
## other, which is the only property the verb needs.
##
## The cost of the sphere model is that a crouched body is also NARROWER, so it
## fits through a slot too tight to walk. Nothing in the house is built to
## exploit that, and a proper capsule with separate height and radius is the
## real fix if it ever matters (WORLD_AUTHORING §12's numbers assume one).
const CROUCH_RADIUS_SCALE: float = 0.5

func _crouch_radius_scale(_world: SimWorld) -> float:
	return CROUCH_RADIUS_SCALE

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

## Decides whether the actor is crouched this tick.
##
## Two separate questions, and conflating them is the bug this is shaped to
## avoid. Going DOWN is always allowed: there is nothing to check, because a
## smaller body fits wherever the larger one did. Coming UP is not, because the
## thing the actor crouched to get under is still overhead - so standing is
## granted only when the standing body actually fits where it is.
##
## That asymmetry is the entire feel of the verb. Release the key under a
## counter and nothing happens until you have crawled out, which is what makes
## a crawl space a commitment rather than a corridor.
func _resolve_stance(world: SimWorld, actor: SimEntity) -> void:
	if actor.crouch_intent:
		if actor.stance != SimEntity.Stance.CROUCHED:
			# Feet stay where they are and the centre drops, mirroring the way
			# standing raises it. Without this the body would keep a standing
			# body's centre height while claiming a crouched radius, and would
			# hover half a radius off the floor until gravity caught up.
			var standing: float = world.tuning.actor_radius if world.tuning != null else 0.0
			var feet: float = actor.position.y - standing
			actor.position.y = feet + standing * CROUCH_RADIUS_SCALE
		actor.stance = SimEntity.Stance.CROUCHED
		return
	if actor.stance != SimEntity.Stance.CROUCHED:
		return
	# Wants up. Only if there is HEADROOM - which is a question about the space
	# above the body, not about the space it currently occupies.
	#
	# Testing the standing body where it stands does not work, and the reason is
	# worth writing down: a crouched body rests with its centre half a radius
	# above the floor, so re-testing that same centre at full radius asks
	# whether a standing body could stand with its middle at ankle height. It
	# could not - the floor is in the way - and the actor would be unable to
	# stand up anywhere at all, including open ground.
	#
	# So the test is the position the body would MOVE TO: feet stay put, centre
	# rises to one standing radius above them. Standing up is a small upward
	# move, and asking whether that move is legal is exactly _can_traverse's
	# job.
	if world.collision == null or world.tuning == null:
		actor.stance = SimEntity.Stance.STANDING
		return
	var standing: float = world.tuning.actor_radius
	var feet: float = actor.position.y - standing * CROUCH_RADIUS_SCALE
	var upright: Vector3 = Vector3(actor.position.x, feet + standing, actor.position.z)
	if world.collision.contains(upright, standing) 		and not world.collision.blocks_segment(actor.position, upright, standing):
		actor.stance = SimEntity.Stance.STANDING
		actor.position = upright

## Spends a jump request, if the actor is in a position to use one.
##
## WORLD_AUTHORING §5: "jump as an impulse". One shove at takeoff and the
## gravity integrator already in this file does everything after - no airborne
## accumulator, no hold-to-rise, nothing that needs a second integrator to stay
## in sync across two machines.
##
## The request is cleared whether or not it is granted. A jump pressed in
## mid-air is DROPPED, not remembered: queuing it would fire the moment the
## actor next touched down, which reads as the body jumping by itself a second
## after you asked.
##
## Crouched actors stand up first, and jump next tick if the button is still
## down. Springing from a crouch is a different verb with its own feel, and
## quietly granting it here would be that verb arriving by accident.
func _resolve_jump(world: SimWorld, actor: SimEntity) -> void:
	if not actor.jump_intent:
		return
	actor.jump_intent = false
	if not actor.is_grounded or actor.stance != SimEntity.Stance.STANDING:
		return
	if world.tuning == null or world.tuning.gravity <= 0.0:
		return # no gravity authored: a fixture, where jumping means nothing
	var speed: float = world.tuning.jump_speed
	if speed <= 0.0:
		return
	actor.velocity.y = speed
	# Off the ground THIS tick, not next: gravity runs after this and would
	# otherwise see a grounded actor and cancel the impulse it was just given.
	actor.is_grounded = false

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
		var radius: float = _radius_for(world, mover)
		if not world.collision.contains(to, radius):
			return false
		if world.collision.blocks_segment(from, to, radius):
			return false
	# Other bodies, last: geometry is the cheaper test and rules out most moves
	# before anyone has to be walked.
	return not _blocked_by_actor(world, mover, from, to)
