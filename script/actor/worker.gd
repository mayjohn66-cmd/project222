extends CharacterBody2D

@onready var floor_node = $"../../Floor"
@onready var build_manager = $"../../BuildManager"
@onready var player = get_parent().get_node("Player")
@onready var day_manager = get_node_or_null("../../DayManager")
@onready var production_room = $"../../ProductionRoom"
# 직원 출퇴근 경로를 제공하는 매장 외부 노드
@onready var store_exterior: Node = (
	get_node_or_null(
		"../../StoreExterior"
	)
)

@export var employee_id: String = ""
@export var production_collect_time: float = 0.8

var employee_display_name: String = ""

var speed: float = 100.0
var checkout_time: float = 1.2
var restock_time: float = 0.8

var can_checkout: bool = true
var can_restock: bool = true

var work_start_hour: int = 9
var work_end_hour: int = 17

var preferred_period: String = ""
var is_hired: bool = false

var work_periods: Array[String] = []



@export var work_check_interval: float = 0.3
@export var start_cell: Vector2i = Vector2i(4, 4)
@export var customer_service_time: float = 0.8


const EXIT_PATH_SELECTOR_SCRIPT = preload(
	"res://script/actor/navigation/exit_path_selector.gd"
)

var exit_path_selector = (
	EXIT_PATH_SELECTOR_SCRIPT.new()
)

var on_duty: bool = false
var shift_ending: bool = false
var shift_was_active: bool = false


enum WorkerState {
	IDLE,
	GO_TO_REGISTER,
	CHECKOUT,
	GO_TO_CUSTOMER,
	CUSTOMER_SERVICE,
	GO_TO_PRODUCTION_DOOR,
	GO_TO_PRODUCTION_FACILITY,
	COLLECT_PRODUCTION,
	RETURN_TO_PRODUCTION_EXIT,
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
var pending_customer = null
var pending_shelf = null
var pending_facility: Node2D = null

var production_return_door: Node2D = null
var production_world_target: Vector2 = Vector2.ZERO

var standby_register = null
var reserved_worker_cell := Vector2i(-1, -1)
var work_check_elapsed: float = 0.0

# 출근 또는 퇴근 연출이 중복 실행되는 것을 방지한다.
var commute_animation_running: bool = false
# 내부 길찾기로 선택한 실제 퇴근 출입문
var clock_out_door: Node = null

#==========================================================

func _ready():
	if not _apply_employee_defaults():
		visible = false
		set_process(false)
		set_physics_process(false)
		return

	if not _restore_or_initialize_employee_state():
		visible = false
		set_process(false)
		set_physics_process(false)
		return

	add_to_group("worker")

	# 아래의 기존 위치 설정·DayManager 연결·비근무 초기화는 유지

	if day_manager == null:
		push_error( "[직원] DayManager를 찾지 못했습니다.")
		return

	if not day_manager.shop_opened.is_connected(
		_on_shop_opened
	):
		day_manager.shop_opened.connect(
			_on_shop_opened
		)

	# 게임 시작은 아직 오픈 준비 상태
	# 06시 근무자도 미리 출근시키지 않는다.
	shift_was_active = false
	on_duty = false
	shift_ending = false

	commute_animation_running = false
	clock_out_door = null

	state = WorkerState.OFF_DUTY
	visible = false

func _process(delta):
	if day_manager == null:
		return

	work_check_elapsed += delta

	if work_check_elapsed < work_check_interval:
		return

	# 가게가 아직 오픈되지 않았으면
	# 출퇴근 판정 이후 업무만 막음
	if not day_manager.shop_open:
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

	# =========================
	# 퇴근
	# =========================
	elif not active_now and shift_was_active:
		on_duty = false
		shift_ending = true

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


	# 1순위: 계산
	if can_checkout:
		var register = find_waiting_register()

		if register != null:
			if do_checkout(register):
				return

	# 2순위: 완성품 회수
	if try_collect_production_output():
		return

	# 3순위: 고객 응대
	if try_help_customer():
		return

	# 4순위: 진열
	if can_restock:
		if try_restock_shelf():
			return

	# 수행할 업무가 없으면 계산대 대기
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
		push_warning("[직원] 계산대 작업 위치로 갈 수 없음")

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

	move_to_cell(
		cashier_cell
	)

	return true


func can_accept_production_task() -> bool:
	if not is_hired:
		return false

	if not on_duty:
		return false

	if shift_ending:
		return false

	if not visible:
		return false

	if state != WorkerState.IDLE:
		return false

	if not is_instance_valid(day_manager):
		return false

	if not day_manager.shop_open:
		return false

	if not is_hour_in_shift(
		day_manager.current_hour
	):
		return false

	return true


func try_collect_production_output() -> bool:
	if not can_accept_production_task():
		return false

	if not is_instance_valid(production_room):
		return false

	# 설비를 예약하기 전에 먼저 접근 가능한 문을 찾음
	var door_result: Dictionary = (
		find_best_production_door()
	)

	var door: Node2D = door_result.get(
		"door",
		null
	)

	var door_cell: Vector2i = door_result.get(
		"cell",
		Vector2i(-1, -1)
	)

	if (
		not is_instance_valid(door)
		or door_cell == Vector2i(-1, -1)
	):
		return false

	var facilities: Array = (
		get_tree().get_nodes_in_group(
			"production_facility"
		)
	)

	for facility_node in facilities:
		if not is_instance_valid(facility_node):
			continue

		if facility_node.is_queued_for_deletion():
			continue

		if not facility_node is Node2D:
			continue

		if not facility_node.has_method(
			"has_collectable_output"
		):
			continue

		if not facility_node.has_collectable_output():
			continue

		if not facility_node.has_method(
			"try_reserve_collector"
		):
			continue

		if not facility_node.try_reserve_collector(
			self
		):
			continue

		release_worker_position()

		pending_facility = facility_node as Node2D
		production_return_door = door

		pending_register = null
		pending_customer = null
		pending_shelf = null

		state = WorkerState.GO_TO_PRODUCTION_DOOR

		move_to_cell(door_cell)

		if state != WorkerState.GO_TO_PRODUCTION_DOOR:
			release_production_reservation()
			pending_facility = null
			production_return_door = null
			return false

		return true

	return false


func get_worker_production_door_candidates() -> Array[Node2D]:
	var result: Array[Node2D] = []
	var checked: Dictionary = {}

	for node in get_tree().get_nodes_in_group(
		"production_door"
	):
		if not is_instance_valid(node):
			continue

		if not node is Node2D:
			continue

		var instance_id: int = node.get_instance_id()

		if checked.has(instance_id):
			continue

		checked[instance_id] = true
		result.append(node as Node2D)

	var objects_node: Node = get_node_or_null(
		"../../Objects"
	)

	if objects_node == null:
		return result

	for node in objects_node.get_children():
		if not is_instance_valid(node):
			continue

		if not node is Node2D:
			continue

		if node.is_queued_for_deletion():
			continue

		if bool(
			node.get_meta(
				"is_build_preview",
				false
			)
		):
			continue

		var build_id: String = str(
			node.get_meta(
				"build_id",
				""
			)
		)

		if build_id.is_empty():
			continue

		if (
			BuildObjectData.get_build_type(build_id)
			!= BuildObjectData.BUILD_TYPE_PRODUCTION_DOOR
		):
			continue

		var instance_id: int = node.get_instance_id()

		if checked.has(instance_id):
			continue

		checked[instance_id] = true
		result.append(node as Node2D)

	return result


func find_best_production_door() -> Dictionary:
	var current_cell: Vector2i = (
		get_current_grid_cell()
	)

	var best_door: Node2D = null
	var best_cell := Vector2i(-1, -1)
	var best_path_size: int = 2147483647

	var doors: Array[Node2D] = (
		get_worker_production_door_candidates()
	)

	for door in doors:
		if not is_instance_valid(door):
			continue

		if door.is_queued_for_deletion():
			continue

		var door_cell: Vector2i = door.get_meta(
			"anchor",
			Vector2i(-1, -1)
		)

		if door.has_method("get_return_cell"):
			door_cell = door.get_return_cell()

		if not floor_node.is_store_cell(door_cell):
			continue

		var candidates: Array[Vector2i] = [
			door_cell,
			door_cell + Vector2i(1, 0),
			door_cell + Vector2i(-1, 0),
			door_cell + Vector2i(0, 1),
			door_cell + Vector2i(0, -1)
		]

		for candidate in candidates:
			if not floor_node.is_store_cell(candidate):
				continue

			if (
				candidate != door_cell
				and build_manager.is_cell_blocked_for_customer(
					candidate
				)
			):
				continue

			if candidate == current_cell:
				return {
					"door": door,
					"cell": candidate
				}

			var path: Array[Vector2i] = (
				create_grid_path(
					current_cell,
					candidate
				)
			)

			if path.is_empty():
				continue

			if path.size() < best_path_size:
				best_path_size = path.size()
				best_door = door
				best_cell = candidate

	return {
		"door": best_door,
		"cell": best_cell
	}


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

		move_to_cell(
			shelf_cell
		)

		return true

	return false


func _physics_process(_delta):
	if _is_production_room_move_state():
		_process_production_room_movement()
		return

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
	).normalized() * get_effective_move_speed()

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
		push_error(
			"[직원] 진열대 접근칸 함수가 없음: "
			+ shelf.name
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

	if moving:
		return

	push_warning(
		"[직원] 이동 경로를 찾지 못했습니다: "
		+ str(current_cell)
		+ " → "
		+ str(target_cell)
)

	release_register_reservation()
	release_customer_service_reservation()
	release_production_reservation()
	release_shelf_reservation()

	pending_register = null
	pending_customer = null
	pending_facility = null
	pending_shelf = null

	production_return_door = null
	production_world_target = Vector2.ZERO

	state = WorkerState.IDLE


func arrive_at_work_target():
	match state:
		WorkerState.GO_TO_REGISTER:
			handle_register_arrival()

		WorkerState.GO_TO_CUSTOMER:
			handle_customer_service_arrival()

		WorkerState.GO_TO_PRODUCTION_DOOR:
			enter_production_room_for_work()

		WorkerState.GO_TO_SHELF:
			handle_shelf_arrival()

		WorkerState.GO_TO_STANDBY:
			state = WorkerState.IDLE

		WorkerState.GO_TO_EXIT:
			start_clock_out_commute()

func handle_customer_service_arrival() -> void:
	if not is_instance_valid(
		pending_customer
	):
		pending_customer = null
		finish_current_work()
		return

	state = WorkerState.CUSTOMER_SERVICE
	velocity = Vector2.ZERO

	await get_tree().create_timer(
		customer_service_time,
		false
	).timeout

	if not is_instance_valid(
		pending_customer
	):
		pending_customer = null
		finish_current_work()
		return

	if pending_customer.has_method(
		"complete_employee_service"
	):
			pending_customer.complete_employee_service(
				self,
				get_customer_service_chance()
			)

	pending_customer = null
	finish_current_work()

func release_customer_service_reservation() -> void:
	if not is_instance_valid(
		pending_customer
	):
		return

	if pending_customer.has_method(
		"cancel_employee_service"
	):
		pending_customer.cancel_employee_service(
			self
		)

func handle_register_arrival():
	if not is_instance_valid(
		pending_register
	):
		pending_register = null
		finish_current_work()
		return

	var customer = (
		pending_register.get_waiting_customer()
	)

	if customer == null:
		pending_register.finish_checkout()
		release_register_reservation()

		pending_register = null
		finish_current_work()
		return

	state = WorkerState.CHECKOUT

	var duration: float = (
		get_effective_checkout_time()
	)

	# 계산 시간은 한 번만 적용
	await get_tree().create_timer(
		duration,
		false
	).timeout

	if is_instance_valid(customer):
		customer.complete_checkout_by_worker()

	if is_instance_valid(pending_register):
		pending_register.finish_checkout()

	release_register_reservation()

	pending_register = null
	finish_current_work()


func handle_shelf_arrival():
	if not is_instance_valid(pending_shelf):
		pending_shelf = null
		finish_current_work()
		return

	state = WorkerState.RESTOCK

	var duration: float = (
		get_effective_restock_time()
	)

	# 진열 시간은 한 번만 적용
	await get_tree().create_timer(
		duration,
		false
	).timeout

	if is_instance_valid(pending_shelf):
		pending_shelf.worker_restock(
			player
		)

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

	move_to_cell(
		target_cell
	)

	return true

func is_hour_in_shift(hour: int) -> bool:
	if not is_hired:
		return false

	var period: String = EmployeeData.get_period_at_hour(hour)

	return work_periods.has(period)


func begin_shift() -> void:
	if commute_animation_running:
		return

	var door = find_entrance_door()

	if door == null:
		push_warning(
			"[직원] 출근할 문을 찾지 못했습니다: "
			+ name
		)

		state = WorkerState.OFF_DUTY
		visible = false
		on_duty = false
		return

	# 이전 업무와 이동 상태를 초기화한다.
	release_worker_position()

	grid_path.clear()
	grid_path_index = 0
	moving = false
	velocity = Vector2.ZERO

	pending_register = null
	pending_customer = null
	pending_shelf = null

	shift_ending = false
	on_duty = false
	state = WorkerState.OFF_DUTY

	# 외부 경로를 사용할 수 없는 경우에는
	# 기존 방식대로 문 안쪽에서 출근시킨다.
	if (
		not is_instance_valid(store_exterior)
		or not store_exterior.has_method(
			"get_random_sidewalk_route_for_door"
		)
	):
		_finish_worker_arrival(
			door
		)
		return

	var sidewalk_route: Dictionary = (
		store_exterior.call(
			"get_random_sidewalk_route_for_door",
			door
		)
	)

	if sidewalk_route.is_empty():
		_finish_worker_arrival(
			door
		)
		return

	var start_position: Vector2 = (
		sidewalk_route.get(
			"start_position",
			Vector2.ZERO
		)
	)

	# 직원은 도로 끝(화면에 보이면 화면 밖까지 물러난 지점)에서 걸어 들어온다.
	var gate_start: Vector2 = CustomerGates.gate_position(
		store_exterior,
		sidewalk_route.get("start_cell", Vector2i.ZERO)
	)
	if gate_start != start_position:
		var lead_in: Array = [start_position]
		lead_in.append_array(sidewalk_route.get("approach_positions", []))
		sidewalk_route["approach_positions"] = lead_in
		start_position = gate_start
	global_position = start_position
	modulate.a = 1.0
	CustomerGates.fade_in(self)
	visible = true
	commute_animation_running = true

	await get_tree().physics_frame

	if not is_instance_valid(self):
		return

	# 도로 끝에서 편의점 앞 보도까지 이동한다.
	var reached_sidewalk: bool = await (
		_move_worker_along_points(
			sidewalk_route.get(
				"approach_positions",
				[]
			)
		)
	)

	if not reached_sidewalk:
		commute_animation_running = false
		return

	if shift_ending:
		commute_animation_running = false
		complete_clock_out()
		return

	var outside_door_position: Vector2 = (
		door.call(
			"get_customer_spawn_position"
		)
	)

	var inside_door_position: Vector2 = (
		door.call(
			"get_customer_target_position"
		)
	)

	# 보도에서 문 바깥까지 이동한다.
	var reached_door: bool = await (
		_move_worker_along_points(
			[
				outside_door_position
			]
		)
	)

	if not reached_door:
		commute_animation_running = false
		return

	if shift_ending:
		commute_animation_running = false
		complete_clock_out()
		return

	# 문을 통과해 매장 내부로 들어간다.
	var entrance_tween: Tween = (
		create_tween()
	)

	entrance_tween.set_trans(
		Tween.TRANS_LINEAR
	)

	entrance_tween.tween_property(
		self,
		"global_position",
		inside_door_position,
		0.45
	)

	await entrance_tween.finished

	if not is_instance_valid(self):
		return

	if shift_ending:
		commute_animation_running = false
		complete_clock_out()
		return

	# 매장에 들어온 다음부터 실제 업무를 시작한다.
	commute_animation_running = false
	on_duty = true
	state = WorkerState.IDLE

	DebugLog.write(
		"[직원] 출근 완료: ",
		employee_display_name
	)

# 외부 출근 경로를 사용할 수 없을 때 적용하는
# 기존 방식의 즉시 출근 처리다.
func _finish_worker_arrival(
	door: Node
) -> void:
	if door.has_method(
		"get_customer_target_position"
	):
		global_position = (
			door.call(
				"get_customer_target_position"
			)
		)
	else:
		global_position = (
			door.global_position
		)

	commute_animation_running = false
	visible = true
	on_duty = true
	state = WorkerState.IDLE


# 직원을 여러 경유점을 따라 순차적으로 이동시킨다.
func _move_worker_along_points(
	points: Array
) -> bool:
	var move_speed: float = maxf(
		speed,
		1.0
	)

	for point_value in points:
		if not is_instance_valid(self):
			return false

		if not point_value is Vector2:
			continue

		var target_position: Vector2 = (
			point_value
		)

		var distance: float = (
			global_position.distance_to(
				target_position
			)
		)

		var duration: float = clampf(
			distance / move_speed,
			0.05,
			3.0
		)

		var move_tween: Tween = (
			create_tween()
		)

		move_tween.set_trans(
			Tween.TRANS_LINEAR
		)

		move_tween.tween_property(
			self,
			"global_position",
			target_position,
			duration
		)

		await move_tween.finished

	return is_instance_valid(self)

# 설치가 완료된 일반 매장 출입문만 반환한다.
# 생산실 문과 건축 미리보기 문은 제외한다.
func get_store_entrance_doors() -> Array[Node]:
	var result: Array[Node] = []

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

		# 생산실 문 그룹은 직원 출퇴근에 사용하지 않는다.
		if door.is_in_group(
			"production_door"
		):
			continue

		var build_id: String = str(
			door.get_meta(
				"build_id",
				""
			)
		)

		if build_id == "production_door":
			continue

		if not door.has_meta("anchor"):
			continue

		if not door.has_method(
			"get_customer_spawn_position"
		):
			continue

		if not door.has_method(
			"get_customer_target_position"
		):
			continue

		result.append(
			door
		)

	return result

func find_exit_cell() -> Vector2i:
	var entrance_doors: Array[Node] = (
		get_store_entrance_doors()
	)

	if entrance_doors.is_empty():
		return Vector2i(-1, -1)

	var exit_cell: Vector2i = (
		exit_path_selector.find_exit_cell(
			entrance_doors,
			get_current_grid_cell(),
			floor_node,
			Callable(
				build_manager,
				"is_cell_blocked_for_customer"
			),
			Callable(
				self,
				"create_grid_path"
			)
		)
	)

	return exit_cell

func start_go_to_exit() -> void:
	if state == WorkerState.GO_TO_EXIT:
		return

	if state == WorkerState.OFF_DUTY:
		return

	if commute_animation_running:
		return

	# 계산대 등의 직원 전용 위치를 해제한다.
	release_worker_position()

	var exit_cell: Vector2i = (
		find_exit_cell()
	)

	if exit_cell == Vector2i(-1, -1):
		push_warning(
			"[직원] 출구까지 이동 가능한 경로가 없습니다: "
			+ name
		)
		return

	# 내부 길찾기가 선택한 셀에 설치된 문을 기억한다.
	clock_out_door = (
		_find_door_at_cell(
			exit_cell
		)
	)

	state = WorkerState.GO_TO_EXIT

	move_to_cell(
		exit_cell
	)

	# 이미 출구 셀에 있거나 길찾기 경로가 필요 없는 경우
	if not moving:
		start_clock_out_commute()

# 내부 길찾기가 선택한 출구 셀에 설치된 문을 찾는다.
func _find_door_at_cell(
	exit_cell: Vector2i
) -> Node:
	var doors: Array[Node] = (
		get_store_entrance_doors()
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

		if not door.has_meta("anchor"):
			continue

		var door_cell: Vector2i = (
			door.get_meta(
				"anchor",
				Vector2i(-1, -1)
			)
		)

		if door_cell != exit_cell:
			continue

		if not door.has_method(
			"get_customer_spawn_position"
		):
			continue

		if not door.has_method(
			"get_customer_target_position"
		):
			continue

		return door

	return null

# 문에 도착한 직원을 보도를 통해 도로 끝까지 퇴근시킨다.
func start_clock_out_commute() -> void:
	if commute_animation_running:
		return

	var door: Node = clock_out_door

	# 내부 길찾기에서 문을 기억하지 못했다면
	# 사용 가능한 출입문을 다시 찾는다.
	if not is_instance_valid(door):
		door = find_entrance_door()

	if not is_instance_valid(door):
		complete_clock_out()
		return

	if (
		not is_instance_valid(store_exterior)
		or not store_exterior.has_method(
			"get_random_sidewalk_route_for_door"
		)
	):
		complete_clock_out()
		return

	var sidewalk_route: Dictionary = (
		store_exterior.call(
			"get_random_sidewalk_route_for_door",
			door
		)
	)

	if sidewalk_route.is_empty():
		complete_clock_out()
		return

	commute_animation_running = true
	moving = false
	velocity = Vector2.ZERO

	var outside_door_position: Vector2 = (
		door.call(
			"get_customer_spawn_position"
		)
	)

	var decision_position: Vector2 = (
		sidewalk_route.get(
			"decision_position",
			outside_door_position
		)
	)

	# 매장 안쪽에서 문 바깥으로 나온다.
	var left_store: bool = await (
		_move_worker_along_points(
			[
				outside_door_position
			]
		)
	)

	if not left_store:
		commute_animation_running = false
		complete_clock_out()
		return

	# 문 바깥에서 보도까지 이동한다.
	var reached_sidewalk: bool = await (
		_move_worker_along_points(
			[
				decision_position
			]
		)
	)

	if not reached_sidewalk:
		commute_animation_running = false
		complete_clock_out()
		return

	# 보도를 따라 양쪽 도로 끝 중 한 곳으로 퇴근한다.
	await _move_worker_along_points(
		sidewalk_route.get(
			"pass_positions",
			[]
		)
	)

	if not is_instance_valid(self):
		return

	# 도로 끝이 화면 안이면 화면 밖 게이트까지 더 걸어가며 사라진다.
	var gate_finish: Vector2 = CustomerGates.gate_position(
		store_exterior,
		sidewalk_route.get("finish_cell", Vector2i.ZERO)
	)
	if gate_finish != global_position:
		CustomerGates.fade_out(self)
		await _move_worker_along_points([gate_finish])
		if not is_instance_valid(self):
			return

	commute_animation_running = false

	DebugLog.write(
		"[직원] 퇴근 완료: ",
		employee_display_name
	)

	complete_clock_out()

# 퇴근 이동이 끝난 뒤 직원 상태를 완전히 초기화한다.
# 직원 노드는 삭제하지 않고 숨겨서 다음 근무 때 다시 사용한다.
func complete_clock_out() -> void:
	release_register_reservation()
	release_customer_service_reservation()
	release_production_reservation()
	release_shelf_reservation()
	release_worker_position()

	grid_path.clear()
	grid_path_index = 0

	moving = false
	velocity = Vector2.ZERO

	pending_register = null
	pending_customer = null
	pending_facility = null
	pending_shelf = null

	production_return_door = null
	production_world_target = Vector2.ZERO

	on_duty = false
	shift_ending = false
	shift_was_active = false

	commute_animation_running = false
	clock_out_door = null

	state = WorkerState.OFF_DUTY
	visible = false
	modulate.a = 1.0

func finish_current_work():
	if shift_ending or not on_duty:
		start_go_to_exit()
		return

	state = WorkerState.IDLE

func request_shift_end():
	on_duty = false
	shift_ending = true

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

		WorkerState.GO_TO_CUSTOMER:
			# 맡은 고객 응대를 마친 뒤 퇴근
			pass

		WorkerState.CUSTOMER_SERVICE:
			# 추천 결과 처리 후 퇴근
			pass

		WorkerState.GO_TO_PRODUCTION_DOOR:
			# 회수를 마치고 복귀한 뒤 퇴근
			pass

		WorkerState.GO_TO_PRODUCTION_FACILITY:
			pass

		WorkerState.COLLECT_PRODUCTION:
			pass

		WorkerState.RETURN_TO_PRODUCTION_EXIT:
			pass

		WorkerState.GO_TO_EXIT:
			pass

		WorkerState.OFF_DUTY:
			pass

func find_entrance_door() -> Node:
	var doors: Array[Node] = (
		get_store_entrance_doors()
	)

	if doors.is_empty():
		return null

	# 출입문이 여러 개라면 한쪽에만 몰리지 않도록
	# 사용할 문을 무작위로 선택한다.
	return doors.pick_random()

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

	begin_shift()

func _apply_employee_defaults() -> bool:
	var data: Dictionary = EmployeeData.get_employee(
		employee_id
	)

	if data.is_empty():
		push_error(
			"[직원] 등록되지 않은 employee_id: "
			+ employee_id
		)
		return false

	employee_display_name = str(data["display_name"])

	speed = float(data["speed"])
	checkout_time = float(data["checkout_time"])
	restock_time = float(data["restock_time"])

	can_checkout = bool(data["can_checkout"])
	can_restock = bool(data["can_restock"])

	work_periods.clear()

	for period in data["default_work_periods"]:
		work_periods.append(str(period))


	preferred_period = str(data["preferred_period"])
	is_hired = bool(data["initially_hired"])

	return true


func get_work_speed_multiplier() -> float:
	if not is_instance_valid(day_manager):
		return 1.0

	if str(day_manager.get_period()) == preferred_period:
		return EmployeeData.PREFERRED_WORK_SPEED_MULTIPLIER

	return 1.0


func get_effective_checkout_time() -> float:
	return checkout_time / (
		get_training_value("checkout")
		* get_work_speed_multiplier()
	)


func get_effective_restock_time() -> float:
	return restock_time / (
		get_training_value("restock")
		* get_work_speed_multiplier()
	)


func get_preferred_period_text() -> String:
	var bonus_percent: int = roundi(
		(
			EmployeeData.PREFERRED_WORK_SPEED_MULTIPLIER
			- 1.0
		) * 100.0
	)

	return "%s 계산·진열 속도 +%d%%" % [
		EmployeeData.get_period_name(preferred_period),
		bonus_percent
	]

func can_change_employment() -> bool:
	if not is_instance_valid(day_manager):
		return false

	return (
		day_manager.current_hour == GameConfig.DAY_START_HOUR
		and not day_manager.shop_open
		and not day_manager.summary_open
		and not day_manager.closing_shop
		and not on_duty
		and not shift_ending
		and not moving
		and state == WorkerState.OFF_DUTY
	)


func can_edit_work_schedule() -> bool:
	return is_hired and can_change_employment()


func get_hire_cost() -> int:
	var data: Dictionary = EmployeeData.get_employee(employee_id)
	return int(data.get("hire_cost", 0))


func hire_employee() -> bool:
	if not EmployeeRecruitmentFlow.met(employee_id): return false
	if is_hired or not can_change_employment():
		return false

	var data: Dictionary = EmployeeData.get_employee(employee_id)

	if data.is_empty():
		return false

	var cost: int = int(data.get("hire_cost", 0))

	if cost < 0 or not GameState.can_afford(cost):
		return false

	# 무료 고용이면 소지금 차감 생략
	if cost > 0:
		if not GameState.spend_money(cost):
			return false

	var empty_periods: Array[String] = []

	if not GameState.set_employee_state(
		employee_id,
		true,
		empty_periods
	):
		if cost > 0:
			GameState.add_money(cost)
		return false

	is_hired = true
	work_periods.clear()
	shift_was_active = false
	return true


func dismiss_employee() -> bool:
	if not is_hired or not can_change_employment():
		return false

	var empty_periods: Array[String] = []

	if not GameState.set_employee_state(
		employee_id,
		false,
		empty_periods
	):
		return false

	is_hired = false
	work_periods.clear()
	shift_was_active = false
	return true

func get_employee_display_name() -> String:
	if employee_display_name.is_empty():
		return str(name)

	return employee_display_name


func get_work_periods() -> Array[String]:
	return work_periods.duplicate()


func set_work_periods(periods: Array[String]) -> bool:
	if not can_edit_work_schedule():
		return false

	if not EmployeeData.is_work_periods_valid(periods):
		return false

	# GameState 기록이 성공한 뒤 실제 직원에게 적용
	if not GameState.set_employee_state(
		employee_id,
		is_hired,
		periods
	):
		return false

	work_periods = periods.duplicate()
	shift_was_active = false

	return true

func _restore_or_initialize_employee_state() -> bool:
	var saved: Dictionary = GameState.get_employee_state(
		employee_id
	)

	if saved.is_empty():
		return GameState.set_employee_state(
			employee_id,
			is_hired,
			work_periods
		)

	if not GameState.is_employee_state_valid(saved):
		push_error(
			"[직원] 저장된 직원 정보가 잘못되었습니다: "
			+ employee_id
		)
		return false

	var restored_periods: Array[String] = []

	for period in saved["work_periods"]:
		restored_periods.append(str(period))

	var restored_hired: bool = bool(saved["is_hired"])

	# 기존 교육 기록 보존, 없는 경우 0레벨 추가
	if not GameState.set_employee_state(
		employee_id,
		restored_hired,
		restored_periods
	):
		return false

	is_hired = restored_hired
	work_periods = restored_periods

	return true

func get_training_level(stat_id: String) -> int:
	var data: Dictionary = GameState.get_employee_state(
		employee_id
	)

	var levels: Dictionary = data.get(
		"training_levels",
		{}
	)

	return int(levels.get(stat_id, 0))


func get_training_value(stat_id: String) -> float:
	var data: Dictionary = EmployeeTrainingData.get_level_data(
		stat_id,
		get_training_level(stat_id)
	)

	if data.is_empty():
		return 0.0 if stat_id == "service" else 1.0

	return float(data["value"])


func get_effective_move_speed() -> float:
	return speed * get_training_value("movement")


func get_customer_service_chance() -> float:
	return get_training_value("service")


func train_stat(stat_id: String) -> bool:
	if not EmployeeRecruitmentFlow.training_available(employee_id): return false
	# 고용된 비근무 직원, 아침 6시 오픈 준비 중에만 교육
	if not can_edit_work_schedule():
		return false

	return GameState.upgrade_employee_training(
		employee_id,
		stat_id
	)

func try_help_customer() -> bool:
	if state != WorkerState.IDLE:
		return false

	var customers: Array = (
		get_tree().get_nodes_in_group("customer")
	)

	for customer in customers:
		if not is_instance_valid(customer):
			continue

		if customer.is_queued_for_deletion():
			continue

		if not customer.has_method(
			"needs_employee_service"
		):
			continue

		if not customer.needs_employee_service():
			continue

		if not customer.has_method(
			"try_reserve_employee_service"
		):
			continue

		# 고객을 먼저 예약하여 다른 직원의 접근을 막음
		if not customer.try_reserve_employee_service(
			self
		):
			continue

		var service_cell: Vector2i = (
			find_best_customer_service_cell(
				customer
			)
		)

		if service_cell == Vector2i(-1, -1):
			if customer.has_method(
				"cancel_employee_service"
			):
				customer.cancel_employee_service(
					self
				)

			continue

		# 계산대 대기 위치에서 떠남
		release_worker_position()

		pending_customer = customer
		pending_register = null
		pending_shelf = null

		state = WorkerState.GO_TO_CUSTOMER

		move_to_cell(service_cell)

		if state != WorkerState.GO_TO_CUSTOMER:
			return false

		return true

	return false


func find_best_customer_service_cell(
	customer: Node
) -> Vector2i:
	if not is_instance_valid(customer):
		return Vector2i(-1, -1)

	if not customer.has_method(
		"get_current_grid_cell"
	):
		return Vector2i(-1, -1)

	var customer_cell: Vector2i = (
		customer.get_current_grid_cell()
	)

	var current_cell: Vector2i = (
		get_current_grid_cell()
	)

	var directions: Array[Vector2i] = [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1)
	]

	var best_cell := Vector2i(-1, -1)
	var best_path_size: int = 2147483647

	for direction in directions:
		var candidate: Vector2i = (
			customer_cell + direction
		)

		if not floor_node.is_cell_inside(
			candidate
		):
			continue

		if build_manager.is_cell_blocked_for_customer(
			candidate
		):
			continue

		if candidate == current_cell:
			return candidate

		var path: Array[Vector2i] = (
			create_grid_path(
				current_cell,
				candidate
			)
		)

		if path.is_empty():
			continue

		if path.size() < best_path_size:
			best_path_size = path.size()
			best_cell = candidate

	return best_cell

func _is_production_room_move_state() -> bool:
	return (
		state
		== WorkerState.GO_TO_PRODUCTION_FACILITY
		or state
		== WorkerState.RETURN_TO_PRODUCTION_EXIT
	)


func _process_production_room_movement() -> void:
	var distance: float = global_position.distance_to(
		production_world_target
	)

	if distance <= 4.0:
		global_position = production_world_target
		velocity = Vector2.ZERO

		if state == WorkerState.GO_TO_PRODUCTION_FACILITY:
			handle_production_facility_arrival()
		else:
			handle_production_exit_arrival()

		return

	velocity = (
		production_world_target
		- global_position
	).normalized() * get_effective_move_speed()

	move_and_slide()

func enter_production_room_for_work() -> void:
	moving = false
	velocity = Vector2.ZERO
	grid_path.clear()
	grid_path_index = 0

	if not is_instance_valid(production_room):
		cancel_production_work()
		return

	if not is_instance_valid(pending_facility):
		cancel_production_work()
		return

	if not production_room.enter_actor(self):
		cancel_production_work()
		return

	production_world_target = (
		production_room.get_facility_approach_position(
			pending_facility
		)
	)

	state = WorkerState.GO_TO_PRODUCTION_FACILITY


func handle_production_facility_arrival() -> void:
	state = WorkerState.COLLECT_PRODUCTION
	velocity = Vector2.ZERO

	await get_tree().create_timer(
		production_collect_time,
		false
	).timeout

	var success: bool = false

	if is_instance_valid(pending_facility):
		if pending_facility.has_method(
			"collect_output_by_worker"
		):
			success = bool(
				pending_facility.collect_output_by_worker(
					self
				)
			)

	if not success:
		push_warning(
			"[직원 생산] 완성품 회수 실패 / 직원: "
			+ get_employee_display_name()
		)

	if is_instance_valid(pending_facility):
		if pending_facility.has_method(
			"release_collector"
		):
			pending_facility.release_collector(self)

	pending_facility = null

	if not is_instance_valid(production_room):
		cancel_production_work()
		return

	production_world_target = (
		production_room.get_entry_world_position()
	)

	state = WorkerState.RETURN_TO_PRODUCTION_EXIT


func handle_production_exit_arrival() -> void:
	velocity = Vector2.ZERO

	if not is_instance_valid(production_room):
		cancel_production_work()
		return

	if not is_instance_valid(production_return_door):
		cancel_production_work()
		return

	var exited: bool = production_room.exit_actor(
		self,
		production_return_door
	)

	if not exited:
		cancel_production_work()
		return

	production_return_door = null
	production_world_target = Vector2.ZERO

	finish_current_work()

func release_production_reservation() -> void:
	if not is_instance_valid(pending_facility):
		return

	if pending_facility.has_method(
		"release_collector"
	):
		pending_facility.release_collector(
			self
		)


func cancel_production_work() -> void:
	release_production_reservation()

	pending_facility = null
	production_return_door = null
	production_world_target = Vector2.ZERO

	moving = false
	velocity = Vector2.ZERO
	grid_path.clear()
	grid_path_index = 0

	finish_current_work()
