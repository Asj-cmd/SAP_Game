class_name BundleTumble
extends RefCounted

## A loose cash bundle tumbles end over end while it flies and hops twice when
## it lands (P4-5, D9: "bundle tumbles and bounces a little").
##
## PRESENTATION ONLY. The sim's bundle is a point on a fixed arc that stops
## where it first hits (CarrySystem: no bounce, no roll), and that stays the
## truth: the drawn bundle is at the sim's x/z on every frame and at the sim's
## y whenever it is at rest. This adds a drawn spin while `in_flight`, and on
## the frame the flight ends a short lift off the resting point (never below
## it) while the spin eases to the nearest FLAT pose, so it always ends lying
## flat exactly where the sim put it. Read from the CONFIRMED world, so a guest
## draws the same. Held = no state at all: `_hold_carried` owns the bundle.
##
## Undo: SPIN_THROW = SPIN_DROP = 0 and BOUNCE_PEAK_MAX = 0.

## Spin while thrown (flat speed at release >= DROP_FLAT_SPEED), degrees/s:
## about 1.5 turns over a full arc.
const SPIN_THROW: float = 540.0
## Spin of a drop or a seized carrier's bundle (falls straight down), degrees/s.
const SPIN_DROP: float = 135.0
## Under this flat speed at release, a let-go counts as a drop.
const DROP_FLAT_SPEED: float = 40.0
## First hop: peak = clamp(landing speed x BOUNCE_PER_SPEED, MIN, MAX) units.
const BOUNCE_PER_SPEED: float = 0.02
const BOUNCE_PEAK_MIN: float = 4.0
const BOUNCE_PEAK_MAX: float = 14.0
## A drop's landing speed counts for this much (it falls from the carrier's
## centre, so its sim speed says "thrown down" when the hands only let go).
const BOUNCE_DROP_SCALE: float = 0.4
## First hop's length, s; the second is SECOND_SHARE as high over SECOND_TIME.
const BOUNCE_TIME: float = 0.22
const SECOND_SHARE: float = 0.3
const SECOND_TIME: float = 0.12

class State:
	extends RefCounted
	## Yaw the bundle had when it left the hands (its resting yaw).
	var yaw: float = 0.0
	## World axis it spins about (horizontal), and the angle so far, radians.
	var axis: Vector3 = Vector3.RIGHT
	var angle: float = 0.0
	var rate: float = 0.0
	var dropped: bool = false
	var flying: bool = false
	## Speed on the last in-flight state seen.
	var speed: float = 0.0
	## Bounce: time since landing (< 0 = not bouncing), first peak, eased spin.
	var since_landing: float = -1.0
	var peak: float = 0.0
	var landed_angle: float = 0.0
	var rest_angle: float = 0.0

var _states: Dictionary[int, State] = {}

## Per frame per loose bundle. `yaw` is the bundle's drawn yaw now (used when a
## flight starts). Returns {active: bool, lift: float, basis: Basis}; inactive
## means draw it as before (no tumble state: never thrown, or held).
## `settling`: the drawn bundle is still being eased from the hands onto the
## sim's arc (P4-2's release blend). A drop lands in the sim (from the carrier's
## centre, 20 up) while the drawn one is still coming down from the hands, so
## the landing waits for the blend; otherwise the hop is spent in mid-air.
func update(id: int, entity: SimEntity, yaw: float, delta: float,
		settling: bool = false) -> Dictionary:
	if entity.is_held():
		_states.erase(id)
		return {&"active": false}
	var state: State = _states.get(id, null)
	if entity.in_flight or (settling and state != null and state.flying):
		if state == null or not state.flying:
			state = _start(entity, yaw)
			_states[id] = state
		state.angle += state.rate * delta
		if entity.in_flight:
			state.speed = entity.velocity.length()
		return _result(state, 0.0)
	if state == null:
		return {&"active": false}
	if state.flying:
		_land(state)
	if state.since_landing < 0.0:
		# At rest: lying flat in the pose it settled into, exactly on the sim.
		return _result(state, 0.0)
	state.since_landing += delta
	var t: float = state.since_landing
	var lift: float = 0.0
	if t < BOUNCE_TIME:
		lift = _hop(state.peak, t / BOUNCE_TIME)
	elif t < BOUNCE_TIME + SECOND_TIME:
		lift = _hop(state.peak * SECOND_SHARE, (t - BOUNCE_TIME) / SECOND_TIME)
	var u: float = clampf(t / (BOUNCE_TIME + SECOND_TIME), 0.0, 1.0)
	var eased: float = 1.0 - (1.0 - u) * (1.0 - u)
	state.angle = lerpf(state.landed_angle, state.rest_angle, eased)
	if u >= 1.0:
		state.since_landing = -1.0
		state.angle = state.rest_angle
		lift = 0.0
	return _result(state, lift)

## The resting yaw of a bundle with tumble state (its pose without the spin).
func yaw_of(id: int) -> float:
	var state: State = _states.get(id, null)
	return state.yaw if state != null else 0.0

func forget(id: int) -> void:
	_states.erase(id)

func _start(entity: SimEntity, yaw: float) -> State:
	var state: State = State.new()
	state.yaw = yaw
	state.flying = true
	var flat: Vector3 = Vector3(entity.velocity.x, 0.0, entity.velocity.z)
	state.dropped = flat.length() < DROP_FLAT_SPEED
	if state.dropped:
		# A fixed axis: the bundle's own short side, so it tips slowly over.
		state.axis = Basis(Vector3.UP, yaw) * Vector3.RIGHT
		state.rate = deg_to_rad(SPIN_DROP)
	else:
		# End over end, top going forward: about UP x travel.
		state.axis = Vector3.UP.cross(flat.normalized()).normalized()
		state.rate = deg_to_rad(SPIN_THROW)
	return state

func _land(state: State) -> void:
	state.flying = false
	var scale: float = BOUNCE_DROP_SCALE if state.dropped else 1.0
	state.peak = clampf(state.speed * scale * BOUNCE_PER_SPEED, BOUNCE_PEAK_MIN, BOUNCE_PEAK_MAX) \
		if BOUNCE_PEAK_MAX > 0.0 else 0.0
	state.landed_angle = state.angle
	state.rest_angle = roundf(state.angle / PI) * PI
	state.since_landing = 0.0 if state.peak > 0.0 or state.rest_angle != state.angle else -1.0
	if state.since_landing < 0.0:
		state.angle = state.rest_angle

## One hop: a parabola from 0 up to `peak` and back, s in 0..1. Never negative.
static func _hop(peak: float, s: float) -> float:
	return maxf(peak * 4.0 * s * (1.0 - s), 0.0)

func _result(state: State, lift: float) -> Dictionary:
	var spin: Basis = Basis(state.axis, state.angle) if state.angle != 0.0 else Basis.IDENTITY
	return {&"active": true, &"lift": lift, &"basis": spin * Basis(Vector3.UP, state.yaw),
		&"resting": not state.flying and state.since_landing < 0.0}
