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

## Where the match is. Owned by MatchFlowSystem; everything else reads it.
enum MatchPhase {
	WAITING, ## Assembled but not started.
	COUNTDOWN, ## Pre-round pause. Actors are placed but inert.
	PLAYING, ## The only phase in which actions are accepted.
	ROUND_END, ## Round decided, result on screen.
	MATCH_END, ## Terminal.
}

## Completed steps. Advances by exactly one per step().
var tick: int = 0

## ---- match state ----
## All of it counted in TICKS, never seconds, and never a clock (§3).
var match_phase: MatchPhase = MatchPhase.WAITING
## Ticks left in the current phase. In PLAYING this is the round timer.
var phase_ticks_remaining: int = 0
var round_number: int = 1
## team id -> carriables currently counting for that team. DERIVED by
## ScoringSystem every tick, never incremented (see its notes).
var scores: Dictionary[StringName, int] = {}
## team id -> rounds won.
var round_wins: Dictionary[StringName, int] = {}
## Winner of the round just ended, empty for a draw or a round in progress.
var round_winner: StringName = &""
var match_winner: StringName = &""
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
## Solid geometry. Null means no shell and no walls - an open plane, which is
## only ever right for a fixture. See WORLD_AUTHORING.md §2.
var collision: WorldCollisionDef = null
## Where a body can stand, and the steps between those places. Built once by
## configure() from the geometry, used by the load gate to prove the level hangs
## together and afterwards by anything navigating it.
##
## Derived from content and never mutated, so it is not simulation state and
## takes no part in the digest: two worlds with the same geometry build the same
## surface, and a world that never navigates is unaffected by its existence.
var surface: WalkableSurface = null

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

## Why the last configure() refused, empty when the content installed.
##
## Content that fails validation is NOT installed and the world will not step
## (WORLD_AUTHORING.md §7). A broken house has to be impossible to play rather
## than something discovered mid-match, and reporting a problem while loading
## anyway is just a slower way of discovering it mid-match.
var content_failures: PackedStringArray = PackedStringArray()

## Installs the content this world runs on. Call before the first step().
##
## Returns true when the content was accepted. Validation runs only when
## collision geometry is present: a world without it is explicitly an open
## plane - the fixture shape the determinism probes and rule suites use - and
## has no geometry to be broken. Anything that could be a level carries
## geometry, so anything that could be a level is gated.
func configure(
	game_mode: GameModeDef,
	tuning_values: TuningDef,
	zone_defs: Array[ZoneDef],
	team_defs: Array[TeamDef],
	collision_def: WorldCollisionDef = null
) -> bool:
	content_failures = PackedStringArray()
	surface = null
	if collision_def != null:
		# Built here rather than inside the gate so the one surface serves both:
		# the gate proves the level is connected, and whatever navigates it
		# afterwards walks the very graph that was proved.
		surface = WalkableSurface.build(
			collision_def,
			tuning_values.actor_radius if tuning_values != null else 0.0,
			tuning_values.step_up_height if tuning_values != null else 0.0
		)
		content_failures = ContentValidator.validate(
			zone_defs, team_defs, collision_def, tuning_values, surface
		)
	if not content_failures.is_empty():
		for failure: String in content_failures:
			push_error("content rejected: %s" % failure)
		# Dropped along with the rest of the rejected content. A surface built
		# from geometry the gate refused describes a level nobody may play, and
		# leaving it reachable invites something to navigate one anyway.
		surface = null
		return false

	mode = game_mode
	tuning = tuning_values
	collision = collision_def
	zones.clear()
	for zone: ZoneDef in zone_defs:
		zones[zone.id] = zone
	teams.clear()
	for team: TeamDef in team_defs:
		teams[team.id] = team
	_rebuild_zone_lookup_order()
	return true

## Did the installed content pass? A world that refused its content is inert.
func has_valid_content() -> bool:
	return content_failures.is_empty()

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

## Creates the round's bodies from content: one actor per roster slot, and
## each team's cash where the team says it starts.
##
## Lives here rather than in whatever assembles the game because it WRITES
## entity state, and presentation writing simulation state is the one thing
## the architecture does not survive (§1). A caller gets a populated world
## from one call and never touches a field.
##
## Clears any previous roster first, so starting a second match does not stack
## bodies on the first one's.
func populate_roster() -> void:
	for entity_id: int in sorted_entity_ids():
		remove_entity(entity_id)

	var slots: int = mode.team_size if mode != null else 1
	for team_id: StringName in sorted_team_ids():
		var team: TeamDef = teams[team_id]
		for slot: int in slots:
			var actor: SimEntity = SimEntity.new(SimEntity.NO_ENTITY, SimEntity.Kind.ACTOR)
			actor.team = team_id
			actor.slot = slot
			actor.position = team.spawn_point_for_slot(slot)
			actor.origin_position = actor.position
			add_entity(actor)
		for point: Vector3 in team.cash_points:
			var cash: SimEntity = SimEntity.new(SimEntity.NO_ENTITY, SimEntity.Kind.CARRIABLE)
			cash.team = team_id
			cash.position = point
			cash.origin_position = point
			add_entity(cash)

## Actor ids in a fixed order - what a local game hands out as seats.
func actor_ids() -> Array[int]:
	var ids: Array[int] = []
	for entity_id: int in sorted_entity_ids():
		if entities[entity_id].is_actor():
			ids.append(entity_id)
	return ids

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

## Team ids in a fixed order, so anything iterating teams is deterministic
## regardless of the order content was loaded in.
##
## Sorted as STRINGS, never as StringNames. Array[StringName].sort() does not
## compare by characters - it compares interning identity, so three names
## interned out of alphabetical order come back in neither alphabetical nor
## insertion order, and which order depends on what the process happened to
## intern first.
##
## That is not cosmetic here. This ordering decides the sequence populate_roster
## creates bodies in, and therefore which entity ID each actor gets; two clients
## interning in different orders would hand the same player different ids and
## disagree about everything thereafter. It also orders the digest's own team
## lines - the desync detector was itself a source of desyncs. Zone resolution
## already cast to String for exactly this reason; teams were missed.
func sorted_team_ids() -> Array[StringName]:
	var ids: Array[StringName] = teams.keys()
	ids.sort_custom(_compare_ids_as_text)
	return ids

static func _compare_ids_as_text(a: StringName, b: StringName) -> bool:
	return String(a) < String(b)

## Are actor actions accepted right now?
##
## Every rule that an actor can trigger gates on this, which is what stops
## players moving during the countdown or being captured after the final
## whistle. Systems read it off world state rather than asking MatchFlowSystem,
## so nothing needs to depend on anything else (§5).
func is_live() -> bool:
	return match_phase == MatchPhase.PLAYING

## Does this system run this tick? Dormant systems receive neither commands
## nor their per-tick update, so a rule cannot fire while play is stopped by
## a system whose author forgot to check.
func is_system_active(system: SimSystem) -> bool:
	return is_live() or system.runs_when_paused()

func score_for(team_id: StringName) -> int:
	return scores.get(team_id, 0)

func round_wins_for(team_id: StringName) -> int:
	return round_wins.get(team_id, 0)

# ---- the contract ----

## Registers a rule module, placing it by its DECLARED phase rather than by
## when it happened to be registered (SimSystem.Phase).
##
## Insertion keeps the array sorted by phase, with registration order
## preserved inside a phase. That gives a total order without relying on a
## sort being stable, and it means a caller cannot mis-wire the simulation by
## listing systems in the wrong sequence - the ordering is not the caller's to
## get wrong.
func add_system(system: SimSystem) -> SimSystem:
	var incoming: SimSystem.Phase = system.phase()
	var index: int = systems.size()
	for i: int in systems.size():
		if systems[i].phase() > incoming:
			index = i
			break
	systems.insert(index, system)
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
	# Rejected content leaves the world inert. Stepping a world whose geometry
	# never installed would run a match inside an empty shell, which is the
	# "discovered mid-match" outcome the gate exists to prevent.
	if not content_failures.is_empty():
		return []

	_pending_events.clear()

	for command: SimCommand in commands:
		var claimed: bool = false
		var dormant_claim: bool = false
		for system: SimSystem in systems:
			if not system.handles(command.kind):
				continue
			if is_system_active(system):
				system.handle(self, command)
				claimed = true
			else:
				dormant_claim = true
		if not claimed:
			# Two different situations that must not read alike. A command
			# whose system is merely asleep between rounds is ordinary and
			# expected; one nobody recognises at all means a malformed
			# command, or a client running a build this one does not have.
			# Collapsing them would bury the second under a countdown's worth
			# of the first, every round.
			if dormant_claim:
				emit(SimEvent.command_ignored_while_paused(tick, command))
			else:
				emit(SimEvent.command_unhandled(tick, command))

	for system: SimSystem in systems:
		if is_system_active(system):
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
	parts.append("phase=%d,%d" % [match_phase, phase_ticks_remaining])
	parts.append("round=%d,%s,%s" % [round_number, round_winner, match_winner])
	# Sorted, like every other collection the digest walks.
	for team_id: StringName in sorted_team_ids():
		parts.append("T%s=%d/%d" % [team_id, score_for(team_id), round_wins_for(team_id)])
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
