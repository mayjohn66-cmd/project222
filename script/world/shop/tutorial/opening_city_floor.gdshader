shader_type spatial;
// 64x32 등각 원본을 월드 평면에 역투영한다. 변형은 칸 좌표로 정해 카메라 이동 중에도 고정된다.
render_mode diffuse_lambert, specular_disabled;
uniform sampler2D tile_1 : source_color, filter_nearest;
uniform sampler2D tile_2 : source_color, filter_nearest;
uniform sampler2D tile_3 : source_color, filter_nearest;
uniform sampler2D normal_1 : hint_normal, filter_nearest;
uniform sampler2D normal_2 : hint_normal, filter_nearest;
uniform sampler2D normal_3 : hint_normal, filter_nearest;
uniform bool use_normal = true;
uniform float normal_strength = 0.55;
uniform vec4 tint : source_color = vec4(1.0);
uniform bool asphalt = false;
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
	vec3 n = vec3(0.0,0.0,1.0);
	if (use_normal) {
		if (variant < 1.0) { n = texture(normal_1,uv).rgb*2.0-1.0; }
		else if (variant < 2.0) { n = texture(normal_2,uv).rgb*2.0-1.0; }
		else { n = texture(normal_3,uv).rgb*2.0-1.0; }
	}
	vec3 world_n = normalize(vec3((n.x-n.y)*normal_strength,n.z,(-n.x-n.y)*normal_strength));
	NORMAL = normalize((VIEW_MATRIX*vec4(world_n,0.0)).xyz);
	// 도시 인도는 기존 포장 원본을 차분하게, 도로는 이세계 돌길 대신 미세한 아스팔트 입자로 표시한다.
	float gray = dot(color.rgb,vec3(0.299,0.587,0.114));
	vec3 surface = mix(color.rgb,vec3(gray),0.65)*0.8;
	if (asphalt) {
		vec2 pixel = floor(world_pos.xz*64.0);
		float grain = fract(sin(dot(pixel,vec2(12.9898,78.233)))*43758.5453);
		surface = vec3(0.25,0.27,0.30)+(grain-0.5)*0.016;
		NORMAL = normalize((VIEW_MATRIX*vec4(0.0,1.0,0.0,0.0)).xyz);
	}
	ALBEDO = surface * tint.rgb;
	DEPTH = 0.1 + 0.8 * (rank + 1.5) / (rank_count + 1.0);
}
