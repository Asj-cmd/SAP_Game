class_name ChaseCamera
extends RefCounted
## Standard third-person rig: a yaw pivot at the actor, a pitch pivot, a spring
## arm, and the camera on the end of it.
##
## Rotation comes from the LOOK input, and - only when the player has let go of
## it - eases back to behind the body.
##
## The previous version derived facing from the actor's velocity outright, which
## is a feedback loop the moment movement becomes camera-relative: the camera
## turns to face where you are going, which changes where forward is, which
## turns the camera. That is still forbidden. What is here instead is a RECENTRE
## that only runs while the look input is idle, so it can never fight the player
## for the yaw:
##
##   mouse moving          free look, untouched
##   mouse idle, running   eases to behind the body over RECENTRE_DELAY
##   standing still        stays exactly where it was left
##
## The travelling case is the one that needed fixing - reported from the chair
## as "the third-person view does not fix to the back of the character". The
## standing case is deliberately left alone, because hiding, peeking and
## checking a corner are all things you do while stationary or walking the other
## way, and taking those away to fix the running case would cost more than it
## bought.
##
## Presentation only. It reads a position and moves a Camera3D; nothing it does
## can change what the rules decide.

## Near and far, named because the ratio between them is load-bearing.
##
## Godot's default near is 0.05, which against a 12,000 far plane is a range of
## 240,000:1 - far past what a depth buffer resolves, and the whole world
## z-fights itself into noise. Ten costs nothing here because the camera sits
## three metres behind a body and never has anything closer.
const NEAR_PLANE: float = 10.0
const FAR_PLANE: float = 12000.0

## Distance and height are in world units - 1 unit = 1 cm, so this arm is 3.5 m.
## Rooms are sized around this number rather than the other way round; see
## WORLD_AUTHORING.md on room dimensions.
const ARM_LENGTH: float = 350.0
## Aimed at chest height rather than the origin, so the actor sits low in frame
## and the space being run into fills the rest of it.
const PIVOT_HEIGHT: float = 120.0
## Keeps the camera off the actor's shoulder when the arm is fully compressed.
const PROBE_RADIUS: float = 18.0

const PITCH_MIN: float = deg_to_rad(-60.0)
const PITCH_MAX: float = deg_to_rad(25.0)
const MOUSE_SENSITIVITY: float = 0.0022
const STICK_SENSITIVITY: float = 2.6
const STICK_DEADZONE: float = 0.15

## How fast the rig catches up to the body. The rig follows POSITION only, so
## this smooths travel without ever smearing the player's aim.
const FOLLOW_RATE: float = 18.0

## Recentring, all three parts of it.
##
## How long the look input must be QUIET before the camera starts easing back.
## Long enough that finishing a deliberate look does not immediately undo it,
## short enough that it feels like the camera helping rather than resisting.
const RECENTRE_DELAY: float = 0.55
## How fast it eases once it starts, per second. Exponential, so it is fastest
## when most wrong and settles without overshoot.
const RECENTRE_RATE: float = 3.4
## How hard the body must be travelling before recentring applies at all, as a
## fraction of walking speed. A player nudging a stick to reposition is not
## running, and the camera should leave them alone.
const RECENTRE_MOVING: float = 0.35

var rig: Node3D = null
var camera: Camera3D = null

var _pitch_pivot: Node3D = null
var _arm: SpringArm3D = null
var _yaw: float = 0.0
var _pitch: float = deg_to_rad(-12.0)
var _settled: bool = false
## Seconds since the look input last moved. Drives the recentre delay.
var _quiet: float = 0.0

func _init(collision_mask: int = 2) -> void:
	rig = Node3D.new()

	_pitch_pivot = Node3D.new()
	_pitch_pivot.position = Vector3(0.0, PIVOT_HEIGHT, 0.0)
	rig.add_child(_pitch_pivot)

	_arm = SpringArm3D.new()
	_arm.spring_length = ARM_LENGTH
	# A sphere rather than a ray, so the camera eases away from a corner
	# instead of snapping through it the instant the ray misses.
	var probe: SphereShape3D = SphereShape3D.new()
	probe.radius = PROBE_RADIUS
	_arm.shape = probe
	# Its own layer: these bodies exist for the camera and nothing else. The
	# simulation has its own collision and never consults physics (§6).
	_arm.collision_mask = collision_mask
	_pitch_pivot.add_child(_arm)

	camera = Camera3D.new()
	camera.fov = 75.0
	# Both planes are set together and neither is a default, because at 1 unit =
	# 1 cm the engine's 0.05 near plane means 0.5 mm - a 240,000:1 depth range
	# against this far plane. That spends almost all of the depth buffer on the
	# first half-metre and leaves the rest of the level fighting over what is
	# left, which shows up as walls flickering through each other and is far
	# worse on gl_compatibility. 10 units is 10 cm: closer than the arm can ever
	# compress to, so nothing is ever clipped by it.
	camera.near = NEAR_PLANE
	camera.far = FAR_PLANE
	_arm.add_child(camera)

## Applies look input. Yaw is unbounded; pitch is clamped so the camera cannot
## roll over the top or bury itself in the floor.
func aim(delta_yaw: float, delta_pitch: float) -> void:
	if not is_zero_approx(delta_yaw) or not is_zero_approx(delta_pitch):
		_quiet = 0.0
	_yaw = wrapf(_yaw - delta_yaw, -PI, PI)
	_pitch = clampf(_pitch - delta_pitch, PITCH_MIN, PITCH_MAX)
	rig.rotation = Vector3(0.0, _yaw, 0.0)
	_pitch_pivot.rotation = Vector3(_pitch, 0.0, 0.0)

## Eases the yaw back to behind `facing`, when the player is running and has not
## touched the look input recently.
##
## `facing` is the body's direction of travel, flattened. It is passed in rather
## than read, because this class never sees the simulation - presentation hands
## it a vector and it turns a rig (§1).
func recentre(facing: Vector3, speed_fraction: float, delta: float) -> void:
	_quiet += delta
	if _quiet < RECENTRE_DELAY or speed_fraction < RECENTRE_MOVING:
		return
	var flat: Vector2 = Vector2(facing.x, facing.z)
	if flat.length_squared() <= 0.0:
		return
	# The yaw that puts the camera BEHIND the body: looking the way it travels.
	var wanted: float = atan2(-flat.x, -flat.y)
	# Shortest way round, so a body facing just past -PI does not spin the long
	# way to reach it.
	var gap: float = wrapf(wanted - _yaw, -PI, PI)
	_yaw = wrapf(_yaw + gap * minf(1.0, RECENTRE_RATE * delta), -PI, PI)
	rig.rotation = Vector3(0.0, _yaw, 0.0)

## The current yaw. Exposed for a probe, and for nothing in the game - the rig's
## own rotation is the thing that matters.
func yaw_for_test() -> float:
	return _yaw

func aim_from_mouse(motion: Vector2) -> void:
	aim(motion.x * MOUSE_SENSITIVITY, motion.y * MOUSE_SENSITIVITY)

func aim_from_stick(stick: Vector2, delta: float) -> void:
	if stick.length() < STICK_DEADZONE:
		return
	aim(stick.x * STICK_SENSITIVITY * delta, stick.y * STICK_SENSITIVITY * delta)

## Moves the rig to the body. Position only - never rotation.
##
## Writes the LOCAL position, for the same reason forward() reads the local
## basis: global_position is only meaningful for a node inside the tree, and
## reading it outside one silently yields the origin - which here would park the
## camera in the corner of the level pointing at nothing, with no error to say
## so. The baker was bitten by exactly this. The rig is parented directly to a
## Viewport, which has no transform of its own, so local and global agree and
## the tree-residency question never arises.
func follow(target: Vector3, delta: float) -> void:
	if not _settled:
		_settled = true
		rig.position = target
		return
	var blend: float = 1.0 - exp(-FOLLOW_RATE * delta)
	rig.position = rig.position.lerp(target, blend)

## Where the camera actually ended up, for the debug read-out. Falls back to the
## rig when the camera is not in a tree, since global_position would read zero.
func world_position() -> Vector3:
	if camera == null or not camera.is_inside_tree():
		return rig.position
	return camera.global_position

## Ground-plane basis the player's movement is expressed in.
##
## Taken from the YAW pivot, so looking up or down never changes which way
## forward is - tilting the camera to look at a doorway must not make the
## actor walk into the floor.
##
## Read from the LOCAL basis. The rig hangs off a root at identity so the two
## agree, and a local read works on a rig that is not inside a tree, which is
## what lets the movement basis be tested without standing up a scene.
func forward() -> Vector3:
	return -rig.transform.basis.z

func right() -> Vector3:
	return rig.transform.basis.x

## Converts a stick or key vector into world-space travel intent.
func intent_from(input: Vector2) -> Vector3:
	var travel: Vector3 = right() * input.x + forward() * -input.y
	travel.y = 0.0
	if travel.length_squared() > 1.0:
		travel = travel.normalized()
	return travel

func reset() -> void:
	_settled = false
