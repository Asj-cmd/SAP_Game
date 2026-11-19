class_name WorldBackdrop
extends RefCounted
## What surrounds the level: sky, sun, haze, and ground running out to the
## horizon. Without it the lot floats in a black void and every frame looks
## like a broken render.
##
## Presentation only. Nothing here has collision or is read by a rule; the lot's
## own blockers stay the ground anyone stands on.
##
## The colours and energies are the ArtTheme's (P1-4); what is here is how they
## are put together for the Compatibility renderer (D6): a procedural sky, a sun
## plus a shadowless fill, flat-colour ambient, depth fog.

## Haze starts at the theme's `haze_from` (world units, 1 = 1 cm) and is
## complete this far short of the camera's far plane, so the ground fades into
## the horizon before it is clipped.
const HAZE_SHORT_OF_FAR: float = 500.0

const DAYLIGHT_SKY: Shader = preload("res://game/art/daylight_sky.gdshader")

## Where the sun's light travels: down, toward +x and -z (rotation -55, -40).
## It lights the faces turned +y, -x and +z; the other three get ambient only.
const SUN_ROTATION_DEG: Vector3 = Vector3(-55, -40, 0)
## A weak, shadowless, level fill from the side the sun is not.
##
## Without it the three faces the sun misses - ceilings and two of the four
## wall directions - were all ambient and all exactly one slate colour, so a
## wall ran into the ceiling with no edge and a stairwell read as a hole in a
## flat sheet (P0-7 frames: upstairs landing, back hall). The fill lights the
## two walls the sun misses by different amounts (+x 0.83, -z 0.55 of its
## energy) and leaves ceilings to ambient alone, so ceilings are always the
## darkest face. The direction the light comes FROM; its colour and energy are
## the theme's.
const FILL_FROM: Vector3 = Vector3(3.0, 0.0, -2.0)

## Render layer (bit value) for what is only ever outdoors: the backdrop plane,
## the lot's ground box, yard and lot finishes. The room lamps light layer 1
## only, so they skip these. On the Compatibility renderer every omni/spot light
## re-draws each object it touches; the ground fills the screen outdoors and was
## being redrawn once per ground-floor lamp (P1-4: ~4 ms of GPU for 16 lamps).
const OUTDOOR_LAYER: int = 2
const LAMP_CULL_MASK: int = 1

## How far below the lot's ground the outer plane sits. It must not share the
## lot's top face (that would z-fight); one unit is invisible at any distance.
const GROUND_DROP: float = 1.0

## A room lamp's drum shade, centred this far above the lamp. The lamp hangs 60
## below the top of the room's zone box (greybox_main CEILING_LAMP_DROP), and the
## slab above takes the top 40 of that box (build_house SLAB), so the ceiling is
## 20 above the lamp: the 14-tall drum's centre is 7 below it.
const SHADE_ABOVE_LAMP: float = 13.0

static var _sun: DirectionalLight3D = null

## Quality preset hook (P7-2): `size` 0 turns the sun shadow off, else sets the atlas.
static func apply_quality(size: int) -> void:
	if size > 0:
		RenderingServer.directional_shadow_atlas_set_size(size, true)
	if is_instance_valid(_sun) and ArtTheme.current().sun_shadows:
		_sun.shadow_enabled = size > 0

## The sun, the sky, the haze and the ambient light.
static func environment(far: float, theme: ArtTheme) -> Array[Node]:
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	_sun = sun
	sun.rotation_degrees = SUN_ROTATION_DEG
	sun.light_energy = theme.sun_energy
	sun.light_color = theme.sun_colour
	sun.shadow_enabled = theme.sun_shadows
	if theme.sun_shadows:
		match theme.sun_shadow_splits:
			1: sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			2: sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			_: sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sun.directional_shadow_max_distance = theme.sun_shadow_distance
		var chosen: int = PlayerSettings.current().shadow_size(theme.sun_shadow_size)
		sun.shadow_enabled = chosen > 0
		RenderingServer.directional_shadow_atlas_set_size(maxi(chosen, 256), true)
		RenderingServer.directional_soft_shadow_filter_set_quality(
			theme.sun_shadow_filter as RenderingServer.ShadowQuality)

	var fill: DirectionalLight3D = DirectionalLight3D.new()
	# A directional light shines along its -Z, i.e. away from FILL_FROM.
	fill.transform.basis = Basis.looking_at(-FILL_FROM.normalized(), Vector3.UP)
	fill.light_energy = theme.fill_energy
	fill.light_color = theme.fill_colour
	fill.light_specular = 0.0
	fill.shadow_enabled = false

	var sky_fill: DirectionalLight3D = DirectionalLight3D.new()
	sky_fill.transform.basis = Basis.looking_at(-theme.sky_fill_from.normalized(), Vector3.FORWARD)
	sky_fill.light_energy = theme.sky_fill_energy
	sky_fill.light_color = theme.sky_fill_colour
	sky_fill.light_specular = 0.0
	sky_fill.shadow_enabled = false

	# Below the horizon the sky is never seen through the ground, except past
	# the far plane where the ground is clipped. There, in the haze and at the
	# horizon itself, everything is the sky's horizon colour, so the ground fades
	# into sky with no band or cut from any height (daylight_sky.gdshader).
	var sky_material: ShaderMaterial = ShaderMaterial.new()
	sky_material.shader = DAYLIGHT_SKY
	sky_material.set_shader_parameter(&"sky_top", theme.sky_top)
	sky_material.set_shader_parameter(&"sky_horizon", theme.sky_horizon)
	sky_material.set_shader_parameter(&"cloud_amount", theme.sky_clouds)
	if theme.sky_clouds > 0.0:
		# Soft cloud cover: seamless noise on a flat layer overhead, thinned so
		# most of it stays blue. One texture read in the sky pass.
		var noise: FastNoiseLite = FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.012
		noise.fractal_octaves = 4
		noise.seed = 7
		var ramp: Gradient = Gradient.new()
		ramp.offsets = PackedFloat32Array([0.0, 0.5, 0.78, 1.0])
		ramp.colors = PackedColorArray([Color(0, 0, 0, 1), Color(0, 0, 0, 1),
			Color(0.6, 0.6, 0.6, 1), Color(0.85, 0.85, 0.85, 1)])
		var cover: NoiseTexture2D = NoiseTexture2D.new()
		cover.width = 512
		cover.height = 512
		cover.seamless = true
		cover.noise = noise
		cover.color_ramp = ramp
		sky_material.set_shader_parameter(&"cover", cover)
	var sky: Sky = Sky.new()
	sky.sky_material = sky_material

	var settings: Environment = Environment.new()
	settings.background_mode = Environment.BG_SKY
	settings.sky = sky
	# Flat-colour ambient, tinted toward the sky, rather than sampling the sky:
	# predictable on the Compatibility renderer and on a GT 730M.
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = theme.ambient_colour
	settings.ambient_light_energy = theme.ambient_energy
	settings.tonemap_mode = theme.tonemap
	settings.tonemap_exposure = theme.exposure
	settings.tonemap_white = theme.tonemap_white
	settings.fog_enabled = true
	settings.fog_mode = Environment.FOG_MODE_DEPTH
	settings.fog_light_color = theme.sky_horizon
	settings.fog_density = 1.0
	settings.fog_depth_begin = minf(theme.haze_from, far - HAZE_SHORT_OF_FAR - 1.0)
	settings.fog_depth_end = far - HAZE_SHORT_OF_FAR
	settings.fog_depth_curve = theme.haze_curve
	settings.fog_sky_affect = 0.0

	var holder: WorldEnvironment = WorldEnvironment.new()
	holder.environment = settings
	return [sun, fill, sky_fill, holder] as Array[Node]

## Behind the main menu (PT4-7) the haze starts only MENU_HAZE_BAND short of the
## far plane: the orbit camera is ~6900 from the lot, so the match haze (from
## `haze_from`) greyed both houses; the thin band left still blends the ground's
## far edge into the sky. `on` false puts the match haze back.
const MENU_HAZE_BAND: float = 2000.0

static func menu_haze(holder: WorldEnvironment, far: float, theme: ArtTheme, on: bool) -> void:
	if holder == null or holder.environment == null:
		return
	var end: float = far - HAZE_SHORT_OF_FAR
	holder.environment.fog_depth_begin = end - MENU_HAZE_BAND if on \
		else minf(theme.haze_from, end - 1.0)

## One warm light per indoor room, at the middle of its ceiling, pointing down
## (STYLE.md §4). No shadows: a shadowed spot is another pass over the scene.
static func interior_lights(zones: Array[ZoneDef], theme: ArtTheme, ceiling_drop: float) -> Array[Node]:
	var lights: Array[Node] = []
	if not theme.interior_lamps and not theme.interior_fittings:
		return lights
	for zone: ZoneDef in zones:
		if zone.outdoor:
			continue
		var kind: StringName = ArtTheme.room_kind(zone.id)
		# Only the rooms listed get a lamp (P3-5: each lamp draws every object it
		# touches again on Compatibility); an empty list lights every room.
		if not theme.interior_lamp_kinds.is_empty() and not theme.interior_lamp_kinds.has(kind):
			continue
		var lamp: SpotLight3D = SpotLight3D.new()
		var middle: Vector3 = zone.bounds.get_center()
		lamp.position = Vector3(middle.x, zone.bounds.end.y - ceiling_drop, middle.z)
		lamp.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		lamp.light_color = theme.interior_colour_by_kind.get(kind, theme.interior_colour)
		lamp.light_energy = theme.interior_energy_by_kind.get(kind, theme.interior_energy)
		lamp.spot_range = theme.interior_range
		lamp.spot_angle = theme.interior_angle_deg
		# Godot divides a positional light by distance^attenuation in WORLD units,
		# and a unit here is a centimetre: at 0.6 a floor 300 below the lamp got
		# 3 % of its energy and no lamp showed at all (P3-5, an energy-6 red test
		# light left the kitchen unchanged). The range window alone shapes the
		# falloff at 0.
		lamp.spot_attenuation = theme.interior_attenuation
		lamp.shadow_enabled = false
		lamp.light_cull_mask = LAMP_CULL_MASK
		# Fittings without lamps (P3-5): the shell is one mesh per house, so any
		# lamp redraws the whole shell in every view of that house.
		if theme.interior_lamps:
			lights.append(lamp)
		# The fitting the light comes from: a shallow drum shade on the ceiling,
		# lit from inside (unshaded, so no lamp redraws it).
		var shade: MeshInstance3D = MeshInstance3D.new()
		var drum: CylinderMesh = CylinderMesh.new()
		drum.top_radius = 26.0
		drum.bottom_radius = 30.0
		drum.height = 14.0
		drum.radial_segments = 20
		drum.rings = 1
		shade.mesh = drum
		var glow: StandardMaterial3D = StandardMaterial3D.new()
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.albedo_color = lamp.light_color.lerp(Color.WHITE, 0.6)
		shade.material_override = glow
		shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Its top against the ceiling, the lamp just inside it: the zone's box
		# runs up into the slab above, and the lamp hangs `ceiling_drop` below
		# that box's top, which is SHADE_ABOVE_LAMP + half the drum below the ceiling.
		shade.position = lamp.position + Vector3(0.0, SHADE_ABOVE_LAMP, 0.0)
		lights.append(shade)
		if not theme.interior_lamps:
			lamp.free()
	return lights

## A flat plane just under the lot's ground, reaching past the far plane in
## every direction. The lot's ground is the blocker with the largest footprint;
## found rather than restated, so a re-baked lot moves the plane with it.
static func ground(blockers: Array[AABB], far: float, theme: ArtTheme) -> MeshInstance3D:
	if blockers.is_empty():
		return null
	var lot: AABB = blockers[0]
	var widest: AABB = widest_blocker(blockers)
	for blocker: AABB in blockers:
		lot = lot.merge(blocker)
	var plane: PlaneMesh = PlaneMesh.new()
	var reach: float = far * 2.0 + maxf(lot.size.x, lot.size.z)
	plane.size = Vector2(reach, reach)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = theme.grass
	material.roughness = 1.0
	# The yards' lawn carried on to the horizon: the same texture at the same
	# true size (a plane's UVs run 0..1 across it), so the lot does not sit on
	# a different green from the land round it.
	var lawn: StandardMaterial3D = theme.floors.get(&"yard", null)
	if lawn != null and lawn.albedo_texture != null:
		material.albedo_color = lawn.albedo_color
		material.albedo_texture = lawn.albedo_texture
		material.uv1_scale = Vector3(reach * lawn.uv1_scale.x, reach * lawn.uv1_scale.y, 1.0)
	var view: MeshInstance3D = MeshInstance3D.new()
	view.mesh = plane
	view.material_override = material
	view.position = Vector3(lot.get_center().x, widest.end.y - GROUND_DROP, lot.get_center().z)
	return view

## The lot's ground: the blocker with the largest footprint.
static func widest_blocker(blockers: Array[AABB]) -> AABB:
	var widest: AABB = blockers[0]
	for blocker: AABB in blockers:
		if blocker.size.x * blocker.size.z > widest.size.x * widest.size.z:
			widest = blocker
	return widest
