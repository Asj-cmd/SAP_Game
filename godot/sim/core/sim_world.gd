class_name SimWorld
extends RefCounted
## All mutable simulation state, plus the one entry point that advances it.
## See ARCHITECTURE.md §3 - this is the load-bearing part of the design.
##
## Pure and headless: no scene tree, no rendering, no input devices, no wall
## clock. The same instance runs on a headless server, inside a client
## predicting ahead of that server, and in the headless runner, unmodified.
##
## Time is counted in TICKS at a fixed timestep. `tick` is the only clock any
## rule may read (§3).

## Fixed simulation timestep (§7), decoupled from render framerate.
## Presentation interpolates between the two most recent simulation states.
const TICKS_PER_SECOND: int = 30
const SECONDS_PER_TICK: float = 1.0 / float(TICKS_PER_SECOND)

## Non-canonical 63-bit FNV-1a: masked to stay non-negative in GDScript's
## signed int64. Distribution and determinism are what matter here - this is a
## desync detector, not a cryptographic digest.
const _HASH_OFFSET_BASIS: int = -3750763034362895579
const _HASH_PRIME: int = 1099511628211
const _HASH_MASK: int = 0x7FFFFFFFFFFFFFFF

## Completed steps. Advances by exactly one per step().
var tick: int = 0
## The only randomness permitted inside sim/ (§3).
var rng: SimRandom = null

## Godot preserves insertion order, and ids are handed out by a monotonic
## counter, so iteration is deterministic.
var entities: Dictionary[int, SimEntity] = {}

## Content (§4). Read-only to the simulation: rules consult these, never edit
## them. A mode or a room is a .tres, not a code path.
var mode: GameModeDef = null
var tuning: TuningDef = null
var zones: Dictionary[StringName, ZoneDef] = {}
var teams: Dictionary[StringName, TeamDef] = {}

## Rule modules, run in this exact order (§5). Order is part of the
## simulation's definition, not an implementation detail: two machines running
## the same systems in different orders are running different games.
var systems: Array[SimSystem] = []

var _next_entity_id: int = 1
## Events accumulated during the current step(), drained by it.
var _pending_events: Array[SimEvent] = []
## Zone ids in resolution order, rebuilt by configure(). Cached because
## zone_at() is called for every moving entity every tick, and re-sorting the
## whole zone table on each of those calls would be pure waste.
var _zone_lookup_order: Array[StringName] = []

func _init(seed_value: int = 0) -> void:
	rng = SimRandom.new(seed_value)

## Installs the content this world runs on. Call before the first step().
func configure(
	game_mode: GameModeDef,
	tuning_values: TuningDef,
	zone_defs: Array[ZoneDef],
	team_defs: Array[TeamDef]
) -> void:
	mode = game_mode
	tuning = tuning_values
	zones.clear()
	for zone: ZoneDef in zone_defs:
		zones[zone.id] = zone
	teams.clear()
	for team: TeamDef in team_defs:
		teams[team.id] = team
	_rebuild_zone_lookup_order()

## Orders zones by descending priority, ties broken by ascending id. The
## tie-break is what makes this a TOTAL order: without it, two equal-priority
## zones would resolve by dictionary insertion sequence, so a client that
## loaded content in a different order could place an entity in a different
## zone than the server did.
func _rebuild_zone_lookup_order() -> void:
	_zone_lookup_order = zones.keys()
	_zone_lookup_order.sort_custom(_compare_zone_resolution)

func _compare_zone_resolution(a: StringName, b: StringName) -> bool:
	var zone_a: ZoneDef = zones[a]
	var zone_b: ZoneDef = zones[b]
	if zone_a.priority != zone_b.priority:
		return zone_a.priority > zone_b.priority
	return String(a) < String(b)

# ---- time ----

## Converts an authored duration into whole ticks. Content is written in
## seconds because that is what a designer reasons in; the simulation counts
## ticks so that no wall clock ever reaches a rule (§3).
static func seconds_to_ticks(seconds: float) -> int:
	return int(roundf(seconds * float(TICKS_PER_SECOND)))

static func ticks_to_seconds(ticks: int) -> float:
	return float(ticks) * SECONDS_PER_TICK

# ---- entities ----

## Registers an entity and assigns it an id. For world construction and for
## systems; never call it from presentation or networking (§3).
func add_entity(entity: SimEntity) -> SimEntity:
	entity.id = _next_entity_id
	_next_entity_id += 1
	entities[entity.id] = entity
	return entity

## Inserts an entity that ALREADY has an id, rather than assigning a fresh
## one: restoring a snapshot, or applying a replicated update from the server.
## Keeps the id counter ahead of everything seen, so a later add_entity()
## cannot collide with a restored id.
func insert_entity(entity: SimEntity) -> SimEntity:
	entities[entity.id] = entity
	if entity.id >= _next_entity_id:
		_next_entity_id = entity.id + 1
	return entity

func get_entity(entity_id: int) -> SimEntity:
	return entities.get(entity_id, null)

func has_entity(entity_id: int) -> bool:
	return entities.has(entity_id)

func remove_entity(entity_id: int) -> void:
	entities.erase(entity_id)

## Ids in ascending order. Systems that must not depend on insertion order -
## and the state digest - iterate through this.
func sorted_entity_ids() -> Array[int]:
	var ids: Array[int] = entities.keys()
	ids.sort()
	return ids

# ---- zones ----

func get_zone(zone_id: StringName) -> ZoneDef:
	return zones.get(zone_id, null)

## The zone containing `point`, or null. Walks the precomputed resolution
## order, so overlapping bounds resolve by authored priority - identically on
## every machine, and by design rather than alphabetically.
func zone_at(point: Vector3) -> ZoneDef:
	for zone_id: StringName in _zone_lookup_order:
		var zone: ZoneDef = zones[zone_id]
		if zone.contains_point(point):
			return zone
	return null

## Zone ids in the same total order zone_at() resolves them by. Systems that
## must pick "the first zone matching X" iterate this, so their choice is
## deterministic and matches how containment resolves.
func zone_ids_in_resolution_order() -> Array[StringName]:
	return _zone_lookup_order.duplicate()

func get_team(team_id: StringName) -> TeamDef:
	return teams.get(team_id, null)

# ---- the contract ----

## Registers a rule module. Call order IS execution order (§5).
func add_system(system: SimSystem) -> SimSystem:
	systems.append(system)
	return system

## Records that something happened. Systems call this rather than returning
## events, so a single command may produce several and a per-tick update may
## produce them without being asked for anything.
func emit(event: SimEvent) -> void:
	_pending_events.append(event)

## Advance the world exactly one fixed step. Returns everything that happened,
## for presentation and networking to react to.
##
## Commands are resolved against the tick they arrive on, then every system
## takes its per-tick update, then the tick counter advances and TickAdvanced
## announces the tick just reached.
func step(commands: Array[SimCommand]) -> Array[SimEvent]:
	_pending_events.clear()

	for command: SimCommand in commands:
		var claimed: bool = false
		for system: SimSystem in systems:
			if system.handles(command.kind):
				system.handle(self, command)
				claimed = true
		# Nobody claimed it: a malformed command, or one from a client running
		# a build with a system this one does not have. Reporting it beats
		# discarding it silently.
		if not claimed:
			emit(SimEvent.command_unhandled(tick, command))

	for system: SimSystem in systems:
		system.step(self)

	tick += 1
	emit(SimEvent.tick_advanced(tick))

	var events: Array[SimEvent] = _pending_events.duplicate()
	_pending_events.clear()
	return events

# ---- determinism instrumentation ----

## Canonical text form of all simulation state. Two worlds that have run the
## same commands from the same seed must produce byte-identical output here.
##
## EVERY collection walked below MUST be traversed in a sorted, insertion-order-
## independent way. GDScript dictionaries iterate in insertion order, so two
## machines holding identical logical state would otherwise digest differently
## purely because entities arrived in a different sequence - a desync report
## with no actual divergence behind it, which is far worse to chase than a real
## one. A same-process two-run test cannot catch this (both runs insert in the
## same order); tools/headless_sim.gd proves it explicitly instead.
func state_digest() -> String:
	var parts: PackedStringArray = PackedStringArray()
	parts.append("tick=%d" % tick)
	parts.append("rng=%d" % rng.state)
	# Simulation state, not bookkeeping: two worlds holding identical entities
	# can still disagree here after a remove-then-restore, and would then hand
	# out different ids for the next spawn. That divergence is invisible until
	# the spawn happens, which is the worst possible time to discover it.
	parts.append("next_id=%d" % _next_entity_id)
	parts.append("entities=%d" % entities.size())
	for entity_id: int in sorted_entity_ids(): # sorted, never entities.keys()
		var entity: SimEntity = entities[entity_id]
		parts.append(entity.to_digest_string())
	return ";".join(parts)

## Digest folded to a single integer - what a desync check actually compares
## across the wire, since shipping the whole digest every tick would not be.
func state_hash() -> int:
	return hash_string(state_digest())

static func hash_string(text: String) -> int:
	var result: int = _HASH_OFFSET_BASIS
	for byte: int in text.to_utf8_buffer():
		result = (result ^ byte) * _HASH_PRIME
		result &= _HASH_MASK
	return result
