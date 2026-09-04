extends Node2D

@warning_ignore("shadowed_global_identifier")
@onready var floor = $"../Floor"
@onready var objects = $"../Objects"
@onready var actors = $"../Actors"
@onready var build_panel: Control = $"../UI/BuildPanel"
@onready var player: CharacterBody2D = $"../Actors/Player"

@onready var shelf_1x1_button = $"../UI/BuildPanel/HBoxContainer/Shelf1x1Button"
@onready var shelf_2x1_button = $"../UI/BuildPanel/HBoxContainer/Shelf2x1Button"
@onready var shelf_3x1_button = $"../UI/BuildPanel/HBoxContainer/Shelf3x1Button"
@onready var register_button = $"../UI/BuildPanel/HBoxContainer/RegisterButton"
@onready var door_button = $"../UI/BuildPanel/HBoxContainer/DoorButton"

@onready var build_confirm_center: CenterContainer = $"../UI/BuildConfirmCenter"
@onready var build_confirm_panel: PanelContainer = $"../UI/BuildConfirmCenter/BuildConfirmPanel"
@onready var save_build_button: Button = $"../UI/BuildConfirmCenter/BuildConfirmPanel/VBoxContainer/HBoxContainer/SaveButton"
@onready var continue_build_button: Button = $"../UI/BuildConfirmCenter/BuildConfirmPanel/VBoxContainer/HBoxContainer/ContinueButton"


const SHELF_SCENE = preload(
    "res://scenes/objects/shelf.tscn"
)

const REGISTER_SCENE = preload(
	"res://scenes/objects/register.tscn"
)

const DOOR_SCENE = preload(
	"res://scenes/objects/door.tscn"
)

# 현재는 같은 Shelf 씬을 사용하지만
# 가구 종류마다 크기를 다르게 정의한다.
var furniture_catalog = [
	{
		"name": "1x1 진열대",
		"type": "shelf",
		"scene": SHELF_SCENE,
		"size": Vector2i(1, 1),
		"count": 5,
		"slots_per_level": 2,
		"slot_capacity": 5,
		"blocks_movement": true
	},
	{
		"name": "2x1 진열대",
		"type": "shelf",
		"scene": SHELF_SCENE,
		"size": Vector2i(2, 1),
		"count": 3,
		"slots_per_level": 3,
		"slot_capacity": 7,
		"blocks_movement": true
	},
	{
		"name": "3x1 진열대",
		"type": "shelf",
		"scene": SHELF_SCENE,
		"size": Vector2i(3, 1),
		"count": 2,
		"slots_per_level": 4,
		"slot_capacity": 9,
		"blocks_movement": true
	},
	{
		"name": "계산대",
		"type": "register",
		"scene": REGISTER_SCENE,
		"size": Vector2i(2, 1),
		"count": 1,
		"blocks_movement": true
	},
	{
		"name": "문",
		"type": "door",
		"scene": DOOR_SCENE,
		"size": Vector2i(1, 1),
		"count": 1,
		"blocks_movement": false
	}
]

var selected_index: int = 0

# 0 = 0도
# 1 = 90도
# 2 = 180도
# 3 = 270도
var rotation_index: int = 0

var preview: Node2D

var occupied_cells: Dictionary = {}
var reserved_cells: Dictionary = {}

var build_mode: bool = false
var tree_was_paused_before_build: bool = false

var moving_furniture: Node2D = null
var moving_original_anchor: Vector2i = Vector2i.ZERO
var moving_original_cells: Array[Vector2i] = []
var moving_original_reserved_cells: Array[Vector2i] = []



func _ready():
	
	process_mode = Node.PROCESS_MODE_ALWAYS
	build_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	build_confirm_center.process_mode = Node.PROCESS_MODE_ALWAYS
	
	z_index = 90
	build_panel.visible = false
	build_confirm_center.visible = false

	create_preview()
	preview.visible = false

	build_confirm_center.visible = false

	save_build_button.pressed.connect(
		confirm_build_changes
	)

	continue_build_button.pressed.connect(
		cancel_build_confirmation
	)

	shelf_1x1_button.pressed.connect(
		func(): select_furniture(0)
	)

	shelf_2x1_button.pressed.connect(
		func(): select_furniture(1)
	)

	shelf_3x1_button.pressed.connect(
		func(): select_furniture(2)
	)

	register_button.pressed.connect(
		func(): select_furniture(3)
	)

	door_button.pressed.connect(
		func(): select_furniture(4)
)

	update_build_ui()

	if GameState.has_store_layout():
		restore_store_layout()


func _process(_delta):
	queue_redraw()
	
	if not build_mode:
		preview.visible = false
		return

	if (
		selected_index < 0
		or selected_index >= furniture_catalog.size()
	):
		if is_instance_valid(preview):
			preview.visible = false
		return

	# 이동 중이 아닐 때만 보유 수량 검사
	if moving_furniture == null:
		if furniture_catalog[selected_index]["count"] <= 0:
			preview.visible = false
			return

	var cell: Vector2i = get_mouse_cell()

	if not floor.is_cell_inside(cell):
		preview.visible = false
		return

	# 진열대 위에 진열대를 올리고 있는지 확인
	var target_shelf = get_shelf_at(cell)

	if is_shelf_selected() and target_shelf != null:
		preview.visible = true

		if target_shelf.has_method(
			"get_next_level_world_position"
		):
			preview.global_position = (
				target_shelf.get_next_level_world_position()
			)
		else:
			preview.global_position = target_shelf.global_position

		if can_stack_on_shelf(target_shelf):
			preview.modulate = Color(
				1.0,
				1.0,
				1.0,
				0.5
			)
		else:
			preview.modulate = Color(
				1.0,
				0.2,
				0.2,
				0.5
			)

		return

	# 일반 가구 설치 미리보기
	preview.visible = true
	preview.global_position = (
		get_current_furniture_world_position(cell)
	)

	if can_place(cell):
		preview.modulate = Color(
			1.0,
			1.0,
			1.0,
			0.5
		)
	else:
		preview.modulate = Color(
			1.0,
			0.2,
			0.2,
			0.5
		)

func _unhandled_input(event):
		# Esc
	if event.is_action_pressed("ui_cancel"):

		# 확인창이 열려 있으면 확인창만 닫기
		if build_confirm_center.visible:
			cancel_build_confirmation()
			get_viewport().set_input_as_handled()
			return

		# 건축 모드라면 종료하지 않고 확인창 표시
		if build_mode:
			request_build_mode_exit()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventKey:
		if event.pressed and not event.echo:

			if event.keycode == KEY_B:
				toggle_build_mode()
				return

			if not build_mode:
				return

			if event.keycode == KEY_1:
				select_furniture(0)
				return

			if event.keycode == KEY_2:
				select_furniture(1)
				return

			if event.keycode == KEY_3:
				select_furniture(2)
				return

			if event.keycode == KEY_R:
				rotate_furniture()
				return

	if event is InputEventMouseButton:
		if not build_mode:
			return

		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			handle_left_click()

		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if moving_furniture != null:
				cancel_move_furniture()
			else:
				remove_furniture()


func _draw():
	if not build_mode:
		return

	if selected_index < 0:
		return

	var anchor: Vector2i = get_mouse_cell()

	if not floor.is_cell_inside(anchor):
		return

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
):
	var world_position: Vector2 = (
		get_cell_world_position(cell)
	)

	var center: Vector2 = (
		to_local(world_position)
	)

	var half_width: float = (
		float(floor.tile_width) * 0.5
	)

	var half_height: float = (
		float(floor.tile_height) * 0.5
	)

	var polygon := PackedVector2Array([
		center + Vector2(0, -half_height),
		center + Vector2(half_width, 0),
		center + Vector2(0, half_height),
		center + Vector2(-half_width, 0)
	])

	# 손님 결제칸 = 초록색
	draw_colored_polygon(
		polygon,
		Color(0.2, 0.8, 0.3, 0.45)
	)


func draw_worker_preview_cell(
	cell: Vector2i
):
	var world_position: Vector2 = (
		get_cell_world_position(cell)
	)

	var center: Vector2 = (
		to_local(world_position)
	)

	var half_width: float = (
		float(floor.tile_width) * 0.5
	)

	var half_height: float = (
		float(floor.tile_height) * 0.5
	)

	var polygon := PackedVector2Array([
		center + Vector2(0, -half_height),
		center + Vector2(half_width, 0),
		center + Vector2(0, half_height),
		center + Vector2(-half_width, 0)
	])

	# 직원 작업칸 = 주황색
	draw_colored_polygon(
		polygon,
		Color(1.0, 0.65, 0.15, 0.4)
	)

func select_furniture(index: int):
	if index < 0 or index >= furniture_catalog.size():
		return

	selected_index = index

	# 가구를 새로 선택하면 기본 방향으로 초기화
	rotation_index = 0

	create_preview()

	print(
		"가구 선택: ",
		furniture_catalog[selected_index]["name"]
	)

func rotate_furniture():
	rotation_index = (rotation_index + 1) % 4

	update_preview_size()

	print(
		"가구 회전: ",
		rotation_index * 90,
        "도"
	)

func create_preview():
	if is_instance_valid(preview):
		preview.queue_free()

	var scene: PackedScene = (
		furniture_catalog[selected_index]["scene"]
	)

	preview = scene.instantiate()

	objects.add_child(preview)

	# 미리보기는 실제 가구 그룹에서 제거
	var gameplay_groups: Array[String] = [
		"shelf",
		"register",
		"door"
	]

	for group_name in gameplay_groups:
		if preview.is_in_group(group_name):
			preview.remove_from_group(group_name)

	preview.set_meta(
		"is_build_preview",
		true
	)

	preview.z_index = 100

	update_preview_size()
	
	if preview.has_method("set_checkout_preview_visible"):
		preview.set_checkout_preview_visible(true)

		print("계산대 결제칸 미리보기 ON")

	var preview_collision = preview.get_node_or_null(
		"Collision"
	)

	if preview_collision != null:
		if preview_collision.has_method("set_blocking"):
			preview_collision.set_blocking(false)
		else:
			preview_collision.set_deferred(
				"disabled",
				true
			)

func update_preview_size():
	if not is_instance_valid(preview):
		return

	apply_current_size(preview)

	if preview.has_method("set_checkout_preview_visible"):
		preview.set_checkout_preview_visible(true)

func apply_furniture_collision(
	furniture,
	size: Vector2i,
	blocking: bool
):
	var collision = furniture.get_node_or_null(
		"Collision"
	)

	if collision == null:
		print(
			"Collision 노드 없음: ",
			furniture.name
		)
		return

	if collision.has_method("set_footprint"):
		collision.set_footprint(
			size.x,
			size.y
		)

	if collision.has_method("set_blocking"):
		collision.set_blocking(
			blocking
		)

	print(
		"충돌 크기 적용: ",
		furniture.name,
		" / ",
		size
	)
	
	print(
	"충돌 확인 / 가구: ",
	furniture.name,
	" / 부모 타입: ",
	collision.get_parent().get_class(),
	" / disabled: ",
	collision.disabled,
	" / layer: ",
	furniture.collision_layer
)

func apply_current_size(furniture):
	var current_size: Vector2i = get_current_size()

	# -------------------------
	# Visual 크기 / 방향 적용
	# -------------------------
	var visual = furniture.get_node_or_null("Visual")

	if visual != null:
		if visual.has_method("set_footprint"):
			visual.set_footprint(
				current_size.x,
				current_size.y
			)

		if visual.has_method("set_rotation_index"):
			visual.set_rotation_index(
				rotation_index
			)

	# -------------------------
	# 현재 가구 종류 확인
	# -------------------------
	var catalog_index: int = selected_index

	if furniture.has_meta("catalog_index"):
		catalog_index = int(
			furniture.get_meta(
				"catalog_index"
			)
		)

	var blocks_movement: bool = true

	if (
		catalog_index >= 0
		and catalog_index < furniture_catalog.size()
	):
		blocks_movement = bool(
			furniture_catalog[catalog_index].get(
				"blocks_movement",
				true
			)
		)

	# -------------------------
	# Collision 크기 적용
	# -------------------------
	apply_furniture_collision(
		furniture,
		current_size,
		blocks_movement
	)

func restore_furniture_collision(furniture):
	if furniture == null:
		return

	var collision = furniture.get_node_or_null(
		"Collision"
	)

	if collision == null:
		return

	var catalog_index: int = int(
		furniture.get_meta(
			"catalog_index",
			-1
		)
	)

	var blocks_movement: bool = true

	if (
		catalog_index >= 0
		and catalog_index < furniture_catalog.size()
	):
		blocks_movement = bool(
			furniture_catalog[catalog_index].get(
				"blocks_movement",
				true
			)
		)

	if collision.has_method("set_blocking"):
		collision.set_blocking(
			blocks_movement
		)

	print(
		"충돌 복구: ",
		furniture.name,
		" / blocking: ",
		blocks_movement,
		" / disabled: ",
		collision.disabled
	)

func get_base_size() -> Vector2i:
	var size: Vector2i = furniture_catalog[selected_index]["size"]

	return size

func get_current_size() -> Vector2i:
	var base_size: Vector2i = get_base_size()

	# 90도 또는 270도 회전 상태
	if rotation_index % 2 == 1:
		return Vector2i(
			base_size.y,
			base_size.x
		)

	return base_size

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

func get_occupied_cells(anchor: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []

	var size: Vector2i = get_current_size()

	for x in range(size.x):
		for y in range(size.y):
			result.append(
				anchor + Vector2i(x, y)
			)

	return result

func can_place(anchor: Vector2i) -> bool:
	if is_door_selected():
		if not can_place_door(anchor):
			return false

	# =========================
	# 실제 가구 본체
	# =========================
	var cells: Array[Vector2i] = (
		get_occupied_cells(anchor)
	)

	for cell in cells:
		if not floor.is_cell_inside(cell):
			return false

		# 다른 가구 본체
		if occupied_cells.has(cell):
			return false

		# 다른 가구의 예약 공간
		if reserved_cells.has(cell):
			return false

	# =========================
	# 직원 작업 예약 공간
	# =========================
	var reserve_cells: Array[Vector2i] = (
		get_current_reserved_cells(anchor)
	)

	for cell in reserve_cells:
		# 직원 공간도 반드시 매장 안이어야 함
		if not floor.is_cell_inside(cell):
			return false

		# 직원 자리에 가구가 있으면 안 됨
		if occupied_cells.has(cell):
			return false

		# 다른 계산대 직원 자리와 겹치면 안 됨
		if reserved_cells.has(cell):
			return false

	return true

func place_furniture():
	var anchor: Vector2i = get_mouse_cell()

	if not can_place(anchor):
		return

	if furniture_catalog[selected_index]["count"] <= 0:
		return

	var scene: PackedScene = furniture_catalog[selected_index]["scene"]
	var furniture = scene.instantiate()

	objects.add_child(furniture)

	apply_current_size(furniture)

	# 진열대라면 종류에 맞는 최대 재고 설정
	# 진열대라면 슬롯 수 설정
	if furniture.is_in_group("shelf"):
		var slots_per_level: int = int(
			furniture_catalog[selected_index].get(
				"slots_per_level",
				2
			)
		)
		
		var slot_capacity: int = int(
			furniture_catalog[selected_index].get(
				"slot_capacity",
				5
			)
		)
		
		
		if furniture.has_method("configure_shelf"):
			furniture.configure_shelf(
				slots_per_level,
				slot_capacity
			)

	# 여기 아래부터 기존 설치 코드 계속
	furniture.global_position = get_current_furniture_world_position(anchor)

	furniture.set_meta("catalog_index", selected_index)
	furniture.set_meta("rotation_index", rotation_index)
	furniture.set_meta("anchor", anchor)

	var cells: Array[Vector2i] = get_occupied_cells(anchor)

	for cell in cells:
		occupied_cells[cell] = furniture

	var reserve_cells: Array[Vector2i] = (
		get_current_reserved_cells(anchor)
	)

	for cell in reserve_cells:
		reserved_cells[cell] = furniture

	furniture_catalog[selected_index]["count"] -= 1

	update_build_ui()

	if furniture_catalog[selected_index]["count"] <= 0:
		clear_build_selection()

func toggle_build_mode():
	if build_mode:
		request_build_mode_exit()
	else:
		start_build_mode()

func start_build_mode():
	build_mode = true

	selected_index = -1
	rotation_index = 0

	build_panel.visible = true

	if is_instance_valid(preview):
		preview.visible = false

	# 플레이어 숨김
	if is_instance_valid(player):
		player.velocity = Vector2.ZERO
		player.visible = false

	# 건축 외 모든 게임 진행 정지
	tree_was_paused_before_build = get_tree().paused
	get_tree().paused = true

	queue_redraw()
	update_build_ui()

	print("건축 모드 ON")


func request_build_mode_exit():
	if not build_mode:
		return

	build_confirm_center.visible = true
	build_confirm_center.z_index = 200

	print("건축 배치 저장 확인")


func confirm_build_changes():
	build_confirm_center.visible = false

	if is_instance_valid(preview):
		preview.visible = false

	selected_index = -1
	rotation_index = 0
	build_mode = false

	build_panel.visible = false

	# 건축 결과 때문에 플레이어가 가구 안에 갇혔는지 검사
	escape_player_if_blocked()

	# 플레이어 다시 표시
	if is_instance_valid(player):
		player.visible = true
		player.velocity = Vector2.ZERO

	# 건축 전에 게임이 진행 중이었다면 다시 진행
	get_tree().paused = tree_was_paused_before_build

	queue_redraw()
	update_build_ui()

	save_store_layout()

	print("건축 배치 확정")
	print("건축 모드 OFF")


func cancel_build_confirmation():
	build_confirm_center.visible = false

	# build_mode는 계속 true
	# build_panel도 계속 보임

	print("건축 계속 편집")

func remove_furniture():
	var cell: Vector2i = get_mouse_cell()

	# 해당 칸에 가구가 없으면 종료
	if not occupied_cells.has(cell):
		return

	var furniture = occupied_cells[cell]

	# 어떤 종류의 가구인지 확인
	var catalog_index: int = int(
		furniture.get_meta("catalog_index", 0)
	)

	# 이 가구가 차지하고 있는 모든 칸 찾기
	var cells_to_remove: Array = []

	for occupied_cell in occupied_cells.keys():
		if occupied_cells[occupied_cell] == furniture:
			cells_to_remove.append(occupied_cell)

	var reserved_to_remove: Array[Vector2i] = []

	for reserved_cell in reserved_cells.keys():
		if reserved_cells[reserved_cell] == furniture:
			reserved_to_remove.append(
				reserved_cell
			)

	# 여러 단으로 쌓인 진열대라면
	# 가장 위 단만 철거
	if furniture.is_in_group("shelf"):
		if furniture.stack_level > 1:

			# 위 단에 상품이 있으면 철거 금지
			if furniture.top_level_has_items():
				print(
					"위쪽 진열대에 상품이 있어서 철거할 수 없음"
				)
				return

			if furniture.remove_level():
				furniture_catalog[catalog_index]["count"] += 1
				update_build_ui()

				print(
					"진열대 1단 철거 / 현재 ",
					furniture.stack_level,
					"단"
				)

			return

	# 점유 정보 제거
	for occupied_cell in cells_to_remove:
		occupied_cells.erase(occupied_cell)

	# 예약 정보 제거
	for reserved_cell in reserved_to_remove:
		reserved_cells.erase(
			reserved_cell
		)

	# ★ 철거한 가구를 보유 수량으로 반환
	furniture_catalog[catalog_index]["count"] += 1

	# ★ 메뉴 수량 갱신
	update_build_ui()

	# 실제 가구 삭제
	furniture.queue_free()

	print(
		"가구 철거: ",
		furniture_catalog[catalog_index]["name"],
		" / 보유 수량: ",
		furniture_catalog[catalog_index]["count"]
	)

func handle_left_click():
	var cell: Vector2i = get_mouse_cell()

	# 이미 가구 이동 중
	if moving_furniture != null:
		finish_move_furniture()
		return

	# Shift + 좌클릭은 기존 가구 이동
	if occupied_cells.has(cell):
		if Input.is_key_pressed(KEY_SHIFT):
			start_move_furniture(cell)
			return

	# 같은 진열대라면 적층 우선
	var target_shelf = get_shelf_at(cell)

	if can_stack_on_shelf(target_shelf):
		stack_shelf(target_shelf)
		return

	# 적층할 수 없는 기존 가구 클릭
	# → 기존 이동 기능 유지
	if occupied_cells.has(cell):
		start_move_furniture(cell)
		return

	# 빈 칸
	place_furniture()

func start_move_furniture(cell: Vector2i):
	moving_furniture = occupied_cells[cell]

	# 원래 위치 기억
	moving_original_anchor = moving_furniture.get_meta(
		"anchor",
		cell
	)

	moving_original_cells.clear()
	moving_original_reserved_cells.clear()

	for reserved_cell in reserved_cells.keys():
		if reserved_cells[reserved_cell] == moving_furniture:
			moving_original_reserved_cells.append(
				reserved_cell
			)

	# 이 가구가 차지하던 모든 칸 찾기
	for occupied_cell in occupied_cells.keys():
		if occupied_cells[occupied_cell] == moving_furniture:
			moving_original_cells.append(occupied_cell)

	# 기존 점유 정보 제거
	for occupied_cell in moving_original_cells:
		occupied_cells.erase(occupied_cell)

	for reserved_cell in moving_original_reserved_cells:
		reserved_cells.erase(
			reserved_cell
		)

	# 이 가구의 종류와 회전 상태 불러오기
	selected_index = int(
		moving_furniture.get_meta("catalog_index", 0)
	)

	rotation_index = int(
		moving_furniture.get_meta("rotation_index", 0)
	)

	# 실제 가구는 잠시 숨김
	moving_furniture.visible = false

	# 같은 모양의 미리보기 생성
	create_preview()

	print("가구 이동 시작")

func finish_move_furniture():
	var new_anchor: Vector2i = get_mouse_cell()

	# 설치 불가능한 자리면 계속 들고 있는 상태 유지
	if not can_place(new_anchor):
		return

	moving_furniture.global_position = get_current_furniture_world_position(
		new_anchor
	)

	apply_current_size(moving_furniture)
	restore_furniture_collision(moving_furniture)



	# 새 위치 정보 저장
	moving_furniture.set_meta(
		"catalog_index",
		selected_index
	)

	moving_furniture.set_meta(
		"rotation_index",
		rotation_index
	)

	moving_furniture.set_meta(
		"anchor",
		new_anchor
	)

	# 새 점유 칸 등록
	var new_cells: Array[Vector2i] = get_occupied_cells(
		new_anchor
	)

	for cell in new_cells:
		occupied_cells[cell] = moving_furniture

	var new_reserved_cells: Array[Vector2i] = (
		get_current_reserved_cells(
			new_anchor
		)
	)

	for cell in new_reserved_cells:
		reserved_cells[cell] = moving_furniture

	moving_furniture.visible = true
	moving_furniture = null

	moving_original_reserved_cells.clear()
	moving_original_cells.clear()

	print("가구 이동 완료")

func cancel_move_furniture():
	if moving_furniture == null:
		return

	# 원래 자리의 점유 정보 복구
	for cell in moving_original_cells:
		occupied_cells[cell] = moving_furniture

	for cell in moving_original_reserved_cells:
		reserved_cells[cell] = moving_furniture

	moving_furniture.global_position = get_cell_world_position(
		moving_original_anchor
	)

	moving_furniture.visible = true
	moving_furniture = null

	moving_original_cells.clear()
	moving_original_reserved_cells.clear()

	print("가구 이동 취소")

func update_build_ui():
	var count_1x1: int = furniture_catalog[0]["count"]
	var count_2x1: int = furniture_catalog[1]["count"]
	var count_3x1: int = furniture_catalog[2]["count"]
	var count_register: int = furniture_catalog[3]["count"]
	var count_door: int = furniture_catalog[4]["count"]

	shelf_1x1_button.text = (
		"1×1 진열대\n보유 " + str(count_1x1)
	)

	shelf_2x1_button.text = (
		"2×1 진열대\n보유 " + str(count_2x1)
	)
	
	shelf_3x1_button.text = (
		"3×1 진열대\n보유 " + str(count_3x1)
	)


	register_button.text = (
		"계산대\n보유 " + str(count_register)
	)

	door_button.text = (
		"문\n보유 " + str(count_door)
	)

	shelf_1x1_button.disabled = count_1x1 <= 0
	shelf_2x1_button.disabled = count_2x1 <= 0
	shelf_3x1_button.disabled = count_3x1 <= 0
	register_button.disabled = count_register <= 0
	door_button.disabled = count_door <= 0

func is_door_selected() -> bool:
	if selected_index < 0:
		return false

	if selected_index >= furniture_catalog.size():
		return false

	return str(
		furniture_catalog[selected_index].get(
			"type",
			""
		)
	) == "door"

func is_door_cell(cell: Vector2i) -> bool:
	if not floor.is_cell_inside(cell):
		return false

	var columns: int = int(floor.columns)
	var rows: int = int(floor.rows)

	var left_edge: bool = cell.x == 0
	var right_edge: bool = cell.x == columns - 1
	var top_edge: bool = cell.y == 0
	var bottom_edge: bool = cell.y == rows - 1

	return left_edge or right_edge or top_edge or bottom_edge

func can_place_door(cell: Vector2i) -> bool:
	if not floor.is_cell_inside(cell):
		return false

	var columns: int = int(floor.columns)
	var rows: int = int(floor.rows)

	match rotation_index:
		0:
			# 위쪽 외벽
			return cell.y == 0

		1:
			# 오른쪽 외벽
			return cell.x == columns - 1

		2:
			# 아래쪽 외벽
			return cell.y == rows - 1

		3:
			# 왼쪽 외벽
			return cell.x == 0

	return false

func get_door_world_position(cell: Vector2i) -> Vector2:
	var center: Vector2 = get_cell_world_position(cell)

	var tile_width: float = float(floor.tile_width)
	var tile_height: float = float(floor.tile_height)

	match rotation_index:
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

func get_current_furniture_world_position(cell: Vector2i) -> Vector2:
	if is_door_selected():
		return get_door_world_position(cell)

	return get_cell_world_position(cell)

func is_shelf_selected() -> bool:
	if selected_index < 0:
		return false

	if selected_index >= furniture_catalog.size():
		return false

	return str(
		furniture_catalog[selected_index].get(
			"type",
			""
		)
	) == "shelf"

func get_shelf_at(cell: Vector2i):
	if not occupied_cells.has(cell):
		return null

	var furniture = occupied_cells[cell]

	if furniture.is_in_group("shelf"):
		return furniture

	return null

func can_stack_on_shelf(target) -> bool:
	if target == null:
		return false

	if not is_shelf_selected():
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

	if target_catalog_index != selected_index:
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
		if target_rotation % 2 != rotation_index % 2:
			return false

	# 보유 가구가 없으면 추가 불가
	if furniture_catalog[selected_index]["count"] <= 0:
		return false

	return true

func stack_shelf(target):
	if not can_stack_on_shelf(target):
		return

	if not target.add_level():
		return

	# 같은 진열대 하나 소비
	furniture_catalog[selected_index]["count"] -= 1

	update_build_ui()

	if furniture_catalog[selected_index]["count"] <= 0:
		clear_build_selection()

	print(
		"진열대 적층 완료 / ",
		target.stack_level,
		"단 / 슬롯 ",
		target.slots.size()
	)

func is_cell_blocked_for_customer(
	cell: Vector2i
) -> bool:

	if not floor.is_cell_inside(cell):
		return true

	if not occupied_cells.has(cell):
		return false

	var furniture = occupied_cells[cell]

	if not is_instance_valid(furniture):
		return false

	var catalog_index: int = int(
		furniture.get_meta(
			"catalog_index",
			-1
		)
	)

	if (
		catalog_index < 0
		or catalog_index >= furniture_catalog.size()
	):
		return true

	return bool(
		furniture_catalog[catalog_index].get(
			"blocks_movement",
			true
		)
	)

func get_adjacent_walkable_cells(
	furniture
) -> Array[Vector2i]:

	var result: Array[Vector2i] = []
	var checked: Dictionary = {}

	var directions: Array[Vector2i] = [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1)
	]

	# 해당 가구가 차지하고 있는 모든 칸 검사
	for occupied_cell in occupied_cells.keys():
		if occupied_cells[occupied_cell] != furniture:
			continue

		for direction in directions:
			var candidate: Vector2i = (
				occupied_cell + direction
			)

			# 같은 후보를 여러 번 추가하지 않음
			if checked.has(candidate):
				continue

			checked[candidate] = true

			if not floor.is_cell_inside(candidate):
				continue

			if is_cell_blocked_for_customer(candidate):
				continue

			result.append(candidate)

	return result

func is_register_selected() -> bool:
	if selected_index < 0:
		return false

	if selected_index >= furniture_catalog.size():
		return false

	return str(
		furniture_catalog[selected_index].get(
			"type",
			""
		)
	) == "register"
	
func get_register_checkout_offsets() -> Array[Vector2i]:
	var result: Array[Vector2i] = []

	match rotation_index % 4:
		0:
			result = [
				Vector2i(0, 1),
				Vector2i(1, 1)
			]

		1:
			result = [
				Vector2i(1, 0),
				Vector2i(1, 1)
			]

		2:
			result = [
				Vector2i(0, -1),
				Vector2i(1, -1)
			]

		3:
			result = [
				Vector2i(-1, 0),
				Vector2i(-1, 1)
			]

	return result

func get_register_worker_offsets() -> Array[Vector2i]:
	var result: Array[Vector2i] = []

	match rotation_index % 4:
		0:
			result = [
				Vector2i(0, -1),
				Vector2i(1, -1)
			]

		1:
			result = [
				Vector2i(-1, 0),
				Vector2i(-1, 1)
			]

		2:
			result = [
				Vector2i(0, 1),
				Vector2i(1, 1)
			]

		3:
			result = [
				Vector2i(1, 0),
				Vector2i(1, 1)
			]

	return result

func get_current_reserved_cells(
	anchor: Vector2i
) -> Array[Vector2i]:

	var result: Array[Vector2i] = []

	if not is_register_selected():
		return result

	for offset in get_register_worker_offsets():
		result.append(
			anchor + offset
		)

	return result

func get_shelf_access_offsets() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var size: Vector2i = get_current_size()

	match rotation_index % 4:
		0:
			for x in range(size.x):
				result.append(
					Vector2i(x, size.y)
				)

		1:
			for y in range(size.y):
				result.append(
					Vector2i(size.x, y)
				)

		2:
			for x in range(size.x):
				result.append(
					Vector2i(x, -1)
				)

		3:
			for y in range(size.y):
				result.append(
					Vector2i(-1, y)
				)

	return result

func draw_shelf_access_cell(
	cell: Vector2i
):
	var world_position: Vector2 = (
		get_cell_world_position(cell)
	)

	var center: Vector2 = (
		to_local(world_position)
	)

	var half_width: float = (
		float(floor.tile_width) * 0.5
	)

	var half_height: float = (
		float(floor.tile_height) * 0.5
	)

	var polygon := PackedVector2Array([
		center + Vector2(0, -half_height),
		center + Vector2(half_width, 0),
		center + Vector2(0, half_height),
		center + Vector2(-half_width, 0)
	])

	draw_colored_polygon(
		polygon,
		Color(0.25, 0.55, 1.0, 0.4)
	)

func clear_build_selection():
	selected_index = -1
	rotation_index = 0

	if is_instance_valid(preview):
		preview.visible = false

	queue_redraw()

	print("가구 선택 해제")

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
			and not is_cell_blocked_for_customer(cell)
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
	if not is_cell_blocked_for_customer(
		player_cell
	):
		return

	var safe_cell: Vector2i = (
		find_nearest_walkable_cell(
			player_cell
		)
	)

	if safe_cell == Vector2i(-1, -1):
		print(
			"[건축] 플레이어 탈출 위치를 찾지 못함"
		)
		return

	player.global_position = (
		get_cell_world_position(
			safe_cell
		)
	)

	player.velocity = Vector2.ZERO

	print(
		"[건축] 플레이어 자동 이동: ",
		player_cell,
		" → ",
		safe_cell
	)

func get_store_layout_data() -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	for furniture in objects.get_children():
		if not is_instance_valid(furniture):
			continue

		# 건축 미리보기 제외
		if bool(
			furniture.get_meta(
				"is_build_preview",
				false
			)
		):
			continue

		if not furniture.has_meta(
			"catalog_index"
		):
			continue

		if not furniture.has_meta(
			"anchor"
		):
			continue

		var data: Dictionary = {
			"catalog_index": int(
				furniture.get_meta(
					"catalog_index"
				)
			),

			"rotation_index": int(
				furniture.get_meta(
					"rotation_index",
					0
				)
			),

			"anchor": furniture.get_meta(
				"anchor"
			)
		}

		# =========================
		# 진열대 상태 저장
		# =========================
		if furniture.is_in_group("shelf"):
			data["stack_level"] = int(
				furniture.stack_level
			)

			# 슬롯의 상품 종류 / 현재 재고 /
			# 용량 등을 통째로 깊은 복사
			data["shelf_slots"] = (
				furniture.slots.duplicate(true)
			)

			print(
				"[저장 확인] 진열대 슬롯: ",
				data["shelf_slots"]
			)

		result.append(data)

	return result

func save_store_layout():
	var layout: Array[Dictionary] = (
		get_store_layout_data()
	)

	GameState.save_store_layout(
		layout
	)

func restore_store_layout():
	if not GameState.has_store_layout():
		print("[GameState] 복원할 편의점 배치 없음")
		return

	var layout: Array[Dictionary] = (
		GameState.get_store_layout()
	)

	print(
		"[GameState] 편의점 배치 복원 시작 / ",
		layout.size(),
		"개"
	)

	# 새로운 main.tscn이므로 점유 정보부터 초기화
	occupied_cells.clear()
	reserved_cells.clear()

	for data in layout:
		var catalog_index: int = int(
			data.get(
				"catalog_index",
				-1
			)
		)

		if (
			catalog_index < 0
			or catalog_index >= furniture_catalog.size()
		):
			print(
				"[복원 실패] 잘못된 catalog_index: ",
				catalog_index
			)
			continue

		var anchor: Vector2i = (
			data.get(
				"anchor",
				Vector2i(-1, -1)
			)
		)

		var saved_rotation: int = int(
			data.get(
				"rotation_index",
				0
			)
		)

		# 기존 BuildManager 함수들이
		# selected_index / rotation_index를 기준으로 동작하므로
		# 복원하는 가구 정보로 임시 변경
		selected_index = catalog_index
		rotation_index = saved_rotation

		var scene: PackedScene = (
			furniture_catalog[catalog_index][
				"scene"
			]
		)

		var furniture = scene.instantiate()

		objects.add_child(furniture)

		# 메타데이터 복원
		furniture.set_meta(
			"catalog_index",
			catalog_index
		)

		furniture.set_meta(
			"rotation_index",
			saved_rotation
		)

		furniture.set_meta(
			"anchor",
			anchor
		)

		# 크기 / 회전 / 충돌 복원
		apply_current_size(furniture)

		if furniture.is_in_group("shelf"):
			var saved_slots: Array = (
				data.get(
					"shelf_slots",
					[]
				)
			)

			if not saved_slots.is_empty():
				furniture.slots = (
					saved_slots.duplicate(true)
				)

				furniture.update_stock_label()

				print(
					"[복원 확인] ",
					furniture.slots
				)

				if furniture.has_method(
					"update_stock_label"
				):
					furniture.update_stock_label()

				print(
					"[진열대 복원] 슬롯 ",
					furniture.slots.size(),
					"개"
				)

		# 진열대 기본 슬롯 설정
		if furniture.is_in_group("shelf"):
			var slots_per_level: int = int(
				furniture_catalog[
					catalog_index
				].get(
					"slots_per_level",
					2
				)
			)

			var slot_capacity: int = int(
				furniture_catalog[
					catalog_index
				].get(
					"slot_capacity",
					5
				)
			)

			if furniture.has_method(
				"configure_shelf"
			):
				furniture.configure_shelf(
					slots_per_level,
					slot_capacity
				)

		# 실제 위치 복원
		furniture.global_position = (
			get_current_furniture_world_position(
				anchor
			)
		)

		# =========================
		# 실제 가구 점유 칸 복원
		# =========================
		var cells: Array[Vector2i] = (
			get_occupied_cells(anchor)
		)

		for cell in cells:
			occupied_cells[cell] = furniture

		# =========================
		# 계산대 직원 작업칸 복원
		# =========================
		var reserve_cells: Array[Vector2i] = (
			get_current_reserved_cells(
				anchor
			)
		)

		for cell in reserve_cells:
			reserved_cells[cell] = furniture

		# =========================
		# 진열대 적층 복원
		# =========================
		var used_count: int = 1

		if furniture.is_in_group("shelf"):
			var saved_stack_level: int = int(
				data.get(
					"stack_level",
					1
				)
			)

			saved_stack_level = clampi(
				saved_stack_level,
				1,
				3
			)

			# =========================
			# 적층 먼저 복원
			# =========================
			while (
				furniture.stack_level
				< saved_stack_level
			):
				if not furniture.add_level():
					break

			used_count = (
				furniture.stack_level
			)

			# =========================
			# 슬롯 내용 복원
			# =========================
			var saved_slots: Array = (
				data.get(
					"shelf_slots",
					[]
				)
			)

			if not saved_slots.is_empty():
				furniture.slots.clear()

				for slot_data in saved_slots:
					if slot_data is Dictionary:
						furniture.slots.append(
							slot_data.duplicate(true)
						)

				print(
					"[진열대 복원] 슬롯: ",
					furniture.slots.size()
				)

		# 설치되어 있는 만큼 보유 수량 차감
		furniture_catalog[
			catalog_index
		]["count"] = max(
			0,
			int(
				furniture_catalog[
					catalog_index
				]["count"]
			)
			- used_count
		)

		print(
			"[가구 복원] ",
			furniture_catalog[
				catalog_index
			]["name"],
			" / 위치: ",
			anchor,
			" / 회전: ",
			saved_rotation
		)

	# 복원이 끝난 뒤 건축 선택 상태 초기화
	selected_index = -1
	rotation_index = 0

	if is_instance_valid(preview):
		preview.visible = false

	update_build_ui()
	queue_redraw()

	print(
		"[GameState] 편의점 배치 복원 완료"
	)
