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
