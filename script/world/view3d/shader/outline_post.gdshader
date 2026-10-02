shader_type canvas_item;
// 화면 후처리: 물체 번호 판에서 이웃 픽셀과 번호가 다르면 "앞(번호 큰) 물체" 쪽 가장자리 픽셀에 한 픽셀 윤곽선을 긋는다.
// 윤곽선 색은 그 픽셀 색을 어둡게 한 것(물체 색에 따라 색이 다른 손그림 같은 선). 색 줄이기(levels)도 같이 한다.
uniform sampler2D id_tex : filter_nearest;
uniform bool outline_on = true;
uniform float outline_dark = 0.35;
uniform float levels = 256.0;

void fragment() {
	vec4 tint = COLOR;  // modulate(투명도 등)가 들어 있는 기본 색
	vec4 c = texture(TEXTURE, UV);
	if (outline_on) {
		vec2 px = TEXTURE_PIXEL_SIZE;
		float id0 = texture(id_tex, UV).r;
		float edge = 0.0;
		float a = texture(id_tex, UV + vec2(px.x, 0.0)).r;
		float b = texture(id_tex, UV - vec2(px.x, 0.0)).r;
		float d = texture(id_tex, UV + vec2(0.0, px.y)).r;
		float e = texture(id_tex, UV - vec2(0.0, px.y)).r;
		float m = 0.015;
		if (a < id0 - m || b < id0 - m || d < id0 - m || e < id0 - m) {
			edge = 1.0;
		}
		c.rgb = mix(c.rgb, c.rgb * outline_dark, edge);
	}
	COLOR = vec4(floor(c.rgb * levels + 0.5) / levels, c.a) * tint;
}
