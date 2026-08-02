extends SceneTree
## The control scheme, and the level scale it has to work at.
##
##   godot --headless --path godot --script res://tests/camera_controls_test.gd
##
## Two things worth a regression test. First, that look and move are
## INDEPENDENT: the camera must never be rotated by where the actor is going,
## because camera-relative movement plus camera-follows-movement is a feedback
## loop that spins. Second, that traversal times stayed in their intended band
## after the rescale - "feels right" is otherwise a claim nobody can check.

const EXPECTED_CHECKS: int = 16

var _passed: int = 0
var _failed: int = 0
var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	print("=== Camera + controls ===")
	_test_look_is_independent_of_movement()
	_test_camera_relative_travel()
	_test_scale_and_pace()

	if _passed + _failed != EXPECTED_CHECKS:
		_failed += 1
		_failures.append("harness: ran %d checks, expected %d - a case was skipped"
			% [_passed + _failed, EXPECTED_CHECKS])
	print("\n%d passed, %d failed" % [_passed, _failed])
	if _failed > 0:
		print("\nFAILURES:")
		for failure: String in _failures:
			print("  - %s" % failure)
	quit(1 if _failed > 0 else 0)

func _check(case_name: String, actual: Variant, expected: Variant) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		_failures.append("%s: expected %s, got %s" % [case_name, expected, actual])

func _close(case_name: String, actual: float, expected: float, tolerance: float) -> void:
	if absf(actual - expected) <= tolerance:
		_passed += 1
	else:
		_failed += 1
		_failures.append("%s: expected ~%f (+/-%f), got %f" % [case_name, expected, tolerance, actual])

# ---- the feedback loop that must not exist ----

func _test_look_is_independent_of_movement() -> void:
	var chase: ChaseCamera = ChaseCamera.new()
	var before: Vector3 = chase.forward()

	# Travelling does not turn the camera. This is the whole fix: the previous
	# rig derived facing from velocity, which spins once movement is expressed
	# relative to that same facing.
	chase.intent_from(Vector2(1.0, -1.0))
	chase.intent_from(Vector2(-1.0, 1.0))
	_check("look/travel does not rotate the camera", chase.forward(), before)

	# Only look input rotates it.
	chase.aim(0.5, 0.0)
	_check("look/aiming does rotate it", chase.forward() != before, true)

	# Pitch is clamped at both ends, so the camera cannot roll over the top or
	# bury itself in the ground.
	for i: int in 200:
		chase.aim(0.0, 1.0)
	_check("look/pitch stops going down", chase._pitch >= ChaseCamera.PITCH_MIN - 0.001, true)
	for i: int in 400:
		chase.aim(0.0, -1.0)
	_check("look/pitch stops going up", chase._pitch <= ChaseCamera.PITCH_MAX + 0.001, true)

	# Pitch must not tilt the ground plane the actor walks on.
	var level_forward: Vector3 = chase.forward()
	_close("look/forward stays level however far you tilt", level_forward.y, 0.0, 0.0001)
	chase.rig.free()

# ---- camera-relative travel ----

func _test_camera_relative_travel() -> void:
	var chase: ChaseCamera = ChaseCamera.new()

	# Facing default (-Z): pushing forward travels -Z, pushing right travels +X.
	var ahead: Vector3 = chase.intent_from(Vector2(0.0, -1.0))
	_close("travel/forward is where the camera looks (z)", ahead.z, -1.0, 0.001)
	var sideways: Vector3 = chase.intent_from(Vector2(1.0, 0.0))
	_close("travel/right is the camera's right (x)", sideways.x, 1.0, 0.001)

	# Turn a quarter turn and forward turns with it. This is what makes "run
	# away while watching the door behind you" expressible.
	#
	# A positive yaw delta is a mouse moved RIGHT, and turning right from a
	# default facing of -Z points the actor at +X. Getting this sign backwards
	# gives inverted look, which is the kind of thing that reads as "the
	# controls feel wrong" without anyone being able to say why.
	chase.aim(PI * 0.5, 0.0)
	var turned: Vector3 = chase.intent_from(Vector2(0.0, -1.0))
	_close("travel/turning right points forward east", turned.x, 1.0, 0.001)
	_close("travel/and leaves the old axis", turned.z, 0.0, 0.001)

	# Travel never has a vertical component, whatever the pitch: aiming at the
	# floor must not walk the actor into it.
	chase.aim(0.0, -10.0)
	_close("travel/never points up or down", chase.intent_from(Vector2(0.3, -0.8)).y, 0.0, 0.0001)

	# A diagonal is not faster than a cardinal.
	var diagonal: Vector3 = chase.intent_from(Vector2(1.0, -1.0))
	_check("travel/diagonals are not faster", diagonal.length() <= 1.001, true)
	chase.rig.free()

# ---- scale and pace ----

## Rooms are sized around the camera's standoff, so the check that matters is
## whether crossing one still takes a sensible amount of time. Both bounds are
## real failures: too fast and rooms read as corridors, too slow and a chase
## through a house becomes a walk.
func _test_scale_and_pace() -> void:
	var level: GreyBoxLevel = GreyBoxLevel.new()
	_check("scale/level loaded", level.is_loaded(), true)
	if not level.is_loaded():
		return

	var room: ZoneDef = level.sheltered_zone()
	var room_width: float = room.bounds.size.x
	var seconds_to_cross: float = room_width / level.tuning.move_speed

	# A room must be several arm-lengths across or the camera lives in a wall.
	_check("scale/room is wider than the camera arm",
		room_width > ChaseCamera.ARM_LENGTH * 1.5, true)
	_check("scale/crossing a room takes over a second", seconds_to_cross > 1.0, true)
	_check("scale/and under three", seconds_to_cross < 3.0, true)

	# A doorway has to admit a body with room to spare, or chases end by
	# getting stuck rather than by being caught.
	_check("scale/actor fits through with margin",
		level.tuning.actor_radius * 2.0 < 240.0 * 0.5, true)
