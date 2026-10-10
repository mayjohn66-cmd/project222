shader_type spatial;
// Full camera-facing quad: uploaded artwork already includes the isometric angle and shading.
render_mode unshaded, cull_disabled, shadows_disabled;
uniform sampler2D frame_texture : source_color, filter_nearest;
uniform vec4 region = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 light_tint : source_color = vec4(1.0);
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
	ALBEDO = color.rgb * light_tint.rgb;
	DEPTH = use_sort ? 0.1 + 0.8 * (rank + 1.5) / (rank_count + 1.0) : FRAGCOORD.z;
}
