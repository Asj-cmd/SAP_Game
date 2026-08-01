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
func _resolve(world: SimWorld, actor: SimEntity) -> SimEntity.MotionState:
	if actor.is_captured:
		actor.velocity = Vector3.ZERO
		return SimEntity.MotionState.HELD

	if actor.move_intent.length_squared() < INTENT_DEADZONE_SQUARED:
		actor.velocity = Vector3.ZERO
		return SimEntity.MotionState.IDLE

	var speed: float = _speed_for(world, actor)
	actor.velocity = actor.move_intent * speed
	var moved: bool = _apply_displacement(world, actor, actor.velocity * SimWorld.SECONDS_PER_TICK)
	if moved:
		return SimEntity.MotionState.MOVING

	# Wanted to move and could not: distinct from standing still, and
	# presentation wants to show it differently.
	actor.velocity = Vector3.ZERO
	return SimEntity.MotionState.BLOCKED

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

	if _can_traverse(world, actor.position, actor.position + delta):
		actor.position += delta
		return true

	var moved: bool = false
	for axis: int in 3:
		var single_axis: Vector3 = Vector3.ZERO
		single_axis[axis] = delta[axis]
		if single_axis == Vector3.ZERO:
			continue
		if _can_traverse(world, actor.position, actor.position + single_axis):
			actor.position += single_axis
			moved = true
	return moved

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
func _can_traverse(world: SimWorld, from: Vector3, to: Vector3) -> bool:
	if world.collision == null:
		return true # no geometry authored: an open plane, fixtures only
	var radius: float = world.tuning.actor_radius if world.tuning != null else 0.0
	if not world.collision.contains(to, radius):
		return false
	return not world.collision.blocks_segment(from, to, radius)
