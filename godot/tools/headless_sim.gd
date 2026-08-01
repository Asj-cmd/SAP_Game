extends SceneTree
## Headless simulation runner. See ARCHITECTURE.md §7 - this stays first-class
## and must never rot: it is the cheapest correctness signal the project has.
##
## At this stage sim/ contains core only (no systems), so what it proves is the
## property everything else is built on: stepping a world from a fixed seed is
## reproducible. Two runs at the same seed must emit byte-identical output. As
## systems land, this same runner grows to play a full match.
##
##   godot --headless --path godot --script res://tools/headless_sim.gd
##   godot --headless --path godot --script res://tools/headless_sim.gd -- --seed 99 --ticks 200
##
## Everything between the BEGIN/END markers is derived solely from the
## simulation, never from the clock, the filesystem, or the engine - so it is
## the region a determinism check compares.

const DEFAULT_SEED: int = 1337
const DEFAULT_TICKS: int = 120
## Per-tick lines are the useful signal but are noisy at 120 ticks; print the
## first and last few in full and hash the rest into the running digest.
const HEAD_TICKS: int = 5
const TAIL_TICKS: int = 3
## Draws taken from a standalone SimRandom to show the generator's stream is
## reproducible independently of the world.
const RNG_PROBE_DRAWS: int = 8

const MARKER_BEGIN: String = "----- DETERMINISM BEGIN -----"
const MARKER_END: String = "----- DETERMINISM END -----"

func _initialize() -> void:
	var seed_value: int = _int_arg("--seed", DEFAULT_SEED)
	var total_ticks: int = _int_arg("--ticks", DEFAULT_TICKS)

	print(MARKER_BEGIN)
	print("seed=%d" % seed_value)
	print("ticks=%d" % total_ticks)
	print("ticks_per_second=%d" % SimWorld.TICKS_PER_SECOND)

	_probe_random(seed_value)
	_probe_entity()
	_probe_insertion_order(seed_value)
	_probe_world(seed_value, total_ticks)

	print(MARKER_END)
	quit()

## SimRandom on its own: the stream must depend on nothing but the seed.
func _probe_random(seed_value: int) -> void:
	var rng: SimRandom = SimRandom.new(seed_value)
	var raws: PackedStringArray = PackedStringArray()
	for i: int in RNG_PROBE_DRAWS:
		raws.append(str(rng.next_raw()))
	print("rng.raw=%s" % ",".join(raws))

	var ints: PackedStringArray = PackedStringArray()
	for i: int in RNG_PROBE_DRAWS:
		ints.append(str(rng.next_int(1000)))
	print("rng.int=%s" % ",".join(ints))

	var floats: PackedStringArray = PackedStringArray()
	for i: int in RNG_PROBE_DRAWS:
		floats.append("%.15f" % rng.next_float())
	print("rng.float=%s" % ",".join(floats))

	# A forked stream must also be a pure function of the parent's state.
	var forked: SimRandom = rng.fork()
	var forks: PackedStringArray = PackedStringArray()
	for i: int in RNG_PROBE_DRAWS:
		forks.append(str(forked.next_int(1000)))
	print("rng.fork=%s" % ",".join(forks))
	print("rng.state=%d" % rng.state)

## SimEntity's digest and copy semantics. Kept out of the stepped world - the
## world below is empty by design - but exercised here so the core's entity
## type is not shipped entirely unrun. `duplicate_entity` must produce a copy
## that does NOT alias the original, or every snapshot the netcode takes would
## silently track the live world instead of freezing it.
func _probe_entity() -> void:
	var entity: SimEntity = SimEntity.new(7, SimEntity.Kind.ACTOR)
	entity.team = &"blue"
	entity.slot = 2
	entity.position = Vector3(1.5, -2.25, 3.0)
	entity.zone_id = &"hall"
	entity.capture_ticks_remaining = 41
	print("entity.digest=%s" % entity.to_digest_string())

	var copy: SimEntity = entity.duplicate_entity()
	copy.position = Vector3.ZERO
	copy.capture_ticks_remaining = 0
	print("entity.copy_is_independent=%s" % str(entity.to_digest_string() != copy.to_digest_string()))
	print("entity.original_unchanged=%s" % str(entity.position == Vector3(1.5, -2.25, 3.0)))

## The one property the two-run comparison structurally CANNOT establish.
##
## Both runs of a same-process test insert entities in the same order, so both
## agree no matter how the digest iterates. Across two machines they need not:
## a client that learned about entities in a different sequence than the server
## holds identical logical state in a dictionary with different insertion
## order. If state_digest() walked entities.keys() rather than sorting, that
## would surface as a desync with no divergence behind it.
##
## Two worlds are built here with the same entities inserted in OPPOSITE
## orders. Their digests must be byte-identical. This fails loudly the moment
## the sort is dropped from state_digest().
func _probe_insertion_order(seed_value: int) -> void:
	var forward: SimWorld = SimWorld.new(seed_value)
	var reverse: SimWorld = SimWorld.new(seed_value)
	forward.configure(GameModeDef.new(), TuningDef.new(), [], [])
	reverse.configure(GameModeDef.new(), TuningDef.new(), [], [])

	var ids: Array[int] = [1, 2, 3, 4, 5]
	for entity_id: int in ids:
		forward.insert_entity(_make_probe_entity(entity_id))
	for i: int in ids.size():
		var entity_id: int = ids[ids.size() - 1 - i]
		reverse.insert_entity(_make_probe_entity(entity_id))

	# Confirm the two dictionaries really do disagree on iteration order,
	# otherwise this probe would pass vacuously.
	var forward_raw: PackedStringArray = PackedStringArray()
	for entity_id: int in forward.entities.keys():
		forward_raw.append(str(entity_id))
	var reverse_raw: PackedStringArray = PackedStringArray()
	for entity_id: int in reverse.entities.keys():
		reverse_raw.append(str(entity_id))

	print("order.forward_insertion=%s" % ",".join(forward_raw))
	print("order.reverse_insertion=%s" % ",".join(reverse_raw))
	print("order.iteration_actually_differs=%s" % str(forward_raw != reverse_raw))
	print("order.forward_hash=%d" % forward.state_hash())
	print("order.reverse_hash=%d" % reverse.state_hash())
	print("order.digests_match=%s" % str(forward.state_digest() == reverse.state_digest()))

## Deterministic entity content derived from the id, so the two worlds above
## differ in nothing but insertion order.
func _make_probe_entity(entity_id: int) -> SimEntity:
	var entity: SimEntity = SimEntity.new(entity_id, SimEntity.Kind.ACTOR)
	entity.team = &"blue" if entity_id % 2 == 0 else &"red"
	entity.slot = entity_id
	entity.position = Vector3(float(entity_id), 0.0, float(entity_id) * 2.0)
	entity.zone_id = &"hall"
	return entity

## An empty world stepped `total_ticks` times.
func _probe_world(seed_value: int, total_ticks: int) -> void:
	var world: SimWorld = SimWorld.new(seed_value)
	# Deliberately empty: default content, no zones, no teams, no entities.
	# The point of this stage is that the CORE steps reproducibly; content and
	# systems arrive in later pulls of work.
	world.configure(GameModeDef.new(), TuningDef.new(), [], [])

	print("world.initial_hash=%d" % world.state_hash())

	var no_commands: Array[SimCommand] = []
	var event_total: int = 0
	# Folds every tick's hash into one value, so a divergence anywhere in the
	# run is caught even on ticks not printed individually.
	var running: String = ""

	for i: int in total_ticks:
		var events: Array[SimEvent] = world.step(no_commands)
		event_total += events.size()
		var tick_hash: int = world.state_hash()
		running += "%d:%d;" % [world.tick, tick_hash]

		if i < HEAD_TICKS or i >= total_ticks - TAIL_TICKS:
			var kinds: PackedStringArray = PackedStringArray()
			for event: SimEvent in events:
				kinds.append(String(event.kind))
			print("tick=%04d hash=%d events=%d[%s]" % [
				world.tick, tick_hash, events.size(), ",".join(kinds),
			])
		elif i == HEAD_TICKS:
			print("... %d ticks elided, folded into world.running_hash ..." % (total_ticks - HEAD_TICKS - TAIL_TICKS))

	print("world.event_total=%d" % event_total)
	print("world.running_hash=%d" % SimWorld.hash_string(running))
	print("world.final_tick=%d" % world.tick)
	print("world.final_hash=%d" % world.state_hash())
	print("world.final_digest=%s" % world.state_digest())

	# One command with no systems installed: every command is unhandled, and
	# the world must still advance by exactly one tick.
	var probe_commands: Array[SimCommand] = [
		SimCommand.new(&"ProbeCommand", SimEntity.NO_ENTITY, world.tick),
	]
	var probe_events: Array[SimEvent] = world.step(probe_commands)
	var probe_kinds: PackedStringArray = PackedStringArray()
	for event: SimEvent in probe_events:
		probe_kinds.append(event.to_digest_string())
	print("world.command_probe=%s" % ";".join(probe_kinds))
	print("world.post_probe_hash=%d" % world.state_hash())

## Reads an integer flag from the args after `--`. Falls back to `fallback`
## when absent or malformed, so the runner always runs.
func _int_arg(flag: String, fallback: int) -> int:
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	for i: int in user_args.size():
		if user_args[i] == flag and i + 1 < user_args.size():
			return user_args[i + 1].to_int()
	return fallback
