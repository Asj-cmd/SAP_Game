extends SceneTree
## The asset import pipeline's one step inside Godot (P1-6): turns a downloaded
## static model into a game-ready `.glb` under `res://art/`.
##
##   node autobuild/import_asset.mjs <source .glb/.gltf/.fbx> --out=res://art/props/<name>.glb [...]
##   godot --headless --path godot --script res://tools/import_asset.gd -- --src=<abs path> --out=...
##
## What it does, in order (godot/art/README.md has the whole pipeline):
##  1. Reads the source at RUNTIME (GLTFDocument, or FBXDocument for .fbx), so it
##     never has to be inside the project or imported by the editor first.
##  2. Drops everything that is not a static mesh: cameras, lights, animation,
##     physics bodies, collision shapes and `-col`/`-colonly` hint nodes. ART
##     NEVER CARRIES COLLISION (WORLD_AUTHORING §6). A skinned mesh is refused:
##     characters have their own path (autobuild/figure_bake.mjs).
##  3. Bakes every node transform, an optional yaw, and the scale to world units
##     into the vertices: 1 unit = 1 cm, so a metre-authored asset is ×100.
##     `--units=auto` decides from the size (anything under 20 units on its
##     longest side cannot be a centimetre prop) and SAYS what it decided.
##     `--height=N` instead scales uniformly to an exact height (a table to the
##     120 threshold, STYLE §3.1); `--fit=x,y,z` scales each axis to fit a
##     blockout box exactly.
##  4. Moves the pivot: `base` (default) = feet at the origin, centred on x/z,
##     so a prop placed at a floor point stands on it; `centre`; `keep`.
##  5. Merges every mesh into ONE mesh, one surface per source material name
##     (a surface is a draw call; STYLE "Rules that follow from the renderer").
##  6. Optionally decimates to `--max-tris=N` with the engine's own simplifier
##     (the LODs ImporterMesh generates), taking the first level that fits.
##  7. Replaces materials with plain placeholders that keep only a NAME and
##     the base colour; textures are dropped (UVs are kept, so a theme material
##     may carry a tiled texture). `--material=` renames them to the theme's
##     generic names (wood, fabric, steel ...). In game, ArtTheme.prop_instance /
##     dress maps the name to a theme material (`by_source_name`) or the role
##     default, so a pack's own look never ships (STYLE §3.3).
##  8. Checks the result against the per-asset budget for its `--role`
##     (prop / hero / cash, STYLE "Per asset") and prints a report plus a draft
##     ASSETS.md row. Exit 1 on a missing source, a refused mesh or a blown
##     budget, so a script can trust it.
##
## Flags: --src= --out= --units=auto|m|cm|<factor> --height= --fit=x,y,z
##        --yaw=<deg> --pivot=base|centre|keep --role=prop|hero|cash
##        --max-tris=N --material=name|src:name,... --dry (report only, write nothing)

const MAX_CM_PROP_SIDE: float = 20.0
const METRE: float = 100.0
## Triangles: [typical, hard limit], and the most materials (surfaces) allowed.
const BUDGETS: Dictionary[String, Array] = {
	"prop": [2000, 6000, 2],
	"hero": [6000, 6000, 2],
	"cash": [500, 500, 1],
}
const COLLISION_SUFFIXES: Array[String] = ["-col", "-colonly", "-convcol", "-convcolonly", "_col", "_colonly"]

var _opts: Dictionary[String, String] = {}
var _notes: PackedStringArray = PackedStringArray()
var _dropped: Dictionary[String, int] = {}
var _renames: Dictionary[String, String] = {}

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var eq: int = arg.find("=")
			if eq < 0:
				_opts[arg.substr(2)] = "true"
			else:
				_opts[arg.substr(2, eq - 2)] = arg.substr(eq + 1)
	quit(_run())

func _run() -> int:
	var src: String = _opts.get("src", "")
	var out: String = _opts.get("out", "")
	var role: String = _opts.get("role", "prop")
	if src == "" or (out == "" and not _opts.has("dry")):
		print("usage: --src=<file> --out=res://art/<dir>/<name>.glb [--units= --height= --fit= --yaw= --pivot= --role= --max-tris= --dry]")
		return 2
	if not BUDGETS.has(role):
		print("FAIL unknown --role=%s (prop, hero, cash)" % role)
		return 2
	if not FileAccess.file_exists(src):
		print("FAIL no such file: %s" % src)
		return 1

	# 1. Read.
	var fbx: bool = src.get_extension().to_lower() == "fbx"
	var reader: GLTFDocument = FBXDocument.new() if fbx else GLTFDocument.new()
	var state: GLTFState = FBXState.new() if fbx else GLTFState.new()
	var failed: Error = reader.append_from_file(src, state)
	if failed != OK:
		print("FAIL cannot read %s (error %d)" % [src, failed])
		return 1
	var scene: Node = reader.generate_scene(state)
	if scene == null:
		print("FAIL %s has no scene" % src)
		return 1

	# 2. Collect static meshes, refuse skins, count what is dropped.
	var pieces: Array[Array] = []  # [Mesh, Transform3D]
	if not _collect(scene, Transform3D.IDENTITY, pieces):
		scene.free()
		return 1
	scene.free()
	if pieces.is_empty():
		print("FAIL %s has no mesh" % src)
		return 1
	var source_tris: int = 0
	var source_surfaces: int = 0
	for piece: Array in pieces:
		var mesh: Mesh = piece[0]
		source_surfaces += mesh.get_surface_count()
		source_tris += _mesh_tris(mesh)

	_renames = _material_renames()

	# 3. Orientation first, then the scale measured from the oriented size.
	var turn: Basis = Basis(Vector3.UP, deg_to_rad(float(_opts.get("yaw", "0"))))
	var raw: Dictionary[String, Array] = _merge(pieces, turn)
	var raw_box: AABB = _bounds(raw)
	var scale: Vector3 = _scale_for(raw_box)
	if scale == Vector3.ZERO:
		return 1
	var groups: Dictionary[String, Array] = _merge(pieces, Basis.from_scale(scale) * turn)
	var box: AABB = _bounds(groups)

	# 4. Pivot.
	var pivot: String = _opts.get("pivot", "base")
	var shift: Vector3 = Vector3.ZERO
	match pivot:
		"base":
			shift = Vector3(box.get_center().x, box.position.y, box.get_center().z)
		"centre", "center":
			shift = box.get_center()
		"keep":
			pass
		_:
			print("FAIL unknown --pivot=%s (base, centre, keep)" % pivot)
			return 2
	for key: String in groups:
		var arrays: Array = groups[key][1]
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i: int in verts.size():
			verts[i] -= shift
		arrays[Mesh.ARRAY_VERTEX] = verts
	box.position -= shift

	# 5 + 6. One mesh; decimate if asked.
	var final_mesh: ArrayMesh = _build(groups, int(_opts.get("max-tris", "0")))
	var tris: int = _mesh_tris(final_mesh)

	# 8. Budget.
	var budget: Array = BUDGETS[role]
	var verdict: String = "ok"
	var exit_code: int = 0
	if tris > int(budget[1]) or final_mesh.get_surface_count() > int(budget[2]):
		verdict = "OVER BUDGET (role %s: <= %d triangles, <= %d materials)" % [role, budget[1], budget[2]]
		exit_code = 1
	elif tris > int(budget[0]):
		verdict = "heavy (over the %d typical for a %s; allowed up to %d)" % [budget[0], role, budget[1]]

	print("source    %s" % src)
	print("read      %d mesh node(s), %d surface(s), %d triangles%s" % [pieces.size(), source_surfaces, source_tris,
		"" if _dropped.is_empty() else "; dropped %s" % _describe_dropped()])
	for note: String in _notes:
		print("step      %s" % note)
	print("size      %.1f x %.1f x %.1f cm (w x h x d), pivot %s" % [box.size.x, box.size.y, box.size.z, pivot])
	print("result    1 mesh, %d surface(s) %s, %d triangles" % [final_mesh.get_surface_count(), _surface_names(final_mesh), tris])
	print("budget    %s" % verdict)
	if box.size.y > 400.0 or maxf(box.size.x, maxf(box.size.y, box.size.z)) < 2.0:
		print("WARNING   %.0f cm tall is not a household object; check --units" % box.size.y)

	if _opts.has("dry"):
		print("dry run: nothing written")
		return exit_code
	if exit_code != 0:
		print("FAIL not written: over budget (try --max-tris=%d)" % budget[0])
		return exit_code

	# 7. Write.
	var root: Node3D = Node3D.new()
	root.name = out.get_file().get_basename()
	var view: MeshInstance3D = MeshInstance3D.new()
	view.name = root.name
	view.mesh = final_mesh
	root.add_child(view)
	view.owner = root
	var writer: GLTFDocument = GLTFDocument.new()
	var out_state: GLTFState = GLTFState.new()
	failed = writer.append_from_scene(root, out_state)
	if failed == OK:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out.get_base_dir()))
		failed = writer.write_to_filesystem(out_state, ProjectSettings.globalize_path(out))
	root.free()
	if failed != OK:
		print("FAIL cannot write %s (error %d)" % [out, failed])
		return 1
	print("wrote     %s" % out)
	print("ASSETS.md | %s | %s | %s | %s | Yes, by tools/import_asset.gd: %s | `godot/%s` |" % [
		out.get_file().get_basename(), _opts.get("url", "<source URL>"), _opts.get("licence", "<licence>"),
		Time.get_date_string_from_system(), _modified_summary(box, tris, source_tris), out.trim_prefix("res://")])
	return 0

## Walks the generated scene; appends [mesh, transform-to-root] per mesh node.
## False (and a FAIL line) on anything that must not be imported as a prop.
func _collect(node: Node, above: Transform3D, into: Array[Array]) -> bool:
	var here: Transform3D = above
	var spatial: Node3D = node as Node3D
	if spatial != null:
		here = above * spatial.transform
	var lower: String = String(node.name).to_lower()
	for suffix: String in COLLISION_SUFFIXES:
		if lower.ends_with(suffix):
			_drop("collision hint")
			return true
	if node is CollisionObject3D or node is CollisionShape3D:
		_drop("collision")
		return true
	if node is Camera3D:
		_drop("camera")
		return true
	if node is Light3D:
		_drop("light")
		return true
	if node is AnimationPlayer:
		_drop("animation")
		return true
	if node is Skeleton3D:
		print("FAIL skinned model (Skeleton3D '%s'): characters go through autobuild/figure_bake.mjs, not this" % node.name)
		return false
	var mesh: Mesh = null
	if node is MeshInstance3D:
		var shown: MeshInstance3D = node as MeshInstance3D
		if shown.skin != null:
			print("FAIL skinned mesh '%s': characters go through autobuild/figure_bake.mjs" % node.name)
			return false
		mesh = shown.mesh
	elif node is ImporterMeshInstance3D:
		var raw: ImporterMeshInstance3D = node as ImporterMeshInstance3D
		if raw.skin != null:
			print("FAIL skinned mesh '%s': characters go through autobuild/figure_bake.mjs" % node.name)
			return false
		if raw.mesh != null:
			mesh = raw.mesh.get_mesh()
	if mesh != null:
		into.append([mesh, here])
	for child: Node in node.get_children():
		if not _collect(child, here, into):
			return false
	return true

func _drop(what: String) -> void:
	_dropped[what] = _dropped.get(what, 0) + 1

func _describe_dropped() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for what: String in _dropped:
		parts.append("%d %s" % [_dropped[what], what])
	return ", ".join(parts)

## Every piece transformed by `basis` then its own node transform, merged into
## one SurfaceTool per (source material name, vertex format).
## Returns key -> [material name, arrays, source material].
func _merge(pieces: Array[Array], basis: Basis) -> Dictionary[String, Array]:
	var tools: Dictionary[String, SurfaceTool] = {}
	var meta: Dictionary[String, Array] = {}
	var normals: Dictionary[String, bool] = {}
	for piece: Array in pieces:
		var mesh: Mesh = piece[0]
		var placed: Transform3D = Transform3D(basis, Vector3.ZERO) * (piece[1] as Transform3D)
		for surface: int in mesh.get_surface_count():
			if mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
				_drop("non-triangle surface")
				continue
			var material: Material = mesh.surface_get_material(surface)
			var name: String = material.resource_name if material != null and material.resource_name != "" else "surface"
			if _renames.has(name):
				name = _renames[name]
			elif _renames.has("*"):
				name = _renames["*"]
			# Only the attribute bits (vertex .. index); flags above them differ
			# between otherwise mergeable surfaces.
			var format: int = mesh.surface_get_format(surface) & ((1 << Mesh.ARRAY_FORMAT_CUSTOM_BASE) - 1)
			var key: String = "%s|%d" % [name, format]
			if not tools.has(key):
				var tool: SurfaceTool = SurfaceTool.new()
				tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[key] = tool
				meta[key] = [name, material]
				normals[key] = (format & Mesh.ARRAY_FORMAT_NORMAL) != 0
			tools[key].append_from(mesh, surface, placed)
	var merged: Dictionary[String, Array] = {}
	for key: String in tools:
		var tool: SurfaceTool = tools[key]
		if not normals[key]:
			tool.generate_normals()
		tool.index()
		merged[key] = [meta[key][0], tool.commit_to_arrays(), meta[key][1]]
	return merged

func _bounds(groups: Dictionary[String, Array]) -> AABB:
	var box: AABB = AABB()
	var first: bool = true
	for key: String in groups:
		var verts: PackedVector3Array = (groups[key][1] as Array)[Mesh.ARRAY_VERTEX]
		for v: Vector3 in verts:
			if first:
				box = AABB(v, Vector3.ZERO)
				first = false
			else:
				box = box.expand(v)
	return box

## The scale from source units to centimetres; ZERO (and a FAIL line) if the
## flags make no sense.
func _scale_for(raw: AABB) -> Vector3:
	var longest: float = maxf(raw.size.x, maxf(raw.size.y, raw.size.z))
	if longest <= 0.0:
		print("FAIL the mesh has no size")
		return Vector3.ZERO
	if _opts.has("fit"):
		var parts: PackedStringArray = _opts["fit"].split(",")
		if parts.size() != 3:
			print("FAIL --fit wants x,y,z in cm")
			return Vector3.ZERO
		var want: Vector3 = Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
		var each: Vector3 = Vector3(want.x / maxf(raw.size.x, 1e-6), want.y / maxf(raw.size.y, 1e-6),
			want.z / maxf(raw.size.z, 1e-6))
		_notes.append("--fit to %s: x %.3f, y %.3f, z %.3f (non-uniform)" % [_opts["fit"], each.x, each.y, each.z])
		return each
	if _opts.has("height"):
		var factor: float = float(_opts["height"]) / maxf(raw.size.y, 1e-6)
		_notes.append("--height=%s: uniform x%.3f (source %.3f tall)" % [_opts["height"], factor, raw.size.y])
		return Vector3.ONE * factor
	var units: String = _opts.get("units", "auto")
	var chosen: float = 1.0
	match units:
		"auto":
			if longest < MAX_CM_PROP_SIDE:
				chosen = METRE
				_notes.append("auto: longest side %.3f < %.0f, read as METRES, x100" % [longest, MAX_CM_PROP_SIDE])
			else:
				_notes.append("auto: longest side %.1f, read as CENTIMETRES, x1" % longest)
		"m":
			chosen = METRE
			_notes.append("--units=m: x100")
		"cm":
			_notes.append("--units=cm: x1")
		_:
			chosen = float(units)
			if chosen <= 0.0:
				print("FAIL --units wants auto, m, cm or a factor")
				return Vector3.ZERO
			_notes.append("--units=%s" % units)
	return Vector3.ONE * chosen

## The final mesh: one surface per group with a placeholder material that keeps
## only the source name and base colour. `max_tris` > 0 decimates.
func _build(groups: Dictionary[String, Array], max_tris: int) -> ArrayMesh:
	var keys: Array[String] = []
	for key: String in groups:
		keys.append(key)
	keys.sort()
	var surfaces: Array[Array] = []  # [arrays, placeholder]
	for key: String in keys:
		var name: String = groups[key][0]
		var source: Material = groups[key][2]
		var placeholder: StandardMaterial3D = StandardMaterial3D.new()
		placeholder.resource_name = name
		var base: BaseMaterial3D = source as BaseMaterial3D
		if base != null:
			placeholder.albedo_color = base.albedo_color
			placeholder.roughness = base.roughness
			placeholder.metallic = base.metallic
		surfaces.append([groups[key][1], placeholder])

	var total: int = 0
	for surface: Array in surfaces:
		total += _array_tris(surface[0])
	if max_tris > 0 and total > max_tris:
		# Every surface shrinks by the same ratio. The engine's LOD generator
		# (meshoptimizer, normal- and UV-aware) is run again on its own smallest
		# level until the surface fits or a round gains < 10 %. Measured on Poly
		# Haven's 5.6k ArmChair_01: one level at exactly half, then nothing, at
		# any normal-merge angle (25/90/180) - it will not break UV or normal
		# seams. A model that must go lower is decimated in Blender first.
		var ratio: float = float(max_tris) / float(total)
		var after: int = 0
		var rounds: int = 0
		for s: int in surfaces.size():
			var arrays: Array = surfaces[s][0]
			var want: int = maxi(1, int(_array_tris(arrays) * ratio))
			for pass_no: int in 8:
				var have: int = _array_tris(arrays)
				if have <= want:
					break
				var step: ImporterMesh = ImporterMesh.new()
				step.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, surfaces[s][1] as Material, "s")
				step.generate_lods(25.0, 60.0, [])
				var picked: PackedInt32Array = PackedInt32Array()
				for lod: int in step.get_surface_lod_count(0):
					picked = step.get_surface_lod_indices(0, lod)
					if picked.size() / 3 <= want:
						break
				if picked.is_empty() or picked.size() / 3 > int(have * 0.9):
					break
				arrays[Mesh.ARRAY_INDEX] = picked
				arrays = _compact(arrays)
				rounds = maxi(rounds, pass_no + 1)
			surfaces[s][0] = arrays
			after += _array_tris(arrays)
		_notes.append("decimated %d -> %d triangles (asked <= %d, %d round(s))" % [total, after, max_tris, rounds])
		if after > max_tris:
			_notes.append("could NOT reach %d: the simplifier stops where the shape would break" % max_tris)

	var mesh: ArrayMesh = ArrayMesh.new()
	for surface: Array in surfaces:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface[0])
		mesh.surface_set_material(mesh.get_surface_count() - 1, surface[1])
	return mesh

## `--material=wood` names every surface's material "wood"; `--material=Seat:fabric,Legs:wood`
## renames by source name (unlisted ones keep theirs). The names are the ones
## ArtTheme.by_source_name maps to theme materials, so a pack's own material
## names never have to appear in the theme. Surfaces renamed alike merge into
## one surface (one draw call).
func _material_renames() -> Dictionary[String, String]:
	var renames: Dictionary[String, String] = {}
	var text: String = _opts.get("material", "")
	if text == "":
		return renames
	for part: String in text.split(","):
		var colon: int = part.find(":")
		if colon < 0:
			renames["*"] = part.strip_edges()
		else:
			renames[part.substr(0, colon).strip_edges()] = part.substr(colon + 1).strip_edges()
	_notes.append("materials renamed %s" % text)
	return renames

## Drops the vertices no triangle uses any more (after decimation the index
## buffer is smaller but every vertex is still there) and renumbers the rest.
## Only per-vertex attributes a static prop can have; skins are refused earlier.
static func _compact(arrays: Array) -> Array:
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var remap: PackedInt32Array = PackedInt32Array()
	remap.resize(verts.size())
	remap.fill(-1)
	var keep: PackedInt32Array = PackedInt32Array()
	for i: int in indices.size():
		var old: int = indices[i]
		if remap[old] < 0:
			remap[old] = keep.size()
			keep.append(old)
		indices[i] = remap[old]
	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_INDEX] = indices
	# [array slot, components per vertex]
	var slots: Array[Array] = [[Mesh.ARRAY_VERTEX, 1], [Mesh.ARRAY_NORMAL, 1], [Mesh.ARRAY_TANGENT, 4],
		[Mesh.ARRAY_COLOR, 1], [Mesh.ARRAY_TEX_UV, 1], [Mesh.ARRAY_TEX_UV2, 1]]
	for slot: Array in slots:
		var at: int = slot[0]
		var width: int = slot[1]
		var source: Variant = arrays[at]
		if source == null:
			continue
		var picked: Variant = source.duplicate()
		picked.resize(keep.size() * width)
		for n: int in keep.size():
			for c: int in width:
				picked[n * width + c] = source[keep[n] * width + c]
		out[at] = picked
	return out

static func _array_tris(arrays: Array) -> int:
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if indices.size() > 0:
		return indices.size() / 3
	return (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3

static func _mesh_tris(mesh: Mesh) -> int:
	var count: int = 0
	for surface: int in mesh.get_surface_count():
		count += _array_tris(mesh.surface_get_arrays(surface))
	return count

static func _surface_names(mesh: Mesh) -> String:
	var names: PackedStringArray = PackedStringArray()
	for surface: int in mesh.get_surface_count():
		var material: Material = mesh.surface_get_material(surface)
		names.append(material.resource_name if material != null else "?")
	return "[%s]" % ", ".join(names)

func _modified_summary(box: AABB, tris: int, source_tris: int) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for note: String in _notes:
		parts.append(note)
	parts.append("pivot %s" % _opts.get("pivot", "base"))
	parts.append("merged to one mesh")
	parts.append("textures dropped, materials from the ArtTheme")
	parts.append("%.0f x %.0f x %.0f cm" % [box.size.x, box.size.y, box.size.z])
	return "; ".join(parts)
