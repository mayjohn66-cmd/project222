shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D background_texture : source_color, filter_nearest, repeat_disable;
uniform vec2 image_size = vec2(1.0);
uniform vec2 viewport_size = vec2(1.0);
uniform vec4 tint : source_color = vec4(1.0);
void fragment() {
	vec2 uv = UV - vec2(0.5);
	float image_aspect = image_size.x / image_size.y;
	float screen_aspect = viewport_size.x / viewport_size.y;
	if (screen_aspect > image_aspect) uv.y *= image_aspect / screen_aspect;
	else uv.x *= screen_aspect / image_aspect;
	ALBEDO = texture(background_texture, uv + vec2(0.5)).rgb * tint.rgb;
}
