shader_type spatial;
// 정렬 순서를 깊이에 넣는 표면. 물체마다 "순번(rank)"을 받아, 순번이 큰(앞쪽) 물체가 항상 위에 그려진다.
// 같은 물체 안의 앞뒤(윗면·옆면)는 두께를 눌러서(local_scale) 그 물체의 순번 칸 안에 넣는다. (Never's End 의 "깊이를 순번으로 민다")
// Godot 에서 DEPTH 는 값이 클수록 앞이다(이 프로젝트의 gl_compatibility 렌더러에서 시험으로 확인).
render_mode diffuse_toon, specular_disabled;

uniform sampler2D albedo_tex : source_color, filter_nearest, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float rank = 0.0;
uniform float rank_count = 1.0;
uniform vec3 center_world = vec3(0.0);
// 같은 물체 안의 깊이 변화(눌러서 남기는 두께). 이 환경의 소프트웨어 렌더러에서는 값이 0이 아니면 줄무늬 구멍이 생겨서 기본 0(물체 전체가 한 깊이).
// 볼록한 상자는 뒷면을 그리지 않으면 보이는 면끼리 겹치지 않으므로 한 깊이로도 모양이 같다.
uniform float local_scale = 0.0;
uniform bool use_sort = true;
uniform float texel_per_unit = 1.0;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = abs(world_normal);
	vec2 uv;
	if (n.y > 0.5) {
		uv = world_pos.xz;
	} else if (n.x > 0.5) {
		uv = vec2(world_pos.z, -world_pos.y);
	} else {
		uv = vec2(world_pos.x, -world_pos.y);
	}
	ALBEDO = texture(albedo_tex, uv * texel_per_unit).rgb * tint.rgb;

	if (use_sort) {
		float cz = (VIEW_MATRIX * vec4(center_world, 1.0)).z;
		float band = 1.0 / (rank_count + 1.0);
		float local = clamp((VERTEX.z - cz) * local_scale, -0.45 * band, 0.45 * band);
		DEPTH = 0.1 + 0.8 * ((rank + 1.5) * band + local);
	} else {
		DEPTH = FRAGCOORD.z;
	}
}
