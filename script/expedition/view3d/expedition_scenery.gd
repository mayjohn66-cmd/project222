class_name ExpeditionScenery
extends RefCounted
## 원정 방의 주변 풍경. 방 둘레를 벽 대신 지역에 맞는 자연물·폐허로 두른다(숲 = 나무·덤불·풀, 광산 = 바위·종유석·수정,
## 늪 = 죽은 나무·갈대·웅덩이, 유적 = 무너진 벽·기둥). 뒤쪽 두 변은 빽빽하게, 앞쪽·옆은 낮은 것만 놓아 방 안이 가려지지 않게 한다.
## 같은 모양(템플릿)은 메시·재질을 공유해서 수십 개를 놓아도 가볍다.

var st: ExpeditionStage3D
var _cache: Dictionary = {}
var _half := Vector2(0.5, 0.5)

const EXIT_X: float = 3.5
const GAP := Rect2(2.45, -2.2, 2.1, 2.5)  # 출구 틈(여기엔 아무것도 놓지 않는다)


func _init(stage: ExpeditionStage3D) -> void:
	st = stage


func clear_cache() -> void:
	_cache.clear()


# ---------------------------------------------------------------- 템플릿(공유 메시·재질)

func _tpl_prop(style: String, rule: Dictionary, key: String) -> Dictionary:
	if _cache.has(key):
		return _cache[key]

	var built: Dictionary = VillageAssets.build_prop(style, -_half, _half, rule, st._p)
	var mats: Array = VillageAssets.make_materials(built["specs"])

	for m in mats:
		(m as ShaderMaterial).set_shader_parameter("use_sort", false)

	var t: Dictionary = {"mesh": built["mesh"], "mats": mats}
	_cache[key] = t
	return t


func _tpl_builder(b: VillageAssets.PartBuilder, key: String) -> Dictionary:
	if _cache.has(key):
		return _cache[key]

	var mesh := ArrayMesh.new()
	var specs: Array = b.commit_into(mesh)
	var mats: Array = VillageAssets.make_materials(specs)

	for m in mats:
		(m as ShaderMaterial).set_shader_parameter("use_sort", false)

	var t: Dictionary = {"mesh": mesh, "mats": mats}
	_cache[key] = t
	return t


func _inst(t: Dictionary, pos: Vector2, scale: float, yaw: float, y: float = 0.0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = t["mesh"]

	for i in range((t["mats"] as Array).size()):
		node.set_surface_override_material(i, t["mats"][i])

	node.position = Vector3(pos.x, y, pos.y)
	node.rotation.y = yaw
	node.scale = Vector3.ONE * scale
	st._content.add_child(node)
	return node


# ---------------------------------------------------------------- 배치

func _scatter(rng: RandomNumberGenerator, rects: Array, avoid: Array, count: int, min_dist: float) -> Array:
	var out: Array = []
	var total: float = 0.0

	for r in rects:
		total += (r as Rect2).get_area()

	var tries: int = 0

	while out.size() < count and tries < count * 40:
		tries += 1
		var pick: float = rng.randf() * total
		var rect: Rect2 = rects[0]

		for r in rects:
			pick -= (r as Rect2).get_area()

			if pick <= 0.0:
				rect = r
				break

		var p := Vector2(rng.randf_range(rect.position.x, rect.end.x), rng.randf_range(rect.position.y, rect.end.y))
		var ok: bool = true

		for a in avoid:
			if (a as Rect2).has_point(p):
				ok = false
				break

		if not ok:
			continue

		for q in out:
			if p.distance_to(q) < min_dist:
				ok = false
				break

		if ok:
			out.append(p)

	return out


func _back_rects() -> Array:
	return [Rect2(-1.9, -1.9, 10.3, 1.75), Rect2(-1.9, -0.15, 1.75, 8.55)]


func _front_rects() -> Array:
	return [Rect2(8.25, -1.5, 1.0, 9.6), Rect2(-0.5, 8.25, 9.0, 1.0)]


func _edge_rects() -> Array:
	# 방 안쪽 가장자리(뒤쪽 두 변을 따라 폭 0.8): 부드러운 경계용 낮은 풀·잔돌
	return [Rect2(0.1, 0.1, 7.8, 0.8), Rect2(0.1, 0.9, 0.8, 7.0)]


# ---------------------------------------------------------------- 지역별

func build(theme_id: String, rng: RandomNumberGenerator, model: RefCounted = null) -> void:
	_build_surroundings(theme_id, rng)
	_build_floor_decor(theme_id, rng, model)


func _build_surroundings(theme_id: String, rng: RandomNumberGenerator) -> void:
	match theme_id:
		"mine":
			_build_mine(rng)
		"swamp":
			_build_swamp(rng)
		"hidden_ruins":
			_build_ruins(rng)
		_:
			_build_forest(rng)


func _yaw(rng: RandomNumberGenerator) -> float:
	return rng.randf() * TAU


# 주변 풍경은 "투명 가벽 + 지형 오브젝트" 방식이다. 방 가장자리는 보이지 않는 벽(이동 한계)이 막고, 그 바깥을 지역 지형물로 꾸민다.
# 일렬로 세우면 인위적이라서, 뒤쪽 두 변을 불규칙한 간격으로 걸으며 점을 뽑고 깊이도 물결치듯 흔든다.
# 종류·크기·방향을 섞고 가끔 빈틈과 작은 무리(군락)를 만든다. 출구 틈 구간은 비운다.
func _walk_border(rng: RandomNumberGenerator, base: float, step_min: float, step_max: float, wave: float, skip: float = 0.0) -> Array:
	var out: Array = []
	var phase: float = rng.randf() * TAU
	var x: float = -1.6 + rng.randf() * step_max

	while x < 9.2:
		if not (x > GAP.position.x and x < GAP.end.x) and rng.randf() >= skip:
			out.append({"pos": Vector2(x, base + sin(x * 0.8 + phase) * wave + rng.randf_range(-wave, wave) * 0.5), "axis": 0})

		x += rng.randf_range(step_min, step_max)

	var z: float = 0.2 + rng.randf() * step_max

	while z < 9.2:
		if rng.randf() >= skip:
			out.append({"pos": Vector2(base + sin(z * 0.8 + phase) * wave + rng.randf_range(-wave, wave) * 0.5, z), "axis": 1})

		z += rng.randf_range(step_min, step_max)

	return out


func _pick(rng: RandomNumberGenerator, arr: Array):
	return arr[rng.randi() % arr.size()]


func _build_forest(rng: RandomNumberGenerator) -> void:
	# 뒤 숲: 큰 나무, 앞 숲: 중간 나무, 가장자리: 덤불·풀. 간격과 크기가 제각각이라 자연스러운 숲 가장자리가 된다.
	for pt in _walk_border(rng, -2.6, 1.3, 2.1, 0.4, 0.05):
		var v: String = _pick(rng, ["big_oak", "pine", "round", "big_oak", "birch"])
		_inst(_tpl_prop("tree", {"variant": v}, "f_tree_" + v), pt["pos"], rng.randf_range(1.15, 1.55), _yaw(rng))

	for pt in _walk_border(rng, -1.3, 1.0, 1.9, 0.35, 0.12):
		var v2: String = _pick(rng, ["pine", "round", "birch", "round"])
		_inst(_tpl_prop("tree", {"variant": v2}, "f_tree_" + v2), pt["pos"], rng.randf_range(0.8, 1.15), _yaw(rng))

	var grass: Dictionary = _tpl_grass(Color(0.28, 0.58, 0.26), Color(0.42, 0.74, 0.34), "f_grass_b", 0.5)

	for pt in _walk_border(rng, -0.4, 0.7, 1.4, 0.3, 0.1):
		if rng.randf() < 0.55:
			var bv: String = _pick(rng, ["", "berry", ""])
			_inst(_tpl_prop("flower_bush", {"variant": bv}, "f_bush_" + bv), pt["pos"], rng.randf_range(0.9, 1.6), _yaw(rng))
		else:
			_inst(grass, pt["pos"], rng.randf_range(0.9, 1.4), _yaw(rng))

		if rng.randf() < 0.25:
			_inst(grass, pt["pos"] + Vector2(rng.randf_range(-0.4, 0.4), rng.randf_range(0.2, 0.6)), rng.randf_range(0.7, 1.1), _yaw(rng))

	# 출구 양옆의 큰 나무 둘(숲의 문)
	_inst(_tpl_prop("tree", {"variant": "big_oak"}, "f_tree_big_oak"), Vector2(2.1, -0.95), 1.55, 0.0)
	_inst(_tpl_prop("tree", {"variant": "big_oak"}, "f_tree_big_oak"), Vector2(4.9, -0.95), 1.55, 2.0)
	_forest_path(rng)
	_exit_forest()


func _forest_path(rng: RandomNumberGenerator) -> void:
	var b := VillageAssets.PartBuilder.new()
	var dirt: Dictionary = VillageAssets._noise_spec(int(st._p["ts"]), Color(0.46, 0.34, 0.22), Color(0.58, 0.45, 0.3), "forest_path", 61, Color.WHITE, 0.12)
	var part: SurfaceTool = b.new_part(dirt, Vector3(-1, 0, -1), Vector3(1, 1, 1))
	var z: float = 8.4

	while z > -1.8:
		var cx: float = 3.5 + sin(z * 0.9) * 0.2
		var w: float = 1.1
		BuildingMesh._quad(part, Vector3(cx - w * 0.5, 0.014, z), Vector3(cx + w * 0.5, 0.014, z), Vector3(cx + w * 0.5, 0.014, z + 0.75), Vector3(cx - w * 0.5, 0.014, z + 0.75), Vector3.UP, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
		z -= 0.62

	st._node(b)


func _build_mine(rng: RandomNumberGenerator) -> void:
	# 큰 암벽(뒤) + 크고 작은 바위가 뭉친 언덕(앞) + 군데군데 수정·종유석. 바위끼리 겹치게 놓아 하나의 덩어리로 보인다.
	for pt in _walk_border(rng, -2.2, 1.4, 2.3, 0.4, 0.05):
		_inst(_tpl_prop("rock", {}, "m_rock"), pt["pos"], rng.randf_range(2.6, 3.6), _yaw(rng))

	var lights: int = 0

	for pt in _walk_border(rng, -0.8, 0.9, 1.7, 0.35, 0.1):
		_inst(_tpl_prop("rock", {}, "m_rock"), pt["pos"], rng.randf_range(1.0, 2.4), _yaw(rng))

		if rng.randf() < 0.5:
			_inst(_tpl_prop("rock", {}, "m_rock"), pt["pos"] + Vector2(rng.randf_range(-0.5, 0.5), rng.randf_range(0.1, 0.5)), rng.randf_range(0.6, 1.2), _yaw(rng))

		var roll: float = rng.randf()

		if roll < 0.2:
			var cp: Vector2 = pt["pos"] + Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(0.2, 0.55))
			_inst(_tpl_crystal(Color(0.35, 0.85, 0.95), "m_crystal"), cp, rng.randf_range(0.8, 1.3), _yaw(rng))

			if lights < 3:
				lights += 1
				st.add_glow_light(Vector3(cp.x, 0.7, cp.y), Color(0.45, 0.85, 1.0), 0.9, 3.4)
		elif roll < 0.4:
			_inst(_tpl_stalagmite(Color(0.5, 0.5, 0.58), "m_stal"), pt["pos"] + Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(0.2, 0.5)), rng.randf_range(0.8, 1.3), _yaw(rng))

	_inst(_tpl_prop("rock", {}, "m_rock"), Vector2(2.0, -0.8), 3.2, 0.0)
	_inst(_tpl_prop("rock", {}, "m_rock"), Vector2(5.0, -0.8), 3.0, 2.0)
	_exit_mine()


func _build_swamp(rng: RandomNumberGenerator) -> void:
	# 군데군데 고인 물, 갈대 무리, 크기가 제각각인 죽은 나무.
	var wb := VillageAssets.PartBuilder.new()
	var water: Dictionary = st._flat(Color(0.2, 0.38, 0.36), "swamp_water", 0.12)
	var wp: SurfaceTool = wb.new_part(water, Vector3(-1, 0, -1), Vector3(1, 1, 1))

	for pt in _walk_border(rng, -0.9, 1.4, 2.4, 0.3, 0.1):
		var pr: float = rng.randf_range(0.5, 0.95)
		VillageAssets.oct_st(wp, pt["pos"].x, pt["pos"].y, pr, 0.0, 0.025, pr * 0.97)

	st._node(wb)
	var reeds: Dictionary = _tpl_reeds("s_reeds")

	for pt in _walk_border(rng, -0.45, 0.6, 1.3, 0.35, 0.15):
		_inst(reeds, pt["pos"], rng.randf_range(0.8, 1.35), _yaw(rng))

	var i: int = 0

	for pt in _walk_border(rng, -1.7, 1.3, 2.3, 0.4, 0.1):
		_inst(_tpl_prop("tree", {"variant": "dead"}, "s_dead"), pt["pos"], rng.randf_range(1.0, 1.5), _yaw(rng))
		i += 1

	for pt in _walk_border(rng, -2.8, 1.4, 2.4, 0.4, 0.05):
		_inst(_tpl_prop("tree", {"variant": "dead"}, "s_dead"), pt["pos"], rng.randf_range(1.3, 1.8), _yaw(rng))

	_inst(_tpl_prop("tree", {"variant": "dead"}, "s_dead"), Vector2(2.2, -0.9), 1.5, 0.4)
	_inst(_tpl_prop("tree", {"variant": "dead"}, "s_dead"), Vector2(4.8, -0.9), 1.4, 2.0)

	for k in range(2):
		st.add_wisp(Vector3(rng.randf_range(0.0, 7.5), 0.8, rng.randf_range(-0.8, 0.5)), Color(0.6, 1.0, 0.7))

	_exit_swamp()


func _build_ruins(rng: RandomNumberGenerator) -> void:
	# 무너진 담 조각(길이·높이·방향이 제각각), 부러진 기둥, 흩어진 돌무더기. 군데군데 이끼 낀 풀.
	var rubble: Dictionary = _tpl_pebbles(Color(0.62, 0.58, 0.7), "r_rubble_b")
	var moss: Dictionary = _tpl_grass(Color(0.3, 0.5, 0.3), Color(0.4, 0.62, 0.36), "r_grass_b", 0.4)

	for pt in _walk_border(rng, -1.9, 1.5, 2.6, 0.35, 0.2):
		var yaw_w: float = (0.0 if pt["axis"] == 0 else PI * 0.5) + rng.randf_range(-0.3, 0.3)
		_inst(_tpl_ruin_wall(2, "r_wall"), pt["pos"], rng.randf_range(1.0, 1.3), yaw_w)

	for pt in _walk_border(rng, -0.7, 1.3, 2.4, 0.3, 0.25):
		var yaw_f: float = (0.0 if pt["axis"] == 0 else PI * 0.5) + rng.randf_range(-0.35, 0.35)
		_inst(_tpl_ruin_wall(int(rng.randi() % 2), "r_wall"), pt["pos"], rng.randf_range(0.8, 1.05), yaw_f)

		if rng.randf() < 0.5:
			_inst(rubble, pt["pos"] + Vector2(rng.randf_range(-0.6, 0.6), rng.randf_range(0.2, 0.7)), rng.randf_range(0.8, 1.3), _yaw(rng))

		if rng.randf() < 0.4:
			_inst(moss, pt["pos"] + Vector2(rng.randf_range(-0.5, 0.5), rng.randf_range(0.2, 0.6)), rng.randf_range(0.7, 1.1), _yaw(rng))

	var cols: Array = []

	for pt in _walk_border(rng, -1.2, 2.2, 3.6, 0.4, 0.15):
		_inst(_tpl_column(int(rng.randi() % 2), "r_col"), pt["pos"], rng.randf_range(0.9, 1.15), _yaw(rng))
		cols.append(pt["pos"])

	for k in range(mini(3, cols.size())):
		st.add_glow_light(Vector3(cols[k].x, 0.9, cols[k].y), Color(0.75, 0.55, 1.0), 0.8, 3.2)

	_exit_ruins()



# ---------------------------------------------------------------- 출구(닫힘/열림)

func _gate_node(b: VillageAssets.PartBuilder) -> MeshInstance3D:
	return st._node(b)


func _glow_quad(color: Color, w: float, h: float, name: String) -> MeshInstance3D:
	var b := VillageAssets.PartBuilder.new()
	var glow: Dictionary = st._flat(color, name, 1.0)
	var part: SurfaceTool = b.new_part(glow, Vector3(-1, 0, -1), Vector3(1, 1, 1))
	BuildingMesh._quad(part, Vector3(EXIT_X - w * 0.5, 0, -0.2), Vector3(EXIT_X + w * 0.5, 0, -0.2), Vector3(EXIT_X + w * 0.5, h, -0.2), Vector3(EXIT_X - w * 0.5, h, -0.2), Vector3(0, 0, 1), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0))
	# 바닥에 번지는 빛
	BuildingMesh._quad(part, Vector3(EXIT_X - w * 0.6, 0.02, -0.2), Vector3(EXIT_X + w * 0.6, 0.02, -0.2), Vector3(EXIT_X + w * 0.6, 0.02, 1.0), Vector3(EXIT_X - w * 0.6, 0.02, 1.0), Vector3.UP, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
	return st._node(b)


func _exit_forest() -> void:
	var b := VillageAssets.PartBuilder.new()
	var thorn: Dictionary = st._flat(Color(0.28, 0.2, 0.14), "thorn")
	var leaf: Dictionary = st._flat(Color(0.2, 0.36, 0.18), "thorn_leaf")
	var tp: SurfaceTool = b.new_part(thorn, Vector3(-1, 0, -1), Vector3(1, 1, 1))
	var lp: SurfaceTool = b.new_part(leaf, Vector3(-1, 0, -1), Vector3(1, 1, 1))
	var rng := RandomNumberGenerator.new()
	rng.seed = 91

	for i in range(15):
		var x: float = EXIT_X - 0.8 + float(i) / 14.0 * 1.6 + rng.randf_range(-0.05, 0.05)
		var z: float = -0.25 + rng.randf_range(-0.15, 0.2)
		VillageAssets.oct_st(tp, x, z, 0.05, 0.0, 0.5 + rng.randf() * 0.55, 0.0)
		VillageAssets.dome_st(lp, x + rng.randf_range(-0.1, 0.1), z, 0.14, 0.12, 0.3 + rng.randf() * 0.15, 2, 6)

	st._exit_bars = st._node(b)
	st._exit_glow = _glow_quad(Color(0.82, 1.0, 0.62), 1.3, 1.5, "forest_light")
	st.add_glow_light(Vector3(EXIT_X, 0.8, 0.2), Color(0.9, 1.0, 0.7), 0.9, 3.4)


func _exit_mine() -> void:
	var plug := _inst(_tpl_prop("rock", {}, "m_rock"), Vector2(EXIT_X, -0.2), 2.4, 1.0)
	st._exit_bars = plug
	st._exit_glow = _glow_quad(Color(1.0, 0.7, 0.35), 1.2, 1.4, "mine_glow")
	st.add_glow_light(Vector3(EXIT_X, 0.8, 0.2), Color(1.0, 0.7, 0.4), 1.0, 3.4)


func _exit_swamp() -> void:
	var b := VillageAssets.PartBuilder.new()
	var root: Dictionary = st._flat(Color(0.2, 0.15, 0.1), "root")
	var moss: Dictionary = st._flat(Color(0.28, 0.42, 0.24), "root_moss")
	var rp: SurfaceTool = b.new_part(root, Vector3(-1, 0, -1), Vector3(1, 1, 1))
	var mp: SurfaceTool = b.new_part(moss, Vector3(-1, 0, -1), Vector3(1, 1, 1))
	var rng := RandomNumberGenerator.new()
	rng.seed = 93

	for i in range(9):
		var x: float = EXIT_X - 0.8 + float(i) / 8.0 * 1.6
		VillageAssets.box_st(rp, Vector3(x - 0.07, 0.0, -0.35 + rng.randf() * 0.2), Vector3(x + 0.07, 0.55 + rng.randf() * 0.5, -0.2 + rng.randf() * 0.2))
		VillageAssets.dome_st(mp, x, -0.2, 0.17, 0.1, 0.35, 2, 6)

	st._exit_bars = st._node(b)
	st._exit_glow = _glow_quad(Color(0.7, 1.0, 0.8), 1.2, 1.4, "swamp_light")
	st.add_glow_light(Vector3(EXIT_X, 0.8, 0.2), Color(0.7, 1.0, 0.8), 0.8, 3.2)


func _exit_ruins() -> void:
	var b := VillageAssets.PartBuilder.new()
	var stone: Dictionary = VillageAssets.stone_spec(st._p, Color(0.8, 0.76, 0.9), "ruin_arch")
	var rune: Dictionary = st._flat(Color(0.7, 0.45, 1.0), "ruin_rune", 0.9)
	# 폐허의 문: 기둥 둘 + 상인방
	VillageAssets.box(b, "jamb", stone, Vector3(EXIT_X - 0.95, 0, -0.55), Vector3(EXIT_X - 0.65, 1.7, -0.15))
	VillageAssets.box(b, "jamb", stone, Vector3(EXIT_X + 0.65, 0, -0.55), Vector3(EXIT_X + 0.95, 1.55, -0.15))
	VillageAssets.box(b, "lintel", stone, Vector3(EXIT_X - 0.95, 1.5, -0.55), Vector3(EXIT_X + 0.95, 1.8, -0.15))
	VillageAssets.box(b, "keystone", rune, Vector3(EXIT_X - 0.12, 1.55, -0.12), Vector3(EXIT_X + 0.12, 1.75, -0.08))
	st._node(b)
	var door := VillageAssets.PartBuilder.new()
	VillageAssets.box(door, "slab", stone, Vector3(EXIT_X - 0.65, 0, -0.32), Vector3(EXIT_X + 0.65, 1.5, -0.2))
	VillageAssets.box(door, "rune_l", rune, Vector3(EXIT_X - 0.4, 0.3, -0.19), Vector3(EXIT_X - 0.34, 1.2, -0.17))
	VillageAssets.box(door, "rune_r", rune, Vector3(EXIT_X + 0.34, 0.3, -0.19), Vector3(EXIT_X + 0.4, 1.2, -0.17))
	st._exit_bars = st._node(door)
	st._exit_glow = _glow_quad(Color(0.75, 0.5, 1.0), 1.2, 1.5, "ruin_light")
	st.add_glow_light(Vector3(EXIT_X, 0.8, 0.2), Color(0.8, 0.55, 1.0), 1.0, 3.4)


# ---------------------------------------------------------------- 바닥 장식(방 안)

# 방 안 바닥에도 주변 풍경과 같은 종류를 깐다: 낮은 것(풀·꽃·덤불·잔돌·버섯·수정 조각)만 놓아 이동을 막지 않고 시야도 가리지 않는다.
# 시작 지점·출구 길·적·오브젝트·장애물 둘레는 비운다.
func _keepout(model: RefCounted) -> Array:
	var out: Array = [Rect2(2.7, 0.0, 1.6, 2.2), Rect2(2.6, 6.0, 1.8, 2.0)]

	if model == null:
		return out

	out.append(Rect2(model.player_position - Vector2(1.2, 1.2), Vector2(2.4, 2.4)))

	for e in model.enemies:
		out.append(Rect2((e["position"] as Vector2) - Vector2(0.9, 0.9), Vector2(1.8, 1.8)))

	for o in model.obstacles:
		out.append((o as Rect2).grow(0.7))

	if model.gathering_sites.is_empty():
		if str(model.object_kind) != "":
			out.append(Rect2(model.object_position - Vector2(0.9, 0.9), Vector2(1.8, 1.8)))
	else:
		for site in model.gathering_sites:
			out.append(Rect2(Vector2(float(site["x"]), float(site["y"])) - Vector2(0.9, 0.9), Vector2(1.8, 1.8)))

	return out


func _build_floor_decor(theme_id: String, rng: RandomNumberGenerator, model: RefCounted) -> void:
	# 방 안 바닥은 비워 두고(채집·상자 오브젝트와 장애물만), 풀밭 수준의 아주 작은 것만 조금 뿌려 허전함을 던다. 큰 것은 놓지 않는다.
	var field: Array = [Rect2(0.35, 0.35, 7.3, 7.3)]
	var avoid: Array = _keepout(model)

	match theme_id:
		"mine":
			var rubble: Dictionary = _tpl_pebbles(Color(0.5, 0.5, 0.58), "m_rubble")

			for p in _scatter(rng, field, avoid, 9, 0.9):
				_inst(rubble, p, 0.7 + rng.randf() * 0.6, _yaw(rng))
		"swamp":
			var tufts: Dictionary = _tpl_grass(Color(0.3, 0.46, 0.26), Color(0.42, 0.6, 0.34), "s_grass", 0.4)

			for p in _scatter(rng, field, avoid, 12, 0.8):
				_inst(tufts, p, 0.6 + rng.randf() * 0.5, _yaw(rng))

			for p in _scatter(rng, field, avoid, 2, 2.5):
				_inst(_tpl_mushrooms("s_mush"), p, 0.8 + rng.randf() * 0.3, _yaw(rng))
		"hidden_ruins":
			var rubble2: Dictionary = _tpl_pebbles(Color(0.62, 0.58, 0.7), "r_rubble")

			for p in _scatter(rng, field, avoid, 9, 0.9):
				_inst(rubble2, p, 0.7 + rng.randf() * 0.6, _yaw(rng))

			var moss: Dictionary = _tpl_grass(Color(0.3, 0.5, 0.3), Color(0.4, 0.62, 0.36), "r_grass", 0.35)

			for p in _scatter(rng, field, avoid, 5, 1.2):
				_inst(moss, p, 0.6 + rng.randf() * 0.4, _yaw(rng))
		_:
			var grass: Dictionary = _tpl_grass(Color(0.28, 0.58, 0.26), Color(0.42, 0.74, 0.34), "f_grass", 0.45)

			for p in _scatter(rng, field, avoid, 16, 0.7):
				_inst(grass, p, 0.6 + rng.randf() * 0.5, _yaw(rng))

			var flowers: Array = [_tpl_flowers(Color(1.0, 0.85, 0.95), "f_fl_a"), _tpl_flowers(Color(1.0, 0.85, 0.3), "f_fl_b"), _tpl_flowers(Color(0.85, 0.7, 1.0), "f_fl_c")]

			for p in _scatter(rng, field, avoid, 5, 1.3):
				_inst(flowers[rng.randi() % 3], p, 0.7 + rng.randf() * 0.4, _yaw(rng))


func _floor_puddles(rng: RandomNumberGenerator, field: Array, avoid: Array, count: int) -> void:
	var b := VillageAssets.PartBuilder.new()
	var water: Dictionary = st._flat(Color(0.2, 0.38, 0.36), "swamp_water_in", 0.12)
	var wp: SurfaceTool = b.new_part(water, Vector3(-1, 0, -1), Vector3(1, 1, 1))

	for p in _scatter(rng, field, avoid, count, 2.0):
		var r: float = 0.4 + rng.randf() * 0.35
		VillageAssets.oct_st(wp, p.x, p.y, r, 0.0, 0.02, r * 0.97)

	st._node(b)


func _tpl_flowers(color: Color, key: String) -> Dictionary:
	if _cache.has(key):
		return _cache[key]

	var b := VillageAssets.PartBuilder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var stem: SurfaceTool = b.new_part(st._flat(Color(0.3, 0.6, 0.28), key + "_s"), Vector3(-1, 0, -1), Vector3(1, 1, 1))
	var head: SurfaceTool = b.new_part(st._flat(color, key + "_h", 0.2), Vector3(-1, 0, -1), Vector3(1, 1, 1))

	for i in range(6):
		var x: float = rng.randf_range(-0.22, 0.22)
		var z: float = rng.randf_range(-0.22, 0.22)
		var h: float = 0.22 + rng.randf() * 0.18
		VillageAssets.oct_st(stem, x, z, 0.02, 0.0, h, 0.0)
		VillageAssets.dome_st(head, x, z, 0.06, h - 0.02, h + 0.07, 2, 6)

	return _tpl_builder(b, key)


func _tpl_mushrooms(key: String) -> Dictionary:
	if _cache.has(key):
		return _cache[key]

	var b := VillageAssets.PartBuilder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var stem: SurfaceTool = b.new_part(st._flat(Color(0.9, 0.88, 0.8), key + "_s"), Vector3(-1, 0, -1), Vector3(1, 1, 1))
	var cap: SurfaceTool = b.new_part(st._flat(Color(0.8, 0.3, 0.3), key + "_c"), Vector3(-1, 0, -1), Vector3(1, 1, 1))

	for i in range(3):
		var x: float = rng.randf_range(-0.15, 0.15)
		var z: float = rng.randf_range(-0.15, 0.15)
		var h: float = 0.1 + rng.randf() * 0.1
		VillageAssets.box_st(stem, Vector3(x - 0.02, 0.0, z - 0.02), Vector3(x + 0.02, h, z + 0.02))
		VillageAssets.dome_st(cap, x, z, 0.07, h - 0.02, h + 0.07, 2, 6)

	return _tpl_builder(b, key)


# ---------------------------------------------------------------- 템플릿 모양

func _tpl_grass(c1: Color, c2: Color, key: String, height: float) -> Dictionary:
	if _cache.has(key):
		return _cache[key]

	var b := VillageAssets.PartBuilder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var sts: Array = [b.new_part(st._flat(c1, key + "_a"), Vector3(-1, 0, -1), Vector3(1, 1, 1)), b.new_part(st._flat(c2, key + "_b"), Vector3(-1, 0, -1), Vector3(1, 1, 1))]

	for i in range(11):
		var a: float = rng.randf() * TAU
		var d: float = sqrt(rng.randf()) * 0.3
		VillageAssets.oct_st(sts[i % 2], cos(a) * d, sin(a) * d, 0.035, 0.0, height * (0.5 + rng.randf() * 0.6), 0.0)

	return _tpl_builder(b, key)


func _tpl_stalagmite(color: Color, key: String) -> Dictionary:
	if _cache.has(key):
		return _cache[key]

	var b := VillageAssets.PartBuilder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var sp: SurfaceTool = b.new_part(VillageAssets._noise_spec(int(st._p["ts"]), color, color.lightened(0.18), key, 71, Color.WHITE, 0.12), Vector3(-1, 0, -1), Vector3(1, 1, 1))

	for i in range(3):
		var a: float = float(i) * 2.1 + rng.randf()
		VillageAssets.oct_st(sp, cos(a) * 0.15, sin(a) * 0.15, 0.13 + rng.randf() * 0.07, 0.0, 0.5 + rng.randf() * 0.9, 0.0)

	return _tpl_builder(b, key)


func _tpl_crystal(color: Color, key: String) -> Dictionary:
	if _cache.has(key):
		return _cache[key]

	var b := VillageAssets.PartBuilder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var glow: SurfaceTool = b.new_part(st._flat(color, key + "_g", 0.85), Vector3(-1, 0, -1), Vector3(1, 1, 1))
	var dark: SurfaceTool = b.new_part(st._flat(color.darkened(0.4), key + "_d", 0.25), Vector3(-1, 0, -1), Vector3(1, 1, 1))

	for i in range(5):
		var a: float = float(i) * 1.3 + rng.randf()
		VillageAssets.oct_st(glow if i % 2 == 0 else dark, cos(a) * 0.14, sin(a) * 0.14, 0.09 + rng.randf() * 0.05, 0.0, 0.4 + rng.randf() * 0.7, 0.0)

	return _tpl_builder(b, key)


func _tpl_pebbles(color: Color, key: String) -> Dictionary:
	if _cache.has(key):
		return _cache[key]

	var b := VillageAssets.PartBuilder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var sp: SurfaceTool = b.new_part(VillageAssets._noise_spec(int(st._p["ts"]), color, color.lightened(0.2), key, 73, Color.WHITE, 0.12), Vector3(-1, 0, -1), Vector3(1, 1, 1))

	for i in range(6):
		VillageAssets.dome_st(sp, rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3), 0.06 + rng.randf() * 0.1, 0.0, 0.05 + rng.randf() * 0.1, 2, 6)

	return _tpl_builder(b, key)


func _tpl_reeds(key: String) -> Dictionary:
	if _cache.has(key):
		return _cache[key]

	var b := VillageAssets.PartBuilder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var sts: Array = [b.new_part(st._flat(Color(0.72, 0.7, 0.4), key + "_a"), Vector3(-1, 0, -1), Vector3(1, 1, 1)), b.new_part(st._flat(Color(0.5, 0.62, 0.32), key + "_b"), Vector3(-1, 0, -1), Vector3(1, 1, 1))]
	var tip: SurfaceTool = b.new_part(st._flat(Color(0.45, 0.3, 0.18), key + "_t"), Vector3(-1, 0, -1), Vector3(1, 1, 1))

	for i in range(14):
		var a: float = rng.randf() * TAU
		var d: float = sqrt(rng.randf()) * 0.3
		var h: float = 0.6 + rng.randf() * 0.6
		VillageAssets.oct_st(sts[i % 2], cos(a) * d, sin(a) * d, 0.03, 0.0, h, 0.012)

		if i % 3 == 0:
			VillageAssets.oct_st(tip, cos(a) * d, sin(a) * d, 0.04, h - 0.02, h + 0.13, 0.03)

	return _tpl_builder(b, key)


func _tpl_ruin_wall(variant: int, key: String) -> Dictionary:
	var k: String = "%s_%d" % [key, variant]

	if _cache.has(k):
		return _cache[k]

	var b := VillageAssets.PartBuilder.new()
	var stone: Dictionary = VillageAssets.stone_spec(st._p, Color(0.78, 0.74, 0.86), "ruin_wall")
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(k)
	var len_h: float = 1.1
	var h: float = [0.8, 1.15, 1.5][variant % 3]
	VillageAssets.box(b, "base", stone, Vector3(-len_h, 0, -0.17), Vector3(len_h, h, 0.17))
	# 윗면이 부서진 모양: 높이가 들쭉날쭉한 덩어리 둘
	VillageAssets.box(b, "chip", stone, Vector3(-len_h, h, -0.17), Vector3(-len_h * 0.2, h + 0.25 + rng.randf() * 0.2, 0.17))
	VillageAssets.box(b, "chip2", stone, Vector3(len_h * 0.35, h, -0.17), Vector3(len_h, h + 0.12, 0.17))
	return _tpl_builder(b, k)


func _tpl_column(variant: int, key: String) -> Dictionary:
	var k: String = "%s_%d" % [key, variant]

	if _cache.has(k):
		return _cache[k]

	var b := VillageAssets.PartBuilder.new()
	var stone: Dictionary = VillageAssets.stone_spec(st._p, Color(0.82, 0.78, 0.9), "ruin_column")
	var h: float = 1.5 if variant == 0 else 0.8
	VillageAssets.box(b, "base", stone, Vector3(-0.36, 0, -0.36), Vector3(0.36, 0.2, 0.36))
	VillageAssets.oct(b, "shaft", stone, 0.0, 0.0, 0.3, 0.18, h, 0.27)

	if variant == 0:
		VillageAssets.box(b, "cap", stone, Vector3(-0.38, h, -0.38), Vector3(0.38, h + 0.18, 0.38))
	else:
		VillageAssets.box(b, "broken", stone, Vector3(-0.22, h, -0.18), Vector3(0.18, h + 0.2, 0.24))

	return _tpl_builder(b, k)
