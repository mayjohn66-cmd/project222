class_name PlaceholderTextures
extends RefCounted
## 3D 매장 층의 임시 질감(코드로 만든 도트). 실제 그림(Pixel Lab 등, 규격서 3~4장)이 들어오면 교체한다.
## 질감 한 변 = 낮은 해상도 칸 폭의 절반(36 → 18)이라야 질감 1픽셀 = 화면 1픽셀.
## 줄눈 패턴은 질감 크기 18(3줄) 기준으로 이음매 없이 반복된다.

## 깔끔한 도트 스타일(카이로소프트풍 참조): 잡음·얼룩 없이 평면 색 + 얇은 선 몇 줄. false 면 이전의 질감 많은 스타일.
static var clean: bool = true


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
					if clean:
						var dot: bool = (x * 7 + y * 13) % 41 == 0
						c = Color(0.56, 0.72, 0.44) if dot else Color(0.5, 0.67, 0.4)
					else:
						var shade: float = rng.randf_range(-0.07, 0.07)
						c = Color(0.36 + shade, 0.6 + shade, 0.3 + shade)
				"brick":
					if clean:
						var edge: bool = x == 0 or y == 0
						c = Color(0.6, 0.6, 0.66) if edge else Color(0.68, 0.68, 0.74)
					else:
						var tone: float = rng.randf_range(-0.04, 0.04)
						c = Color(0.3, 0.3, 0.38) if seam else Color(0.5 + tone, 0.5 + tone, 0.58 + tone)
				_:
					if clean:
						# 깔끔한 나무판: 밝은 갈색 면 + 판 사이 한 줄 어두운 선(잡음 없음)
						c = Color(0.62, 0.42, 0.26) if seam else Color(0.84, 0.64, 0.42)
					else:
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

	return normal_from_heights(heights, size, levels)


static func normal_from_heights(heights: Array, size: int, levels: int = 2) -> ImageTexture:
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
# 벽 질감과 3D 부속(덧문·화분·계단)이 같은 창·문 크기를 쓰도록 한 곳에서 계산한다(픽셀 단위).
# 문은 캐릭터(약 24px)보다 확실히 크게(약 1.4배), 창은 한눈에 창으로 읽히게 키웠다.
static func window_layout(w: int, h: int, cells: int) -> Dictionary:
	var cell_px: float = float(w) / float(maxi(cells, 1))
	var dh: int = clampi(int(float(h) * 0.64), 6, 46)
	# 문 폭은 높이의 약 0.46배(현관문 비율 1:2.2). 입방체 건물에서 문이 길쭉해 보이지 않게 칸 폭 안에서 넓힌다.
	var dw: int = clampi(int(float(dh) * 0.46), 8, 18)
	dw = mini(dw, maxi(int(cell_px * 0.7), 6))
	return {
		"base_h": clampi(int(float(h) * 0.16), 2, 6),
		"dw": dw,
		"dh": dh,
		"ww": clampi(int(cell_px * 0.46), 5, 14),
		"wh": clampi(int(float(h) * 0.36), 4, 18),
		"wy": int(float(h) * 0.2),
	}


# 깔끔한 스타일 벽: 평면 회반죽 + 얇은 보 + 밝은 파랑 유리창(흰 틀) + 갈색 문. 잡음·그림자 줄 없음.
static func _wall_facade_clean(w: int, h: int, door: bool, window_count: int, plaster: Color, timber: Color) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var lay: Dictionary = window_layout(w, h, window_count)
	var base_h: int = lay["base_h"]
	var glass := Color(0.5, 0.74, 0.92)
	var frame := Color(0.92, 0.88, 0.8)
	var door_color := Color(0.64, 0.38, 0.22)
	var door_dark := Color(0.4, 0.24, 0.14)
	var stone := Color(0.82, 0.8, 0.76)
	var stone_line := Color(0.66, 0.64, 0.6)

	for y in range(h):
		for x in range(w):
			img.set_pixel(x, y, plaster)

	for y in range(h - base_h, h):
		for x in range(w):
			img.set_pixel(x, y, stone_line if (y == h - base_h or (x % 8 == 0 and (y - (h - base_h)) % 3 != 0)) else stone)

	for x in range(w):
		for y in range(0, 2):
			img.set_pixel(x, y, timber)

	for y in range(h):
		for x in [0, 1, w - 2, w - 1]:
			img.set_pixel(x, y, timber)

	var cells: int = maxi(window_count, 1)
	var door_cell: int = cells / 2 if door else -1

	for k in range(cells):
		var cx: int = int((float(k) + 0.5) * float(w) / float(cells))

		if k == door_cell:
			var dw: int = lay["dw"]
			var dh: int = lay["dh"]
			var x0: int = cx - dw / 2
			var y0: int = h - base_h - dh

			# 문: 어두운 테두리 + 갈색 면 + 위·아래 판(안쪽 한 칸 어둡게) + 위쪽 작은 유리창 + 손잡이, 위에 문 위 틀(상인방)
			for y in range(y0 - 1, h - base_h):
				for x in range(x0 - 1, x0 + dw + 1):
					if x < 0 or x >= w or y < 0:
						continue

					var lintel: bool = y == y0 - 1
					var edge: bool = x == x0 - 1 or x == x0 + dw or y == y0 or lintel
					var inner: bool = x == x0 or x == x0 + dw - 1
					var pane_row: bool = y == y0 + dh / 2
					var upper: bool = y > y0 + 1 and y < y0 + dh / 2 and x > x0 + 1 and x < x0 + dw - 2
					var lower: bool = y > y0 + dh / 2 + 1 and y < h - base_h - 1 and x > x0 + 1 and x < x0 + dw - 2
					var col: Color = door_color

					if edge or lintel:
						col = door_dark
					elif inner or pane_row:
						col = door_dark.lightened(0.1)
					elif upper:
						col = Color(0.78, 0.9, 0.98) if (x + y) % 4 != 0 else Color(0.92, 0.97, 1.0)
					elif lower:
						col = door_color.lightened(0.12)

					img.set_pixel(x, y, col)

			if x0 + dw - 3 < w:
				img.set_pixel(x0 + dw - 3, y0 + dh / 2 + 3, Color(0.98, 0.84, 0.3))
		else:
			var ww: int = lay["ww"]
			var wh: int = lay["wh"]
			var wy: int = lay["wy"]
			var wx0: int = cx - ww / 2

			for y in range(wy, wy + wh):
				for x in range(wx0, wx0 + ww):
					if x >= 0 and x < w and y >= 0 and y < h:
						var edge: bool = x == wx0 or x == wx0 + ww - 1 or y == wy or y == wy + wh - 1
						var bar: bool = x == cx or y == wy + wh / 2
						var shine: bool = (not edge) and (not bar) and (x - wx0) + (y - wy) in [3, 4]
						img.set_pixel(x, y, frame if (edge or bar) else (Color(0.9, 0.97, 1.0) if shine else glass))

			for x in range(wx0 - 1, wx0 + ww + 1):
				if x >= 0 and x < w and wy + wh < h:
					img.set_pixel(x, wy + wh, frame.darkened(0.12))

	return ImageTexture.create_from_image(img)


static func wall_facade(width_texels: int, height_texels: int, door: bool, window_count: int, plaster: Color, timber: Color) -> ImageTexture:
	var w: int = maxi(width_texels, 4)
	var h: int = maxi(height_texels, 4)

	if clean:
		return _wall_facade_clean(w, h, door, window_count, plaster, timber)

	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = w * 131 + h
	var glass := Color(0.45, 0.62, 0.78)
	var door_color := Color(0.5, 0.3, 0.16)

	# 회반죽: 단색 + 드문 어두운 점(무작위 노이즈로 색이 흔들리지 않게)
	for y in range(h):
		for x in range(w):
			var speck: bool = rng.randf() < 0.035
			img.set_pixel(x, y, plaster.darkened(0.08) if speck else plaster)

	# 아래쪽 돌 기단 + 윗 가로 보 + 양 끝 세로 보
	var lay: Dictionary = window_layout(w, h, window_count)
	var base_h: int = lay["base_h"]

	# 돌 기단: 3톤 블록(줄 높이 3px, 어긋난 세로 줄눈)
	for y in range(h - base_h, h):
		var srow: int = (y - (h - base_h)) / 3
		var soff: int = (srow % 2) * 4

		for x in range(w):
			var mortar_row: bool = (y - (h - base_h)) % 3 == 2
			var mortar_col: bool = (x + soff) % 8 == 0
			img.set_pixel(x, y, Color(0.4, 0.39, 0.37) if (mortar_row or mortar_col) else Color(0.6, 0.58, 0.54))

	# 나무 뼈대는 위/왼쪽에 밝은 줄, 아래/오른쪽에 어두운 줄을 둬서 두께가 있어 보이게 한다.
	var beam_hi: Color = timber.lightened(0.28)
	var beam_lo: Color = timber.darkened(0.3)

	for x in range(w):
		for y in range(0, 3):
			img.set_pixel(x, y, beam_hi if y == 0 else (beam_lo if y == 2 else timber))

	for y in range(3, h):
		for k in range(4):
			var bx: int = k if k < 2 else w - 4 + k
			img.set_pixel(bx, y, beam_hi if k == 0 else (beam_lo if k == 3 else timber))

	# 모서리 버팀대(위쪽 안쪽 대각선 4px) — 반목조 느낌
	for k in range(5):
		img.set_pixel(clampi(4 + k, 0, w - 1), clampi(3 + k, 0, h - 1), timber)
		img.set_pixel(clampi(w - 5 - k, 0, w - 1), clampi(3 + k, 0, h - 1), timber)

	# 창문: 가로를 window_count 칸으로 나눠 가운데에 하나씩. 문이 있으면 문 칸은 창문 대신 문.
	var cells: int = maxi(window_count, 1)
	var door_cell: int = cells / 2 if door else -1

	for k in range(cells):
		var cx: int = int((float(k) + 0.5) * float(w) / float(cells))

		if k == door_cell:
			var dw: int = lay["dw"]
			var dh: int = lay["dh"]

			for y in range(h - base_h - dh, h - base_h):
				for x in range(cx - dw / 2, cx - dw / 2 + dw):
					if x >= 0 and x < w and y >= 0:
						img.set_pixel(x, y, door_color if (x != cx - dw / 2 and x != cx - dw / 2 + dw - 1 and y != h - base_h - dh) else timber)

			if cx + 2 < w and h - base_h - dh / 2 >= 0:
				img.set_pixel(cx + dw / 4, h - base_h - dh / 2, Color(0.9, 0.8, 0.3))
		else:
			var ww: int = lay["ww"]
			var wh: int = lay["wh"]
			var wy: int = lay["wy"]

			for y in range(wy, wy + wh):
				for x in range(cx - ww / 2, cx - ww / 2 + ww):
					if x >= 0 and x < w and y >= 0 and y < h:
						var edge: bool = x == cx - ww / 2 or x == cx - ww / 2 + ww - 1 or y == wy or y == wy + wh - 1
						var bar: bool = x == cx or y == wy + wh / 2
						var shine: bool = (not edge) and (not bar) and ((x - (cx - ww / 2)) + (y - wy)) % 7 == 0
						img.set_pixel(x, y, timber if (edge or bar) else (glass.lightened(0.28) if shine else glass))

			# 창턱(창 아래 한 줄 밝은 돌/나무)
			for x in range(cx - ww / 2 - 1, cx - ww / 2 + ww + 1):
				if x >= 0 and x < w and wy + wh < h:
					img.set_pixel(x, wy + wh, beam_hi)

	# 바닥·처마 아래 접지 그림자(환경 가림 근사): 기단 바로 위 2줄과 위쪽 보 아래 3줄을 어둡게
	for x in range(w):
		for k in range(2):
			var y_low: int = h - base_h - 1 - k
			if y_low > 3:
				img.set_pixel(x, y_low, img.get_pixel(x, y_low).darkened(0.16 - 0.06 * k))
		for k in range(3):
			var y_up: int = 3 + k
			if y_up < h:
				img.set_pixel(x, y_up, img.get_pixel(x, y_up).darkened(0.2 - 0.06 * k))

	return ImageTexture.create_from_image(img)


# 기와 지붕 질감: 한 칸(size×size) 반복. 도트 느낌을 위해 **3톤만** 쓴다(윗줄 밝은 하이라이트 / 가운데 기본색 / 아랫줄 어두운 그림자 줄)
# + 기와 사이 세로 틈. 부드러운 그라데이션과 무작위 노이즈는 쓰지 않는다. 기와 폭 = 한 칸의 3분의 1, 줄 높이 = 한 칸의 6분의 1(18 → 6×3).
# 채도를 낮춘 색(형광 느낌 줄이기): 채도 ×scale 후 상한 sat_max, 밝기는 살짝 눌러 눈부심을 막는다. 지붕·천 같은 큰 색 면에 쓴다.
static func soften(c: Color, scale: float = 0.68, sat_max: float = 0.5, val_max: float = 0.9) -> Color:
	var s: float = minf(c.s * scale, sat_max)
	var v: float = minf(c.v, val_max)
	return Color.from_hsv(c.h, s, v, c.a)


static func roof_tiles(size: int, base_in: Color) -> ImageTexture:
	var base: Color = soften(base_in)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)

	if clean:
		# 평면 색 + 기와 줄마다 윗줄 한 픽셀 밝게 / 아랫줄 한 픽셀 어둡게(깔끔한 도트 지붕)
		var rh: int = maxi(size / 3, 2)

		for y in range(size):
			var c: Color = base

			if y % rh == 0:
				c = base.lightened(0.14)
			elif y % rh == rh - 1:
				c = base.darkened(0.2)

			for x in range(size):
				img.set_pixel(x, y, c)

		return ImageTexture.create_from_image(img)

	var tile_w: int = maxi(size / 3, 3)
	var row_h: int = maxi(size / 6, 2)
	var cols: int = maxi(size / tile_w, 1)
	var rows: int = maxi(size / row_h, 1)
	# 손으로 칠한 느낌: 기와 장마다 밝기를 조금씩 다르게(3가지), 채도는 살짝 낮춰 형광 느낌을 줄인다.
	var calm: Color = base.lerp(Color(base.get_luminance(), base.get_luminance(), base.get_luminance()), 0.12)
	var variants: Array = [calm.darkened(0.06), calm, calm.lightened(0.07)]
	var gap: Color = calm.darkened(0.45)

	for y in range(size):
		var row: int = y / row_h
		var ly: int = y % row_h
		var offset: int = (row % 2) * (tile_w / 2)

		for x in range(size):
			var xs: int = x + offset
			var lx: int = xs % tile_w
			var col: int = (xs / tile_w) % cols
			var c: Color = variants[(row * 5 + col * 3 + row / 2) % 3]

			if ly == 0:
				c = c.lightened(0.16)  # 윗줄 하이라이트
			elif ly == row_h - 1:
				c = c.darkened(0.34)  # 아랫줄 그림자(겹친 기와 아래)
			elif lx == 1:
				c = c.lightened(0.1)  # 왼쪽 가장자리 약한 하이라이트

			if lx == 0:
				c = gap if ly > 0 else c.darkened(0.2)  # 기와 사이 틈

			img.set_pixel(x, y, c)

	return ImageTexture.create_from_image(img)


# 기와 지붕 법선 맵: 기와 한 장마다 아래 끝이 불룩하게 겹친 느낌(roof_tiles 와 같은 줄·폭 구조).
static func roof_normal(size: int) -> ImageTexture:
	var tile_w: int = maxi(size / 3, 3)
	var row_h: int = maxi(size / 6, 2)
	var heights: Array = []

	for y in range(size):
		var row_idx: int = y / row_h
		var ly: int = y % row_h
		var offset: int = (row_idx % 2) * (tile_w / 2)
		var row: Array = []

		for x in range(size):
			var lx: int = (x + offset) % tile_w
			var hgt: float = float(ly) / float(maxi(row_h - 1, 1))

			if lx == 0:
				hgt *= 0.4

			row.append(hgt)

		heights.append(row)

	return normal_from_heights(heights, size, 2)


# 차양: 세로 줄무늬(크림 / 주황)
static func awning_stripes(size_in: int, a: Color, b_in: Color) -> ImageTexture:
	var size: int = size_in
	var b: Color = soften(b_in)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var stripe: int = maxi(size / 6, 2)

	for y in range(size):
		for x in range(size):
			img.set_pixel(x, y, a if ((x / stripe) % 2 == 0) else b)

	return ImageTexture.create_from_image(img)


# 빵집 간판(걸이식): 따뜻한 베이지 판에 둥근 빵 한 덩이(칼집 3줄). 16×12 도트 그림 한 장.
static func bread_sign() -> ImageTexture:
	var w: int = 16
	var h: int = 12
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var board := Color(0.93, 0.8, 0.55)
	var frame := Color(0.36, 0.22, 0.12)
	var crust_hi := Color(0.96, 0.72, 0.36)
	var crust := Color(0.82, 0.5, 0.2)
	var crust_lo := Color(0.6, 0.33, 0.13)

	for y in range(h):
		for x in range(w):
			var edge: bool = x == 0 or y == 0 or x == w - 1 or y == h - 1
			img.set_pixel(x, y, frame if edge else board)

	# 둥근 빵(타원): 가운데 (8, 6), 가로 반지름 5.5, 세로 반지름 3.4
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var dx: float = (float(x) - 7.5) / 5.5
			var dy: float = (float(y) - 6.0) / 3.4

			if dx * dx + dy * dy <= 1.0:
				var c: Color = crust
				if dy < -0.35:
					c = crust_hi
				elif dy > 0.45:
					c = crust_lo
				img.set_pixel(x, y, c)

	# 칼집 세 줄(비스듬한 어두운 선)
	for k in range(3):
		var sx: int = 5 + k * 3
		img.set_pixel(sx, 4, crust_lo)
		img.set_pixel(sx + 1, 5, crust_lo)
		img.set_pixel(sx + 1, 6, crust_lo)

	return ImageTexture.create_from_image(img)


# 풀 다발(십자로 세우는 컷아웃용): 투명 배경에 풀잎 몇 가닥. flower 면 끝에 점 하나(분홍/흰). 8×7 도트.
static func grass_tuft(flower: bool) -> ImageTexture:
	var w: int = 8
	var h: int = 7
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var dark := Color(0.3, 0.52, 0.24)
	var mid := Color(0.42, 0.68, 0.32)
	var light := Color(0.6, 0.82, 0.42)
	# 잎 가닥 (x, 높이): 가운데가 가장 높고 양옆이 낮다
	var blades: Array = [[1, 3], [2, 5], [3, 4], [4, 6], [5, 4], [6, 5]]

	for b in blades:
		var bx: int = b[0]
		var bh: int = b[1]

		for k in range(bh):
			var y: int = h - 1 - k
			var c: Color = dark if k == 0 else (mid if k < bh - 1 else light)
			img.set_pixel(bx, y, c)

	if flower:
		img.set_pixel(4, 0, Color(1.0, 0.85, 0.9))
		img.set_pixel(3, 1, Color(0.95, 0.5, 0.65))
		img.set_pixel(5, 1, Color(0.95, 0.5, 0.65))

	return ImageTexture.create_from_image(img)


# 빵집 진열대 윗면(위에서 본 빵 그림): 나무 쟁반 위 바게트 두 줄(뒤) + 둥근 빵 셋(앞). 18×18 중 앞쪽 17×8 칸만 쓴다.
static func bread_counter_top(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var tray := Color(0.86, 0.66, 0.42)
	var tray_dark := Color(0.7, 0.5, 0.3)
	var loaf := Color(0.84, 0.52, 0.2)
	var loaf_hi := Color(0.96, 0.74, 0.4)
	var loaf_lo := Color(0.6, 0.34, 0.13)
	var bag := Color(0.9, 0.66, 0.3)
	var bag_lo := Color(0.68, 0.45, 0.18)

	for y in range(size):
		for x in range(size):
			img.set_pixel(x, y, tray_dark if (x == 0 or y == 0 or y == 8) else tray)

	# 바게트 둘: 뒤쪽(y 1~3), 가로로 긴 타원 + 아랫줄 그늘
	for row in [[1, 2], [3, 4]]:
		for x in range(2, 15):
			img.set_pixel(x, row[0], bag)
			img.set_pixel(x, row[1], bag_lo if row[1] == 4 else bag)
		img.set_pixel(1, row[0], bag_lo)
		img.set_pixel(15, row[0], bag_lo)

	# 둥근 빵 셋: 앞쪽(y 5~7), 지름 4~5
	for cx in [3, 8, 13]:
		for dy in range(-1, 2):
			for dx in range(-2, 3):
				if abs(dx) == 2 and abs(dy) == 1:
					continue
				var c: Color = loaf
				if dy == -1:
					c = loaf_hi
				elif dy == 1:
					c = loaf_lo
				img.set_pixel(cx + dx, 6 + dy, c)

	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------- 빵집(가게) 전용

# 5×7 도트 글꼴(가게 간판용, 영문 대문자 A~Z 와 공백). 한 줄이 5비트.
const FONT_5X7: Dictionary = {
	"A": [0b01110, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001],
	"B": [0b11110, 0b10001, 0b10001, 0b11110, 0b10001, 0b10001, 0b11110],
	"C": [0b01110, 0b10001, 0b10000, 0b10000, 0b10000, 0b10001, 0b01110],
	"D": [0b11110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b11110],
	"E": [0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b11111],
	"F": [0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b10000],
	"G": [0b01110, 0b10001, 0b10000, 0b10111, 0b10001, 0b10001, 0b01111],
	"H": [0b10001, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001],
	"I": [0b01110, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110],
	"J": [0b00111, 0b00010, 0b00010, 0b00010, 0b00010, 0b10010, 0b01100],
	"K": [0b10001, 0b10010, 0b10100, 0b11000, 0b10100, 0b10010, 0b10001],
	"L": [0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b11111],
	"M": [0b10001, 0b11011, 0b10101, 0b10101, 0b10001, 0b10001, 0b10001],
	"N": [0b10001, 0b11001, 0b10101, 0b10011, 0b10001, 0b10001, 0b10001],
	"O": [0b01110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110],
	"P": [0b11110, 0b10001, 0b10001, 0b11110, 0b10000, 0b10000, 0b10000],
	"Q": [0b01110, 0b10001, 0b10001, 0b10001, 0b10101, 0b10010, 0b01101],
	"R": [0b11110, 0b10001, 0b10001, 0b11110, 0b10100, 0b10010, 0b10001],
	"S": [0b01111, 0b10000, 0b10000, 0b01110, 0b00001, 0b00001, 0b11110],
	"T": [0b11111, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100],
	"U": [0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110],
	"V": [0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01010, 0b00100],
	"W": [0b10001, 0b10001, 0b10001, 0b10101, 0b10101, 0b11011, 0b10001],
	"X": [0b10001, 0b10001, 0b01010, 0b00100, 0b01010, 0b10001, 0b10001],
	"Y": [0b10001, 0b10001, 0b01010, 0b00100, 0b00100, 0b00100, 0b00100],
	"Z": [0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b10000, 0b11111],
	" ": [0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000],
}


static func text_len(s: String) -> int:
	return s.length()


static func _draw_text(img: Image, text: String, x0: int, y0: int, color: Color, shadow: Color) -> void:
	var x: int = x0

	for ch in text:
		var rows: Array = FONT_5X7.get(ch, [])

		for ry in range(rows.size()):
			for rx in range(5):
				if (int(rows[ry]) >> (4 - rx)) & 1 == 1:
					var px: int = x + rx
					var py: int = y0 + ry

					if px + 1 < img.get_width() and py + 1 < img.get_height():
						img.set_pixel(px + 1, py + 1, shadow)

		for ry in range(rows.size()):
			for rx in range(5):
				if (int(rows[ry]) >> (4 - rx)) & 1 == 1:
					var qx: int = x + rx
					var qy: int = y0 + ry

					if qx < img.get_width() and qy < img.get_height():
						img.set_pixel(qx, qy, color)

		x += 6


# 가게 앞 가로 간판: 진갈색 판 + 크림색 테두리 + 가운데 "BAKERY" + 양끝 둥근 빵 그림.
static func bakery_fascia(w: int, h: int, text: String = "BAKERY", icon: String = "bread") -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var board := Color(0.5, 0.3, 0.17)
	var rim := Color(0.96, 0.88, 0.68)
	var text_color := Color(1.0, 0.94, 0.78)
	var shade := Color(0.28, 0.15, 0.08)
	var loaf := Color(0.9, 0.58, 0.24)
	var loaf_hi := Color(0.98, 0.78, 0.44)

	for y in range(h):
		for x in range(w):
			var edge: bool = x == 0 or y == 0 or x == w - 1 or y == h - 1
			img.set_pixel(x, y, rim if edge else board)

	var tw: int = text_len(text) * 6 - 1
	var tx: int = (w - tw) / 2
	var ty: int = maxi((h - 7) / 2, 1)
	_draw_text(img, text, tx, ty, text_color, shade)

	# 양끝 그림(7×5): bread = 둥근 빵(위 한 줄 밝게), tool = 망치(손잡이 + 머리), none = 없음
	for side in [0, 1]:
		var bx: int = 4 if side == 0 else w - 11
		var by: int = maxi((h - 5) / 2, 1)

		if icon == "bread":
			for dy in range(5):
				for dx in range(7):
					if (dy == 0 or dy == 4) and (dx == 0 or dx == 6):
						continue

					var c: Color = loaf_hi if dy <= 1 else loaf

					if dx == 0 or dx == 6 or dy == 4:
						c = loaf.darkened(0.25)

					if bx + dx < w - 1 and by + dy < h - 1:
						img.set_pixel(bx + dx, by + dy, c)
		elif icon == "tool":
			var steel := Color(0.78, 0.82, 0.9)
			var handle := Color(0.66, 0.44, 0.24)

			for k in range(5):
				if bx + 1 + k < w - 1 and by + 4 - k < h - 1:
					img.set_pixel(bx + 1 + k, by + 4 - k, handle)

			for dx in range(3):
				for dy in range(2):
					if bx + 3 + dx < w - 1 and by + dy < h - 1:
						img.set_pixel(bx + 3 + dx, by + dy, steel)

	return ImageTexture.create_from_image(img)


# 가게 앞면 벽(빵집): 큰 진열창(선반 두 단 + 빵) 셋과 유리문 하나, 위쪽은 간판 자리(간판은 따로 붙는다).
static func shop_front_wall(w: int, h: int, cells: int, plaster: Color, timber: Color, goods: Color = Color(0.88, 0.56, 0.22)) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var lay: Dictionary = window_layout(w, h, cells)
	var base_h: int = lay["base_h"]
	var cell_px: float = float(w) / float(maxi(cells, 1))
	var door_cell: int = cells / 2
	var glow := Color(1.0, 0.9, 0.66)
	var glow_dark := Color(0.92, 0.76, 0.5)
	var shelf := Color(0.55, 0.34, 0.2)
	var loaf: Color = goods
	var loaf_hi: Color = goods.lightened(0.28)
	var loaf_lo: Color = goods.darkened(0.3)
	var glass := Color(0.7, 0.86, 0.96)
	var stone := Color(0.82, 0.8, 0.76)
	var stone_line := Color(0.66, 0.64, 0.6)
	var win_top: int = int(float(h) * 0.28)
	var win_bot: int = h - base_h - 3

	for y in range(h):
		for x in range(w):
			img.set_pixel(x, y, plaster)

	for y in range(h - base_h, h):
		for x in range(w):
			img.set_pixel(x, y, stone_line if (y == h - base_h or (x % 8 == 0 and (y - (h - base_h)) % 3 != 0)) else stone)

	# 칸 경계 기둥(2px)과 양 끝 기둥
	for k in range(cells + 1):
		var bx: int = clampi(int(float(k) * cell_px) - 1, 0, w - 2)

		for y in range(h):
			img.set_pixel(bx, y, timber)
			img.set_pixel(bx + 1, y, timber)

	for k in range(cells):
		var x0: int = int(float(k) * cell_px) + 3
		var x1: int = int(float(k + 1) * cell_px) - 2

		if k == door_cell:
			# 유리문: 갈색 틀 + 위 유리 + 아래 판 + 손잡이
			var dtop: int = int(float(h) * 0.24)

			for y in range(dtop, h - base_h):
				for x in range(x0, x1):
					var frame: bool = x == x0 or x == x1 - 1 or y == dtop or y == h - base_h - 1
					var upper: bool = y < dtop + int(float(h - base_h - dtop) * 0.62)
					img.set_pixel(x, y, timber if frame else (glow if upper else Color(0.62, 0.38, 0.22)))

			img.set_pixel(x1 - 3, dtop + (h - base_h - dtop) / 2, Color(0.98, 0.84, 0.3))
			continue

		# 진열창: 틀(갈색 1px) 안쪽은 따뜻한 빛, 선반 둘, 선반마다 빵
		for y in range(win_top, win_bot):
			for x in range(x0, x1):
				var edge: bool = x == x0 or x == x1 - 1 or y == win_top or y == win_bot - 1
				img.set_pixel(x, y, timber if edge else (glow if y < (win_top + win_bot) / 2 else glow_dark))

		var shelf_ys: Array = [win_top + (win_bot - win_top) / 3, win_top + (win_bot - win_top) * 2 / 3]

		for sy in shelf_ys:
			for x in range(x0 + 1, x1 - 1):
				img.set_pixel(x, sy, shelf)

			# 선반 위 빵: 4×3 도트 둥근 빵을 6px 간격으로
			var bxx: int = x0 + 3

			while bxx + 4 < x1 - 1:
				for dy in range(3):
					for dx in range(4):
						if dy == 0 and (dx == 0 or dx == 3):
							continue

						var c: Color = loaf_hi if dy == 0 else (loaf_lo if dy == 2 else loaf)
						img.set_pixel(bxx + dx, sy - 3 + dy, c)

				bxx += 6

		# 유리 반사 한 줄
		for k2 in range(3):
			var gx: int = x0 + 2 + k2
			var gy: int = win_top + 1 + k2

			if gx < x1 - 1 and gy < win_bot - 1:
				img.set_pixel(gx, gy, glass)

	return ImageTexture.create_from_image(img)


static func _add_outline(img: Image, color: Color) -> void:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var src: Image = img.duplicate()

	for y in range(h):
		for x in range(w):
			if src.get_pixel(x, y).a > 0.5:
				continue

			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y

				if nx >= 0 and ny >= 0 and nx < w and ny < h and src.get_pixel(nx, ny).a > 0.5:
					img.set_pixel(x, y, color)
					break


# 빵 카드(상자에 꽂는 평면 그림, 투명 배경): "baguette"(세로로 긴 바게트, 칼집) / "loaf"(둥근 빵). 어두운 갈색 윤곽선 포함.
static func bread_card(kind: String) -> ImageTexture:
	var line := Color(0.36, 0.2, 0.1)
	var base := Color(0.9, 0.6, 0.26)
	var hi := Color(0.99, 0.8, 0.46)
	var lo := Color(0.72, 0.43, 0.17)
	var cut := Color(0.6, 0.3, 0.12)
	var img: Image

	if kind == "baguette":
		img = Image.create(7, 18, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))

		for y in range(1, 17):
			var half: float = 2.5 if (y > 2 and y < 15) else 1.5

			for x in range(7):
				var dx: float = float(x) - 3.0

				if absf(dx) <= half:
					var c: Color = base

					if dx < -half + 1.0:
						c = hi
					elif dx > half - 1.0:
						c = lo

					img.set_pixel(x, y, c)

		for y in [5, 9, 13]:
			img.set_pixel(2, y, cut)
			img.set_pixel(3, y, cut)
			img.set_pixel(4, y, cut)
	else:
		img = Image.create(12, 10, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))

		for y in range(1, 9):
			for x in range(1, 11):
				var dx2: float = (float(x) - 5.5) / 4.5
				var dy2: float = (float(y) - 4.5) / 3.5

				if dx2 * dx2 + dy2 * dy2 <= 1.0:
					var c2: Color = base

					if dy2 < -0.35:
						c2 = hi
					elif dy2 > 0.4:
						c2 = lo

					img.set_pixel(x, y, c2)

		for x in [3, 5, 7]:
			img.set_pixel(x, 3, cut)
			img.set_pixel(x + 1, 4, cut)

	_add_outline(img, line)
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------- 대장간·작업장 전용

static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)


# 대장간 앞벽: 푸른 회색 돌벽 + 가운데 큰 아치형 화덕 칸(안쪽 어둡고, 오른쪽에 불꽃·숯, 왼쪽에 모루 그림자) + 양옆 쇠창살 작은 창.
static func forge_front_wall(w: int, h: int, cells: int, stone_tint: Color) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var a: Color = Color(0.64, 0.66, 0.74) * stone_tint
	var b: Color = Color(0.54, 0.56, 0.64) * stone_tint
	var mortar: Color = Color(0.36, 0.37, 0.45)
	var base_h: int = clampi(int(float(h) * 0.12), 2, 5)

	for y in range(h):
		var row: int = y / 4
		var off: int = (row % 2) * 4

		for x in range(w):
			var m: bool = (y % 4 == 0) or ((x + off) % 8 == 0)
			img.set_pixel(x, y, mortar if m else (a if ((x + off) / 8 + row) % 2 == 0 else b))

	# 화덕 칸(아치): 가운데 폭 약 44%
	var bw: int = int(float(w) * 0.44)
	var bx0: int = (w - bw) / 2
	var bx1: int = bx0 + bw
	var by0: int = int(float(h) * 0.2)
	var by1: int = h
	var frame := Color(0.8, 0.8, 0.88)

	for y in range(by0, by1):
		for x in range(bx0 - 2, bx1 + 2):
			var corner: bool = (y - by0) < 2 and (x - (bx0 - 2) < 2 or (bx1 + 1) - x < 2)
			if not corner:
				_px(img, x, y, frame)

	for y in range(by0 + 2, by1):
		for x in range(bx0, bx1):
			var corner2: bool = (y - by0 - 2) < 2 and (x - bx0 < 2 or (bx1 - 1) - x < 2)
			if not corner2:
				_px(img, x, y, Color(0.13, 0.1, 0.1))

	# 바닥 따뜻한 반사(화덕 앞)
	for x in range(bx0 + 2, bx1 - 2):
		_px(img, x, h - 2, Color(0.42, 0.2, 0.1))
		_px(img, x, h - 1, Color(0.3, 0.14, 0.08))

	# 불꽃·숯(오른쪽): 숯 줄 + 불꽃 두 겹
	var fx: int = bx1 - 10
	for dx in range(8):
		_px(img, fx + dx, h - 4, Color(0.85, 0.22, 0.08))
		_px(img, fx + dx, h - 3, Color(0.6, 0.12, 0.06))

	for dx in range(2, 7):
		_px(img, fx + dx, h - 5, Color(1.0, 0.55, 0.15))
		_px(img, fx + dx, h - 6, Color(1.0, 0.55, 0.15))

	for dx in range(3, 6):
		_px(img, fx + dx, h - 7, Color(1.0, 0.85, 0.3))
		_px(img, fx + dx, h - 8, Color(1.0, 0.85, 0.3))

	_px(img, fx + 4, h - 9, Color(1.0, 0.9, 0.5))

	# 모루 그림자(왼쪽): 받침 + 허리 + 윗판(뿔 포함)
	var ax: int = bx0 + 5
	var shade := Color(0.34, 0.36, 0.46)

	for dx in range(0, 8):
		_px(img, ax + dx, h - 3, shade)
		_px(img, ax + dx, h - 2, shade)

	for dx in range(2, 6):
		_px(img, ax + dx, h - 4, shade)
		_px(img, ax + dx, h - 5, shade)

	for dx in range(-1, 10):
		_px(img, ax + dx, h - 6, Color(0.5, 0.52, 0.62))
		_px(img, ax + dx, h - 7, shade)

	_px(img, ax - 2, h - 6, shade)

	# 양옆 작은 쇠창살 창
	for k in range(cells):
		var cx: int = int((float(k) + 0.5) * float(w) / float(cells))

		if cx > bx0 - 4 and cx < bx1 + 4:
			continue

		for y in range(int(float(h) * 0.3), int(float(h) * 0.3) + 8):
			for x in range(cx - 3, cx + 3):
				var edge: bool = x == cx - 3 or x == cx + 2 or y == int(float(h) * 0.3) or y == int(float(h) * 0.3) + 7
				var bar: bool = x == cx - 1 or x == cx
				_px(img, x, y, frame if edge else (Color(0.2, 0.2, 0.26) if bar else Color(0.1, 0.1, 0.14)))

	for y in range(h - base_h, h):
		for x in range(w):
			if x < bx0 - 2 or x >= bx1 + 2:
				_px(img, x, y, Color(0.4, 0.41, 0.48) if (y == h - base_h) else Color(0.46, 0.47, 0.55))

	return ImageTexture.create_from_image(img)


static func _draw_tool(img: Image, kind: String, x: int, y: int) -> void:
	var steel := Color(0.78, 0.82, 0.9)
	var steel_dk := Color(0.5, 0.54, 0.64)
	var wood := Color(0.66, 0.44, 0.24)

	match kind:
		"pick":
			for k in range(10):
				_px(img, x + 4, y + k, wood)

			for dx in range(0, 9):
				_px(img, x + dx, y + 1, steel)

			_px(img, x, y + 2, steel_dk)
			_px(img, x + 8, y + 2, steel_dk)
		"saw":
			for k in range(6):
				for dx in range(1, 6 - k / 2):
					_px(img, x + dx, y + k, steel)

			for k in range(6):
				_px(img, x, y + k, steel_dk if k % 2 == 0 else steel)

			for k in range(6, 10):
				_px(img, x + 2, y + k, wood)
				_px(img, x + 3, y + k, wood)
		"shovel":
			for k in range(7):
				_px(img, x + 3, y + k, wood)

			for dy in range(6, 10):
				for dx in range(1, 6):
					if not (dy == 9 and (dx == 1 or dx == 5)):
						_px(img, x + dx, y + dy, steel)
		_:
			for k in range(10):
				_px(img, x + 3, y + k, wood)

			for dx in range(0, 7):
				for dy in range(0, 3):
					_px(img, x + dx, y + dy, steel if dy < 2 else steel_dk)


# 작업장(도구 가게) 앞벽: 세로 널판 벽 + 가운데 큰 쌍여닫이문(X 보강) + 양옆 판에 걸린 도구(곡괭이·톱·삽·망치).
static func workshop_front_wall(w: int, h: int, cells: int, wood_tint: Color) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var pa: Color = Color(0.82, 0.6, 0.38) * wood_tint
	var pb: Color = Color(0.74, 0.53, 0.33) * wood_tint
	var seam: Color = Color(0.46, 0.3, 0.17)
	var trim := Color(0.28, 0.5, 0.45)
	var base_h: int = clampi(int(float(h) * 0.1), 2, 4)

	for y in range(h):
		for x in range(w):
			var c: Color = seam if x % 4 == 0 else (pa if (x / 4) % 2 == 0 else pb)
			img.set_pixel(x, y, c)

	for x in range(w):
		for y in range(0, 2):
			img.set_pixel(x, y, trim)

	for y in range(h):
		for x in [0, 1, w - 2, w - 1]:
			img.set_pixel(x, y, trim)

	var door_cell: int = cells / 2
	var cell_px: float = float(w) / float(maxi(cells, 1))
	var dw: int = int(cell_px * 0.8)
	var dh: int = int(float(h) * 0.72)
	var dcx: int = int((float(door_cell) + 0.5) * cell_px)
	var dx0: int = dcx - dw / 2
	var dy0: int = h - base_h - dh
	var door := Color(0.5, 0.33, 0.18)
	var door_dk := Color(0.3, 0.19, 0.1)

	for y in range(dy0, h - base_h):
		for x in range(dx0, dx0 + dw):
			var edge: bool = x == dx0 or x == dx0 + dw - 1 or y == dy0 or x == dcx
			_px(img, x, y, door_dk if edge else door)

	# 쌍여닫이문 X 보강
	for half in range(2):
		var hx0: int = dx0 + half * (dw / 2)
		var hwid: int = dw / 2

		for k in range(hwid):
			var yy: int = dy0 + 2 + int(float(k) * float(dh - 4) / float(maxi(hwid, 1)))
			_px(img, hx0 + k, yy, door_dk)
			_px(img, hx0 + hwid - 1 - k, yy, door_dk)

	_px(img, dcx - 2, dy0 + dh / 2, Color(0.95, 0.82, 0.3))
	_px(img, dcx + 1, dy0 + dh / 2, Color(0.95, 0.82, 0.3))

	# 양옆 도구 걸이판: 어두운 판 위에 도구 둘씩
	var kinds_left: Array = ["pick", "saw"]
	var kinds_right: Array = ["shovel", "hammer"]

	for k in range(cells):
		if k == door_cell:
			continue

		var cx: int = int((float(k) + 0.5) * cell_px)
		var board_w: int = clampi(int(cell_px * 0.7), 10, 24)
		var bx: int = cx - board_w / 2
		var by: int = int(float(h) * 0.3)

		for y in range(by, by + 14):
			for x in range(bx, bx + board_w):
				_px(img, x, y, Color(0.34, 0.22, 0.13) if (x == bx or x == bx + board_w - 1 or y == by or y == by + 13) else Color(0.55, 0.37, 0.22))

		var kinds: Array = kinds_left if k < door_cell else kinds_right
		_draw_tool(img, kinds[0], bx + 2, by + 2)

		if board_w >= 18:
			_draw_tool(img, kinds[1], bx + board_w - 10, by + 2)

	for y in range(h - base_h, h):
		for x in range(w):
			_px(img, x, y, Color(0.56, 0.54, 0.5))

	return ImageTexture.create_from_image(img)


# 걸이 간판용 그림(16×12): 모루(대장간) / 곡괭이+망치(도구 가게)
static func icon_sign(kind: String) -> ImageTexture:
	var img := Image.create(16, 12, false, Image.FORMAT_RGBA8)
	var board := Color(0.86, 0.8, 0.7)
	var frame := Color(0.3, 0.2, 0.12)

	for y in range(12):
		for x in range(16):
			img.set_pixel(x, y, frame if (x == 0 or y == 0 or x == 15 or y == 11) else board)

	var dark := Color(0.2, 0.2, 0.26)
	var mid := Color(0.45, 0.47, 0.56)

	if kind == "anvil":
		for dx in range(3, 13):
			_px(img, dx, 3, mid)
			_px(img, dx, 4, dark)

		for dx in range(1, 4):
			_px(img, dx, 3, mid)

		for dx in range(6, 10):
			for dy in range(5, 8):
				_px(img, dx, dy, dark)

		for dx in range(4, 12):
			_px(img, dx, 8, dark)
			_px(img, dx, 9, dark)
	else:
		_draw_tool(img, "pick", 2, 1)
		_draw_tool(img, "hammer", 9, 1)

	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------- 가판대 상품 카드(투명 컷아웃, 어두운 윤곽선)

# 종류: apple orange lemon grape fish ham bottle(색 지정) flower(색 지정) jar book cloth(색 지정) herb loaf baguette
static func goods_card(kind: String, color: Color = Color(0.85, 0.25, 0.25)) -> ImageTexture:
	if kind == "loaf" or kind == "baguette":
		return bread_card(kind)

	var line := Color(0.3, 0.18, 0.1)
	var img := Image.create(10, 10, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	match kind:
		"apple", "orange", "lemon":
			var base: Color = {"apple": Color(0.86, 0.2, 0.2), "orange": Color(0.96, 0.6, 0.15), "lemon": Color(0.98, 0.86, 0.25)}[kind]

			for y in range(2, 9):
				for x in range(1, 9):
					var dx: float = (float(x) - 4.5) / 3.7
					var dy: float = (float(y) - 5.5) / 3.3

					if dx * dx + dy * dy <= 1.0:
						img.set_pixel(x, y, base.lightened(0.25) if (dx < -0.1 and dy < -0.1) else (base.darkened(0.18) if dy > 0.4 else base))

			_px(img, 4, 1, Color(0.3, 0.6, 0.25))
			_px(img, 5, 1, Color(0.3, 0.6, 0.25))
		"grape":
			var g := Color(0.5, 0.25, 0.65)

			for row in range(4):
				for k in range(4 - row):
					var gx: int = 2 + row + k * 2
					_px(img, gx, 2 + row * 2, g.lightened(0.2))
					_px(img, gx + 1, 2 + row * 2, g)
					_px(img, gx, 3 + row * 2, g)
					_px(img, gx + 1, 3 + row * 2, g.darkened(0.2))

			_px(img, 4, 1, Color(0.3, 0.55, 0.25))
		"fish":
			var body := Color(0.55, 0.7, 0.85)

			for y in range(3, 8):
				for x in range(1, 8):
					var dx2: float = (float(x) - 4.0) / 3.6
					var dy2: float = (float(y) - 5.0) / 2.2

					if dx2 * dx2 + dy2 * dy2 <= 1.0:
						img.set_pixel(x, y, body.lightened(0.25) if y < 5 else body)

			for k in range(3):
				_px(img, 8, 4 + k - (k % 2), body.darkened(0.15))
				_px(img, 9, 3 + k * 2 - (k % 2) * 0, body.darkened(0.15))

			_px(img, 2, 4, Color(0.1, 0.1, 0.15))
		"ham":
			var meat := Color(0.82, 0.33, 0.33)

			for y in range(2, 9):
				for x in range(1, 8):
					var dx3: float = (float(x) - 4.0) / 3.4
					var dy3: float = (float(y) - 5.5) / 3.2

					if dx3 * dx3 + dy3 * dy3 <= 1.0:
						img.set_pixel(x, y, meat.lightened(0.2) if dy3 < -0.2 else (meat.darkened(0.2) if dy3 > 0.4 else meat))

			_px(img, 8, 5, Color(0.95, 0.9, 0.8))
			_px(img, 9, 5, Color(0.95, 0.9, 0.8))
			_px(img, 9, 4, Color(0.95, 0.9, 0.8))
			_px(img, 9, 6, Color(0.95, 0.9, 0.8))
		"bottle":
			for y in range(4, 9):
				for x in range(3, 7):
					img.set_pixel(x, y, color.lightened(0.2) if x == 3 else (color.darkened(0.2) if x == 6 else color))

			for y in range(1, 4):
				_px(img, 4, y, Color(0.8, 0.85, 0.9))
				_px(img, 5, y, Color(0.8, 0.85, 0.9))

			_px(img, 4, 1, Color(0.55, 0.35, 0.2))
			_px(img, 5, 1, Color(0.55, 0.35, 0.2))
		"flower":
			var leaf := Color(0.3, 0.6, 0.28)

			for y in range(5, 10):
				_px(img, 4, y, leaf)

			_px(img, 3, 7, leaf)
			_px(img, 5, 6, leaf)

			for c in [Vector2i(3, 2), Vector2i(5, 2), Vector2i(4, 1), Vector2i(4, 3), Vector2i(4, 2)]:
				_px(img, c.x, c.y, color.lightened(0.15) if c.x == 4 and c.y == 2 else color)

			_px(img, 4, 2, Color(1.0, 0.9, 0.4))
		"jar":
			var clay := Color(0.72, 0.42, 0.25)

			for y in range(3, 9):
				var half: int = 3 if (y > 3 and y < 8) else 2

				for x in range(5 - half, 5 + half):
					img.set_pixel(x, y, clay.lightened(0.18) if x == 5 - half else (clay.darkened(0.2) if x == 4 + half else clay))

			for x in range(3, 7):
				_px(img, x, 2, clay.darkened(0.3))
		"book":
			var cover: Color = color

			for y in range(1, 9):
				for x in range(2, 8):
					img.set_pixel(x, y, cover.lightened(0.15) if x == 2 else cover)

			for y in range(2, 8):
				_px(img, 7, y, Color(0.95, 0.92, 0.8))

			for x in range(3, 6):
				_px(img, x, 3, Color(0.95, 0.85, 0.4))
		"cloth":
			for y in range(2, 9):
				for x in range(1, 9):
					var stripe: bool = (x + y / 2) % 3 == 0
					img.set_pixel(x, y, color.lightened(0.3) if stripe else color)

			for x in range(1, 9):
				_px(img, x, 2, color.darkened(0.2))
				_px(img, x, 8, color.darkened(0.25))
		_:
			# herb: 풀 다발
			var gr := Color(0.35, 0.65, 0.3)

			for k in range(4):
				for y in range(2 + (k % 2), 9):
					_px(img, 2 + k * 2, y, gr.lightened(0.15) if y < 4 else gr)

			_px(img, 3, 8, Color(0.7, 0.5, 0.3))
			_px(img, 4, 8, Color(0.7, 0.5, 0.3))

	_add_outline(img, line)
	return ImageTexture.create_from_image(img)


# 덩굴 카드(벽에 붙임, 투명 배경): 위에서 아래로 늘어진 잎 덩어리 + 군데군데 분홍·흰 꽃. 14×16.
static func vine_card() -> ImageTexture:
	var img := Image.create(14, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var greens: Array = [Color(0.3, 0.52, 0.26), Color(0.42, 0.66, 0.34), Color(0.56, 0.78, 0.42)]

	for y in range(16):
		for x in range(14):
			var edge: float = absf(float(x) - 6.5) / 6.5
			var chance: float = 0.78 - edge * 0.5 - float(y) / 40.0

			if rng.randf() < chance:
				img.set_pixel(x, y, greens[rng.randi() % 3])

	for k in range(5):
		var fx: int = rng.randi_range(1, 12)
		var fy: int = rng.randi_range(1, 13)
		img.set_pixel(fx, fy, Color(1.0, 0.82, 0.88) if k % 2 == 0 else Color(0.96, 0.55, 0.7))

	_add_outline(img, Color(0.18, 0.3, 0.14))
	return ImageTexture.create_from_image(img)


# 풍차 날개(투명 배경 컷아웃): 십자 뼈대 + 네 날개 격자. 24×24.
static func windmill_blades() -> ImageTexture:
	var img := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var wood := Color(0.55, 0.38, 0.22)
	var wood_dk := Color(0.36, 0.24, 0.14)
	var cloth := Color(0.96, 0.92, 0.82)
	var cloth_dk := Color(0.82, 0.76, 0.64)

	# 날개 네 개: 가운데에서 뻗는 폭 5 의 격자 판(뼈대 선 + 천)
	for arm in range(4):
		for d in range(3, 12):
			for w in range(-3, 4):
				var x: int
				var y: int

				match arm:
					0:
						x = 12 + w
						y = 12 - d
					1:
						x = 12 + d
						y = 12 + w
					2:
						x = 12 + w
						y = 12 + d
					_:
						x = 12 - d
						y = 12 - w

				var edge: bool = absi(w) == 3 or d == 11
				var bar: bool = (d % 3 == 0)
				_px(img, x, y, wood_dk if edge else (wood if bar else (cloth if (w + d) % 2 == 0 else cloth_dk)))

	# 중심 축
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			if absi(dx) + absi(dy) <= 3:
				_px(img, 12 + dx, 12 + dy, wood_dk if (absi(dx) == 2 or absi(dy) == 2) else wood)

	return ImageTexture.create_from_image(img)


# 헛간(곳간) 앞벽: 세로 널판(붉은 갈색) + 큰 쌍여닫이문(흰 틀, X 보강) + 위쪽 건초 다락 문.
static func barn_front_wall(w: int, h: int, cells: int, tint: Color) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var pa: Color = soften(Color(0.72, 0.36, 0.28)) * tint
	var pb: Color = pa.darkened(0.1)
	var seam: Color = pa.darkened(0.4)
	var white := Color(0.95, 0.92, 0.84)
	var base_h: int = clampi(int(float(h) * 0.08), 2, 4)

	for y in range(h):
		for x in range(w):
			img.set_pixel(x, y, seam if x % 4 == 0 else (pa if (x / 4) % 2 == 0 else pb))

	var dw: int = int(float(w) * 0.5)
	var dh: int = int(float(h) * 0.55)
	var dcx: int = w / 2
	var dx0: int = dcx - dw / 2
	var dy0: int = h - base_h - dh

	for y in range(dy0, h - base_h):
		for x in range(dx0, dx0 + dw):
			var edge: bool = x == dx0 or x == dx0 + dw - 1 or y == dy0 or x == dcx or x == dcx - 1
			_px(img, x, y, white if edge else pa.darkened(0.08))

	for half in range(2):
		var hx0: int = dx0 + half * (dw / 2)
		var hwid: int = dw / 2

		for k in range(hwid):
			var yy: int = dy0 + 1 + int(float(k) * float(dh - 2) / float(maxi(hwid, 1)))
			_px(img, hx0 + k, yy, white)
			_px(img, hx0 + hwid - 1 - k, yy, white)

	# 건초 다락 문(위쪽 가운데): 흰 틀 + 노란 건초
	var lw: int = int(float(w) * 0.24)
	var lh: int = int(float(h) * 0.2)
	var lx0: int = dcx - lw / 2
	var ly0: int = int(float(h) * 0.12)

	for y in range(ly0, ly0 + lh):
		for x in range(lx0, lx0 + lw):
			var ledge: bool = x == lx0 or x == lx0 + lw - 1 or y == ly0 or y == ly0 + lh - 1
			_px(img, x, y, white if ledge else (Color(0.86, 0.72, 0.3) if (x + y) % 3 != 0 else Color(0.7, 0.55, 0.2)))

	for y in range(h - base_h, h):
		for x in range(w):
			_px(img, x, y, Color(0.5, 0.48, 0.44))

	return ImageTexture.create_from_image(img)


# 마구간 앞벽: 가로 널판 + 칸마다 위가 열린 반문(말 머리가 내다봄) + 아래는 닫힌 널판.
static func stable_front_wall(w: int, h: int, cells: int, tint: Color) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var pa: Color = Color(0.74, 0.56, 0.36) * tint
	var seam: Color = pa.darkened(0.35)
	var trim := Color(0.95, 0.92, 0.84)
	var base_h: int = clampi(int(float(h) * 0.1), 2, 4)

	for y in range(h):
		for x in range(w):
			img.set_pixel(x, y, seam if y % 4 == 0 else (pa if (y / 4) % 2 == 0 else pa.darkened(0.06)))

	var n: int = maxi(cells, 2)
	var cell_px: float = float(w) / float(n)

	for k in range(n):
		var x0: int = int(float(k) * cell_px) + 3
		var x1: int = int(float(k + 1) * cell_px) - 3
		var top: int = int(float(h) * 0.26)
		var bot: int = h - base_h
		var mid: int = top + (bot - top) / 2

		# 위쪽 열린 부분(어두운 안쪽) + 말 머리
		for y in range(top, mid):
			for x in range(x0, x1):
				var edge: bool = x == x0 or x == x1 - 1 or y == top
				_px(img, x, y, trim if edge else Color(0.16, 0.12, 0.1))

		var hx: int = (x0 + x1) / 2 - 3
		var brown := Color(0.5, 0.32, 0.18)
		var mane := Color(0.28, 0.16, 0.1)

		for dy in range(0, 6):
			for dx in range(0, 6):
				if dy < 2 and dx > 3:
					continue

				_px(img, hx + dx, mid - 7 + dy, brown if dx > 0 else mane)

		_px(img, hx + 5, mid - 3, Color(0.95, 0.9, 0.8))
		_px(img, hx + 1, mid - 6, Color(0.1, 0.08, 0.08))
		_px(img, hx, mid - 5, mane)
		_px(img, hx, mid - 4, mane)

		# 아래쪽 닫힌 판
		for y in range(mid, bot):
			for x in range(x0, x1):
				var edge2: bool = x == x0 or x == x1 - 1 or y == mid or y == bot - 1
				var brace: bool = (x - x0) == (y - mid) * (x1 - x0) / maxi(bot - mid, 1)
				_px(img, x, y, trim if edge2 else (trim.darkened(0.25) if brace else pa.lightened(0.05)))

	for y in range(h - base_h, h):
		for x in range(w):
			_px(img, x, y, Color(0.5, 0.48, 0.44))

	return ImageTexture.create_from_image(img)


# 덧문(겉창): 가로 살(루버) 줄무늬. 밝은 줄과 어두운 줄이 두 픽셀씩 번갈아.
static func shutter(size: int, base: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)

	for y in range(size):
		for x in range(size):
			var c: Color = base.lightened(0.12) if (y / 2) % 2 == 0 else base.darkened(0.12)
			if x == 0 or x == size - 1:
				c = base.darkened(0.35)
			img.set_pixel(x, y, c)

	return ImageTexture.create_from_image(img)


# 단색 한 장(지붕 두께·용마루 덮개 등). 살짝 결을 준다.
static func flat_color(size: int, base: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(base.r * 255.0) * 7919 + int(base.g * 255.0)

	for y in range(size):
		for x in range(size):
			var v: float = rng.randf_range(-0.03, 0.03)
			img.set_pixel(x, y, Color(base.r + v, base.g + v, base.b + v))

	return ImageTexture.create_from_image(img)


# 나무 상자: 판자 + 가로 보강대 + 모서리 테두리
static func crate(size: int, base: Color = Color(0.62, 0.45, 0.27)) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242

	for y in range(size):
		for x in range(size):
			var v: float = rng.randf_range(-0.03, 0.03)
			var c := Color(base.r + v, base.g + v, base.b + v)
			var frame: bool = x < 2 or y < 2 or x >= size - 2 or y >= size - 2
			var band: bool = absi(x - y) < 2 or absi(x - (size - 1 - y)) < 2
			img.set_pixel(x, y, base.darkened(0.38) if (frame or band) else (base.darkened(0.15) if (y % 6 == 0) else c))

	return ImageTexture.create_from_image(img)


# 통(배럴): 세로 판자 + 쇠테 두 줄
static func barrel(size: int, base: Color = Color(0.55, 0.36, 0.2)) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)

	for y in range(size):
		for x in range(size):
			var hoop: bool = (y >= size / 5 and y < size / 5 + 2) or (y >= size * 4 / 5 - 2 and y < size * 4 / 5)
			var seam: bool = x % 5 == 0
			img.set_pixel(x, y, Color(0.3, 0.3, 0.34) if hoop else (base.darkened(0.3) if seam else base))

	return ImageTexture.create_from_image(img)


# 덤불/잎: 짙은 초록 + 밝은 점, flower 가 있으면 꽃 점
static func foliage(size: int, base: Color, flower: Color = Color(0, 0, 0, 0)) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(base.g * 1000.0) + 17

	for y in range(size):
		for x in range(size):
			var v: float = rng.randf_range(-0.07, 0.07)
			var c := Color(base.r + v, base.g + v, base.b + v)

			if rng.randf() < 0.1:
				c = base.lightened(0.25)

			if flower.a > 0.0 and rng.randf() < 0.08:
				c = flower

			img.set_pixel(x, y, c)

	return ImageTexture.create_from_image(img)


# 돌(낮은 담·우물): 회색 블록 줄눈
static func stone(size: int, base: Color = Color(0.58, 0.56, 0.52)) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)

	if clean:
		var rh: int = maxi(size / 3, 2)
		var lit: Color = base.lightened(0.18)

		for y in range(size):
			for x in range(size):
				var mortar: bool = (y % rh == 0) or ((x + (y / rh % 2) * (size / 4)) % (size / 2) == 0)
				img.set_pixel(x, y, base.darkened(0.22) if mortar else lit)

		return ImageTexture.create_from_image(img)

	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	var row_h: int = maxi(size / 3, 2)

	for y in range(size):
		var row: int = y / row_h
		var offset: int = (row % 2) * (size / 4)

		for x in range(size):
			var v: float = rng.randf_range(-0.05, 0.05)
			var mortar: bool = (y % row_h == 0) or ((x + offset) % (size / 2) == 0)
			img.set_pixel(x, y, base.darkened(0.35) if mortar else Color(base.r + v, base.g + v, base.b + v))

	return ImageTexture.create_from_image(img)


# 게시판 종이/공지: 코르크 바탕에 종이 쪽지 몇 장
static func notice_board(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)

	for y in range(size):
		for x in range(size):
			var paper: bool = (x > 2 and x < size / 2 - 1 and y > 2 and y < size / 2) or (x > size / 2 + 1 and x < size - 3 and y > size / 3 and y < size - 3) or (x > 3 and x < size / 2 and y > size / 2 + 2 and y < size - 3)
			img.set_pixel(x, y, Color(0.93, 0.88, 0.7) if paper else Color(0.55, 0.38, 0.22))

	return ImageTexture.create_from_image(img)


# 간판/표지판: 나무 판 + 테두리 + 흰 화살표
static func sign_board(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)

	for y in range(size):
		for x in range(size):
			var border: bool = x < 2 or y < 2 or x >= size - 2 or y >= size - 2
			var arrow: bool = absi(y - size / 2) <= maxi(1, (size - x) / 6) and x > size / 5 and x < size * 4 / 5
			img.set_pixel(x, y, Color(0.3, 0.2, 0.12) if border else (Color(0.95, 0.92, 0.85) if arrow else Color(0.6, 0.42, 0.26)))

	return ImageTexture.create_from_image(img)
