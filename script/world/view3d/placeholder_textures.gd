class_name PlaceholderTextures
extends RefCounted
## 3D 매장 층의 임시 질감(코드로 만든 도트). 실제 그림(Pixel Lab 등, 규격서 3~4장)이 들어오면 교체한다.
## 질감 한 변 = 낮은 해상도 칸 폭의 절반(36 → 18)이라야 질감 1픽셀 = 화면 1픽셀.
## 줄눈 패턴은 질감 크기 18(3줄) 기준으로 이음매 없이 반복된다.


static func is_seam(kind: String, x: int, y: int, size: int) -> bool:
	var rows: int = 3 if size % 3 == 0 else 2
	var row_h: int = size / rows
	var row: int = y / row_h

	if kind == "brick":
		var brick_w: int = size / 2
		var offset: int = (row % 2) * (brick_w / 2)
		return (y % row_h == 0) or ((x + offset) % brick_w == 0)

	if kind == "plank":
		return y % row_h == 0

	return false


static func albedo(kind: String, size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)

	for y in range(size):
		for x in range(size):
			var seam: bool = is_seam(kind, x, y, size)
			var c: Color

			match kind:
				"grass":
					var shade: float = rng.randf_range(-0.07, 0.07)
					c = Color(0.36 + shade, 0.6 + shade, 0.3 + shade)
				"brick":
					var tone: float = rng.randf_range(-0.04, 0.04)
					c = Color(0.3, 0.3, 0.38) if seam else Color(0.5 + tone, 0.5 + tone, 0.58 + tone)
				_:
					var grain: float = rng.randf_range(-0.03, 0.03)
					c = Color(0.3, 0.2, 0.12) if seam else Color(0.62 + grain, 0.43 + grain, 0.27 + grain)

			img.set_pixel(x, y, c)

	return ImageTexture.create_from_image(img)


# 높이 맵(줄눈 낮음) → 법선 맵. tools/height_to_normal.py 와 같은 계산.
static func normal(kind: String, size: int, levels: int = 2) -> ImageTexture:
	var heights: Array = []
	var rows: int = 3 if size % 3 == 0 else 2
	var row_h: int = size / rows

	for y in range(size):
		var row: Array = []

		for x in range(size):
			var hgt: float = 0.2 if is_seam(kind, x, y, size) else 0.8

			if kind == "plank" and hgt > 0.5:
				var local: int = y % row_h
				hgt += 0.12 if (local == 1 or local == row_h - 1) else 0.0

			if kind == "grass":
				hgt = 0.5 + 0.25 * sin(float(x) * 2.1 + float(y) * 1.3) * cos(float(y) * 1.7)

			row.append(hgt)

		heights.append(row)

	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)

	for y in range(size):
		for x in range(size):
			var gx: float = 0.0
			var gy: float = 0.0

			for d in [-1, 0, 1]:
				var w: float = 2.0 if d == 0 else 1.0
				gx += w * (float(heights[posmod(y + d, size)][posmod(x + 1, size)]) - float(heights[posmod(y + d, size)][posmod(x - 1, size)]))
				gy += w * (float(heights[posmod(y + 1, size)][posmod(x + d, size)]) - float(heights[posmod(y - 1, size)][posmod(x + d, size)]))

			var nx: float = _level(-gx * 0.25, levels)
			var ny: float = _level(gy * 0.25, levels)
			var nz: float = sqrt(maxf(0.0, 1.0 - minf(1.0, nx * nx + ny * ny)))
			img.set_pixel(x, y, Color(nx * 0.5 + 0.5, ny * 0.5 + 0.5, nz * 0.5 + 0.5))

	return ImageTexture.create_from_image(img)


static func _level(v: float, levels: int) -> float:
	if levels <= 0:
		return v

	return clampf(roundf(v * float(levels)) / float(levels), -1.0, 1.0)


# 건물 벽 면 질감(코드로 칠한 임시 그림): 회반죽 + 나무 뼈대 + 창문 + (선택) 문. 크기는 면의 칸 폭 × 18, 높이(블록) × 블록 px.
static func wall_facade(width_texels: int, height_texels: int, door: bool, window_count: int, plaster: Color, timber: Color) -> ImageTexture:
	var w: int = maxi(width_texels, 4)
	var h: int = maxi(height_texels, 4)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = w * 131 + h
	var glass := Color(0.45, 0.62, 0.78)
	var door_color := Color(0.5, 0.3, 0.16)

	for y in range(h):
		for x in range(w):
			var shade: float = rng.randf_range(-0.03, 0.03)
			img.set_pixel(x, y, Color(plaster.r + shade, plaster.g + shade, plaster.b + shade))

	# 아래쪽 돌 기단 + 윗 가로 보 + 양 끝 세로 보
	var base_h: int = clampi(int(float(h) * 0.16), 2, 6)

	for y in range(h - base_h, h):
		for x in range(w):
			var stone: float = 0.55 + rng.randf_range(-0.05, 0.05)
			img.set_pixel(x, y, Color(stone, stone, stone * 0.95))

	for x in range(w):
		for y in range(0, 2):
			img.set_pixel(x, y, timber)

	for y in range(h):
		for x in [0, 1, w - 2, w - 1]:
			img.set_pixel(x, y, timber)

	# 창문: 가로를 window_count 칸으로 나눠 가운데에 하나씩. 문이 있으면 문 칸은 창문 대신 문.
	var cells: int = maxi(window_count, 1)
	var door_cell: int = cells / 2 if door else -1

	for k in range(cells):
		var cx: int = int((float(k) + 0.5) * float(w) / float(cells))

		if k == door_cell:
			var dw: int = clampi(int(float(w) / float(cells) * 0.45), 4, 14)
			var dh: int = clampi(int(float(h) * 0.62), 6, 40)

			for y in range(h - base_h - dh, h - base_h):
				for x in range(cx - dw / 2, cx - dw / 2 + dw):
					if x >= 0 and x < w and y >= 0:
						img.set_pixel(x, y, door_color if (x != cx - dw / 2 and x != cx - dw / 2 + dw - 1 and y != h - base_h - dh) else timber)

			if cx + 2 < w and h - base_h - dh / 2 >= 0:
				img.set_pixel(cx + dw / 4, h - base_h - dh / 2, Color(0.9, 0.8, 0.3))
		else:
			var ww: int = clampi(int(float(w) / float(cells) * 0.4), 4, 12)
			var wh: int = clampi(int(float(h) * 0.36), 4, 14)
			var wy: int = int(float(h) * 0.22)

			for y in range(wy, wy + wh):
				for x in range(cx - ww / 2, cx - ww / 2 + ww):
					if x >= 0 and x < w and y >= 0 and y < h:
						var edge: bool = x == cx - ww / 2 or x == cx - ww / 2 + ww - 1 or y == wy or y == wy + wh - 1
						var bar: bool = x == cx or y == wy + wh / 2
						img.set_pixel(x, y, timber if (edge or bar) else glass)

	return ImageTexture.create_from_image(img)


# 기와 지붕 질감: 한 칸(size×size) 반복. 가로줄마다 어긋난 둥근 기와.
static func roof_tiles(size: int, base: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rows: int = 3 if size % 3 == 0 else 2
	var row_h: int = size / rows
	var tile_w: int = maxi(size / 3, 3)

	for y in range(size):
		var row: int = y / row_h
		var offset: int = (row % 2) * (tile_w / 2)

		for x in range(size):
			var local_y: int = y % row_h
			var edge: bool = local_y == 0 or ((x + offset) % tile_w) == 0
			var c: Color = base.darkened(0.35) if edge else base.lightened(0.04 * float(local_y))
			img.set_pixel(x, y, c)

	return ImageTexture.create_from_image(img)
