extends Node
## 픽셀 스냅 효과를 숫자로 잰다(Never's End 글의 방법): 카메라를 소수 픽셀씩 천천히 옮기며 앞 프레임과 비교한다.
## 앞 프레임을 가로·세로 -2~2 픽셀 어긋나게 맞춰 본 뒤에도 다른 픽셀이 몇 % 남는지 잰다. 스냅을 켜면 거의 0 이어야 한다.
## 인자: --out <폴더>

func _diff_ratio(a: Image, b: Image) -> float:
	var best: float = 1.0
	var w: int = a.get_width()
	var h: int = a.get_height()

	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var diff: int = 0
			var total: int = 0

			for y in range(4, h - 4, 2):
				for x in range(4, w - 4, 2):
					total += 1

					if a.get_pixel(x, y) != b.get_pixel(x + dx, y + dy):
						diff += 1

			best = minf(best, float(diff) / float(total))

	return best


# 앞 프레임과 가장 잘 맞는 이동량으로 맞춘 뒤 다른 픽셀을 빨갛게 칠한 그림.
func _diff_image(a: Image, b: Image) -> Image:
	var best: float = 2.0
	var best_shift := Vector2i.ZERO

	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var diff: int = 0
			var total: int = 0

			for y in range(4, a.get_height() - 4, 2):
				for x in range(4, a.get_width() - 4, 2):
					total += 1

					if a.get_pixel(x, y) != b.get_pixel(x + dx, y + dy):
						diff += 1

			var ratio: float = float(diff) / float(total)

			if ratio < best:
				best = ratio
				best_shift = Vector2i(dx, dy)

	var out := Image.create(a.get_width(), a.get_height(), false, Image.FORMAT_RGBA8)

	for y in range(4, a.get_height() - 4):
		for x in range(4, a.get_width() - 4):
			var same: bool = a.get_pixel(x, y) == b.get_pixel(x + best_shift.x, y + best_shift.y)
			out.set_pixel(x, y, a.get_pixel(x, y).darkened(0.35) if same else Color(1, 0.1, 0.1))

	out.resize(a.get_width() * 3, a.get_height() * 3, Image.INTERPOLATE_NEAREST)
	return out


func _ready() -> void:
	var out: String = ""
	var args := OS.get_cmdline_user_args()

	for i in range(args.size()):
		if args[i] == "--out" and i + 1 < args.size():
			out = args[i + 1]

	var scene = load("res://dev/spike3d/iso_room_spike.tscn").instantiate()
	add_child(scene)
	scene.shrink = 3
	scene.toon = true
	scene.shadows = false  # 그림자 가장자리는 따로 흔들려서 이번 측정에서는 끈다
	scene._apply_shrink()
	scene.set_process(false)

	for snap in [false, true]:
		scene.snap = snap
		scene.cam_target = Vector3(4, 0, 4)
		scene._update_camera()

		for i in 3:
			await get_tree().process_frame

		var prev: Image = scene.viewport.get_texture().get_image()
		var sum: float = 0.0
		var count: int = 0
		var step: float = 0.37 * scene.pixel_world_size()  # 한 프레임에 0.37 픽셀씩

		for f in range(1, 21):
			scene.cam_target += scene.camera.basis.x * step
			scene._update_camera()

			for i in 2:
				await get_tree().process_frame

			var cur: Image = scene.viewport.get_texture().get_image()
			sum += _diff_ratio(prev, cur)

			if f == 10 and not out.is_empty():
				_diff_image(prev, cur).save_png("%s/snap_diff_%s.png" % [out, "on" if snap else "off"])

			count += 1
			prev = cur

		print("스냅 %s: 앞 프레임과 한 픽셀 단위로 맞춘 뒤에도 다른 픽셀 평균 %.3f%%" % ["켬" if snap else "끔", sum / float(count) * 100.0])

	get_tree().quit()
