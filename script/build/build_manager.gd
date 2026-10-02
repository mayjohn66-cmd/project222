extends Node2D

# 건축 모드의 진입점이다.
# 입력과 UI를 조정하고 실제 배치·이동·철거 판정은 model/service/view에 위임한다.

@warning_ignore("shadowed_global_identifier")
@onready var floor = $"../Floor"
@onready var objects = $"../Objects"
@onready var actors = $"../Actors"
@onready var player: CharacterBody2D = $"../Actors/Player"

@onready var build_quick_slot_bar = $"../UI/BuildQuickSlotBar"
@onready var build_confirm_center: CenterContainer = $"../UI/BuildConfirmCenter"
@onready var build_confirm_panel: PanelContainer = $"../UI/BuildConfirmCenter/BuildConfirmPanel"
@onready var save_build_button: Button = $"../UI/BuildConfirmCenter/BuildConfirmPanel/VBoxContainer/HBoxContainer/SaveButton"
@onready var continue_build_button: Button = $"../UI/BuildConfirmCenter/BuildConfirmPanel/VBoxContainer/HBoxContainer/ContinueButton"

@onready var store_floor = $"../Floor"
@onready var store_objects = $"../Objects"
@onready var production_floor = $"../ProductionRoom"
@onready var production_objects = $"../ProductionRoom/Objects"
@onready var warehouse_floor = $"../WarehouseRoom"
@onready var warehouse_objects = $"../WarehouseRoom/Objects"


var store_occupancy_state
var production_occupancy_state = (
	BUILD_OCCUPANCY_STATE_SCRIPT.new()
)

var building_in_production: bool = false

const BUILD_SELECTION_STATE_SCRIPT = preload(
	"res://script/build/model/build_selection_state.gd"
)

const BUILD_PREVIEW_CONTROLLER_SCRIPT = preload(
	"res://script/build/view/build_preview_controller.gd"
)

const BUILD_OCCUPANCY_STATE_SCRIPT = preload(
	"res://script/build/model/build_occupancy_state.gd"
)


const BUILD_PLACEMENT_SERVICE_SCRIPT = preload(
	"res://script/build/services/build_placement_service.gd"
)

const BuildRemovalServiceScript = preload(
	"res://script/build/services/build_removal_service.gd"
)

const BUILD_MOVE_SERVICE_SCRIPT = preload(
	"res://script/build/services/build_move_service.gd"
)


const BUILD_AREA_RULES_SCRIPT = preload(
	"res://script/build/model/build_area_rules.gd"
)

const BUILD_LAYOUT_SERVICE_SCRIPT = preload(
	"res://script/build/services/build_layout_service.gd"
)

const WAREHOUSE_LAYOUT_PERSISTENCE_SCRIPT = preload(
	"res://script/build/services/warehouse_layout_persistence.gd"
)




# 실행할 때 build_objects.csv에서 생성
var furniture_catalog: Array[String] = []


var build_preview_controller = (
	BUILD_PREVIEW_CONTROLLER_SCRIPT.new()
)


var build_occupancy_state = (
	BUILD_OCCUPANCY_STATE_SCRIPT.new()
)

var build_placement_service = (
	BUILD_PLACEMENT_SERVICE_SCRIPT.new()
)

var build_removal_service = (
	BuildRemovalServiceScript.new()
)

var build_move_service = (
	BUILD_MOVE_SERVICE_SCRIPT.new()
)


var build_area_rules = (
	BUILD_AREA_RULES_SCRIPT.new()
)



var build_mode: bool = false
var hidden_build_ui: Dictionary = {}
var tree_was_paused_before_build: bool = false
var management_input_blocked: bool = false
var warehouse_occupancy_state = (
	BUILD_OCCUPANCY_STATE_SCRIPT.new()
)

var building_in_warehouse: bool = false


var build_layout_service = (
	BUILD_LAYOUT_SERVICE_SCRIPT.new()
)

var decoration_effect_totals: Dictionary = {
	"reputation": 0.0,
	"purchase_desire": 0.0
}


func set_management_input_blocked(blocked: bool) -> void:
	management_input_blocked = blocked


func initialize_furniture_catalog() -> bool:
	furniture_catalog = (
		BuildObjectData.get_all_build_ids()
	)

	if furniture_catalog.is_empty():
		push_error(
			"[건축] 등록된 건축물이 없습니다."
		)

		return false

	return true


func configure_build_removal_service() -> void:
	build_removal_service.configure(
		build_occupancy_state
	)


func configure_build_placement_service() -> void:
	build_placement_service.configure(
		objects,
		build_occupancy_state,
		build_selection_state,
		Callable(
			self,
			"apply_current_size"
		),
		Callable(
			self,
			"get_current_furniture_world_position"
		),
		Callable(
			self,
			"get_occupied_cells"
		),
		Callable(
			self,
			"get_current_reserved_cells"
		),
		Callable(
			self,
			"handle_depleted_build_item"
		)
	)


func configure_build_move_service() -> void:
	build_move_service.configure(
		build_occupancy_state
	)


func _ready() -> void:
	add_to_group("build_manager")
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 90

	store_occupancy_state = build_occupancy_state

	configure_build_placement_service()
	configure_build_removal_service()
	configure_build_move_service()

	build_confirm_center.process_mode = (
		Node.PROCESS_MODE_ALWAYS
	)

	build_confirm_center.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)

	build_confirm_center.mouse_filter = (
		Control.MOUSE_FILTER_STOP
	)

	build_confirm_panel.mouse_filter = (
		Control.MOUSE_FILTER_STOP
	)

	build_confirm_center.get_parent().move_child(
		build_confirm_center,
		-1
	)

	build_confirm_center.z_index = 200
	build_confirm_center.hide()
	build_confirm_panel.show()

	FurnitureData.ensure_loaded()

	if not initialize_furniture_catalog():
		set_process(false)
		set_process_unhandled_input(false)
		return

	configure_build_placement_service()
	configure_build_removal_service()
	configure_build_move_service()

	if not save_build_button.pressed.is_connected(
		confirm_build_changes
	):
		save_build_button.pressed.connect(
			confirm_build_changes
		)

	if not continue_build_button.pressed.is_connected(
		cancel_build_confirmation
	):
		continue_build_button.pressed.connect(
			cancel_build_confirmation
		)

	if not build_quick_slot_bar.slot_pressed.is_connected(
		_on_build_quick_slot_pressed
	):
		build_quick_slot_bar.slot_pressed.connect(
			_on_build_quick_slot_pressed
		)

	if not GameState.build_quick_slot_changed.is_connected(
		_on_build_quick_slot_changed
	):
		GameState.build_quick_slot_changed.connect(
			_on_build_quick_slot_changed
		)

	if not GameState.store_expansion_changed.is_connected(
		_on_store_expansion_changed
	):
		GameState.store_expansion_changed.connect(
			_on_store_expansion_changed
		)

	if GameState.has_store_layout():
		restore_store_layout()
	else:
		clear_build_selection()

	# 이전 확장 과정에서 안쪽에 남은 출입문도
	# 현재 외벽 위치로 자동 복구한다.
	call_deferred(
		"_relocate_customer_doors_to_current_boundary"
	)


func _process(_delta: float) -> void:
	queue_redraw()

	if build_confirm_center.visible:
		build_preview_controller.hide_preview()
		return

	if (
		build_mode
		and build_quick_slot_bar.is_inventory_active()
	):
		build_preview_controller.hide_preview()
		return

	if not build_mode:
		build_preview_controller.hide_preview()
		return

	if not has_valid_build_selection():
		build_preview_controller.hide_preview()
		return

	if not build_preview_controller.has_preview():
		return

	# 이동 중이 아닐 때만 보유 수량 검사
	if not build_move_service.is_active():
		if get_selected_furniture_count() <= 0:
			build_preview_controller.hide_preview()
			return

	var cell: Vector2i = get_mouse_cell()

	if not floor.is_cell_inside(cell):
		build_preview_controller.hide_preview()
		return

	var target_shelf = get_shelf_at(cell)

	# 진열대 쌓기 미리보기
	if (
		is_shelf_selected()
		and target_shelf != null
	):
		build_preview_controller.show_preview()

		if target_shelf.has_method(
			"get_next_level_world_position"
		):
			build_preview_controller.set_preview_position(
				target_shelf.get_next_level_world_position()
			)
		else:
			build_preview_controller.set_preview_position(
				target_shelf.global_position
			)

		build_preview_controller.set_placement_valid(
			can_stack_on_shelf(target_shelf)
		)

		return

	# 일반 가구 설치 미리보기
	build_preview_controller.show_preview()

	build_preview_controller.set_preview_position(
		get_current_furniture_world_position(
			cell
		)
	)

	build_preview_controller.set_placement_valid(
		can_place(cell)
	)


func _unhandled_input(event):
	if management_input_blocked:
		return

	if event is InputEventKey:
		if event.echo:
			return

	# 이미 열린 확인창은 ESC로 닫기
	if build_confirm_center.visible:
		if event.is_action_pressed("ui_cancel"):
			cancel_build_confirmation()

		get_viewport().set_input_as_handled()
		return

	# 확인창이 닫혀 있을 때의 ESC 처리
	if event.is_action_pressed("ui_cancel"):
		if build_mode:
			# 인벤토리를 먼저 닫기
			if build_quick_slot_bar.try_close_inventory():
				get_viewport().set_input_as_handled()
				return

			# 인벤토리가 닫혀 있으면 저장 확인창 열기
			request_build_mode_exit()
			get_viewport().set_input_as_handled()
			return

	# 이 아래에는 기존 인벤토리 입력 차단,
	# B·R·숫자키·마우스 처리 코드를 그대로 유지


	# 인벤토리 사용 중에는 건축 입력 차단
	# ESC는 위에서 먼저 처리함
	if build_mode and build_quick_slot_bar.is_inventory_active():
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey:
		if event.pressed and not event.echo:

			if event.keycode == KEY_B:
				toggle_build_mode()
				return

			if not build_mode:
				return

			if event.keycode == KEY_R:
				rotate_furniture()
				return

	if (
		build_mode
		and event is InputEventKey
		and event.pressed
		and not event.echo
	):
		var quick_slot_index: int = -1

		match event.keycode:
			KEY_1:
				quick_slot_index = 0
			KEY_2:
				quick_slot_index = 1
			KEY_3:
				quick_slot_index = 2
			KEY_4:
				quick_slot_index = 3
			KEY_5:
				quick_slot_index = 4
			KEY_6:
				quick_slot_index = 5
			KEY_7:
				quick_slot_index = 6
			KEY_8:
				quick_slot_index = 7
			KEY_9:
				quick_slot_index = 8

		if quick_slot_index >= 0:
			select_build_quick_slot(
				quick_slot_index
			)

			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton:
		if not build_mode:
			return

		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			handle_left_click()

		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if build_move_service.is_active():
				cancel_move_furniture()
			else:
				remove_furniture()


func _draw() -> void:
	if not build_mode:
		return

	if build_confirm_center.visible:
		return

	if build_quick_slot_bar.is_inventory_active():
		return

	if not has_valid_build_selection():
		return

	var anchor: Vector2i = get_mouse_cell()

	if not floor.is_cell_inside(anchor):
		return

	# Show the original tile boundary faintly, so its occupied half reads clearly.
	var selected_id := get_selected_build_id()
	if selected_id == "register" or selected_id.begins_with("shelf_"):
		for cell in get_occupied_cells(anchor):
			var full := FurnitureFootprint.polygon(Vector2i.ONE,1.0,0,Vector2(floor.tile_width,floor.tile_height))
			var origin := to_local(get_cell_world_position(cell))
			for i in range(full.size()): full[i] += origin
			full.append(full[0])
			draw_polyline(full,Color(0.6,0.8,0.9,0.35),1.0)
	var outline := get_build_footprint_outline(anchor)
	if not outline.is_empty():
		outline.append(outline[0])
		draw_polyline(outline, Color(0.4,0.95,1.0,0.95),1.0)

	# =========================
	# 계산대
	# =========================
	if is_register_selected():

		# 직원 작업 영역
		var worker_offsets: Array[Vector2i] = (
			get_register_worker_offsets()
		)

		for offset in worker_offsets:
			var cell: Vector2i = (
				anchor + offset
			)

			if not floor.is_cell_inside(cell):
				continue

			draw_worker_preview_cell(cell)

		# 손님 결제 영역
		var checkout_offsets: Array[Vector2i] = (
			get_register_checkout_offsets()
		)

		for offset in checkout_offsets:
			var cell: Vector2i = (
				anchor + offset
			)

			if not floor.is_cell_inside(cell):
				continue

			draw_checkout_preview_cell(cell)

		return

	# =========================
	# 진열대 상품 접근 영역
	# =========================
	if is_shelf_selected():
		var access_offsets: Array[Vector2i] = (
			get_shelf_access_offsets()
		)

		for offset in access_offsets:
			var cell: Vector2i = (
				anchor + offset
			)

			if not floor.is_cell_inside(cell):
				continue

			draw_shelf_access_cell(cell)


func draw_checkout_preview_cell(
	cell: Vector2i
) -> void:
	draw_build_guide_cell(
		cell,
		Color(0.2, 0.8, 0.3, 0.45)
	)


func draw_worker_preview_cell(
	cell: Vector2i
) -> void:
	draw_build_guide_cell(
		cell,
		Color(1.0, 0.65, 0.15, 0.4)
	)


func rotate_furniture() -> void:
	if not has_valid_build_selection():
		return

	if not is_selected_furniture_rotatable():
		DebugLog.write(
			"[건축] 회전할 수 없는 가구: ",
			get_selected_build_id()
		)

		return

	build_selection_state.rotate_clockwise()

	update_preview_size()


func normalize_build_rotation(
	build_id: String,
	saved_rotation: int
) -> int:
	if not BuildObjectData.is_rotatable(
		build_id
	):
		return 0

	return posmod(
		saved_rotation,
		4
	)


func create_preview() -> void:
	if not has_valid_build_selection():
		build_preview_controller.clear_preview()
		return

	var build_id: String = (
		get_selected_build_id()
	)

	if build_id.is_empty():
		build_preview_controller.clear_preview()

		push_error(
			"[건축] 선택한 가구의 build_id를 찾지 못함"
		)

		return

	var scene: PackedScene = (
		BuildObjectData.get_build_scene(
			build_id
		)
	)

	if scene == null:
		build_preview_controller.clear_preview()

		push_error(
			"[건축] 건축 씬을 불러오지 못함: "
			+ build_id
		)

		return

	var created_preview: Node2D = (
		build_preview_controller.create_preview(
			objects,
			scene,
			build_id
		)
	)

	if created_preview == null:
		return

	update_preview_size()


func update_preview_size() -> void:
	var current_preview: Node2D = (
		build_preview_controller.get_preview()
	)

	if current_preview == null:
		return

	apply_current_size(
		current_preview
	)

	if current_preview.has_method(
		"set_checkout_preview_visible"
	):
		current_preview.set_checkout_preview_visible(
			true
		)

func apply_furniture_collision(
	furniture,
	size: Vector2i,
	blocking: bool
):
	var collision = furniture.get_node_or_null(
		"Collision"
	)

	if collision == null:
		push_warning(
			"[건축] Collision 노드 없음: "
			+ furniture.name
		)
		return

	if collision.has_method("set_rotation_index"):
		collision.set_rotation_index(build_selection_state.rotation_index)

	if collision.has_method("set_footprint"):
		collision.set_footprint(
			size.x,
			size.y
		)

	if collision.has_method("set_blocking"):
		collision.set_blocking(
			blocking
		)


func apply_current_size(furniture):
	var configured_build_id: String = str(
		furniture.get_meta(
			"build_id",
			""
		)
	).strip_edges()

	if configured_build_id.is_empty():
		configured_build_id = (
			get_selected_build_id()
		)

	if not configured_build_id.is_empty():
		if furniture.has_method(
			"configure_decoration"
		):
			furniture.call(
				"configure_decoration",
				configured_build_id
			)

		if furniture.has_method(
			"configure_facility"
		):
			furniture.call(
				"configure_facility",
				configured_build_id
			)

	var current_size: Vector2i = (
		get_current_size()
	)


	# -------------------------
	# Visual 크기 / 방향 적용
	# -------------------------
	var visual = furniture.get_node_or_null(
		"Visual"
	)

	if visual != null:
		if visual.has_method(
			"set_footprint"
		):
			visual.set_footprint(
				current_size.x,
				current_size.y
			)

		if visual.has_method(
			"set_rotation_index"
		):
			visual.set_rotation_index(
				build_selection_state.rotation_index
			)

	# -------------------------
	# 이동 차단 여부는 CSV에서 조회
	# -------------------------
	var blocks_movement: bool = (
		get_blocks_movement_for_furniture(
			furniture
		)
	)

	# -------------------------
	# Collision 적용
	# -------------------------
	apply_furniture_collision(
		furniture,
		current_size,
		blocks_movement
	)

func restore_furniture_collision(
	furniture
):
	if furniture == null:
		return

	var collision = furniture.get_node_or_null(
		"Collision"
	)

	if collision == null:
		return

	var blocks_movement: bool = (
		get_blocks_movement_for_furniture(
			furniture
		)
	)

	if collision.has_method(
		"set_blocking"
	):
		collision.set_blocking(
			blocks_movement
		)

func is_selected_furniture_rotatable() -> bool:
	var build_id: String = (
		get_selected_build_id()
	)

	if build_id.is_empty():
		return false

	return BuildObjectData.is_rotatable(
		build_id
	)


func get_build_id_from_catalog_index(
	catalog_index: int
) -> String:
	if not is_valid_catalog_index(
		catalog_index
	):
		return ""

	return furniture_catalog[
		catalog_index
	]

func get_catalog_index_from_build_id(
	build_id: String
) -> int:
	if build_id.is_empty():
		return -1

	if not BuildObjectData.has_build_object(
		build_id
	):
		return -1

	return furniture_catalog.find(
		build_id
	)

func get_catalog_furniture_name(
	catalog_index: int
) -> String:
	var build_id: String = (
		get_build_id_from_catalog_index(
			catalog_index
		)
	)

	if build_id.is_empty():
		return "알 수 없는 가구"

	if not FurnitureData.has_furniture(
		build_id
	):
		return build_id

	return FurnitureData.get_furniture_name(
		build_id
	)



func get_build_id_for_furniture(
	furniture: Node
) -> String:
	if not is_instance_valid(furniture):
		return ""

	var build_id: String = str(
		furniture.get_meta(
			"build_id",
			""
		)
	)

	# 가구에 기록된 ID를 우선 사용
	if not build_id.is_empty():
		if BuildObjectData.has_build_object(build_id):
			return build_id

		push_warning(
			"[건축] 등록되지 않은 가구 ID: "
			+ build_id
		)
		return ""

	# ID가 없는 이전 배치 데이터 호환
	if furniture.has_meta("catalog_index"):
		var catalog_index: int = int(
			furniture.get_meta("catalog_index")
		)

		if is_valid_catalog_index(catalog_index):
			return get_build_id_from_catalog_index(
				catalog_index
			)

	# 다른 가구의 선택 정보를 대신 사용하지 않음
	return ""

func get_blocks_movement_for_furniture(
	furniture: Node
) -> bool:
	var build_id: String = (
		get_build_id_for_furniture(
			furniture
		)
	)

	if build_id.is_empty():
		return true

	var build_data: Dictionary = (
		BuildObjectData.get_build_object(
			build_id
		)
	)

	if build_data.is_empty():
		return true

	return bool(
		build_data.get(
			"blocks_movement",
			true
		)
	)


func get_base_size() -> Vector2i:
	var build_id: String = (
		get_selected_build_id()
	)

	if build_id.is_empty():
		return Vector2i.ZERO

	var build_data: Dictionary = (
		BuildObjectData.get_build_object(
			build_id
		)
	)

	if build_data.is_empty():
		return Vector2i.ZERO

	return build_data.get(
		"grid_size",
		Vector2i.ZERO
	)

func get_current_size() -> Vector2i:
	return build_area_rules.get_rotated_size(
		get_base_size(),
		build_selection_state.rotation_index
	)

func get_mouse_cell() -> Vector2i:
	var mouse_world: Vector2 = get_global_mouse_position()

	var mouse_floor_local: Vector2 = floor.to_local(
		mouse_world
	)

	return floor.local_to_grid(
		mouse_floor_local
	)

func get_cell_world_position(cell: Vector2i) -> Vector2:
	var floor_local: Vector2 = floor.grid_to_local(cell)

	return floor.to_global(floor_local)

func get_occupied_cells(
	anchor: Vector2i
) -> Array[Vector2i]:
	return build_area_rules.get_occupied_cells(
		anchor,
		get_current_size()
	)


func can_apply_selected_placement_rule(
	anchor: Vector2i
) -> bool:
	var placement_rule: String = (
		get_selected_placement_rule()
	)

	match placement_rule:
		BuildObjectData.PLACEMENT_NORMAL:
			return true

		BuildObjectData.PLACEMENT_WALL:
			return can_place_wall_object(anchor)

		_:
			push_warning(
				"[건축] 알 수 없는 배치 규칙: "
				+ placement_rule
			)

			return false


func can_place(
	anchor: Vector2i
) -> bool:
	if not has_valid_build_selection():
		return false

	# 생산실에서는 생산 설비만 배치할 수 있다.
	if building_in_production:
		if not is_selected_furniture_type(
			BuildObjectData.BUILD_TYPE_PRODUCTION_FACILITY
		):
			return false

	# 데이터에 설정된 배치 규칙을 먼저 확인한다.
	# placement_rule이 wall인 문은 매장 경계에만 설치할 수 있다.
	if not can_apply_selected_placement_rule(
		anchor
	):
		return false

	if building_in_warehouse:
		if not is_selected_furniture_type(
			BuildObjectData.BUILD_TYPE_WAREHOUSE_STORAGE
		):
			return false

	elif is_selected_furniture_type(
		BuildObjectData.BUILD_TYPE_WAREHOUSE_STORAGE
	):
		return false

	var furniture_cells: Array[Vector2i] = (
		get_occupied_cells(
			anchor
		)
	)

	var furniture_reserved_cells: Array[Vector2i] = (
		get_current_reserved_cells(
			anchor
		)
	)

	return build_placement_service.can_place(
		floor,
		furniture_cells,
		furniture_reserved_cells
	)


func place_furniture() -> void:
	var anchor: Vector2i = get_mouse_cell()

	if not can_place(anchor):
		return

	var build_id: String = (
		get_selected_build_id()
	)

	if build_id.is_empty():
		return

	var placed_furniture: Node2D = (
		build_placement_service.place_furniture(
			build_id,
			anchor
		)
	)

	if placed_furniture == null:
		return


func toggle_build_mode():
	if build_mode:
		request_build_mode_exit()
	else:
		start_build_mode()

func start_build_mode() -> void:
	if build_mode:
		return

	if not is_instance_valid(player):
		return

	clear_build_selection()

	_set_build_area(
		bool(
			player.get(
				"in_production_room"
			)
		),
		bool(
			player.get(
				"in_warehouse_room"
			)
		)
	)

	tree_was_paused_before_build = get_tree().paused
	build_mode = true

	build_confirm_center.hide()

	player.velocity = Vector2.ZERO
	player.visible = false

	_set_build_focus(true)
	build_quick_slot_bar.set_build_mode_active(true)
	get_tree().paused = true

	queue_redraw()


func request_build_mode_exit():
	if not build_mode:
		return

	build_confirm_center.visible = true
	build_confirm_center.z_index = 200




func confirm_build_changes() -> void:
	if not build_mode:
		return

	if build_move_service.is_active():
		cancel_move_furniture()

	build_confirm_center.hide()
	clear_build_selection()

	build_mode = false
	build_quick_slot_bar.set_build_mode_active(false)
	_set_build_focus(false)

	escape_player_if_blocked()

	if is_instance_valid(player):
		player.visible = true
		player.velocity = Vector2.ZERO

	save_store_layout()

	_set_build_area(false)

	get_tree().paused = tree_was_paused_before_build

	queue_redraw()


func cancel_build_confirmation():
	build_confirm_center.visible = false


func remove_furniture() -> void:
	var cell: Vector2i = get_mouse_cell()

	var furniture = (
		build_occupancy_state.get_furniture_at(
			cell
		)
	)

	if furniture.has_method(
		"can_remove_storage"
	):
		if not bool(
			furniture.call(
				"can_remove_storage"
			)
		):
			DebugLog.write(
				"[건축] 아이템을 모두 출고한 뒤 창고 선반을 철거할 수 있습니다."
			)
			return

	if not is_instance_valid(furniture):
		return

	if furniture is ProductionFacility:
		var facility: ProductionFacility = (
			furniture as ProductionFacility
		)

		if not facility.can_remove_facility():
			DebugLog.write(
				"[건축] 가공을 마치고 완성품을 회수한 뒤 철거할 수 있습니다."
			)
			return

	var build_id: String = (
		get_build_id_for_furniture(
			furniture
		)
	)

	if build_id.is_empty():
		push_warning(
			"[건축] 철거할 가구의 build_id를 찾을 수 없음"
		)
		return

	build_removal_service.remove_furniture(
		furniture,
		build_id
	)


func handle_left_click() -> void:
	var cell: Vector2i = get_mouse_cell()

	if build_move_service.is_active():
		finish_move_furniture()
		return

	if (
		build_occupancy_state.has_occupied_cell(
			cell
		)
		and Input.is_key_pressed(KEY_SHIFT)
	):
		start_move_furniture(cell)
		return

	var target_shelf = get_shelf_at(cell)

	if can_stack_on_shelf(target_shelf):
		stack_shelf(target_shelf)
		return

	if build_occupancy_state.has_occupied_cell(
		cell
	):
		start_move_furniture(cell)
		return

	place_furniture()


func start_move_furniture(
	cell: Vector2i
) -> void:
	if build_move_service.is_active():
		return

	var target_furniture: Node2D = (
		build_occupancy_state.get_furniture_at(
			cell
		)
	)

	if not is_instance_valid(target_furniture):
		return

	var target_build_id: String = (
		get_build_id_for_furniture(
			target_furniture
		)
	)

	# 현재 CSV의 ID를 기준으로 카탈로그 위치 조회
	var catalog_index: int = (
		get_catalog_index_from_build_id(
			target_build_id
		)
	)

	if not is_valid_catalog_index(catalog_index):
		push_error(
			"[건축 이동] 등록되지 않은 가구: "
			+ target_build_id
		)
		return

	var saved_rotation: int = int(
		target_furniture.get_meta(
			"rotation_index",
			0
		)
	)

	saved_rotation = normalize_build_rotation(
		target_build_id,
		saved_rotation
	)

	# 데이터 검사가 끝난 뒤 실제 이동 시작
	if not build_move_service.begin_move(
		target_furniture,
		cell
	):
		return

	build_selection_state.restore_selection(
		catalog_index,
		saved_rotation
	)

	if build_quick_slot_bar.has_method(
		"clear_selected_slot"
	):
		build_quick_slot_bar.clear_selected_slot()

	create_preview()

	# 미리보기 생성 실패 시 원래 가구 복구
	if not build_preview_controller.has_preview():
		cancel_move_furniture()
		return


func finish_move_furniture() -> void:
	var target_furniture: Node2D = (
		build_move_service.get_furniture()
	)

	if not is_instance_valid(target_furniture):
		build_move_service.clear()
		clear_build_selection()
		return

	var new_anchor: Vector2i = get_mouse_cell()

	if not can_place(new_anchor):
		return

	var new_world_position: Vector2 = (
		get_current_furniture_world_position(
			new_anchor
		)
	)

	var new_cells: Array[Vector2i] = (
		get_occupied_cells(new_anchor)
	)

	var new_reserved_cells: Array[Vector2i] = (
		get_current_reserved_cells(new_anchor)
	)

	# 현재 선택의 크기·회전을 실제 가구에 적용
	apply_current_size(target_furniture)
	restore_furniture_collision(target_furniture)

	build_move_service.finish_move(
		new_anchor,
		new_world_position,
		build_selection_state.catalog_index,
		build_selection_state.rotation_index,
		new_cells,
		new_reserved_cells
	)

	clear_build_selection()


func cancel_move_furniture() -> void:
	build_move_service.cancel_move()

	clear_build_selection()


func is_door_selected() -> bool:
	return is_selected_furniture_type(
		BuildObjectData.BUILD_TYPE_DOOR
	)

func can_place_wall_object(
	cell: Vector2i
) -> bool:
	if not floor.is_cell_inside(
		cell
	):
		return false

	var columns: int = int(
		floor.columns
	)

	var rows: int = int(
		floor.rows
	)

	var rotation_index: int = (
		build_selection_state.rotation_index
	)

	var matches_current_wall: bool = false

	# 현재 회전 방향과 실제 벽 방향이 일치하는지 확인한다.
	match rotation_index:
		0:
			matches_current_wall = (
				cell.y == 0
			)

		1:
			matches_current_wall = (
				cell.x == columns - 1
			)

		2:
			matches_current_wall = (
				cell.y == rows - 1
			)

		3:
			matches_current_wall = (
				cell.x == 0
			)

	if not matches_current_wall:
		return false

	# 일반 고객용 문은 현재 부지의
	# 도로를 바라보는 전면 벽에만 설치할 수 있다.
	if is_door_selected():
		return (
			StoreLotData
			.is_customer_door_rotation_allowed(
				GameState.get_store_lot_type(),
				rotation_index
			)
		)

	# 생산실 문과 이후 추가될 벽 전용 오브젝트는
	# 각자의 벽 배치 규칙을 그대로 사용한다.
	return true

func get_door_world_position(cell: Vector2i) -> Vector2:
	var center: Vector2 = get_cell_world_position(cell)

	var tile_width: float = float(floor.tile_width)
	var tile_height: float = float(floor.tile_height)

	match build_selection_state.rotation_index:
		0:
			# 오른쪽 위 변
			return center + Vector2(
				tile_width * 0.25,
				-tile_height * 0.25
			)

		1:
			# 오른쪽 아래 변
			return center + Vector2(
				tile_width * 0.25,
				tile_height * 0.25
			)

		2:
			# 왼쪽 아래 변
			return center + Vector2(
				-tile_width * 0.25,
				tile_height * 0.25
			)

		3:
			# 왼쪽 위 변
			return center + Vector2(
				-tile_width * 0.25,
				-tile_height * 0.25
			)

	return center

func get_current_furniture_world_position(
	cell: Vector2i
) -> Vector2:
	if (
		is_door_selected()
		or is_selected_furniture_type(
			BuildObjectData.BUILD_TYPE_PRODUCTION_DOOR
		)
		or is_selected_furniture_type(
			BuildObjectData.BUILD_TYPE_WAREHOUSE_DOOR
		)
	):
		return get_door_world_position(cell)

	return get_cell_world_position(cell)

func is_shelf_selected() -> bool:
	return is_selected_furniture_type(
		BuildObjectData.BUILD_TYPE_SHELF
	)

func get_shelf_at(
	cell: Vector2i
):
	var furniture: Node2D = (
		build_occupancy_state.get_furniture_at(
			cell
		)
	)

	if furniture == null:
		return null

	if furniture.is_in_group("shelf"):
		return furniture

	return null

func can_stack_on_shelf(target) -> bool:
	if build_move_service.is_active():
		return false

	if not is_instance_valid(target):
		return false

	if not target.is_in_group("shelf"):
		return false

	if not target.has_method("can_add_level"):
		return false

	# 이미 3단이면 적층 불가
	if not target.can_add_level():
		return false

	# 같은 종류의 진열대인지 검사
	var target_catalog_index: int = int(
		target.get_meta(
			"catalog_index",
			-1
		)
	)

	if target_catalog_index != build_selection_state.catalog_index:
		return false

	# 크기 확인
	var current_size: Vector2i = get_base_size()

	# 2×1처럼 방향이 의미 있는 가구만 방향 비교
	if current_size.x != current_size.y:
		var target_rotation: int = int(
			target.get_meta(
				"rotation_index",
				0
			)
		)

		# 0/180은 같은 방향, 90/270도 같은 방향
		if target_rotation % 2 != build_selection_state.rotation_index % 2:
			return false

	# 보유 가구가 없으면 추가 불가
	var build_id: String = (
		get_selected_build_id()
	)

	if not GameState.has_furniture(
		build_id,
		1
	):
		return false

	return true

func stack_shelf(target):
	if not can_stack_on_shelf(target):
		return

	if not target.add_level():
		return

	# 같은 진열대 하나 소비
	var build_id: String = (
		get_selected_build_id()
	)

	GameState.remove_furniture(
		build_id,
		1
	)

	handle_depleted_build_item(build_id)


func is_cell_blocked_for_customer(
	cell: Vector2i
) -> bool:
	if not store_floor.is_cell_inside(cell):
		return true

	var furniture: Node2D = (
		store_occupancy_state.get_furniture_at(cell)
	)

	if not is_instance_valid(furniture):
		return false

	return get_blocks_movement_for_furniture(furniture)


func get_adjacent_walkable_cells(
	furniture
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []

	if not is_instance_valid(furniture):
		return result

	var checked: Dictionary = {}

	var directions: Array[Vector2i] = [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1)
	]

	var furniture_cells: Array[Vector2i] = (
		store_occupancy_state.find_occupied_cells_for(
			furniture
		)
	)

	for occupied_cell in furniture_cells:
		for direction in directions:
			var candidate: Vector2i = (
				occupied_cell + direction
			)

			if checked.has(candidate):
				continue

			checked[candidate] = true

			# 바닥 바깥인지와 가구에 막혔는지를 함께 검사
			if is_cell_blocked_for_customer(candidate):
				continue

			result.append(candidate)

	return result

func is_register_selected() -> bool:
	return is_selected_furniture_type(
		BuildObjectData.BUILD_TYPE_REGISTER
	)
	
func get_register_worker_offsets() -> Array[Vector2i]:
	return build_area_rules.get_register_worker_offsets(
		build_selection_state.rotation_index,
		get_selected_register_area_profile()
	)


func get_register_checkout_offsets() -> Array[Vector2i]:
	return build_area_rules.get_register_checkout_offsets(
		build_selection_state.rotation_index,
		get_selected_register_area_profile()
	)


func get_current_reserved_cells(
	anchor: Vector2i
) -> Array[Vector2i]:
	if (
		is_selected_furniture_type(
			BuildObjectData.BUILD_TYPE_PRODUCTION_DOOR
		)
		or is_selected_furniture_type(
			BuildObjectData.BUILD_TYPE_WAREHOUSE_DOOR
		)
	):
		var return_cells: Array[Vector2i] = [
			anchor
		]

		return return_cells

	if not is_register_selected():
		return []

	return build_area_rules.get_register_reserved_cells(
		anchor,
		build_selection_state.rotation_index,
		get_selected_register_area_profile()
	)

func get_shelf_access_offsets() -> Array[Vector2i]:
	return build_area_rules.get_shelf_access_offsets(
		get_current_size(),
		build_selection_state.rotation_index
	)

func draw_shelf_access_cell(
	cell: Vector2i
) -> void:
	draw_build_guide_cell(
		cell,
		Color(0.25, 0.55, 1.0, 0.4)
	)

func clear_build_selection() -> void:
	build_selection_state.clear()

	build_preview_controller.clear_preview()

	if build_quick_slot_bar.has_method(
		"clear_selected_slot"
	):
		build_quick_slot_bar.clear_selected_slot()

	queue_redraw()


func get_player_grid_cell() -> Vector2i:
	return floor.local_to_grid(
		floor.to_local(
			player.global_position
		)
	)


func find_nearest_walkable_cell(
	start_cell: Vector2i
) -> Vector2i:
	var queue: Array[Vector2i] = []
	var visited: Dictionary = {}

	queue.append(start_cell)
	visited[start_cell] = true

	var directions: Array[Vector2i] = [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1)
	]

	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()

		if (
			floor.is_cell_inside(cell)
			and not is_cell_blocked_in_build_area(cell)
		):
			return cell

		for direction in directions:
			var next_cell: Vector2i = (
				cell + direction
			)

			if visited.has(next_cell):
				continue

			if not floor.is_cell_inside(next_cell):
				continue

			visited[next_cell] = true
			queue.append(next_cell)

	return Vector2i(-1, -1)

func escape_player_if_blocked():
	if not is_instance_valid(player):
		return

	var player_cell: Vector2i = (
		get_player_grid_cell()
	)

	# 현재 위치가 막히지 않았다면 그대로
	if not is_cell_blocked_in_build_area(
		player_cell
	):
		return

	var safe_cell: Vector2i = (
		find_nearest_walkable_cell(
			player_cell
		)
	)

	if safe_cell == Vector2i(-1, -1):
		DebugLog.write(
			"[건축] 플레이어 탈출 위치를 찾지 못함"
		)
		return

	player.global_position = (
		get_cell_world_position(
			safe_cell
		)
	)

	player.velocity = Vector2.ZERO


func get_store_layout_data() -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	var store_layout: Array[Dictionary] = (
		build_layout_service.collect_layout(
			store_objects,
			Callable(self, "get_build_id_for_furniture")
		)
	)

	for entry in store_layout:
		entry["room_id"] = "store"
		result.append(entry)

	var production_layout: Array[Dictionary] = (
		build_layout_service.collect_layout(
			production_objects,
			Callable(self, "get_build_id_for_furniture")
		)
	)

	for entry in production_layout:
		entry["room_id"] = "production"
		result.append(entry)

	var warehouse_layout: Array[Dictionary] = (
		build_layout_service.collect_layout(
			warehouse_objects,
			Callable(
				self,
				"get_build_id_for_furniture"
			)
		)
	)

	WAREHOUSE_LAYOUT_PERSISTENCE_SCRIPT.attach_storage_slots(
		warehouse_layout,
		warehouse_occupancy_state
	)

	for entry in warehouse_layout:
		entry["room_id"] = "warehouse"
		result.append(entry)

	return result

func save_store_layout():
	var layout: Array[Dictionary] = (
		get_store_layout_data()
	)

	GameState.save_store_layout(layout)

	refresh_decoration_effects(layout)


func restore_store_layout() -> void:
	if not GameState.has_store_layout():
		return

	var layout: Array[Dictionary] = (
		GameState.get_store_layout()
	)

	var store_layout: Array[Dictionary] = []
	var production_layout: Array[Dictionary] = []
	var warehouse_layout: Array[Dictionary] = []

	for entry in layout:
		var room_id: String = str(
			entry.get("room_id", "store")
		)

		match room_id:
			"store":
				store_layout.append(entry)

			"production":
				production_layout.append(entry)

			"warehouse":
				warehouse_layout.append(entry)

			_:
				push_error(
					"[배치 복원] 알 수 없는 구역: "
					+ room_id
				)
				return

	_set_build_area(
		false,
		false
	)

	_restore_current_area_layout(
		store_layout
	)

	_set_build_area(
		true,
		false
	)

	_restore_current_area_layout(
		production_layout
	)

	_set_build_area(
		false,
		true
	)

	_restore_current_area_layout(
		warehouse_layout
	)

	clear_build_selection()

	_set_build_area(
		false,
		false
	)

	refresh_decoration_effects(
		layout
	)


func _restore_current_area_layout(
	layout: Array[Dictionary]
) -> void:
	build_layout_service.restore_layout(
		layout,
		objects,
		build_occupancy_state,
		build_selection_state,
		furniture_catalog,
		Callable(
			self,
			"apply_current_size"
		),
		Callable(
			self,
			"get_current_furniture_world_position"
		),
		Callable(
			self,
			"get_occupied_cells"
		),
		Callable(
			self,
			"get_current_reserved_cells"
		)
	)

	# 가구 생성과 점유 등록이 끝난 뒤 창고 내용만 복구한다.
	WAREHOUSE_LAYOUT_PERSISTENCE_SCRIPT.restore_storage_slots(
		layout,
		build_occupancy_state
	)

# =========================
# 현재 건축 선택 조회
# =========================

func is_valid_catalog_index(
	catalog_index: int
) -> bool:
	return (
		catalog_index >= 0
		and catalog_index < furniture_catalog.size()
	)


func has_valid_build_selection() -> bool:
	if not build_selection_state.has_selection():
		return false

	return is_valid_catalog_index(
		build_selection_state.catalog_index
	)



func get_selected_furniture_type() -> String:
	var build_id: String = (
		get_selected_build_id()
	)

	if build_id.is_empty():
		return ""

	return BuildObjectData.get_build_type(
		build_id
	)


func is_selected_furniture_type(
	expected_type: String
) -> bool:
	return (
		get_selected_furniture_type()
		== expected_type
	)


func get_selected_build_id() -> String:
	if not has_valid_build_selection():
		return ""

	return get_build_id_from_catalog_index(
		build_selection_state.catalog_index
	)


func get_selected_furniture_count() -> int:
	var build_id: String = (
		get_selected_build_id()
	)

	if build_id.is_empty():
		return 0

	return GameState.get_furniture_count(
		build_id
	)


func _on_build_quick_slot_pressed(
	slot_index: int,
	build_id: String
) -> void:
	if not build_mode:
		return

	if build_confirm_center.visible:
		return

	if build_quick_slot_bar.is_inventory_active():
		return

	if management_input_blocked:
		return

	if building_in_production:
		if BuildObjectData.get_build_type(build_id) != (
			BuildObjectData.BUILD_TYPE_PRODUCTION_FACILITY
		):
			DebugLog.write(
				"[건축] 생산실에는 생산 설비를 배치할 수 있습니다."
			)
			return

	if building_in_warehouse:
		if BuildObjectData.get_build_type(
			build_id
		) != BuildObjectData.BUILD_TYPE_WAREHOUSE_STORAGE:
			DebugLog.write(
				"[건축] 창고에는 창고 전용 보관 설비만 배치할 수 있습니다."
			)
			return

	elif BuildObjectData.get_build_type(
		build_id
	) == BuildObjectData.BUILD_TYPE_WAREHOUSE_STORAGE:
		DebugLog.write(
			"[건축] 창고 선반은 창고 내부에만 배치할 수 있습니다."
		)
		return


	var catalog_index: int = (
		get_catalog_index_from_build_id(
			build_id
		)
	)

	if not is_valid_catalog_index(
		catalog_index
	):
		push_warning(
			"[건축 퀵슬롯] 등록되지 않은 건축물: "
			+ build_id
		)

		return

	if GameState.get_furniture_count(
		build_id
	) <= 0:
		DebugLog.write(
			"[건축 퀵슬롯] 보유 수량 없음: ",
			build_id
		)

		return

	# 들고 있던 가구를 먼저 원래 위치로 복구
	if build_move_service.is_active():
		cancel_move_furniture()

	build_selection_state.select_quick_slot(
		catalog_index,
		slot_index
	)

	create_preview()

	if build_quick_slot_bar.has_method(
		"set_selected_slot"
	):
		build_quick_slot_bar.set_selected_slot(
			slot_index
		)


func select_build_quick_slot(
	slot_index: int
) -> void:
	if not build_mode:
		return

	if (
		slot_index < 0
		or slot_index >= GameState.BUILD_QUICK_SLOT_COUNT
	):
		return

	var build_id: String = (
		GameState.get_build_quick_slot(
			slot_index
		)
	)

	# 빈 슬롯이면 현재 선택을 유지한다.
	if build_id.is_empty():
		return

	# 마우스로 퀵슬롯을 클릭했을 때와
	# 동일한 선택 함수 사용
	_on_build_quick_slot_pressed(
		slot_index,
		build_id
	)

func handle_depleted_build_item(
	build_id: String
) -> void:
	if GameState.get_furniture_count(
		build_id
	) > 0:
		return

	for slot_index in range(
		GameState.BUILD_QUICK_SLOT_COUNT
	):
		if GameState.get_build_quick_slot(
			slot_index
		) == build_id:
			GameState.clear_build_quick_slot(
				slot_index
			)

	clear_build_selection()


func _on_build_quick_slot_changed(
	slot_index: int,
	_previous_build_id: String,
	_new_build_id: String
) -> void:
	if not build_selection_state.is_quick_slot_selected(
		slot_index
	):
		return

	# 배치된 가구 이동 중에는 이동 선택을 유지
	if build_move_service.is_active():
		build_selection_state.detach_quick_slot()

		if build_quick_slot_bar.has_method(
			"clear_selected_slot"
		):
			build_quick_slot_bar.clear_selected_slot()

		return

	# 선택한 퀵슬롯의 내용이 변경됐으므로
	# 기존 건축 선택을 해제
	clear_build_selection()


var build_selection_state = (
	BUILD_SELECTION_STATE_SCRIPT.new()
)



func get_selected_placement_rule() -> String:
	var build_id: String = (
		get_selected_build_id()
	)

	if build_id.is_empty():
		return ""

	return BuildObjectData.get_placement_rule(
		build_id
	)

func draw_build_guide_cell(
	cell: Vector2i,
	color: Color
) -> void:
	var center: Vector2 = to_local(
		get_cell_world_position(cell)
	)

	var half_width: float = (
		float(floor.tile_width) * 0.5
	)

	var half_height: float = (
		float(floor.tile_height) * 0.5
	)

	var polygon := PackedVector2Array([
		center + Vector2(0.0, -half_height),
		center + Vector2(half_width, 0.0),
		center + Vector2(0.0, half_height),
		center + Vector2(-half_width, 0.0)
	])

	draw_colored_polygon(
		polygon,
		color
	)

func get_selected_register_area_profile() -> RegisterAreaProfile:
	return BuildObjectData.get_register_area_profile(
		get_selected_build_id()
	)

func _set_build_area(
	use_production: bool,
	use_warehouse: bool = false
) -> void:
	building_in_production = (
		use_production
	)

	building_in_warehouse = (
		use_warehouse
	)

	if use_warehouse:
		floor = warehouse_floor
		objects = warehouse_objects

		build_occupancy_state = (
			warehouse_occupancy_state
		)

	elif use_production:
		floor = production_floor
		objects = production_objects

		build_occupancy_state = (
			production_occupancy_state
		)

	else:
		floor = store_floor
		objects = store_objects

		build_occupancy_state = (
			store_occupancy_state
		)

	configure_build_placement_service()
	configure_build_removal_service()
	configure_build_move_service()

func is_cell_blocked_in_build_area(
	cell: Vector2i
) -> bool:
	if not floor.is_cell_inside(cell):
		return true

	var furniture: Node2D = (
		build_occupancy_state.get_furniture_at(cell)
	)

	if not is_instance_valid(furniture):
		return false

	return get_blocks_movement_for_furniture(furniture)


func refresh_decoration_effects(
	layout: Array[Dictionary]
) -> void:
	decoration_effect_totals = (
		DecorationEffectService.calculate(layout)
	)


func get_decoration_effect(
	effect_type: String
) -> float:
	return float(
		decoration_effect_totals.get(effect_type, 0.0)
	)

func get_customer_weight_bonuses() -> Dictionary:
	var bonuses: Dictionary = decoration_effect_totals.get(
		"customer_weight",
		{}
	)

	return bonuses.duplicate(true)

# 바닥 크기 변경이 적용된 다음 프레임에 문을 옮긴다.
func _on_store_expansion_changed(
	_previous_level: int,
	_new_level: int,
	_new_store_size: Vector2i
) -> void:
	call_deferred(
		"_relocate_customer_doors_to_current_boundary"
	)

# 생산실 문이 아닌 일반 고객용 출입문인지 확인한다.
func _is_customer_entrance_door(
	furniture: Node
) -> bool:
	if not is_instance_valid(furniture):
		return false

	if furniture.is_queued_for_deletion():
		return false

	if bool(
		furniture.get_meta(
			"is_build_preview",
			false
		)
	):
		return false

	var build_id: String = (
		get_build_id_for_furniture(
			furniture
		)
	)

	if build_id.is_empty():
		return false

	return (
		BuildObjectData.get_build_type(
			build_id
		)
		== BuildObjectData.BUILD_TYPE_DOOR
	)

# 문의 방향을 유지하면서 현재 크기의 외벽 위치를 계산한다.
func _get_current_boundary_anchor(
	door: Node
) -> Vector2i:
	var current_anchor: Vector2i = (
		door.get_meta(
			"anchor",
			Vector2i(-1, -1)
		)
	)

	if current_anchor == Vector2i(-1, -1):
		return current_anchor

	var rotation_index: int = int(
		door.get_meta(
			"rotation_index",
			0
		)
	)

	var columns: int = int(
		store_floor.columns
	)

	var rows: int = int(
		store_floor.rows
	)

	var new_anchor: Vector2i = current_anchor

	match rotation_index:
		0:
			# 위쪽 외벽은 y = 0으로 유지
			new_anchor.y = 0
			new_anchor.x = clampi(
				new_anchor.x,
				0,
				columns - 1
			)

		1:
			# 오른쪽 외벽
			new_anchor.x = columns - 1
			new_anchor.y = clampi(
				new_anchor.y,
				0,
				rows - 1
			)

		2:
			# 아래쪽 외벽
			new_anchor.y = rows - 1
			new_anchor.x = clampi(
				new_anchor.x,
				0,
				columns - 1
			)

		3:
			# 왼쪽 외벽은 x = 0으로 유지
			new_anchor.x = 0
			new_anchor.y = clampi(
				new_anchor.y,
				0,
				rows - 1
			)

	return new_anchor

# 매장 확장 후 기존 출입문을 새 외벽으로 이동한다.
# build_move_service를 사용하므로 위치, 메타데이터,
# 점유 정보가 함께 갱신된다.
func _relocate_customer_doors_to_current_boundary() -> void:
	if not is_instance_valid(store_floor):
		return

	if not is_instance_valid(store_objects):
		return

	if build_move_service.is_active():
		push_warning(
			"[매장 확장] 가구 이동 중이라 문 위치를 보정할 수 없습니다."
		)
		return

	# 반드시 매장 점유 정보에 연결된 상태에서 처리한다.
	_set_build_area(false)

	var moved_count: int = 0

	for furniture_node in store_objects.get_children():
		if not _is_customer_entrance_door(
			furniture_node
		):
			continue

		if not furniture_node is Node2D:
			continue

		var door: Node2D = (
			furniture_node as Node2D
		)

		var old_anchor: Vector2i = (
			door.get_meta(
				"anchor",
				Vector2i(-1, -1)
			)
		)

		if old_anchor == Vector2i(-1, -1):
			continue

		var new_anchor: Vector2i = (
			_get_current_boundary_anchor(
				door
			)
		)

		if new_anchor == old_anchor:
			continue

		var build_id: String = (
			get_build_id_for_furniture(
				door
			)
		)

		var catalog_index: int = (
			get_catalog_index_from_build_id(
				build_id
			)
		)

		if not is_valid_catalog_index(
			catalog_index
		):
			push_warning(
				"[매장 확장] 출입문 카탈로그를 찾을 수 없음: "
				+ build_id
			)
			continue

		var rotation_index: int = (
			normalize_build_rotation(
				build_id,
				int(
					door.get_meta(
						"rotation_index",
						0
					)
				)
			)
		)

		build_selection_state.restore_selection(
			catalog_index,
			rotation_index
		)

		if not build_move_service.begin_move(
			door,
			old_anchor
		):
			clear_build_selection()
			continue

		# 새 외벽 위치가 다른 가구와 충돌하면
		# 기존 위치로 되돌린다.
		if not can_place(
			new_anchor
		):
			build_move_service.cancel_move()
			clear_build_selection()

			push_warning(
				"[매장 확장] 출입문 이동 위치가 막혀 있음: ",
				new_anchor
			)
			continue

		var new_world_position: Vector2 = (
			get_current_furniture_world_position(
				new_anchor
			)
		)

		var new_cells: Array[Vector2i] = (
			get_occupied_cells(
				new_anchor
			)
		)

		var new_reserved_cells: Array[Vector2i] = (
			get_current_reserved_cells(
				new_anchor
			)
		)

		apply_current_size(
			door
		)

		restore_furniture_collision(
			door
		)

		var move_succeeded: bool = (
			build_move_service.finish_move(
				new_anchor,
				new_world_position,
				catalog_index,
				rotation_index,
				new_cells,
				new_reserved_cells
			)
		)

		if move_succeeded:
			moved_count += 1

			DebugLog.write(
				"[매장 확장] 출입문 이전 / ",
				old_anchor,
				" → ",
				new_anchor
			)

		clear_build_selection()

	if moved_count <= 0:
		return

	# 변경된 문 위치를 저장 데이터에도 반영한다.
	save_store_layout()

	# 새 문 위치를 기준으로 벽 충돌을 다시 만든다.
	if store_floor.has_method(
		"request_boundary_rebuild"
	):
		store_floor.call(
			"request_boundary_rebuild"
		)

	DebugLog.write(
		"[매장 확장] 출입문 자동 이전 완료 / ",
		moved_count,
		"개"
	)

func get_build_footprint_outline(anchor: Vector2i) -> PackedVector2Array:
	var id := get_selected_build_id()
	var depth := 0.5 if id == "register" or id.begins_with("shelf_") else 1.0
	var outline := FurnitureFootprint.polygon(get_current_size(),depth,
		build_selection_state.rotation_index,Vector2(floor.tile_width,floor.tile_height))
	var origin := to_local(get_cell_world_position(anchor))
	for i in range(outline.size()):
		outline[i] += origin
	return outline

func _set_build_focus(active: bool) -> void:
	if active:
		hidden_build_ui.clear()
		for child in build_quick_slot_bar.get_parent().get_children():
			if child is CanvasItem and child != build_quick_slot_bar and child != build_confirm_center:
				hidden_build_ui[child] = child.visible
				if child is GameMenu: child.close_all()
				child.hide()
	else:
		for child in hidden_build_ui:
			if is_instance_valid(child): child.visible = hidden_build_ui[child]
		hidden_build_ui.clear()
