shader_type spatial;
// 상자로 만든 캐릭터의 부품(머리·몸통·팔·다리) 표면. 앞/옆/윗면 그림을 상자의 국소 좌표에서 골라 씌운다.
// 깊이는 캐릭터 전체의 순번 칸 안에서 부품 순서(sub)로 정한다(부품끼리는 서로 가리고, 캐릭터 전체는 다른 물체와 순번으로 정렬).
render_mode diffuse_toon, specular_disabled;

uniform sampler2D tex_front : source_color, filter_nearest;
uniform sampler2D tex_side : source_color, filter_nearest;
uniform sampler2D tex_top : source_color, filter_nearest;
uniform vec3 part_size = vec3(1.0);
uniform float rank = 0.0;
uniform float rank_count = 1.0;
uniform float sub = 0.5;
uniform bool use_sort = true;  // false = 순번 깊이 대신 진짜 깊이(원정 방처럼 3D 물체가 실제 깊이로 가리는 장면)

varying vec3 lpos;
varying vec3 lnormal;

void vertex() {
	lpos = VERTEX;
	lnormal = NORMAL;
}

void fragment() {
	vec3 n = abs(lnormal);
	vec3 p = lpos / part_size;
	vec3 col;
	if (n.z > 0.5) {
		float side = sign(lnormal.z);
		col = texture(tex_front, vec2(0.5 + p.x * side, 0.5 - p.y)).rgb;
		if (side < 0.0) { col = texture(tex_top, vec2(0.5, 0.5)).rgb; } // 뒷면은 윗면(머리카락) 색
	} else if (n.x > 0.5) {
		col = texture(tex_side, vec2(0.5 - p.z * sign(lnormal.x), 0.5 - p.y)).rgb;
	} else {
		col = texture(tex_top, vec2(0.5 + p.x, 0.5 + p.z)).rgb;
	}
	ALBEDO = col;
	if (use_sort) {
		float band = 1.0 / (rank_count + 1.0);
		DEPTH = 0.1 + 0.8 * ((rank + 1.5) * band + (sub - 0.5) * 0.8 * band);
	} else {
		DEPTH = FRAGCOORD.z;
	}
}
