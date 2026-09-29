shader_type canvas_item;

uniform vec4 roof_color : source_color = vec4(0.33, 0.46, 0.60, 1.0);
uniform bool front_facing = false;

float edge_side(vec2 a, vec2 b, vec2 point) {
	return (b.x - a.x) * (point.y - a.y) - (b.y - a.y) * (point.x - a.x);
}

void fragment() {
	vec4 pixel = texture(TEXTURE, UV);
	float green = max(pixel.g, 0.001);
	bool inside_roof = edge_side(vec2(0.39, 0.05), vec2(0.67, 0.22), UV) >= 0.0
		&& edge_side(vec2(0.67, 0.22), vec2(0.80, 0.47), UV) >= 0.0
		&& edge_side(vec2(0.80, 0.47), vec2(0.45, 0.69), UV) >= 0.0
		&& edge_side(vec2(0.45, 0.69), vec2(0.18, 0.46), UV) >= 0.0
		&& edge_side(vec2(0.18, 0.46), vec2(0.39, 0.05), UV) >= 0.0;
	bool front_gable_roof = front_facing
		&& edge_side(vec2(0.45, 0.40), vec2(0.57, 0.58), UV) >= 0.0
		&& edge_side(vec2(0.57, 0.58), vec2(0.54, 0.65), UV) >= 0.0
		&& edge_side(vec2(0.54, 0.65), vec2(0.35, 0.57), UV) >= 0.0
		&& edge_side(vec2(0.35, 0.57), vec2(0.45, 0.40), UV) >= 0.0;
	bool roof_tile = (inside_roof || front_gable_roof)
		&& pixel.a > 0.01
		&& pixel.g > 0.11
		&& pixel.r > green * 0.74
		&& pixel.r < green * 1.22
		&& pixel.b < green * 0.67;
	if (roof_tile) {
		float lightness = dot(pixel.rgb, vec3(0.299, 0.587, 0.114));
		pixel.rgb = clamp(roof_color.rgb * (lightness / 0.42), vec3(0.0), vec3(1.0));
	}
	COLOR = pixel;
}
