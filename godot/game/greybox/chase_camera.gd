class_name ChaseCamera
extends RefCounted
## Standard third-person rig: a yaw pivot at the actor, a pitch pivot, a spring
## arm, and the camera on the end of it.
##
## Rotation comes from the LOOK input and from nothing else. The previous
## version derived facing from the actor's velocity, which is a feedback loop
## the moment movement becomes camera-relative: the camera turns to face where
## you are going, which changes where forward is, which turns the camera. Look
## and move have to be independent, and online they have to be independent for
## the further reason that hiding, peeking and checking a corner are all things
## you do while standing still or walking the other way.
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

var rig: Node3D = null
var camera: Camera3D = null

var _pitch_pivot: Node3D = null
var _arm: SpringArm3D = null
var _yaw: float = 0.0
var _pitch: float = deg_to_rad(-12.0)
var _settled: bool = false

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
	_yaw = wrapf(_yaw - delta_yaw, -PI, PI)
	_pitch = clampf(_pitch - delta_pitch, PITCH_MIN, PITCH_MAX)
	rig.rotation = Vector3(0.0, _yaw, 0.0)
	_pitch_pivot.rotation = Vector3(_pitch, 0.0, 0.0)

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
