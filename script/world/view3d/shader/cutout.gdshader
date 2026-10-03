shader_type spatial;
// 풀 다발처럼 투명한 부분이 있는 그림(알파 컷아웃). facade.gdshader 와 같은 순번 깊이를 쓰되 알파 절반 미만 픽셀은 그리지 않는다.
// 주의: discard 가 있는 셰이더는 그림자 패스에서도 DEPTH 를 쓰게 되어 그림자 깊이가 틀어진다 → 이 재질을 쓰는 물체는 그림자를 드리우지 않게(cast_shadow OFF) 해야 한다.
render_mode diffuse_toon, specular_disabled;

uniform sampler2D albedo_tex : source_color, filter_nearest, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec2 uv_scale = vec2(1.0);
uniform float rank = 0.0;
uniform float rank_count = 1.0;
uniform bool use_sort = true;
uniform vec3 center_world = vec3(0.0);
uniform float sub = 0.5;

void fragment() {
	vec4 s = texture(albedo_tex, UV * uv_scale);
	if (s.a < 0.5) {
		discard;
	}
	ALBEDO = s.rgb * tint.rgb;

	if (use_sort) {
		float band = 1.0 / (rank_count + 1.0);
		DEPTH = 0.1 + 0.8 * ((rank + 1.5) * band + (sub - 0.5) * 0.8 * band);
	} else {
		DEPTH = FRAGCOORD.z;
	}
}
