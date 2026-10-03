extends Node3D
## 실험: 평면 하나가 DEPTH 에 상수를 쓸 때 어떤 값에서 구멍(하늘색)이 생기는가?

func _ready() -> void:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 10.0
	cam.rotation_degrees = Vector3(-30, 45, 0)
	cam.position = cam.basis.z * 30.0
	cam.near = 0.1
	cam.far = 100.0
	add_child(cam)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.72, 0.9)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(14, 12)
	plane.mesh = pm
	add_child(plane)
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded;
uniform float d = 0.5;
uniform bool use_d = true;
void fragment() {
	ALBEDO = vec3(0.3, 0.7, 0.3);
	DEPTH = use_d ? d : FRAGCOORD.z;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	plane.material_override = m
	for dv in [-1.0, 0.02, 0.1, 0.3, 0.5, 0.9, 0.999]:
		m.set_shader_parameter("use_d", dv >= 0.0)
		m.set_shader_parameter("d", maxf(dv, 0.0))
		for i in 6:
			await get_tree().process_frame
		var img: Image = get_viewport().get_texture().get_image()
		var sky: int = 0
		var tot: int = 0
		for y in range(260, 400, 3):
			for x in range(450, 700, 3):
				tot += 1
				var c: Color = img.get_pixel(x, y)
				if absf(c.r - 0.55) < 0.05 and absf(c.g - 0.72) < 0.05 and absf(c.b - 0.9) < 0.05:
					sky += 1
		print("DEPTH %s → 중앙부 하늘색 %.1f%%" % ["(FRAGCOORD.z)" if dv < 0.0 else str(dv), float(sky) / float(tot) * 100.0])
	get_tree().quit()
