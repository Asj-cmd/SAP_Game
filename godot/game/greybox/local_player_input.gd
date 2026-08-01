class_name LocalPlayerInput
extends RefCounted
## One seat at the couch: a device, and the intent it is currently expressing.
##
## Polled every rendered frame, drained once per simulation tick. Those are
## different rates and must stay different - input arrives whenever the player
## moves a stick, and the simulation only cares at 30 Hz. Sampling input INSIDE
## the tick would quietly tie feel to the tick rate; sampling continuously and
## collapsing to one command per tick keeps the two independent.
##
## Produces intent. It never touches the world: presentation and input read
## simulation state and emit commands, and that is the entire contract (§1).

enum Device { KEYBOARD, GAMEPAD }

## Buttons are edge-triggered and latched, because a press between two ticks
## must not be lost - a 30 Hz tick is 33 ms and a tap can easily fall inside
## one.
var _capture_pressed: bool = false
var _carry_pressed: bool = false
var _rescue_pressed: bool = false

var device: Device = Device.KEYBOARD
var pad_id: int = 0
var actor_id: int = SimEntity.NO_ENTITY

## Last intent handed to the simulation, so a repeat is not re-sent. Intent
## persists in the sim, so re-stating it every tick would be pure noise.
var _last_sent: Vector3 = Vector3.ZERO
var _intent: Vector3 = Vector3.ZERO

const STICK_DEADZONE: float = 0.2

func _init(input_device: Device, joypad: int = 0) -> void:
	device = input_device
	pad_id = joypad

## Called every rendered frame.
func poll() -> void:
	_intent = _read_direction()
	if _read_button(KEY_E, JOY_BUTTON_A):
		_capture_pressed = true
	if _read_button(KEY_Q, JOY_BUTTON_X):
		_carry_pressed = true
	if _read_button(KEY_R, JOY_BUTTON_B):
		_rescue_pressed = true

## Screen-space intent, mapped to the world's ground plane. X is right, Z is
## away from the camera, which is the layout the fixed overhead view implies.
func _read_direction() -> Vector3:
	if device == Device.KEYBOARD:
		var x: float = 0.0
		var z: float = 0.0
		if Input.is_key_pressed(KEY_D):
			x += 1.0
		if Input.is_key_pressed(KEY_A):
			x -= 1.0
		if Input.is_key_pressed(KEY_S):
			z += 1.0
		if Input.is_key_pressed(KEY_W):
			z -= 1.0
		var keyed: Vector3 = Vector3(x, 0.0, z)
		# Normalised so diagonals are not faster than the cardinals, which is
		# the oldest movement bug there is.
		return keyed.normalized() if keyed.length_squared() > 1.0 else keyed

	var stick: Vector2 = Vector2(
		Input.get_joy_axis(pad_id, JOY_AXIS_LEFT_X),
		Input.get_joy_axis(pad_id, JOY_AXIS_LEFT_Y)
	)
	# A stick that never quite centres should read as released, or the actor
	# creeps forever and the movement feel test is judging drift.
	if stick.length() < STICK_DEADZONE:
		return Vector3.ZERO
	return Vector3(stick.x, 0.0, stick.y)

func _read_button(key: Key, button: JoyButton) -> bool:
	if device == Device.KEYBOARD:
		return Input.is_key_pressed(key)
	return Input.is_joy_button_pressed(pad_id, button)

## Drains one tick's worth of input into commands.
##
## At most one MoveCommand, and only when the intent actually changed -
## including the change to zero, which is what MoveCommand.stop() is for.
## Intent persists in the simulation, so silence means "carry on".
func drain(world: SimWorld, tick: int) -> Array[SimCommand]:
	var commands: Array[SimCommand] = []
	if actor_id == SimEntity.NO_ENTITY:
		return commands

	if not _intent.is_equal_approx(_last_sent):
		_last_sent = _intent
		if _intent == Vector3.ZERO:
			commands.append(MoveCommand.stop(actor_id, tick))
		else:
			commands.append(MoveCommand.move(actor_id, _intent, tick))

	# Targets are chosen here, by proximity, exactly as a bot director would
	# choose them. The simulation re-checks every condition, so a bad pick is
	# refused rather than trusted (§3).
	if _capture_pressed:
		_capture_pressed = false
		var enemy: int = _nearest(world, _is_capture_target, world.tuning.capture_range)
		if enemy != SimEntity.NO_ENTITY:
			commands.append(CaptureCommand.capture(actor_id, enemy, tick))

	if _rescue_pressed:
		_rescue_pressed = false
		var ally: int = _nearest(world, _is_rescue_target, world.tuning.rescue_range)
		if ally != SimEntity.NO_ENTITY:
			commands.append(CaptureCommand.release(actor_id, ally, tick))

	if _carry_pressed:
		_carry_pressed = false
		var me: SimEntity = world.get_entity(actor_id)
		if me != null and me.is_carrying():
			commands.append(CarryCommand.drop(actor_id, tick))
		else:
			var loot: int = _nearest(world, _is_carriable_target, world.tuning.pickup_range)
			if loot != SimEntity.NO_ENTITY:
				commands.append(CarryCommand.pick_up(actor_id, loot, tick))

	return commands

func _nearest(world: SimWorld, predicate: Callable, range_limit: float) -> int:
	var me: SimEntity = world.get_entity(actor_id)
	if me == null:
		return SimEntity.NO_ENTITY
	var best: int = SimEntity.NO_ENTITY
	var best_distance: float = range_limit * range_limit
	for entity_id: int in world.sorted_entity_ids():
		var candidate: SimEntity = world.entities[entity_id]
		if entity_id == actor_id or not predicate.call(me, candidate):
			continue
		var distance: float = me.position.distance_squared_to(candidate.position)
		if distance <= best_distance:
			best_distance = distance
			best = entity_id
	return best

func _is_capture_target(me: SimEntity, other: SimEntity) -> bool:
	return other.is_actor() and other.team != me.team and not other.is_captured

func _is_rescue_target(me: SimEntity, other: SimEntity) -> bool:
	return other.is_actor() and other.team == me.team and other.is_captured

func _is_carriable_target(_me: SimEntity, other: SimEntity) -> bool:
	return other.is_carriable() and not other.is_held()
