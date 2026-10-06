@tool
extends Node2D



@export var columns: int = 6:
	set(value):
		columns = maxi(value, 1)
		queue_redraw()


@export var rows: int = 5:
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


var boundary_body: StaticBody2D = null
var return_door_visual: Node2D = null


func _enter_tree() -> void:
	queue_redraw()


func _ready() -> void:
	if Engine.is_editor_hint():
		# 에디터 미리보기는 다른 노드 뒤로 숨지 않도록 한다.
		z_index = 0
		queue_redraw()
		return

	z_index = -10

	_apply_saved_warehouse_size()
	_rebuild_warehouse()

	if not GameState.warehouse_expansion_changed.is_connected(
		_on_warehouse_expansion_changed
	):
		GameState.warehouse_expansion_changed.connect(
			_on_warehouse_expansion_changed
		)


func _apply_saved_warehouse_size() -> void:
	var warehouse_size: Vector2i = (
		GameState.get_warehouse_size()
	)

	columns = maxi(warehouse_size.x, 1)
	rows = maxi(warehouse_size.y, 1)


func _on_warehouse_expansion_changed(
	_previous_level: int,
	_new_level: int,
	new_warehouse_size: Vector2i
) -> void:
	columns = maxi(new_warehouse_size.x, 1)
	rows = maxi(new_warehouse_size.y, 1)

	_rebuild_warehouse()

	DebugLog.write(
		"[창고] 크기 변경 완료 / ",
		columns,
		" × ",
		rows
	)


func _rebuild_warehouse() -> void:
	_clear_boundary()
	_clear_return_door_visual()

	_create_boundary()
	_create_return_door_visual()

	queue_redraw()

func _clear_return_door_visual() -> void:
	if not is_instance_valid(return_door_visual):
		return

	return_door_visual.free()
	return_door_visual = null

func _create_return_door_visual() -> void:
	var door_scene: PackedScene = load(
		"res://scenes/shop/objects/door.tscn"
	) as PackedScene

	if door_scene == null:
		push_error(
			"[창고] 문 씬을 찾지 못했습니다."
		)
		return

	var template: Node = (
		door_scene.instantiate()
	)

	var source_visual: Node = (
		template.get_node_or_null(
			"Visual"
		)
	)

	if not source_visual is Node2D:
		template.free()

		push_error(
			"[창고] 문의 Visual을 찾지 못했습니다."
		)
		return

	return_door_visual = (
		source_visual.duplicate()
		as Node2D
	)

	template.free()

	if not is_instance_valid(
		return_door_visual
	):
		return

	return_door_visual.name = (
		"ReturnDoorVisual"
	)

	# WarehouseRoom의 음수 Z 값을 상속하지 않는다.
	return_door_visual.z_as_relative = false
	return_door_visual.z_index = 0

	add_child(
		return_door_visual
	)

	return_door_visual.position = (
		grid_to_local(
			get_entry_cell()
		)
		+ Vector2(
			-tile_width * 0.25,
			-tile_height * 0.25
		)
	)

	return_door_visual.set(
		"tile_width",
		tile_width
	)

	return_door_visual.set(
		"tile_height",
		tile_height
	)

	if return_door_visual.has_method(
		"set_rotation_index"
	):
		return_door_visual.call(
			"set_rotation_index",
			3
		)

func _clear_boundary() -> void:
	if not is_instance_valid(boundary_body):
		return

	boundary_body.free()
	boundary_body = null


func _create_boundary() -> void:
	boundary_body = StaticBody2D.new()
	boundary_body.name = "Boundary"
	boundary_body.collision_layer = 1
	boundary_body.collision_mask = 0

	add_child(boundary_body)

	for y in range(rows):
		for x in range(columns):
			var cell := Vector2i(x, y)
			var center: Vector2 = grid_to_local(cell)

			var top := center + Vector2(
				0.0,
				-tile_height * 0.5
			)

			var right := center + Vector2(
				tile_width * 0.5,
				0.0
			)

			var bottom := center + Vector2(
				0.0,
				tile_height * 0.5
			)

			var left := center + Vector2(
				-tile_width * 0.5,
				0.0
			)

			if x == 0:
				_add_boundary_edge(
					left,
					top
				)

			if x == columns - 1:
				_add_boundary_edge(
					right,
					bottom
				)

			if y == 0:
				_add_boundary_edge(
					top,
					right
				)

			if y == rows - 1:
				_add_boundary_edge(
					bottom,
					left
				)


func _add_boundary_edge(
	point_a: Vector2,
	point_b: Vector2
) -> void:
	if not is_instance_valid(boundary_body):
		return

	var segment := SegmentShape2D.new()
	segment.a = point_a
	segment.b = point_b

	var collision := CollisionShape2D.new()
	collision.shape = segment

	boundary_body.add_child(collision)



func grid_to_local(
	cell: Vector2i
) -> Vector2:
	return Vector2(
		(cell.x - cell.y)
			* tile_width
			* 0.5,

		(cell.x + cell.y)
			* tile_height
			* 0.5
	)


func local_to_grid(
	local_position: Vector2
) -> Vector2i:
	var column: float = (
		local_position.x / tile_width
		+ local_position.y / tile_height
	)

	var row: float = (
		local_position.y / tile_height
		- local_position.x / tile_width
	)

	return Vector2i(
		roundi(column),
		roundi(row)
	)


func is_cell_inside(
	cell: Vector2i
) -> bool:
	return (
		cell.x >= 0
		and cell.x < columns
		and cell.y >= 0
		and cell.y < rows
	)


func get_entry_cell() -> Vector2i:
	return Vector2i(
		0,
		floori(float(rows) / 2.0)
	)


func get_entry_world_position() -> Vector2:
	return to_global(
		grid_to_local(
			get_entry_cell()
		)
	)


func is_cell_buildable(
	cell: Vector2i
) -> bool:
	if not is_cell_inside(cell):
		return false

	var entry_cell: Vector2i = get_entry_cell()

	# 창고 출입구와 바로 안쪽 통로는 비워둔다.
	if cell == entry_cell:
		return false

	if cell == entry_cell + Vector2i(1, 0):
		return false

	return true

func enter_actor(
	actor: Node2D
) -> bool:
	if not ShopSpaceProgression.room_ready("warehouse"): return false
	if not is_instance_valid(actor):
		return false

	_stop_actor_movement(actor)
	ShopSpaceProgression.entered("warehouse")

	actor.global_position = (
		get_entry_world_position()
	)

	_reset_actor_camera(actor)

	DebugLog.write(
		"[창고] 입장 / ",
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
			return_door.call(
				"get_return_world_position"
			)
		)

	else:
		var store_floor: Node = (
			get_node_or_null(
				"../Floor"
			)
		)

		if not is_instance_valid(store_floor):
			return false

		var return_cell: Vector2i = (
			return_door.get_meta(
				"anchor",
				Vector2i(-1, -1)
			)
		)

		if return_cell.x < 0 or return_cell.y < 0:
			return false

		return_world = (
			store_floor.to_global(
				store_floor.grid_to_local(
					return_cell
				)
			)
		)

	_stop_actor_movement(actor)

	actor.global_position = return_world

	_reset_actor_camera(actor)

	DebugLog.write(
		"[창고] 퇴장 / ",
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
		actor.get_node_or_null(
			"Camera2D"
		)
		as Camera2D
	)

	if camera != null:
		camera.reset_smoothing()
