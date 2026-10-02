shader_type spatial;
// 상자 캐릭터 부품의 윤곽선용 번호 판(캐릭터 전체가 같은 번호). 깊이는 blocky_part 와 같은 식.
render_mode unshaded;
uniform float id = 0.0;
uniform float rank = 0.0;
uniform float rank_count = 1.0;
uniform float sub = 0.5;
void fragment() {
	ALBEDO = vec3(id);
	float band = 1.0 / (rank_count + 1.0);
	DEPTH = 0.1 + 0.8 * ((rank + 1.5) * band + (sub - 0.5) * 0.8 * band);
}
