shader_type spatial;
// 건물 면(벽·지붕·박공) 질감. 메시의 UV 로 한 장짜리 면 질감을 찍는다(벽은 창문·문이 있는 한 장, 지붕은 기와 반복).
// 깊이는 sorted_surface 와 같은 식(순번 깊이). 질감 한 픽셀 = 낮은 해상도 한 픽셀이 되도록 질감 크기를 면 크기에 맞춰 만든다.
render_mode diffuse_toon, specular_disabled;

uniform sampler2D albedo_tex : source_color, filter_nearest, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec2 uv_scale = vec2(1.0);
uniform float rank = 0.0;
uniform float rank_count = 1.0;
uniform bool use_sort = true;
uniform vec3 center_world = vec3(0.0);

void fragment() {
	ALBEDO = texture(albedo_tex, UV * uv_scale).rgb * tint.rgb;

	if (use_sort) {
		float band = 1.0 / (rank_count + 1.0);
		DEPTH = 0.1 + 0.8 * ((rank + 1.5) * band);
	} else {
		DEPTH = FRAGCOORD.z;
	}
}
