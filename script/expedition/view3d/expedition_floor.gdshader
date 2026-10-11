shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
// Same source tiles as the village; expedition cells run from integer corners to integer corners.
uniform sampler2D tile_1 : source_color, filter_nearest;
uniform sampler2D tile_2 : source_color, filter_nearest;
uniform sampler2D tile_3 : source_color, filter_nearest;
uniform sampler2D dirt_1 : source_color, filter_nearest;
uniform sampler2D dirt_2 : source_color, filter_nearest;
uniform sampler2D dirt_3 : source_color, filter_nearest;
uniform sampler2D water_1 : source_color, filter_nearest;
uniform sampler2D water_2 : source_color, filter_nearest;
uniform sampler2D water_3 : source_color, filter_nearest;
uniform sampler2D tile_normal_1 : hint_normal, filter_nearest;
uniform sampler2D tile_normal_2 : hint_normal, filter_nearest;
uniform sampler2D tile_normal_3 : hint_normal, filter_nearest;
uniform sampler2D dirt_normal_1 : hint_normal, filter_nearest;
uniform sampler2D dirt_normal_2 : hint_normal, filter_nearest;
uniform sampler2D dirt_normal_3 : hint_normal, filter_nearest;
uniform sampler2D water_normal_1 : hint_normal, filter_nearest;
uniform sampler2D water_normal_2 : hint_normal, filter_nearest;
uniform sampler2D water_normal_3 : hint_normal, filter_nearest;
uniform vec4 tint : source_color = vec4(1.0);
uniform float ring_tint = 0.8;
uniform bool forest_path = false;
uniform int puddle_count = 0;
uniform vec3 puddles[32];
varying vec3 world_pos;
void vertex() { world_pos = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
vec4 sample_three(sampler2D a, sampler2D b, sampler2D c, vec2 uv, float variant) {
	return variant < 1.0 ? texture(a,uv) : (variant < 2.0 ? texture(b,uv) : texture(c,uv));
}
void fragment() {
	vec2 cell = floor(world_pos.xz);
	vec2 local = fract(world_pos.xz);
	vec2 uv = vec2(0.5+(local.x-local.y)*0.5,(local.x+local.y)*0.5);
	float variant = mod(abs(cell.x*17.0+cell.y*31.0),3.0);
	bool path = forest_path && world_pos.z > -1.8 && world_pos.z < 9.15 && abs(world_pos.x-(3.5+sin(world_pos.z*0.9)*0.2)) < 0.55;
	bool wet = false;
	for (int i=0;i<puddle_count;i++) {
		vec2 d = abs(world_pos.xz-puddles[i].xy);
		// Octagonal footprint matches the original decorative water, with no collision change.
		if (max(d.x,d.y) < puddles[i].z && (d.x+d.y) < puddles[i].z*1.41421356) { wet = true; }
	}
	vec4 color = wet ? sample_three(water_1,water_2,water_3,uv,variant) : (path ? sample_three(dirt_1,dirt_2,dirt_3,uv,variant) : sample_three(tile_1,tile_2,tile_3,uv,variant));
	if (color.a < 0.5) {
		uv = mix(vec2(0.5),uv,0.94);
		color = wet ? sample_three(water_1,water_2,water_3,uv,variant) : (path ? sample_three(dirt_1,dirt_2,dirt_3,uv,variant) : sample_three(tile_1,tile_2,tile_3,uv,variant));
	}
	vec3 n = (wet ? sample_three(water_normal_1,water_normal_2,water_normal_3,uv,variant) : (path ? sample_three(dirt_normal_1,dirt_normal_2,dirt_normal_3,uv,variant) : sample_three(tile_normal_1,tile_normal_2,tile_normal_3,uv,variant))).rgb*2.0-1.0;
	vec3 world_n = normalize(vec3((n.x-n.y)*0.55,n.z,(-n.x-n.y)*0.55));
	NORMAL = normalize((VIEW_MATRIX*vec4(world_n,0.0)).xyz);
	float outside = max(max(-cell.x,cell.x-7.0),max(-cell.y,cell.y-7.0));
	float dim = outside <= 0.0 ? 1.0 : max(0.55,ring_tint-0.05*(outside-1.0));
	ALBEDO = color.rgb*tint.rgb*dim;
	DEPTH = FRAGCOORD.z;
}
