class_name ChaseCamera
extends RefCounted
## A third-person camera that follows one actor from behind and above.
##
## Purely presentational: it reads a position and a velocity and moves a
## Camera3D. It never writes simulation state, and nothing about where the
## camera points can change what the rules decide.
##
## The smoothing exists because the point of the grey-box is judging movement.
## A camera welded to the actor makes every stop feel identical, and a camera
## that lags too far turns a chase into a guess - so the lag is a tuned number
## rather than an accident of whatever felt fine on the day.

## How far behind, and how high above, the actor the camera sits.
const DISTANCE: float = 300.0
const HEIGHT: float = 170.0
## Where on the body the camera aims: above the feet, so the actor sits in the
## lower half of frame and the space being run into fills the rest.
const LOOK_HEIGHT: float = 60.0
## Higher converges faster. Framed as a rate rather than a per-frame fraction
## so the feel does not change with framerate.
const FOLLOW_RATE: float = 6.0
const TURN_RATE: float = 5.0
## Below this the actor is treated as stationary and the camera holds its
## heading, rather than snapping to whatever direction a dying velocity had.
const HEADING_EPSILON: float = 1.0

var camera: Camera3D = null

var _facing: Vector3 = Vector3.FORWARD
var _eye: Vector3 = Vector3.ZERO
var _aim: Vector3 = Vector3.ZERO
var _settled: bool = false

func _init(fov: float = 70.0) -> void:
	camera = Camera3D.new()
	camera.fov = fov
	camera.far = 8000.0

## Frame-rate independent exponential smoothing: the fraction of the remaining
## gap closed per second is constant, so a 30 Hz and a 144 Hz machine converge
## at the same real-world speed.
static func _approach(rate: float, delta: float) -> float:
	return 1.0 - exp(-rate * delta)

func follow(target: Vector3, velocity: Vector3, delta: float) -> void:
	var travel: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	if travel.length() > HEADING_EPSILON:
		var heading: Vector3 = travel.normalized()
		_facing = _facing.lerp(heading, _approach(TURN_RATE, delta)).normalized()

	var desired_eye: Vector3 = target - _facing * DISTANCE + Vector3.UP * HEIGHT
	var desired_aim: Vector3 = target + Vector3.UP * LOOK_HEIGHT

	if not _settled:
		# First frame, and after a respawn: start framed rather than flying in
		# from wherever the camera happened to be.
		_settled = true
		_eye = desired_eye
		_aim = desired_aim
	else:
		_eye = _eye.lerp(desired_eye, _approach(FOLLOW_RATE, delta))
		_aim = _aim.lerp(desired_aim, _approach(FOLLOW_RATE, delta))

	camera.global_position = _eye
	# look_at fails on a degenerate direction, which happens if the camera and
	# its target land on the same point.
	if _eye.distance_squared_to(_aim) > 0.001:
		camera.look_at(_aim, Vector3.UP)

## Reframes instantly on the next follow(), for a cut rather than a swoop.
func reset() -> void:
	_settled = false
