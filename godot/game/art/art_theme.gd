class_name ArtTheme
extends Resource
## The whole look in one resource: the figures' material, the house's materials,
## the sky and the lights (STYLE.md; PLAN P1-4).
##
## Every imported mesh has its materials REPLACED from here, so models from
## different sources come out as one game, and changing the look later is an
## edit to `default_theme.tres`, not to code. Presentation only: nothing here is
## read by a rule, has collision, or changes what a body walks through.
##
## Everything is chosen for the Compatibility renderer (D1, D6): StandardMaterial3D,
## vertex colour, omni/spot/directional lights. No outline shader (D2).

const DEFAULT_PATH: String = "res://art/theme/default_theme.tres"

@export_group("Figures")
## Every family member in both families (STYLE §2.3): one smooth satin putty
## grey. Each figure gets its own copy, because the camera fades the local body
## through its material (ChaseCamera fade, P0-6).
@export var figure: StandardMaterial3D = null
## Family colours by team id (STYLE §2.4): wristband (D3 c), HUD, front door.
@export var family_colours: Dictionary[StringName, Color] = {}
## STOPGAP until the D3 team tell exists (P2-4): how far a figure's colour leans
## toward its family colour. 0 is the target (identical families, D3); above 0
## only so a playtest before P2-4 can tell the sides apart.
@export_range(0.0, 1.0) var figure_family_tint: float = 0.0
## The figure every body is drawn as (STYLE §2; `autobuild/figure_bake.mjs`
## makes them from the Quaternius bodies). Empty, or a path that does not exist,
## falls back to the old per-team `character_<team>.glb` and then the capsule.
@export var figure_model: String = ""
## Tallest a figure is drawn: a taller model is scaled down to it, a shorter one
## keeps its height (STYLE §2.2: never above the 180 sim body).
@export var figure_height: float = 180.0
## "Slightly off" (STYLE §2.2): a scale per bone, set as the bone's pose scale.
## A bone's scale carries to everything below it, so "Head" enlarges the head and
## "hand_l"/"hand_r" the hands. Empty = proportions as modelled.
@export var figure_bone_scales: Dictionary[StringName, Vector3] = {}
## The family (STYLE §2.2, P2-1): every member both families can draw. Empty =
## every body is the one `figure_model`, as before P2-1.
@export var family: Array[FamilyMember] = []
## Which member each roster slot is drawn as (slot 0 first; a slot past the end
## wraps). The same for both families unless `family_order_by_team` overrides a
## team (the D3 d kid swap, P2-4).
@export var family_order: PackedStringArray = PackedStringArray(
	["dad", "mom", "elder_girl", "younger_boy"])
@export var family_order_by_team: Dictionary[StringName, PackedStringArray] = {}

@export_group("Imported materials")
## Materials replaced BY NAME when a model is dressed (`dress`): the name the
## source file gave a material -> the theme's material. A model surface whose
## material is not listed gets the dressing role's default instead.
@export var by_source_name: Dictionary[String, StandardMaterial3D] = {}
## Default for a carriable's surfaces not named in `by_source_name`.
@export var cash: StandardMaterial3D = null
## Default for an imported prop's surfaces not named in `by_source_name`
## (`prop_instance`). The import pipeline (godot/art/README.md, P1-6) renames a
## pack's materials to the theme's generic names - wood, fabric, steel, painted
## - so this only shows on a surface nobody mapped.
@export var prop: StandardMaterial3D = null

@export_group("House")
## Blockout boxes are drawn in ONE material with a colour per face direction
## (vertex colour), so every box is still one draw call but a room reads as
## walls, floor and ceiling. The material's own albedo is ignored.
@export var blockout: StandardMaterial3D = null
@export var wall_colour: Color = Color(0.86, 0.83, 0.77)
@export var floor_colour: Color = Color(0.55, 0.4, 0.27)
@export var ceiling_colour: Color = Color(0.92, 0.91, 0.88)
## The lot's ground box (the widest blocker): its top is lawn, not floor.
@export var lawn_colour: Color = Color(0.36, 0.5, 0.3)
## The top of the highest boxes (the roofs): STYLE §3.3 roof tile.
@export var roof_colour: Color = Color(0.3, 0.3, 0.32)
## Floor finish per room KIND (zone id without its team suffix: "kitchen",
## "jail", "landing_a" ...). Laid on the walkable floor of each zone, clipped to
## it (FloorTint). A zone kind not listed shows the slab's own floor colour.
@export var floors: Dictionary[StringName, StandardMaterial3D] = {}

@export_group("Daylight")
@export var sky_top: Color = Color(0.33, 0.56, 0.86)
@export var sky_horizon: Color = Color(0.78, 0.85, 0.92)
@export var grass: Color = Color(0.36, 0.5, 0.3)
@export var sun_colour: Color = Color(1.0, 0.95, 0.86)
@export var sun_energy: float = 1.15
## One shadowed light at most (STYLE §4, budgets). Without it the sun lights
## every upward face inside the house exactly as it lights the lawn, so an
## interior cannot read as an interior.
@export var sun_shadows: bool = true
## How far from the camera the sun's shadow reaches, in units.
@export var sun_shadow_distance: float = 4000.0
## 1 = one orthogonal shadow map (cheapest: the shadow pass draws each caster
## once), 2 or 4 = that many cascades (sharper near the camera, a pass each).
@export_range(1, 4) var sun_shadow_splits: int = 1
@export var fill_colour: Color = Color(0.85, 0.9, 1.0)
@export var fill_energy: float = 0.45
## Light from straight above, no shadow: the sky and the bounce off floors,
## faked as a third directional light (base pass on Compatibility, so nearly
## free). Inside the sun's shadow it is what keeps floors brighter than walls and
## ceilings darkest (STYLE §4) where flat ambient would light all six alike.
@export var sky_fill_colour: Color = Color(1.0, 0.9, 0.78)
@export var sky_fill_energy: float = 0.35
## Where it comes FROM. Tilted off vertical so the two wall directions the
## cool fill misses (-x, +z) get a little of it too, and every wall stays
## brighter than the ceiling, which gets none.
@export var sky_fill_from: Vector3 = Vector3(-1.0, 3.0, 1.0)
@export var ambient_colour: Color = Color(0.62, 0.66, 0.74)
@export var ambient_energy: float = 0.65
@export var tonemap: Environment.ToneMapper = Environment.TONE_MAPPER_LINEAR
@export var exposure: float = 1.0
## The tonemapper's white point. Godot's default of 1.0 makes Filmic lift every
## mid-tone toward white (P1-4 frame: the sunlit lawn went lime); 4-6 is usual.
@export var tonemap_white: float = 1.0

@export_group("Interior light")
## One warm ceiling light per indoor room, pointing down (STYLE §4: 2700-3000 K,
## no shadows, at most two touching any object). A spot rather than an omni so
## the cone stops at the room's own walls instead of lighting the house's
## outside faces through them.
##
## OFF by default (P1-4, measured on the GT 730M): Compatibility draws every
## object again for each lamp touching it, and the blockout's walls are long
## boxes every nearby lamp touches - 16 lamps cost ~3.7 ms of GPU in the kitchen
## view, and with the sun's shadow that is 10.2 ms against a 9 ms budget. Indoors
## is warm through the ambient instead. P3-5 turns lamps on room by room once
## fittings and merged meshes exist (STYLE §4).
@export var interior_lamps: bool = false
@export var interior_colour: Color = Color(1.0, 0.84, 0.66)
@export var interior_energy: float = 1.2
@export var interior_range: float = 650.0
@export var interior_angle_deg: float = 62.0
## Per room kind; a kind not listed gets `interior_energy`.
@export var interior_energy_by_kind: Dictionary[StringName, float] = {}
@export var interior_colour_by_kind: Dictionary[StringName, Color] = {}

static var _loaded: ArtTheme = null

## The game's theme: `default_theme.tres` when it exists, else built-in
## defaults, so a checkout without the file still draws (art stays optional).
## `--art-theme=res://...tres` on the command line swaps in another one (the
## P1-5 style slice variants), with no code change.
static func current() -> ArtTheme:
	if _loaded == null:
		var wanted: String = DEFAULT_PATH
		for arg: String in OS.get_cmdline_user_args():
			if arg.begins_with("--art-theme="):
				wanted = arg.trim_prefix("--art-theme=")
		if ResourceLoader.exists(wanted):
			_loaded = load(wanted) as ArtTheme
		if _loaded == null and wanted != DEFAULT_PATH:
			push_error("art theme: cannot load %s, using the default" % wanted)
			if ResourceLoader.exists(DEFAULT_PATH):
				_loaded = load(DEFAULT_PATH) as ArtTheme
		if _loaded == null:
			_loaded = ArtTheme.new()
		_loaded._fill_missing()
	return _loaded

func _fill_missing() -> void:
	if figure == null:
		figure = _material(Color(0.72, 0.69, 0.64), 0.55)
	if cash == null:
		cash = _material(Color(0.45, 0.62, 0.42), 0.7)
	if prop == null:
		prop = _material(Color(0.6, 0.57, 0.52), 0.8)
	if blockout == null:
		blockout = _material(Color.WHITE, 0.9)
	blockout.vertex_color_use_as_albedo = true
	# The face colours are palette (sRGB) values, like every albedo in STYLE.md.
	blockout.vertex_color_is_srgb = true
	if family_colours.is_empty():
		family_colours = {&"team_a": Color(0.48, 0.58, 0.45), &"team_b": Color(0.7, 0.4, 0.3)}

static func _material(colour: Color, roughness: float) -> StandardMaterial3D:
	var made: StandardMaterial3D = StandardMaterial3D.new()
	made.albedo_color = colour
	made.roughness = roughness
	return made

## A room kind from a zone id: "kitchen_a" -> "kitchen", "landing_b_a" -> "landing_b".
static func room_kind(zone_id: StringName) -> StringName:
	var text: String = String(zone_id)
	var cut: int = text.rfind("_")
	return StringName(text.substr(0, cut)) if cut > 0 else zone_id

func family_colour(team: StringName) -> Color:
	return family_colours.get(team, wall_colour)

## A fresh copy of the figure material for one body of `team`.
func figure_material(team: StringName) -> StandardMaterial3D:
	var copy: StandardMaterial3D = figure.duplicate() as StandardMaterial3D
	if figure_family_tint > 0.0 and family_colours.has(team):
		copy.albedo_color = figure.albedo_color.lerp(family_colours[team], figure_family_tint)
	return copy

var _figure_scene: PackedScene = null
var _figure_looked: bool = false

## The theme's figure model, or null when it has none (or it is not built).
func figure_scene() -> PackedScene:
	if not _figure_looked:
		_figure_looked = true
		if figure_model != "" and ResourceLoader.exists(figure_model):
			_figure_scene = load(figure_model) as PackedScene
	return _figure_scene

## The member drawn for roster `slot` of `team`; null when the theme has no
## family (every body is then `figure_model`).
func member_for(team: StringName, slot: int) -> FamilyMember:
	if family.is_empty():
		return null
	var order: PackedStringArray = family_order_by_team.get(team, family_order)
	if order.is_empty():
		return family[0]
	return member(StringName(order[posmod(slot, order.size())]))

## A member by id ("dad", "younger_girl" ...), or null.
func member(id: StringName) -> FamilyMember:
	for each: FamilyMember in family:
		if each != null and each.id == id:
			return each
	return null

var _member_scenes: Dictionary[String, PackedScene] = {}

## The model `who` is drawn as: its own baked body when it exists, else the
## theme's `figure_model`; null when neither is built.
func member_scene(who: FamilyMember) -> PackedScene:
	if who == null or who.model == "":
		return figure_scene()
	if not _member_scenes.has(who.model):
		var found: PackedScene = null
		if ResourceLoader.exists(who.model):
			found = load(who.model) as PackedScene
		_member_scenes[who.model] = found
	var scene: PackedScene = _member_scenes[who.model]
	return scene if scene != null else figure_scene()

## Sizes an instanced figure and applies the bone nudges (the theme's shared
## ones times `who`'s own). Origin stays at the feet, also when a nudge shortens
## the legs. With a member the figure is drawn at exactly the member's height,
## measured AFTER the nudges (a bigger head makes a taller figure, so the body
## is scaled down to make up for it); without one it is only capped at
## `figure_height`, as before P2-1. Only reads local transforms, so it works
## before the figure is in the tree.
func shape_figure(art: Node3D, who: FamilyMember = null) -> void:
	art.scale = Vector3.ONE
	art.position = Vector3.ZERO
	var natural: float = 0.0
	for child: Node in art.get_children():
		natural = maxf(natural, _model_height(child, Transform3D.IDENTITY))
	var scales: Dictionary[StringName, Vector3] = figure_bone_scales.duplicate()
	if who != null:
		for bone_name: StringName in who.bone_scales:
			scales[bone_name] = scales.get(bone_name, Vector3.ONE) * who.bone_scales[bone_name]
	var grown: float = 0.0  # crown raised by the nudges, model units
	var lifted: float = 0.0  # feet raised by the nudges (shorter legs)
	for skeleton: Node in art.find_children("*", "Skeleton3D", true, false):
		var bones: Skeleton3D = skeleton as Skeleton3D
		for bone_name: StringName in scales:
			var bone: int = bones.find_bone(bone_name)
			if bone >= 0:
				bones.set_bone_pose_scale(bone, scales[bone_name])
		var to_art: Transform3D = _chain(art, bones)
		var head: int = bones.find_bone(&"Head")
		if head >= 0:
			var rest_at: Vector3 = to_art * bones.get_bone_global_rest(head).origin
			var posed: Transform3D = bones.get_bone_global_pose(head)
			var stretch: float = posed.basis.get_scale().y / bones.get_bone_global_rest(head).basis.get_scale().y
			grown = maxf(grown, (to_art * posed.origin).y - rest_at.y + (natural - rest_at.y) * (stretch - 1.0))
		var foot: int = bones.find_bone(&"foot_l")
		if foot >= 0:
			lifted = maxf(lifted, (to_art * bones.get_bone_global_pose(foot).origin).y
				- (to_art * bones.get_bone_global_rest(foot).origin).y)
	var drawn: float = natural + grown - lifted
	if drawn <= 0.0:
		return
	var factor: float = 1.0
	if who != null:
		factor = minf(who.height, figure_height) / drawn
	elif drawn > figure_height:
		# Only ever DOWN without a member: a shorter body keeps its own height.
		factor = figure_height / drawn
	art.scale = Vector3.ONE * factor
	art.position = Vector3(0.0, -lifted * factor, 0.0)
## The transform from `node`'s space into `top`'s (top's own transform excluded).
static func _chain(top: Node3D, node: Node3D) -> Transform3D:
	var at: Transform3D = Transform3D.IDENTITY
	var walk: Node = node
	while walk != null and walk != top:
		var spatial: Node3D = walk as Node3D
		if spatial != null:
			at = spatial.transform * at
		walk = walk.get_parent()
	return at

## Height of the tallest mesh at or under `node`, in the units of whatever
## `above` maps into (the meshes sit under a scaled armature, so their own AABB
## is in the source's metres).
static func _model_height(node: Node, above: Transform3D) -> float:
	var here: Transform3D = above
	var spatial: Node3D = node as Node3D
	if spatial != null:
		here = above * spatial.transform
	var tallest: float = 0.0
	var mesh_view: MeshInstance3D = node as MeshInstance3D
	if mesh_view != null and mesh_view.mesh != null:
		tallest = (here * mesh_view.get_aabb()).size.y
	for child: Node in node.get_children():
		tallest = maxf(tallest, _model_height(child, here))
	return tallest

## Replaces every material under `root` from the theme. Surfaces whose source
## material is named in `by_source_name` get that; the rest get `fallback`.
## Uses surface overrides, so the imported mesh itself is never modified.
func dress(root: Node, fallback: StandardMaterial3D) -> void:
	var mesh_view: MeshInstance3D = root as MeshInstance3D
	if mesh_view != null and mesh_view.mesh != null:
		for surface: int in mesh_view.mesh.get_surface_count():
			var own: Material = mesh_view.mesh.surface_get_material(surface)
			var named: StandardMaterial3D = null
			if own != null:
				named = by_source_name.get(own.resource_name, null)
			mesh_view.set_surface_override_material(surface, named if named != null else fallback)
	for child: Node in root.get_children():
		dress(child, fallback)

## An imported prop (a `res://art/props/*.glb` written by tools/import_asset.gd),
## instanced and dressed from the theme; null when the file is not there, so the
## caller keeps its primitive (art stays optional, godot/art/README.md). Drawn
## only: an art mesh never has collision and the simulation never reads it.
func prop_instance(path: String) -> Node3D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		return null
	var made: Node3D = scene.instantiate() as Node3D
	if made == null:
		return null
	dress(made, prop)
	return made

## Every mesh under `root` drawn in one material (a figure: STYLE §2.3 is a
## single material for the whole body). Through material_override, which the
## body fade (GreyBoxMain._set_opacity) fades in place - hence one copy per body.
static func dress_whole(root: Node, material: StandardMaterial3D) -> void:
	var mesh_view: MeshInstance3D = root as MeshInstance3D
	if mesh_view != null:
		mesh_view.material_override = material
	for child: Node in root.get_children():
		dress_whole(child, material)

## A box of `size`, centred on the origin, with each face coloured by which way
## it faces: up = floor (or lawn), down = ceiling, sides = wall. One surface, so
## one draw call, like the BoxMesh it replaces.
func blockout_box(size: Vector3, top_colour: Color) -> ArrayMesh:
	var half: Vector3 = size * 0.5
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	# normal, then the two in-face axes chosen so (u x v) == normal (CCW from outside).
	var faces: Array[Array] = [
		[Vector3.UP, Vector3(0, 0, 1), Vector3(1, 0, 0), top_colour],
		[Vector3.DOWN, Vector3(1, 0, 0), Vector3(0, 0, 1), ceiling_colour],
		[Vector3.RIGHT, Vector3(0, 1, 0), Vector3(0, 0, 1), wall_colour],
		[Vector3.LEFT, Vector3(0, 0, 1), Vector3(0, 1, 0), wall_colour],
		[Vector3.BACK, Vector3(1, 0, 0), Vector3(0, 1, 0), wall_colour],
		[Vector3.FORWARD, Vector3(0, 1, 0), Vector3(1, 0, 0), wall_colour],
	]
	for face: Array in faces:
		var n: Vector3 = face[0]
		var u: Vector3 = face[1]
		var v: Vector3 = face[2]
		var colour: Color = face[3]
		var centre: Vector3 = n * half
		var du: Vector3 = u * half
		var dv: Vector3 = v * half
		var corners: Array[Vector3] = [
			centre - du - dv, centre + du - dv, centre + du + dv, centre - du + dv,
		]
		tool.set_normal(n)
		tool.set_color(colour)
		# Godot's front faces are clockwise seen from outside.
		for index: int in [0, 2, 1, 0, 3, 2]:
			tool.set_normal(n)
			tool.set_color(colour)
			tool.add_vertex(corners[index])
	tool.set_material(blockout)
	return tool.commit()
