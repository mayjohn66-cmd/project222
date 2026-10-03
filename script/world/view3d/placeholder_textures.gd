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
						c = Color(0.56, 0.74, 0.42) if dot else Color(0.48, 0.68, 0.36)
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
	return {
		"base_h": clampi(int(float(h) * 0.16), 2, 6),
		"dw": clampi(int(cell_px * 0.5), 5, 16),
		"dh": clampi(int(float(h) * 0.66), 6, 46),
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

			for y in range(y0, h - base_h):
				for x in range(x0, x0 + dw):
					if x >= 0 and x < w and y >= 0:
						var edge: bool = x == x0 or x == x0 + dw - 1 or y == y0
						var panel: bool = y == y0 + dh / 2 or x == cx
						img.set_pixel(x, y, door_dark if (edge or panel) else door_color)

			if cx + dw / 4 < w:
				img.set_pixel(cx + dw / 4, h - base_h - dh / 2 + 2, Color(0.98, 0.84, 0.3))
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
static func roof_tiles(size: int, base: Color) -> ImageTexture:
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
static func awning_stripes(size: int, a: Color, b: Color) -> ImageTexture:
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
