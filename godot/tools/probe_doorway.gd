extends SceneTree
## Looks closely at one doorway.
##
##   godot --headless --path godot --script res://tools/probe_doorway.gd
##
## A lone bot stalls two hundred times in one place, so the question stopped
## being "why do bots get stuck" and became "what is different about THIS
## door". This prints the geometry there, the standing places the fill found,
## and the route a bot would be handed - which is a better instrument for a
## fixed location than watching from the other side of the map.

## The stall, from tools/bot_match.gd --lone.
const NEAR: Vector3 = Vector3(4120.0, 60.0, 1210.0)
const SPAN: float = 400.0

func _initialize() -> void:
	var level: GreyBoxLevel = GreyBoxLevel.new()
	if not level.is_loaded():
		print("no baked level")
		quit(1)
		return

	print("--- geometry within %d units of %s ---" % [int(SPAN), NEAR])
	for blocker: AABB in level.collision.blockers:
		if blocker.grow(SPAN).has_point(NEAR):
			print("  blocker x %6.0f..%-6.0f  z %6.0f..%-6.0f  y %4.0f..%-4.0f" % [
				blocker.position.x, blocker.position.x + blocker.size.x,
				blocker.position.z, blocker.position.z + blocker.size.z,
				blocker.position.y, blocker.position.y + blocker.size.y,
			])

	print("\n--- zones there ---")
	for zone: ZoneDef in level.zones:
		if zone.bounds.grow(SPAN).has_point(NEAR):
			print("  %-10s %-10s x %6.0f..%-6.0f  z %6.0f..%-6.0f" % [
				zone.id, ZoneDef.Role.keys()[zone.role],
				zone.bounds.position.x, zone.bounds.position.x + zone.bounds.size.x,
				zone.bounds.position.z, zone.bounds.position.z + zone.bounds.size.z,
			])

	var surface: WalkableSurface = WalkableSurface.build(
		level.collision, level.tuning.actor_radius, level.tuning.step_up_height
	)
	var nav: NavGraph = NavGraph.of(surface)

	print("\n--- standing places within %d units ---" % int(SPAN))
	var nearby: Array[int] = []
	for i: int in surface.size():
		if surface.nodes[i].distance_to(NEAR) <= SPAN:
			nearby.append(i)
	print("  %d nodes, %d edges between them" % [nearby.size(), _edges_among(surface, nearby)])

	# The errand the stalled bot was on: carrying, heading for its own vault.
	var vault: ZoneDef = _vault_for(level, &"team_b")
	if vault == null:
		print("no team_b vault")
		quit(1)
		return
	var destination: Vector3 = vault.bounds.get_center()
	print("\n--- the route a bot is handed, standing where it stalls ---")
	print("  from %s to %s (vault centre)" % [NEAR.round(), destination.round()])
	var route: PackedVector3Array = nav.route(NEAR, destination)
	print("  %d waypoints" % route.size())
	for i: int in route.size():
		print("    [%d] %s   clear from the stall point: %s" % [
			i, route[i].round(),
			"yes" if surface.is_clear_between(NEAR, route[i]) else "NO",
		])

	# The destination itself is the interesting one: a bot aims at its task's
	# target, and a target nobody can stand on has no node to route to.
	print("\n--- the destination ---")
	print("  vault centre standable: %s" % _standable(level, surface, destination))
	var landed: int = surface.nearest(destination)
	if landed >= 0:
		print("  nearest standing place: %s, %.0f units away" % [
			surface.nodes[landed].round(), surface.nodes[landed].distance_to(destination),
		])
	quit(0)

func _edges_among(surface: WalkableSurface, nodes: Array[int]) -> int:
	var total: int = 0
	for index: int in nodes:
		for other: int in surface.neighbours(index):
			if nodes.has(other):
				total += 1
	return total

func _vault_for(level: GreyBoxLevel, team: StringName) -> ZoneDef:
	for zone: ZoneDef in level.zones:
		if zone.role == ZoneDef.Role.CASH_ROOM and zone.owner_team == team:
			return zone
	return null

func _standable(level: GreyBoxLevel, surface: WalkableSurface, point: Vector3) -> String:
	var radius: float = level.tuning.actor_radius
	if not level.collision.contains(point, radius):
		return "no - outside the shell"
	if level.collision.blocks_segment(point, point, radius):
		return "no - inside a blocker"
	return "yes"
