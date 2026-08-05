extends SceneTree
## Runs a whole match with every geometry predicate double-checked.
##
##   godot --headless --path godot --script res://tools/audit_predicates.gd
##
## The instrument that found the one bug two rounds of offline equivalence
## testing could not. WalkableSurface._blocked was a hand-copy of
## WorldCollisionDef.blocks_segment with a cheap bounding-box reject in front;
## the reject dropped blockers on a touching edge, so sight lines lying exactly
## along the top of the floor - which is where every sight line lies, because
## that is where bodies stand - reported clear through walls.
##
## It survived 200,000 random segments and 106,000 lattice-aligned ones drawn
## from the surface itself. Both sampled ENDPOINTS. Real queries run from
## wherever a body has actually got to, mid-motion, and that is the only sample
## that contained the failure.
##
## So the rule this tool exists to enforce: to check a predicate, sample the
## WORKLOAD, not a model of it. Run this after any change to collision, the
## walkable surface, or anything that answers a geometric question twice.

const TICKS: int = 3000

func _initialize() -> void:
	var level: GreyBoxLevel = GreyBoxLevel.new()
	if not level.is_loaded():
		print("no baked level")
		quit(1)
		return
	var world: SimWorld = SimWorld.new(20260805)
	if not world.configure(level.mode, level.tuning, level.zones, level.teams,
		level.collision, level.surface):
		print("content rejected")
		quit(1)
		return
	world.add_system(MovementSystem.new())
	world.add_system(CarrySystem.new())
	world.add_system(CaptureSystem.new())
	world.add_system(ScoringSystem.new())
	world.add_system(MatchFlowSystem.new())
	world.populate_roster()
	var crew: BotCrew = BotCrew.create(level.bot_profile, NavGraph.of(world.surface), 5)
	crew.fill_lobby(world, [], world.actor_ids().size())
	world.step([MatchCommand.start()])

	var collision: WorldCollisionDef = world.collision
	var radius: float = level.tuning.actor_radius
	var grown: Array[AABB] = []
	for blocker: AABB in collision.blockers:
		grown.append(blocker.grow(radius))

	# Every query the match makes, replayed against a full scan. Sampling the
	# positions rather than the predicate: the bodies move, and where they get
	# to is the input that matters.
	var queries: int = 0
	var wrong: int = 0
	for tick: int in TICKS:
		if world.match_phase == SimWorld.MatchPhase.MATCH_END:
			break
		world.step(crew.drain(world, world.tick))
		for actor_id: int in world.actor_ids():
			var body: SimEntity = world.get_entity(actor_id)
			if body == null:
				continue
			for other_id: int in world.actor_ids():
				var target: SimEntity = world.get_entity(other_id)
				if target == null:
					continue
				queries += 1
				var indexed: bool = collision.blocks_segment(body.position, target.position, radius)
				var scanned: bool = _scan(grown, body.position, target.position)
				var surfaced: bool = not world.surface.is_clear_between(body.position, target.position)
				if indexed != scanned or surfaced != scanned:
					wrong += 1
					if wrong <= 5:
						print("DISAGREEMENT tick %d  %s -> %s   indexed %s  scan %s  surface %s" % [
							tick, body.position, target.position, indexed, scanned, surfaced])

	print("%d live queries, %d disagreements" % [queries, wrong])
	quit(1 if wrong > 0 else 0)

## The predicate with no index and no shortcuts: the definition everything else
## has to match.
func _scan(grown: Array[AABB], from: Vector3, to: Vector3) -> bool:
	for solid: AABB in grown:
		var depth: float = WorldCollisionDef.penetration_depth(from, solid)
		if depth > 0.0:
			if WorldCollisionDef.penetration_depth(to, solid) < depth:
				continue
			return true
		if WorldCollisionDef.segment_hits_box(from, to, solid):
			return true
	return false
