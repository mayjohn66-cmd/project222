shader_type spatial;
// 정렬 순서를 깊이에 넣는 캐릭터 판. 카메라를 보되 위아래로는 눕지 않는다(Y 빌보드). 그림은 시트의 한 칸(region)만 쓴다.
render_mode diffuse_toon, specular_disabled, cull_disabled, shadows_disabled;

uniform sampler2D sheet : source_color, filter_nearest;
uniform vec4 region = vec4(0.0, 0.0, 0.25, 0.2);  // x, y, w, h (UV 비율)
uniform float rank = 0.0;
uniform float rank_count = 1.0;
uniform vec3 center_world = vec3(0.0);
// 같은 물체 안의 깊이 변화(눌러서 남기는 두께). 이 환경의 소프트웨어 렌더러에서는 값이 0이 아니면 줄무늬 구멍이 생겨서 기본 0(물체 전체가 한 깊이).
// 볼록한 상자는 뒷면을 그리지 않으면 보이는 면끼리 겹치지 않으므로 한 깊이로도 모양이 같다.
uniform float local_scale = 0.0;
uniform bool use_sort = true;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], MODEL_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	NORMAL = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz;
}

void fragment() {
	vec4 c = texture(sheet, region.xy + UV * region.zw);
	if (c.a < 0.5) {
		discard;
	}
	ALBEDO = c.rgb;

	if (use_sort) {
		float cz = (VIEW_MATRIX * vec4(center_world, 1.0)).z;
		float band = 1.0 / (rank_count + 1.0);
		float local = clamp((VERTEX.z - cz) * local_scale, -0.45 * band, 0.45 * band);
		DEPTH = 0.1 + 0.8 * ((rank + 1.5) * band + local);
	} else {
		DEPTH = FRAGCOORD.z;
	}
}
