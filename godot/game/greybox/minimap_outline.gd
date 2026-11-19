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

## PT5-2: one storey of one house as the map draws it (its rooms on that floor,
## merged, plus a wall), and the vault / jail icons on that floor.
class Footprint:
	var team: StringName = &""
	var storey: int = 0
	var rect: Rect2 = Rect2()

class Mark:
	var team: StringName = &""
	var storey: int = 0
	var kind: StringName = &""  # &"vault" or &"jail"
	var at: Vector2 = Vector2.ZERO
	## The room it stands for (x, z), so cash at rest in a vault is shown by its icon.
	var room: Rect2 = Rect2()

## How far below the upper floor a body's feet may be and still count as
## upstairs, so a body halfway up a flight still reads as on the ground floor.
const UPPER_TOLERANCE: float = 60.0
## Indoor zones whose floor sits more than this above the lowest indoor floor
## are upstairs.
const STOREY_STEP: float = 100.0

var footprints: Array[Footprint] = []
var marks: Array[Mark] = []
## Height of the upstairs floor (feet), INF for a house with one storey.
var upper_floor_y: float = INF

## 0 for the ground floor, 1 for upstairs: upstairs once the feet are within
## UPPER_TOLERANCE of the upper floor (PT5-2).
static func floor_of(feet_y: float, upper_y: float) -> int:
	return 1 if feet_y >= upper_y - UPPER_TOLERANCE else 0

static func build(level: GreyBoxLevel) -> MinimapOutline:
	var outline: MinimapOutline = MinimapOutline.new()
	var bounds: AABB = level.collision.bounds
	outline.lot = Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z)
	var by_team: Dictionary[StringName, Rect2] = {}
	var ground_y: float = INF
	for zone: ZoneDef in level.zones:
		if zone.owner_team != &"" and not zone.outdoor:
			ground_y = minf(ground_y, zone.bounds.position.y)
	for zone: ZoneDef in level.zones:
		if zone.owner_team != &"" and not zone.outdoor \
				and zone.bounds.position.y > ground_y + STOREY_STEP:
			outline.upper_floor_y = minf(outline.upper_floor_y, zone.bounds.position.y)
	# Per house and floor: the rooms' union, and its vaults and jail.
	var storeys: Dictionary[String, Footprint] = {}
	for zone: ZoneDef in level.zones:
		if zone.owner_team == &"":
			continue
		var flat: Rect2 = Rect2(zone.bounds.position.x, zone.bounds.position.z,
			zone.bounds.size.x, zone.bounds.size.z)
		if zone.outdoor:
			outline.yards.append(flat.intersection(outline.lot))
			continue
		if by_team.has(zone.owner_team):
			by_team[zone.owner_team] = by_team[zone.owner_team].merge(flat)
		else:
			by_team[zone.owner_team] = flat
		var storey: int = floor_of(zone.bounds.position.y, outline.upper_floor_y)
		var key: String = "%s/%d" % [zone.owner_team, storey]
		if storeys.has(key):
			storeys[key].rect = storeys[key].rect.merge(flat)
		else:
			var foot: Footprint = Footprint.new()
			foot.team = zone.owner_team
			foot.storey = storey
			foot.rect = flat
			storeys[key] = foot
		if zone.role == ZoneDef.Role.CASH_ROOM or zone.role == ZoneDef.Role.JAIL:
			var mark: Mark = Mark.new()
			mark.team = zone.owner_team
			mark.storey = storey
			mark.kind = &"vault" if zone.role == ZoneDef.Role.CASH_ROOM else &"jail"
			mark.at = flat.get_center()
			mark.room = flat
			outline.marks.append(mark)
	var teams: Array[StringName] = by_team.keys()
	teams.sort()
	for team: StringName in teams:
		outline.houses.append(by_team[team].grow(WALL))
		outline.house_teams.append(team)
	var keys: Array[String] = storeys.keys()
	keys.sort()
	for key: String in keys:
		storeys[key].rect = storeys[key].rect.grow(WALL)
		outline.footprints.append(storeys[key])
	outline.marks.sort_custom(_mark_before)
	outline._find_fence(level)
	return outline

## Marks in a fixed order (team, floor, kind, x, z), whatever order the zones came in.
static func _mark_before(a: Mark, b: Mark) -> bool:
	if a.team != b.team:
		return String(a.team) < String(b.team)
	if a.storey != b.storey:
		return a.storey < b.storey
	if a.kind != b.kind:
		return String(a.kind) < String(b.kind)
	if a.at.x != b.at.x:
		return a.at.x < b.at.x
	return a.at.y < b.at.y

## The footprints drawn on `storey` (one per house).
func footprints_on(storey: int) -> Array[Footprint]:
	var out: Array[Footprint] = []
	for foot: Footprint in footprints:
		if foot.storey == storey:
			out.append(foot)
	return out

## The vault and jail icons drawn on `storey`.
func marks_on(storey: int) -> Array[Mark]:
	var out: Array[Mark] = []
	for mark: Mark in marks:
		if mark.storey == storey:
			out.append(mark)
	return out

## Where a family's name goes on its own lot: under or over its house, on the
## side with more open lawn, half way to the lot's edge.
func name_spot(house: Rect2) -> Vector2:
	var before: float = house.position.y - lot.position.y
	var after: float = lot.end.y - house.end.y
	var z: float = lot.end.y - after * 0.5 if after >= before else lot.position.y + before * 0.5
	return Vector2(house.get_center().x, z)

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
