@tool
extends Node2D
const TILE_ART = preload("res://script/world/shop/world_tile_art.gd")


# 기존 매장 크기
@export var columns: int = 10:
	set(value):
		columns = maxi(value, 1)
		queue_redraw()

@export var rows: int = 8:
	set(value):
		rows = maxi(value, 1)
		queue_redraw()

@export var tile_width: float = 96.0:
	set(value):
		tile_width = maxf(value, 1.0)
		queue_redraw()

@export var tile_height: float = 48.0:
	set(value):
		tile_height = maxf(value, 1.0)
		queue_redraw()

# 생산 구역
@export var production_columns: int = 6:
	set(value):
		production_columns = maxi(value, 1)
		queue_redraw()

@export var production_rows: int = 6:
	set(value):
		production_rows = maxi(value, 1)
		queue_redraw()

# 매장과 생산 구역 사이 통로
@export var corridor_length: int = 2:
	set(value):
		corridor_length = maxi(value, 1)
		queue_redraw()

@export var corridor_width: int = 2:
	set(value):
		corridor_width = maxi(value, 1)
		queue_redraw()


#====================================================


# 설치된 문의 위치나 방향이 변경되었는지 확인하는 값
var door_boundary_signature: String = ""

# 같은 프레임에 경계 충돌이 여러 번 갱신되는 것을 방지한다.
var boundary_rebuild_pending: bool = false


#======================================================


func get_store_rect() -> Rect2i:
	return Rect2i(
		0,
		0,
		columns,
		rows
	)


func get_production_rect() -> Rect2i:
	# 생산 구역을 매장 오른쪽 아래 방향에 연결
	var start_row: int = floori(
		float(rows - production_rows) / 2.0
	)

	return Rect2i(
		columns + corridor_length,
		start_row,
		production_columns,
		production_rows
	)


func get_corridor_rect() -> Rect2i:
	var production_rect: Rect2i = get_production_rect()

	# 두 구역이 공통으로 접할 수 있는 행 범위
	var overlap_start: int = maxi(
		0,
		production_rect.position.y
	)

	var overlap_end: int = mini(
		rows,
		production_rect.end.y
	)

	var actual_width: int = mini(
		corridor_width,
		overlap_end - overlap_start
	)

	var start_row: int = overlap_start + floori(
		float(
			overlap_end - overlap_start - actual_width
		) / 2.0
	)

	return Rect2i(
		columns,
		start_row,
		corridor_length,
		actual_width
	)


func _draw() -> void:
	_draw_region(
		get_store_rect(),
		Color(0.35, 0.38, 0.35)
	)

func _draw_region(region: Rect2i, _fill_color: Color) -> void:
	for row in range(region.position.y, region.end.y):
		for column in range(region.position.x, region.end.x):
			TILE_ART.draw_cell(self, grid_to_local(Vector2i(column, row)), tile_width, tile_height, TILE_ART.WOOD)


func grid_to_local(cell: Vector2i) -> Vector2:
	return Vector2(
		(cell.x - cell.y) * tile_width * 0.5,
		(cell.x + cell.y) * tile_height * 0.5
	)


func local_to_grid(pos: Vector2) -> Vector2i:
	var column: float = (
		pos.x / tile_width + pos.y / tile_height
	)

	var row: float = (
		pos.y / tile_height - pos.x / tile_width
	)

	return Vector2i(
		roundi(column),
		roundi(row)
	)


# 기존 호출과의 호환성: 매장 범위
func is_cell_inside(cell: Vector2i) -> bool:
	return is_store_cell(cell)

func is_store_cell(cell: Vector2i) -> bool:
	return get_store_rect().has_point(cell)


# 플레이어 이동 등에 사용할 전체 바닥 범위
func is_world_cell_inside(cell: Vector2i) -> bool:
	return is_store_cell(cell)

func _ready() -> void:
	z_index = -10

	if Engine.is_editor_hint():
		return

	# 저장된 확장 단계에 맞는 내부 크기를 적용한다.
	_apply_saved_expansion_size()

	if not GameState.store_expansion_changed.is_connected(
		_on_store_expansion_changed
	):
		GameState.store_expansion_changed.connect(
			_on_store_expansion_changed
		)

	# 현재 문 배치 상태를 기록한다.
	door_boundary_signature = (
		_get_door_boundary_signature()
	)

	# 현재 매장 크기와 문 위치를 기준으로 경계를 만든다.
	_create_boundary_collision()

func _process(
	_delta: float
) -> void:
	if Engine.is_editor_hint():
		return

	var new_signature: String = (
		_get_door_boundary_signature()
	)

	if new_signature == door_boundary_signature:
		return

	door_boundary_signature = new_signature

	request_boundary_rebuild()

func request_boundary_rebuild() -> void:
	if boundary_rebuild_pending:
		return

	boundary_rebuild_pending = true

	call_deferred(
		"_rebuild_boundary_collision"
	)


func _rebuild_boundary_collision() -> void:
	boundary_rebuild_pending = false

	if not is_inside_tree():
		return

	_create_boundary_collision()

# GameState가 보관 중인 확장 단계로
# 현재 매장 바닥의 가로·세로 크기를 결정한다.
func _apply_saved_expansion_size() -> void:
	var expansion_level: int = (
		GameState.get_store_expansion_level()
	)

	var store_size: Vector2i = (
		GameState.get_store_size()
	)

	columns = store_size.x
	rows = store_size.y

	DebugLog.write(
		"[매장 확장] 단계: ",
		expansion_level,
		" / 내부 크기: ",
		store_size
	)

# 매장 확장 구매가 완료되면 현재 바닥 크기를 즉시 갱신한다.
func _on_store_expansion_changed(
	_previous_level: int,
	new_level: int,
	new_store_size: Vector2i
) -> void:
	columns = maxi(
		new_store_size.x,
		1
	)

	rows = maxi(
		new_store_size.y,
		1
	)

	queue_redraw()

	# 바뀐 크기를 기준으로 벽 충돌을 다시 만든다.
	request_boundary_rebuild()

	DebugLog.write(
		"[매장 바닥] 확장 적용 / 단계: ",
		new_level,
		" / 크기: ",
		new_store_size
	)

func _create_boundary_collision() -> void:
	# 이전에 만든 경계가 있으면 먼저 제거한다.
	var existing_boundary: Node = (
		get_node_or_null(
			"FloorBoundary"
		)
	)

	if is_instance_valid(
		existing_boundary
	):
		existing_boundary.free()

	var boundary := StaticBody2D.new()

	boundary.name = "FloorBoundary"
	boundary.collision_layer = 1
	boundary.collision_mask = 0

	add_child(
		boundary
	)

	var regions: Array[Rect2i] = [
		get_store_rect()
	]

	for region in regions:
		for row in range(
			region.position.y,
			region.end.y
		):
			for column in range(
				region.position.x,
				region.end.x
			):
				_add_cell_boundary(
					boundary,
					Vector2i(
						column,
						row
					)
				)

	_refresh_wood_walls.call_deferred(boundary)

func _refresh_wood_walls(boundary: StaticBody2D) -> void:
	if not is_instance_valid(boundary): return
	var walls = get_parent().get_node_or_null("WoodWalls")
	if walls == null:
		walls = preload("res://script/world/shop/wood_walls.gd").new()
		walls.name = "WoodWalls"
		get_parent().add_child(walls)
	walls.global_position = global_position
	walls.rebuild(self,boundary)

# 설치된 문들의 위치와 방향을 문자열로 만든다.
# 값이 달라지면 문이 설치·이동·철거된 것으로 판단한다.
func _get_door_boundary_signature() -> String:
	var signature_parts: Array[String] = []

	var doors: Array = (
		get_tree().get_nodes_in_group(
			"door"
		)
	)

	for door in doors:
		if not is_instance_valid(door):
			continue

		if door.is_queued_for_deletion():
			continue

		# 건축 미리보기 문은 실제 출입구가 아니다.
		if bool(
			door.get_meta(
				"is_build_preview",
				false
			)
		):
			continue

		if not door.has_meta("anchor"):
			continue

		var anchor: Vector2i = (
			door.get_meta(
				"anchor",
				Vector2i(-1, -1)
			)
		)

		var rotation_index: int = int(
			door.get_meta(
				"rotation_index",
				-1
			)
		)

		signature_parts.append(
			"%d:%d:%d"
			% [
				anchor.x,
				anchor.y,
				rotation_index
			]
		)

	signature_parts.sort()

	var result: String = ""

	for signature_part in signature_parts:
		result += signature_part + ";"

	return result


# 특정 셀의 특정 방향에 실제 문이 설치되어 있는지 확인한다.
func _has_door_opening(
	cell: Vector2i,
	required_rotation: int
) -> bool:
	var doors: Array = (
		get_tree().get_nodes_in_group(
			"door"
		)
	)

	for door in doors:
		if not is_instance_valid(door):
			continue

		if door.is_queued_for_deletion():
			continue

		if bool(
			door.get_meta(
				"is_build_preview",
				false
			)
		):
			continue

		var door_cell: Vector2i = (
			door.get_meta(
				"anchor",
				Vector2i(-1, -1)
			)
		)

		var door_rotation: int = int(
			door.get_meta(
				"rotation_index",
				-1
			)
		)

		if (
			door_cell == cell
			and door_rotation == required_rotation
		):
			return true

	return false

func _add_cell_boundary(
	boundary: StaticBody2D,
	cell: Vector2i
) -> void:
	var center: Vector2 = grid_to_local(
		cell
	)

	var top: Vector2 = center + Vector2(
		0,
		-tile_height * 0.5
	)

	var right: Vector2 = center + Vector2(
		tile_width * 0.5,
		0
	)

	var bottom: Vector2 = center + Vector2(
		0,
		tile_height * 0.5
	)

	var left: Vector2 = center + Vector2(
		-tile_width * 0.5,
		0
	)

	# 오른쪽 경계
	if not is_world_cell_inside(
		cell + Vector2i(1, 0)
	):
		if not _has_door_opening(
			cell,
			1
		):
			BoundarySegment.add(
				boundary,
				right,
				bottom
			)

	# 왼쪽 경계
	if not is_world_cell_inside(
		cell + Vector2i(-1, 0)
	):
		if not _has_door_opening(
			cell,
			3
		):
			BoundarySegment.add(
				boundary,
				left,
				top
			)

	# 아래쪽 경계
	if not is_world_cell_inside(
		cell + Vector2i(0, 1)
	):
		if not _has_door_opening(
			cell,
			2
		):
			BoundarySegment.add(
				boundary,
				bottom,
				left
			)

	# 위쪽 경계
	if not is_world_cell_inside(
		cell + Vector2i(0, -1)
	):
		if not _has_door_opening(
			cell,
			0
		):
			BoundarySegment.add(
				boundary,
				top,
				right
			)
