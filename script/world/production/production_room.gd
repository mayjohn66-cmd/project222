extends Node2D


@export var columns: int = 6
@export var rows: int = 6
@export var tile_width: float = 96.0
@export var tile_height: float = 48.0


func _ready() -> void:
	z_index = -10

	_apply_saved_expansion_size()

	if not GameState.production_room_expansion_changed.is_connected(
		_on_production_room_expansion_changed
	):
		GameState.production_room_expansion_changed.connect(
			_on_production_room_expansion_changed
		)

	_rebuild_boundary_collision()
	_create_return_door_visual()
	queue_redraw()


func grid_to_local(cell: Vector2i) -> Vector2:
	return Vector2(
		(cell.x - cell.y) * tile_width * 0.5,
		(cell.x + cell.y) * tile_height * 0.5
	)


func get_entry_cell() -> Vector2i:
	return Vector2i(0, floori(float(rows) / 2.0))


func get_entry_world_position() -> Vector2:
	return to_global(grid_to_local(get_entry_cell()))


func _add_edge(
	body: StaticBody2D,
	point_a: Vector2,
	point_b: Vector2
) -> void:
	var shape := SegmentShape2D.new()
	shape.a = point_a
	shape.b = point_b

	var collision := CollisionShape2D.new()
	collision.shape = shape
	body.add_child(collision)



func _create_return_door_visual() -> void:
	var existing_visual: Node = (
		get_node_or_null(
			"ReturnDoorVisual"
		)
	)

	if is_instance_valid(existing_visual):
		existing_visual.free()

	var door_scene: PackedScene = load(
		"res://scenes/shop/production/production_door.tscn"
	) as PackedScene

	if door_scene == null:
		push_error("[생산실] 문 씬을 찾지 못했습니다.")
		return

	var template: Node = door_scene.instantiate()
	var source_visual: Node = template.get_node_or_null("Visual")

	if not source_visual is Node2D:
		template.free()
		push_error("[생산실] 문의 Visual을 찾지 못했습니다.")
		return

	var door_visual: Node2D = source_visual.duplicate() as Node2D
	template.free()

	door_visual.name = "ReturnDoorVisual"

	# 생산실 바닥의 -10을 상속하지 않음
	door_visual.z_as_relative = false
	door_visual.z_index = 0

	add_child(door_visual)

	# 입구는 x = 0이므로 왼쪽 위 벽에 표시
	door_visual.position = grid_to_local(get_entry_cell()) + Vector2(-tile_width*0.25,-tile_height*0.25)

	door_visual.set("tile_width", tile_width)
	door_visual.set("tile_height", tile_height)

	if door_visual.has_method("set_rotation_index"):
		door_visual.call("set_rotation_index", 3)

func local_to_grid(pos: Vector2) -> Vector2i:
	var column: float = (
		pos.x / tile_width
		+ pos.y / tile_height
	)

	var row: float = (
		pos.y / tile_height
		- pos.x / tile_width
	)

	return Vector2i(
		roundi(column),
		roundi(row)
	)


func is_cell_inside(cell: Vector2i) -> bool:
	return (
		cell.x >= 0
		and cell.x < columns
		and cell.y >= 0
		and cell.y < rows
	)


func is_cell_buildable(cell: Vector2i) -> bool:
	if not is_cell_inside(cell):
		return false

	var entry_cell: Vector2i = get_entry_cell()

	# 복귀 위치와 바로 안쪽 한 칸은 비워둠
	if cell == entry_cell:
		return false

	if cell == entry_cell + Vector2i(1, 0):
		return false

	return true

func enter_actor(actor: Node2D) -> bool:
	if not is_instance_valid(actor):
		return false

	_stop_actor_movement(actor)

	actor.global_position = (
		get_entry_world_position()
	)

	_reset_actor_camera(actor)

	DebugLog.write(
		"[생산실] 입장 / ",
		actor.name
	)

	return true


func exit_actor(
	actor: Node2D,
	return_door: Node2D
) -> bool:
	if not is_instance_valid(actor):
		return false

	if not is_instance_valid(return_door):
		return false

	if return_door.is_queued_for_deletion():
		return false

	var return_world: Vector2

	if return_door.has_method(
		"get_return_world_position"
	):
		return_world = (
			return_door.get_return_world_position()
		)
	else:
		var store_floor: Node = get_node_or_null(
			"../Floor"
		)

		if store_floor == null:
			return false

		var return_cell: Vector2i = (
			return_door.get_meta(
				"anchor",
				Vector2i(-1, -1)
			)
		)

		if return_cell.x < 0 or return_cell.y < 0:
			return false

		return_world = store_floor.to_global(
			store_floor.grid_to_local(
				return_cell
			)
		)

	_stop_actor_movement(actor)

	actor.global_position = return_world

	_reset_actor_camera(actor)

	DebugLog.write(
		"[생산실] 퇴장 / ",
		actor.name
	)

	return true


func _stop_actor_movement(
	actor: Node2D
) -> void:
	if actor is CharacterBody2D:
		var body := actor as CharacterBody2D
		body.velocity = Vector2.ZERO


func _reset_actor_camera(
	actor: Node2D
) -> void:
	var camera := (
		actor.get_node_or_null("Camera2D")
		as Camera2D
	)

	if camera != null:
		camera.reset_smoothing()

func get_facility_approach_position(
	facility: Node2D
) -> Vector2:
	if not is_instance_valid(facility):
		return get_entry_world_position()

	var anchor: Vector2i = facility.get_meta(
		"anchor",
		Vector2i(-1, -1)
	)

	if not is_cell_inside(anchor):
		# 배치 좌표가 없는 설비의 임시 대응
		var direction: Vector2 = (
			get_entry_world_position()
			- facility.global_position
		).normalized()

		if direction == Vector2.ZERO:
			direction = Vector2.LEFT

		return (
			facility.global_position
			+ direction * tile_height
		)

	var occupied_cells: Array[Vector2i] = (
		_get_facility_cells(
			facility,
			anchor
		)
	)

	var occupied_lookup: Dictionary = {}

	for occupied_cell in occupied_cells:
		occupied_lookup[occupied_cell] = true

	var directions: Array[Vector2i] = [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1)
	]

	var entry_cell: Vector2i = get_entry_cell()
	var best_cell := Vector2i(-1, -1)
	var best_distance: int = 2147483647
	var checked: Dictionary = {}

	for occupied_cell in occupied_cells:
		for direction in directions:
			var candidate: Vector2i = (
				occupied_cell + direction
			)

			if checked.has(candidate):
				continue

			checked[candidate] = true

			if occupied_lookup.has(candidate):
				continue

			if not is_cell_inside(candidate):
				continue

			var distance: int = (
				absi(candidate.x - entry_cell.x)
				+ absi(candidate.y - entry_cell.y)
			)

			if distance < best_distance:
				best_distance = distance
				best_cell = candidate

	if best_cell == Vector2i(-1, -1):
		return get_entry_world_position()

	return to_global(
		grid_to_local(best_cell)
	)


func _get_facility_cells(
	facility: Node2D,
	anchor: Vector2i
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []

	var build_id: String = str(
		facility.get_meta(
			"build_id",
			""
		)
	)

	var size := Vector2i.ONE

	if not build_id.is_empty():
		var build_data: Dictionary = (
			BuildObjectData.get_build_object(
				build_id
			)
		)

		if not build_data.is_empty():
			size = build_data.get(
				"grid_size",
				Vector2i.ONE
			)

	var rotation_index: int = int(
		facility.get_meta(
			"rotation_index",
			0
		)
	)

	if rotation_index % 2 != 0:
		size = Vector2i(
			size.y,
			size.x
		)

	for y in range(size.y):
		for x in range(size.x):
			result.append(
				anchor + Vector2i(x, y)
			)

	return result

func _apply_saved_expansion_size() -> void:
	var room_size: Vector2i = (
		GameState.get_production_room_size()
	)

	columns = maxi(
		room_size.x,
		1
	)

	rows = maxi(
		room_size.y,
		1
	)

	DebugLog.write(
		"[생산실] 저장된 크기 적용 / ",
		room_size
	)


func _on_production_room_expansion_changed(
	_previous_level: int,
	new_level: int,
	new_room_size: Vector2i
) -> void:
	columns = maxi(
		new_room_size.x,
		1
	)

	rows = maxi(
		new_room_size.y,
		1
	)

	queue_redraw()
	_rebuild_boundary_collision()
	_create_return_door_visual()

	DebugLog.write(
		"[생산실] 확장 적용 / 단계: ",
		new_level,
		" / 크기: ",
		new_room_size
	)


func _rebuild_boundary_collision() -> void:
	var existing_boundary: Node = (
		get_node_or_null(
			"ProductionRoomBoundary"
		)
	)

	if is_instance_valid(existing_boundary):
		existing_boundary.free()

	var boundary := StaticBody2D.new()
	boundary.name = "ProductionRoomBoundary"
	boundary.collision_layer = 1
	boundary.collision_mask = 0

	add_child(
		boundary
	)

	for y in range(rows):
		for x in range(columns):
			var cell := Vector2i(
				x,
				y
			)

			var center: Vector2 = (
				grid_to_local(
					cell
				)
			)

			var top := center + Vector2(
				0,
				-tile_height * 0.5
			)

			var right := center + Vector2(
				tile_width * 0.5,
				0
			)

			var bottom := center + Vector2(
				0,
				tile_height * 0.5
			)

			var left := center + Vector2(
				-tile_width * 0.5,
				0
			)

			if x == 0:
				_add_edge(
					boundary,
					left,
					top
				)

			if x == columns - 1:
				_add_edge(
					boundary,
					right,
					bottom
				)

			if y == 0:
				_add_edge(
					boundary,
					top,
					right
				)

			if y == rows - 1:
				_add_edge(
					boundary,
					bottom,
					left
				)
