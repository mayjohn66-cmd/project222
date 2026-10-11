shader_type spatial;
// Full camera-facing quad; source pixels stay fixed while normals respond to world lights.
render_mode diffuse_lambert, specular_disabled, cull_disabled;
uniform sampler2D frame_texture : source_color, filter_nearest;
uniform vec4 region = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 light_tint : source_color = vec4(1.0);
uniform sampler2D normal_texture : hint_normal, filter_nearest;
uniform float normal_strength = 0.55;
uniform vec3 normal_base = vec3(0.0);
uniform float unlit_top = 0.0;
uniform bool use_normal = true;
// Optional village glass glow. Default OFF for actors and every other world sprite.
uniform bool use_emission = false;
uniform sampler2D emission_texture : filter_nearest;
uniform float emission_strength = 0.0;
uniform vec2 frame_offset = vec2(0.0);
#include "res://script/world/view3d/shader/pixel_cutaway.gdshaderinc"
uniform float rank = 0.0;
uniform float rank_count = 1.0;
uniform bool use_sort = true;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	VERTEX.xy += frame_offset;
}
void fragment() {
	vec4 color = texture(frame_texture, region.xy + UV * region.zw);
	if (color.a < 0.5) { discard; }
	if (cutaway_hidden(region.xy + UV * region.zw, vec2(textureSize(frame_texture, 0)))) { discard; }
	vec2 at = region.xy + UV * region.zw;
	vec3 base = length(normal_base) > 0.1 ? normal_base : INV_VIEW_MATRIX[2].xyz;
	vec3 n = use_normal ? texture(normal_texture, at).rgb * 2.0 - 1.0 : vec3(0.0,0.0,1.0);
	vec3 tangent = normalize(INV_VIEW_MATRIX[0].xyz-base*dot(INV_VIEW_MATRIX[0].xyz,base));
	vec3 bitangent = normalize(cross(base,tangent));
	vec3 world_n = normalize(base*n.z + (tangent*n.x + bitangent*n.y)*normal_strength);
	NORMAL = normalize((VIEW_MATRIX * vec4(world_n,0.0)).xyz);
	ALBEDO = color.rgb * light_tint.rgb;
	if (use_emission) { EMISSION = color.rgb * texture(emission_texture,at).r * emission_strength; }
	if (at.y < unlit_top) { EMISSION = ALBEDO; ALBEDO = vec3(0.0); }
	DEPTH = use_sort ? 0.1 + 0.8 * (rank + 1.5) / (rank_count + 1.0) : FRAGCOORD.z;
}
