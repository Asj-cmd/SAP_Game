extends Node
## Ported 1:1 from server/src/zones.ts (+ client/src/geometry/floorplan.ts).
## Top-down floor plan: two mirrored houses (bedroom/living/basement stacked
## per team), each with a private backyard strip along its outer edge,
## flanking a shared neutral garden in the middle. Pure data + lookups - no
## per-frame work, so this autoload only ever answers queries other autoloads
## (MatchState) make of it.

const WORLD_SCALE: float = 2.0 # MUST match client/src/constants.ts WORLD_SCALE
const WORLD_WIDTH: float = 1600.0 * WORLD_SCALE
const WORLD_HEIGHT: float = 900.0 * WORLD_SCALE

# Column boundaries, left to right: backyard B | house B | garden | house A | backyard A
const YARD_B_MAX: float = 140.0 * WORLD_SCALE
const HOUSE_B_MAX: float = 540.0 * WORLD_SCALE
const HOUSE_A_MIN: float = 1060.0 * WORLD_SCALE
const YARD_A_MIN: float = 1460.0 * WORLD_SCALE
# Row boundaries within a house column: bedroom | living | basement
const BEDROOM_MAX_Y: float = 200.0 * WORLD_SCALE
const BASEMENT_MIN_Y: float = 620.0 * WORLD_SCALE

func get_zone_at(x: float, y: float) -> String:
	if x < YARD_B_MAX:
		return "backyardB"
	if x < HOUSE_B_MAX:
		if y < BEDROOM_MAX_Y:
			return "bedroomB"
		if y < BASEMENT_MIN_Y:
			return "livingB"
		return "basementB"
	if x < HOUSE_A_MIN:
		return "garden"
	if x < YARD_A_MIN:
		if y < BEDROOM_MAX_Y:
			return "bedroomA"
		if y < BASEMENT_MIN_Y:
			return "livingA"
		return "basementA"
	return "backyardA"

func is_enemy_bedroom(team: String, x: float, y: float) -> bool:
	var zone := get_zone_at(x, y)
	return (team == "B" and zone == "bedroomA") or (team == "A" and zone == "bedroomB")

## Own home = own living room, own master bedroom, or own backyard - the yard
## is part of the property, so owners can jail intruders caught there too.
func is_own_home(team: String, x: float, y: float) -> bool:
	var zone := get_zone_at(x, y)
	if team == "B":
		return zone == "livingB" or zone == "bedroomB" or zone == "backyardB"
	return zone == "livingA" or zone == "bedroomA" or zone == "backyardA"

## The basement that holds a given team's jailed prisoners (the enemy's basement).
func jail_basement_for_team(team: String) -> String:
	return "basementB" if team == "A" else "basementA"

static func _scale_point(p: Vector2) -> Vector2:
	return p * WORLD_SCALE

static func _scale_rect(r: Dictionary) -> Dictionary:
	var out := r.duplicate()
	out["x1"] = r["x1"] * WORLD_SCALE
	out["y1"] = r["y1"] * WORLD_SCALE
	out["x2"] = r["x2"] * WORLD_SCALE
	out["y2"] = r["y2"] * WORLD_SCALE
	return out

# ---- collision geometry (bots) ----
# Hand-synced with client/src/geometry/floorplan.ts WALLS + DOORS (same
# pre-scale numbers, scaled here at load). Only the SEALED doors are
# colliders (and only for the team they're sealed for).
var WALLS: Array[Dictionary] = []
var SEALED_DOORS: Array[Dictionary] = []

var SPAWN_POINTS: Dictionary = {}
var JAIL_POSITIONS: Dictionary = {}

# ---- Bot pathing graph ----
var BOT_WAYPOINTS: Dictionary = {}
var _bot_edges: Array[Dictionary] = []

func _init() -> void:
	# Done in the constructor (not _ready) so this data is guaranteed populated
	# the instant the autoload is instantiated - no dependence on when/whether
	# this node's _ready() gets flushed relative to other startup code (e.g. a
	# `--script` SceneTree entry point that runs before any node's _ready).
	_init_walls()
	_init_sealed_doors()
	_init_spawn_and_jail()
	_init_bot_graph()

func _init_walls() -> void:
	var raw: Array[Dictionary] = [
		# world boundary
		{"x1": 0, "y1": 0, "x2": 1600, "y2": 10},
		{"x1": 0, "y1": 890, "x2": 1600, "y2": 900},
		{"x1": 0, "y1": 0, "x2": 10, "y2": 900},
		{"x1": 1590, "y1": 0, "x2": 1600, "y2": 900},
		# backyard B | house B (x=140)
		{"x1": 135, "y1": 0, "x2": 145, "y2": 60},
		{"x1": 135, "y1": 140, "x2": 145, "y2": 370},
		{"x1": 135, "y1": 450, "x2": 145, "y2": 700},
		{"x1": 135, "y1": 780, "x2": 145, "y2": 900},
		# house B | garden (x=540)
		{"x1": 535, "y1": 0, "x2": 545, "y2": 230},
		{"x1": 535, "y1": 290, "x2": 545, "y2": 380},
		{"x1": 535, "y1": 440, "x2": 545, "y2": 530},
		{"x1": 535, "y1": 590, "x2": 545, "y2": 900},
		# bedroom B | living B (y=200)
		{"x1": 140, "y1": 195, "x2": 300, "y2": 205},
		{"x1": 380, "y1": 195, "x2": 540, "y2": 205},
		# living B | basement B (y=620)
		{"x1": 140, "y1": 615, "x2": 300, "y2": 625},
		{"x1": 380, "y1": 615, "x2": 540, "y2": 625},
		# garden | house A (x=1060)
		{"x1": 1055, "y1": 0, "x2": 1065, "y2": 230},
		{"x1": 1055, "y1": 290, "x2": 1065, "y2": 380},
		{"x1": 1055, "y1": 440, "x2": 1065, "y2": 530},
		{"x1": 1055, "y1": 590, "x2": 1065, "y2": 900},
		# house A | backyard A (x=1460)
		{"x1": 1455, "y1": 0, "x2": 1465, "y2": 60},
		{"x1": 1455, "y1": 140, "x2": 1465, "y2": 370},
		{"x1": 1455, "y1": 450, "x2": 1465, "y2": 700},
		{"x1": 1455, "y1": 780, "x2": 1465, "y2": 900},
		# bedroom A | living A (y=200)
		{"x1": 1060, "y1": 195, "x2": 1220, "y2": 205},
		{"x1": 1300, "y1": 195, "x2": 1460, "y2": 205},
		# living A | basement A (y=620)
		{"x1": 1060, "y1": 615, "x2": 1220, "y2": 625},
		{"x1": 1300, "y1": 615, "x2": 1460, "y2": 625},
	]
	WALLS = []
	for r in raw:
		WALLS.append(_scale_rect(r))

func _init_sealed_doors() -> void:
	var raw: Array[Dictionary] = [
		{"x1": 133, "y1": 60, "x2": 147, "y2": 140, "team": "B"}, # bedroom <-> backyard
		{"x1": 300, "y1": 193, "x2": 380, "y2": 207, "team": "B"}, # bedroom <-> living
		{"x1": 300, "y1": 613, "x2": 380, "y2": 627, "team": "B"}, # basement <-> living
		{"x1": 133, "y1": 700, "x2": 147, "y2": 780, "team": "B"}, # basement <-> backyard
		{"x1": 1453, "y1": 60, "x2": 1467, "y2": 140, "team": "A"},
		{"x1": 1220, "y1": 193, "x2": 1300, "y2": 207, "team": "A"},
		{"x1": 1220, "y1": 613, "x2": 1300, "y2": 627, "team": "A"},
		{"x1": 1453, "y1": 700, "x2": 1467, "y2": 780, "team": "A"},
	]
	SEALED_DOORS = []
	for d in raw:
		SEALED_DOORS.append(_scale_rect(d))

func _init_spawn_and_jail() -> void:
	var spawn_b: Array[Vector2] = []
	for p in [Vector2(280, 330), Vector2(400, 330), Vector2(280, 450), Vector2(400, 450)]:
		spawn_b.append(_scale_point(p))
	var spawn_a: Array[Vector2] = []
	for p in [Vector2(1200, 330), Vector2(1320, 330), Vector2(1200, 450), Vector2(1320, 450)]:
		spawn_a.append(_scale_point(p))
	SPAWN_POINTS = {"B": spawn_b, "A": spawn_a}
	JAIL_POSITIONS = {
		"basementB": _scale_point(Vector2(340, 760)),
		"basementA": _scale_point(Vector2(1260, 760)),
	}

## Arrange `count` points in a compact grid inside [x_min,x_max] x [y_min,y_max].
static func _grid(x_min: float, x_max: float, y_min: float, y_max: float, count: int) -> Array[Vector2]:
	var rows := 1 if count <= 5 else 2
	var cols := ceili(float(count) / rows)
	var out: Array[Vector2] = []
	for i in range(count):
		@warning_ignore("integer_division") # floor(i / cols): row index, matches source's Math.floor(i / cols)
		var row := i / cols
		var col := i % cols
		var x := (x_min + x_max) / 2.0 if cols == 1 else x_min + (col * (x_max - x_min)) / (cols - 1)
		var y := (y_min + y_max) / 2.0 if rows == 1 else y_min + (row * (y_max - y_min)) / (rows - 1)
		out.append(Vector2(roundf(x), roundf(y)))
	return out

## Starting positions for the `count` original bundles in a master bedroom.
func bundle_positions(bedroom: String, count: int) -> Array[Vector2]:
	var s := WORLD_SCALE
	if bedroom == "bedroomB":
		return _grid(180 * s, 500 * s, 40 * s, 100 * s, count)
	return _grid(1100 * s, 1420 * s, 40 * s, 100 * s, count)

## Where scored (deposited) bundles stack inside the scoring team's own bedroom.
func score_slot_positions(team: String, count: int) -> Array[Vector2]:
	var s := WORLD_SCALE
	if team == "B":
		return _grid(180 * s, 500 * s, 125 * s, 165 * s, count)
	return _grid(1100 * s, 1420 * s, 125 * s, 165 * s, count)

func _init_bot_graph() -> void:
	var raw: Dictionary = {
		"livingB": Vector2(340, 410), "bedroomB": Vector2(340, 100), "basementB": Vector2(340, 760),
		"livingA": Vector2(1260, 410), "bedroomA": Vector2(1260, 100), "basementA": Vector2(1260, 760),
		"garden": Vector2(800, 450),
		"gateB_bedroom": Vector2(340, 200), "gateB_basement": Vector2(340, 620), "gateB_garden": Vector2(540, 410),
		"gateA_bedroom": Vector2(1260, 200), "gateA_basement": Vector2(1260, 620), "gateA_garden": Vector2(1060, 410),
		"backyardB": Vector2(70, 410), "yardB_bedroom": Vector2(70, 100), "yardB_basement": Vector2(70, 740),
		"gateB_yard": Vector2(140, 410), "gateB_yardBedroom": Vector2(140, 100), "gateB_yardBasement": Vector2(140, 740),
		"backyardA": Vector2(1530, 410), "yardA_bedroom": Vector2(1530, 100), "yardA_basement": Vector2(1530, 740),
		"gateA_yard": Vector2(1460, 410), "gateA_yardBedroom": Vector2(1460, 100), "gateA_yardBasement": Vector2(1460, 740),
	}
	BOT_WAYPOINTS = {}
	for key in raw:
		BOT_WAYPOINTS[key] = _scale_point(raw[key])

	_bot_edges = [
		{"a": "livingB", "b": "gateB_garden"},
		{"a": "gateB_garden", "b": "garden"},
		{"a": "garden", "b": "gateA_garden"},
		{"a": "gateA_garden", "b": "livingA"},
		{"a": "livingB", "b": "gateB_bedroom", "blocked_for": "B"},
		{"a": "gateB_bedroom", "b": "bedroomB", "blocked_for": "B"},
		{"a": "livingB", "b": "gateB_basement", "blocked_for": "B"},
		{"a": "gateB_basement", "b": "basementB", "blocked_for": "B"},
		{"a": "livingA", "b": "gateA_bedroom", "blocked_for": "A"},
		{"a": "gateA_bedroom", "b": "bedroomA", "blocked_for": "A"},
		{"a": "livingA", "b": "gateA_basement", "blocked_for": "A"},
		{"a": "gateA_basement", "b": "basementA", "blocked_for": "A"},
		{"a": "livingB", "b": "gateB_yard"},
		{"a": "gateB_yard", "b": "backyardB"},
		{"a": "backyardB", "b": "yardB_bedroom"},
		{"a": "backyardB", "b": "yardB_basement"},
		{"a": "yardB_bedroom", "b": "gateB_yardBedroom", "blocked_for": "B"},
		{"a": "gateB_yardBedroom", "b": "bedroomB", "blocked_for": "B"},
		{"a": "yardB_basement", "b": "gateB_yardBasement", "blocked_for": "B"},
		{"a": "gateB_yardBasement", "b": "basementB", "blocked_for": "B"},
		{"a": "livingA", "b": "gateA_yard"},
		{"a": "gateA_yard", "b": "backyardA"},
		{"a": "backyardA", "b": "yardA_bedroom"},
		{"a": "backyardA", "b": "yardA_basement"},
		{"a": "yardA_bedroom", "b": "gateA_yardBedroom", "blocked_for": "A"},
		{"a": "gateA_yardBedroom", "b": "bedroomA", "blocked_for": "A"},
		{"a": "yardA_basement", "b": "gateA_yardBasement", "blocked_for": "A"},
		{"a": "gateA_yardBasement", "b": "basementA", "blocked_for": "A"},
	]

func nearest_bot_node(x: float, y: float) -> String:
	var best := "garden"
	var best_dist := INF
	for id in BOT_WAYPOINTS:
		var p: Vector2 = BOT_WAYPOINTS[id]
		var d := Vector2(p.x - x, p.y - y).length()
		if d < best_dist:
			best_dist = d
			best = id
	return best

## BFS shortest path (by hop count) between two nodes, respecting which gates
## `team` is allowed to use. Falls back to staying put if unreachable.
func find_bot_path(team: String, from: String, to: String) -> Array[String]:
	if from == to:
		return [from]

	var adjacency: Dictionary = {}
	for edge in _bot_edges:
		if edge.get("blocked_for", "") == team:
			continue
		var a: String = edge["a"]
		var b: String = edge["b"]
		if not adjacency.has(a):
			adjacency[a] = []
		if not adjacency.has(b):
			adjacency[b] = []
		adjacency[a].append(b)
		adjacency[b].append(a)

	var queue: Array[String] = [from]
	var came_from: Dictionary = {}
	var visited: Dictionary = {from: true}
	while queue.size() > 0:
		var current: String = queue.pop_front()
		if current == to:
			break
		for next in adjacency.get(current, []):
			if visited.has(next):
				continue
			visited[next] = true
			came_from[next] = current
			queue.append(next)

	if not visited.has(to):
		return [from]
	var path: Array[String] = [to]
	while path[0] != from:
		path.push_front(came_from[path[0]])
	return path
