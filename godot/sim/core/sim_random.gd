class_name SimRandom
extends RefCounted
## The ONLY randomness permitted inside sim/ (ARCHITECTURE.md §3).
##
## Implements SplitMix64 in pure integer arithmetic rather than wrapping
## Godot's RandomNumberGenerator. The reason is replay durability: a recorded
## seed plus a command stream must re-simulate identically not only on another
## machine but on another *engine build*. Binding the sim's entropy to engine
## internals would silently invalidate every stored replay the day those
## internals changed. This is ~20 lines and removes that entire class of risk.
##
## The whole generator is one 64-bit integer, so `state` snapshots and restores
## trivially - which is what rollback netcode and mid-replay seeking need.

## SplitMix64 constants, written as signed decimals because GDScript's int is
## int64 and these exceed its positive range:
##   GAMMA = 0x9E3779B97F4A7C15, MIX_A = 0xBF58476D1CE4E5B9, MIX_B = 0x94D049BB133111EB
const GAMMA: int = -7046029254386353131
const MIX_A: int = -4658895280553007687
const MIX_B: int = -7723592293110705685

## 2^53: floats get a full double mantissa's worth of bits and no more, so the
## int -> float mapping is exact and therefore reproducible.
const FLOAT_SCALE: float = 9007199254740992.0

var state: int = 0

func _init(seed_value: int = 0) -> void:
	state = seed_value

## Logical (zero-filling) right shift. GDScript's `>>` is arithmetic and would
## sign-extend, which SplitMix64's mixing steps must not do.
static func _lsr(value: int, bits: int) -> int:
	return (value >> bits) & ((1 << (64 - bits)) - 1)

## Next raw 64-bit draw. Signed-overflow wraparound is intended here; it is
## exactly the modulo-2^64 arithmetic the algorithm is defined in terms of.
func next_raw() -> int:
	state = state + GAMMA
	var z: int = state
	z = (z ^ _lsr(z, 30)) * MIX_A
	z = (z ^ _lsr(z, 27)) * MIX_B
	return z ^ _lsr(z, 31)

## Next draw as a non-negative 63-bit integer.
func next_positive() -> int:
	return _lsr(next_raw(), 1)

## Uniform integer in [0, bound). Returns 0 for a non-positive bound so a
## caller iterating an empty collection degrades quietly instead of crashing.
func next_int(bound: int) -> int:
	if bound <= 0:
		return 0
	return next_positive() % bound

## Uniform integer in [min_value, max_value] inclusive.
func next_int_range(min_value: int, max_value: int) -> int:
	if max_value <= min_value:
		return min_value
	return min_value + next_int(max_value - min_value + 1)

## Uniform float in [0, 1).
func next_float() -> float:
	return float(_lsr(next_raw(), 11)) / FLOAT_SCALE

## Uniform float in [min_value, max_value).
func next_float_range(min_value: float, max_value: float) -> float:
	return min_value + next_float() * (max_value - min_value)

## Uniform float in [-magnitude, +magnitude) - the shape every jitter and
## noise term in the AI weights table wants.
func next_signed(magnitude: float) -> float:
	return next_float_range(-magnitude, magnitude)

func next_bool() -> bool:
	return (next_raw() & 1) == 1

## An independent generator derived from this one. Gives each bot (or system)
## its own stream, so adding a consumer cannot shift the draws every other
## consumer sees - a notorious source of "one change reshuffled the whole
## match" determinism bugs.
func fork() -> SimRandom:
	return SimRandom.new(next_raw())

func clone() -> SimRandom:
	return SimRandom.new(state)
