shader_type spatial;
// 윤곽선용 물체 번호 판. 색 대신 "순번을 정규화한 값"을 그린다. 깊이는 본 장면과 같은 식(순번 깊이)이라 같은 앞뒤로 그려진다.
render_mode unshaded;

uniform float id = 0.0;
uniform float rank = 0.0;
uniform float rank_count = 1.0;

void fragment() {
	ALBEDO = vec3(id);
	float band = 1.0 / (rank_count + 1.0);
	DEPTH = 0.1 + 0.8 * ((rank + 1.5) * band);
}
