class_name FurnitureDresser
extends RefCounted
## Draws the level's furniture (LevelDef.props, P3-3). Presentation only: the
## pieces that block are blockers in the level already (tools/build_house.gd
## writes both from one table), and nothing here feeds collision or the sim.
##
## A fitted piece is scaled per axis to fill its box EXACTLY, so what a player
## sees is what they hit: a counter's top is at 120 because its collision is.
## Imported models come from the theme (`furniture_models`); the two silhouettes
## nothing else in the house may share are built here: the SAFE (squat, dark
## steel, a dial and a wheel) and the jail PEN (a cage of round bars with its
## gate open). A model that is missing is drawn as a plain box of the theme's
## `prop` material, so the house never has invisible furniture.

const BAR_RADIUS: float = 2.2
const BAR_SPACING: float = 14.0
const POST: float = 8.0
const RAIL: float = 6.0

## Furniture is merged per square of this many units (P3-6): one mesh per
## square, a surface per material. A square is about a room pair, so a view
## still culls the far side of a house and the other house.
const MERGE_CELL: float = 1200.0

## One node holding every piece, merged (MeshMerge) into a mesh per MERGE_CELL
## square by the centre of each piece's box. `merge = false` keeps one node per
## piece (named by model), for looking at a single piece.
static func build(props: Array[PropPlacement], theme: ArtTheme, merge: bool = true) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "Furniture"
	var cells: Dictionary[Vector2i, Array] = {}
	var order: Array[Vector2i] = []
	for placement: PropPlacement in props:
		var piece: Node3D = null
		if placement.family != &"":
			piece = _yard(theme.yard_kind(placement.family, placement.model), placement, theme)
		else:
			match placement.model:
				&"safe":
					piece = _safe(placement, theme)
				&"jail_pen":
					piece = _pen(placement, theme)
				_:
					piece = _model(placement, theme)
		if piece == null:
			continue
		if not merge:
			root.add_child(piece)
			continue
		var centre: Vector3 = placement.box.get_center() if placement.box.size.x > 0.0 else placement.box.position
		var cell: Vector2i = Vector2i(floori(centre.x / MERGE_CELL), floori(centre.z / MERGE_CELL))
		if not cells.has(cell):
			cells[cell] = []
			order.append(cell)
		cells[cell].append(piece)
	for cell: Vector2i in order:
		var pieces: Array[Node3D] = []
		pieces.assign(cells[cell])
		var mesh: ArrayMesh = MeshMerge.of_trees(pieces)
		for piece: Node3D in pieces:
			piece.free()
		if mesh == null:
			continue
		var view: MeshInstance3D = MeshInstance3D.new()
		view.name = "furniture_%d_%d" % [cell.x, cell.y]
		view.mesh = mesh
		root.add_child(view)
	return root

## An imported model, turned to face `yaw_deg` and fitted to its box (or stood
## on the box's point at its own size).
static func _model(placement: PropPlacement, theme: ArtTheme) -> Node3D:
	var made: Node3D = theme.prop_instance(theme.furniture_models.get(placement.model, ""))
	if made == null:
		return _stand_in(placement, theme)
	var bounds: AABB = _bounds(made, Transform3D.IDENTITY)
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0 or bounds.size.z <= 0.0:
		return _stand_in(placement, theme)
	var yaw: float = fmod(placement.yaw_deg + theme.furniture_front_yaw, 360.0)
	var turn: Basis = Basis(Vector3.UP, deg_to_rad(yaw))
	var basis: Basis = turn
	var box: AABB = placement.box
	# Bottom centre to bottom centre.
	var anchor: Vector3 = Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	var target: Vector3 = box.position
	if placement.fit and box.size.x > 0.0:
		target = Vector3(box.get_center().x, box.position.y, box.get_center().z)
		var top: float = bounds.end.y
		var top_name: String = theme.furniture_top_surface.get(placement.model, "")
		if top_name != "":
			top = _surface_top(made, top_name, Transform3D.IDENTITY, bounds.end.y)
		# A quarter turn swaps which model axis lies along world x.
		var quarter: bool = absf(sin(deg_to_rad(yaw))) > 0.5
		var want: Vector3 = Vector3(box.size.z, box.size.y, box.size.x) if quarter else box.size
		basis = turn * Basis.from_scale(Vector3(want.x / bounds.size.x,
			want.y / maxf(top - bounds.position.y, 0.01), want.z / bounds.size.z))
	made.transform = Transform3D(basis, target - basis * anchor)
	made.name = String(placement.model)
	return made

## A missing model: a plain box filling the collision box, never nothing.
static func _stand_in(placement: PropPlacement, theme: ArtTheme) -> Node3D:
	if not placement.fit or placement.box.size.x <= 0.0:
		return null
	var view: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = placement.box.size
	view.mesh = mesh
	view.material_override = theme.prop
	view.position = placement.box.get_center()
	view.name = "%s_stand_in" % placement.model
	return view

## The safe: a dark steel block on a plinth, a raised door on its front with a
## dial and a three-spoke wheel, two hinge barrels. Fills its box; one mesh,
## two surfaces (body, brass-ish trim).
static func _safe(placement: PropPlacement, theme: ArtTheme) -> Node3D:
	var size: Vector3 = placement.box.size
	var quarter: bool = absf(sin(deg_to_rad(placement.yaw_deg))) > 0.5
	# Model space: front faces +z, width along x.
	var w: float = size.z if quarter else size.x
	var d: float = size.x if quarter else size.z
	var h: float = size.y
	var body: SurfaceTool = SurfaceTool.new()
	body.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trim: SurfaceTool = SurfaceTool.new()
	trim.begin(Mesh.PRIMITIVE_TRIANGLES)
	var plinth: float = 8.0
	var door: float = 3.0
	_box_into(body, Vector3(0.0, plinth * 0.5, -door * 0.5), Vector3(w - 8.0, plinth, d - door - 8.0))
	_box_into(body, Vector3(0.0, plinth + (h - plinth) * 0.5, -door * 0.5),
		Vector3(w, h - plinth, d - door))
	var face_z: float = d * 0.5 - door
	var inset: float = 9.0
	_box_into(body, Vector3(0.0, plinth + (h - plinth) * 0.5, face_z + door * 0.5),
		Vector3(w - inset * 2.0, h - plinth - inset * 2.0, door))
	var front: float = d * 0.5
	# A cylinder's own axis is y; a dial and a hub face +z.
	var facing: Basis = Basis(Vector3.RIGHT, PI * 0.5)
	var dial_at: Vector3 = Vector3(-w * 0.12, plinth + (h - plinth) * 0.62, front)
	_cylinder_into(trim, dial_at + Vector3(0.0, 0.0, 2.0), 9.0, 4.0, 12, facing)
	var wheel_at: Vector3 = Vector3(w * 0.16, plinth + (h - plinth) * 0.45, front)
	_cylinder_into(trim, wheel_at + Vector3(0.0, 0.0, 3.0), 4.0, 6.0, 8, facing)
	for spoke: int in 3:
		var angle: float = TAU * float(spoke) / 3.0 + PI * 0.5
		var out: Vector3 = Vector3(cos(angle), sin(angle), 0.0)
		var spoke_basis: Basis = Basis(Vector3.BACK, angle)
		_box_into(trim, wheel_at + out * 8.0 + Vector3(0.0, 0.0, 4.5),
			Vector3(16.0, 2.4, 2.4), spoke_basis)
		_box_into(trim, wheel_at + out * 16.0 + Vector3(0.0, 0.0, 4.5), Vector3(3.6, 3.6, 3.6))
	for hinge: float in [0.28, 0.72]:
		_cylinder_into(trim, Vector3(-w * 0.5 + inset * 0.5, plinth + (h - plinth) * hinge, front - 1.0),
			2.2, 14.0, 8)
	var mesh: ArrayMesh = body.commit()
	mesh = trim.commit(mesh)
	mesh.surface_set_material(0, theme.safe_body if theme.safe_body != null else theme.prop)
	mesh.surface_set_material(1, theme.safe_trim if theme.safe_trim != null else theme.prop)
	return _placed(mesh, placement, "safe")

## The pen: corner posts, top and bottom rails, round bars every BAR_SPACING,
## and the gate gap (PropPlacement.PEN_GATE) left open in the middle of the
## front side, framed by two posts. Matches build_house.gd's collision boxes:
## PEN_BAR thick, the box's full height.
static func _pen(placement: PropPlacement, theme: ArtTheme) -> Node3D:
	var size: Vector3 = placement.box.size
	var quarter: bool = absf(sin(deg_to_rad(placement.yaw_deg))) > 0.5
	var w: float = size.z if quarter else size.x
	var d: float = size.x if quarter else size.z
	var h: float = size.y
	var bar: float = PropPlacement.PEN_BAR
	var gate: float = PropPlacement.PEN_GATE
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Each side as a segment in model space (front = +z), inset to the bars'
	# middle so the bars sit inside the collision.
	var hx: float = w * 0.5 - bar * 0.5
	var hz: float = d * 0.5 - bar * 0.5
	var sides: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(-hx, -hz), Vector2(hx, -hz)]), # back
		PackedVector2Array([Vector2(-hx, -hz), Vector2(-hx, hz)]),
		PackedVector2Array([Vector2(hx, -hz), Vector2(hx, hz)]),
		PackedVector2Array([Vector2(-hx, hz), Vector2(-gate * 0.5, hz)]), # front, left of the gate
		PackedVector2Array([Vector2(gate * 0.5, hz), Vector2(hx, hz)]),
	]
	for side: PackedVector2Array in sides:
		var a: Vector2 = side[0]
		var b: Vector2 = side[1]
		var length: float = a.distance_to(b)
		var mid: Vector2 = (a + b) * 0.5
		var along_x: bool = absf(b.x - a.x) > absf(b.y - a.y)
		var rail_size: Vector3 = Vector3(length, RAIL, RAIL) if along_x else Vector3(RAIL, RAIL, length)
		for rail_y: float in [RAIL * 0.5 + 4.0, h - RAIL * 0.5, h * 0.55]:
			_box_into(tool, Vector3(mid.x, rail_y, mid.y), rail_size)
		var count: int = maxi(1, int(round(length / BAR_SPACING)))
		for i: int in range(1, count):
			var at: Vector2 = a.lerp(b, float(i) / float(count))
			_cylinder_into(tool, Vector3(at.x, h * 0.5, at.y), BAR_RADIUS, h, 6)
		for end: Vector2 in [a, b]:
			_box_into(tool, Vector3(end.x, h * 0.5, end.y), Vector3(POST, h, POST))
	var mesh: ArrayMesh = tool.commit()
	mesh.surface_set_material(0, theme.pen_bars if theme.pen_bars != null else theme.prop)
	return _placed(mesh, placement, "jail_pen")

## Plain colours for the yard pieces' materials the theme does not have.
const YARD_FALLBACK: Dictionary[StringName, Color] = {
	&"fence_wood": Color(0.45, 0.33, 0.23), &"fence_post": Color(0.36, 0.27, 0.19),
	&"fence_steel": Color(0.1, 0.105, 0.11), &"fence_cap": Color(0.72, 0.69, 0.63),
	&"soil": Color(0.25, 0.19, 0.14), &"hedge": Color(0.2, 0.33, 0.17),
	&"bin": Color(0.16, 0.25, 0.17), &"door": Color(0.2, 0.22, 0.25),
}

## A yard prop (P3-8): plain household things built from boxes, each filling
## its collision box exactly, so what you see is what you hit. The two
## families get different things in the same box (`ArtTheme.yard_models`).
## An unknown kind is the plain stand-in box.
static func _yard(kind: StringName, placement: PropPlacement, theme: ArtTheme) -> Node3D:
	var size: Vector3 = placement.box.size
	var quarter: bool = absf(sin(deg_to_rad(placement.yaw_deg))) > 0.5
	# Model space: front faces +z, width along x, floor at y 0.
	var w: float = size.z if quarter else size.x
	var d: float = size.x if quarter else size.z
	var h: float = size.y
	var parts: Array[Array] = [] # [material key, centre, size]
	match kind:
		&"picnic_table":
			parts.append([&"fence_wood", Vector3(0.0, h - 4.0, 0.0), Vector3(w, 8.0, d * 0.6)])
			for side: float in [-1.0, 1.0]:
				parts.append([&"fence_wood", Vector3(0.0, 66.0, side * (d * 0.5 - 12.0)),
					Vector3(w * 0.94, 6.0, 24.0)])
			for end: float in [-1.0, 1.0]:
				var x: float = end * (w * 0.5 - 24.0)
				for side: float in [-1.0, 1.0]:
					parts.append([&"fence_post", Vector3(x, (h - 8.0) * 0.5, side * d * 0.2),
						Vector3(9.0, h - 8.0, 9.0)])
				parts.append([&"fence_post", Vector3(x, 60.0, 0.0), Vector3(9.0, 6.0, d - 2.0)])
		&"barbecue":
			parts.append([&"brick", Vector3(0.0, 45.0, 0.0), Vector3(w, 90.0, d)])
			parts.append([&"fence_cap", Vector3(0.0, 93.0, 0.0), Vector3(w, 6.0, d)])
			parts.append([&"fence_steel", Vector3(0.0, 108.0, 0.0), Vector3(w * 0.5, 24.0, d * 0.75)])
			parts.append([&"fence_steel", Vector3(0.0, 119.0, 0.0), Vector3(w * 0.54, 2.0, d * 0.8)])
		&"shed":
			parts.append([&"fence_wood", Vector3(0.0, 100.0, 0.0), Vector3(w - 10.0, 200.0, d - 10.0)])
			parts.append([&"roof", Vector3(0.0, 215.0, 0.0), Vector3(w, 30.0, d)])
			parts.append([&"fence_post", Vector3(0.0, 90.0, d * 0.5 - 4.0), Vector3(84.0, 180.0, 2.0)])
		&"outhouse":
			parts.append([&"brick", Vector3(0.0, 102.0, 0.0), Vector3(w - 8.0, 204.0, d - 8.0)])
			parts.append([&"fence_cap", Vector3(0.0, 217.0, 0.0), Vector3(w, 26.0, d)])
			parts.append([&"door", Vector3(0.0, 96.0, d * 0.5 - 3.0), Vector3(84.0, 192.0, 2.0)])
		&"compost_bin":
			parts.append([&"bin", Vector3(0.0, 55.0, 0.0), Vector3(w - 8.0, 110.0, d - 8.0)])
			parts.append([&"bin", Vector3(0.0, 115.0, 0.0), Vector3(w, 10.0, d)])
		&"planter":
			parts.append([&"fence_wood", Vector3(0.0, 50.0, 0.0), Vector3(w, 100.0, d)])
			parts.append([&"soil", Vector3(0.0, 100.5, 0.0), Vector3(w - 12.0, 1.0, d - 12.0)])
			parts.append([&"hedge", Vector3(0.0, 110.0, 0.0), Vector3(w * 0.62, 20.0, d * 0.62)])
		_:
			return _stand_in(placement, theme)
	var tools: Dictionary[StringName, SurfaceTool] = {}
	var order: Array[StringName] = []
	for part: Array in parts:
		var key: StringName = part[0]
		if not tools.has(key):
			var tool: SurfaceTool = SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[key] = tool
			order.append(key)
		_sized_box_into(tools[key], part[1], part[2])
	var mesh: ArrayMesh = null
	for key: StringName in order:
		mesh = tools[key].commit(mesh) if mesh != null else tools[key].commit()
		mesh.surface_set_material(mesh.get_surface_count() - 1, _yard_material(key, theme))
	return _placed(mesh, placement, String(kind))

## A box whose UVs are its size in units (ShellBuilder's convention), so a
## tiled theme texture (brick, boards, roof tile) shows at its true size.
static func _sized_box_into(tool: SurfaceTool, centre: Vector3, size: Vector3) -> void:
	var half: Vector3 = size * 0.5
	for axis: int in 3:
		for sign: float in [-1.0, 1.0]:
			var u: int = (axis + 1) % 3
			var w: int = (axis + 2) % 3
			var normal: Vector3 = Vector3.ZERO
			normal[axis] = sign
			var corners: Array[Vector3] = []
			for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var p: Vector3 = centre
				p[axis] += sign * half[axis]
				p[u] += corner.x * half[u]
				p[w] += corner.y * half[w]
				corners.append(p)
			var turning: float = (corners[1] - corners[0]).cross(corners[2] - corners[0]).dot(normal)
			var order: Array[int] = ShellBuilder.QUAD_TURNED if turning > 0.0 else ShellBuilder.QUAD_AS_IS
			for index: int in order:
				tool.set_normal(normal)
				tool.set_uv(ShellBuilder._uv(corners[index], normal))
				tool.add_vertex(corners[index])

static func _yard_material(key: StringName, theme: ArtTheme) -> Material:
	match key:
		&"brick":
			return theme.wall_outside
		&"roof":
			return theme.roof
	var found: StandardMaterial3D = theme.exterior_materials.get(key, null)
	if found != null:
		return found
	var made: StandardMaterial3D = StandardMaterial3D.new()
	made.albedo_color = YARD_FALLBACK.get(key, Color(0.6, 0.6, 0.6))
	made.roughness = 0.85
	return made

## A model-space mesh (front +z, centred on x/z, floor at y 0) put at its box.
static func _placed(mesh: ArrayMesh, placement: PropPlacement, label: String) -> Node3D:
	var view: MeshInstance3D = MeshInstance3D.new()
	view.mesh = mesh
	view.name = label
	var box: AABB = placement.box
	view.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(placement.yaw_deg)),
		Vector3(box.get_center().x, box.position.y, box.get_center().z))
	return view

static func _box_into(tool: SurfaceTool, centre: Vector3, size: Vector3,
		turn: Basis = Basis.IDENTITY) -> void:
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	tool.append_from(box, 0, Transform3D(turn, centre))

static func _cylinder_into(tool: SurfaceTool, centre: Vector3, radius: float, height: float,
		sides: int, turn: Basis = Basis.IDENTITY) -> void:
	var cylinder: CylinderMesh = CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = height
	cylinder.radial_segments = sides
	cylinder.rings = 1
	tool.append_from(cylinder, 0, Transform3D(turn, centre))

## The highest vertex of the surfaces whose material is named `surface_name`,
## in the root's space; `fallback` when no surface has that name.
static func _surface_top(node: Node, surface_name: String, to_root: Transform3D,
		fallback: float) -> float:
	var best: float = -INF
	var view: MeshInstance3D = node as MeshInstance3D
	if view != null and view.mesh != null:
		for surface: int in view.mesh.get_surface_count():
			var material: Material = view.mesh.surface_get_material(surface)
			if material == null or material.resource_name != surface_name:
				continue
			var points: PackedVector3Array = view.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for point: Vector3 in points:
				best = maxf(best, (to_root * point).y)
	for child: Node in node.get_children():
		var spatial: Node3D = child as Node3D
		var inner: float = _surface_top(child, surface_name,
			to_root * (spatial.transform if spatial != null else Transform3D.IDENTITY), -INF)
		best = maxf(best, inner)
	return best if best > -INF else fallback

## The model's bounds in its own root's space, over every mesh under it.
static func _bounds(node: Node, to_root: Transform3D) -> AABB:
	var here: Transform3D = to_root
	var found: AABB = AABB()
	var any: bool = false
	var view: MeshInstance3D = node as MeshInstance3D
	if view != null and view.mesh != null:
		found = here * view.mesh.get_aabb()
		any = true
	for child: Node in node.get_children():
		var child_spatial: Node3D = child as Node3D
		var child_to_root: Transform3D = here * (child_spatial.transform if child_spatial != null else Transform3D.IDENTITY)
		var inner: AABB = _bounds(child, child_to_root)
		if inner.size == Vector3.ZERO and inner.position == Vector3.ZERO:
			continue
		found = inner if not any else found.merge(inner)
		any = true
	return found
