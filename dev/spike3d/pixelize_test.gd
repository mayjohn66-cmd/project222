extends Node
## 3D 도트화 시험: 현재 3D 가게 화면에 후처리(저해상도 → 색 줄이기 → 외곽선)를 얹어 원본과 비교 캡처한다.
## 사용: godot --path . res://dev/spike3d/pixelize_test.tscn -- <저장 폴더>  (화면 필요: xvfb 등)
const SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float pixel_size = 3.0;      // 큰 도트로 뭉치는 크기(화면 픽셀)
uniform float levels = 6.0;          // 색 단계(채널당): 낮을수록 색이 적다
uniform float outline_strength = 0.55;
uniform float edge_threshold = 0.18;
uniform float saturation = 1.18;
vec3 quant(vec3 c) { return floor(c * levels + 0.5) / levels; }
void fragment() {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 cell = floor(FRAGCOORD.xy / pixel_size) * pixel_size + pixel_size * 0.5;
	vec2 uv = cell / res;
	vec3 c = texture(screen_tex, uv).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	// 이웃 도트와의 밝기 차이로 외곽선
	float e = 0.0;
	vec2 step_uv = vec2(pixel_size) / res;
	for (int i = 0; i < 4; i++) {
		vec2 d = (i == 0) ? vec2(1, 0) : (i == 1) ? vec2(-1, 0) : (i == 2) ? vec2(0, 1) : vec2(0, -1);
		vec3 n = texture(screen_tex, uv + d * step_uv).rgb;
		e = max(e, abs(dot(n, vec3(0.299, 0.587, 0.114)) - l));
	}
	vec3 g = vec3(l);
	c = mix(g, c, saturation);
	c = quant(c);
	if (e > edge_threshold) c = mix(c, c * 0.28, outline_strength);
	COLOR = vec4(c, 1.0);
}
"""
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run")
func snap(path: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)
func run() -> void:
	var dir: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp/pixelize"
	DirAccess.make_dir_recursive_absolute(dir)
	var world = load("res://scenes/shop/main.tscn").instantiate()
	add_child(world)
	for i in range(40): await get_tree().process_frame
	var ui = world.get_node_or_null("UI")
	if ui != null: ui.visible = false
	var d = world.get_node_or_null("TutorialDirector")
	if d != null: d.dialogue.close()
	if d != null: d.dialogue.root.visible = false
	await get_tree().create_timer(9.0, true, false, true).timeout   # 도입 연출의 현대 편의점(진열대·냉장고)이 보일 때까지
	if d != null: d.dialogue.root.visible = false
	await snap(dir + "/a_current.png")
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = SHADER
	rect.material = mat
	layer.add_child(rect)
	for variant in [["b_outline_only", 3.0, 24.0, 0.6], ["c_levels8", 3.0, 8.0, 0.5], ["d_pixel4_levels12", 4.0, 12.0, 0.55]]:
		mat.set_shader_parameter("pixel_size", variant[1])
		mat.set_shader_parameter("levels", variant[2])
		mat.set_shader_parameter("outline_strength", variant[3])
		await snap(dir + "/%s.png" % variant[0])
	print("saved to ", dir)
	get_tree().quit()
