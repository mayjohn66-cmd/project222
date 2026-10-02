class_name StoreView3D
extends Node
## 매장 안쪽을 3D 도트 방식(낮은 해상도 3D + 정렬 순서 깊이 + 한 픽셀 윤곽선 + 법선 맵)으로 다시 그리는 "보이는 층".
## 게임 규칙·충돌·길찾기·건축은 지금의 2D 코드가 그대로 맡고, 이 층은 2D 노드의 상태를 **읽기만** 한다(2D 코드를 바꾸지 않음).
## World 노드 아래에 붙인다. 읽는 곳: Floor(칸 수), WoodWalls(벽 선분), Objects(가구: 메타 build_id/anchor, Visual 의 footprint/rotation),
## Actors/Player(+ Camera2D), 그룹 customer / worker / story_npc / merchant_npc.
## 설계: docs/계획_매장_3D_적용_초안.md, 규격: docs/그림_규격서_3D도트_초안.md
## 칸 좌표: 2D 게임의 칸 좌표(칸 중심이 정수)를 그대로 3D 의 (x, z) 로 쓴다.

enum Mode { OFF, OVERLAY, ON }  # 끔 / 반투명 겹침(2D 와 위치 비교) / 3D 만 불투명(2D 는 3D 가 안 덮는 곳에만 보임)

const GAME_TILE: Vector2 = Vector2(96.0, 48.0)  # 2D 게임의 칸 크기
const TILE_LOW: float = 36.0  # 낮은 해상도에서 한 칸 마름모 폭
const BLOCK_PX: float = 22.0  # 1블록 = 낮은 해상도 세로 22픽셀
const SHRINK: int = 3  # 낮은 해상도 → 화면 3배 확대
const MATCH_ZOOM: float = TILE_LOW * SHRINK / 96.0  # 1.125: 2D 카메라가 이 줌일 때 3D 와 2D 칸 크기가 같다
const PITCH_DEG: float = 30.0
const YAW_DEG: float = 45.0
const TEXTURE_SIZE: int = 18  # 질감 한 변 = 칸 폭의 절반

const WALL_THICKNESS: float = 0.3
# 2D 벽 높이(96칸 기준 px)를 낮은 해상도 px 로: ×36/96. 120px → 45px ≈ 2.0블록, 75px → 28px ≈ 1.3블록 (캐릭터 25px 와의 비율도 같음)
const WALL_TALL_BLOCKS: float = 2.0  # 안쪽 벽(2D 120px)
const WALL_LOW_BLOCKS: float = 1.3  # 도로 쪽 벽(2D 75px)
const WALL_TALL_PX: float = 100.0  # 이보다 높은 2D 벽 = 안쪽 벽

const ACTOR_HEAD_RATIO: float = 3.0
const ACTOR_TOTAL: float = 1.14
const ACTOR_TORSO: float = 0.308
const ACTOR_HEIGHT_PX: float = 25.0
const ACTOR_HALF: float = 0.12

const SURFACE_SHADER: Shader = preload("res://script/world/view3d/shader/sorted_surface.gdshader")
const ID_SHADER: Shader = preload("res://script/world/view3d/shader/sorted_id.gdshader")
const OUTLINE_SHADER: Shader = preload("res://script/world/view3d/shader/outline_post.gdshader")

var mode: Mode = Mode.OFF:
	set(value):
		mode = value
		_apply_mode()

var world: Node2D
var floor_node: Node2D
var objects_node: Node2D
var player: Node2D
var camera2d: Camera2D

var _canvas: CanvasLayer
var _container: SubViewportContainer
var _viewport: SubViewport
var _id_viewport: SubViewport
var _camera: Camera3D
var _id_camera: Camera3D
var _sun: DirectionalLight3D
var _post_material: ShaderMaterial
var _ready_done: bool = false
var _zoom_applied: bool = false
var _saved_zoom: Vector2 = Vector2.ONE

# 키 → {mesh, material, id_mesh, id_material, min, max, center, signature}
var _items: Dictionary = {}
# 노드 인스턴스 id → {node, figure}
var _actors: Dictionary = {}
var _floor_signature: String = ""
var _wall_signature: String = ""
var _wall_timer: float = 0.0
var _ground_material: ShaderMaterial
var _ground_mesh: MeshInstance3D
var _ground_id_mesh: MeshInstance3D
var _ground_id_material: ShaderMaterial
var _texture_cache: Dictionary = {}


func _ready() -> void:
	process_priority = 200  # 2D 노드들이 움직인 다음에 읽는다
	world = get_parent() as Node2D
	_build_view.call_deferred()


func _build_view() -> void:
	floor_node = world.get_node_or_null("Floor")
	objects_node = world.get_node_or_null("Objects")
	player = world.get_node_or_null("Actors/Player")

	if floor_node == null or objects_node == null:
		push_warning("[StoreView3D] Floor/Objects 를 찾지 못해 3D 층을 만들지 않음")
		return

	if player != null:
		camera2d = player.get_node_or_null("Camera2D")

	_canvas = CanvasLayer.new()
	_canvas.layer = 0
	add_child(_canvas)
	_container = SubViewportContainer.new()
	_container.stretch = true
	_container.stretch_shrink = SHRINK
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.add_child(_container)

	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.handle_input_locally = false
	_container.add_child(_viewport)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.rotation_degrees = Vector3(-PITCH_DEG, YAW_DEG, 0.0)
	_camera.near = 0.1
	_camera.far = 100.0
	_camera.cull_mask = 1
	_viewport.add_child(_camera)

	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-55, 25, 0)
	_sun.light_energy = 1.1
	_sun.shadow_enabled = true
	_viewport.add_child(_sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.8)
	env.ambient_light_energy = 0.55
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)

	_build_id_pass()
	_post_material = ShaderMaterial.new()
	_post_material.shader = OUTLINE_SHADER
	_post_material.set_shader_parameter("id_tex", _id_viewport.get_texture())
	_container.material = _post_material
	_ready_done = true
	_apply_mode()


# 윤곽선용 번호 판: 같은 3D 세계를 층 2 카메라로 한 번 더 그린다(물체마다 순번 값만).
func _build_id_pass() -> void:
	_id_viewport = SubViewport.new()
	_id_viewport.world_3d = _viewport.world_3d
	_id_viewport.transparent_bg = false
	_id_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_id_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_id_viewport)
	_id_camera = Camera3D.new()
	_id_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_id_camera.near = 0.1
	_id_camera.far = 100.0
	_id_camera.cull_mask = 2
	_id_viewport.add_child(_id_camera)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	var id_env := WorldEnvironment.new()
	id_env.environment = env
	_id_viewport.add_child(id_env)


func _apply_mode() -> void:
	if not _ready_done:
		return

	_canvas.visible = mode != Mode.OFF

	# 3D 칸 크기(화면 108px)와 2D 칸 크기를 맞추려고 2D 카메라 줌을 올린다(끄면 원래 값으로).
	if camera2d != null:
		if mode != Mode.OFF and not _zoom_applied:
			_saved_zoom = camera2d.zoom
			camera2d.zoom = Vector2.ONE * MATCH_ZOOM
			_zoom_applied = true
		elif mode == Mode.OFF and _zoom_applied:
			camera2d.zoom = _saved_zoom
			_zoom_applied = false

	_container.modulate = Color(1, 1, 1, 0.55 if mode == Mode.OVERLAY else 1.0)
	set_process(mode != Mode.OFF)


func cycle_mode() -> void:
	mode = ((int(mode) + 1) % 3) as Mode


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F10:
		cycle_mode()


# ---------------------------------------------------------------- 좌표

# 2D 세계 좌표 → 칸 좌표(연속 값, 칸 중심이 정수)
func world_to_cell(global_pos: Vector2) -> Vector2:
	var local: Vector2 = floor_node.to_local(global_pos)
	var tile := Vector2(floor_node.tile_width, floor_node.tile_height)
	return Vector2(local.x / tile.x + local.y / tile.y, local.y / tile.y - local.x / tile.x)


func block_height(blocks: float) -> float:
	var px_per_unit_z: float = (TILE_LOW / sqrt(2.0)) * cos(deg_to_rad(PITCH_DEG))
	return blocks * BLOCK_PX / px_per_unit_z


func _pixel_world_size() -> float:
	return _camera.size / float(_viewport.size.y)


func _snap(p: Vector3) -> Vector3:
	var px: float = _pixel_world_size()
	var right: Vector3 = _camera.basis.x
	var up: Vector3 = _camera.basis.y
	var r: float = p.dot(right)
	var u: float = p.dot(up)
	return p + (roundf(r / px) * px - r) * right + (roundf(u / px) * px - u) * up


# ---------------------------------------------------------------- 매 프레임

func _process(delta: float) -> void:
	if not _ready_done:
		return

	_sync_camera()
	_wall_timer -= delta

	if _wall_timer <= 0.0:
		_wall_timer = 0.25
		_sync_floor()
		_sync_walls()
		_sync_furniture()

	_sync_actors(delta)
	_sort_and_update()


func _sync_camera() -> void:
	var base_size: Vector2 = get_viewport().get_visible_rect().size
	_viewport.size = Vector2i(ceili(base_size.x / SHRINK), ceili(base_size.y / SHRINK))
	_id_viewport.size = _viewport.size
	var zoom: float = camera2d.zoom.x if camera2d != null else 1.0
	_camera.size = base_size.y / (GAME_TILE.x * zoom / sqrt(2.0))
	var center_world: Vector2 = camera2d.get_screen_center_position() if camera2d != null else floor_node.global_position
	var c: Vector2 = world_to_cell(center_world)
	var target := Vector3(c.x, 0.0, c.y)
	var pos: Vector3 = target + _camera.basis.z * 30.0
	_camera.position = _snap(pos)
	_id_camera.global_transform = _camera.global_transform
	_id_camera.size = _camera.size


# ---------------------------------------------------------------- 바닥·벽

func _sync_floor() -> void:
	var rect: Rect2i = floor_node.get_store_rect()
	var sig: String = str(rect)

	if sig == _floor_signature:
		return

	_floor_signature = sig
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(rect.size)

	if _ground_mesh == null:
		_ground_mesh = MeshInstance3D.new()
		_ground_mesh.layers = 1
		_ground_material = _make_surface_material("plank", Color(0.62, 0.38, 0.28))
		_ground_mesh.material_override = _ground_material
		_viewport.add_child(_ground_mesh)
		_ground_id_mesh = MeshInstance3D.new()
		_ground_id_mesh.layers = 2
		_ground_id_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ground_id_material = ShaderMaterial.new()
		_ground_id_material.shader = ID_SHADER
		_ground_id_mesh.material_override = _ground_id_material
		_viewport.add_child(_ground_id_mesh)

	_ground_mesh.mesh = mesh
	_ground_id_mesh.mesh = mesh
	var center := Vector3(float(rect.position.x) + float(rect.size.x) * 0.5 - 0.5, 0.0, float(rect.position.y) + float(rect.size.y) * 0.5 - 0.5)
	_ground_mesh.position = center
	_ground_id_mesh.position = center


# WoodWalls 의 판자 벽 선분(칸 한 변 길이)을 읽어서 이어 붙인 상자로 만든다.
func _sync_walls() -> void:
	var walls: Node = world.get_node_or_null("WoodWalls")
	var segments: Array = []

	if walls != null:
		for panel in walls.get_children():
			if not panel is Node2D:
				continue

			var start_w: Vector2 = (panel as Node2D).global_position + (panel.get("start") as Vector2)
			var end_w: Vector2 = (panel as Node2D).global_position + (panel.get("end") as Vector2)
			var a: Vector2 = world_to_cell(start_w)
			var b: Vector2 = world_to_cell(end_w)
			var tall: bool = float(panel.get("wall_height")) > WALL_TALL_PX
			segments.append({"a": a, "b": b, "direction": int(panel.get("direction")), "tall": tall})

	var sig: String = str(segments.size())

	for s in segments:
		sig += "|%.2f,%.2f,%.2f,%.2f,%d,%s" % [s["a"].x, s["a"].y, s["b"].x, s["b"].y, s["direction"], s["tall"]]

	if sig == _wall_signature:
		return

	_wall_signature = sig

	for key in _items.keys():
		if str(key).begins_with("wall"):
			_remove_item(key)

	# 같은 방향·높이이고 끝과 시작이 맞닿는 선분을 한 상자로 합친다.
	var runs: Array = []

	for s in segments:
		var along_x: bool = absf(s["a"].y - s["b"].y) < 0.05
		var line: float = s["a"].y if along_x else s["a"].x
		var lo: float = minf(s["a"].x, s["b"].x) if along_x else minf(s["a"].y, s["b"].y)
		var hi: float = maxf(s["a"].x, s["b"].x) if along_x else maxf(s["a"].y, s["b"].y)
		runs.append({"along_x": along_x, "line": snappedf(line, 0.01), "lo": lo, "hi": hi, "direction": s["direction"], "tall": s["tall"]})

	runs.sort_custom(func(p, q):
		if p["direction"] != q["direction"]:
			return p["direction"] < q["direction"]

		if p["line"] != q["line"]:
			return p["line"] < q["line"]

		return p["lo"] < q["lo"])
	var merged: Array = []

	for r in runs:
		if not merged.is_empty():
			var last: Dictionary = merged[-1]

			if last["direction"] == r["direction"] and last["line"] == r["line"] and last["tall"] == r["tall"] and absf(last["hi"] - r["lo"]) < 0.05:
				last["hi"] = r["hi"]
				continue

		merged.append(r.duplicate())

	var index: int = 0

	for r in merged:
		var lo_v: Vector2
		var hi_v: Vector2
		var line_v: float = r["line"]

		if r["along_x"]:
			# 방향 0 = 뒤쪽(y 작은 쪽) 바깥, 2 = 앞쪽(y 큰 쪽) 바깥
			var outward: float = -1.0 if r["direction"] == 0 else 1.0
			var y0: float = line_v if outward > 0.0 else line_v - WALL_THICKNESS
			lo_v = Vector2(r["lo"], y0)
			hi_v = Vector2(r["hi"], y0 + WALL_THICKNESS)
		else:
			var outward_x: float = -1.0 if r["direction"] == 3 else 1.0
			var x0: float = line_v if outward_x > 0.0 else line_v - WALL_THICKNESS
			lo_v = Vector2(x0, r["lo"])
			hi_v = Vector2(x0 + WALL_THICKNESS, r["hi"])

		_set_item("wall%d" % index, lo_v, hi_v, WALL_TALL_BLOCKS if r["tall"] else WALL_LOW_BLOCKS, "brick", Color(0.85, 0.7, 0.55), "")
		index += 1


# ---------------------------------------------------------------- 가구

func _sync_furniture() -> void:
	var alive: Dictionary = {}

	for node in objects_node.get_children():
		if not node is Node2D or not node.has_meta("build_id"):
			continue

		var build_id: String = str(node.get_meta("build_id"))
		var row: Dictionary = Furniture3DData.get_row(build_id)

		if row["kind"] != "box":
			continue

		var visual: Node = node.get_node_or_null("Visual")
		var anchor: Vector2i = node.get_meta("anchor", Vector2i.ZERO)
		var rotation_index: int = int(visual.get("rotation_index")) if visual != null and visual.get("rotation_index") != null else int(node.get_meta("rotation_index", 0))
		var fx: int = int(visual.get("footprint_x")) if visual != null and visual.get("footprint_x") != null else 1
		var fy: int = int(visual.get("footprint_y")) if visual != null and visual.get("footprint_y") != null else 1
		var stack: int = int(node.get("stack_level")) if node.get("stack_level") != null else 1
		var key: String = "furn%d" % node.get_instance_id()
		alive[key] = true
		var sig: String = "%s|%s|%d|%d|%d|%d" % [build_id, str(anchor), rotation_index, fx, fy, stack]

		if _items.has(key) and _items[key]["signature"] == sig:
			continue

		# FurnitureFootprint 와 같은 규칙: 칸 중심이 정수, 두께(depth_ratio)는 회전에 따라 한쪽 변에 붙는다.
		var lo := Vector2(float(anchor.x) - 0.5, float(anchor.y) - 0.5)
		var hi := Vector2(float(anchor.x + fx) - 0.5, float(anchor.y + fy) - 0.5)
		var depth: float = row["depth_ratio"]

		if depth < 1.0:
			match posmod(rotation_index, 4):
				0:
					hi.y = lo.y + depth
				1:
					hi.x = lo.x + depth
				2:
					lo.y = hi.y - depth
				3:
					lo.x = hi.x - depth

		var height_blocks: float = float(row["height_blocks"]) + float(row["stack_step_blocks"]) * float(maxi(stack - 1, 0))
		_set_item(key, lo, hi, height_blocks, str(row["texture"]), row["tint"], sig)

	for key in _items.keys():
		if str(key).begins_with("furn") and not alive.has(key):
			_remove_item(key)


# ---------------------------------------------------------------- 상자 만들기·지우기

func _make_surface_material(kind: String, tint: Color) -> ShaderMaterial:
	if not _texture_cache.has(kind):
		_texture_cache[kind] = {"albedo": PlaceholderTextures.albedo(kind, TEXTURE_SIZE), "normal": PlaceholderTextures.normal(kind, TEXTURE_SIZE)}

	var m := ShaderMaterial.new()
	m.shader = SURFACE_SHADER
	m.set_shader_parameter("albedo_tex", _texture_cache[kind]["albedo"])
	m.set_shader_parameter("normal_tex", _texture_cache[kind]["normal"])
	m.set_shader_parameter("use_normal", true)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("texel_per_unit", 1.0)
	return m


func _set_item(key: String, lo: Vector2, hi: Vector2, height_blocks: float, texture_kind: String, tint: Color, signature: String) -> void:
	_remove_item(key)
	var h: float = block_height(height_blocks)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(hi.x - lo.x, h, hi.y - lo.y)
	var material: ShaderMaterial = _make_surface_material(texture_kind, tint)
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.layers = 1
	inst.material_override = material
	inst.position = Vector3((lo.x + hi.x) * 0.5, h * 0.5, (lo.y + hi.y) * 0.5)
	_viewport.add_child(inst)
	var id_inst := MeshInstance3D.new()
	id_inst.mesh = mesh
	id_inst.layers = 2
	id_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var id_material := ShaderMaterial.new()
	id_material.shader = ID_SHADER
	id_inst.material_override = id_material
	id_inst.position = inst.position
	_viewport.add_child(id_inst)
	_items[key] = {"mesh": inst, "material": material, "id_mesh": id_inst, "id_material": id_material, "min": Vector3(lo.x, lo.y, 0.0), "max": Vector3(hi.x, hi.y, height_blocks * BLOCK_PX), "center": inst.position, "signature": signature}


func _remove_item(key: String) -> void:
	if not _items.has(key):
		return

	(_items[key]["mesh"] as Node).queue_free()
	(_items[key]["id_mesh"] as Node).queue_free()
	_items.erase(key)


# ---------------------------------------------------------------- 사람

func _collect_actor_nodes() -> Array:
	var nodes: Array = []

	if player != null:
		nodes.append(player)

	for group_name in ["customer", "worker", "story_npc", "merchant_npc"]:
		for n in get_tree().get_nodes_in_group(group_name):
			if n is Node2D and not nodes.has(n):
				nodes.append(n)

	return nodes


func _sync_actors(delta: float) -> void:
	var seen: Dictionary = {}

	for n in _collect_actor_nodes():
		var id: int = n.get_instance_id()
		seen[id] = true

		if not _actors.has(id):
			var figure := BlockyFigure.new()
			figure.build(_viewport, _viewport, ACTOR_HEAD_RATIO, ACTOR_TOTAL, ACTOR_TORSO)
			_actors[id] = {"node": n, "figure": figure, "cell": world_to_cell((n as Node2D).global_position)}

		var entry: Dictionary = _actors[id]
		var figure: BlockyFigure = entry["figure"]
		var cell: Vector2 = world_to_cell((n as Node2D).global_position)
		var move: Vector2 = cell - (entry["cell"] as Vector2)
		entry["cell"] = cell
		figure.set_shown((n as Node2D).is_visible_in_tree())
		figure.walking = move.length() > 0.0005 and delta > 0.0

		if move.length() > 0.0005:
			figure.facing_yaw_deg = rad_to_deg(atan2(move.x, move.y))

		figure.animate(delta)

	for id in _actors.keys():
		if not seen.has(id):
			(_actors[id]["figure"] as BlockyFigure).destroy()
			_actors.erase(id)


# ---------------------------------------------------------------- 정렬·깊이 순서

func _sort_and_update() -> void:
	var boxes: Array = []

	for key in _items.keys():
		boxes.append({"id": key, "min": _items[key]["min"], "max": _items[key]["max"]})

	for id in _actors.keys():
		var cell: Vector2 = _actors[id]["cell"]
		boxes.append({"id": "a%d" % id, "min": Vector3(cell.x - ACTOR_HALF, cell.y - ACTOR_HALF, 0.0), "max": Vector3(cell.x + ACTOR_HALF, cell.y + ACTOR_HALF, ACTOR_HEIGHT_PX)})

	var result: Dictionary = IsoSorter.sort_items(boxes)
	var rank_of: Dictionary = {}

	for i in range(result["order"].size()):
		rank_of[result["order"][i]] = float(i)

	var count: float = float(boxes.size())

	for key in _items.keys():
		var it: Dictionary = _items[key]
		var rank: float = rank_of[key]
		var m: ShaderMaterial = it["material"]
		m.set_shader_parameter("rank", rank)
		m.set_shader_parameter("rank_count", count)
		m.set_shader_parameter("center_world", it["center"])
		var idm: ShaderMaterial = it["id_material"]
		idm.set_shader_parameter("rank", rank)
		idm.set_shader_parameter("rank_count", count)
		idm.set_shader_parameter("id", (rank + 1.0) / (count + 1.0))

	if _ground_material != null:
		_ground_material.set_shader_parameter("rank", -1.0)
		_ground_material.set_shader_parameter("rank_count", count)
		_ground_material.set_shader_parameter("center_world", _ground_mesh.position)
		_ground_id_material.set_shader_parameter("rank", -1.0)
		_ground_id_material.set_shader_parameter("rank_count", count)
		_ground_id_material.set_shader_parameter("id", 0.0)

	for id in _actors.keys():
		var entry: Dictionary = _actors[id]
		var figure: BlockyFigure = entry["figure"]
		var cell: Vector2 = entry["cell"]
		var foot := Vector3(cell.x, 0.0, cell.y)
		figure.position = _snap(foot)
		var r: float = rank_of["a%d" % id]
		figure.sync_sort(r, count, _camera, (r + 1.0) / (count + 1.0))
