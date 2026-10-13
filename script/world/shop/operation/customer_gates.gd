class_name CustomerGates
extends RefCounted
## 손님이 나타나고 사라지는 "거리 끝(게이트)". 카메라에 보이는 영역 밖에서만 생기고 사라지게 한다.
## 도로 끝 칸에서 바깥 방향으로 화면 밖 지점을 찾고, 안전망으로 짧게 투명도를 섞는다. 수치는 customer_gates.csv.

const PATH: String = "res://data/shop/catalogs/customer/customer_gates.csv"
const DEFAULTS: Dictionary = {"margin_px": 96.0, "max_extend_cells": 14.0, "fade_seconds": 0.5}

static var values: Dictionary = {}
static var _loaded: bool = false


static func value(key: String) -> float:
	if not _loaded:
		_loaded = true
		values = DEFAULTS.duplicate()
		var file := FileAccess.open(PATH, FileAccess.READ)
		if file != null:
			var header: PackedStringArray = file.get_csv_line()
			var indexes: Dictionary = {}
			for i in range(header.size()):
				indexes[header[i].strip_edges()] = i
			while not file.eof_reached():
				var row: PackedStringArray = file.get_csv_line()
				var name: String = CsvReader.get_cell(row, indexes, "key")
				if not name.is_empty() and not name.begins_with("#"):
					values[name] = float(CsvReader.get_cell(row, indexes, "value"))
	return float(values.get(key, DEFAULTS.get(key, 0.0)))


# 카메라가 비추는 월드 영역. 카메라가 없으면 빈 영역(= 어디든 화면 밖으로 본다).
static func visible_world_rect(node: Node) -> Rect2:
	var viewport: Viewport = node.get_viewport() if node != null and node.is_inside_tree() else null
	if viewport == null:
		return Rect2()
	var camera: Camera2D = viewport.get_camera_2d()
	var size: Vector2 = viewport.get_visible_rect().size
	if camera == null or size == Vector2.ZERO:
		return Rect2()
	var zoom: Vector2 = camera.zoom
	var world_size := Vector2(size.x / maxf(zoom.x, 0.01), size.y / maxf(zoom.y, 0.01))
	return Rect2(camera.get_screen_center_position() - world_size * 0.5, world_size)


# 도로 끝 칸이 바깥으로 향하는 방향(부지 왼쪽 끝은 -x, 위쪽 끝은 -y). 끝 칸이 아니면 0.
static func outward(exterior_rect: Rect2i, end_cell: Vector2i) -> Vector2i:
	if end_cell.x <= exterior_rect.position.x:
		return Vector2i(-1, 0)
	if end_cell.y <= exterior_rect.position.y:
		return Vector2i(0, -1)
	return Vector2i.ZERO


# 도로 끝 칸에서 바깥으로 밀어 화면 밖인 첫 지점(월드 좌표)을 돌려준다.
static func gate_position(exterior: Node2D, end_cell: Vector2i) -> Vector2:
	var end_world: Vector2 = exterior.to_global(exterior.grid_to_local(end_cell))
	var direction: Vector2i = outward(exterior.get_exterior_rect(), end_cell)
	if direction == Vector2i.ZERO:
		return end_world
	var view: Rect2 = visible_world_rect(exterior).grow(value("margin_px"))
	var position: Vector2 = end_world
	for step in range(int(value("max_extend_cells")) + 1):
		position = exterior.to_global(exterior.grid_to_local(end_cell + direction * step))
		if not view.has_point(position):
			return position
	return position


# 안전망: 나타날 때 투명에서 불투명으로.
static func fade_in(actor: CanvasItem) -> void:
	if not is_instance_valid(actor):
		return
	var seconds: float = value("fade_seconds")
	if seconds <= 0.0:
		return
	actor.modulate.a = 0.0
	actor.create_tween().tween_property(actor, "modulate:a", 1.0, seconds)


# 안전망: 사라질 때 불투명에서 투명으로.
static func fade_out(actor: CanvasItem) -> void:
	if not is_instance_valid(actor):
		return
	var seconds: float = value("fade_seconds")
	if seconds <= 0.0:
		return
	actor.create_tween().tween_property(actor, "modulate:a", 0.0, seconds)


# 이미 화면 안에 보이는 위치인가(지금 사라지거나 나타나면 눈에 띄는가).
static func is_on_screen(actor: Node2D) -> bool:
	return is_instance_valid(actor) and visible_world_rect(actor).has_point(actor.global_position)


# 마을에 서 있는 이야기 인물이 새로 나타날 때: 투명에서 서서히 보이게 한다.
static func appear(actor: CanvasItem) -> void:
	fade_in(actor)


# 서 있던 인물이 사라질 때: 화면 안이면 서서히 사라지고, 화면 밖이면 바로 지운다.
static func dismiss(actor: Node2D) -> void:
	if not is_instance_valid(actor) or actor.is_queued_for_deletion():
		return
	var seconds: float = value("fade_seconds")
	if seconds <= 0.0 or not is_on_screen(actor):
		actor.queue_free()
		return
	# 사라지는 동안에는 상호작용·검색 대상에서 빠진다(같은 인물이 곧바로 다시 나타나도 옛 몸이 섞이지 않게).
	for group_name in actor.get_groups():
		if not str(group_name).begins_with("_"):
			actor.remove_from_group(group_name)
	actor.set_meta("gate_leaving", true)
	var tween: Tween = actor.create_tween()
	tween.tween_property(actor, "modulate:a", 0.0, seconds)
	tween.tween_callback(actor.queue_free)


# 가게 안쪽 입구 문(가구로 놓인 문, 미리보기 제외). 없으면 null.
static func entrance_door(world: Node) -> Node:
	var objects: Node = world.get_node_or_null("Objects")
	for door in world.get_tree().get_nodes_in_group("door"):
		if not is_instance_valid(door) or door.is_queued_for_deletion():
			continue
		if door.get_meta("is_build_preview", false) or door.get_parent() != objects:
			continue
		if door.has_method("get_customer_target_position"):
			return door
	return null


# 문으로 들어와 서는 방문자: 도로 끝(화면 밖)에서 보도를 따라 걸어와 문 안쪽 자리에 선다.
static func walk_in_through_door(actor: Node2D, world: Node, door: Node, inside: Vector2) -> void:
	var exterior := world.get_node_or_null("StoreExterior") as Node2D
	if exterior == null or door == null:
		actor.global_position = inside
		return
	var route: Dictionary = exterior.call("get_random_sidewalk_route_for_door", door)
	if route.is_empty():
		actor.global_position = inside
		return
	var start: Vector2 = gate_position(exterior, route.get("start_cell", Vector2i.ZERO))
	actor.global_position = start
	fade_in(actor)
	var points: Array = []
	if start != route["start_position"]:
		points.append(route["start_position"])
	points.append_array(route.get("approach_positions", []))
	points.append(door.call("get_customer_spawn_position"))
	points.append(inside)
	_walk(actor, points)


# 문으로 나가는 방문자: 문 안쪽에서 보도를 따라 걸어 도로 끝(화면 밖)으로 빠져나가며 사라진다.
static func walk_out_through_door(actor: Node2D, world: Node, door: Node) -> void:
	var exterior := world.get_node_or_null("StoreExterior") as Node2D
	if exterior == null or door == null:
		_fade_and_free(actor)
		return
	var route: Dictionary = exterior.call("get_random_sidewalk_route_for_door", door)
	if route.is_empty():
		_fade_and_free(actor)
		return
	var points: Array = [door.call("get_customer_spawn_position"), route["decision_position"]]
	points.append_array(route.get("pass_positions", []))
	var gate: Vector2 = gate_position(exterior, route.get("finish_cell", Vector2i.ZERO))
	if gate != route["finish_position"]:
		points.append(gate)
	_walk(actor, points, true)


static func _fade_and_free(actor: Node2D) -> void:
	if not is_instance_valid(actor):
		return
	var tween: Tween = actor.create_tween()
	tween.tween_property(actor, "modulate:a", 0.0, 0.5)
	tween.tween_callback(actor.queue_free)


# 경유점을 차례로 걷는다. 끝나면 free_at_end 일 때 지운다. 걷는 동안 몸을 흐리게 해 끝에서 사라지게 한다.
static func _walk(actor: Node2D, points: Array, free_at_end: bool = false) -> void:
	const SPEED := 180.0
	var tween: Tween = actor.create_tween()
	var here: Vector2 = actor.global_position
	var total := 0.0
	for point in points:
		if point is Vector2:
			total += here.distance_to(point) / SPEED
			here = point
	var elapsed := 0.0
	here = actor.global_position
	for point in points:
		if not point is Vector2:
			continue
		var seconds: float = maxf(here.distance_to(point) / SPEED, 0.05)
		tween.tween_property(actor, "global_position", point, seconds)
		here = point
		elapsed += seconds
	if free_at_end:
		tween.tween_property(actor, "modulate:a", 0.0, value("fade_seconds"))
		tween.tween_callback(actor.queue_free)
