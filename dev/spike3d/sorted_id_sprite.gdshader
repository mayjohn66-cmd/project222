shader_type spatial;
// 캐릭터 판의 물체 번호. 그림이 투명한 곳은 그리지 않는다.
render_mode unshaded, cull_disabled;

uniform sampler2D sheet : source_color, filter_nearest;
uniform vec4 region = vec4(0.0, 0.0, 0.25, 0.2);
uniform float id = 0.0;
uniform float rank = 0.0;
uniform float rank_count = 1.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], MODEL_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec4 c = texture(sheet, region.xy + UV * region.zw);
	if (c.a < 0.5) {
		discard;
	}
	ALBEDO = vec3(id);
	float band = 1.0 / (rank_count + 1.0);
	DEPTH = 0.1 + 0.8 * ((rank + 1.5) * band);
}
