class_name GroundDecals
extends RefCounted
## 땅 위에 납작하게 붙는 장식: 비 오는 날의 물웅덩이(+물결)와 눈 위의 발자국. 둘 다 투명 컷아웃 판이라 도트 그림을 그대로 쓴다.
## 값(개수·수명)은 아래 상수로. 순번은 바닥(-1) 바로 위 고정 순번이라 건물·사람 뒤에 깔린다.

const DECAL_RANK: float = -0.55
const CUTOUT_SHADER: Shader = preload("res://script/world/view3d/shader/cutout.gdshader")
const PUDDLE_RATE: float = 0.05  # 땅 칸 중 웅덩이가 생기는 비율
const PUDDLE_CHUNK: int = 8
const PUDDLE_MARGIN: float = 1.0  # 건물·소품 발자국에서 이만큼(칸) 떨어진 곳에만 웅덩이가 생긴다
const RIPPLE_FPS: float = 5.0
const WET_SHOW: float = 0.3  # 이 젖음 이상이면 웅덩이가 보인다
const PRINT_LIFE: float = 70.0  # 발자국이 눈에 덮여 사라지는 시간(초)
const PRINT_MAX: int = 180
const PRINT_STEP: float = 0.55  # 이만큼(칸) 걸을 때마다 발자국 하나

var view: Node  # StoreView3D
var mirror: RefCounted  # VillageMirror

var _puddle_keys: Array = []
var _puddle_mats: Array = []  # 물결 단계를 바꿀 재질(3그룹)
var _puddle_tex: Array = []  # [group][frame]
var _frame: int = -1
var _t: float = 0.0
var _prints: Array = []  # {pos: Vector2, dir: Vector2, born: float}
var _print_dirty: bool = false
var _print_mat: ShaderMaterial
var _clock: float = 0.0
var _strides: Dictionary = {}  # 사람 id → {dist, side}


func _init(view_node: Node, mirror_node: RefCounted) -> void:
	view = view_node
	mirror = mirror_node

	for g in range(3):
		var frames: Array = []

		for f in range(5):
			frames.append(PlaceholderTextures.puddle(g, f))

		_puddle_tex.append(frames)


func _material(tex: Texture2D) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = CUTOUT_SHADER
	m.set_shader_parameter("albedo_tex", tex)
	return m


# ---------------------------------------------------------------- 물웅덩이

func clear_puddles() -> void:
	for k in _puddle_keys:
		view._remove_item(str(k))

	_puddle_keys.clear()
	_puddle_mats.clear()


# 땅 종류별 칸 목록(per_kind: {"grass": [...], "road": [...], "paving": [...]})에서 일부 칸에 웅덩이를 만든다. 칸 위치로 정해져서 항상 같은 자리.
func rebuild_puddles(per_kind: Dictionary, snowy: bool, blockers: Array = []) -> void:
	clear_puddles()

	if snowy:
		return

	var chunks: Dictionary = {}

	for kind in ["road", "paving", "grass"]:
		for cell in per_kind.get(kind, []):
			var h: int = absi((cell.x * 668265263) ^ (cell.y * 374761393)) % 10000
			var rate: float = PUDDLE_RATE * (0.5 if kind == "grass" else 1.0)

			if float(h) >= rate * 10000.0:
				continue

			# 물체(건물·소품·나무 등)의 판정 사각형 근처는 피한다: 웅덩이 크기(최대 약 1.5칸)와 여유를 더해 겹치면 건너뜀.
			var spot := Rect2(float(cell.x) - 0.75 - PUDDLE_MARGIN, float(cell.y) - 0.75 - PUDDLE_MARGIN, 1.5 + PUDDLE_MARGIN * 2.0, 1.5 + PUDDLE_MARGIN * 2.0)
			var near_object: bool = false

			for bl in blockers:
				if (bl as Rect2).intersects(spot):
					near_object = true
					break

			if near_object:
				continue

			var ck := Vector2i(int(floorf(float(cell.x) / float(PUDDLE_CHUNK))), int(floorf(float(cell.y) / float(PUDDLE_CHUNK))))

			if not chunks.has(ck):
				chunks[ck] = []

			(chunks[ck] as Array).append([cell, h])

	var mats: Array = []

	for g in range(3):
		var m: ShaderMaterial = _material(_puddle_tex[g][0])
		m.set_shader_parameter("tint", Color(1, 1, 1, 1))
		mats.append(m)

	_puddle_mats = mats

	for ck in chunks.keys():
		var sts: Array = []

		for g in range(3):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			sts.append(st)

		var counts: Array = [0, 0, 0]
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)

		for entry in chunks[ck]:
			var cell: Vector2i = entry[0]
			var h: int = entry[1]
			var g: int = h % 3
			var size: float = 0.9 + float((h / 3) % 8) * 0.09
			var cx: float = float(cell.x) + (float((h / 7) % 10) / 10.0 - 0.5) * 0.4
			var cz: float = float(cell.y) + (float((h / 11) % 10) / 10.0 - 0.5) * 0.4
			_add_flat_quad(sts[g], cx, cz, size, 0.0, 0.025, size * 0.8)
			counts[g] += 1
			lo = Vector2(minf(lo.x, cx - size), minf(lo.y, cz - size))
			hi = Vector2(maxf(hi.x, cx + size), maxf(hi.y, cz + size))

		var mesh := ArrayMesh.new()
		var cmats: Array = []

		for g in range(3):
			if counts[g] > 0:
				(sts[g] as SurfaceTool).commit(mesh)
				cmats.append(mats[g])

		if cmats.is_empty():
			continue

		var key: String = "puddle_%d_%d" % [ck.x, ck.y]
		view._set_mesh_item(key, mesh, cmats, lo, hi, 0.1, "puddle", DECAL_RANK, false)
		(view._items[key]["mesh"] as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(view._items[key]["mesh"] as Node3D).visible = false
		_puddle_keys.append(key)


# 바닥에 누운 정사각(축에 평행) 판 하나. 폭 w, 깊이 d(칸), 높이 y. 위를 본다.
static func _add_flat_quad(st: SurfaceTool, cx: float, cz: float, w: float, _unused: float, y: float, d: float) -> void:
	var x0: float = cx - w * 0.5
	var x1: float = cx + w * 0.5
	var z0: float = cz - d * 0.5
	var z1: float = cz + d * 0.5
	BuildingMesh._quad(st, Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1), Vector3.UP, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))


# ---------------------------------------------------------------- 낙엽 더미(가을 땅 장식)

var _litter_keys: Array = []
var _litter_mats: Array = []


func clear_litter() -> void:
	for k in _litter_keys:
		view._remove_item(str(k))

	_litter_keys.clear()


# 풀밭 칸 일부에 낙엽이 흩어진다(rate = 칸 비율). 칸 위치로 정해져서 항상 같은 자리, 물체 근처(0.4칸)는 피한다.
func rebuild_litter(grass_cells: Array, rate: float, blockers: Array) -> void:
	clear_litter()

	if rate <= 0.0:
		return

	if _litter_mats.is_empty():
		for v in range(4):
			_litter_mats.append(_material(PlaceholderTextures.leaf_litter(v)))

	var chunks: Dictionary = {}

	for cell in grass_cells:
		var h: int = absi((cell.x * 1597334677) ^ (cell.y * 3812015801)) % 10000

		if float(h) >= rate * 10000.0:
			continue

		var spot := Rect2(float(cell.x) - 0.5 - 0.4, float(cell.y) - 0.5 - 0.4, 1.8, 1.8)
		var near_object: bool = false

		for bl in blockers:
			if (bl as Rect2).intersects(spot):
				near_object = true
				break

		if near_object:
			continue

		var ck := Vector2i(int(floorf(float(cell.x) / float(PUDDLE_CHUNK))), int(floorf(float(cell.y) / float(PUDDLE_CHUNK))))

		if not chunks.has(ck):
			chunks[ck] = []

		(chunks[ck] as Array).append([cell, h])

	for ck in chunks.keys():
		var sts: Array = []

		for v in range(4):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			sts.append(st)

		var counts: Array = [0, 0, 0, 0]
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)

		for entry in chunks[ck]:
			var cell: Vector2i = entry[0]
			var h: int = entry[1]
			var v: int = h % 4
			var size: float = 0.7 + float((h / 4) % 5) * 0.1
			var cx: float = float(cell.x) + (float((h / 9) % 10) / 10.0 - 0.5) * 0.5
			var cz: float = float(cell.y) + (float((h / 13) % 10) / 10.0 - 0.5) * 0.5
			_add_flat_quad(sts[v], cx, cz, size, 0.0, 0.022, size)
			counts[v] += 1
			lo = Vector2(minf(lo.x, cx - size), minf(lo.y, cz - size))
			hi = Vector2(maxf(hi.x, cx + size), maxf(hi.y, cz + size))

		var mesh := ArrayMesh.new()
		var cmats: Array = []

		for v in range(4):
			if counts[v] > 0:
				(sts[v] as SurfaceTool).commit(mesh)
				cmats.append(_litter_mats[v])

		if cmats.is_empty():
			continue

		var key: String = "litter_%d_%d" % [ck.x, ck.y]
		view._set_mesh_item(key, mesh, cmats, lo, hi, 0.1, "litter", DECAL_RANK - 0.03, false)
		(view._items[key]["mesh"] as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_litter_keys.append(key)


# ---------------------------------------------------------------- 발자국

# 사람이 움직인 만큼(칸) 걸음을 쌓고, 한 걸음마다 왼발·오른발을 번갈아 찍는다. snow_here: 지금 밟는 땅이 눈밭인지.
func walk(actor_id: int, pos: Vector2, move: Vector2, snow_here: bool) -> void:
	var st: Dictionary = _strides.get(actor_id, {"dist": 0.0, "side": 1.0})
	var step: float = move.length()

	if step < 0.0005 or not snow_here:
		_strides[actor_id] = st
		return

	st["dist"] = float(st["dist"]) + step

	if float(st["dist"]) >= PRINT_STEP:
		st["dist"] = 0.0
		var dir: Vector2 = move.normalized()
		var right := Vector2(-dir.y, dir.x)
		st["side"] = -float(st["side"])
		_prints.append({"pos": pos + right * 0.11 * float(st["side"]) - dir * 0.05, "dir": dir, "born": _clock})

		if _prints.size() > PRINT_MAX:
			_prints.remove_at(0)

		_print_dirty = true

	_strides[actor_id] = st


func clear_prints() -> void:
	_prints.clear()
	_print_dirty = true


# ---------------------------------------------------------------- 매 프레임

func tick(delta: float) -> void:
	_clock += delta
	_tick_puddles(delta)
	_tick_prints()


func _tick_puddles(delta: float) -> void:
	if _puddle_keys.is_empty():
		return

	var show: bool = float(view.wetness) > WET_SHOW
	var raining: bool = str(view.weather["kind"]) == "rain" and float(view.weather["intensity"]) > 0.05
	_t += delta
	var tick_no: int = int(_t * RIPPLE_FPS) if raining else -1

	for k in _puddle_keys:
		if view._items.has(k):
			(view._items[k]["mesh"] as Node3D).visible = show

	if tick_no == _frame:
		return

	_frame = tick_no

	for g in range(_puddle_mats.size()):
		# 비가 오면 물결 고리가 0~4 단계를 반복(그룹마다 시작이 어긋남), 아니면 잔잔한 물
		var f: int = ((tick_no + g * 2) % 5) if raining else 0
		(_puddle_mats[g] as ShaderMaterial).set_shader_parameter("albedo_tex", _puddle_tex[g][f])


func _tick_prints() -> void:
	var before: int = _prints.size()

	while not _prints.is_empty() and _clock - float(_prints[0]["born"]) > PRINT_LIFE:
		_prints.remove_at(0)

	if _prints.size() != before:
		_print_dirty = true

	if not _print_dirty:
		return

	_print_dirty = false
	var key := "footprints"

	if _prints.is_empty():
		view._remove_item(key)
		return

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)

	for pr in _prints:
		var pos: Vector2 = pr["pos"]
		var dir: Vector2 = pr["dir"]
		var right := Vector2(-dir.y, dir.x)
		var hl: float = 0.27  # 길이 절반
		var hw: float = 0.17  # 폭 절반
		var fade: float = clampf((PRINT_LIFE - (_clock - float(pr["born"]))) / 10.0, 0.0, 1.0)

		if fade < 0.2:
			hw *= 0.6  # 사라지기 직전엔 눈에 덮여 작아진다

		var a: Vector2 = pos - right * hw - dir * hl  # 뒤꿈치 쪽(v=1)
		var b: Vector2 = pos + right * hw - dir * hl
		var c: Vector2 = pos + right * hw + dir * hl  # 발끝(v=0)
		var d: Vector2 = pos - right * hw + dir * hl
		BuildingMesh._quad(st, Vector3(a.x, 0.03, a.y), Vector3(b.x, 0.03, b.y), Vector3(c.x, 0.03, c.y), Vector3(d.x, 0.03, d.y), Vector3.UP, Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0))

		for q in [a, b, c, d]:
			lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
			hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))

	if _print_mat == null:
		_print_mat = _material(PlaceholderTextures.footprint())

	var mesh: ArrayMesh = st.commit()
	view._set_mesh_item(key, mesh, [_print_mat], lo, hi, 0.1, "footprints", DECAL_RANK + 0.02, false)
	(view._items[key]["mesh"] as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
