class_name OpeningStoreDressing
extends RefCounted
## 새 게임 프롤로그의 가게 안 장식. 게임에 이미 있는 **현대 편의점 집기**(편의점 진열대·냉장함·냉동함)를 연출용으로만 놓는다.
## 실제 가구 노드가 아니라 3D 화면에 모델만 그리므로 저장·충돌·건축과 무관하다.
##   `build_modern()`  전이 전: 냉장함 벽, 편의점 진열대 줄, 입구 쪽 소형 진열대. 진열대에는 실제 상품 모양이 놓인다.
##   `smash()`         전이 뒤: 그 집기를 모두 치우고 부서진 판자·쏟아진 상품·꺾인 기둥·유리 조각을 흩어 놓는다. 시작 배치의 진열대 하나(2,2)만 멀쩡하다.
##   `clear_debris_step()` 정리를 시작하면 잔해를 몇 개씩 치운다.
## 가구 하나는 항목 하나다. 작은 상자를 잘게 쌓으면 깊이 정렬이 수십 배 느려져 화면이 끊기므로(측정: 101개일 때 한 프레임 150~260ms)
## 장식을 늘릴 때도 모델 단위로만 늘린다. 항목 이름은 `cut_s` 로 시작해 도시 장식(`cut_`)·매장 벽과 섞이지 않는다.

const KEY_PREFIX := "cut_s"
const WOOD := Color(0.62, 0.43, 0.28)
const GLASS := Color(0.7, 0.92, 1.0)
const GOODS_COLORS := [
	Color(0.95, 0.35, 0.3), Color(0.98, 0.8, 0.3), Color(0.3, 0.7, 0.95), Color(0.45, 0.85, 0.5),
	Color(0.95, 0.55, 0.8), Color(0.95, 0.95, 0.98), Color(0.62, 0.48, 0.92), Color(0.98, 0.6, 0.25),
]
const DEBRIS_PER_SPOT := 9
const SEED_VALUE := 5
const STOCK_PER_SLOT := 5

# 진열대에 놓는 상품(게임의 실제 상품 id). 모양은 item_3d.csv 가 정한다.
const SHELF_GOODS := ["water", "herb_drink", "bread", "mineral_water", "potion", "berry_juice", "herbal_bread", "reed_tea", "camp_bread", "raw_water", "water", "bread"]

# 놓을 집기: id(건축 id), anchor(칸), size(칸 수), rot(0 이면 앞면이 +y 쪽 = 카메라 쪽), stack(층), spl(층당 칸)
# 칸 좌표: 문 (0,4), 계산대 (4,3), 남은 진열대 (2,2). 매장은 (0..9, 0..7).
const PROPS := [
	{"id": "fridge_unit", "anchor": Vector2i(3, 0), "size": Vector2i(1, 1), "rot": 0},
	{"id": "fridge_unit", "anchor": Vector2i(4, 0), "size": Vector2i(1, 1), "rot": 0},
	{"id": "fridge_unit", "anchor": Vector2i(5, 0), "size": Vector2i(1, 1), "rot": 0},
	{"id": "fridge_unit", "anchor": Vector2i(6, 0), "size": Vector2i(1, 1), "rot": 0},
	{"id": "freezer_unit", "anchor": Vector2i(7, 0), "size": Vector2i(2, 1), "rot": 0},
	{"id": "modern_shelf_2x1", "anchor": Vector2i(1, 0), "size": Vector2i(2, 1), "rot": 0, "stack": 2, "spl": 4},
	{"id": "modern_shelf_3x1", "anchor": Vector2i(7, 2), "size": Vector2i(3, 1), "rot": 0, "stack": 2, "spl": 4},
	{"id": "modern_shelf_3x1", "anchor": Vector2i(6, 5), "size": Vector2i(3, 1), "rot": 0, "stack": 2, "spl": 4},
	{"id": "modern_shelf_2x1", "anchor": Vector2i(3, 6), "size": Vector2i(2, 1), "rot": 0, "stack": 2, "spl": 4},
	{"id": "modern_shelf_1x1", "anchor": Vector2i(1, 6), "size": Vector2i(1, 1), "rot": 1, "stack": 1, "spl": 2},
]

# 부서진 잔해를 놓지 않는 곳: 남은 진열대(2,2)·계산대 주변·문 앞 통로. (칸 좌표 사각형)
const KEEP_CLEAR := [Rect2(1.3, 1.3, 1.4, 1.4), Rect2(3.2, 2.2, 2.6, 1.6), Rect2(-0.5, 3.3, 2.6, 1.5)]

var view: Node                      # StoreView3D
var keys: Array[String] = []
var debris: Array[String] = []
var _count: int = 0


func _init(store_view: Node) -> void:
	view = store_view


func built() -> bool:
	return not keys.is_empty()


# ---------------------------------------------------------------- 전이 전

func build_modern() -> void:
	if built() or view == null:
		return

	for prop in PROPS:
		_place(prop)


# 집기가 차지하는 칸 사각형(가구 3D 와 같은 규칙: 칸 중심이 정수, 두께(depth_ratio)는 회전에 따라 한쪽 변에 붙는다).
func _rect_of(prop: Dictionary) -> Rect2:
	var row: Dictionary = Furniture3DData.get_row(str(prop["id"]))
	var anchor: Vector2i = prop["anchor"]
	var size: Vector2i = prop["size"]
	var lo := Vector2(float(anchor.x) - 0.5, float(anchor.y) - 0.5)
	var hi := Vector2(float(anchor.x + size.x) - 0.5, float(anchor.y + size.y) - 0.5)
	var depth: float = row["depth_ratio"]

	if depth < 1.0:
		match posmod(int(prop["rot"]), 4):
			0:
				hi.y = lo.y + depth
			1:
				hi.x = lo.x + depth
			2:
				lo.y = hi.y - depth
			3:
				lo.x = hi.x - depth

	return Rect2(lo, hi - lo)


func _place(prop: Dictionary) -> void:
	var build_id: String = str(prop["id"])
	var row: Dictionary = Furniture3DData.get_row(build_id)
	var rect: Rect2 = _rect_of(prop)
	var lo: Vector2 = rect.position
	var hi: Vector2 = rect.end
	var rot: int = int(prop["rot"])
	var pp: Dictionary = {"ts": view.texture_size, "block_px": view.block_px, "unit_px_z": (view.tile_low / sqrt(2.0)) * cos(deg_to_rad(view.PITCH_DEG))}
	var built_model: Dictionary

	if str(row["kind"]) == "model":
		built_model = FurnitureAssets.build(build_id, lo, hi, rot, pp, {})
	else:
		pp["furniture_stage"] = FurnitureObjectCatalog.get_object(build_id).get("stage", "")
		var spl: int = int(prop.get("spl", 2))
		var levels: int = int(prop.get("stack", 1))
		var slots: Array = []

		for i in range(spl * levels):
			slots.append({"item_id": SHELF_GOODS[(i + _count) % SHELF_GOODS.size()], "stock": STOCK_PER_SLOT})

		built_model = ShelfAssets.build(lo, hi, rot, levels, slots, spl, pp)

	_count += 1
	var key: String = "%s%s%d" % [KEY_PREFIX, build_id, _count]
	view._set_mesh_item(key, built_model["mesh"], VillageAssets.make_materials(built_model["specs"]), lo, hi, float(built_model["total_blocks"]), "")
	keys.append(key)


# ---------------------------------------------------------------- 전이 뒤

func _put(name: String, lo: Vector2, hi: Vector2, height: float, tint: Color, base: float = 0.0, kind: String = "tile") -> String:
	_count += 1
	var key: String = "%s%s%d" % [KEY_PREFIX, name, _count]
	view._set_item(key, lo, hi, height, kind, tint, "", base)
	return key


# 현대 집기를 모두 치우고 그 자리에 잔해를 깐다.
func smash() -> void:
	for k in keys:
		view._remove_item(k)

	keys.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_VALUE

	for prop in PROPS:
		var rect: Rect2 = _rect_of(prop)
		var lo: Vector2 = rect.position - Vector2(0.35, 0.35)
		var hi: Vector2 = rect.end + Vector2(0.35, 0.35)
		var long_side: float = maxf(rect.size.x, rect.size.y)
		var amount: int = maxi(2, int(round(float(DEBRIS_PER_SPOT) * long_side / 3.0)))

		# 부서진 판자(눕거나 비스듬히 박힌 것처럼 짧고 낮은 막대)
		for i in range(amount):
			var at := Vector2(rng.randf_range(lo.x, hi.x), rng.randf_range(lo.y, hi.y))
			var wide: bool = rng.randf() < 0.5
			var size := Vector2(rng.randf_range(0.45, 0.9), 0.13) if wide else Vector2(0.13, rng.randf_range(0.45, 0.9))
			_add_debris("dp", at, size, rng.randf_range(0.05, 0.16), WOOD * rng.randf_range(0.8, 1.15))

		# 쏟아진 상품
		for i in range(amount):
			var at2 := Vector2(rng.randf_range(lo.x, hi.x), rng.randf_range(lo.y, hi.y))
			_add_debris("dg", at2, Vector2(0.2, 0.2), rng.randf_range(0.1, 0.18), GOODS_COLORS[rng.randi() % GOODS_COLORS.size()])

		# 꺾여 남은 기둥
		if long_side >= 2.0:
			for i in range(2):
				var at3 := Vector2(rng.randf_range(lo.x + 0.3, hi.x - 0.3), rng.randf_range(lo.y + 0.3, hi.y - 0.3))
				_add_debris("ds", at3, Vector2(0.11, 0.11), rng.randf_range(0.35, 0.8), WOOD * 0.8)

		# 유리 조각(냉장함·냉동함 앞)
		if str(prop["id"]).ends_with("_unit"):
			for i in range(3):
				var at4 := Vector2(rng.randf_range(lo.x, hi.x), rng.randf_range(rect.end.y, rect.end.y + 0.9))
				_add_debris("dh", at4, Vector2(rng.randf_range(0.12, 0.3), rng.randf_range(0.12, 0.3)), 0.03, GLASS)


func _add_debris(name: String, at: Vector2, size: Vector2, height: float, tint: Color) -> void:
	for clear in KEEP_CLEAR:
		if (clear as Rect2).intersects(Rect2(at - size * 0.5, size)):
			return

	debris.append(_put(name, at - size * 0.5, at + size * 0.5, height, tint))


# 잔해를 몇 개씩 치운다. 남은 개수를 돌려준다.
func clear_debris_step(count: int) -> int:
	for i in range(mini(count, debris.size())):
		view._remove_item(debris.pop_back())

	return debris.size()


func clear_all() -> void:
	for k in keys:
		view._remove_item(k)

	for k in debris:
		view._remove_item(k)

	keys.clear()
	debris.clear()
