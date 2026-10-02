extends Node
## PNG 질감(알베도·법선)을 Godot 가 손상 없이 가져오는지, 코드로 만든 질감과 화면이 같은지 확인한다(개발용). 인자: --out <폴더>
func _ready() -> void:
	var out: String = ""
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--out" and i + 1 < args.size():
			out = args[i + 1]

	# 1) 가져온 질감이 원본 PNG 와 픽셀 단위로 같은가(압축·흐림 없음)
	for name in ["brick_18_a", "brick_18_n", "plank_18_a", "plank_18_n"]:
		var path: String = "res://dev/spike3d/textures/%s.png" % name
		var src: Image = Image.load_from_file(ProjectSettings.globalize_path(path))
		var tex: Texture2D = load(path)
		var got: Image = tex.get_image()
		got.decompress()
		got.convert(Image.FORMAT_RGBA8)
		src.convert(Image.FORMAT_RGBA8)
		var diff: int = 0
		var max_d: int = 0

		for y in range(src.get_height()):
			for x in range(src.get_width()):
				var a: Color = src.get_pixel(x, y)
				var b: Color = got.get_pixel(x, y)
				var d: int = int(maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b)) * 255.0 + 0.5)
				max_d = maxi(max_d, d)
				diff += 1 if d > 0 else 0

		print("import_check ", name, " size=", got.get_size(), " format=", tex.get_class(), " different_pixels=", diff, " max_channel_diff=", max_d)

	# 2) 같은 장면(12시, 법선 켬)을 코드 질감과 PNG 질감으로 그려 비교
	var scene = load("res://dev/spike3d/store_spike.tscn").instantiate()
	add_child(scene)
	for i in range(120):
		await get_tree().process_frame
	scene.freeze_crowd = true
	scene.apply_time(12.0)
	scene.set_normal_map(true)
	var shots: Array = []

	for use_png in [false, true]:
		scene.set_png_textures(use_png)
		for i in 8:
			await get_tree().process_frame
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png("%s/png_%s.png" % [out, "file" if use_png else "code"])
		shots.append(img)

	var a: Image = shots[0]
	var b: Image = shots[1]
	var changed: int = 0
	var big: int = 0

	for y in range(a.get_height()):
		for x in range(a.get_width()):
			var ca: Color = a.get_pixel(x, y)
			var cb: Color = b.get_pixel(x, y)
			var d: float = maxf(maxf(absf(ca.r - cb.r), absf(ca.g - cb.g)), absf(ca.b - cb.b))

			if d > 0.004:
				changed += 1

			if d > 0.08:
				big += 1

	print("render_compare changed_pixels=", changed, " big_diff_pixels=", big, " total=", a.get_width() * a.get_height())
	get_tree().quit()
