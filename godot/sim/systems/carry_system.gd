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

func phase() -> SimSystem.Phase:
	return SimSystem.Phase.INTERACTION

func system_name() -> StringName:
	return &"CarrySystem"

func handles(kind: StringName) -> bool:
	return kind == CarryCommand.KIND_PICK_UP or kind == CarryCommand.KIND_DROP

func handle(world: SimWorld, command: SimCommand) -> void:
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
		if not carriable.is_carriable() or not carriable.is_held():
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
