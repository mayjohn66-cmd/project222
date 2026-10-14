// Optional top face: map a pixel-aligned parallelogram to the original cornice.
// Color, normals and picking use the same source coordinates.
uniform bool wall_top_enabled = false;
uniform bool wall_top_attached = false;
uniform bool wall_top_corner = false;
uniform vec4 wall_top_bounds = vec4(0.0);
uniform vec2 wall_top_start = vec2(0.0);
uniform vec2 wall_top_along = vec2(32.0, 16.0);
uniform vec2 wall_top_outward = vec2(16.0, -8.0);
uniform float wall_top_profile_sign = 1.0;
vec3 world_sprite_sample(vec2 uv, vec4 source_region, vec2 pixels) {
	if (!wall_top_enabled) {
		vec2 at = source_region.xy + uv * source_region.zw;
		if (wall_top_attached) {
			vec2 pixel = floor(at * pixels);
			float top = 44.0 + wall_top_profile_sign * floor((pixel.x - 32.0) / 2.0);
			if (pixel.y < top + 2.0) { return vec3(0.0); }
			// The old wide yellow highlight flickers through the bevel at tile joins.
			if (pixel.y < top + 7.0) { at.y = (top + 8.5) / pixels.y; }
		}
		return vec3(at, 1.0);
	}
	vec2 p = wall_top_bounds.xy + uv * wall_top_bounds.zw - wall_top_start;
	float det = wall_top_along.x * wall_top_outward.y - wall_top_along.y * wall_top_outward.x;
	float u = (p.x * wall_top_outward.y - p.y * wall_top_outward.x) / det;
	float v = (wall_top_along.x * p.y - wall_top_along.y * p.x) / det;
	if (u < 0.0 || u > 1.0 || v < 0.0 || v > 1.0) { return vec3(0.0); }
	float x = clamp(floor(16.0 + u * 32.0), 16.0, 47.0);
	float depth = wall_top_corner ? max(u, v) : v;
	// Cornice stone palette: quiet middle, one narrow shaded/beveled edge each side.
	float row = depth < 0.125 ? 56.0 : depth >= 0.875 ? 51.0 : 52.0;
	float y = row + wall_top_profile_sign * floor((x - 32.0) / 2.0);
	return vec3((vec2(x, y) + vec2(0.5)) / pixels, 1.0);
}
