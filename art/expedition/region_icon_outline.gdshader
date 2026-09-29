shader_type canvas_item;

uniform vec4 outline_color : source_color = vec4(0.98, 0.88, 0.63, 1.0);
uniform vec4 outer_color : source_color = vec4(0.13, 0.07, 0.04, 1.0);

varying vec4 icon_tint;

void vertex() {
	icon_tint = COLOR;
}

void fragment() {
	vec4 icon = COLOR;
	float inner_alpha = 0.0;
	float outer_alpha = 0.0;
	vec2 step_uv = fwidth(UV) * 2.0;

	for (int x = -2; x <= 2; x++) {
		for (int y = -2; y <= 2; y++) {
			float alpha = texture(TEXTURE, UV + vec2(float(x), float(y)) * step_uv).a;
			outer_alpha = max(outer_alpha, alpha);
			if (abs(x) <= 1 && abs(y) <= 1) {
				inner_alpha = max(inner_alpha, alpha);
			}
		}
	}

	if (icon.a < 0.5 && inner_alpha >= 0.5) {
		COLOR = outline_color * icon_tint;
	} else if (icon.a < 0.5 && outer_alpha >= 0.5) {
		COLOR = outer_color * icon_tint;
	} else {
		COLOR = icon;
	}
}
