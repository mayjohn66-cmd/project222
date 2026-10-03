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
// 같은 물체 안의 부품 순서(0 = 가장 뒤, 1 = 가장 앞). 순번 칸 안에서 아주 조금 깊이를 달리해, 그리는 순서에 기대지 않고 부품끼리 가린다.
uniform float sub = 0.5;
// 법선 맵(선택). 메시의 UV 와 접선(SurfaceTool.generate_tangents)을 따라 기와 요철 등을 낸다.
uniform sampler2D normal_tex : hint_normal, filter_nearest, repeat_enable;
uniform bool use_normal = false;
// 따뜻한 밝은 색 픽셀(가게 진열창 안쪽의 빛)만 스스로 빛나게 하는 정도. 0 이면 끔. 그림자(차양 그늘)가 져도 창 안이 어둡게 죽지 않게 한다.
uniform float emit_strength = 0.0;

void fragment() {
	vec3 albedo_rgb = texture(albedo_tex, UV * uv_scale).rgb;
	ALBEDO = albedo_rgb * tint.rgb;
	float warm = step(0.85, albedo_rgb.r) * step(0.7, albedo_rgb.g) * (1.0 - step(0.8, albedo_rgb.b));
	EMISSION = albedo_rgb * emit_strength * warm;

	if (use_normal) {
		NORMAL_MAP = texture(normal_tex, UV * uv_scale).rgb;
	}

	if (use_sort) {
		float band = 1.0 / (rank_count + 1.0);
		DEPTH = 0.1 + 0.8 * ((rank + 1.5) * band + (sub - 0.5) * 0.8 * band);
	} else {
		DEPTH = FRAGCOORD.z;
	}
}
