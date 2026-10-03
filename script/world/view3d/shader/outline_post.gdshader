shader_type canvas_item;
// 화면 후처리: 물체 번호 판에서 이웃 픽셀과 번호가 다르면 "앞(번호 큰) 물체" 쪽 가장자리 픽셀에 한 픽셀 윤곽선을 긋는다.
// 윤곽선 색은 그 픽셀 색을 어둡게 한 것(물체 색에 따라 색이 다른 손그림 같은 선). 색 줄이기(levels)도 같이 한다.
uniform sampler2D id_tex : filter_nearest;
uniform bool outline_on = true;
uniform float outline_dark = 0.35;
uniform float levels = 256.0;
// 빛 조절(참조 화면처럼 하이라이트가 날아가지 않게): 밝기 knee 위쪽은 부드럽게 눌러 흰색으로 날아가는 것을 막고(색은 유지),
// 어두운 쪽은 차가운 색으로 살짝 물들여(그림자 색 이동) 칙칙하지 않게 한다. knee=1.0 이면 눌러 주지 않는다.
uniform float knee = 0.78;
// 전체 노출(밝기 배율). 깔끔한 스타일은 밝은 질감이라 1 보다 낮춰 하이라이트가 날아가지 않게 한다.
uniform float exposure = 1.0;
uniform vec3 shadow_tint = vec3(0.86, 0.92, 1.12);
uniform float shadow_amount = 0.45;

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
	c.rgb *= exposure;
	float lum = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));
	if (knee < 0.999 && lum > knee) {
		float room = 1.0 - knee;
		float soft = knee + room * (1.0 - exp(-(lum - knee) / room));
		c.rgb *= soft / max(lum, 0.0001);
	}
	float shade = 1.0 - smoothstep(0.12, 0.55, lum);
	c.rgb = mix(c.rgb, c.rgb * shadow_tint, shade * shadow_amount);
	COLOR = vec4(floor(c.rgb * levels + 0.5) / levels, c.a) * tint;
}
