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
## wraps). The same for both families unless the kid swap is on.
@export var family_order: PackedStringArray = PackedStringArray(
	["dad", "mom", "elder_girl", "younger_boy"])
## Per team, the order used INSTEAD while the D3 (d) kid swap is on (TeamTell,
## P2-4): family B's children are the other way round.
@export var family_order_by_team: Dictionary[StringName, PackedStringArray] = {}
## Family outfits (D3 default since 2026-11-14, P2-1b): each family's colour
## scheme, team id -> {role: Color}. A member's `outfit` says which role each
## painted region of its body wears, so a family reads as one family in matching
## clothes and each member as itself. Off, or a team with no palette, leaves the
## bodies in their baked plain clothes (the same for everyone: D3 option c).
@export var family_outfits: bool = true
@export var family_palettes: Dictionary[StringName, Dictionary] = {}
## D3 (c) wristband (TeamTell, P2-4; STYLE §2.4): a band on the left wrist in
## the family colour, the one coloured thing on a figure. Width along the arm in
## model units; its radius is measured from the forearm's own vertices, plus
## `wristband_clearance`, so it hugs a thin kid's wrist and an adult's alike.
@export var wristband_width: float = 7.0
@export var wristband_clearance: float = 0.6
## Where along the forearm the band sits, 0 = elbow, 1 = the wrist joint.
@export_range(0.0, 1.0) var wristband_along: float = 0.86
## Used when the radius cannot be measured (no skin, no forearm vertices).
@export var wristband_radius: float = 4.0

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

@export_group("Shell")
## The house drawn by `ShellBuilder` (P3-2): textured walls, floors, ceilings,
## stairs, casings, open doors and a pitched roof, merged per house. Off = the
## P1-4 vertex-coloured blockout boxes. Textures use world UVs in units, so a
## material's `uv1_scale` is 1 / (the texture's size in cm).
@export var shell: bool = true
## Interior wall finish, and per room kind (the jail's painted block).
@export var wall_inside: StandardMaterial3D = null
@export var walls: Dictionary[StringName, StandardMaterial3D] = {}
## Outside faces of the houses.
@export var wall_outside: StandardMaterial3D = null
@export var ceiling: StandardMaterial3D = null
## Painted wood: skirting, casings, risers, fascia, soffit (STYLE §3.3 trim).
## The family colour's paint on exterior casings and door leaves is a copy of it.
@export var trim: StandardMaterial3D = null
@export var stair_tread: StandardMaterial3D = null
@export var roof: StandardMaterial3D = null
@export var glass: StandardMaterial3D = null
@export var roof_pitch_deg: float = 24.0
@export var roof_overhang: float = 45.0
@export var roof_fascia: float = 18.0
@export var casing_width: float = 10.0
@export var casing_depth: float = 2.0
@export var skirting_height: float = 12.0
@export var skirting_depth: float = 1.5
@export var leaf_depth: float = 4.0
## A door leaf's frame round its pane, and the bottom rail's height.
@export var leaf_frame: float = 12.0
@export var leaf_rail: float = 90.0
## Stairs (P3-5): an oak handrail on brackets along a flight's walled side, its
## top this far above the nosing line (about 1.3x a real 85-90, like the
## furniture); a painted string board along the open side. No collision.
@export var handrail_height: float = 110.0
@export var handrail_width: float = 7.0
@export var handrail_depth: float = 6.0
@export var handrail_wall_gap: float = 7.0
@export var handrail_bracket_spacing: float = 120.0
@export var string_height: float = 28.0

@export_group("Furniture")
## The model drawn for each furniture id in the level (LevelDef.props, P3-3):
## id -> an imported prop under res://art/props/. An id not listed, or a file
## that is missing, is drawn as a plain box of `prop` filling its collision box
## (art stays optional). `safe` and `jail_pen` are built in code
## (FurnitureDresser) from the three materials below.
@export var furniture_models: Dictionary[StringName, String] = {}
## Turn added to every furniture model so its front faces +z at yaw 0 (the
## level's facings are "which way the front looks").
@export var furniture_front_yaw: float = 0.0
## For a piece whose standable top is not its highest point (a bed: the
## mattress, below the headboard): the surface whose top is fitted to the
## collision box's top. The rest of the model rises above the box.
@export var furniture_top_surface: Dictionary[StringName, String] = {}
@export var safe_body: StandardMaterial3D = null
@export var safe_trim: StandardMaterial3D = null
@export var pen_bars: StandardMaterial3D = null

@export_group("Exterior")
## What is drawn round the houses (ExteriorBuilder, P3-4): the lot's fences,
## paths and gravel, the two streets, the neighbours' houses, hedges and trees.
## Off = the bare lawn out to the horizon.
@export var exterior: bool = true
## The exterior's materials by name: pavement, asphalt, road_line, kerb,
## gravel, soil, fence_wood, fence_post, fence_steel, fence_cap, hedge, crown,
## bark, render, door. A name not listed is a plain colour built into
## ExteriorBuilder (art stays optional). Brick, roof tile, trim and glass are
## the house's own (`wall_outside`, `roof`, `trim`, `glass`).
@export var exterior_materials: Dictionary[StringName, StandardMaterial3D] = {}
## Both boundary fences stand this tall: over the 210 "blocks, looks tall"
## threshold (WORLD_AUTHORING §12), because the level's bounds stop a body there.
@export var fence_height: float = 210.0
## Soft cloud cover on the sky, 0 = clear.
@export_range(0.0, 1.0) var sky_clouds: float = 0.5
## Distance haze in the sky's horizon colour: it starts this far from the eye
## (units) and is complete just short of the camera's far plane.
@export var haze_from: float = 5000.0
## How the haze builds between the two: 1 = evenly, higher = clear for longer
## and thick only near the far plane (the amount is the distance fraction to
## this power).
@export var haze_curve: float = 2.5

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
## The directional shadow map's side in texels (the engine default is 4096).
## Over `sun_shadow_distance` this sets how sharp the sun's shadows are, and
## filling it is a fixed GPU cost every frame (P3-6).
@export var sun_shadow_size: int = 4096
## Soft-shadow filter quality, RenderingServer.ShadowQuality: 0 hard, 1 very
## soft low ... 5 ultra. The engine default is 2 (soft low).
@export_range(0, 5) var sun_shadow_filter: int = 2
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

@export_group("Contact shadows")
## A soft dark disc on the floor under every figure and loose cash bundle
## (ContactShadows, P3-5). Alpha at its centre; 0 = off.
@export_range(0.0, 1.0) var contact_shadow_alpha: float = 0.35
## The disc's radius under a 180-tall figure (scaled with a member's height),
## and under a bundle.
@export var contact_shadow_radius: float = 30.0
@export var contact_shadow_bundle_radius: float = 45.0
## Gone at this height above the floor (a jump), widening and fading on the way.
@export var contact_shadow_fade_height: float = 160.0

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
## Draw the ceiling fitting (a lit drum shade) in the listed rooms even when
## `interior_lamps` is off: it costs one small unshaded draw, a lamp a whole pass.
@export var interior_fittings: bool = true
## Room kinds that get a lamp when `interior_lamps` is on; empty = every room.
@export var interior_lamp_kinds: Array[StringName] = []
@export var interior_colour: Color = Color(1.0, 0.84, 0.66)
@export var interior_energy: float = 1.2
@export var interior_range: float = 650.0
## The spot's distance falloff exponent. Godot applies it to the distance in
## units (cm), so anything much above 0 makes a lamp vanish at room scale.
@export var interior_attenuation: float = 0.0
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
		_loaded._apply_overrides(OS.get_cmdline_user_args())
	return _loaded

## `--theme.<field>=<value>` sets one plain field (bool, int, float) for this run
## only, e.g. `--theme.sun_shadows=false`: a measurement compares settings as
## arguments, without a theme file per variant (P3-6). Never saved.
func _apply_overrides(args: PackedStringArray) -> void:
	for arg: String in args:
		if not arg.begins_with("--theme.") or not arg.contains("="):
			continue
		var field: String = arg.trim_prefix("--theme.").get_slice("=", 0)
		var text: String = arg.get_slice("=", 1)
		var now: Variant = get(field)
		match typeof(now):
			TYPE_BOOL: set(field, text == "true" or text == "1")
			TYPE_INT: set(field, int(text))
			TYPE_FLOAT: set(field, float(text))
			_: push_error("art theme: --theme.%s is not a bool, int or float field" % field)

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
	if wall_inside == null:
		wall_inside = _material(wall_colour, 0.9)
	if wall_outside == null:
		wall_outside = _material(Color(0.55, 0.33, 0.25), 0.85)
	if ceiling == null:
		ceiling = _material(ceiling_colour, 0.95)
	if trim == null:
		trim = _material(Color(0.9, 0.88, 0.83), 0.5)
	if stair_tread == null:
		stair_tread = _material(floor_colour, 0.6)
	if roof == null:
		roof = _material(roof_colour, 0.8)
	if glass == null:
		glass = _material(Color(0.32, 0.38, 0.42), 0.1)
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
## family (every body is then `figure_model`). `kid_swap` (D3 d) uses the team's
## own order from `family_order_by_team` where it has one.
func member_for(team: StringName, slot: int, kid_swap: bool = false) -> FamilyMember:
	if family.is_empty():
		return null
	var order: PackedStringArray = family_order
	if kid_swap:
		order = family_order_by_team.get(team, family_order)
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

## The colours the figure bakes paint each region of a body
## (`tools/rerig_character.gd` PAINT, `autobuild/figure_bake.mjs`): how
## `outfit_figure` knows which vertices are the shirt.
const OUTFIT_REGIONS: Dictionary[StringName, Color] = {
	&"bare": Color8(255, 255, 255),
	&"shirt": Color8(160, 174, 190),
	&"trim": Color8(200, 196, 160),
	&"trousers": Color8(128, 122, 116),
	&"shoes": Color8(80, 76, 72),
	# P2-6: the plain hair shapes; coloured per member (FamilyMember.hair_colour),
	# never by team.
	&"hair": Color8(122, 86, 58),
}

var _outfit_meshes: Dictionary[String, ArrayMesh] = {}

## Dresses an instanced figure in `who`'s outfit in `team`'s colours (D3): each
## skinned mesh is swapped for a copy whose painted regions carry the family
## palette's colours. Still one mesh, one material and one draw per body; the
## copies are made once per (body, team, member) and shared. `plain` (D3 option
## c), a theme with outfits off, or a team with no palette leaves the baked
## plain clothes. The member's hair colour (P2-6) is applied in every case, with
## or without a team. Drawn only.
func outfit_figure(art: Node3D, team: StringName, who: FamilyMember, plain: bool = false) -> void:
	if who == null:
		return
	var outfit: Dictionary[StringName, StringName] = {}
	var palette: Dictionary = {}
	if not plain and family_outfits and not who.outfit.is_empty():
		palette = family_palettes.get(team, {})
		if not palette.is_empty():
			outfit = who.outfit
	if outfit.is_empty() and who.hair_colour.a <= 0.0:
		return
	var wearing: StringName = team if not outfit.is_empty() else &""
	for found: Node in art.find_children("*", "MeshInstance3D", true, false):
		var body: MeshInstance3D = found as MeshInstance3D
		if body.mesh == null or body.skin == null:
			continue
		var key: String = "%d|%s|%s" % [body.mesh.get_instance_id(), wearing, who.id]
		if not _outfit_meshes.has(key):
			_outfit_meshes[key] = _outfit_mesh(body.mesh, outfit, palette, who.hair_colour)
		if _outfit_meshes[key] != null:
			body.mesh = _outfit_meshes[key]

## A copy of `source` with every vertex colour that is a region's paint replaced
## by the colour that region wears. The figure material multiplies the vertex
## colour (as sRGB) by its own putty albedo, so the stored colour is the wanted
## one divided by the albedo in linear light, to come out on screen as asked.
func _outfit_mesh(source: Mesh, outfit: Dictionary[StringName, StringName], palette: Dictionary,
		hair: Color = Color(0.0, 0.0, 0.0, 0.0)) -> ArrayMesh:
	var asked: Dictionary[StringName, Color] = {}
	for region: StringName in outfit:
		if palette.has(outfit[region]) and OUTFIT_REGIONS.has(region):
			asked[region] = palette[outfit[region]] as Color
	if hair.a > 0.0:
		asked[&"hair"] = hair
	var wear: Dictionary[StringName, Color] = {}
	var under: Color = figure.albedo_color.srgb_to_linear() if figure != null else Color.WHITE
	for region: StringName in asked:
		var want: Color = asked[region].srgb_to_linear()
		wear[region] = Color(minf(want.r / maxf(under.r, 0.01), 1.0), minf(want.g / maxf(under.g, 0.01), 1.0),
			minf(want.b / maxf(under.b, 0.01), 1.0)).linear_to_srgb()
	if wear.is_empty():
		return null
	var made: ArrayMesh = ArrayMesh.new()
	for surface: int in source.get_surface_count():
		var arrays: Array = source.surface_get_arrays(surface)
		if arrays[Mesh.ARRAY_COLOR] != null:
			var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			for i: int in colours.size():
				var region: StringName = _outfit_region(colours[i])
				if wear.has(region):
					colours[i] = wear[region]
			arrays[Mesh.ARRAY_COLOR] = colours
		var keep: int = Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		if source is ArrayMesh:
			keep &= (source as ArrayMesh).surface_get_format(surface)
		else:
			keep = 0
		made.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, keep)
		made.surface_set_material(surface, source.surface_get_material(surface))
	# The copy's hair no longer carries the hair paint: hand on the body's box.
	_body_boxes[made] = _body_box(source)
	return made

static var _body_boxes: Dictionary[Mesh, AABB] = {}

## A figure mesh's box WITHOUT its hair (P2-6). Hair may stand above the crown
## (mom's hairdo, a mohawk); a member's drawn height is its body's, so hair
## never shrinks anybody. A mesh with no hair paint gives its whole box.
static func _body_box(mesh: Mesh) -> AABB:
	if _body_boxes.has(mesh):
		return _body_boxes[mesh]
	var box: AABB = mesh.get_aabb()
	var body: AABB = AABB()
	var any_body: bool = false
	var any_hair: bool = false
	for surface: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		if arrays[Mesh.ARRAY_COLOR] == null:
			any_hair = false
			break
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		for i: int in points.size():
			if _outfit_region(colours[i]) == &"hair":
				any_hair = true
			elif any_body:
				body = body.expand(points[i])
			else:
				body = AABB(points[i], Vector3.ZERO)
				any_body = true
	if any_hair and any_body:
		box = body
	_body_boxes[mesh] = box
	return box

## The painted region a baked vertex colour belongs to (the nearest paint).
static func _outfit_region(colour: Color) -> StringName:
	var best: StringName = &"bare"
	var nearest: float = INF
	for region: StringName in OUTFIT_REGIONS:
		var paint: Color = OUTFIT_REGIONS[region]
		var off: float = Vector3(colour.r - paint.r, colour.g - paint.g, colour.b - paint.b).length_squared()
		if off < nearest:
			nearest = off
			best = region
	return best

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
		tallest = (here * _body_box(mesh_view.mesh)).size.y
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

## Puts the D3 (c) wristband on a shaped figure: a short ring on the left
## forearm just above the wrist joint, riding the `lowerarm_l` bone so it follows
## every clip, in a satin copy of the figure material tinted the family colour.
## Returns the band, or null when the figure has no skin or no such bones.
## Drawn only, like the figure.
func add_wristband(art: Node3D, team: StringName) -> MeshInstance3D:
	for found: Node in art.find_children("*", "MeshInstance3D", true, false):
		var body: MeshInstance3D = found as MeshInstance3D
		if body.mesh == null or body.skin == null:
			continue
		var bones: Skeleton3D = body.get_node_or_null(body.skeleton) as Skeleton3D
		if bones == null:
			continue
		# The skinned mesh is in the source's metres under a scaled armature: how
		# many model units one mesh unit is, so width and clearance convert.
		var per_unit: float = _chain(art, body).basis.get_scale().x
		if per_unit <= 0.0:
			per_unit = 1.0
		var fit: Dictionary = _wrist_fit(body, wristband_width / per_unit)
		if fit.is_empty():
			return null
		var attach: BoneAttachment3D = BoneAttachment3D.new()
		attach.bone_name = "lowerarm_l"
		bones.add_child(attach)
		var band: MeshInstance3D = MeshInstance3D.new()
		var ring: CylinderMesh = CylinderMesh.new()
		var widest: float = fit["widest"]
		var radius: float = widest + wristband_clearance / per_unit if widest > 0.0 \
			else wristband_radius / per_unit
		ring.top_radius = radius
		ring.bottom_radius = radius
		ring.height = wristband_width / per_unit
		ring.radial_segments = 14
		ring.rings = 1
		band.mesh = ring
		# The ring is built in the mesh's bind space (where it was measured) and
		# carried into the bone's own space by the bone's bind pose.
		band.transform = fit["bind"] * fit["place"]
		band.material_override = wristband_material(team)
		band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		attach.add_child(band)
		return band
	return null

## The band's material for `team`: the figure's satin finish in the family colour.
func wristband_material(team: StringName) -> StandardMaterial3D:
	var made: StandardMaterial3D = StandardMaterial3D.new()
	made.albedo_color = family_colour(team)
	made.roughness = figure.roughness if figure != null else 0.7
	if figure != null and figure.rim_enabled:
		made.rim_enabled = true
		made.rim = figure.rim
		made.rim_tint = figure.rim_tint
	return made

var _wrist_fits: Dictionary[int, Dictionary] = {}

## Where the band goes on `body`'s mesh and how big it is, measured once per
## mesh, all in the mesh's own (bind) units: the ring's centre and axis on the
## elbow->wrist line, and `widest`, the farthest forearm/hand vertex from that
## axis within a slab `width` long (0 when none was found). Only vertices the
## forearm or hand mostly carry are measured: the arms hang beside the hips in
## the rest pose, so a slab alone would catch the thigh. Empty when the skin
## lacks the bones.
func _wrist_fit(body: MeshInstance3D, width: float) -> Dictionary:
	var key: int = body.mesh.get_instance_id()
	if _wrist_fits.has(key):
		return _wrist_fits[key]
	var skin: Skin = body.skin
	var fore: int = -1
	var hand: int = -1
	for i: int in skin.get_bind_count():
		var named: StringName = skin.get_bind_name(i)
		if named == &"lowerarm_l":
			fore = i
		elif named == &"hand_l":
			hand = i
	if fore < 0 or hand < 0:
		_wrist_fits[key] = {}
		return {}
	var elbow: Vector3 = skin.get_bind_pose(fore).affine_inverse().origin
	var wrist: Vector3 = skin.get_bind_pose(hand).affine_inverse().origin
	var axis: Vector3 = (wrist - elbow).normalized()
	var centre: Vector3 = elbow.lerp(wrist, wristband_along)
	var reach: float = width * 0.5
	var widest: float = 0.0
	for surface: int in body.mesh.get_surface_count():
		var arrays: Array = body.mesh.surface_get_arrays(surface)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
		if joints.is_empty() or points.is_empty():
			continue
		var per: int = joints.size() / points.size()
		for v: int in points.size():
			var carried: float = 0.0
			for k: int in per:
				var joint: int = joints[v * per + k]
				if joint == fore or joint == hand:
					carried += weights[v * per + k]
			if carried < 0.5:
				continue
			var off: Vector3 = points[v] - centre
			var along: float = off.dot(axis)
			if absf(along) > reach:
				continue
			widest = maxf(widest, (off - axis * along).length())
	# Cylinder axis (+y) along the forearm.
	var turn: Basis = Basis(Quaternion(Vector3.UP, axis))
	var fit: Dictionary = {
		"widest": widest,
		"place": Transform3D(turn, centre),
		"bind": skin.get_bind_pose(fore),
	}
	_wrist_fits[key] = fit
	return fit

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
