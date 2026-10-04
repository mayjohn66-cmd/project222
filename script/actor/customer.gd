extends CharacterBody2D


@export var speed: float = 100.0
@export var shelf_pick_delay: float = 0.8
@export var wander_min_moves: int = 2
@export var wander_max_moves: int = 4
@export var wander_pause_delay: float = 0.7
@export var checkout_finish_delay: float = 0.4
@export var move_timeout: float = 4.0
@export var max_move_retries: int = 2
@export var show_movement_debug: bool = false


const EXIT_PATH_SELECTOR_SCRIPT = preload(
	"res://script/actor/navigation/exit_path_selector.gd"
)

var exit_path_selector = (
	EXIT_PATH_SELECTOR_SCRIPT.new()
)

var wander_moves_remaining: int = 0
var move_elapsed: float = 0.0
var move_retry_count: int = 0
var recover_from_state: int = CustomerState.IDLE
var force_exit_requested: bool = false
var decoration_extra_purchase_checked: bool = false

var visit_recorded: bool = false
var purchase_completed: bool = false
var visit_result_recorded: bool = false

# 퇴장 Tween이 중복 실행되는 것을 방지한다.
var exit_animation_running: bool = false

@onready var floor_node = $"../../Floor"
@onready var build_manager = $"../../BuildManager"
@onready var store_exterior: Node = $"../../StoreExterior"
@onready var player = get_parent().get_node("Player")

@export_range(0.0, 1.0, 0.05)
var rumor_activation_chance: float = 1.0



enum CustomerState {
	IDLE,
	GO_TO_SHELF,
	GO_TO_REGISTER,
	WANDER,
	WAIT_FOR_SERVICE,
	RECOVER,
	GO_TO_EXIT
}


var customer_type_id: String = "normal"
var customer_group_id: String = "normal"
var customer_type_selected: bool = false

var state: int = CustomerState.IDLE
var moving: bool = false

var target_shelf = null
var target_register = null

var grid_path: Array[Vector2i] = []
var grid_path_index: int = 0

# 중간 칸을 지나갔다고 보는 거리(픽셀). 칸 중심에 붙지 않고 연속으로 걷기 위한 값.
const WAYPOINT_RADIUS: float = 12.0

# 연속 이동 + 분리(CrowdSteering). false 로 바꾸면 예전처럼 칸 중심에서 칸 중심으로 이동하고 서로 피하지 않는다(문제가 생길 때 되돌리는 스위치).
const CROWD_STEERING: bool = true

# true 이면 걷는 동안 앞사람 때문에 완전히 멈추지 않고 겹쳐 지나간다(막힘이 적음). false 이면 앞사람 뒤에서 멈추고 줄을 선다(겹침 0, 막힘 많음).
const CROWD_SOFT: bool = true

var carried_item_id: String = ""
var carried_amount: int = 0

var wanted_item_id: String = ""
var wanted_amount: int = 1
var wanted_event_id: String = ""

var rumor_event_id: String = ""
var rumor_icon: Label = null
var rumor_checked: bool = false

var service_worker: Node = null
var service_attempted: bool = false


# =========================
# 생명주기와 이동 처리
# =========================

func _ready() -> void:
	add_to_group("customer")

	_create_rumor_icon()

	if not GameState.store_event_discovered.is_connected(
		_on_store_event_discovered
	):
		GameState.store_event_discovered.connect(
			_on_store_event_discovered
		)

func _physics_process(
	delta: float
) -> void:
	if not moving:
		velocity = Vector2.ZERO
		return

	if grid_path.is_empty():
		moving = false
		velocity = Vector2.ZERO
		handle_move_timeout()
		return

	if grid_path_index >= grid_path.size():
		moving = false
		velocity = Vector2.ZERO
		arrive_at_target()
		return

	move_elapsed += delta

	if move_elapsed >= move_timeout:
		handle_move_timeout()
		return

	var next_cell: Vector2i = (
		grid_path[grid_path_index]
	)

	var next_position: Vector2 = (
		floor_node.to_global(
			floor_node.grid_to_local(
				next_cell
			)
		)
	)

	# 칸 중심에 붙지 않고 연속으로 걷는다. 중간 칸은 가까이 지나가면 넘어가고,
	# 마지막 칸만 정확한 위치로 맞춘다(진열대·계산대 앞 자리 판정이 그대로 유지되도록).
	var is_last_cell: bool = (
		not CROWD_STEERING
		or grid_path_index >= grid_path.size() - 1
	)
	var arrival_distance: float = (
		maxf(speed * delta, 4.0)
		if is_last_cell
		else maxf(speed * delta, WAYPOINT_RADIUS)
	)

	if (
		global_position.distance_to(
			next_position
		)
		<= arrival_distance
	):
		if is_last_cell:
			global_position = next_position

		velocity = Vector2.ZERO

		grid_path_index += 1

		# 한 칸 이동에 성공했으므로
		# 정체 감지 시간을 다시 시작
		move_elapsed = 0.0

		if grid_path_index >= grid_path.size():
			moving = false
			arrive_at_target()

		return

	var direction: Vector2 = global_position.direction_to(next_position)

	if not CROWD_STEERING:
		velocity = direction * speed
		move_and_slide()
		return

	var steer: Dictionary = CrowdSteering.compute(
		CrowdSteering.screen_to_ground(direction).normalized(),
		_nearby_ground_offsets(),
		CROWD_SOFT
	)

	velocity = (
		direction * speed * float(steer["slow"])
		+ CrowdSteering.ground_to_screen(steer["push"])
	)

	# 앞사람 때문에 서 있는 동안은 정체 시간을 거의 세지 않는다(줄을 서다 포기하고 나가지 않게).
	if float(steer["slow"]) < 0.5:
		move_elapsed -= delta * 0.75

	move_and_slide()


# 주변 손님까지의 바닥 벡터(칸). 가까운 사람만 모은다.
func _nearby_ground_offsets() -> Array:
	var offsets: Array = []

	for other in get_tree().get_nodes_in_group("customer"):
		if other == self or not is_instance_valid(other) or not (other is Node2D):
			continue

		var offset: Vector2 = CrowdSteering.screen_to_ground(other.global_position - global_position)

		if offset.length() < CrowdSteering.KEEP_DISTANCE:
			offsets.append(offset)

	return offsets

# =========================
# 손님 유형과 구매 목표
# =========================

func choose_customer_type() -> void:
	if customer_type_selected: return
	customer_type_selected = true
	var decoration_bonuses: Dictionary = {}

	var manager: Node = get_tree().get_first_node_in_group(
		"build_manager"
	)

	if is_instance_valid(manager):
		if manager.has_method("get_customer_weight_bonuses"):
			decoration_bonuses = manager.call(
				"get_customer_weight_bonuses"
			)

	# 시간대는 DayManager의 현재 시각으로 정한다(없으면 시간대를 보지 않는다).
	var current_period: String = ""
	var scene: Node = get_tree().current_scene
	var day_manager: Node = (
		scene.get_node_or_null("DayManager")
		if scene != null
		else null
	)

	if is_instance_valid(day_manager) and day_manager.has_method("get_period"):
		current_period = str(day_manager.call("get_period"))

	var type_data: Dictionary = (
		CustomerTypeData.get_random_customer_type(
			GameState.total_day,
			decoration_bonuses,
			current_period
		)
	)

	if type_data.is_empty():
		customer_type_id = "normal"

		push_warning(
			"[손님] 유형 데이터를 선택하지 못해 일반 손님으로 설정"
		)

		return

	var selected_type_id: String = str(
		type_data.get(
			"customer_type_id",
			""
		)
	)

	if selected_type_id.is_empty():
		customer_type_id = "normal"

		push_warning(
			"[손님] 선택된 손님 유형 ID가 비어 있습니다."
		)

		return

	if not CustomerTypeData.has_customer_type(
		selected_type_id
	):
		customer_type_id = "normal"

		push_warning(
			"[손님] 등록되지 않은 유형: "
			+ selected_type_id
		)

		return

	customer_type_id = selected_type_id
	customer_group_id = CustomerTypeData.get_group_id(
		selected_type_id
	)

func choose_wanted_item() -> String:
	wanted_amount = 1
	wanted_event_id = ""
	if has_meta("regular_story_item"):
		wanted_amount = maxi(1,int(get_meta("regular_story_amount",1)))
		return str(get_meta("regular_story_item"))

	var request: Dictionary = (
		CustomerDemandData.get_random_wanted_request(
			get_customer_type_id(),
			GameState.total_day,
			ShopStock.get_stocked_item_ids(get_tree())
		)
	)

	if request.is_empty():
		return ""

	var item_id: String = str(
		request.get(
			"item_id",
			""
		)
	)

	if item_id.is_empty():
		return ""

	wanted_amount = maxi(
		int(
			request.get(
				"amount",
				1
			)
		),
		1
	)

	wanted_event_id = str(
		request.get(
			"event_id",
			""
		)
	)

	return item_id

func start_shopping():
	# 같은 손님이 중복으로 쇼핑을 시작하지 않도록 방지
	if visit_recorded or force_exit_requested:
		return

	visit_recorded = true
	decoration_extra_purchase_checked = false

	choose_customer_type()

	player.record_visitor(
		get_customer_type_id()
	)

	# -------------------------
	# 원하는 상품 결정
	# -------------------------
	var sellable_items: Array[String] = (
		ItemData.get_sellable_items()
	)

	if sellable_items.is_empty():
		push_error("[손님] 판매 가능한 상품 데이터가 없습니다.")
		go_to_exit()
		return

	wanted_item_id = (
		choose_wanted_item()
	)

	if wanted_item_id.is_empty():
		push_warning("[손님] 구매 가능한 상품을 선택하지 못했습니다.")
		go_to_exit()
		return

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

		player.record_unmet_demand(
			wanted_item_id,
			wanted_amount
		)
		StoreEventRemark.tell(self, "missing", wanted_item_id)

		start_wandering()
		return

	target_shelf = choose_best_stocked_shelf(
		available_shelves,
		wanted_item_id,
		wanted_amount
	)

	if target_shelf == null:
		push_warning("[손님] 상품을 제공할 진열대를 선택하지 못했습니다.")

		start_wandering()
		return

	# -------------------------
	# 진열대 접근 셀 검색
	# -------------------------
	var shelf_cell: Vector2i = (
		find_best_shelf_access_cell(
			target_shelf
		)
	)

	if shelf_cell == Vector2i(-1, -1):
		push_warning("[손님] 진열대에 접근할 수 없습니다.")
		go_to_exit()
		return


	if show_movement_debug:
		DebugLog.write(
			"진열대 접근 셀: ",
			shelf_cell
		)

	state = CustomerState.GO_TO_SHELF

	move_to_cell(shelf_cell)


# =========================
# 진열대·계산대 이용
# =========================

func find_register():
	var registers: Array = (
		get_tree().get_nodes_in_group("register")
	)

	var start_cell: Vector2i = (
		get_current_grid_cell()
	)

	var best_register = null
	var best_path_size: int = 2147483647

	for register in registers:
		if not is_instance_valid(register):
			continue

		if register.is_queued_for_deletion():
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

		var checkout_cell: Vector2i = (
			find_best_checkout_cell(register)
		)

		# 접근 가능한 결제 칸이 없는 계산대 제외
		if checkout_cell == Vector2i(-1, -1):
			continue

		if checkout_cell == start_cell:
			return register

		var path: Array[Vector2i] = (
			create_astar_grid_path(
				start_cell,
				checkout_cell
			)
		)

		if path.is_empty():
			continue

		if path[path.size() - 1] != checkout_cell:
			continue

		if path.size() < best_path_size:
			best_path_size = path.size()
			best_register = register

	return best_register


func arrive_at_target():
	move_elapsed = 0.0
	
	if state != CustomerState.RECOVER:
		move_retry_count = 0
		
	match state:

		CustomerState.GO_TO_SHELF:

			velocity = Vector2.ZERO

			await get_tree().create_timer(
				shelf_pick_delay,
				false
			).timeout

			if force_exit_requested:
				return

			if state != CustomerState.GO_TO_SHELF:
				return

			if not is_instance_valid(target_shelf):
				go_to_exit()
				return

			# 재고와 관계없이 상품을 살펴본 뒤 소문 검사
			if not rumor_checked:
				rumor_checked = true
				assign_discoverable_rumor()

			carried_item_id = ""
			carried_amount = 0

			if target_shelf.has_method(
				"take_items_by_id"
			):
				carried_amount = int(
					target_shelf.take_items_by_id(
						wanted_item_id,
						wanted_amount
					)
				)

			else:
				var taken_item_id: String = (
					target_shelf.take_one_item_by_id(
						wanted_item_id
					)
				)

				if not taken_item_id.is_empty():
					carried_amount = 1

			if carried_amount <= 0:

				go_to_exit()
				return


			carried_item_id = wanted_item_id
			try_decoration_extra_purchase()

			if carried_amount < wanted_amount:
				var missing_amount: int = (
					wanted_amount
					- carried_amount
				)

				player.record_unmet_demand(
					wanted_item_id,
					missing_amount
				)

			target_register = find_register()

			if target_register == null:
				push_warning("[손님] 접근 가능한 계산대가 없습니다.")
				go_to_exit()
				return

			var register_cell: Vector2i = (
				find_best_checkout_cell(
					target_register
				)
			)

			if register_cell == Vector2i(-1, -1):
				push_warning("[손님] 계산대에 접근할 수 없습니다.")
				go_to_exit()
				return

			if show_movement_debug:
				DebugLog.write(
					"계산대 접근 셀: ",
					register_cell
				)

			state = CustomerState.GO_TO_REGISTER

			move_to_cell(register_cell)

		CustomerState.WANDER:
			DebugLog.write("구경 위치 도착")

			velocity = Vector2.ZERO

			# 원하는 상품이 없어 구경하던 손님이
			# 처음 멈춘 순간에만 소문 활성화 검사
			if not rumor_checked:
				rumor_checked = true

				assign_discoverable_rumor()

			# 구경 중 잠시 대기
			await get_tree().create_timer(
				wander_pause_delay,
				false
			).timeout

			if force_exit_requested:
				return

			if state != CustomerState.WANDER:
				return

			wander_moves_remaining -= 1

			if wander_moves_remaining <= 0:
				go_to_exit()
				return

			move_to_next_wander_cell()

		CustomerState.GO_TO_REGISTER:

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
					return

				# 계산대 사용 가능 여부를 다시 확인할 간격
				await get_tree().create_timer(
					0.4,
					false
				).timeout

			if force_exit_requested:
				return

			# 아직 전달하지 않은 소문이 있다면
			# 계산 후 잠시 가게를 돌아다닌다.
			if can_share_rumor():

				start_wandering()
				return

			go_to_exit()

		CustomerState.RECOVER:
			velocity = Vector2.ZERO

			# 우회 후 원래 목표로 돌아가기 전 대기
			await get_tree().create_timer(
				0.3,
				false
			).timeout

			if force_exit_requested:
				return

			if state != CustomerState.RECOVER:
				return


			retry_previous_target()

		CustomerState.GO_TO_EXIT:
			DebugLog.write("출구 도착")
			finish_exit()


func checkout_item() -> void:
	if purchase_completed or visit_result_recorded:
		return

	if force_exit_requested:
		return

	if carried_item_id.is_empty():
		push_warning("[손님] 계산할 상품이 없습니다.")
		return

	if carried_amount <= 0:
		push_warning("[손님] 계산할 상품 수량이 없습니다.")
		return

	if not ItemData.has_item(carried_item_id):
		push_error(
			"[손님] 상품 데이터를 찾을 수 없습니다: "
			+ carried_item_id
		)

		return

	var unit_price: int = (
		ItemData.get_item_price(
			carried_item_id
		)
	)

	if unit_price <= 0:
		push_error(
			"[손님] 상품 가격이 없습니다: "
			+ carried_item_id
		)

		return

	var total_price: int = (
		unit_price
		* carried_amount
	)

	purchase_completed = true
	visit_result_recorded = true

	player.add_money(
		total_price
	)

	player.record_successful_sale(
		total_price,
		carried_item_id,
		carried_amount
	)
	if RegularCustomerRecords.record_sale(self,carried_item_id,carried_amount): RegularCustomerVisits.remark(self)
	if ExpeditionContactFlow.record_sale(self,carried_item_id,carried_amount): ExpeditionContactVisits.remark(self)
	StoreEventRemark.tell(self, "bought", carried_item_id)

	# 결제 완료 상품은 더 이상 미결제 상태가 아님
	carried_item_id = ""
	carried_amount = 0


func go_to_exit():
	_return_unpaid_items_to_shelf()

	service_worker = null

	force_exit_requested = true

	# 이전 이동 중단
	moving = false
	velocity = Vector2.ZERO
	grid_path.clear()
	grid_path_index = 0
	move_elapsed = 0.0

	state = CustomerState.GO_TO_EXIT

	var exit_cell: Vector2i = find_exit_cell()

	if exit_cell == Vector2i(-1, -1):
		push_warning("[손님 퇴장] 접근 가능한 출구가 없어 강제 퇴장합니다.")
		finish_exit()
		return

	if get_current_grid_cell() == exit_cell:
		finish_exit()
		return

	move_to_cell(exit_cell)

	if not moving:
		push_warning("[손님 퇴장] 출구 경로 생성에 실패해 강제 퇴장합니다.")
		finish_exit()

func finish_exit() -> void:
	if is_queued_for_deletion():
		return

	if exit_animation_running:
		return

	force_exit_requested = true
	service_worker = null

	moving = false
	velocity = Vector2.ZERO

	grid_path.clear()
	grid_path_index = 0
	move_elapsed = 0.0

	state = CustomerState.GO_TO_EXIT

	_return_unpaid_items_to_shelf()

	# 미결제 상품이 남아 있으면 퇴장할 수 없다.
	if (
		not carried_item_id.is_empty()
		and carried_amount > 0
	):
		push_error(
			"[손님 퇴장] 미결제 상품이 남아 있어 퇴장을 보류합니다."
		)
		return

	exit_animation_running = true

	# 방문 결과는 퇴장 연출 시작 시 한 번만 기록한다.
	_record_final_visit_result()

	target_shelf = null
	target_register = null

	rumor_event_id = ""
	_refresh_rumor_icon()

	var exit_door: Node = (
		find_nearest_exit_door()
	)

	if not is_instance_valid(
		exit_door
	):
		queue_free()
		return

	if not is_instance_valid(
		store_exterior
	):
		queue_free()
		return

	if not store_exterior.has_method(
		"get_sidewalk_approach_position_for_door"
	):
		queue_free()
		return

	if not store_exterior.has_method(
		"get_sidewalk_spawn_position_for_door"
	):
		queue_free()
		return

	# 문 안쪽 위치
	var inside_position: Vector2 = (
		exit_door.call(
			"get_customer_target_position"
		)
	)

	# 문 바로 바깥 위치
	var outside_position: Vector2 = (
		exit_door.call(
			"get_customer_spawn_position"
		)
	)

	# 문에서 보도로 진입하는 위치
	var sidewalk_approach_position: Vector2 = (
		store_exterior.call(
			"get_sidewalk_approach_position_for_door",
			exit_door
		)
	)

	# 보도 끝의 퇴장 위치
	var sidewalk_exit_position: Vector2 = (
		store_exterior.call(
			"get_sidewalk_spawn_position_for_door",
			exit_door
		)
	)

	var safe_speed: float = maxf(
		speed,
		1.0
	)

	# 길찾기 도착 지점에서 정확한 문 위치까지
	var inside_duration: float = clampf(
		global_position.distance_to(
			inside_position
		) / safe_speed,
		0.1,
		0.6
	)

	# 문 밖에서 보도까지
	var yard_duration: float = clampf(
		outside_position.distance_to(
			sidewalk_approach_position
		) / safe_speed,
		0.3,
		2.0
	)

	# 보도를 따라 화면 밖으로 이동
	var sidewalk_duration: float = clampf(
		sidewalk_approach_position.distance_to(
			sidewalk_exit_position
		) / safe_speed,
		0.4,
		3.0
	)

	var exit_tween: Tween = (
		create_tween()
	)

	exit_tween.set_trans(
		Tween.TRANS_LINEAR
	)

	# 1단계: 정확한 문 안쪽으로 이동
	exit_tween.tween_property(
		self,
		"global_position",
		inside_position,
		inside_duration
	)

	# 2단계: 문을 통과
	exit_tween.tween_property(
		self,
		"global_position",
		outside_position,
		0.45
	)

	# 3단계: 앞마당을 지나 보도로 이동
	exit_tween.tween_property(
		self,
		"global_position",
		sidewalk_approach_position,
		yard_duration
	)

	# 보도에 도착한 뒤 잠시 방향 전환
	exit_tween.tween_interval(
		0.1
	)

	# 4단계: 보도를 따라 외부 끝으로 이동
	exit_tween.tween_property(
		self,
		"global_position",
		sidewalk_exit_position,
		sidewalk_duration
	)

	await exit_tween.finished

	if is_instance_valid(self):
		queue_free()

# =========================
# 격자 길찾기
# =========================

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
		return []

	var path: Array[Vector2i] = (
		astar.get_id_path(
			start_cell,
			goal_cell
		)
	)

	if show_movement_debug:
		DebugLog.write(
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
	
	

func move_to_cell(
	target_cell: Vector2i
) -> void:
	var start_cell: Vector2i = get_current_grid_cell()

	moving = false
	velocity = Vector2.ZERO
	grid_path.clear()
	grid_path_index = 0
	move_elapsed = 0.0

	if target_cell == start_cell:
		if show_movement_debug:
			DebugLog.write(
				"이미 목표 셀에 도착: ",
				start_cell
			)

		arrive_at_target()
		return

	grid_path = create_astar_grid_path(
		start_cell,
		target_cell
	)

	moving = not grid_path.is_empty()

	if show_movement_debug:
		DebugLog.write(
			"셀 이동: ",
			start_cell,
			" → ",
			target_cell,
			" / 경로: ",
			grid_path
		)

	if not moving:
		handle_move_timeout()

func find_best_checkout_cell(
	register
) -> Vector2i:
	if not is_instance_valid(register):
		return Vector2i(-1, -1)

	var candidates: Array[Vector2i] = (
		register.get_checkout_cells()
	)

	return find_best_reachable_cell(candidates)

func find_best_shelf_access_cell(
	shelf
) -> Vector2i:
	if not is_instance_valid(shelf):
		return Vector2i(-1, -1)

	var candidates: Array[Vector2i] = (
		shelf.get_customer_access_cells()
	)

	return find_best_reachable_cell(candidates)

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

	move_to_next_wander_cell()
	
func move_to_next_wander_cell():
	var target_cell: Vector2i = (
		find_random_walkable_cell()
	)

	if target_cell == Vector2i(-1, -1):
		push_warning("[손님] 구경할 위치를 찾지 못해 퇴장합니다.")
		go_to_exit()
		return

	if show_movement_debug:
		DebugLog.write(
			"구경 위치: ",
			target_cell
		)

	move_to_cell(target_cell)

func complete_checkout_by_worker():
	if carried_item_id.is_empty():
		return

	checkout_item()

	# 계산 완료 후 퇴장하기 전 대기
	await get_tree().create_timer(
		checkout_finish_delay,
		false
	).timeout


	# 기다리는 동안 폐점 명령을 받았다면
	# 쇼핑을 다시 진행하지 않음
	if force_exit_requested:
		return

	go_to_exit()

func handle_move_timeout():

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
			push_warning("[손님 퇴장] 이동 실패가 반복되어 강제 퇴장합니다.")

			move_retry_count = 0
			finish_exit()
			return

		go_to_exit()
		return

	if move_retry_count > max_move_retries:
		push_warning("[손님] 이동 재시도 한도를 초과해 퇴장합니다.")

		move_retry_count = 0
		go_to_exit()
		return

	recover_from_state = state

	var escape_cell: Vector2i = (
		find_random_walkable_cell()
	)

	if escape_cell == Vector2i(-1, -1):
		push_warning("[손님] 우회할 위치를 찾지 못해 퇴장합니다.")
		go_to_exit()
		return

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


func find_best_reachable_cell(
	candidates: Array[Vector2i]
) -> Vector2i:
	var start_cell: Vector2i = (
		get_current_grid_cell()
	)

	var best_cell := Vector2i(-1, -1)
	var best_path_size: int = 2147483647

	for candidate in candidates:
		if not floor_node.is_cell_inside(candidate):
			continue

		if build_manager.is_cell_blocked_for_customer(
			candidate
		):
			continue

		# 이미 접근 칸에 서 있다면 이동할 필요 없음
		if candidate == start_cell:
			return candidate

		var path: Array[Vector2i] = (
			create_astar_grid_path(
				start_cell,
				candidate
			)
		)

		if path.is_empty():
			continue

		# 접근 칸 대신 다른 칸으로 향하는 경로 제외
		if path[path.size() - 1] != candidate:
			continue

		if path.size() < best_path_size:
			best_path_size = path.size()
			best_cell = candidate

	return best_cell

func find_exit_cell() -> Vector2i:
	return exit_path_selector.find_exit_cell(
		get_tree().get_nodes_in_group("door"),
		get_current_grid_cell(),
		floor_node,
		Callable(
			build_manager,
			"is_cell_blocked_for_customer"
		),
		Callable(self, "create_astar_grid_path")
	)

func get_customer_type_id() -> String:
	return customer_type_id

# 손님이 도착한 위치에서 가장 가까운 일반 출입문을 찾는다.
func find_nearest_exit_door() -> Node:
	var nearest_door: Node = null
	var nearest_distance: float = INF

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

		if not door.has_meta("anchor"):
			continue

		if not door.has_method(
			"get_customer_target_position"
		):
			continue

		if not door.has_method(
			"get_customer_spawn_position"
		):
			continue

		if not door.has_method(
			"get_customer_arrival_position"
		):
			continue

		var inside_position: Vector2 = (
			door.call(
				"get_customer_target_position"
			)
		)

		var distance: float = (
			global_position.distance_to(
				inside_position
			)
		)

		if distance >= nearest_distance:
			continue

		nearest_distance = distance
		nearest_door = door

	return nearest_door

# =========================
# 소문 이벤트
# =========================

func assign_discoverable_rumor() -> void:
	rumor_event_id = ""
	_refresh_rumor_icon()


	var candidates: Array[Dictionary] = (
		StoreEventData.get_discoverable_events(
			GameState.total_day,
			customer_type_id
		)
	)

	if candidates.is_empty():
		return

	# 이 손님에게 소문 아이콘이 나타날지 확률 판정
	var roll: float = randf()

	if roll >= rumor_activation_chance:
		return

	var selected_event: Dictionary = (
		candidates.pick_random()
	)

	rumor_event_id = str(
		selected_event.get(
			"event_id",
			""
		)
	)

	if rumor_event_id.is_empty():
		return

	_refresh_rumor_icon()


func _create_rumor_icon() -> void:
	rumor_icon = Label.new()

	rumor_icon.text = "!"
	rumor_icon.position = Vector2(
		-14,
		-54
	)

	rumor_icon.size = Vector2(
		28,
		28
	)

	rumor_icon.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)

	rumor_icon.vertical_alignment = (
		VERTICAL_ALIGNMENT_CENTER
	)

	rumor_icon.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)

	rumor_icon.z_index = 50

	rumor_icon.add_theme_font_size_override(
		"font_size",
		22
	)

	rumor_icon.add_theme_color_override(
		"font_color",
		Color(
			1.0,
			0.9,
			0.2
		)
	)

	rumor_icon.add_theme_color_override(
		"font_outline_color",
		Color.BLACK
	)

	rumor_icon.add_theme_constant_override(
		"outline_size",
		4
	)

	var icon_background := StyleBoxFlat.new()

	icon_background.bg_color = Color(
		0.12,
		0.12,
		0.14,
		0.95
	)

	icon_background.border_color = Color(
		1.0,
		0.85,
		0.15,
		1.0
	)

	icon_background.set_border_width_all(2)

	icon_background.corner_radius_top_left = 14
	icon_background.corner_radius_top_right = 14
	icon_background.corner_radius_bottom_left = 14
	icon_background.corner_radius_bottom_right = 14

	rumor_icon.add_theme_stylebox_override(
		"normal",
		icon_background
	)

	add_child(
		rumor_icon
	)

	_refresh_rumor_icon()


func _refresh_rumor_icon() -> void:
	if not is_instance_valid(rumor_icon):
		return

	rumor_icon.visible = (
		not rumor_event_id.is_empty()
	)

func _on_store_event_discovered(
	event_id: String,
	_discovery_day: int
) -> void:
	if rumor_event_id != event_id:
		return

	rumor_event_id = ""

	_refresh_rumor_icon()

func can_share_rumor() -> bool:
	if rumor_event_id.is_empty():
		return false

	return StoreEventData.can_share_event(rumor_event_id, GameState.total_day)


func share_rumor_event() -> Dictionary:
	if not can_share_rumor():
		return {}

	var event_data: Dictionary = (
		StoreEventData.get_event_occurrence(
			rumor_event_id, GameState.total_day
		)
	)

	if event_data.is_empty():
		return {}

	var event_id: String = rumor_event_id

	var discovered: bool = (
		StoreEventData.discover_event(
			event_id, GameState.total_day
		)
	)

	if not discovered:
		return {}

	# 발견 신호에 의해서도 지워지지만
	# 현재 손님의 상태도 확실히 정리
	rumor_event_id = ""
	_refresh_rumor_icon()

	return event_data

func choose_best_stocked_shelf(
	available_shelves: Array,
	item_id: String,
	requested_amount: int
):
	var enough_shelves: Array = []
	var partial_shelves: Array = []

	var highest_partial_stock: int = 0

	for shelf in available_shelves:
		if not is_instance_valid(shelf):
			continue

		var shelf_stock: int = 1

		if shelf.has_method(
			"get_item_stock"
		):
			shelf_stock = int(
				shelf.get_item_stock(
					item_id
				)
			)

		if shelf_stock >= requested_amount:
			enough_shelves.append(
				shelf
			)

			continue

		if shelf_stock > highest_partial_stock:
			highest_partial_stock = shelf_stock

			partial_shelves.clear()
			partial_shelves.append(
				shelf
			)

		elif shelf_stock == highest_partial_stock:
			partial_shelves.append(
				shelf
			)

	# 요구 수량을 전부 제공할 수 있는 진열대 우선
	if not enough_shelves.is_empty():
		return enough_shelves.pick_random()

	# 전부 제공할 수 없다면 재고가 가장 많은 진열대 선택
	if not partial_shelves.is_empty():
		return partial_shelves.pick_random()

	return null

func _return_unpaid_items_to_shelf() -> void:
	if carried_item_id.is_empty():
		return

	if carried_amount <= 0:
		carried_item_id = ""
		carried_amount = 0
		return

	# 먼저 원래 진열대에 반환
	var returned_amount: int = 0

	if is_instance_valid(target_shelf):
		if not target_shelf.is_queued_for_deletion():
			if target_shelf.has_method("return_items_by_id"):
				returned_amount = int(
					target_shelf.return_items_by_id(
						carried_item_id,
						carried_amount
					)
				)

	returned_amount = clampi(
		returned_amount,
		0,
		carried_amount
	)

	carried_amount -= returned_amount

	# 진열대에 전부 반환했다면 처리 완료
	if carried_amount == 0:
		carried_item_id = ""
		return

	# 등록되지 않은 상품은 보존하고 오류 표시
	if not ItemData.has_item(carried_item_id):
		push_error(
			"[손님] 미결제 상품 회수 실패 / 미등록 아이템: "
			+ carried_item_id
			+ " ×"
			+ str(carried_amount)
		)
		return

	# 진열대가 없거나 가득 찼으면 공용 재고로 회수
	var recovered_item_id: String = carried_item_id
	var recovered_amount: int = carried_amount

	GameState.add_item(
		recovered_item_id,
		recovered_amount
	)

	# 회수 완료 후 비워서 중복 반환 방지
	carried_item_id = ""
	carried_amount = 0


# =========================
# 직원 응대와 추천 구매
# =========================

func needs_employee_service() -> bool:
	return (
		state == CustomerState.WANDER
		and not service_attempted
		and not is_instance_valid(service_worker)
		and carried_item_id.is_empty()
		and not force_exit_requested
	)


func try_reserve_employee_service(
	worker: Node
) -> bool:
	if not is_instance_valid(worker):
		return false

	if not needs_employee_service():
		return false

	service_worker = worker
	service_attempted = true

	# 직원이 접근하는 동안 고객은 현재 위치에서 기다림
	moving = false
	velocity = Vector2.ZERO
	grid_path.clear()
	grid_path_index = 0
	move_elapsed = 0.0

	state = CustomerState.WAIT_FOR_SERVICE

	return true


func cancel_employee_service(
	worker: Node
) -> void:
	if service_worker != worker:
		return

	service_worker = null

	if force_exit_requested:
		return

	start_wandering()


func complete_employee_service(
	worker: Node,
	success_chance: float
) -> bool:
	if service_worker != worker:
		return false

	if state != CustomerState.WAIT_FOR_SERVICE:
		service_worker = null
		return false

	service_worker = null

	var normalized_chance: float = clampf(
		success_chance,
		0.0,
		1.0
	)

	var roll: float = randf()

	if roll >= normalized_chance:
		start_wandering()
		return false

	if not _start_recommended_purchase():
		start_wandering()
		return false

	return true


func _start_recommended_purchase() -> bool:
	var sellable_items: Array[String] = (
		ItemData.get_sellable_items()
	)

	if sellable_items.is_empty():
		return false

	# 매번 같은 상품만 추천되지 않도록 순서를 섞음
	sellable_items.shuffle()

	var shelves: Array = (
		get_tree().get_nodes_in_group("shelf")
	)

	for candidate_item_id in sellable_items:
		if candidate_item_id.is_empty():
			continue

		# 처음 원했던 품목은 대체 상품에서 제외
		if candidate_item_id == wanted_item_id:
			continue

		var available_shelves: Array = []

		for shelf in shelves:
			if not is_instance_valid(shelf):
				continue

			if shelf.is_queued_for_deletion():
				continue

			if bool(
				shelf.get_meta(
					"is_build_preview",
					false
				)
			):
				continue

			if not shelf.has_method(
				"has_item_in_stock"
			):
				continue

			if shelf.has_item_in_stock(
				candidate_item_id
			):
				available_shelves.append(shelf)

		if available_shelves.is_empty():
			continue

		var recommended_shelf = (
			choose_best_stocked_shelf(
				available_shelves,
				candidate_item_id,
				1
			)
		)

		if not is_instance_valid(
			recommended_shelf
		):
			continue

		var shelf_cell: Vector2i = (
			find_best_shelf_access_cell(
				recommended_shelf
			)
		)

		if shelf_cell == Vector2i(-1, -1):
			continue

		wanted_item_id = candidate_item_id
		wanted_amount = 1
		wanted_event_id = ""
		target_shelf = recommended_shelf

		state = CustomerState.GO_TO_SHELF
		move_to_cell(shelf_cell)

		return true

	return false

# =========================
# 치장 추가 구매와 최종 통계
# =========================

func try_decoration_extra_purchase() -> void:
	# 방문당 한 번만 검사
	if decoration_extra_purchase_checked:
		return

	decoration_extra_purchase_checked = true

	if not is_instance_valid(target_shelf):
		return

	if carried_item_id.is_empty():
		return

	# 원래 요구량도 확보하지 못했다면 추가 구매하지 않음
	if carried_amount < wanted_amount:
		return

	if not target_shelf.has_method("get_item_stock"):
		return

	if not target_shelf.has_method("take_items_by_id"):
		return

	var remaining_stock: int = int(
		target_shelf.get_item_stock(carried_item_id)
	)

	if remaining_stock <= 0:
		return

	var manager: Node = get_tree().get_first_node_in_group(
		"build_manager"
	)

	if not is_instance_valid(manager):
		return

	if not manager.has_method("get_decoration_effect"):
		return

	var chance: float = float(
		manager.call(
			"get_decoration_effect",
			"purchase_desire"
		)
	)

	if not is_finite(chance):
		return

	# effect_value 0.20 = 추가 구매 확률 20%
	chance = clampf(chance, 0.0, 1.0)

	if chance <= 0.0:
		return

	if randf() >= chance:
		return

	var added_amount: int = int(
		target_shelf.take_items_by_id(
			carried_item_id,
			1
		)
	)

	if added_amount <= 0:
		return

	carried_amount += added_amount

func _record_final_visit_result() -> void:
	if not visit_recorded:
		return

	if visit_result_recorded:
		return

	visit_result_recorded = true

	if purchase_completed:
		return

	if is_instance_valid(player):
		# 상품 부족 수요는 앞에서 별도로 기록했으므로
		# 여기에서는 실패 인원만 증가
		player.record_missed_sale()
