class_name MinimapOutline
extends RefCounted
## What the minimap draws of the level (PT4-4): the lot, both yards, both houses
## and the boundary fence with its gates, as flat x/z rectangles and z ranges.
## Built once per level from the level data, the same way ExteriorBuilder finds
## them (owned zones for the houses and yards, the fence's own collision boxes on
## the lot's middle x). Presentation only; reads nothing from the simulation.

const WALL: float = 30.0  # build_house WALL: the rooms' union grown by a wall
const FENCE_MIN_HEIGHT: float = 200.0

## The lot (x, z) the map fits to.
var lot: Rect2 = Rect2()
## Each owned outdoor zone, clipped to the lot.
var yards: Array[Rect2] = []
## Each house's outline, in team id order: its indoor rooms' union plus a wall.
var houses: Array[Rect2] = []
## The team each house belongs to, matching `houses`.
var house_teams: Array[StringName] = []
## The fence line's x, and the z spans of its panels and of its openings.
var fence_x: float = 0.0
var fence_panels: Array[Vector2] = []
var gates: Array[Vector2] = []

static func build(level: GreyBoxLevel) -> MinimapOutline:
	var outline: MinimapOutline = MinimapOutline.new()
	var bounds: AABB = level.collision.bounds
	outline.lot = Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z)
	var by_team: Dictionary[StringName, Rect2] = {}
	for zone: ZoneDef in level.zones:
		if zone.owner_team == &"":
			continue
		var flat: Rect2 = Rect2(zone.bounds.position.x, zone.bounds.position.z,
			zone.bounds.size.x, zone.bounds.size.z)
		if zone.outdoor:
			outline.yards.append(flat.intersection(outline.lot))
		elif by_team.has(zone.owner_team):
			by_team[zone.owner_team] = by_team[zone.owner_team].merge(flat)
		else:
			by_team[zone.owner_team] = flat
	var teams: Array[StringName] = by_team.keys()
	teams.sort()
	for team: StringName in teams:
		outline.houses.append(by_team[team].grow(WALL))
		outline.house_teams.append(team)
	outline._find_fence(level)
	return outline

func _find_fence(level: GreyBoxLevel) -> void:
	fence_x = lot.get_center().x
	if level.level == null:
		return
	var panels: Array[AABB] = []
	for box: AABB in level.level.furniture:
		if box.position.x > fence_x or box.end.x < fence_x or box.size.y < FENCE_MIN_HEIGHT:
			continue
		var flat: Rect2 = Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
		var outside: bool = true
		for house: Rect2 in houses:
			if house.intersects(flat):
				outside = false
		if outside:
			panels.append(box)
	if panels.is_empty():
		return
	panels.sort_custom(func(a: AABB, b: AABB) -> bool: return a.position.z < b.position.z)
	var cursor: float = lot.position.y
	for box: AABB in panels:
		if box.position.z - cursor > 1.0:
			gates.append(Vector2(cursor, box.position.z))
		fence_panels.append(Vector2(box.position.z, box.end.z))
		cursor = maxf(cursor, box.end.z)
	if lot.end.y - cursor > 1.0:
		gates.append(Vector2(cursor, lot.end.y))
