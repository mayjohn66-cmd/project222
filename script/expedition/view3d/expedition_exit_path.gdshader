shader_type spatial;
render_mode diffuse_lambert, specular_disabled, depth_prepass_alpha;
uniform sampler2D tile_1 : source_color, filter_nearest;
uniform sampler2D tile_2 : source_color, filter_nearest;
uniform sampler2D tile_3 : source_color, filter_nearest;
uniform sampler2D normal_1 : hint_normal, filter_nearest;
uniform sampler2D normal_2 : hint_normal, filter_nearest;
uniform sampler2D normal_3 : hint_normal, filter_nearest;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec2 exit_position = vec2(3.5,0.5);
uniform float path_width = 1.3;
uniform float path_length = 3.5;
uniform float inside_length = 0.75;
uniform float opened = 1.0;
uniform bool straight_edges = false;
varying vec3 world_pos;
void vertex() { world_pos = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
vec4 sample_three(sampler2D a,sampler2D b,sampler2D c,vec2 uv,float variant) {
	return variant < 1.0 ? texture(a,uv) : (variant < 2.0 ? texture(b,uv) : texture(c,uv));
}
void fragment() {
	vec2 cell = floor(world_pos.xz);
	vec2 local = fract(world_pos.xz);
	vec2 uv = vec2(0.5+(local.x-local.y)*0.5,(local.x+local.y)*0.5);
	float variant = mod(abs(cell.x*17.0+cell.y*31.0),3.0);
	vec4 color = sample_three(tile_1,tile_2,tile_3,uv,variant);
	if (color.a < 0.5) {
		uv = mix(vec2(0.5),uv,0.94);
		color = sample_three(tile_1,tile_2,tile_3,uv,variant);
	}
	vec3 n = sample_three(normal_1,normal_2,normal_3,uv,variant).rgb*2.0-1.0;
	vec3 world_n = normalize(vec3((n.x-n.y)*0.55,n.z,(-n.x-n.y)*0.55));
	NORMAL = normalize((VIEW_MATRIX*vec4(world_n,0.0)).xyz);
	float progress = (exit_position.y + inside_length - world_pos.z) / path_length;
	float center = exit_position.x + (straight_edges ? 0.0 : sin((world_pos.z-exit_position.y)*0.9)*0.1);
	float side = 1.0-smoothstep(path_width*0.43,path_width*0.53,abs(world_pos.x-center));
	float ends = smoothstep(0.0,0.13,progress) * (1.0-smoothstep(0.72,1.0,progress));
	ALBEDO = color.rgb*tint.rgb*mix(0.58,1.0,opened);
	ALPHA = side*ends;
	DEPTH = FRAGCOORD.z;
}
