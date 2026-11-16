class_name ContactShadows
extends MultiMeshInstance3D
## A soft dark disc on the floor under every figure and every loose cash bundle
## (STYLE §4, P3-5): what puts a body ON the floor rather than pasted over it,
## where the one shadow map is too coarse or the sun does not reach (indoors).
##
## Presentation only. The floor under a point is read from the level's blocker
## boxes (the highest top at or below the feet), so a jumping body's disc stays
## on the floor below and fades and widens with height. One MultiMesh, so every
## disc together is one draw call; unshaded, no depth write, casts nothing.
##
## Each frame: `begin()`, `add()` per body, `finish()`.

const MAX_DISCS: int = 64
## Off the floor, so the disc does not fight it.
const LIFT: float = 1.5
## Horizontal grid for the floor lookup, units.
const CELL: float = 250.0
## A point counts as on a top this far above it (a body's feet sit on the top
## exactly; a drawn position eases a little).
const SNAP: float = 4.0

var _theme: ArtTheme = null
var _blockers: Array[AABB] = []
var _cells: Dictionary[Vector2i, PackedInt32Array] = {}
var _count: int = 0

static func make(blockers: Array[AABB], theme: ArtTheme) -> ContactShadows:
	var made: ContactShadows = ContactShadows.new()
	made.name = "contact_shadows"
	made._theme = theme
	made._blockers = blockers
	made._index()
	var disc: PlaneMesh = PlaneMesh.new()
	disc.size = Vector2(1.0, 1.0)
	var falloff: Gradient = Gradient.new()
	falloff.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	falloff.colors = PackedColorArray([Color(0, 0, 0, 1), Color(0, 0, 0, 0.6), Color(0, 0, 0, 0)])
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = falloff
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	var look: StandardMaterial3D = StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	look.albedo_texture = texture
	look.vertex_color_use_as_albedo = true
	look.disable_receive_shadows = true
	disc.material = look
	var many: MultiMesh = MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.use_colors = true
	many.mesh = disc
	many.instance_count = MAX_DISCS
	many.visible_instance_count = 0
	made.multimesh = many
	made.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Out of the room lamps' reach (WorldBackdrop.OUTDOOR_LAYER): unlit anyway.
	made.layers = WorldBackdrop.OUTDOOR_LAYER
	return made

func begin() -> void:
	_count = 0

## A disc under `feet` (the bottom of a body or a bundle), `radius` across when
## standing on the floor.
func add(feet: Vector3, radius: float) -> void:
	if _count >= MAX_DISCS or _theme == null or _theme.contact_shadow_alpha <= 0.0:
		return
	var ground: float = floor_below(feet)
	if ground == -INF:
		return
	var fade: float = maxf(_theme.contact_shadow_fade_height, 1.0)
	var height: float = maxf(feet.y - ground, 0.0)
	if height >= fade:
		return
	var up: float = height / fade
	var size: float = radius * 2.0 * (1.0 + 0.4 * up)
	var placed: Transform3D = Transform3D(Basis.from_scale(Vector3(size, 1.0, size)),
		Vector3(feet.x, ground + LIFT, feet.z))
	multimesh.set_instance_transform(_count, placed)
	multimesh.set_instance_color(_count, Color(1.0, 1.0, 1.0,
		_theme.contact_shadow_alpha * (1.0 - up) * (1.0 - up)))
	_count += 1

func finish() -> void:
	multimesh.visible_instance_count = _count

## The highest blocker top at or just above-below `point` whose footprint holds
## it: the floor a body there stands on, or would land on. -INF over nothing.
func floor_below(point: Vector3) -> float:
	var best: float = -INF
	var cell: Vector2i = Vector2i(floori(point.x / CELL), floori(point.z / CELL))
	for index: int in _cells.get(cell, PackedInt32Array()):
		var box: AABB = _blockers[index]
		if point.x < box.position.x or point.x > box.end.x \
				or point.z < box.position.z or point.z > box.end.z:
			continue
		var top: float = box.end.y
		if top <= point.y + SNAP and top > best:
			best = top
	return best

func _index() -> void:
	for index: int in _blockers.size():
		var box: AABB = _blockers[index]
		for x: int in range(floori(box.position.x / CELL), floori(box.end.x / CELL) + 1):
			for z: int in range(floori(box.position.z / CELL), floori(box.end.z / CELL) + 1):
				var key: Vector2i = Vector2i(x, z)
				var held: PackedInt32Array = _cells.get(key, PackedInt32Array())
				held.append(index)
				_cells[key] = held
