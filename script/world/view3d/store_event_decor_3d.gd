class_name StoreEventDecor3D
extends RefCounted
## 진행 중인 가게 행사에 맞춰 매장 안쪽 두 벽(북·서)에 걸리는 장식(깃발 줄·꽃 줄·등불·전구 줄). 바닥에 놓지 않으므로 진열대·동선과 겹치지 않는다.
## 어떤 행사에 어떤 장식·색을 쓸지는 data/shop/events/store_event_decor_3d.csv. 행사가 끝나면 사라진다.

const DATA_PATH: String = "res://data/shop/events/store_event_decor_3d.csv"
const SEGMENT: float = 4.0  # 한 물체로 묶는 벽 길이(칸)
const SPAN: float = 1.6  # 줄이 한 번 처지는 길이(칸)
const BASE_BLOCKS: float = 1.9  # 벽 안쪽에서 줄이 걸리는 높이
const LANE_DROP: float = 0.28  # 행사가 둘 이상일 때 줄 하나마다 내려가는 높이
const OFFSET: float = 0.07  # 벽에서 떨어진 거리

static var _rows: Dictionary = {}
static var _loaded: bool = false

var view: StoreView3D
var _signature: String = ""
var _keys: Array = []


func _init(store_view: StoreView3D) -> void:
	view = store_view


static func rows_for(event_id: String) -> Dictionary:
	if not _loaded:
		_load()

	return _rows.get(event_id, {})


static func _load() -> void:
	_loaded = true
	_rows.clear()
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)

	if file == null:
		push_warning("[StoreEventDecor3D] 파일 없음: " + DATA_PATH)
		return

	file.get_csv_line()

	while not file.eof_reached():
		var c: PackedStringArray = file.get_csv_line()

		if c.size() < 4 or c[0].strip_edges().is_empty():
			continue

		var colors: Array = []

		for h in c[2].strip_edges().split("|"):
			colors.append(Color.html(h))

		_rows[c[0].strip_edges()] = {"style": c[1].strip_edges(), "colors": colors, "lane": int(c[3])}


# 지금 진행 중인 행사에 맞는 장식을 만든다(구성이 바뀔 때만 다시 만든다).
func sync(rect: Rect2i) -> void:
	var active: Array = []

	for ev in StoreEventData.get_active_events(GameState.total_day):
		if not rows_for(str(ev.get("event_id", ""))).is_empty():
			active.append(str(ev["event_id"]))

	active.sort()
	var sig: String = "%s|%s" % [str(rect), ",".join(active)]

	if sig == _signature:
		return

	_signature = sig

	for key in _keys:
		view._remove_item(key)

	_keys.clear()
	var lanes_used: Dictionary = {}

	for id in active:
		var row: Dictionary = rows_for(id)
		var lane: int = int(row["lane"])

		while lanes_used.has(lane):
			lane += 1

		lanes_used[lane] = true
		_build_run(id, row, rect, lane)


func _build_run(event_id: String, row: Dictionary, rect: Rect2i, lane: int) -> void:
	var x0: float = float(rect.position.x) - 0.5
	var y0: float = float(rect.position.y) - 0.5
	var x1: float = float(rect.end.x) - 0.5
	var y1: float = float(rect.end.y) - 0.5
	var h: float = BASE_BLOCKS - float(lane) * LANE_DROP
	# 북쪽 벽(x 방향으로 뻗음), 서쪽 벽(y 방향으로 뻗음)
	_segments(event_id, row, "n", Vector2(x0, y0 + OFFSET), Vector2(x1, y0 + OFFSET), h)
	_segments(event_id, row, "w", Vector2(x0 + OFFSET, y0), Vector2(x0 + OFFSET, y1), h)


func _segments(event_id: String, row: Dictionary, wall: String, a: Vector2, b: Vector2, h: float) -> void:
	var length: float = a.distance_to(b)
	var count: int = maxi(1, ceili(length / SEGMENT))

	for i in range(count):
		var t0: float = float(i) / float(count)
		var t1: float = float(i + 1) / float(count)
		var p0: Vector2 = a.lerp(b, t0)
		var p1: Vector2 = a.lerp(b, t1)
		var built: Dictionary = _build_segment(row, p0, p1, h, i)
		var key: String = "evdecor_%s_%s_%d" % [event_id, wall, i]
		var lo := Vector2(minf(p0.x, p1.x) - 0.1, minf(p0.y, p1.y) - 0.1)
		var hi := Vector2(maxf(p0.x, p1.x) + 0.25, maxf(p0.y, p1.y) + 0.25)
		view._set_mesh_item(key, built["mesh"], VillageAssets.make_materials(built["specs"]), lo, hi, h + 0.1, "", NAN, false)
		_keys.append(key)


# 선분 p0 → p1 위에 줄을 처지게 걸고 장식을 단다. 부품은 색마다 한 면.
func _build_segment(row: Dictionary, p0: Vector2, p1: Vector2, h: float, seed_offset: int) -> Dictionary:
	var b := VillageAssets.PartBuilder.new()
	var ts: int = view.texture_size
	var parts: Dictionary = {}
	var colors: Array = row["colors"]
	var style: String = str(row["style"])
	var along: Vector2 = (p1 - p0).normalized()
	var length: float = p0.distance_to(p1)
	var inward := Vector2(-along.y, along.x)  # 벽 안쪽(매장 안)을 향하는 쪽을 아래서 고른다
	var wall_in: Vector2 = Vector2(1.0, 1.0)  # 북·서 벽은 둘 다 +x/+y 쪽이 매장 안

	if inward.dot(wall_in) < 0.0:
		inward = -inward

	var cord: Dictionary = VillageAssets._flat_spec(ts, Color(0.25, 0.2, 0.16) if style != "garland" else Color(0.26, 0.5, 0.24), "ed_cord_" + style)
	var steps: int = maxi(1, int(length / 0.2))

	for s in range(steps):
		var d0: float = length * float(s) / float(steps)
		var d1: float = length * float(s + 1) / float(steps)
		var q0: Vector3 = _point(p0, along, d0, h, seed_offset, length)
		var q1: Vector3 = _point(p0, along, d1, h, seed_offset, length)
		var thick: float = 0.05 if style == "garland" else 0.022
		_wire(b, parts, cord, q0, q1, thick)

	var spacing: float = {"bunting": 0.26, "garland": 0.18, "lanterns": 0.8, "lights": 0.2}.get(style, 0.3)
	var n: int = int(length / spacing)

	for k in range(n):
		var d: float = (float(k) + 0.5) * length / float(n)
		var at: Vector3 = _point(p0, along, d, h, seed_offset, length)
		var col: Color = colors[(k + seed_offset) % colors.size()]
		match style:
			"bunting":
				_pennant(b, parts, ts, at, along, col)
			"garland":
				_bloom(b, parts, ts, at, col, k)
			"lanterns":
				_lantern(b, parts, ts, at, col)
			"lights":
				_bulb(b, parts, ts, at, col)

	var mesh := ArrayMesh.new()
	var specs: Array = b.commit_into(mesh)
	return {"mesh": mesh, "specs": specs}


# 줄 위의 점: 걸림 지점 사이에서 사인 곡선으로 처진다. y 는 높이.
func _point(p0: Vector2, along: Vector2, d: float, h: float, seed_offset: int, length: float) -> Vector3:
	var span_pos: float = fmod(d + float(seed_offset) * SEGMENT, SPAN) / SPAN
	var sag: float = 0.16 * sin(span_pos * PI)
	var pos: Vector2 = p0 + along * d
	return Vector3(pos.x, h - sag, pos.y)


func _spec_part(b: VillageAssets.PartBuilder, parts: Dictionary, spec: Dictionary, a: Vector3, c: Vector3) -> SurfaceTool:
	var key: String = str(spec["name"])

	if not parts.has(key):
		parts[key] = b.new_part(spec, a, c)

	return parts[key]


func _flat(ts: int, color: Color, name: String, emit: float = 0.0) -> Dictionary:
	var sp: Dictionary = VillageAssets._flat_spec(ts, color, name)

	if emit > 0.0:
		sp["emit"] = emit

	return sp


func _cube(b: VillageAssets.PartBuilder, parts: Dictionary, spec: Dictionary, lo: Vector3, hi: Vector3) -> void:
	VillageAssets.box_st(_spec_part(b, parts, spec, lo, hi), lo, hi)


func _wire(b: VillageAssets.PartBuilder, parts: Dictionary, spec: Dictionary, q0: Vector3, q1: Vector3, thick: float) -> void:
	var lo := Vector3(minf(q0.x, q1.x) - thick, minf(q0.y, q1.y) - thick, minf(q0.z, q1.z) - thick)
	var hi := Vector3(maxf(q0.x, q1.x) + thick, maxf(q0.y, q1.y) + thick, maxf(q0.z, q1.z) + thick)
	_cube(b, parts, spec, lo, hi)


# 깃발: 줄에서 아래로 좁아지는 삼각 모양(상자 세 개).
func _pennant(b: VillageAssets.PartBuilder, parts: Dictionary, ts: int, at: Vector3, along: Vector2, col: Color) -> void:
	var sp: Dictionary = _flat(ts, col, "ed_flag_" + col.to_html(false))
	var wx: float = absf(along.x)
	var wz: float = absf(along.y)
	var sizes: Array = [[0.16, 0.1], [0.11, 0.09], [0.05, 0.08]]
	var y: float = at.y

	for s in sizes:
		var hw: float = float(s[0]) * 0.5
		var hh: float = float(s[1])
		var lo := Vector3(at.x - hw * wx - 0.012, y - hh, at.z - hw * wz - 0.012)
		var hi := Vector3(at.x + hw * wx + 0.012, y, at.z + hw * wz + 0.012)
		_cube(b, parts, sp, lo, hi)
		y -= hh


func _bloom(b: VillageAssets.PartBuilder, parts: Dictionary, ts: int, at: Vector3, col: Color, k: int) -> void:
	var leaf: Dictionary = _flat(ts, Color(0.3, 0.58, 0.28), "ed_leaf")
	var sp: Dictionary = _flat(ts, col, "ed_bloom_" + col.to_html(false))
	_cube(b, parts, leaf, at + Vector3(-0.06, -0.09, -0.06), at + Vector3(0.06, 0.03, 0.06))
	var drop: float = 0.05 + float(k % 3) * 0.05
	_cube(b, parts, sp, at + Vector3(-0.05, -0.09 - drop, -0.05), at + Vector3(0.05, -0.09 - drop + 0.1, 0.05))


func _lantern(b: VillageAssets.PartBuilder, parts: Dictionary, ts: int, at: Vector3, col: Color) -> void:
	var cord: Dictionary = _flat(ts, Color(0.2, 0.16, 0.12), "ed_lcord")
	var glow: Dictionary = _flat(ts, col, "ed_lantern_" + col.to_html(false), 0.9)
	_cube(b, parts, cord, at + Vector3(-0.008, -0.14, -0.008), at + Vector3(0.008, 0.0, 0.008))
	_cube(b, parts, cord, at + Vector3(-0.07, -0.16, -0.07), at + Vector3(0.07, -0.14, 0.07))
	_cube(b, parts, glow, at + Vector3(-0.06, -0.34, -0.06), at + Vector3(0.06, -0.16, 0.06))
	_cube(b, parts, cord, at + Vector3(-0.045, -0.36, -0.045), at + Vector3(0.045, -0.34, 0.045))


func _bulb(b: VillageAssets.PartBuilder, parts: Dictionary, ts: int, at: Vector3, col: Color) -> void:
	var glow: Dictionary = _flat(ts, col, "ed_bulb_" + col.to_html(false), 1.2)
	_cube(b, parts, glow, at + Vector3(-0.035, -0.08, -0.035), at + Vector3(0.035, 0.0, 0.035))
