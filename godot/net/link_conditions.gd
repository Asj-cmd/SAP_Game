class_name LinkConditions
extends RefCounted
## Optional lag and loss for a LoopbackTransport's outgoing packets.
##
## Opt-in: a transport with no conditions delivers immediately and losslessly,
## which stays the reference. Conditions apply to what the transport SENDS.
##
## Reliable packets are never lost (the ENet reliable model): a "lost" one
## arrives one extra round trip later, and delivery stays in order. Unreliable
## packets are dropped with probability `loss` and may reorder under jitter.

## One-way delay in milliseconds.
var latency_ms: int = 0
var jitter_ms: int = 0
## Probability 0..1 that a packet is lost.
var loss: float = 0.0
## Returns the current time in ms. A test replaces it to drive time by hand.
var clock: Callable = Time.get_ticks_msec

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _last_due: Dictionary[int, int] = {}

func _init(
	latency: int = 0, loss_chance: float = 0.0, jitter: int = 0, rng_seed: int = 1
) -> void:
	latency_ms = latency
	loss = loss_chance
	jitter_ms = jitter
	_rng.seed = rng_seed

func now_ms() -> int:
	return int(clock.call())

## When a packet sent now to `receiver` is due, or -1 if it is dropped.
func due_for(receiver: int, reliable: bool) -> int:
	var lost: bool = loss > 0.0 and _rng.randf() < loss
	var delay: int = latency_ms
	if jitter_ms > 0:
		delay += _rng.randi_range(0, jitter_ms)
	if lost:
		if not reliable:
			return -1
		delay += 2 * latency_ms
	var due: int = now_ms() + delay
	if reliable:
		due = maxi(due, _last_due.get(receiver, 0))
		_last_due[receiver] = due
	return due
