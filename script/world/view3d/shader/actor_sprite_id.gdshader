shader_type spatial;
// Same silhouette/anchor/depth as color pass: transparent canvas never hides furniture.
render_mode unshaded, cull_disabled;
uniform sampler2D frame_texture : filter_nearest;
uniform vec4 region = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec2 frame_offset = vec2(0.0);
#include "res://script/world/view3d/shader/pixel_cutaway.gdshaderinc"
#include "res://script/world/view3d/shader/wall_top.gdshaderinc"
uniform float id = 0.0;
uniform float rank = 0.0;
uniform float rank_count = 1.0;
uniform bool use_sort = true;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	VERTEX.xy += frame_offset;
}
void fragment() {
	vec3 sample_at = world_sprite_sample(UV, region, vec2(textureSize(frame_texture, 0)));
	if (sample_at.z < 0.5) { discard; }
	if (texture(frame_texture, sample_at.xy).a < 0.5) { discard; }
	if (cutaway_hidden(sample_at.xy, vec2(textureSize(frame_texture, 0)))) { discard; }
	ALBEDO = vec3(id);
	DEPTH = use_sort ? 0.1 + 0.8 * (rank + 1.5) / (rank_count + 1.0) : FRAGCOORD.z;
}
