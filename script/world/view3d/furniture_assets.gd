class_name FurnitureAssets
extends RefCounted
## 가구 3D 모델(진열대 제외, 진열대는 ShelfAssets): 계산대, 창고 선반, 음료 제조기, 마법 오븐, 화분, 등불, 골동품 진열장,
## 벽 장식(포스터·세계지도·깃발), 문(출입문·창고 문·생산실 문). 가구마다 부품(상자·기둥·돔)을 쌓아 만들고, 발광 부품(emit)은 어두운 곳에서도 읽히게 한다.
## 좌표는 (u = 길이 방향, v = 뒤→앞 방향, y = 높이). lo/hi 는 3D 발자국(칸 좌표), rot 은 앞쪽 방향(0=+z, 1=+x, 2=-z, 3=-x).

const MODEL_IDS: Array = ["register", "warehouse_rack", "drink_machine", "magic_oven", "plant_small", "night_lantern", "antique_cabinet", "wall_poster", "old_world_map", "adventurer_banner", "door", "warehouse_door", "production_door"]


# 부품을 쌓는 좌표 틀. 재질 이름 하나당 면 하나만 만든다(메시 면은 최대 256개).
class Frame extends RefCounted:
	var b := VillageAssets.PartBuilder.new()
	var parts: Dictionary = {}
	var lo: Vector2
	var hi: Vector2
	var rot: int
	var p: Dictionary
	var length: float
	var depth: float

	func _init(lo_: Vector2, hi_: Vector2, rot_: int, p_: Dictionary) -> void:
		lo = lo_
		hi = hi_
		rot = posmod(rot_, 4)
		p = p_
		var along_x: bool = rot == 0 or rot == 2
		length = (hi.x - lo.x) if along_x else (hi.y - lo.y)
		depth = (hi.y - lo.y) if along_x else (hi.x - lo.x)

	func part(spec: Dictionary) -> SurfaceTool:
		var key: String = str(spec["name"])

		if not parts.has(key):
			parts[key] = b.new_part(spec, Vector3(lo.x, 0.0, lo.y), Vector3(hi.x, 2.0, hi.y))

		return parts[key]

	func world(u: float, v: float, y: float) -> Vector3:
		return ShelfAssets._to_world(lo, hi, rot, u, v, y, depth)

	func box(spec: Dictionary, u0: float, u1: float, v0: float, v1: float, y0: float, y1: float) -> void:
		var a: Vector3 = world(u0, v0, y0)
		var c: Vector3 = world(u1, v1, y1)
		VillageAssets.box_st(part(spec), Vector3(minf(a.x, c.x), minf(a.y, c.y), minf(a.z, c.z)), Vector3(maxf(a.x, c.x), maxf(a.y, c.y), maxf(a.z, c.z)))

	func cyl(spec: Dictionary, u: float, v: float, r: float, y0: float, y1: float, r_top: float = -1.0) -> void:
		var c: Vector3 = world(u, v, y0)
		VillageAssets.oct_st(part(spec), c.x, c.z, r, y0, y1, r_top)

	func dome(spec: Dictionary, u: float, v: float, r: float, y0: float, y1: float) -> void:
		var c: Vector3 = world(u, v, y0)
		VillageAssets.dome_st(part(spec), c.x, c.z, r, y0, y1, 3, 10)

	func flat(color: Color, name: String, emit: float = 0.0) -> Dictionary:
		var sp: Dictionary = VillageAssets._flat_spec(int(p["ts"]), color, name)

		if emit > 0.0:
			sp["emit"] = emit

		return sp

	func wood(color: Color, name: String) -> Dictionary:
		return VillageAssets.wood(p, color, name)

	func stone(color: Color, name: String) -> Dictionary:
		return VillageAssets.stone_spec(p, color, name)

	func finish(total: float) -> Dictionary:
		var mesh := ArrayMesh.new()
		var specs: Array = b.commit_into(mesh)
		return {"mesh": mesh, "specs": specs, "total_blocks": total, "lo": lo, "hi": hi}


static func has_model(build_id: String) -> bool:
	return MODEL_IDS.has(build_id)


# 벽 부착물의 회전(0=뒤 y 작은 벽, 1=x 큰 벽, 2=y 큰 벽, 3=x 작은 벽)을 앞쪽 방향 회전(0=+z, 1=+x, 2=-z, 3=-x)으로 바꾼다.
static func wall_front_rot(wall_rotation: int) -> int:
	return [0, 3, 2, 1][posmod(wall_rotation, 4)]


static func build(build_id: String, lo: Vector2, hi: Vector2, rot: int, p: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var f := Frame.new(lo, hi, rot, p)

	match build_id:
		"register":
			return _register(f)
		"warehouse_rack":
			return _rack(f, extra)
		"drink_machine":
			return _drink_machine(f)
		"magic_oven":
			return _oven(f)
		"plant_small":
			return _plant(f)
		"night_lantern":
			return _lantern(f)
		"antique_cabinet":
			return _cabinet(f)
		"wall_poster":
			return _poster(f)
		"old_world_map":
			return _map(f)
		"adventurer_banner":
			return _banner(f)
		"door", "warehouse_door", "production_door":
			return _door(f, build_id)

	return f.finish(1.0)


# ---------------------------------------------------------------- 매장 가구

static func _register(f: Frame) -> Dictionary:
	var L: float = f.length
	var D: float = f.depth
	var body: Dictionary = f.wood(Color(0.62, 0.42, 0.26), "reg_body")
	var top: Dictionary = f.stone(Color(0.86, 0.84, 0.78), "reg_top")
	var panel: Dictionary = f.wood(Color(0.48, 0.32, 0.2), "reg_panel")
	var dark: Dictionary = f.flat(Color(0.16, 0.17, 0.2), "reg_dark")
	var screen: Dictionary = f.flat(Color(0.5, 0.95, 0.7), "reg_screen", 0.9)
	var key: Dictionary = f.flat(Color(0.75, 0.78, 0.85), "reg_key")
	f.box(body, 0.04, L - 0.04, 0.03, D - 0.03, 0.0, 0.74)
	f.box(panel, 0.14, L - 0.14, D - 0.035, D - 0.015, 0.1, 0.62)  # 앞 판
	f.box(top, 0.0, L, 0.0, D, 0.74, 0.82)
	# 단말기: 받침 + 화면(손님 쪽으로 기울지 않게 세움) + 자판
	f.box(dark, 0.22, 0.62, D * 0.3, D * 0.7, 0.82, 0.88)
	f.box(dark, 0.4, 0.44, D * 0.46, D * 0.54, 0.88, 1.0)
	f.box(dark, 0.26, 0.58, D * 0.4, D * 0.6, 0.98, 1.1)
	f.box(screen, 0.28, 0.56, D * 0.6, D * 0.63, 1.0, 1.08)
	f.box(key, 0.3, 0.54, D * 0.36, D * 0.52, 0.88, 0.9)
	# 돈통(서랍)과 영수증 프린터, 장바구니 걸이
	f.box(dark, L - 0.62, L - 0.2, D * 0.25, D * 0.75, 0.82, 0.92)
	f.box(key, L - 0.58, L - 0.4, D * 0.4, D * 0.6, 0.92, 0.95)
	f.box(panel, 0.9, 1.14, D * 0.2, D * 0.8, 0.82, 0.86)
	return f.finish(1.1)


# 창고 선반: 철제 기둥 + 선반 판 세 장. 저장된 아이템을 층마다 한 종류씩 보여 준다(아래 층부터 저장 칸 순서대로 서로 다른 아이템 3종까지).
# extra["storage_slots"] = [{item_id, amount}]. 수량이 많을수록 더 많이(최대 6개) 놓인다.
static func _rack(f: Frame, extra: Dictionary = {}) -> Dictionary:
	var L: float = f.length
	var D: float = f.depth
	var post: Dictionary = f.flat(Color(0.34, 0.37, 0.43), "rack_iron")
	var board: Dictionary = f.wood(Color(0.7, 0.52, 0.34), "rack_board")

	for pu in [0.05, L - 0.05]:
		for pv in [0.08, D - 0.08]:
			f.box(post, pu - 0.04, pu + 0.04, pv - 0.04, pv + 0.04, 0.0, 1.7)

	var ys: Array = [0.12, 0.66, 1.2]
	for y in ys:
		f.box(board, 0.0, L, 0.0, D, y, y + 0.05)

	f.box(board, 0.0, L, 0.0, D, 1.68, 1.74)

	# 층별 저장품: 서로 다른 아이템을 저장 칸 순서대로 최대 3종, 같은 아이템의 수량은 합친다.
	var order: Array = []
	var totals: Dictionary = {}

	for slot in extra.get("storage_slots", []):
		var id: String = str((slot as Dictionary).get("item_id", ""))
		var amount: int = int((slot as Dictionary).get("amount", 0))

		if id.is_empty() or amount <= 0:
			continue

		if not totals.has(id):
			totals[id] = 0
			order.append(id)

		totals[id] = int(totals[id]) + amount

	var ts: int = int(f.p["ts"])
	var limits: Array = [0.66 - 0.17, 1.2 - 0.71, 1.68 - 1.25]  # 각 층 선반 위 여유 높이

	for k in range(mini(order.size(), 3)):
		var item_id: String = order[k]
		var gs: Array = ShelfAssets.goods_specs(item_id, ts)
		var shape: String = ShelfAssets.shape_of(item_id)
		var count: int = clampi(int(ceil(float(totals[item_id]) / 8.0)), 1, 6)
		var fit: float = float(limits[k]) * ShelfAssets.HEADROOM / float(ShelfAssets.SHAPE_HEIGHT.get(shape, 0.2))
		var sc: float = minf(ShelfAssets.GOODS_SCALE * 1.15, fit)
		var y_top: float = float(ys[k]) + 0.05

		for n in range(count):
			var u: float = 0.16 + (L - 0.32) * (float(n) + 0.5) / float(count)
			var v: float = D * (0.62 if n % 2 == 0 else 0.4) if count > 3 else D * 0.5
			var at: Vector3 = f.world(u, v, y_top)
			ShelfAssets._good(shape, Callable(f, "part"), gs[0], gs[1], gs[2], at, sc, n)

	return f.finish(1.8)


static func _drink_machine(f: Frame) -> Dictionary:
	var L: float = f.length
	var D: float = f.depth
	var body: Dictionary = f.flat(Color(0.82, 0.3, 0.26), "dm_body")
	var trim: Dictionary = f.flat(Color(0.95, 0.9, 0.82), "dm_trim")
	var dark: Dictionary = f.flat(Color(0.14, 0.15, 0.18), "dm_dark")
	var glass: Dictionary = f.flat(Color(0.7, 0.9, 1.0), "dm_glass", 0.55)
	var cx: float = L * 0.5
	f.box(dark, 0.14, L - 0.14, 0.14, D - 0.14, 0.0, 0.08)  # 받침
	f.box(body, 0.12, L - 0.12, 0.12, D - 0.12, 0.08, 1.52)
	f.box(trim, 0.1, L - 0.1, 0.1, D - 0.1, 1.48, 1.58)  # 윗머리
	# 앞면: 유리 진열창(병 줄) + 투입구 + 배출구
	f.box(glass, 0.2, L - 0.2, D - 0.135, D - 0.115, 0.7, 1.4)
	var cols: Array = [Color(0.3, 0.7, 1.0), Color(1.0, 0.8, 0.25), Color(0.5, 0.9, 0.5), Color(0.95, 0.45, 0.6)]
	for r in range(3):
		for c in range(4):
			var u: float = 0.2 + (L - 0.4) * (float(c) + 0.5) / 4.0
			var col: Dictionary = f.flat(cols[(c + r) % 4], "dm_bottle%d" % ((c + r) % 4), 0.35)
			f.box(col, u - 0.04, u + 0.04, D - 0.18, D - 0.13, 0.76 + float(r) * 0.22, 0.9 + float(r) * 0.22)

	f.box(dark, 0.28, L - 0.28, D - 0.16, D - 0.1, 0.14, 0.4)  # 배출구
	f.box(trim, cx - 0.1, cx + 0.1, D - 0.14, D - 0.1, 0.5, 0.6)  # 동전 투입구
	return f.finish(1.6)


static func _oven(f: Frame) -> Dictionary:
	var L: float = f.length
	var D: float = f.depth
	var brick: Dictionary = f.stone(Color(0.62, 0.48, 0.56), "ov_brick")
	var trim: Dictionary = f.flat(Color(0.5, 0.35, 0.72), "ov_trim", 0.25)
	var dark: Dictionary = f.flat(Color(0.1, 0.06, 0.08), "ov_dark")
	var fire: Dictionary = f.flat(Color(1.0, 0.55, 0.2), "ov_fire", 1.0)
	var rune: Dictionary = f.flat(Color(0.75, 0.55, 1.0), "ov_rune", 0.9)
	f.box(brick, 0.04, L - 0.04, 0.08, D - 0.08, 0.0, 1.0)
	f.box(trim, 0.0, L, 0.04, D - 0.04, 0.96, 1.06)  # 마법 띠
	f.box(brick, 0.1, L - 0.1, 0.14, D - 0.14, 1.06, 1.3)
	f.cyl(brick, L * 0.78, D * 0.4, 0.15, 1.3, 1.62, 0.1)  # 굴뚝
	# 앞면 아치 입구: 어두운 속 + 안쪽 불빛
	var u0: float = L * 0.22
	var u1: float = L * 0.62
	f.box(dark, u0, u1, D - 0.1, D - 0.06, 0.18, 0.7)
	f.box(fire, u0 + 0.07, u1 - 0.07, D - 0.12, D - 0.09, 0.2, 0.46)
	f.box(trim, u0 - 0.06, u0, D - 0.12, D - 0.04, 0.14, 0.76)
	f.box(trim, u1, u1 + 0.06, D - 0.12, D - 0.04, 0.14, 0.76)
	f.box(trim, u0 - 0.06, u1 + 0.06, D - 0.12, D - 0.04, 0.7, 0.78)
	# 옆 룬 장식
	for i in range(3):
		var ur: float = L * 0.7 + float(i) * 0.12
		f.box(rune, ur, ur + 0.05, D - 0.1, D - 0.07, 0.3 + float(i % 2) * 0.12, 0.55 + float(i % 2) * 0.12)

	return f.finish(1.4)


static func _plant(f: Frame) -> Dictionary:
	var L: float = f.length
	var D: float = f.depth
	var pot: Dictionary = f.flat(Color(0.78, 0.42, 0.28), "pl_pot")
	var rim: Dictionary = f.flat(Color(0.86, 0.5, 0.34), "pl_rim")
	var soil: Dictionary = f.flat(Color(0.3, 0.2, 0.14), "pl_soil")
	var leaf: Dictionary = f.flat(Color(0.3, 0.62, 0.3), "pl_leaf")
	var leaf2: Dictionary = f.flat(Color(0.42, 0.74, 0.36), "pl_leaf2")
	var stem: Dictionary = f.flat(Color(0.28, 0.5, 0.24), "pl_stem")
	var cu: float = L * 0.5
	var cv: float = D * 0.5
	f.cyl(pot, cu, cv, 0.2, 0.0, 0.3, 0.26)
	f.cyl(rim, cu, cv, 0.27, 0.28, 0.36, 0.27)
	f.cyl(soil, cu, cv, 0.22, 0.34, 0.37, 0.22)

	for i in range(6):
		var a: float = float(i) * 1.05
		var du: float = cos(a) * 0.1
		var dv: float = sin(a) * 0.08
		var h: float = 0.55 + 0.12 * float(i % 3)
		f.cyl(stem, cu + du, cv + dv, 0.015, 0.36, h, 0.01)
		f.dome(leaf if i % 2 == 0 else leaf2, cu + du * 1.6, cv + dv * 1.6, 0.11, h - 0.04, h + 0.1)

	f.dome(leaf2, cu, cv, 0.13, 0.5, 0.8)
	return f.finish(0.8)


static func _lantern(f: Frame) -> Dictionary:
	var L: float = f.length
	var D: float = f.depth
	var iron: Dictionary = f.flat(Color(0.2, 0.2, 0.24), "ln_iron")
	var glow: Dictionary = f.flat(Color(1.0, 0.85, 0.45), "ln_glow", 1.0)
	var cu: float = L * 0.5
	var cv: float = D * 0.5
	f.cyl(iron, cu, cv, 0.12, 0.0, 0.06, 0.1)
	f.cyl(iron, cu, cv, 0.035, 0.06, 1.32, 0.03)
	f.box(iron, cu - 0.12, cu + 0.12, cv - 0.12, cv + 0.12, 1.3, 1.36)
	f.box(glow, cu - 0.09, cu + 0.09, cv - 0.09, cv + 0.09, 1.36, 1.62)
	for du in [-0.1, 0.1]:
		for dv in [-0.1, 0.1]:
			f.box(iron, cu + du - 0.012, cu + du + 0.012, cv + dv - 0.012, cv + dv + 0.012, 1.36, 1.62)

	f.cyl(iron, cu, cv, 0.14, 1.62, 1.72, 0.04)
	f.cyl(iron, cu, cv, 0.03, 1.72, 1.8, 0.02)
	return f.finish(1.8)


static func _cabinet(f: Frame) -> Dictionary:
	var L: float = f.length
	var D: float = f.depth
	var dark: Dictionary = f.wood(Color(0.5, 0.34, 0.22), "cab_wood")
	var trim: Dictionary = f.wood(Color(0.66, 0.46, 0.28), "cab_trim")
	var glass: Dictionary = f.flat(Color(0.75, 0.88, 0.95), "cab_glass", 0.4)
	var inner: Dictionary = f.flat(Color(0.28, 0.2, 0.16), "cab_inner")
	var vase: Dictionary = f.flat(Color(0.35, 0.6, 0.75), "cab_vase")
	var gold: Dictionary = f.flat(Color(0.95, 0.78, 0.3), "cab_gold", 0.3)
	var book: Dictionary = f.flat(Color(0.7, 0.3, 0.3), "cab_book")
	f.box(dark, 0.08, L - 0.08, 0.1, D - 0.1, 0.0, 0.3)  # 아래 서랍장
	f.box(trim, 0.1, L - 0.1, D - 0.115, D - 0.095, 0.08, 0.28)
	f.box(gold, L * 0.5 - 0.05, L * 0.5 + 0.05, D - 0.12, D - 0.09, 0.17, 0.2)
	f.box(inner, 0.1, L - 0.1, 0.12, D - 0.12, 0.3, 1.62)  # 유리장 속
	f.box(glass, 0.12, L - 0.12, D - 0.125, D - 0.105, 0.34, 1.58)
	f.box(dark, 0.06, 0.12, 0.08, D - 0.08, 0.3, 1.66)  # 옆틀
	f.box(dark, L - 0.12, L - 0.06, 0.08, D - 0.08, 0.3, 1.66)
	f.box(trim, 0.02, L - 0.02, 0.04, D - 0.04, 1.66, 1.76)  # 윗장식
	f.box(dark, 0.1, L - 0.1, 0.12, D - 0.12, 0.95, 0.99)  # 중간 선반

	# 진열품: 꽃병·책·금 장식
	f.cyl(vase, L * 0.3, D * 0.5, 0.07, 0.99, 1.2, 0.05)
	f.cyl(vase, L * 0.3, D * 0.5, 0.03, 1.2, 1.3, 0.03)
	f.box(book, L * 0.55, L * 0.72, D * 0.3, D * 0.7, 0.99, 1.2)
	f.dome(gold, L * 0.5, D * 0.5, 0.07, 0.3, 0.42)
	f.cyl(gold, L * 0.72, D * 0.5, 0.05, 0.3, 0.55, 0.03)
	f.cyl(vase, L * 0.28, D * 0.5, 0.06, 0.3, 0.5, 0.05)
	return f.finish(1.8)


# ---------------------------------------------------------------- 벽 장식(얇은 판) — 앞쪽 = 방 안쪽

static func _poster(f: Frame) -> Dictionary:
	var L: float = f.length
	var frame: Dictionary = f.wood(Color(0.55, 0.38, 0.24), "po_frame")
	var paper: Dictionary = f.flat(Color(0.97, 0.9, 0.78), "po_paper")
	var red: Dictionary = f.flat(Color(0.85, 0.3, 0.25), "po_red")
	var blue: Dictionary = f.flat(Color(0.3, 0.5, 0.8), "po_blue")
	var D: float = f.depth
	var u0: float = L * 0.5 - 0.35
	var u1: float = L * 0.5 + 0.35
	f.box(frame, u0, u1, 0.0, D, 0.0, 0.9)
	f.box(paper, u0 + 0.05, u1 - 0.05, D * 0.7, D, 0.05, 0.85)
	f.box(red, u0 + 0.12, u1 - 0.12, D * 0.9, D * 1.0, 0.55, 0.75)  # 큰 글자 띠
	f.box(blue, u0 + 0.12, L * 0.5, D * 0.9, D * 1.0, 0.2, 0.46)  # 상품 그림
	f.box(red, L * 0.5 + 0.04, u1 - 0.12, D * 0.9, D * 1.0, 0.22, 0.4)
	return f.finish(0.9)


static func _map(f: Frame) -> Dictionary:
	var L: float = f.length
	var D: float = f.depth
	var rod: Dictionary = f.wood(Color(0.42, 0.28, 0.18), "mp_rod")
	var paper: Dictionary = f.flat(Color(0.88, 0.8, 0.6), "mp_paper")
	var ink: Dictionary = f.flat(Color(0.4, 0.3, 0.2), "mp_ink")
	var sea: Dictionary = f.flat(Color(0.55, 0.72, 0.72), "mp_sea")
	var land: Dictionary = f.flat(Color(0.5, 0.65, 0.4), "mp_land")
	var red: Dictionary = f.flat(Color(0.8, 0.25, 0.2), "mp_x")
	var u0: float = L * 0.5 - 0.38
	var u1: float = L * 0.5 + 0.38
	f.box(paper, u0, u1, 0.0, D * 0.6, 0.06, 0.76)
	f.box(sea, u0 + 0.05, u1 - 0.05, D * 0.5, D * 0.8, 0.12, 0.7)
	f.box(land, u0 + 0.12, u0 + 0.38, D * 0.7, D, 0.3, 0.6)
	f.box(land, u0 + 0.36, u1 - 0.1, D * 0.7, D, 0.16, 0.34)
	f.box(ink, u0 + 0.1, u1 - 0.1, D * 0.85, D, 0.62, 0.64)
	f.box(red, u0 + 0.4, u0 + 0.46, D * 0.9, D * 1.1, 0.38, 0.44)
	f.cyl(rod, L * 0.5, D * 0.2, 0.035, 0.0, 0.06, 0.035)
	f.box(rod, u0 - 0.04, u1 + 0.04, 0.0, D * 0.4, 0.74, 0.8)  # 위 막대
	f.box(rod, u0 - 0.04, u1 + 0.04, 0.0, D * 0.4, 0.0, 0.06)  # 아래 막대
	return f.finish(0.8)


static func _banner(f: Frame) -> Dictionary:
	var L: float = f.length
	var D: float = f.depth
	var rod: Dictionary = f.wood(Color(0.42, 0.28, 0.18), "bn_rod")
	var cloth: Dictionary = f.flat(Color(0.75, 0.2, 0.2), "bn_cloth")
	var gold: Dictionary = f.flat(Color(0.95, 0.78, 0.3), "bn_gold", 0.25)
	var cu: float = L * 0.5
	f.box(rod, cu - 0.34, cu + 0.34, 0.0, D * 0.5, 1.16, 1.22)
	f.box(cloth, cu - 0.28, cu + 0.28, D * 0.2, D * 0.55, 0.28, 1.16)
	f.box(cloth, cu - 0.28, cu - 0.04, D * 0.2, D * 0.55, 0.1, 0.28)  # 아래 두 갈래 꼬리
	f.box(cloth, cu + 0.04, cu + 0.28, D * 0.2, D * 0.55, 0.1, 0.28)
	f.box(gold, cu - 0.1, cu + 0.1, D * 0.55, D * 0.75, 0.62, 0.9)  # 문장(검 모양)
	f.box(gold, cu - 0.03, cu + 0.03, D * 0.55, D * 0.75, 0.5, 1.02)
	f.box(gold, cu - 0.16, cu + 0.16, D * 0.55, D * 0.75, 0.82, 0.86)
	f.box(gold, cu - 0.28, cu + 0.28, D * 0.55, D * 0.75, 1.1, 1.14)
	return f.finish(1.2)


# ---------------------------------------------------------------- 문: 틀(기둥 둘 + 윗가로대) + 열린 문짝 + 손잡이/장식

static func _door(f: Frame, build_id: String) -> Dictionary:
	if build_id == "door":
		return _glass_door(f)

	var L: float = f.length
	var D: float = f.depth
	var frame_col := Color(0.55, 0.38, 0.24)
	var leaf_col := Color(0.62, 0.44, 0.28)
	var plate_col := Color(0.85, 0.7, 0.35)

	if build_id == "warehouse_door":
		frame_col = Color(0.36, 0.38, 0.44)
		leaf_col = Color(0.44, 0.46, 0.52)
		plate_col = Color(0.7, 0.72, 0.78)
	elif build_id == "production_door":
		frame_col = Color(0.4, 0.3, 0.5)
		leaf_col = Color(0.5, 0.4, 0.62)
		plate_col = Color(0.8, 0.6, 1.0)

	var frame: Dictionary = f.wood(frame_col, "dr_frame_" + build_id)
	var leaf: Dictionary = f.wood(leaf_col, "dr_leaf_" + build_id)
	var plate: Dictionary = f.flat(plate_col, "dr_plate_" + build_id, 0.35 if build_id == "production_door" else 0.0)
	var dark: Dictionary = f.flat(Color(0.15, 0.12, 0.1), "dr_dark")
	var post: float = 0.12
	f.box(frame, 0.0, post, 0.0, D, 0.0, 1.9)
	f.box(frame, L - post, L, 0.0, D, 0.0, 1.9)
	f.box(frame, 0.0, L, 0.0, D, 1.55, 1.9)
	f.box(plate, L * 0.5 - 0.22, L * 0.5 + 0.22, D, D + 0.03, 1.62, 1.82)  # 문 위 간판판
	f.box(dark, post, L - post, D * 0.4, D * 0.6, 0.0, 0.02)  # 문턱 그늘

	# 열린 문짝: 한쪽 기둥에 경첩으로 달려 안쪽(앞)으로 90도 열린 모습
	f.box(leaf, post, post + 0.05, D, D + 0.62, 0.02, 1.52)
	f.box(frame, post + 0.005, post + 0.045, D, D + 0.62, 0.7, 0.76)
	f.box(plate, post + 0.045, post + 0.075, D + 0.5, D + 0.56, 0.76, 0.84)  # 손잡이
	return f.finish(1.9)


# 매장 출입문: 현대 편의점의 알루미늄 틀 유리 자동문. 두 짝이 살짝 열려 있고, 위에 브랜드색 간판 띠와 센서가 있다.
static func _glass_door(f: Frame) -> Dictionary:
	var L: float = f.length
	var D: float = f.depth
	var alu: Dictionary = f.flat(Color(0.78, 0.8, 0.84), "gd_alu")
	var glass: Dictionary = f.flat(Color(0.6, 0.82, 0.94), "gd_glass", 0.3)
	var brand: Dictionary = f.flat(StoreShell.BRAND, "gd_brand", 0.2)
	var white: Dictionary = f.flat(Color(0.95, 0.95, 0.92), "gd_white")
	var dark: Dictionary = f.flat(Color(0.16, 0.17, 0.2), "gd_dark")
	var post: float = 0.08
	f.box(alu, 0.0, post, 0.0, D, 0.0, 1.9)  # 양옆 기둥
	f.box(alu, L - post, L, 0.0, D, 0.0, 1.9)
	f.box(white, 0.0, L, 0.0, D, 1.62, 1.9)  # 위 간판 칸
	f.box(brand, 0.04, L - 0.04, D - 0.02, D + 0.02, 1.7, 1.82)  # 브랜드색 띠(양면으로 보임)
	f.box(alu, 0.0, L, 0.0, D, 1.58, 1.64)
	f.box(dark, L * 0.5 - 0.08, L * 0.5 + 0.08, D * 0.3, D * 0.7, 1.52, 1.58)  # 센서
	# 유리문 두 짝(가운데가 한 뼘 열림) + 가운데 손잡이 막대
	var gap: float = 0.1
	f.box(alu, post, L * 0.5 - gap, D * 0.35, D * 0.65, 0.0, 0.05)
	f.box(glass, post, L * 0.5 - gap, D * 0.4, D * 0.6, 0.05, 1.56)
	f.box(alu, L * 0.5 - gap - 0.03, L * 0.5 - gap, D * 0.35, D * 0.65, 0.05, 1.56)
	f.box(alu, L * 0.5 + gap, L - post, D * 0.35, D * 0.65, 0.0, 0.05)
	f.box(glass, L * 0.5 + gap, L - post, D * 0.4, D * 0.6, 0.05, 1.56)
	f.box(alu, L * 0.5 + gap, L * 0.5 + gap + 0.03, D * 0.35, D * 0.65, 0.05, 1.56)
	f.box(dark, 0.0, L, D * 0.45, D * 0.55, 0.0, 0.02)  # 바닥 레일
	return f.finish(1.9)
