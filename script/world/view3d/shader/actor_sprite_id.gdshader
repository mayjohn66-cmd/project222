shader_type spatial;
// Same silhouette/anchor/depth as color pass: transparent canvas never hides furniture.
render_mode unshaded, cull_disabled;
uniform sampler2D frame_texture : filter_nearest;
uniform vec4 region = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec2 frame_offset = vec2(0.0);
uniform float id = 0.0;
uniform float rank = 0.0;
uniform float rank_count = 1.0;
uniform bool use_sort = true;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	VERTEX.xy += frame_offset;
}
void fragment() {
	if (texture(frame_texture, region.xy + UV * region.zw).a < 0.5) { discard; }
	ALBEDO = vec3(id);
	DEPTH = use_sort ? 0.1 + 0.8 * (rank + 1.5) / (rank_count + 1.0) : FRAGCOORD.z;
}
