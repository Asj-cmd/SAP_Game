class_name MeshMerge
extends RefCounted
## Bakes many static meshes into one ArrayMesh with ONE SURFACE PER MATERIAL
## (P3-6). On the Compatibility renderer every surface of every visible mesh is
## a draw call, and again in the sun's shadow pass: a room of furniture pieces
## at 1-3 surfaces each, or a bundle built from seven boxes, costs far more in
## draws than in triangles. Merging happens at load, in code, from the same
## nodes that would otherwise have been drawn; nothing is edited by hand.
##
## Presentation only. Skinned meshes are not merged (they move), and neither is
## anything that is not a MeshInstance3D.

## Surfaces with no material at all are drawn in this one (Godot's default look).
static var _plain: StandardMaterial3D = null

## Every MeshInstance3D under `root` (root included), in root's own space, as
## one mesh. The materials are each surface's active one (override, then
## surface override, then the mesh's own). Null when there is nothing to merge.
static func of_tree(root: Node3D) -> ArrayMesh:
	var tools: Dictionary[Material, SurfaceTool] = {}
	var order: Array[Material] = []
	_collect(root, Transform3D.IDENTITY, tools, order)
	return _commit(tools, order)

## Several trees, each placed by its own transform (as when it is a child of a
## common parent), in that parent's space.
static func of_trees(roots: Array[Node3D]) -> ArrayMesh:
	var tools: Dictionary[Material, SurfaceTool] = {}
	var order: Array[Material] = []
	for root: Node3D in roots:
		_collect(root, root.transform, tools, order)
	return _commit(tools, order)

static func _collect(node: Node, to_space: Transform3D, tools: Dictionary[Material, SurfaceTool],
		order: Array[Material]) -> void:
	var view: MeshInstance3D = node as MeshInstance3D
	if view != null and view.mesh != null and view.skin == null and view.visible:
		for surface: int in view.mesh.get_surface_count():
			if view.mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var material: Material = view.get_active_material(surface)
			if material == null:
				if _plain == null:
					_plain = StandardMaterial3D.new()
				material = _plain
			if not tools.has(material):
				var tool: SurfaceTool = SurfaceTool.new()
				tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[material] = tool
				order.append(material)
			tools[material].append_from(view.mesh, surface, to_space)
	for child: Node in node.get_children():
		var spatial: Node3D = child as Node3D
		_collect(child, to_space * (spatial.transform if spatial != null else Transform3D.IDENTITY),
			tools, order)

static func _commit(tools: Dictionary[Material, SurfaceTool], order: Array[Material]) -> ArrayMesh:
	if order.is_empty():
		return null
	var mesh: ArrayMesh = ArrayMesh.new()
	for material: Material in order:
		var tool: SurfaceTool = tools[material]
		tool.set_material(material)
		tool.commit(mesh)
	return mesh
