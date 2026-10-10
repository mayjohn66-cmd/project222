// Ordered alpha cutout preserves native sprite geometry and matches the ID pass.
uniform float cutaway_visibility = 1.0;
float bayer2(vec2 p) {
	return 2.0 * p.x + 3.0 * p.y - 4.0 * p.x * p.y;
}
bool cutaway_hidden(vec2 uv, vec2 texture_size) {
	vec2 pixel = floor(uv * texture_size);
	vec2 fine = mod(pixel, 2.0);
	vec2 coarse = mod(floor(pixel / 2.0), 2.0);
	float threshold = (4.0 * bayer2(fine) + bayer2(coarse) + 0.5) / 16.0;
	return cutaway_visibility < threshold;
}
