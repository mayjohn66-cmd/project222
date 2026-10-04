class_name ShelfAssets
extends RefCounted
## 진열대 3D 모델: 나무 틀(옆판·뒷판·선반 판)과 선반에 놓인 상품. 상품은 아이템마다 모양(빵, 병, 플라스크, 그릇, 광석 …)이 있고
## 색은 아이콘 평균색에서 뽑는다. 모양 지정은 data/shop/catalogs/item_3d.csv, 칸 수·재고는 진열대 노드(slots)에서 읽는다.
## 좌표는 (u = 진열대 길이 방향, v = 뒤→앞 방향, y = 높이)로 정하고 회전에 맞춰 칸 좌표(x, z)로 옮긴다.

const SHAPES_PATH: String = "res://data/shop/catalogs/item_3d.csv"
const DEPTH: float = 0.5
const FIRST_LEVEL_H: float = 1.4
const STACK_LEVEL_H: float = 1.0
const MAX_VISIBLE: int = 5
const GOODS_SCALE: float = 1.45  # 3D 화면(낮은 해상도)에서 알아볼 수 있게 상품을 실제 비율보다 크게
## 모양별 높이(크기 배율 1 기준). 선반 사이 여유보다 높으면 배율을 줄여 윗판을 뚫지 않게 한다.
const SHAPE_HEIGHT: Dictionary = {"loaf": 0.15, "bottle": 0.37, "flask": 0.33, "bowl": 0.095, "jar": 0.19, "rocks": 0.1, "crystal": 0.2, "bundle": 0.24, "mushroom": 0.17, "orb": 0.09, "scroll": 0.2, "lantern": 0.2, "box": 0.12, "disc": 0.04}
const HEADROOM: float = 0.94  # 위 판과의 사이를 조금 남긴다

static var _shapes: Dictionary = {}
static var _loaded: bool = false
static var _colors: Dictionary = {}


static func _load() -> void:
	_loaded = true
	_shapes.clear()
	var file := FileAccess.open(SHAPES_PATH, FileAccess.READ)

	if file == null:
		push_warning("[ShelfAssets] 파일 없음: " + SHAPES_PATH)
		return

	var header: PackedStringArray = file.get_csv_line()

	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()

		if row.size() < 2 or row[0].strip_edges().is_empty():
			continue

		var entry: Dictionary = {}

		for i in range(mini(header.size(), row.size())):
			entry[header[i]] = row[i].strip_edges()

		_shapes[str(entry["item_id"])] = entry


static func shape_of(item_id: String) -> String:
	if not _loaded:
		_load()

	return str((_shapes.get(item_id, {}) as Dictionary).get("shape", "jar"))


# 아이콘의 불투명한 부분 평균색(조금 진하게). 읽지 못하면 CSV 의 color, 그것도 없으면 회갈색.
static func item_color(item_id: String) -> Color:
	if _colors.has(item_id):
		return _colors[item_id]

	if not _loaded:
		_load()

	var fallback := Color(0.62, 0.55, 0.45)
	var entry: Dictionary = _shapes.get(item_id, {})

	if str(entry.get("color", "")) != "":
		fallback = Color(str(entry["color"]))

	var out: Color = fallback
	var icon = ItemData.get_item_icon(item_id)

	if icon is Texture2D:
		var img: Image = (icon as Texture2D).get_image()

		if img != null and not img.is_empty():
			if img.is_compressed():
				img.decompress()

			var sum := Vector3.ZERO
			var n: int = 0
			var step: int = maxi(1, img.get_width() / 24)

			for y in range(0, img.get_height(), step):
				for x in range(0, img.get_width(), step):
					var c: Color = img.get_pixel(x, y)

					if c.a > 0.6:
						sum += Vector3(c.r, c.g, c.b)
						n += 1

			if n > 0:
				var avg := Color(sum.x / n, sum.y / n, sum.z / n)
				out = avg.lerp(Color.WHITE, 0.0)
				out.s = clampf(out.s * 1.15, 0.0, 1.0)

	_colors[item_id] = out
	return out


# 진열대 한 대의 메시. lo/hi 는 3D 발자국(depth 반영, 칸 좌표), rotation 은 앞쪽 방향(0=+z, 1=+x, 2=-z, 3=-x).
# slots = [{item_id, stock, capacity}], slots_per_level = 한 층의 칸 수. 반환: {mesh, specs, total_blocks, lo, hi}
static func build(lo: Vector2, hi: Vector2, rotation: int, stack: int, slots: Array, slots_per_level: int, p: Dictionary) -> Dictionary:
	var b := VillageAssets.PartBuilder.new()
	var rot: int = posmod(rotation, 4)
	var along_x: bool = rot == 0 or rot == 2
	var length: float = (hi.x - lo.x) if along_x else (hi.y - lo.y)
	var depth: float = (hi.y - lo.y) if along_x else (hi.x - lo.x)
	var materials := FurnitureVariantAssets.shelf_materials(p)
	var wood_frame: Dictionary = materials[0]
	var wood_back: Dictionary = materials[1]
	var wood_board: Dictionary = materials[2]
	var stage := str(p.get("furniture_stage", ""))
	var ts: int = int(p["ts"])
	# 부품(면)은 재질 이름 하나당 하나만 만든다.
	var parts: Dictionary = {}

	var part := func(spec: Dictionary) -> SurfaceTool:
		var key: String = str(spec["name"])

		if not parts.has(key):
			parts[key] = b.new_part(spec, Vector3(lo.x, 0.0, lo.y), Vector3(hi.x, 2.0, hi.y))

		return parts[key]

	# (u, v, y) 상자를 칸 좌표로 옮겨 놓는다.
	var lbox := func(spec: Dictionary, u0: float, u1: float, v0: float, v1: float, y0: float, y1: float) -> void:
		var a: Vector3 = _to_world(lo, hi, rot, u0, v0, y0, depth)
		var c: Vector3 = _to_world(lo, hi, rot, u1, v1, y1, depth)
		VillageAssets.box_st(part.call(spec), Vector3(minf(a.x, c.x), minf(a.y, c.y), minf(a.z, c.z)), Vector3(maxf(a.x, c.x), maxf(a.y, c.y), maxf(a.z, c.z)))

	var levels: int = clampi(stack, 1, 3)
	var spl: int = maxi(1, slots_per_level)
	var total_h: float = FIRST_LEVEL_H + STACK_LEVEL_H * float(levels - 1)
	var inset: float = 0.06

	for k in range(levels):
		var y0: float = 0.0 if k == 0 else FIRST_LEVEL_H + STACK_LEVEL_H * float(k - 1)
		var h: float = FIRST_LEVEL_H if k == 0 else STACK_LEVEL_H
		var y1: float = y0 + h
		lbox.call(wood_frame, 0.0, inset, 0.0, depth, y0, y1)
		lbox.call(wood_frame, length - inset, length, 0.0, depth, y0, y1)
		lbox.call(wood_back, inset, length - inset, 0.0, 0.05, y0, y1)
		var boards: Array = [y0 + 0.1, y0 + 0.1 + (h - 0.14) * 0.5]
		lbox.call(wood_board, inset, length - inset, 0.0, depth, boards[0], boards[0] + 0.04)
		lbox.call(wood_board, inset, length - inset, 0.0, depth, boards[1], boards[1] + 0.04)
		lbox.call(wood_frame, 0.0, length, 0.0, depth, y1 - 0.05, y1)
		if stage == "modern":
			var stripe := VillageAssets._flat_spec(ts, Color(0.26, 0.62, 0.43), "shelf_price_strip")
			for y in boards: lbox.call(stripe, inset, length - inset, depth - 0.025, depth, float(y) - 0.04, float(y) + 0.02)
		elif stage == "reinforced":
			var iron := VillageAssets._flat_spec(ts, Color(0.31, 0.35, 0.39), "shelf_reinforced_bracket")
			for u in [0.0, length - inset]: lbox.call(iron, u, u + inset, depth - 0.04, depth + 0.005, y0 + 0.1, y0 + 0.3)

		# 이 층의 칸(slot): 칸 j 는 아래·위 선반에 번갈아 놓고, 한 선반에는 칸 수에 맞춰 길이를 나눈다.
		var per_board: int = int(ceil(float(spl) / 2.0))
		var seg: float = (length - 2.0 * inset - 0.06) / float(per_board)

		for j in range(spl):
			var slot_index: int = k * spl + j

			if slot_index >= slots.size():
				continue

			var slot: Dictionary = slots[slot_index]
			var count: int = mini(int(slot.get("stock", 0)), MAX_VISIBLE)
			var item_id: String = str(slot.get("item_id", ""))

			if count <= 0 or item_id.is_empty():
				continue

			var board_y: float = float(boards[j % 2]) + 0.04
			# 이 선반 위 여유 높이(위 판 밑면까지). 아래 선반은 위 선반 밑까지, 위 선반은 층 윗판 밑까지.
			var room: float = (float(boards[1]) - board_y) if j % 2 == 0 else ((y1 - 0.05) - board_y)
			var seg_index: int = j / 2
			var u_start: float = inset + 0.03 + seg * float(seg_index)
			var shape: String = shape_of(item_id)
			var gs: Array = goods_specs(item_id, ts)
			var goods_spec: Dictionary = gs[0]
			var accent: Dictionary = gs[1]
			var cork: Dictionary = gs[2]

			for n in range(count):
				var uu: float = u_start + seg * (float(n) + 0.5) / float(count)
				var vv: float = depth * (0.62 if n % 2 == 0 else 0.4) if count > 3 else depth * 0.5
				var at: Vector3 = _to_world(lo, hi, rot, uu, vv, board_y, depth)
				var fit: float = room * HEADROOM / float(SHAPE_HEIGHT.get(shape, 0.2))
				_good(shape, part, goods_spec, accent, cork, at, minf(GOODS_SCALE * (0.82 if count > 3 else 1.0), fit), n)

	var mesh := ArrayMesh.new()
	var specs: Array = b.commit_into(mesh)
	return {"mesh": mesh, "specs": specs, "total_blocks": total_h, "lo": lo, "hi": hi}


# 상품 재질 셋: [주색, 어두운 색, 마개]. 선반 안쪽은 그늘이라 상품이 어둡게 죽으므로 색을 밝히고 약하게 스스로 빛나게 한다.
static func goods_specs(item_id: String, ts: int) -> Array:
	var color: Color = item_color(item_id).lerp(Color.WHITE, 0.22)
	var goods_spec: Dictionary = VillageAssets._flat_spec(ts, color, "good_" + color.to_html(false))
	var accent: Dictionary = VillageAssets._flat_spec(ts, color.darkened(0.25), "goodd_" + color.to_html(false))
	goods_spec["emit"] = 0.3
	accent["emit"] = 0.22
	return [goods_spec, accent, VillageAssets._flat_spec(ts, Color(0.62, 0.45, 0.28), "good_cork")]


# 상품 한 개만의 메시(갤러리·미리보기용). 원점 중심, sc = 크기 배율.
static func build_good(item_id: String, p: Dictionary, sc: float = 2.4) -> Dictionary:
	var b := VillageAssets.PartBuilder.new()
	var parts: Dictionary = {}
	var part := func(spec: Dictionary) -> SurfaceTool:
		var key: String = str(spec["name"])

		if not parts.has(key):
			parts[key] = b.new_part(spec, Vector3(-0.4, 0.0, -0.4), Vector3(0.4, 0.6, 0.4))

		return parts[key]

	var gs: Array = goods_specs(item_id, int(p["ts"]))
	_good(shape_of(item_id), part, gs[0], gs[1], gs[2], Vector3.ZERO, sc, 0)
	var mesh := ArrayMesh.new()
	var specs: Array = b.commit_into(mesh)
	return {"mesh": mesh, "specs": specs}


# (u, v, y) → 칸 좌표 (x, y, z). lo/hi 는 3D 발자국. v 는 뒤(0)에서 앞(depth)으로.
static func _to_world(lo: Vector2, hi: Vector2, rot: int, u: float, v: float, y: float, depth: float) -> Vector3:
	match rot:
		0:
			return Vector3(lo.x + u, y, lo.y + v)
		2:
			return Vector3(hi.x - u, y, hi.y - v)
		1:
			return Vector3(lo.x + v, y, lo.y + u)
		_:
			return Vector3(hi.x - v, y, hi.y - u)


# 상품 한 개. at = 선반 위 바닥 중심(칸 좌표 + 높이), sc = 크기 배율.
static func _good(shape: String, part: Callable, main: Dictionary, dark: Dictionary, cork: Dictionary, at: Vector3, sc: float, n: int) -> void:
	var st: SurfaceTool = part.call(main)
	var sd: SurfaceTool = part.call(dark)
	var sk: SurfaceTool = part.call(cork)
	var x: float = at.x
	var z: float = at.z
	var y: float = at.y

	match shape:
		"loaf":
			VillageAssets.dome_st(st, x, z, 0.11 * sc, y, y + 0.13 * sc, 2, 8)
			VillageAssets.dome_st(sd, x, z, 0.075 * sc, y + 0.09 * sc, y + 0.15 * sc, 2, 6)
		"bottle":
			VillageAssets.oct_st(st, x, z, 0.055 * sc, y, y + 0.24 * sc, 0.055 * sc)
			VillageAssets.oct_st(st, x, z, 0.028 * sc, y + 0.24 * sc, y + 0.34 * sc, 0.028 * sc)
			VillageAssets.oct_st(sk, x, z, 0.03 * sc, y + 0.34 * sc, y + 0.37 * sc, 0.03 * sc)
		"flask":
			VillageAssets.dome_st(st, x, z, 0.085 * sc, y, y + 0.15 * sc, 2, 8)
			VillageAssets.oct_st(st, x, z, 0.03 * sc, y + 0.12 * sc, y + 0.3 * sc, 0.03 * sc)
			VillageAssets.oct_st(sk, x, z, 0.034 * sc, y + 0.3 * sc, y + 0.33 * sc, 0.034 * sc)
		"bowl":
			VillageAssets.oct_st(sd, x, z, 0.085 * sc, y, y + 0.09 * sc, 0.1 * sc)
			VillageAssets.oct_st(st, x, z, 0.075 * sc, y + 0.07 * sc, y + 0.095 * sc, 0.075 * sc)
		"jar":
			VillageAssets.oct_st(st, x, z, 0.075 * sc, y, y + 0.16 * sc, 0.07 * sc)
			VillageAssets.oct_st(sk, x, z, 0.08 * sc, y + 0.16 * sc, y + 0.19 * sc, 0.08 * sc)
		"rocks":
			VillageAssets.dome_st(st, x - 0.03 * sc, z, 0.075 * sc, y, y + 0.1 * sc, 2, 6)
			VillageAssets.dome_st(sd, x + 0.04 * sc, z + 0.02 * sc, 0.055 * sc, y, y + 0.08 * sc, 2, 6)
		"crystal":
			VillageAssets.oct_st(st, x, z, 0.05 * sc, y, y + 0.2 * sc, 0.008 * sc)
			VillageAssets.oct_st(sd, x + 0.045 * sc, z + 0.015 * sc, 0.032 * sc, y, y + 0.13 * sc, 0.006 * sc)
		"bundle":
			for i in range(4):
				var a: float = float(i) * 1.6 + float(n)
				VillageAssets.oct_st(st, x + cos(a) * 0.035 * sc, z + sin(a) * 0.035 * sc, 0.012 * sc, y, y + (0.2 + 0.04 * float(i % 2)) * sc, 0.006 * sc)

			VillageAssets.dome_st(sd, x, z, 0.06 * sc, y + 0.12 * sc, y + 0.2 * sc, 2, 6)
		"mushroom":
			VillageAssets.oct_st(sd, x, z, 0.022 * sc, y, y + 0.1 * sc, 0.022 * sc)
			VillageAssets.dome_st(st, x, z, 0.075 * sc, y + 0.08 * sc, y + 0.17 * sc, 2, 8)
		"orb":
			VillageAssets.dome_st(st, x - 0.025 * sc, z, 0.05 * sc, y, y + 0.09 * sc, 2, 6)
			VillageAssets.dome_st(st, x + 0.035 * sc, z + 0.02 * sc, 0.045 * sc, y, y + 0.08 * sc, 2, 6)
			VillageAssets.dome_st(sd, x, z - 0.03 * sc, 0.04 * sc, y, y + 0.07 * sc, 2, 6)
		"scroll":
			VillageAssets.oct_st(st, x, z, 0.035 * sc, y, y + 0.2 * sc, 0.035 * sc)
			VillageAssets.oct_st(sd, x, z, 0.04 * sc, y + 0.04 * sc, y + 0.07 * sc, 0.04 * sc)
		"lantern":
			VillageAssets.oct_st(sd, x, z, 0.05 * sc, y, y + 0.03 * sc, 0.05 * sc)
			VillageAssets.oct_st(st, x, z, 0.045 * sc, y + 0.03 * sc, y + 0.17 * sc, 0.045 * sc)
			VillageAssets.oct_st(sd, x, z, 0.05 * sc, y + 0.17 * sc, y + 0.2 * sc, 0.02 * sc)
		"box":
			VillageAssets.box_st(st, Vector3(x - 0.07 * sc, y, z - 0.06 * sc), Vector3(x + 0.07 * sc, y + 0.12 * sc, z + 0.06 * sc))
			VillageAssets.box_st(sd, Vector3(x - 0.072 * sc, y + 0.05 * sc, z - 0.062 * sc), Vector3(x + 0.072 * sc, y + 0.07 * sc, z + 0.062 * sc))
		"disc":
			VillageAssets.oct_st(st, x, z, 0.065 * sc, y, y + 0.025 * sc, 0.065 * sc)
			VillageAssets.oct_st(sd, x, z, 0.03 * sc, y + 0.025 * sc, y + 0.04 * sc, 0.03 * sc)
		_:
			VillageAssets.box_st(st, Vector3(x - 0.06 * sc, y, z - 0.06 * sc), Vector3(x + 0.06 * sc, y + 0.12 * sc, z + 0.06 * sc))
