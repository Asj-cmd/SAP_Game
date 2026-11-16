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

## The sun, the sky, the haze and the ambient light.
static func environment(far: float, theme: ArtTheme) -> Array[Node]:
	var sun: DirectionalLight3D = DirectionalLight3D.new()
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

## One warm light per indoor room, at the middle of its ceiling, pointing down
## (STYLE.md §4). No shadows: a shadowed spot is another pass over the scene.
static func interior_lights(zones: Array[ZoneDef], theme: ArtTheme, ceiling_drop: float) -> Array[Node]:
	var lights: Array[Node] = []
	if not theme.interior_lamps:
		return lights
	for zone: ZoneDef in zones:
		if zone.outdoor:
			continue
		var kind: StringName = ArtTheme.room_kind(zone.id)
		var lamp: SpotLight3D = SpotLight3D.new()
		var middle: Vector3 = zone.bounds.get_center()
		lamp.position = Vector3(middle.x, zone.bounds.end.y - ceiling_drop, middle.z)
		lamp.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		lamp.light_color = theme.interior_colour_by_kind.get(kind, theme.interior_colour)
		lamp.light_energy = theme.interior_energy_by_kind.get(kind, theme.interior_energy)
		lamp.spot_range = theme.interior_range
		lamp.spot_angle = theme.interior_angle_deg
		lamp.spot_attenuation = 0.6
		lamp.shadow_enabled = false
		lamp.light_cull_mask = LAMP_CULL_MASK
		lights.append(lamp)
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
