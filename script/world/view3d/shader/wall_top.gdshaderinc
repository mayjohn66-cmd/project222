// Optional top face: map a pixel-aligned parallelogram to the original cornice.
// Color, normals and picking use the same source coordinates.
uniform bool wall_top_enabled = false;
uniform bool wall_top_corner = false;
uniform vec4 wall_top_bounds = vec4(0.0);
uniform vec2 wall_top_start = vec2(0.0);
uniform vec2 wall_top_along = vec2(32.0, 16.0);
uniform vec2 wall_top_outward = vec2(16.0, -8.0);
uniform float wall_top_profile_sign = 1.0;
vec3 world_sprite_sample(vec2 uv, vec4 source_region, vec2 pixels) {
	if (!wall_top_enabled) { return vec3(source_region.xy + uv * source_region.zw, 1.0); }
	vec2 p = wall_top_bounds.xy + uv * wall_top_bounds.zw - wall_top_start;
	float det = wall_top_along.x * wall_top_outward.y - wall_top_along.y * wall_top_outward.x;
	float u = (p.x * wall_top_outward.y - p.y * wall_top_outward.x) / det;
	float v = (wall_top_along.x * p.y - wall_top_along.y * p.x) / det;
	if (u < 0.0 || u > 1.0 || v < 0.0 || v > 1.0) { return vec3(0.0); }
	float x = clamp(floor(16.0 + u * 32.0), 16.0, 47.0);
	float depth = wall_top_corner ? max(u, v) : v;
	// Reuse the cornice fill; its first two outline rows would double the seam.
	float y = 46.0 + wall_top_profile_sign * floor((x - 32.0) / 2.0) + min(5.0, floor(depth * 6.0));
	return vec3((vec2(x, y) + vec2(0.5)) / pixels, 1.0);
}
