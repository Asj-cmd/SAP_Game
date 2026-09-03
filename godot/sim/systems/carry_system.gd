class_name CarrySystem
extends SimSystem
## Picking things up, and putting them down. See ARCHITECTURE.md §5.
##
## Deliberately has no notion of "deposit". ScoringSystem already derives a
## team's holdings from where the carriables ARE, so banking cash is dropping
## it in the right room - a position, not an event this system has to know
## about. That keeps the two systems independent: a mode that scores by some
## other rule changes ScoringSystem and nothing here.
##
## Carrying is also what ends safe-room shelter under
## ZoneDef.safe_ends_on_pickup, so this system is what makes variant A a
## playable rule rather than a setting nothing can trigger.

## Bisection steps used to settle a thrown bundle against geometry. Fixed
## rather than tolerance-driven, for the reason MovementSystem gives: a loop
## that runs until it is "close enough" runs a different number of times on
## different inputs, and the simulation is built on doing the same work every
## time.
const FLIGHT_SWEEP_STEPS: int = 12

func phase() -> SimSystem.Phase:
	return SimSystem.Phase.INTERACTION

func system_name() -> StringName:
	return &"CarrySystem"

func handles(kind: StringName) -> bool:
	return kind == CarryCommand.KIND_PICK_UP 		or kind == CarryCommand.KIND_DROP 		or kind == ThrowCommand.KIND_THROW

func handle(world: SimWorld, command: SimCommand) -> void:
	var thrown: ThrowCommand = command as ThrowCommand
	if thrown != null:
		_try_throw(world, thrown)
		return

	var carry: CarryCommand = command as CarryCommand
	if carry == null:
		return
	if carry.kind == CarryCommand.KIND_PICK_UP:
		_try_pick_up(world, carry)
	else:
		_try_drop(world, carry)

## Carried things travel with their carrier.
##
## Position is copied rather than offset: where a prop actually sits in the
## carrier's hands is presentation's business, and an offset here would be a
## rule quietly encoding how the game looks.
func step(world: SimWorld) -> void:
	for entity_id: int in world.sorted_entity_ids():
		var carriable: SimEntity = world.entities[entity_id]
		if not carriable.is_carriable():
			continue
		if carriable.in_flight:
			_advance_flight(world, carriable)
			continue
		if not carriable.is_held():
			continue
		var carrier: SimEntity = world.get_entity(carriable.carried_by)
		if carrier == null:
			# The carrier is gone. Leave the carriable where it stands rather
			# than orphaned in a held state nothing will ever release.
			carriable.carried_by = SimEntity.NO_ENTITY
			continue
		carriable.position = carrier.position

func _try_pick_up(world: SimWorld, command: CarryCommand) -> void:
	var actor: SimEntity = world.get_entity(command.actor_id)
	var carriable: SimEntity = world.get_entity(command.target_id)
	if actor == null or carriable == null:
		return
	if not actor.is_actor() or not carriable.is_carriable():
		return
	if actor.is_captured or actor.is_carrying():
		return
	# Already in somebody's hands, including this actor's.
	if carriable.is_held():
		return
	if actor.position.distance_squared_to(carriable.position) > _pickup_range_squared(world):
		return

	actor.carrying_id = carriable.id
	carriable.carried_by = actor.id
	carriable.position = actor.position
	world.emit(CarryEvent.picked_up(world.tick, actor.id, carriable.id))

func _try_drop(world: SimWorld, command: CarryCommand) -> void:
	var actor: SimEntity = world.get_entity(command.actor_id)
	if actor == null or not actor.is_carrying():
		return
	var carriable: SimEntity = world.get_entity(actor.carrying_id)
	var dropped_id: int = actor.carrying_id
	actor.carrying_id = SimEntity.NO_ENTITY
	if carriable != null:
		carriable.carried_by = SimEntity.NO_ENTITY
		carriable.position = actor.position
	world.emit(CarryEvent.dropped(world.tick, actor.id, dropped_id))

## Squared, like every other range check: comparing distances never needs the
## square root (ARCHITECTURE.md §6).
func _pickup_range_squared(world: SimWorld) -> float:
	if world.tuning == null:
		return 0.0
	return world.tuning.pickup_range * world.tuning.pickup_range

## Throws what an actor is holding, along a fixed arc in a chosen direction.
##
## THE HIGHEST-VALUE VERB not yet built, per DESIGN_DIRECTION §5: it creates
## teamwork with no coordination system - chuck the cash over the fence and a
## team-mate runs it in - it creates risk, and it removes any need for bespoke
## cash-moving contraptions. A dumbwaiter was cut for exactly this reason.
##
## The arc is FIXED. The player chooses which way to face; throw_lift decides
## how steeply it leaves the hand and throw_speed how hard. Nothing here rewards
## aim, which is the design constraint the whole verb list is written under -
## party games break when they reward mechanical skill.
func _try_throw(world: SimWorld, command: ThrowCommand) -> void:
	var actor: SimEntity = world.get_entity(command.actor_id)
	if actor == null or not actor.is_actor() or not actor.is_carrying():
		return
	if actor.is_captured:
		return # a held actor keeps hold of what it was carrying
	var carriable: SimEntity = world.get_entity(actor.carrying_id)
	if carriable == null:
		return
	if world.tuning == null or world.tuning.throw_speed <= 0.0:
		return

	# Horizontal only, then lifted. An aim that points at the sky throws no
	# higher and one that points at the floor throws no lower: the arc belongs
	# to the game, the direction belongs to the player.
	var aim: Vector3 = Vector3(command.direction.x, 0.0, command.direction.z)
	if aim.length_squared() <= 0.0:
		return
	aim = aim.normalized()

	var thrown_id: int = actor.carrying_id
	actor.carrying_id = SimEntity.NO_ENTITY
	carriable.carried_by = SimEntity.NO_ENTITY
	carriable.position = actor.position
	carriable.in_flight = true
	var speed: float = world.tuning.throw_speed
	carriable.velocity = aim * speed + Vector3.UP * (speed * world.tuning.throw_lift)
	# A throw IS a drop as far as every other rule is concerned - the cash has
	# left this actor's hands, safe-room shelter ends, and scoring re-derives
	# from where it comes to rest. Emitting the same event keeps those rules
	# from having to learn a second way to lose hold of something.
	world.emit(CarryEvent.dropped(world.tick, actor.id, thrown_id))

## Carries a thrown bundle one tick along its arc.
##
## NOT A PHYSICS BODY. ARCHITECTURE §2 keeps physics out of the rules because it
## is not bit-identical across platforms and so cannot be lockstepped - but a
## ballistic arc integrated at the fixed timestep against the same swept
## collision every other movement uses is not physics, it is arithmetic. It
## rolls back and replays like anything else in the simulation.
##
## No bounce and no roll. It stops where it first hits something, which is the
## readable outcome - a bundle that skitters under furniture is a bundle nobody
## can find, and the verb is about passing cash to people rather than about
## simulating parcels.
##
## A TOSS, not a delivery. Nothing here knows or cares who the thrower meant it
## for: the bundle lands on the ground where the arc ends and lies there until
## somebody walks over and picks it up with the ordinary pickup rule. Passing to
## a team-mate is therefore two players choosing to cooperate rather than a
## mechanic that finds a receiver, which is the whole reason the verb creates
## teamwork without a coordination system (DESIGN_DIRECTION §5).
func _advance_flight(world: SimWorld, carriable: SimEntity) -> void:
	var gravity: float = world.tuning.gravity if world.tuning != null else 0.0
	if gravity > 0.0:
		carriable.velocity.y = maxf(
			carriable.velocity.y - gravity * SimWorld.SECONDS_PER_TICK,
			-world.tuning.terminal_fall_speed)

	var step: Vector3 = carriable.velocity * SimWorld.SECONDS_PER_TICK
	if step == Vector3.ZERO:
		_land(carriable)
		return

	var to: Vector3 = carriable.position + step
	if world.collision != null 		and (not world.collision.contains(to, 0.0) 			or world.collision.blocks_segment(carriable.position, to, 0.0)):
		# Hit something. Come to rest at the last clear point rather than
		# inside it - the same bisection MovementSystem settles a blocked move
		# with, so a thrown bundle lands exactly where a walking body would
		# have stopped.
		carriable.position = _last_clear(world, carriable.position, step)
		_land(carriable)
		return
	carriable.position = to

## The furthest point along `step` that is still clear of geometry.
func _last_clear(world: SimWorld, from: Vector3, step: Vector3) -> Vector3:
	var reachable: float = 0.0
	var blocked: float = 1.0
	for i: int in FLIGHT_SWEEP_STEPS:
		var middle: float = (reachable + blocked) * 0.5
		var probe: Vector3 = from + step * middle
		if world.collision.contains(probe, 0.0) 			and not world.collision.blocks_segment(from, probe, 0.0):
			reachable = middle
		else:
			blocked = middle
	return from + step * reachable

func _land(carriable: SimEntity) -> void:
	carriable.in_flight = false
	carriable.velocity = Vector3.ZERO
