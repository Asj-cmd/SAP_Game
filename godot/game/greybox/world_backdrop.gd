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
## procedural sky, flat-colour ambient, depth fog. No shadows yet (P3-5).

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

## How far below the lot's ground the outer plane sits. It must not share the
## lot's top face (that would z-fight); one unit is invisible at any distance.
const GROUND_DROP: float = 1.0

## The sun, the sky, the haze and the ambient light.
static func environment(far: float) -> Array[Node]:
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -40, 0)
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.96, 0.88)

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
	settings.ambient_light_energy = 0.9
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
	return [sun, holder] as Array[Node]

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
