extends SceneTree
## Checks that the baked level is the same game for both teams.
##
##   godot --headless --path godot --script res://tools/symmetry_probe.gd
##
## House B is House A turned 180 degrees about the middle of the lot
## (build_house.gd). If that holds for everything the rules and the bots read -
## blockers, rooms, spawns, cash and the walkable surface - then a side that keeps
## winning is winning because of something that is NOT turn-invariant (an
## iteration order, a tie-break), and the content is cleared. If it does not
## hold, this says exactly which piece differs.
##
## Every check prints how many items it compared, because a check that matched
## nothing is not a check that passed.

## Positions are compared at a tenth of a unit; the builder works in whole units.
const SNAP: float = 10.0
## Random trips routed both ways round. Enough to cross every room many times.
const ROUTE_PAIRS: int = 200

var _pivot: Vector2 = Vector2.ZERO
var _failures: int = 0

func _initialize() -> void:
	var level: LevelDef = load(GreyBoxLevel.LEVEL_PATH) as LevelDef
	if level == null or level.teams.size() != 2:
		print("no two-team baked level at %s" % GreyBoxLevel.LEVEL_PATH)
		quit(1)
		return
	var shell: AABB = level.collision.bounds
	_pivot = Vector2(shell.position.x + shell.size.x * 0.5, shell.position.z + shell.size.z * 0.5)
	print("pivot (%.1f, %.1f) - the middle of the shell" % [_pivot.x, _pivot.y])

	var first: TeamDef = level.teams[0]
	var other: TeamDef = level.teams[1]
	_check_points("spawns", first.spawn_points, other.spawn_points)
	_check_points("cash", first.cash_points, other.cash_points)
	_check_blockers(level.collision.blockers)
	_check_zones(level.zones, first.id, other.id)
	_check_surface(level.surface)
	_check_routes(level)

	print("\nSYMMETRY: %s" % ("exact" if _failures == 0 else "%d differences" % _failures))
	quit(0 if _failures == 0 else 1)

func _turn(point: Vector3) -> Vector3:
	return Vector3(2.0 * _pivot.x - point.x, point.y, 2.0 * _pivot.y - point.z)

func _turn_box(box: AABB) -> AABB:
	var far: Vector3 = _turn(box.end)
	return AABB(Vector3(far.x, box.position.y, far.z), box.size)

func _key(point: Vector3) -> Vector3i:
	return Vector3i((point * SNAP).round())

func _box_key(box: AABB) -> String:
	return "%s %s" % [_key(box.position), _key(box.size)]

func _fail(what: String) -> void:
	_failures += 1
	if _failures <= 40:
		print("  DIFF  %s" % what)

## Slot for slot: spawn 0 of one team must turn onto spawn 0 of the other.
func _check_points(label: String, mine: Array[Vector3], theirs: Array[Vector3]) -> void:
	if mine.size() != theirs.size():
		_fail("%s: %d against %d" % [label, mine.size(), theirs.size()])
	for i: int in mini(mine.size(), theirs.size()):
		if _key(_turn(mine[i])) != _key(theirs[i]):
			_fail("%s %d: %s turns to %s, the other team has %s" % [
				label, i, mine[i], _turn(mine[i]), theirs[i]])
	print("%-9s %d pairs compared" % [label, mini(mine.size(), theirs.size())])

## The set of blockers must map onto itself. Lot-wide pieces (terrain, shell)
## map onto themselves, which is fine.
func _check_blockers(blockers: Array[AABB]) -> void:
	var have: Dictionary[String, int] = {}
	for box: AABB in blockers:
		var key: String = _box_key(box)
		have[key] = have.get(key, 0) + 1
	var matched: int = 0
	for box: AABB in blockers:
		var turned: String = _box_key(_turn_box(box))
		if have.get(turned, 0) == have.get(_box_key(box), 0):
			matched += 1
		else:
			_fail("blocker %s has no turned twin" % box)
	print("blockers  %d of %d have a turned twin" % [matched, blockers.size()])

## Each room must turn onto a room with the same meaning for the other team:
## same role, outdoor flag, shelter, priority, owner swapped. Links must name
## twins of the same rooms. Names are NOT compared, except as the tie-break
## between equal priorities, which is checked last because it is the one
## place a name changes which room a point is in.
func _check_zones(zones: Array[ZoneDef], first: StringName, other: StringName) -> void:
	var by_shape: Dictionary[String, ZoneDef] = {}
	for zone: ZoneDef in zones:
		by_shape[_box_key(zone.bounds)] = zone
	var twin: Dictionary[StringName, StringName] = {}
	for zone: ZoneDef in zones:
		var found: ZoneDef = by_shape.get(_box_key(_turn_box(zone.bounds)), null)
		if found == null:
			_fail("zone %s %s has no turned twin" % [zone.id, zone.bounds])
			continue
		twin[zone.id] = found.id
		var swapped: StringName = other if zone.owner_team == first 			else (first if zone.owner_team == other else zone.owner_team)
		if found.owner_team != swapped or found.role != zone.role or found.outdoor != zone.outdoor 				or found.priority != zone.priority 				or found.safe_duration_seconds != zone.safe_duration_seconds 				or found.safe_ends_on_pickup != zone.safe_ends_on_pickup:
			_fail("zone %s and its twin %s differ in meaning" % [zone.id, found.id])
	for zone: ZoneDef in zones:
		if not twin.has(zone.id):
			continue
		var mapped: Array[String] = []
		for link: StringName in zone.links:
			mapped.append(String(twin.get(link, &"?")))
		mapped.sort()
		var theirs: Array[String] = []
		for zone_b: ZoneDef in zones:
			if zone_b.id == twin[zone.id]:
				for link: StringName in zone_b.links:
					theirs.append(String(link))
		theirs.sort()
		if mapped != theirs:
			_fail("zone %s links %s, its twin %s links %s" % [zone.id, mapped, twin[zone.id], theirs])
	print("zones     %d of %d have a turned twin" % [twin.size(), zones.size()])
	_check_resolution(zones, twin)

## Where two rooms touch or overlap at equal priority, the NAME decides which
## one a point is in. That is turn-invariant only if the twins sort the same way.
func _check_resolution(zones: Array[ZoneDef], twin: Dictionary[StringName, StringName]) -> void:
	var by_id: Dictionary[StringName, ZoneDef] = {}
	for zone: ZoneDef in zones:
		by_id[zone.id] = zone
	var pairs: int = 0
	for i: int in zones.size():
		for j: int in range(i + 1, zones.size()):
			var a: ZoneDef = zones[i]
			var b: ZoneDef = zones[j]
			if a.priority != b.priority or not a.bounds.intersects(b.bounds) 					and not _touch(a.bounds, b.bounds):
				continue
			if not twin.has(a.id) or not twin.has(b.id):
				continue
			if twin[a.id] == b.id:
				# Each other's twins (the two yards, meeting on the midline).
				# Whichever sorts first owns the shared face - a line of zero
				# width, so noted rather than failed.
				print("  note  %s and %s share a face; points exactly on it resolve to %s" % [
					a.id, b.id, a.id if ZoneDef.compare_for_resolution(a, b) else b.id])
				continue
			pairs += 1
			var here: bool = ZoneDef.compare_for_resolution(a, b)
			var there: bool = ZoneDef.compare_for_resolution(by_id[twin[a.id]], by_id[twin[b.id]])
			if here != there:
				_fail("%s/%s resolve one way and their twins %s/%s the other" % [
					a.id, b.id, twin[a.id], twin[b.id]])
	print("ties      %d touching equal-priority pairs compared" % pairs)

## Shared faces count: has_point is inclusive, so a point on the face is in both.
func _touch(a: AABB, b: AABB) -> bool:
	return a.grow(0.5).intersects(b.grow(0.5))

## Every stance must have a twin, and its neighbours must be its twin's
## neighbours. This is what the bots actually walk.
func _check_surface(surface: WalkableSurfaceDef) -> void:
	if surface == null:
		_fail("no baked surface")
		return
	var index: Dictionary[Vector3i, int] = {}
	for i: int in surface.nodes.size():
		index[_key(surface.nodes[i])] = i
	var twins: int = 0
	var edges_ok: int = 0
	for i: int in surface.nodes.size():
		var j: int = index.get(_key(_turn(surface.nodes[i])), -1)
		if j < 0:
			_fail("stance %d at %s has no turned twin" % [i, surface.nodes[i]])
			continue
		twins += 1
		var mine: Array[Vector3i] = []
		for e: int in range(surface.edge_offsets[i], surface.edge_offsets[i + 1]):
			mine.append(_key(_turn(surface.nodes[surface.edge_targets[e]])))
		var theirs: Array[Vector3i] = []
		for e: int in range(surface.edge_offsets[j], surface.edge_offsets[j + 1]):
			theirs.append(_key(surface.nodes[surface.edge_targets[e]]))
		mine.sort()
		theirs.sort()
		if mine == theirs:
			edges_ok += 1
		else:
			_fail("stance %d at %s: %d neighbours, its twin %d has %d" % [
				i, surface.nodes[i], mine.size(), j, theirs.size()])
	print("surface   %d of %d stances have a twin, %d with the same neighbours" % [
		twins, surface.nodes.size(), edges_ok])

## A twin graph is not enough: the ROUTER has to find twin routes on it. Equal
## shortest paths are common on a grid, and whichever way the search breaks the
## tie is the side of the stairwell a bot walks. Random stance pairs, each
## routed as-is and turned; every waypoint of one must turn onto the other's.
func _check_routes(level: LevelDef) -> void:
	var walkable: WalkableSurface = WalkableSurface.from_def(level.surface, level.collision)
	var started: int = Time.get_ticks_msec()
	var graph: NavGraph = NavGraph.of(walkable)
	print("graph     built in %d ms (both edge orders)" % (Time.get_ticks_msec() - started))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20261112
	var matched: int = 0
	var routed: int = 0
	for n: int in ROUTE_PAIRS:
		var from: Vector3 = walkable.nodes[rng.randi_range(0, walkable.size() - 1)]
		var to: Vector3 = walkable.nodes[rng.randi_range(0, walkable.size() - 1)]
		var mine: PackedVector3Array = graph.route(from, to)
		var theirs: PackedVector3Array = graph.route(_turn(from), _turn(to))
		if mine.is_empty() and theirs.is_empty():
			continue
		routed += 1
		var same: bool = mine.size() == theirs.size()
		for k: int in mine.size() if same else 0:
			if _key(_turn(mine[k])) != _key(theirs[k]):
				same = false
				break
		if same:
			matched += 1
		elif routed - matched <= 3:
			print("  DIFF  route %s -> %s: %d waypoints, its twin %d" % [from, to, mine.size(), theirs.size()])
	if matched != routed:
		_fail("%d of %d routes differ from their turned twin" % [routed - matched, routed])
	print("routes    %d of %d trips match their turned twin" % [matched, routed])
