shader_type sky;
// P3-4: the daylight sky (WorldBackdrop). A horizon-to-zenith gradient with the
// same curve as Godot's ProceduralSkyMaterial, and soft clouds projected onto a
// flat layer overhead (so they shrink toward the horizon like real ones, rather
// than an equirect noise that smears into vertical streaks).
//
// Clouds fade out well above the horizon, so the sky AT the horizon is exactly
// `sky_horizon`: the depth fog's colour. Below the horizon (past the camera's far
// plane, where the ground is clipped) the sky is that colour too. Together there
// is no line where haze meets sky, from any camera height.

uniform vec3 sky_top : source_color = vec3(0.33, 0.56, 0.86);
uniform vec3 sky_horizon : source_color = vec3(0.78, 0.85, 0.92);
// Smaller = the blue reaches lower; ProceduralSkyMaterial's default is 0.15.
uniform float sky_curve = 0.2;
// Seamless noise, black where clear (a ramp is baked into it).
uniform sampler2D cover : filter_linear_mipmap, repeat_enable;
uniform float cloud_amount = 0.0;
// Tiles of `cover` per unit of the flat cloud layer (1 = the layer's height).
uniform float cloud_scale = 0.3;
uniform vec3 cloud_colour : source_color = vec3(0.96, 0.97, 0.98);

void sky() {
	vec3 dir = EYEDIR;
	float up = clamp(dir.y, 0.0, 1.0);
	float c = 1.0 - acos(up) / (PI * 0.5);
	vec3 colour = mix(sky_horizon, sky_top, clamp(1.0 - pow(1.0 - c, 1.0 / sky_curve), 0.0, 1.0));
	if (cloud_amount > 0.0 && up > 0.0) {
		// The + 0.15 bends the layer down at the edges like a dome, so it never
		// runs to an infinitely fine pattern at the horizon.
		vec2 uv = dir.xz / (up + 0.15) * cloud_scale;
		float cloud = texture(cover, uv).r * cloud_amount * smoothstep(0.04, 0.4, up);
		colour = mix(colour, cloud_colour, clamp(cloud, 0.0, 1.0));
	}
	COLOR = colour;
}
