extends CharacterBody2D


@export var speed: float = 100.0
@export var shelf_pick_delay: float = 0.8
@export var wander_min_moves: int = 2
@export var wander_max_moves: int = 4
@export var wander_pause_delay: float = 0.7
@export var checkout_delay: float = 1.2
@export var checkout_finish_delay: float = 0.4
@export var move_timeout: float = 4.0
@export var max_move_retries: int = 2

var wander_moves_remaining: int = 0
var move_elapsed: float = 0.0
var move_retry_count: int = 0
var recover_from_state: int = CustomerState.IDLE
var force_exit_requested: bool = false

@onready var floor_node = $"../../Floor"
@onready var build_manager = $"../../BuildManager"

@onready var player = get_parent().get_node("Player")


enum CustomerState {
	IDLE,
	GO_TO_SHELF,
	GO_TO_REGISTER,
	WANDER,
	RECOVER,
	GO_TO_EXIT
}

enum CustomerType {
	NORMAL,
	TRAVELER
}

var customer_type: CustomerType = CustomerType.NORMAL

var state: int = CustomerState.IDLE
var moving: bool = false

var target_shelf = null
var target_register = null
var target_door = null

var grid_path: Array[Vector2i] = []
var grid_path_index: int = 0

var current_target_position: Vector2
var carried_item_id: String = ""
var wanted_item_id: String = ""

func _ready():
	add_to_group("customer")


func _physics_process(delta):

	# 테스트용: Space / Enter로 쇼핑 시작
	if Input.is_action_just_pressed("ui_accept"):
		if state == CustomerState.IDLE:
			start_shopping()

	if not moving:
		velocity = Vector2.ZERO
		return

	move_elapsed += delta

	if move_elapsed >= move_timeout:
		handle_move_timeout()
		return


	if grid_path_index >= grid_path.size():
		moving = false
		velocity = Vector2.ZERO

		arrive_at_target()
		return


	var target_cell: Vector2i = (
		grid_path[grid_path_index]
	)

	var target_local: Vector2 = (
		floor_node.grid_to_local(target_cell)
	)

	var target_world: Vector2 = (
		floor_node.to_global(target_local)
	)

	var distance: float = (
		global_position.distance_to(target_world)
	)


	if distance <= 4.0:
		global_position = target_world
		grid_path_index += 1
		return


	var direction: Vector2 = (
		target_world - global_position
	).normalized()

	velocity = direction * speed

	move_and_slide()

func choose_customer_type():
	var roll: float = randf()

	if roll < 0.7:
		customer_type = CustomerType.NORMAL
	else:
		customer_type = CustomerType.TRAVELER

func choose_wanted_item() -> String:
	var items: Array[String] = (
		ItemData.get_sellable_items()
	)

	if items.is_empty():
		return ""

	return items.pick_random()

func start_shopping():
	print("손님 쇼핑 시작")

	player.record_visitor()


	# -------------------------
	# 원하는 상품 결정
	# -------------------------
	var sellable_items: Array[String] = (
		ItemData.get_sellable_items()
	)

	if sellable_items.is_empty():
		print("판매 가능한 상품 데이터가 없습니다.")
		go_to_exit()
		return

	choose_customer_type()

	wanted_item_id = (
		choose_wanted_item()
	)

	if wanted_item_id.is_empty():
		print("구매 가능한 상품을 선택하지 못했습니다.")
		go_to_exit()
		return

	var wanted_data: Dictionary = (
		ItemData.get_item(wanted_item_id)
	)

	print(
		"손님이 원하는 상품: ",
		wanted_data.get(
			"name",
			wanted_item_id
		)
	)

	# -------------------------
	# 원하는 상품이 있는 진열대 검색
	# -------------------------
	var shelves: Array = (
		get_tree().get_nodes_in_group("shelf")
	)

	var available_shelves: Array = []

	for shelf in shelves:
		if not shelf.has_method(
			"has_item_in_stock"
		):
			continue

		if shelf.has_item_in_stock(
			wanted_item_id
		):
			available_shelves.append(
				shelf
			)

	if available_shelves.is_empty():
		print(
			"원하는 상품 재고 없음: ",
			wanted_item_id
		)

		player.record_missed_sale()

		start_wandering()
		return

	# 같은 상품을 파는 진열대가 여러 개라면
	# 그중 하나를 랜덤 선택
	target_shelf = (
		available_shelves.pick_random()
	)

	# -------------------------
	# 진열대 접근 셀 검색
	# -------------------------
	var shelf_cell: Vector2i = (
		find_best_shelf_access_cell(
			target_shelf
		)
	)

	if shelf_cell == Vector2i(-1, -1):
		print("진열대에 접근할 수 없습니다.")
		go_to_exit()
		return

	print(
		"진열대 접근 셀: ",
		shelf_cell
	)

	state = CustomerState.GO_TO_SHELF

	move_to_cell(shelf_cell)


func move_to(target: Vector2):
	current_target_position = target

	var start_cell: Vector2i = (
		floor_node.local_to_grid(
			floor_node.to_local(global_position)
		)
	)

	var target_cell: Vector2i = (
		floor_node.local_to_grid(
			floor_node.to_local(target)
		)
	)

	grid_path = create_astar_grid_path(
		start_cell,
		target_cell
	)

	grid_path_index = 0
	moving = not grid_path.is_empty()
	move_elapsed = 0.0

	print(
		"격자 이동: ",
		start_cell,
		" → ",
		target_cell,
		" / 경로 ",
		grid_path
	)


func find_register():
	var registers: Array = (
		get_tree().get_nodes_in_group("register")
	)

	for register in registers:
		if not is_instance_valid(register):
			continue

		if bool(
			register.get_meta(
				"is_build_preview",
				false
			)
		):
			continue

		if not register.has_meta("anchor"):
			continue

		return register

	return null


func arrive_at_target():
	move_elapsed = 0.0
	
	if state != CustomerState.RECOVER:
		move_retry_count = 0
		
	match state:

		CustomerState.GO_TO_SHELF:
			print("진열대 도착")

			velocity = Vector2.ZERO

			print("상품 확인 중...")

			await get_tree().create_timer(
				shelf_pick_delay
			).timeout

			if not is_instance_valid(target_shelf):
				go_to_exit()
				return

			carried_item_id = (
				target_shelf.take_one_item_by_id(
					wanted_item_id
				)
			)

			if carried_item_id.is_empty():
				print("상품을 가져오지 못했습니다.")

				state = CustomerState.GO_TO_EXIT

				go_to_exit()
				return

			print(
				"손님이 상품을 가져감: ",
				carried_item_id
			)

			target_register = find_register()

			if target_register == null:
				print("계산대가 없습니다.")

				state = CustomerState.GO_TO_EXIT

				go_to_exit()
				return

			var register_cell: Vector2i = (
				find_best_checkout_cell(
					target_register
				)
			)

			if register_cell == Vector2i(-1, -1):
				print("계산대에 접근할 수 없습니다.")

				go_to_exit()
				return

			print(
				"계산대 접근 셀: ",
				register_cell
			)

			state = CustomerState.GO_TO_REGISTER

			move_to_cell(register_cell)

		CustomerState.WANDER:
			print("구경 위치 도착")

			velocity = Vector2.ZERO

			await get_tree().create_timer(
				wander_pause_delay
			).timeout

			if force_exit_requested:
				return

			wander_moves_remaining -= 1

			if wander_moves_remaining <= 0:
				print("손님 구경 종료")
				go_to_exit()
				return

			move_to_next_wander_cell()

		CustomerState.GO_TO_REGISTER:
			print("계산대 도착")

			moving = false
			velocity = Vector2.ZERO

			if not is_instance_valid(target_register):
				go_to_exit()
				return

			while is_instance_valid(target_register):
				if force_exit_requested:
					return

				var accepted: bool = (
					target_register.request_checkout(
						self
					)
				)

				if accepted:
					print("계산 기다리는 중...")
					return

				print("계산대 사용 중 - 대기")

				await get_tree().create_timer(
					0.4
				).timeout

				if force_exit_requested:
					return

			# 계산대가 사라졌다면 퇴장
			go_to_exit()

		CustomerState.RECOVER:
			print("우회 위치 도착")

			velocity = Vector2.ZERO

			await get_tree().create_timer(
				0.3
			).timeout

			if force_exit_requested:
				return

			retry_previous_target()

		CustomerState.GO_TO_EXIT:
			print("출구 도착")
			finish_exit()

			carried_item_id = ""
			target_shelf = null
			target_register = null
			target_door = null

			queue_free()


func checkout_item():
	if carried_item_id.is_empty():
		print("계산할 상품이 없습니다.")
		return

	if not ItemData.has_item(
		carried_item_id
	):
		print(
			"상품 데이터를 찾을 수 없음: ",
			carried_item_id
		)
		return

	var price: int = (
		ItemData.get_item_price(
			carried_item_id
		)
	)

	if price <= 0:
		print(
			"상품 가격이 없습니다: ",
			carried_item_id
		)
		return

	player.add_money(price)
	player.record_successful_sale(price)

	print(
		"계산 완료: ",
		carried_item_id,
		" / ",
		price,
		"원"
	)



func find_door():
	var doors: Array = (
		get_tree().get_nodes_in_group("door")
	)

	for door in doors:
		if not is_instance_valid(door):
			continue

		if bool(
			door.get_meta(
				"is_build_preview",
				false
			)
		):
			continue

		if not door.has_meta("anchor"):
			continue

		return door

	return null
	
func go_to_exit():
	force_exit_requested = true

	target_door = find_door()

	if target_door == null:
		print("출구 문이 없습니다.")
		finish_exit()
		return

	var door_cell: Vector2i = (
		target_door.get_meta(
			"anchor"
		)
	)

	print(
		"출구 문 발견: ",
		target_door.name,
		" / 셀: ",
		door_cell
	)

	# 기존 행동/경로 완전히 취소
	grid_path.clear()
	grid_path_index = 0
	move_elapsed = 0.0
	velocity = Vector2.ZERO

	state = CustomerState.GO_TO_EXIT

	var current_cell: Vector2i = (
		get_current_grid_cell()
	)

	# 이미 문 칸이면 바로 퇴장
	if current_cell == door_cell:
		finish_exit()
		return

	move_to_cell(
		door_cell
	)

	# 경로 생성 자체가 실패한 경우
	if not moving:
		print(
			"[손님 퇴장] 출구 경로 생성 실패 → 강제 퇴장"
		)

		finish_exit()

func finish_exit():
	moving = false
	velocity = Vector2.ZERO

	grid_path.clear()
	grid_path_index = 0
	move_elapsed = 0.0

	carried_item_id = ""
	target_shelf = null
	target_register = null
	target_door = null

	print("손님 쇼핑 완료 / 퇴장")

	queue_free()

func create_astar_grid_path(
	start_cell: Vector2i,
	target_cell: Vector2i
) -> Array[Vector2i]:

	var astar := AStarGrid2D.new()

	astar.region = Rect2i(
		0,
		0,
		int(floor_node.columns),
		int(floor_node.rows)
	)

	# 격자 4방향만 허용
	astar.diagonal_mode = (
		AStarGrid2D.DIAGONAL_MODE_NEVER
	)

	astar.default_compute_heuristic = (
		AStarGrid2D.HEURISTIC_MANHATTAN
	)

	astar.default_estimate_heuristic = (
		AStarGrid2D.HEURISTIC_MANHATTAN
	)

	astar.update()

	# 가구가 있는 셀을 이동 불가로 설정
	for x in range(int(floor_node.columns)):
		for y in range(int(floor_node.rows)):
			var cell := Vector2i(x, y)

			if build_manager.is_cell_blocked_for_customer(
				cell
			):
				astar.set_point_solid(
					cell,
					true
				)

	# 시작 위치는 혹시 막힘 판정이어도 풀어준다.
	if floor_node.is_cell_inside(start_cell):
		astar.set_point_solid(
			start_cell,
			false
		)

	# 목표가 가구 칸으로 판정되면
	# 주변에서 가장 가까운 빈 칸을 찾는다.
	var goal_cell: Vector2i = (
		find_walkable_target_cell(
			target_cell,
			astar
		)
	)

	if goal_cell.x < 0:
		print(
			"이동 가능한 목표 셀을 찾지 못함: ",
			target_cell
		)

		return []

	var path: Array[Vector2i] = (
		astar.get_id_path(
			start_cell,
			goal_cell
		)
	)

	print(
		"A* 경로: ",
		start_cell,
		" → ",
		goal_cell,
		" / ",
		path
	)

	return path

func find_walkable_target_cell(
	target_cell: Vector2i,
	astar: AStarGrid2D
) -> Vector2i:

	# 원래 목표가 빈 셀이면 그대로 사용
	if (
		floor_node.is_cell_inside(target_cell)
		and not astar.is_point_solid(target_cell)
	):
		return target_cell

	# 목표 주변을 1~3칸까지 검색
	for radius in range(1, 4):

		var candidates: Array[Vector2i] = [
			target_cell + Vector2i(radius, 0),
			target_cell + Vector2i(-radius, 0),
			target_cell + Vector2i(0, radius),
			target_cell + Vector2i(0, -radius)
		]

		for cell in candidates:
			if not floor_node.is_cell_inside(cell):
				continue

			if astar.is_point_solid(cell):
				continue

			return cell

	return Vector2i(-1, -1)

func get_current_grid_cell() -> Vector2i:
	return floor_node.local_to_grid(
		floor_node.to_local(
			global_position
		)
	)
	
	

func find_best_access_cell(
	furniture
) -> Vector2i:

	var candidates: Array[Vector2i] = (
		build_manager.get_adjacent_walkable_cells(
			furniture
		)
	)

	if candidates.is_empty():
		return Vector2i(-1, -1)

	var start_cell: Vector2i = (
		get_current_grid_cell()
	)

	var best_cell := Vector2i(-1, -1)
	var best_path_size: int = 999999

	for candidate in candidates:

		# 현재 손님이 서 있는 칸은
		# 계산대 접근 위치로 사용하지 않는다.
		if candidate == start_cell:
			continue

		var test_path: Array[Vector2i] = (
			create_astar_grid_path(
				start_cell,
				candidate
			)
		)

		# 이동 불가능
		if test_path.is_empty():
			continue

		# 시작 셀 하나뿐인 경로도 제외
		if test_path.size() <= 1:
			continue

		if test_path.size() < best_path_size:
			best_path_size = test_path.size()
			best_cell = candidate

	print(
		"접근 셀 선택 / 현재: ",
		start_cell,
		" / 목표: ",
		best_cell,
		" / 거리: ",
		best_path_size
	)

	return best_cell


func move_to_cell(
	target_cell: Vector2i
):
	var start_cell: Vector2i = (
		get_current_grid_cell()
	)

	if target_cell == start_cell:
		print(
			"이동 취소: 현재 셀과 목표 셀이 같음 ",
			start_cell
		)
		return

	grid_path = create_astar_grid_path(
		start_cell,
		target_cell
	)

	grid_path_index = 0
	moving = not grid_path.is_empty()
	move_elapsed = 0.0

	print(
		"셀 이동: ",
		start_cell,
		" → ",
		target_cell,
		" / 경로: ",
		grid_path
	)

func find_best_checkout_cell(
	register
) -> Vector2i:

	var candidates: Array[Vector2i] = (
		register.get_checkout_cells()
	)

	var start_cell: Vector2i = (
		get_current_grid_cell()
	)

	var best_cell := Vector2i(-1, -1)
	var best_path_size: int = 999999

	for candidate in candidates:
		if not floor_node.is_cell_inside(candidate):
			continue

		if build_manager.is_cell_blocked_for_customer(
			candidate
		):
			continue

		var path: Array[Vector2i] = (
			create_astar_grid_path(
				start_cell,
				candidate
			)
		)

		if path.is_empty():
			continue

		if path.size() < best_path_size:
			best_path_size = path.size()
			best_cell = candidate

	return best_cell

func find_best_shelf_access_cell(
	shelf
) -> Vector2i:

	var candidates: Array[Vector2i] = (
		shelf.get_customer_access_cells()
	)

	var start_cell: Vector2i = (
		get_current_grid_cell()
	)

	var best_cell := Vector2i(-1, -1)
	var best_path_size: int = 999999

	for candidate in candidates:
		if not floor_node.is_cell_inside(candidate):
			continue

		if build_manager.is_cell_blocked_for_customer(
			candidate
		):
			continue

		var path: Array[Vector2i] = (
			create_astar_grid_path(
				start_cell,
				candidate
			)
		)

		if path.is_empty():
			continue

		if path.size() < best_path_size:
			best_path_size = path.size()
			best_cell = candidate

	return best_cell

func find_random_walkable_cell() -> Vector2i:
	var start_cell: Vector2i = (
		get_current_grid_cell()
	)

	# 무한 반복 방지
	for attempt in range(30):
		var cell := Vector2i(
			randi_range(
				0,
				int(floor_node.columns) - 1
			),
			randi_range(
				0,
				int(floor_node.rows) - 1
			)
		)

		if cell == start_cell:
			continue

		if build_manager.is_cell_blocked_for_customer(
			cell
		):
			continue

		var test_path: Array[Vector2i] = (
			create_astar_grid_path(
				start_cell,
				cell
			)
		)

		if test_path.is_empty():
			continue

		return cell

	return Vector2i(-1, -1)
	
func start_wandering():
	wander_moves_remaining = randi_range(
		wander_min_moves,
		wander_max_moves
	)

	state = CustomerState.WANDER

	print(
		"손님 구경 시작 / 이동 횟수: ",
		wander_moves_remaining
	)

	move_to_next_wander_cell()
	
func move_to_next_wander_cell():
	var target_cell: Vector2i = (
		find_random_walkable_cell()
	)

	if target_cell == Vector2i(-1, -1):
		print("구경할 위치를 찾지 못함")
		go_to_exit()
		return

	print(
		"구경 위치: ",
		target_cell
	)

	move_to_cell(target_cell)

func complete_checkout_by_worker():
	if carried_item_id.is_empty():
		return

	checkout_item()

	print("직원이 계산 완료")

	await get_tree().create_timer(
		checkout_finish_delay
	).timeout

	# 기다리는 동안 폐점 명령을 받았다면
	# 쇼핑을 다시 진행하지 않음
	if force_exit_requested:
		return

	go_to_exit()

func handle_move_timeout():
	print(
		"이동 시간 초과 / 상태: ",
		state,
		" / 재시도: ",
		move_retry_count
	)

	moving = false
	velocity = Vector2.ZERO
	grid_path.clear()
	grid_path_index = 0
	move_elapsed = 0.0

	move_retry_count += 1

	# 강제 퇴장 중에는 쇼핑용 우회 로직을 사용하지 않음
	if (
		force_exit_requested
		or state == CustomerState.GO_TO_EXIT
	):
		if move_retry_count > max_move_retries:
			print(
				"[손님 퇴장] 이동 실패 반복 → 강제 퇴장"
			)

			move_retry_count = 0
			finish_exit()
			return

		print(
			"[손님 퇴장] 출구 이동 재시도"
		)

		go_to_exit()
		return

	if move_retry_count > max_move_retries:
		print("이동 재시도 한도 초과 → 퇴장")

		move_retry_count = 0
		go_to_exit()
		return

	recover_from_state = state

	var escape_cell: Vector2i = (
		find_random_walkable_cell()
	)

	if escape_cell == Vector2i(-1, -1):
		print("우회할 위치를 찾지 못함")
		go_to_exit()
		return

	print(
		"잠시 다른 위치로 우회: ",
		escape_cell
	)

	state = CustomerState.RECOVER
	move_to_cell(escape_cell)
	
func retry_previous_target():
	match recover_from_state:

		CustomerState.GO_TO_SHELF:
			if not is_instance_valid(target_shelf):
				go_to_exit()
				return

			var shelf_cell: Vector2i = (
				find_best_shelf_access_cell(
					target_shelf
				)
			)

			if shelf_cell == Vector2i(-1, -1):
				go_to_exit()
				return

			state = CustomerState.GO_TO_SHELF
			move_to_cell(shelf_cell)


		CustomerState.GO_TO_REGISTER:
			if not is_instance_valid(target_register):
				go_to_exit()
				return

			var register_cell: Vector2i = (
				find_best_checkout_cell(
					target_register
				)
			)

			if register_cell == Vector2i(-1, -1):
				go_to_exit()
				return

			state = CustomerState.GO_TO_REGISTER
			move_to_cell(register_cell)


		CustomerState.WANDER:
			state = CustomerState.WANDER
			move_to_next_wander_cell()


		CustomerState.GO_TO_EXIT:
			go_to_exit()


		_:
			go_to_exit()
