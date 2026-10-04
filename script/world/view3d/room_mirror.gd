class_name RoomMirror
extends RefCounted
## 창고·생산실을 3D 로 보여 주는 거울. 매장(StoreView3D)처럼 바닥·벽·문·가구를 만들되, 방은 매장과 멀리 떨어진 별도 공간(2D 좌표 12000·18000 부근)이라
## 방 칸 (0,0) 이 놓인 세계 칸(origin)을 더해 3D 좌표로 옮긴다. 방 크기(columns × rows)와 입구(0, rows/2)는 방 노드에서 읽는다.

const ROOMS: Array = [
	{"node": "WarehouseRoom", "door": "warehouse_door", "floor": "plank", "tint": Color(0.9, 0.78, 0.62)},
	{"node": "ProductionRoom", "door": "production_door", "floor": "brick", "tint": Color(0.86, 0.8, 0.9)},
]
const WALL_BLOCKS: float = 2.0

var view: StoreView3D
var _floors: Dictionary = {}  # 방 이름 → {mesh, id_mesh, material, id_material}
var _signatures: Dictionary = {}
var _lamps: Dictionary = {}


func _init(store_view: StoreView3D) -> void:
	view = store_view


# 방 노드의 칸 (0,0) 이 놓인 세계 칸(정수).
func origin_of(room: Node2D) -> Vector2:
	var c: Vector2 = view.world_to_cell(room.to_global(room.call("grid_to_local", Vector2i.ZERO)))
	return Vector2(roundf(c.x), roundf(c.y))


# 가구 동기화에 쓰는 방 정보 목록: [{node: Objects, origin: Vector2, rect: Rect2i, room: Node2D}]
func sources() -> Array:
	var out: Array = []

	for info in ROOMS:
		var room: Node2D = view.world.get_node_or_null(str(info["node"])) as Node2D

		if room == null:
			continue

		var objects: Node = room.get_node_or_null("Objects")

		if objects == null:
			continue

		out.append({"node": objects, "origin": origin_of(room), "rect": Rect2i(0, 0, int(room.get("columns")), int(room.get("rows"))), "room": room})

	return out


func sync() -> void:
	for info in ROOMS:
		var room: Node2D = view.world.get_node_or_null(str(info["node"])) as Node2D

		if room == null:
			continue

		var cols: int = int(room.get("columns"))
		var rows: int = int(room.get("rows"))
		var origin: Vector2 = origin_of(room)
		var sig: String = "%d|%d|%s" % [cols, rows, str(origin)]
		var name: String = str(info["node"])

		if _signatures.get(name, "") == sig:
			continue

		_signatures[name] = sig
		_build_floor(name, info, origin, cols, rows)
		_build_walls(name, info, origin, cols, rows)
		_build_lamps(name, origin, cols, rows)


func _build_floor(name: String, info: Dictionary, origin: Vector2, cols: int, rows: int) -> void:
	if not _floors.has(name):
		var f: Dictionary = {}
		f["material"] = view._make_surface_material(str(info["floor"]), info["tint"])
		f["mesh"] = MeshInstance3D.new()
		(f["mesh"] as MeshInstance3D).layers = 1
		(f["mesh"] as MeshInstance3D).material_override = f["material"]
		view._viewport.add_child(f["mesh"])
		f["id_mesh"] = MeshInstance3D.new()
		(f["id_mesh"] as MeshInstance3D).layers = 2
		(f["id_mesh"] as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var idm := ShaderMaterial.new()
		idm.shader = StoreView3D.ID_SHADER
		(f["id_mesh"] as MeshInstance3D).material_override = idm
		view._viewport.add_child(f["id_mesh"])
		_floors[name] = f

	var plane := PlaneMesh.new()
	plane.size = Vector2(float(cols), float(rows))
	var center := Vector3(origin.x + float(cols) * 0.5 - 0.5, 0.0, origin.y + float(rows) * 0.5 - 0.5)

	for k in ["mesh", "id_mesh"]:
		(_floors[name][k] as MeshInstance3D).mesh = plane
		(_floors[name][k] as MeshInstance3D).position = center


# 벽 네 면(안쪽 면이 방 가장자리 선). 입구(서쪽 벽, 행 rows/2)는 한 칸 비우고 문 모델을 세운다. 동·남쪽 앞벽은 플레이어가 다가오면 낮아진다.
func _build_walls(name: String, info: Dictionary, origin: Vector2, cols: int, rows: int) -> void:
	for key in view._items.keys():
		if str(key).begins_with("rwall_" + name) or str(key).begins_with("rdoor_" + name):
			view._remove_item(key)

	var t: float = StoreView3D.WALL_THICKNESS
	var x0: float = origin.x - 0.5
	var x1: float = origin.x + float(cols) - 0.5
	var y0: float = origin.y - 0.5
	var y1: float = origin.y + float(rows) - 0.5
	var entry_row: int = floori(float(rows) / 2.0)
	var ey0: float = origin.y + float(entry_row) - 0.5
	var ey1: float = ey0 + 1.0
	var walls: Array = [
		["n", Vector2(x0 - t, y0 - t), Vector2(x1 + t, y0), false],
		["s", Vector2(x0 - t, y1), Vector2(x1 + t, y1 + t), true],
		["w1", Vector2(x0 - t, y0), Vector2(x0, ey0), false],
		["w2", Vector2(x0 - t, ey1), Vector2(x0, y1), false],
		["e", Vector2(x1, y0), Vector2(x1 + t, y1), true],
	]
	var tint: Color = Color(1.2, 1.08, 0.92) if PlaceholderTextures.clean else Color(0.85, 0.7, 0.55)

	for w in walls:
		var key: String = "rwall_%s_%s" % [name, w[0]]
		var lo: Vector2 = w[1]
		var hi: Vector2 = w[2]
		view._set_item(key, lo, hi, WALL_BLOCKS, "brick", tint, "")

		if w[3]:
			view._items[key]["cutaway"] = {"rect": Rect2(lo, hi - lo), "h": view.block_height(WALL_BLOCKS), "factor": 1.0}

	# 입구 문(서쪽 벽, 방 안쪽 = +x 를 본다)
	var door_id: String = str(info["door"])
	var pp: Dictionary = {"ts": view.texture_size, "block_px": view.block_px, "unit_px_z": (view.tile_low / sqrt(2.0)) * cos(deg_to_rad(30.0))}
	var dlo := Vector2(x0 - t * 0.5, ey0)
	var dhi := Vector2(x0 + t * 0.5, ey1)
	var built: Dictionary = FurnitureAssets.build(door_id, dlo, dhi, FurnitureAssets.wall_front_rot(3), pp)
	view._set_mesh_item("rdoor_" + name, built["mesh"], VillageAssets.make_materials(built["specs"]), dlo, Vector2(dhi.x + 0.65, dhi.y), float(built["total_blocks"]), "", NAN, true)


# 방 조명: 낮에는 꺼 두고 밤에 켠다(매장 조명 목록에 합쳐 같이 켜고 끈다).
func _build_lamps(name: String, origin: Vector2, cols: int, rows: int) -> void:
	for lamp in _lamps.get(name, []):
		view._lamps.erase(lamp)
		(lamp as Node).queue_free()

	var made: Array = []

	for fx in [0.3, 0.7]:
		for fy in [0.3, 0.7]:
			var lamp := OmniLight3D.new()
			lamp.position = Vector3(origin.x - 0.5 + float(cols) * fx, view.block_height(1.8), origin.y - 0.5 + float(rows) * fy)
			lamp.omni_range = 4.5
			lamp.light_color = Color(1.0, 0.86, 0.62)
			lamp.shadow_enabled = false
			lamp.light_cull_mask = 1
			view._viewport.add_child(lamp)
			view._lamps.append(lamp)
			made.append(lamp)

	_lamps[name] = made
