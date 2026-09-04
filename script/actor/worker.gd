extends CharacterBody2D


@onready var floor_node = $"../../Floor"
@onready var build_manager = $"../../BuildManager"
@onready var player = get_parent().get_node("Player")
@onready var day_manager = (
	get_tree().current_scene.get_node_or_null(
		"DayManager"
	)
)


@export var speed: float = 100.0
@export var checkout_time: float = 1.2
@export var work_check_interval: float = 0.3
@export var restock_time: float = 0.8

@export var can_checkout: bool = true
@export var can_restock: bool = true

@export var start_cell: Vector2i = Vector2i(4, 4)

@export_range(0, 23) var work_start_hour: int = 9
@export_range(0, 23) var work_end_hour: int = 17

var on_duty: bool = false
var shift_ending: bool = false
var shift_was_active: bool = false


enum WorkerState {
	IDLE,
	GO_TO_REGISTER,
	CHECKOUT,
	GO_TO_SHELF,
	RESTOCK,
	GO_TO_STANDBY,
	GO_TO_EXIT,
	OFF_DUTY
}


var state: WorkerState = WorkerState.IDLE

var grid_path: Array[Vector2i] = []
var grid_path_index: int = 0
var moving: bool = false

var pending_register = null
var pending_shelf = null

var standby_register = null
var reserved_worker_cell := Vector2i(-1, -1)
var work_check_elapsed: float = 0.0


func _ready():
	var start_local: Vector2 = (
		floor_node.grid_to_local(
			start_cell
		)
	)

	global_position = (
		floor_node.to_global(
			start_local
		)
	)

	if day_manager == null:
		print("[직원] DayManager를 찾지 못했습니다.")
		return

	print(
		"[직원] DayManager 연결 성공: ",
		day_manager
	)

	if not day_manager.shop_opened.is_connected(
		_on_shop_opened
	):
		day_manager.shop_opened.connect(
			_on_shop_opened
		)

	# 게임 시작은 아직 오픈 준비 상태
	# 09시 근무자도 미리 출근시키지 않는다.
	shift_was_active = false
	on_duty = false
	shift_ending = false

	state = WorkerState.OFF_DUTY
	visible = false

func _process(delta):
	if day_manager == null:
		return

	if not day_manager.shop_open:
		return

	work_check_elapsed += delta

	if work_check_elapsed < work_check_interval:
		return

	work_check_elapsed = 0.0


	# =========================
	# 현재 근무시간 판정
	# =========================
	var active_now: bool = (
		day_manager.shop_open
		and is_hour_in_shift(
			day_manager.current_hour
		)
	)


	# =========================
	# 출근
	# =========================
	if active_now and not shift_was_active:
		on_duty = true
		shift_ending = false

		begin_shift()

		print(
			"[직원] 출근: ",
			name,
			" / ",
			day_manager.current_hour,
			":00"
		)


	# =========================
	# 퇴근
	# =========================
	elif not active_now and shift_was_active:
		on_duty = false
		shift_ending = true

		print(
			"[직원] 퇴근 시간: ",
			name,
			" / ",
			day_manager.current_hour,
			":00"
		)

		request_shift_end()


	shift_was_active = active_now


	# 가게가 아직 오픈되지 않았으면
	# 출퇴근 판정 이후 업무만 막음
	if not day_manager.shop_open:
		return


	# 비근무 직원은 업무 금지
	if not on_duty:
		return

	if shift_ending:
		return

	if state != WorkerState.IDLE:
		return


	# =========================
	# 1순위: 계산
	# =========================
	if can_checkout:
		var register = find_waiting_register()

		if register != null:
			if do_checkout(register):
				return


	# =========================
	# 2순위: 진열
	# =========================
	if can_restock:
		if try_restock_shelf():
			return


	# 업무 없음
	try_go_to_standby()


func find_waiting_register():
	var registers: Array = (
		get_tree().get_nodes_in_group(
			"register"
		)
	)

	for register in registers:
		if not register.has_method(
			"has_waiting_customer"
		):
			continue

		if not register.has_waiting_customer():
			continue

		if register.has_method(
			"is_reserved_for_other"
		):
			if register.is_reserved_for_other(
				self
			):
				continue

		return register

	return null


func do_checkout(register) -> bool:
	if state != WorkerState.IDLE:
		return false

	if not is_instance_valid(register):
		return false

	if not register.has_method(
		"try_reserve_worker"
	):
		return false

	if not register.try_reserve_worker(self):
		return false

	pending_register = register
	pending_shelf = null

	var cashier_cell: Vector2i = (
		find_best_cashier_cell(
			register
		)
	)

	if cashier_cell == Vector2i(-1, -1):
		print(
			"[직원] 계산대 작업 위치로 갈 수 없음"
		)

		register.release_worker_reservation(
			self
		)

		pending_register = null
		return false

	# 다른 계산대에서 대기 중이었다면 자리 해제
	if (
		is_instance_valid(standby_register)
		and standby_register != register
	):
		standby_register.release_worker_cell(
			self
		)

	if not register.try_reserve_worker_cell(
		cashier_cell,
		self
	):
		register.release_worker_reservation(
			self
		)

		pending_register = null
		return false

	standby_register = register
	reserved_worker_cell = cashier_cell

	state = WorkerState.GO_TO_REGISTER

	print("[직원] 계산대 예약 완료")
	print("[직원] 계산대로 이동")

	move_to_cell(
		cashier_cell
	)

	return true


func try_restock_shelf() -> bool:
	if state != WorkerState.IDLE:
		return false

	var shelves: Array = (
		get_tree().get_nodes_in_group(
			"shelf"
		)
	)

	for shelf in shelves:
		if not shelf.has_method(
			"needs_worker_restock"
		):
			continue

		if shelf.has_method(
			"is_reserved_for_other"
		):
			if shelf.is_reserved_for_other(
				self
			):
				continue

		if not shelf.needs_worker_restock(
			player
		):
			continue

		var shelf_cell: Vector2i = (
			find_best_shelf_cell(
				shelf
			)
		)

		if shelf_cell == Vector2i(-1, -1):
			continue

		if not shelf.has_method(
			"try_reserve_worker"
		):
			continue

		if not shelf.try_reserve_worker(self):
			continue
			

		# 계산대 대기 자리에서 떠남
		release_worker_position()

		pending_shelf = shelf
		pending_register = null

		state = WorkerState.GO_TO_SHELF

		print(
			"[직원] 진열대 예약 완료: ",
			shelf.name
		)

		print(
			"[직원] 진열대로 이동: ",
			shelf.name
		)

		move_to_cell(
			shelf_cell
		)

		return true

	return false


func _physics_process(_delta):
	if not moving:
		velocity = Vector2.ZERO
		return

	if grid_path_index >= grid_path.size():
		moving = false
		velocity = Vector2.ZERO

		arrive_at_work_target()
		return

	var target_cell: Vector2i = (
		grid_path[grid_path_index]
	)

	var target_local: Vector2 = (
		floor_node.grid_to_local(
			target_cell
		)
	)

	var target_world: Vector2 = (
		floor_node.to_global(
			target_local
		)
	)

	if global_position.distance_to(
		target_world
	) <= 4.0:
		global_position = target_world
		grid_path_index += 1
		return

	velocity = (
		target_world - global_position
	).normalized() * speed

	move_and_slide()


func get_current_grid_cell() -> Vector2i:
	return floor_node.local_to_grid(
		floor_node.to_local(
			global_position
		)
	)


func find_best_cashier_cell(
	register
) -> Vector2i:

	if not is_instance_valid(register):
		return Vector2i(-1, -1)

	if not register.has_method(
		"get_worker_cells"
	):
		return Vector2i(-1, -1)

	var current_cell: Vector2i = (
		get_current_grid_cell()
	)

	var best_cell := Vector2i(-1, -1)
	var best_path_size: int = 999999

	for cell in register.get_worker_cells():
		if not floor_node.is_cell_inside(cell):
			continue

		if build_manager.is_cell_blocked_for_customer(
			cell
		):
			continue

		if register.has_method(
			"is_worker_cell_available"
		):
			if not register.is_worker_cell_available(
				cell,
				self
			):
				continue

		var path: Array[Vector2i] = (
			create_grid_path(
				current_cell,
				cell
			)
		)

		if path.is_empty():
			continue

		if path.size() < best_path_size:
			best_path_size = path.size()
			best_cell = cell

	return best_cell

func find_best_standby_position() -> Dictionary:
	var registers: Array = (
		get_tree().get_nodes_in_group(
			"register"
		)
	)

	var current_cell: Vector2i = (
		get_current_grid_cell()
	)

	var best_register = null
	var best_cell := Vector2i(-1, -1)
	var best_path_size: int = 999999

	for register in registers:
		if not is_instance_valid(register):
			continue

		if not register.has_method(
			"get_worker_cells"
		):
			continue

		if not register.has_method(
			"is_worker_cell_available"
		):
			continue

		for cell in register.get_worker_cells():
			if not floor_node.is_cell_inside(cell):
				continue

			if build_manager.is_cell_blocked_for_customer(
				cell
			):
				continue

			if not register.is_worker_cell_available(
				cell,
				self
			):
				continue

			var path: Array[Vector2i] = (
				create_grid_path(
					current_cell,
					cell
				)
			)

			if path.is_empty():
				continue

			if path.size() < best_path_size:
				best_path_size = path.size()
				best_register = register
				best_cell = cell

	return {
		"register": best_register,
		"cell": best_cell
	}

func release_worker_position():
	if is_instance_valid(
		standby_register
	):
		if standby_register.has_method(
			"release_worker_cell"
		):
			standby_register.release_worker_cell(
				self
			)

	standby_register = null
	reserved_worker_cell = Vector2i(-1, -1)

func find_best_shelf_cell(
	shelf
) -> Vector2i:

	if not is_instance_valid(shelf):
		return Vector2i(-1, -1)

	if not shelf.has_method(
		"get_customer_access_cells"
	):
		print(
			"[직원] 진열대 접근칸 함수가 없음: ",
			shelf.name
		)

		return Vector2i(-1, -1)

	var current_cell: Vector2i = (
		get_current_grid_cell()
	)

	var best_cell := Vector2i(-1, -1)
	var best_path_size: int = 999999

	var access_cells = (
		shelf.get_customer_access_cells()
	)

	for cell in access_cells:
		if not floor_node.is_cell_inside(cell):
			continue

		if build_manager.is_cell_blocked_for_customer(
			cell
		):
			continue

		var path: Array[Vector2i] = (
			create_grid_path(
				current_cell,
				cell
			)
		)

		if path.is_empty():
			continue

		if path.size() < best_path_size:
			best_path_size = path.size()
			best_cell = cell

	return best_cell


func create_grid_path(
	from_cell: Vector2i,
	target_cell: Vector2i
) -> Array[Vector2i]:

	if not floor_node.is_cell_inside(
		from_cell
	):
		return []

	if not floor_node.is_cell_inside(
		target_cell
	):
		return []

	var astar := AStarGrid2D.new()

	astar.region = Rect2i(
		0,
		0,
		int(floor_node.columns),
		int(floor_node.rows)
	)

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

	for x in range(
		int(floor_node.columns)
	):
		for y in range(
			int(floor_node.rows)
		):
			var cell := Vector2i(x, y)

			if build_manager.is_cell_blocked_for_customer(
				cell
			):
				astar.set_point_solid(
					cell,
					true
				)

	astar.set_point_solid(
		from_cell,
		false
	)

	if astar.is_point_solid(
		target_cell
	):
		return []

	return astar.get_id_path(
		from_cell,
		target_cell
	)


func move_to_cell(
	target_cell: Vector2i
):
	var current_cell: Vector2i = (
		get_current_grid_cell()
	)

	grid_path = create_grid_path(
		current_cell,
		target_cell
	)

	grid_path_index = 0
	moving = not grid_path.is_empty()

	print(
		"[직원] 이동: ",
		current_cell,
		" → ",
		target_cell,
		" / 경로: ",
		grid_path
	)

	if moving:
		return

	print("[직원] 이동 경로 없음")

	release_register_reservation()
	release_shelf_reservation()

	pending_register = null
	pending_shelf = null

	state = WorkerState.IDLE


func arrive_at_work_target():
	match state:
		WorkerState.GO_TO_REGISTER:
			handle_register_arrival()

		WorkerState.GO_TO_SHELF:
			handle_shelf_arrival()

		WorkerState.GO_TO_STANDBY:
			print(
				"[직원] 계산대 대기 위치 도착"
			)

			state = WorkerState.IDLE

		WorkerState.GO_TO_EXIT:
			complete_clock_out()


func handle_register_arrival():
	if not is_instance_valid(
		pending_register
	):
		pending_register = null
		finish_current_work()
		return

	var customer = (
		pending_register
		.get_waiting_customer()
	)

	if customer == null:
		pending_register.finish_checkout()

		release_register_reservation()

		pending_register = null
		finish_current_work()
		return

	state = WorkerState.CHECKOUT

	print("[직원] 계산 시작")

	await get_tree().create_timer(
		checkout_time
	).timeout

	if is_instance_valid(customer):
		customer.complete_checkout_by_worker()

	if is_instance_valid(
		pending_register
	):
		pending_register.finish_checkout()

	release_register_reservation()

	print("[직원] 계산 완료")

	pending_register = null
	state = WorkerState.IDLE


func handle_shelf_arrival():
	if not is_instance_valid(
		pending_shelf
	):
		pending_shelf = null
		state = WorkerState.IDLE
		return

	state = WorkerState.RESTOCK

	print("[직원] 진열 시작")

	await get_tree().create_timer(
		restock_time
	).timeout

	if is_instance_valid(
		pending_shelf
	):
		var success: bool = (
			pending_shelf.worker_restock(
				player
			)
		)

		if success:
			print("[직원] 진열 완료")
		else:
			print("[직원] 진열 실패")

	release_shelf_reservation()

	pending_shelf = null
	finish_current_work()


func release_register_reservation():
	if not is_instance_valid(
		pending_register
	):
		return

	if pending_register.has_method(
		"release_worker_reservation"
	):
		pending_register.release_worker_reservation(
			self
		)


func release_shelf_reservation():
	if not is_instance_valid(
		pending_shelf
	):
		return

	if pending_shelf.has_method(
		"release_worker_reservation"
	):
		pending_shelf.release_worker_reservation(
			self
		)

func try_go_to_standby() -> bool:
	if state != WorkerState.IDLE:
		return false

	var result: Dictionary = (
		find_best_standby_position()
	)

	var target_register = result.get(
		"register",
		null
	)

	var target_cell: Vector2i = result.get(
		"cell",
		Vector2i(-1, -1)
	)

	if not is_instance_valid(
		target_register
	):
		return false

	if target_cell == Vector2i(-1, -1):
		return false

	# 이미 그 대기칸에 서 있음
	if (
		standby_register == target_register
		and reserved_worker_cell == target_cell
		and get_current_grid_cell() == target_cell
	):
		return false

	if not target_register.try_reserve_worker_cell(
		target_cell,
		self
	):
		return false

	# 새 자리를 확보한 다음 이전 자리 해제
	if (
		is_instance_valid(standby_register)
		and standby_register != target_register
	):
		standby_register.release_worker_cell(
			self
		)

	standby_register = target_register
	reserved_worker_cell = target_cell

	state = WorkerState.GO_TO_STANDBY

	print(
		"[직원] 계산대로 대기 이동: ",
		target_cell
	)

	move_to_cell(
		target_cell
	)

	return true

func is_hour_in_shift(hour: int) -> bool:
	# 같은 시간은 근무하지 않는 것으로 처리
	if work_start_hour == work_end_hour:
		return false

	# 일반 근무
	# 예: 09 → 17
	if work_start_hour < work_end_hour:
		return (
			hour >= work_start_hour
			and hour < work_end_hour
		)

	# 자정을 넘는 근무
	# 예: 21 → 09
	return (
		hour >= work_start_hour
		or hour < work_end_hour
	)

func _on_hour_changed(hour: int):
	print(
		"[시간 변경] ",
		name,
		" / ",
		hour,
		":00"
	)


func update_shift_state(hour: int):
	var should_work: bool = (
		is_hour_in_shift(hour)
	)

	# =========================
	# 출근
	# =========================
	if should_work:
		if on_duty:
			return

		on_duty = true
		shift_ending = false

		begin_shift()

		print(
			"[직원] 출근: ",
			name,
			" / ",
			hour,
			":00"
		)

		return


	# =========================
	# 퇴근
	# =========================
	if not on_duty:
		return

	on_duty = false

	print(
		"[직원] 퇴근 시간 도달: ",
		name,
		" / ",
		hour,
		":00"
	)

	request_shift_end()

func begin_shift():
	var door = find_entrance_door()

	if door == null:
		print(
			"[직원] 출근할 문을 찾지 못함: ",
			name
		)

		state = WorkerState.OFF_DUTY
		visible = false
		on_duty = false
		return

	# 이전 상태 초기화
	release_worker_position()

	grid_path.clear()
	grid_path_index = 0
	moving = false

	pending_register = null
	pending_shelf = null

	shift_ending = false
	on_duty = true

	# 문 위치에서 등장
	if door.has_method(
		"get_customer_target_position"
	):
		global_position = (
			door.get_customer_target_position()
		)
	else:
		global_position = door.global_position

	visible = true
	state = WorkerState.IDLE

	print(
		"[직원] 문에서 출근: ",
		name
	)

func find_exit_cell() -> Vector2i:
	var doors: Array = (
		get_tree().get_nodes_in_group(
			"door"
		)
	)

	var current_cell: Vector2i = (
		get_current_grid_cell()
	)

	var best_cell := Vector2i(-1, -1)
	var best_path_size: int = 999999

	for door in doors:
		if not is_instance_valid(door):
			continue

		# 건축 미리보기 문 제외
		if bool(
			door.get_meta(
				"is_build_preview",
				false
			)
		):
			continue

		# 실제 설치된 문의 논리 그리드 위치
		if not door.has_meta("anchor"):
			continue

		var door_cell: Vector2i = (
			door.get_meta("anchor")
		)

		if not floor_node.is_cell_inside(
			door_cell
		):
			continue

		var path: Array[Vector2i] = (
			create_grid_path(
				current_cell,
				door_cell
			)
		)

		if (
			path.is_empty()
			and current_cell != door_cell
		):
			continue

		var path_size: int = path.size()

		if current_cell == door_cell:
			path_size = 0

		if path_size < best_path_size:
			best_path_size = path_size
			best_cell = door_cell

	print(
		"[직원] 퇴근 출구 선택: ",
		best_cell
	)

	return best_cell

func start_go_to_exit():
	if state == WorkerState.GO_TO_EXIT:
		return

	if state == WorkerState.OFF_DUTY:
		return

	# 계산대 대기 자리 해제
	release_worker_position()

	var exit_cell: Vector2i = (
		find_exit_cell()
	)

	if exit_cell == Vector2i(-1, -1):
		print(
			"[직원] 퇴근할 문을 찾지 못함: ",
			name
		)
		return

	state = WorkerState.GO_TO_EXIT

	print(
		"[직원] 퇴근하러 이동: ",
		name,
		" → ",
		exit_cell
	)

	move_to_cell(
		exit_cell
	)

	# 경로 생성 실패 시
	if not moving:
		print(
			"[직원] 퇴근 경로 없음: ",
			name
		)

		complete_clock_out()

func complete_clock_out():
	release_worker_position()

	grid_path.clear()
	grid_path_index = 0

	moving = false
	velocity = Vector2.ZERO

	pending_register = null
	pending_shelf = null

	state = WorkerState.OFF_DUTY
	shift_ending = false

	visible = false

	print(
		"[직원] 퇴근 완료: ",
		name
	)

func finish_current_work():
	if shift_ending or not on_duty:
		start_go_to_exit()
		return

	state = WorkerState.IDLE

func request_shift_end():
	shift_ending = true

	print(
		"[직원] 퇴근 준비: ",
		name,
		" / state:",
		state
	)

	match state:
		WorkerState.IDLE:
			start_go_to_exit()

		WorkerState.GO_TO_STANDBY:
			moving = false
			grid_path.clear()
			grid_path_index = 0

			release_worker_position()

			state = WorkerState.IDLE
			start_go_to_exit()

		WorkerState.GO_TO_REGISTER:
			# 이미 맡은 계산은 마무리
			pass

		WorkerState.CHECKOUT:
			# 계산 완료 후 퇴근
			pass

		WorkerState.GO_TO_SHELF:
			# 이미 맡은 진열은 마무리
			pass

		WorkerState.RESTOCK:
			# 진열 완료 후 퇴근
			pass

		WorkerState.GO_TO_EXIT:
			pass

		WorkerState.OFF_DUTY:
			pass

func find_entrance_door():
	var doors: Array = (
		get_tree().get_nodes_in_group(
			"door"
		)
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

		return door

	return null

func _on_shop_opened():
	var current_hour: int = (
		day_manager.current_hour
	)

	# 현재 시간이 자기 근무시간인지 검사
	var should_work: bool = (
		is_hour_in_shift(
			current_hour
		)
	)

	shift_was_active = should_work

	if not should_work:
		on_duty = false
		state = WorkerState.OFF_DUTY
		visible = false
		return

	print(
		"[직원] 가게 오픈과 함께 출근: ",
		name,
		" / ",
		current_hour,
		":00"
	)

	begin_shift()
