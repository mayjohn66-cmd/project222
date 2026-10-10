shader_type spatial;
// 64x32 등각 원본을 월드 평면에 역투영한다. 변형은 칸 좌표로 정해 카메라 이동 중에도 고정된다.
render_mode unshaded;
uniform sampler2D tile_1 : source_color, filter_nearest;
uniform sampler2D tile_2 : source_color, filter_nearest;
uniform sampler2D tile_3 : source_color, filter_nearest;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 light_tint : source_color = vec4(1.0);
uniform vec4 lamps[16]; // xyz=현재 점등 위치, w=유효 거리(꺼진 등은 0).
uniform vec4 lamp_colors[16];
uniform float rank = -1.0;
uniform float rank_count = 1.0;
uniform vec3 center_world = vec3(0.0);
varying vec3 world_pos;
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 cell = floor(world_pos.xz + vec2(0.5));
	vec2 local = fract(world_pos.xz + vec2(0.5));
	vec2 uv = vec2(0.5 + (local.x - local.y) * 0.5, (local.x + local.y) * 0.5);
	float variant = mod(abs(cell.x * 17.0 + cell.y * 31.0), 3.0);
	vec4 color;
	if (variant < 1.0) { color = texture(tile_1, uv); }
	else if (variant < 2.0) { color = texture(tile_2, uv); }
	else { color = texture(tile_3, uv); }
	// 최근접 샘플이 투명 외곽에 닿을 때만 안쪽 색을 사용해 검은 이음새를 막는다.
	if (color.a < 0.5) {
		uv = mix(vec2(0.5), uv, 0.94);
		if (variant < 1.0) { color = texture(tile_1, uv); }
		else if (variant < 2.0) { color = texture(tile_2, uv); }
		else { color = texture(tile_3, uv); }
	}
	vec3 light = light_tint.rgb;
	for (int i = 0; i < 16; i++) {
		float strength = clamp(1.0 - distance(world_pos, lamps[i].xyz) / max(lamps[i].w, 0.001), 0.0, 1.0);
		light = mix(light, lamp_colors[i].rgb, strength * lamp_colors[i].a * 0.55);
	}
	ALBEDO = color.rgb * tint.rgb * light;
	DEPTH = 0.1 + 0.8 * (rank + 1.5) / (rank_count + 1.0);
}
