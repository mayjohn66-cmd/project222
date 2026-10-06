class_name OpeningCityBackdrop
extends RefCounted
## 새 게임 프롤로그의 "익숙한 도시 거리". 가게 바깥을 현대 거리처럼 보이게 하는 임시 입방체 장식이다(새 그림 파일 없음).
## 숲(풀·나무·꽃)은 숨겨 두었다가 `show_forest()`에서 한꺼번에 되돌린다. 모든 항목 이름은 `cut_` 로 시작해
## 매장 벽(`wall`)·마을 물체 정리 코드와 섞이지 않는다. 배치 수치는 아래 상수로 조정한다.

const KEY_PREFIX := "cut_"
const NATURE_PREFIXES := ["tuft", "bush", "tree", "puddle"]

# 가게 칸 사각형 바깥으로 얼마나 떨어져 거리를 놓을지(칸 단위). 보이는 범위가 가게 중심 ±9칸쯤이다.
const SIDEWALK_GAP := 0.3
const SIDEWALK_WIDTH := 1.3
const ROAD_WIDTH := 3.6
const STREET_LENGTH := 14.0       # 가게 모서리에서 거리 양쪽으로 뻗는 길이
const BUILDING_GAP := 1.2         # 건너편 인도와 건물 사이
const BUILDING_MIN_BLOCKS := 3.0
const BUILDING_MAX_BLOCKS := 7.0

const ASPHALT := Color(0.42, 0.43, 0.48)
const CONCRETE := Color(0.95, 0.96, 1.0)
const CURB := Color(1.0, 1.0, 1.0)
const LANE := Color(2.4, 2.3, 1.8)
const LAMP_POLE := Color(0.3, 0.32, 0.36)
const LAMP_LIGHT := Color(1.0, 0.92, 0.62)

# 표면 질감이 어두워 곱해지는 색을 1보다 크게 잡아야 실제로는 선명하게 보인다.
const CAR_COLORS := [Color(2.2, 0.55, 0.5), Color(0.6, 1.2, 2.2), Color(2.2, 2.1, 1.9), Color(0.9, 1.7, 1.0)]
const CAR_CABIN := Color(0.7, 0.9, 1.2)
const BUILDING_TINTS := [Color(0.95, 0.82, 0.74), Color(0.78, 0.82, 0.92), Color(0.96, 0.9, 0.74), Color(0.72, 0.84, 0.78), Color(0.88, 0.76, 0.86)]

var view: Node                          # StoreView3D
var keys: Array[String] = []
var cars: Array[Dictionary] = []        # {body, cabin, axis, lane, pos, speed, length}
var _nature: Array[String] = []
var _ground_saved: Dictionary = {}      # 지면 재질 → {albedo, normal, tint}
var _built: bool = false
var _ground_check: float = 0.0


func _init(store_view: Node) -> void:
	view = store_view


func built() -> bool:
	return _built


# ---------------------------------------------------------------- 만들기

func build() -> void:
	if _built or view == null or view.floor_node == null:
		return

	_built = true
	var rect: Rect2i = view.floor_node.get_store_rect()
	var x0: float = float(rect.position.x) - 0.5
	var y0: float = float(rect.position.y) - 0.5
	var x1: float = float(rect.end.x) - 0.5
	var y1: float = float(rect.end.y) - 0.5
	_hide_nature()
	_recolor_ground(true)

	# 남쪽(+y, 화면 왼쪽 아래)과 동쪽(+x, 화면 오른쪽 아래)으로 길이 하나씩 뻗는 'ㄱ'자 교차로 거리.
	var south_walk_y: float = y1 + SIDEWALK_GAP
	var south_road_y: float = south_walk_y + SIDEWALK_WIDTH
	var far_walk_y: float = south_road_y + ROAD_WIDTH
	var east_walk_x: float = x1 + SIDEWALK_GAP
	var east_road_x: float = east_walk_x + SIDEWALK_WIDTH
	var far_walk_x: float = east_road_x + ROAD_WIDTH

	var west: float = x0 - STREET_LENGTH
	var east: float = far_walk_x + SIDEWALK_WIDTH + 2.0
	var north: float = y0 - STREET_LENGTH
	var south: float = far_walk_y + SIDEWALK_WIDTH + 2.0

	# 인도 → 도로(남쪽 가로 길, 동쪽 세로 길) → 건너편 인도
	_slab("walk_s1", Vector2(west, south_walk_y), Vector2(east, south_road_y), 0.16, CURB)
	_slab("road_s", Vector2(west, south_road_y), Vector2(east, far_walk_y), 0.06, ASPHALT)
	_slab("walk_s2", Vector2(west, far_walk_y), Vector2(east, far_walk_y + SIDEWALK_WIDTH), 0.16, CURB)
	_slab("walk_e1", Vector2(east_walk_x, north), Vector2(east_road_x, south_walk_y), 0.16, CURB)
	_slab("road_e", Vector2(east_road_x, north), Vector2(far_walk_x, south_road_y), 0.06, ASPHALT)
	_slab("walk_e2", Vector2(far_walk_x, north), Vector2(far_walk_x + SIDEWALK_WIDTH, south_road_y), 0.16, CURB)

	# 중앙선(점선)
	var mid_y: float = south_road_y + ROAD_WIDTH * 0.5
	var step: float = 2.0
	var x: float = west + 1.0
	var n: int = 0

	while x < east - 2.0:
		_slab("lane_s%d" % n, Vector2(x, mid_y - 0.07), Vector2(x + 1.1, mid_y + 0.07), 0.09, LANE)
		x += step
		n += 1

	var mid_x: float = east_road_x + ROAD_WIDTH * 0.5
	var y: float = north + 1.0
	n = 0

	while y < south_road_y - 1.0:
		_slab("lane_e%d" % n, Vector2(mid_x - 0.07, y), Vector2(mid_x + 0.07, y + 1.1), 0.09, LANE)
		y += step
		n += 1

	# 가로등: 인도 가장자리에 4칸 간격
	var lamp_n: int = 0
	var lx: float = west + 2.5

	while lx < east - 3.0:
		if lx < x0 - 1.0 or lx > east_walk_x + 0.5:
			_lamp("lamp_s%d" % lamp_n, Vector2(lx, south_walk_y + 0.3))
			lamp_n += 1

		lx += 5.0

	var ly: float = north + 2.5

	while ly < south_walk_y - 2.0:
		_lamp("lamp_e%d" % lamp_n, Vector2(east_walk_x + 0.3, ly))
		lamp_n += 1
		ly += 5.0

	# 건물: 건너편(남쪽 줄·동쪽 줄)과 가게 뒤쪽·왼쪽 줄. 높이와 색을 바꿔 가며 이어 붙인다.
	_building_row("bs", Vector2(west, far_walk_y + SIDEWALK_WIDTH + BUILDING_GAP), Vector2(east, south + 4.0), true, 11)
	_building_row("be", Vector2(far_walk_x + SIDEWALK_WIDTH + BUILDING_GAP, north), Vector2(east + 8.0, south_road_y), false, 23)
	_building_row("bn", Vector2(west, y0 - 11.0), Vector2(east, y0 - 7.0), true, 37)
	_building_row("bw", Vector2(x0 - 11.0, y0 - 7.0), Vector2(x0 - 7.0, far_walk_y), false, 41)

	# 달리는 차: 남쪽 길 두 대(반대 방향), 동쪽 길 한 대
	var lane_a: float = south_road_y + ROAD_WIDTH * 0.25
	var lane_b: float = south_road_y + ROAD_WIDTH * 0.75
	_car("car0", "x", lane_a, west + 3.0, 4.2, 0)
	_car("car1", "x", lane_b, east - 3.0, -3.4, 1)
	_car("car2", "y", east_road_x + ROAD_WIDTH * 0.25, north + 4.0, 3.6, 2)
	_car("car3", "x", lane_a, west - 12.0, 5.0, 3)
	cars[0]["wrap"] = Vector2(west - 2.0, east + 2.0)
	cars[1]["wrap"] = Vector2(west - 2.0, east + 2.0)
	cars[2]["wrap"] = Vector2(north - 2.0, south_road_y + 2.0)
	cars[3]["wrap"] = Vector2(west - 2.0, east + 2.0)


func _key(name: String) -> String:
	var k: String = KEY_PREFIX + name
	keys.append(k)
	return k


func _slab(name: String, lo: Vector2, hi: Vector2, height_blocks: float, tint: Color, kind: String = "tile") -> void:
	view._set_item(_key(name), lo, hi, height_blocks, kind, tint, "")


func _lamp(name: String, at: Vector2) -> void:
	view._set_item(_key(name + "p"), at, at + Vector2(0.14, 0.14), 3.6, "tile", LAMP_POLE, "")
	view._set_item(_key(name + "h"), at + Vector2(-0.12, -0.12), at + Vector2(0.4, 0.26), 0.22, "tile", LAMP_LIGHT, "", 3.6)


func _building_row(name: String, lo: Vector2, hi: Vector2, along_x: bool, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var span: float = (hi.x - lo.x) if along_x else (hi.y - lo.y)
	var at: float = 0.0
	var index: int = 0

	while at < span - 1.5:
		var width: float = rng.randf_range(4.0, 7.0)
		width = minf(width, span - at)
		var height_blocks: float = rng.randf_range(BUILDING_MIN_BLOCKS, BUILDING_MAX_BLOCKS)
		var tint: Color = BUILDING_TINTS[rng.randi() % BUILDING_TINTS.size()]
		var a: Vector2
		var b: Vector2

		if along_x:
			a = Vector2(lo.x + at, lo.y)
			b = Vector2(lo.x + at + width, hi.y)
		else:
			a = Vector2(lo.x, lo.y + at)
			b = Vector2(hi.x, lo.y + at + width)

		var kind: String = "brick" if rng.randf() < 0.5 else "tile"
		view._set_item(_key("%s%d" % [name, index]), a, b, height_blocks, kind, tint, "")
		# 가게 앞 창처럼 보이는 어두운 띠(길 쪽 면을 살짝 덮는 얇은 상자)
		var band_a: Vector2 = a
		var band_b: Vector2 = b

		if along_x:
			band_a = Vector2(a.x + 0.5, a.y - 0.05)
			band_b = Vector2(b.x - 0.5, a.y + 0.12)
		else:
			band_a = Vector2(a.x - 0.05, a.y + 0.5)
			band_b = Vector2(a.x + 0.12, b.y - 0.5)

		view._set_item(_key("%s%dw" % [name, index]), band_a, band_b, 1.4, "tile", Color(0.18, 0.24, 0.3), "", 1.0)
		at += width + 0.2
		index += 1


func _car(name: String, axis: String, lane: float, start: float, speed: float, color_index: int) -> void:
	var length: float = 2.2
	var width: float = 1.0
	var color: Color = CAR_COLORS[color_index % CAR_COLORS.size()]
	var info: Dictionary = {"body": _key(name + "b"), "cabin": _key(name + "c"), "axis": axis, "lane": lane, "pos": start, "speed": speed, "length": length, "width": width, "color": color}
	cars.append(info)
	_place_car(info)


func _place_car(info: Dictionary) -> void:
	var axis: String = str(info["axis"])
	var p: float = float(info["pos"])
	var lane: float = float(info["lane"])
	var length: float = float(info["length"])
	var width: float = float(info["width"])
	var a: Vector2
	var b: Vector2
	var ca: Vector2
	var cb: Vector2

	if axis == "x":
		a = Vector2(p, lane - width * 0.5)
		b = Vector2(p + length, lane + width * 0.5)
		ca = Vector2(p + length * 0.25, lane - width * 0.4)
		cb = Vector2(p + length * 0.75, lane + width * 0.4)
	else:
		a = Vector2(lane - width * 0.5, p)
		b = Vector2(lane + width * 0.5, p + length)
		ca = Vector2(lane - width * 0.4, p + length * 0.25)
		cb = Vector2(lane + width * 0.4, p + length * 0.75)

	var body_key: String = str(info["body"])
	var cabin_key: String = str(info["cabin"])

	if not view._items.has(body_key):
		view._set_item(body_key, a, b, 0.55, "tile", info["color"], "", 0.12)
		view._set_item(cabin_key, ca, cb, 0.5, "tile", CAR_CABIN, "", 0.67)
		return

	_move_item(body_key, a, b)
	_move_item(cabin_key, ca, cb)


# 이미 만든 항목을 새 바닥 사각형으로 옮긴다(정렬이 쓰는 min/max/center도 함께 갱신).
func _move_item(key: String, lo: Vector2, hi: Vector2) -> void:
	var item: Dictionary = view._items[key]
	var mn: Vector3 = item["min"]
	var mx: Vector3 = item["max"]
	var center := Vector3((lo.x + hi.x) * 0.5, (item["center"] as Vector3).y, (lo.y + hi.y) * 0.5)
	item["min"] = Vector3(lo.x, lo.y, mn.z)
	item["max"] = Vector3(hi.x, hi.y, mx.z)
	item["center"] = center

	for node_key in ["mesh", "id_mesh"]:
		(item[node_key] as Node3D).position = center


# ---------------------------------------------------------------- 매 프레임

func tick(delta: float) -> void:
	# 마을 지면은 한 박자 늦게(또는 다시) 만들어질 수 있어, 새 재질이 보이면 도시 색을 다시 입힌다.
	_ground_check -= delta

	if _ground_check <= 0.0:
		_ground_check = 0.25
		_recolor_ground(true)
		_hide_nature()

	for car in cars:
		var wrap: Vector2 = car.get("wrap", Vector2(-1000.0, 1000.0))
		var p: float = float(car["pos"]) + float(car["speed"]) * delta

		if p > wrap.y:
			p = wrap.x
		elif p < wrap.x:
			p = wrap.y

		car["pos"] = p
		_place_car(car)


# ---------------------------------------------------------------- 숲으로 되돌리기

func show_forest() -> void:
	for k in keys:
		view._remove_item(k)

	keys.clear()
	cars.clear()
	_recolor_ground(false)

	for k in view._items.keys():
		var name: String = str(k)

		for prefix in NATURE_PREFIXES:
			if name.begins_with(prefix):
				(view._items[k]["mesh"] as Node3D).visible = true
				# 풀 다발은 윤곽선 판에 사각형이 찍히지 않도록 원래 꺼 두므로 그 설정은 건드리지 않는다
				if not name.begins_with("tuft"):
					(view._items[k]["id_mesh"] as Node3D).visible = true

				break

	_nature.clear()
	_built = false


# 숲의 풀·나무·꽃을 숨긴다. 마을 물체는 한 박자 늦게 만들어지므로 주기적으로 불러 새로 생긴 것도 숨긴다.
func _hide_nature() -> void:
	for k in view._items.keys():
		var name: String = str(k)

		for prefix in NATURE_PREFIXES:
			if name.begins_with(prefix):
				var item: Dictionary = view._items[k]

				# 같은 이름으로 다시 만들어진 물체도 있으므로 이름이 아니라 실제 보이는 상태를 본다
				if (item["mesh"] as Node3D).visible:
					(item["mesh"] as Node3D).visible = false
					(item["id_mesh"] as Node3D).visible = false

				if not _nature.has(name):
					_nature.append(name)

				break


# 풀·길 바닥 질감을 도시 콘크리트로 바꿨다가(`city=true`) 되돌린다. 지면 재질이 새로 만들어졌으면 그것도 다시 칠한다.
func _recolor_ground(city: bool) -> void:
	if view.village == null:
		return

	for kind in view.village._ground.keys():
		var material: ShaderMaterial = view.village._ground[kind]["material"]
		var saved: Dictionary = _ground_saved.get(kind, {})

		if city:
			if not saved.is_empty() and saved["material"] == material:
				continue  # 이미 칠한 재질

			_ground_saved[kind] = {"material": material, "albedo": material.get_shader_parameter("albedo_tex"), "normal": material.get_shader_parameter("normal_tex"), "tint": material.get_shader_parameter("tint")}
			var tile: Dictionary = view._texture_cache.get("tile", {})

			if not tile.is_empty():
				material.set_shader_parameter("albedo_tex", tile["albedo"])
				material.set_shader_parameter("normal_tex", tile["normal"])

			material.set_shader_parameter("tint", CONCRETE)
		elif not saved.is_empty() and saved["material"] == material:
			material.set_shader_parameter("albedo_tex", saved["albedo"])
			material.set_shader_parameter("normal_tex", saved["normal"])
			material.set_shader_parameter("tint", saved["tint"])

	if not city:
		_ground_saved.clear()
