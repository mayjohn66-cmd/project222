extends Node
## 2D 스프라이트(빵집) + 자동 법선 맵 + 2D 조명(DirectionalLight2D)으로 낮·밤을 그려 보는 시제품(개발용).
## 인자: --out <폴더>. 같은 시각마다 (1) 색조만(지금 2D 게임 방식) (2) 법선 맵 조명 을 저장한다.

const HOURS: Array = [9.0, 12.0, 17.5, 19.0, 21.0]


func _ready() -> void:
	var out: String = ""
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--out" and i + 1 < args.size():
			out = args[i + 1]

	get_window().size = Vector2i(640, 520)
	var bg := ColorRect.new()
	bg.color = Color(0.2, 0.42, 0.14)
	bg.size = Vector2(640, 520)
	bg.z_index = -10
	add_child(bg)

	var diffuse: Texture2D = load("res://dev/spike3d/lit2d/bakery_d.png")
	var normal: Texture2D = load("res://dev/spike3d/lit2d/bakery_n.png")
	var ct := CanvasTexture.new()
	ct.diffuse_texture = diffuse
	ct.normal_texture = normal
	ct.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var spr := Sprite2D.new()
	spr.texture = ct
	spr.position = Vector2(320, 270)
	spr.scale = Vector2(0.3, 0.3)
	add_child(spr)

	var mod := CanvasModulate.new()
	add_child(mod)
	var sun := DirectionalLight2D.new()
	sun.height = 0.55
	sun.shadow_enabled = false
	add_child(sun)

	for lit in [false, true]:
		spr.texture = ct if lit else diffuse
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sun.enabled = lit

		for h in HOURS:
			var tint: Color = TimeOfDayData.get_tint(h)
			var day_amt: float = smoothstep(5.0, 7.0, h) * (1.0 - smoothstep(17.0, 19.0, h))
			var sun_curve: float = clampf(sin((h - 6.0) / 12.0 * PI), 0.0, 1.0)

			if lit:
				var soft: Color = Color.WHITE.lerp(tint, 0.75)
				mod.color = Color(0.62, 0.64, 0.74) * soft
				sun.color = soft
				sun.energy = lerpf(0.35, lerpf(0.55, 0.95, sun_curve), day_amt)
				# 해 방향: 낮에 동→서로 움직임. DirectionalLight2D 는 회전각이 빛 방향
				sun.rotation_degrees = lerpf(-60.0, 60.0, clampf((h - 6.0) / 12.0, 0.0, 1.0)) + 90.0
			else:
				mod.color = tint

			for i in range(4):
				await get_tree().process_frame

			get_viewport().get_texture().get_image().save_png("%s/lit2d_%s_%03d.png" % [out, "normal" if lit else "flat", int(h * 10)])

	get_tree().quit()
