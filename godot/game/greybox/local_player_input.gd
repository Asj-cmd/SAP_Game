class_name LocalPlayerInput
extends RefCounted
## One seat: a device, a camera, and the intent the two of them express.
##
## Movement is CAMERA-RELATIVE. Forward is wherever the camera is looking, not
## a fixed world axis, which is what makes look and move independent - you can
## back away from a doorway while watching it, or edge round a corner without
## turning to face the way you are travelling.
##
## Polled every rendered frame, drained once per simulation tick. Those are
## different rates and must stay different: input arrives whenever a stick
## moves, and the simulation only cares at 30 Hz. Sampling inside the tick
## would tie feel to the tick rate.
##
## Emits commands. It never touches the world.

enum Device { KEYBOARD_MOUSE, GAMEPAD }

const STICK_DEADZONE: float = 0.2

var device: Device = Device.KEYBOARD_MOUSE
var pad_id: int = 0
var actor_id: int = SimEntity.NO_ENTITY
var camera: ChaseCamera = null

## Buttons are edge-latched: a tap between two ticks must not be lost, and a
## 30 Hz tick is 33 ms - comfortably shorter than a deliberate press.
var _capture_pressed: bool = false
var _carry_pressed: bool = false
var _rescue_pressed: bool = false

## Mouse motion accrues from events between frames rather than being polled.
var _mouse_motion: Vector2 = Vector2.ZERO

var _intent: Vector3 = Vector3.ZERO
## Last intent handed to the simulation. Intent persists there, so re-sending
## an unchanged one every tick would be noise.
var _last_sent: Vector3 = Vector3.ZERO

func _init(input_device: Device, joypad: int = 0) -> void:
	device = input_device
	pad_id = joypad

func add_mouse_motion(motion: Vector2) -> void:
	if device == Device.KEYBOARD_MOUSE:
		_mouse_motion += motion

## Called every rendered frame: aims the camera, then reads travel relative to
## where it now points.
func poll(delta: float) -> void:
	if camera == null:
		return

	if device == Device.KEYBOARD_MOUSE:
		camera.aim_from_mouse(_mouse_motion)
		_mouse_motion = Vector2.ZERO
	else:
		camera.aim_from_stick(Vector2(
			Input.get_joy_axis(pad_id, JOY_AXIS_RIGHT_X),
			Input.get_joy_axis(pad_id, JOY_AXIS_RIGHT_Y)
		), delta)

	_intent = camera.intent_from(_read_travel())

	if _read_button(KEY_E, JOY_BUTTON_A):
		_capture_pressed = true
	if _read_button(KEY_Q, JOY_BUTTON_X):
		_carry_pressed = true
	if _read_button(KEY_R, JOY_BUTTON_B):
		_rescue_pressed = true

## Screen-relative travel: +x right, -y forward. Turned into world space by
## the camera.
func _read_travel() -> Vector2:
	if device == Device.KEYBOARD_MOUSE:
		var keyed: Vector2 = Vector2(
			float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
			float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
		)
		# Normalised so a diagonal is not faster than a cardinal.
		return keyed.normalized() if keyed.length_squared() > 1.0 else keyed

	var stick: Vector2 = Vector2(
		Input.get_joy_axis(pad_id, JOY_AXIS_LEFT_X),
		Input.get_joy_axis(pad_id, JOY_AXIS_LEFT_Y)
	)
	# A stick that never quite centres should read as released, or the actor
	# creeps forever and the movement test is judging drift.
	return Vector2.ZERO if stick.length() < STICK_DEADZONE else stick

func _read_button(key: Key, button: JoyButton) -> bool:
	if device == Device.KEYBOARD_MOUSE:
		return Input.is_key_pressed(key)
	return Input.is_joy_button_pressed(pad_id, button)

## Drains one tick's worth of input into commands.
##
## At most one MoveCommand, and only when the intent actually changed -
## including the change to zero, which is what MoveCommand.stop() is for.
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

	# Targets are chosen here by proximity, exactly as a bot director would
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

func device_name() -> String:
	return "mouse + keys" if device == Device.KEYBOARD_MOUSE else "pad %d" % pad_id
