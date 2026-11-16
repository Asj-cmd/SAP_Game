shader_type spatial;
// The lot's boundary fence (ExteriorBuilder, P3-4).
//
// The level's bounds stop a body at the fence, but the chase camera's arm does
// not collide with it: backed against the boundary, the camera hangs outside
// the lot looking in. A 2.1 m fence would then stand between the camera and the
// body. So each side of the fence is not drawn for a camera that is a short way
// outside that side: the side's outward direction rides in UV2, and a fragment
// is dropped when the camera is beyond it by less than `cut_reach`. A camera
// far outside (an overview) still sees the whole fence.
//
// The shadow is cast by a shadows-only twin with a plain material, so the cut
// never removes the fence's shadow.

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_texture = false;
uniform vec2 uv_scale = vec2(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.9;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float cut_reach = 600.0;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 outward = vec3(UV2.x, 0.0, UV2.y);
	float beyond = dot(CAMERA_POSITION_WORLD - world_position, outward);
	if (beyond > 0.0 && beyond < cut_reach) {
		discard;
	}
	vec3 colour = albedo.rgb;
	if (use_texture) {
		colour *= texture(albedo_texture, UV * uv_scale).rgb;
	}
	ALBEDO = colour;
	ROUGHNESS = roughness;
	METALLIC = metallic;
}
