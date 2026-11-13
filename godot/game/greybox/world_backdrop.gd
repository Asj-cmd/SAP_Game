class_name WorldBackdrop
extends RefCounted
## What surrounds the level: sky, sun, haze, and ground running out to the
## horizon. Without it the lot floats in a black void and every frame looks
## like a broken render.
##
## Presentation only. Nothing here has collision or is read by a rule; the lot's
## own blockers stay the ground anyone stands on.
##
## Every number is a look, chosen for the Compatibility renderer (D6): a
## procedural sky, a sun plus a shadowless fill, flat-colour ambient, depth
## fog. No shadows yet (P3-5).

## Sky: soft blue overhead, pale at the horizon.
const SKY_TOP: Color = Color(0.33, 0.56, 0.86)
const SKY_HORIZON: Color = Color(0.78, 0.85, 0.92)
## The grass beyond the lot. Muted so the lot and the houses stay the subject.
const GRASS: Color = Color(0.36, 0.5, 0.3)
## Below the horizon the sky is never seen through the ground, except past the
## far plane where the ground is clipped. There, and in the haze, everything is
## the sky's own horizon colour, so grass fades into sky with no band or cut.
const FAR_GROUND: Color = SKY_HORIZON

## Haze starts this far from the eye (world units, 1 = 1 cm) and is complete
## just short of the camera's far plane, so the ground fades into the horizon
## before it is clipped. Far enough out that both houses stay clear from
## anywhere on the lot.
const HAZE_FROM: float = 6000.0
const HAZE_SHORT_OF_FAR: float = 500.0

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
## darkest face. Light reaching a face, sun x 1.15 + fill x 0.45: +y 0.94,
## +z 0.51, -x 0.42, +x 0.37, -z 0.25, -y 0 - every corner, wall to wall or
## wall to ceiling, shows an edge. (+x and -x are close, but they face each
## other and never meet.) The direction the light comes FROM.
const FILL_FROM: Vector3 = Vector3(3.0, 0.0, -2.0)
const FILL_ENERGY: float = 0.45
const FILL_COLOUR: Color = Color(0.85, 0.9, 1.0)
## Lower than before the fill (0.9): with a third light in, less flat ambient
## keeps the faces apart instead of washing them toward one grey.
const AMBIENT_ENERGY: float = 0.65

## How far below the lot's ground the outer plane sits. It must not share the
## lot's top face (that would z-fight); one unit is invisible at any distance.
const GROUND_DROP: float = 1.0

## The sun, the sky, the haze and the ambient light.
static func environment(far: float) -> Array[Node]:
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = SUN_ROTATION_DEG
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.96, 0.88)

	var fill: DirectionalLight3D = DirectionalLight3D.new()
	# A directional light shines along its -Z, i.e. away from FILL_FROM.
	fill.transform.basis = Basis.looking_at(-FILL_FROM.normalized(), Vector3.UP)
	fill.light_energy = FILL_ENERGY
	fill.light_color = FILL_COLOUR
	fill.light_specular = 0.0
	fill.shadow_enabled = false

	var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = SKY_TOP
	sky_material.sky_horizon_color = SKY_HORIZON
	sky_material.ground_horizon_color = FAR_GROUND
	sky_material.ground_bottom_color = FAR_GROUND
	var sky: Sky = Sky.new()
	sky.sky_material = sky_material

	var settings: Environment = Environment.new()
	settings.background_mode = Environment.BG_SKY
	settings.sky = sky
	# Flat-colour ambient, tinted toward the sky, rather than sampling the sky:
	# predictable on the Compatibility renderer and on a GT 730M.
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color(0.62, 0.66, 0.74)
	settings.ambient_light_energy = AMBIENT_ENERGY
	settings.fog_enabled = true
	settings.fog_mode = Environment.FOG_MODE_DEPTH
	settings.fog_light_color = FAR_GROUND
	settings.fog_density = 1.0
	settings.fog_depth_begin = HAZE_FROM
	settings.fog_depth_end = far - HAZE_SHORT_OF_FAR
	settings.fog_depth_curve = 1.0
	settings.fog_sky_affect = 0.0

	var holder: WorldEnvironment = WorldEnvironment.new()
	holder.environment = settings
	return [sun, fill, holder] as Array[Node]

## A flat plane just under the lot's ground, reaching past the far plane in
## every direction. The lot's ground is the blocker with the largest footprint;
## found rather than restated, so a re-baked lot moves the plane with it.
static func ground(blockers: Array[AABB], far: float) -> MeshInstance3D:
	if blockers.is_empty():
		return null
	var lot: AABB = blockers[0]
	var widest: AABB = blockers[0]
	for blocker: AABB in blockers:
		lot = lot.merge(blocker)
		if blocker.size.x * blocker.size.z > widest.size.x * widest.size.z:
			widest = blocker
	var plane: PlaneMesh = PlaneMesh.new()
	var reach: float = far * 2.0 + maxf(lot.size.x, lot.size.z)
	plane.size = Vector2(reach, reach)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = GRASS
	material.roughness = 1.0
	var view: MeshInstance3D = MeshInstance3D.new()
	view.mesh = plane
	view.material_override = material
	view.position = Vector3(lot.get_center().x, widest.end.y - GROUND_DROP, lot.get_center().z)
	return view
