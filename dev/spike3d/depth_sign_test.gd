extends Node3D
## 실험: 공간 셰이더가 DEPTH 에 쓴 값이 클수록 앞인가 뒤인가? 실제로는 뒤에 있는 빨간 상자가 DEPTH 를 '앞쪽' 값으로 쓰면 이기는지 본다.

func _make(color: Color, depth_value: float, use_depth: bool) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded;
uniform vec4 col : source_color;
uniform float d = 0.5;
uniform bool use_depth = false;
void fragment() {
	ALBEDO = col.rgb;
	DEPTH = use_depth ? d : FRAGCOORD.z;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("col", color)
	m.set_shader_parameter("d", depth_value)
	m.set_shader_parameter("use_depth", use_depth)
	return m


func _ready() -> void:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 6.0
	cam.position = Vector3(0, 0, 10)
	cam.near = 0.1
	cam.far = 100.0
	add_child(cam)
	# 가까운 파란 판(z=2)과 먼 빨간 판(z=-2)이 화면에서 겹친다. 실제 깊이로는 파란 판이 앞.
	var blue := MeshInstance3D.new()
	var qb := QuadMesh.new()
	qb.size = Vector2(3, 3)
	blue.mesh = qb
	blue.position = Vector3(-0.8, 0, 2)
	add_child(blue)
	var red := MeshInstance3D.new()
	var qr := QuadMesh.new()
	qr.size = Vector2(3, 3)
	red.mesh = qr
	red.position = Vector3(0.8, 0, -2)
	add_child(red)

	var case_index: int = 0

	for case in [["실제 깊이만(기본)", -1.0, -1.0], ["빨강 DEPTH=0.9, 파랑 0.1", 0.9, 0.1], ["빨강 DEPTH=0.1, 파랑 0.9", 0.1, 0.9]]:
		blue.material_override = _make(Color(0, 0, 1), case[2], case[2] >= 0.0)
		red.material_override = _make(Color(1, 0, 0), case[1], case[1] >= 0.0)

		for i in 12:
			await get_tree().process_frame

		var img: Image = get_viewport().get_texture().get_image()
		# 겹치는 가운데 지점 색
		var c: Color = img.get_pixel(img.get_width() / 2, img.get_height() / 2)
		img.save_png("/tmp/claude-0/-home-user-project222/bebbb279-1de2-53fc-a969-a86653068aa7/scratchpad/depth_sign_%d.png" % case_index)
		case_index += 1
		var left: Color = img.get_pixel(img.get_width() / 2 - 150, img.get_height() / 2)
		var right: Color = img.get_pixel(img.get_width() / 2 + 150, img.get_height() / 2)
		print("  (왼쪽 %s / 가운데 %s / 오른쪽 %s)" % [left, c, right])
		print("%s → 겹친 자리 색: %s" % [case[0], "파랑(파랑이 앞)" if c.b > c.r else "빨강(빨강이 앞)"])

	get_tree().quit()
