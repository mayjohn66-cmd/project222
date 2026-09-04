extends Node


enum GamePhase {
	SHOP,
	EXPEDITION
}

enum Weekday {
	MONDAY = 1,
	TUESDAY = 2,
	WEDNESDAY = 3,
	THURSDAY = 4,
	FRIDAY = 5,
	SATURDAY = 6,
	SUNDAY = 7
}

signal shop_opened

var shop_open: bool = false
var current_day: int = Weekday.FRIDAY
var current_phase: GamePhase = GamePhase.SHOP

var summary_open: bool = false
var closing_shop: bool = false
var night_closed: bool = false
var first_settlement_done: bool = false
var fast_forwarding_to_morning: bool = false
var night_auto_running: bool = false

@export var night_auto_time_scale: float = 4.0

var saved_time_scale: float = 1.0
var saved_player_collision_layer: int = 0
var saved_player_collision_mask: int = 0

@export var night_fast_forward_delay: float = 0.08
@onready var day_label: Label = $"../UI/DayLabel"
@onready var player = $"../Actors/Player"
@onready var customer_spawner = $"../CustomerSpawner"
@onready var day_summary_center: CenterContainer = $"../UI/DaySummaryCenter"
@onready var summary_text: Label = $"../UI/DaySummaryCenter/DaySummaryPanel/VBoxContainer/SummaryText"
@onready var next_day_button: Button = $"../UI/DaySummaryCenter/DaySummaryPanel/VBoxContainer/NextDayButton"
@onready var build_manager = $"../BuildManager"


signal hour_changed(hour: int)
signal period_changed(period: String)

@export var current_hour: int = 9
@export var open_shop_button: Button

@onready var hour_timer: Timer = $HourTimer
@onready var time_label: Label = $"../UI/TimeLabel"

var current_period: String = ""



func _ready():
	# 정산창이 열린 상태에서도 버튼 입력을 받을 수 있도록 함
	process_mode = Node.PROCESS_MODE_ALWAYS
	day_summary_center.process_mode = Node.PROCESS_MODE_ALWAYS

	day_summary_center.visible = false

	next_day_button.text = "확인"

	next_day_button.pressed.connect(
		confirm_next_day
	)

	# 저장된 게임 상태가 있을 때만 날짜 복원
	if (
		GameState.has_player_state()
		or GameState.has_store_layout()
	):
		current_day = GameState.current_day

		print(
			"[DayManager] 요일 복원: ",
			get_day_name()
		)

	# 새 게임이면 DayManager의 현재 설정을 사용
	else:
		GameState.current_day = current_day

		print(
			"[DayManager] 새 게임 시작 요일: ",
			get_day_name()
		)

	update_phase()
	apply_phase()
	update_day_ui()

	current_period = get_period()

	hour_timer.timeout.connect(
		_on_hour_timer_timeout
	)

	update_time_ui()

	shop_open = false

	hour_timer.stop()
	
	customer_spawner.process_mode = (
	Node.PROCESS_MODE_DISABLED
)

	if open_shop_button == null:
		print("[DayManager] OpenShopButton을 찾지 못했습니다.")
		return

	print(
		"[DayManager] OpenShopButton 연결 성공: ",
		open_shop_button
	)

	open_shop_button.visible = true

	if not open_shop_button.pressed.is_connected(
		open_shop
	):
		open_shop_button.pressed.connect(
			open_shop
		)

	update_time_ui()

	print("[가게] 오픈 준비")



func request_day_end():
	# 영업일이면 정산창 표시
	if current_phase == GamePhase.SHOP:
		end_shop_day()
		return

	# 원정일은 아직 시스템이 없으므로
	# 테스트에서는 바로 다음 날로 진행
	advance_to_next_day()


func end_shop_day():
	if summary_open:
		return

	if closing_shop:
		return

	closing_shop = true

	# 신규 손님 생성 중단
	if customer_spawner.has_method("set_shop_open"):
		customer_spawner.set_shop_open(false)

	print("폐점 시작 - 남은 손님을 기다립니다.")

	update_day_ui()

	await wait_for_customers_to_leave()

	print("모든 손님 퇴장 완료")

	closing_shop = false

	show_day_summary()


func show_day_summary():
	if summary_open:
		return

	var stats: Dictionary = (
		player.get_daily_shop_stats()
	)

	var visitors: int = int(
		stats.get("visitors", 0)
	)

	var sales: int = int(
		stats.get("sales", 0)
	)

	var missed: int = int(
		stats.get("missed", 0)
	)

	var revenue: int = int(
		stats.get("revenue", 0)
	)

	var purchase_rate: float = 0.0

	if visitors > 0:
		purchase_rate = (
			float(sales)
			/ float(visitors)
			* 100.0
		)

	var settlement_period: String

	if not first_settlement_done:
		settlement_period = (
			"09:00 ~ 21:00"
		)
	else:
		settlement_period = (
			"전일 21:00 ~ 금일 21:00"
		)

	summary_text.text = (
		str(current_day)
		+ " 영업 결과"
		+ "\n"
		+ settlement_period
		+ "\n\n방문객: "
		+ str(visitors)
		+ "명"
		+ "\n구매 성공: "
		+ str(sales)
		+ "명"
		+ "\n판매 실패: "
		+ str(missed)
		+ "명"
		+ "\n구매율: "
		+ str(roundi(purchase_rate))
		+ "%"
		+ "\n매출: "
		+ str(revenue)
		+ "G"
	)

	summary_open = true
	day_summary_center.visible = true

	# 결산 확인 전까지 전체 게임 정지
	get_tree().paused = true

	print(
		"[결산] ",
		settlement_period
	)


func confirm_next_day():
	if not summary_open:
		return

	summary_open = false
	day_summary_center.visible = false

	get_tree().paused = false

	first_settlement_done = true

	# =========================
	# 금요일 마지막 결산
	# → 토요일 원정
	# =========================
	if current_day == Weekday.FRIDAY:
		enter_expedition_scene()
		return

	# =========================
	# 월~목 일반 날짜 진행
	# =========================
	advance_to_next_day()

	if night_closed:
		fast_forward_to_morning()
		return

	resolve_night_operation()


func advance_to_next_day():
	current_day += 1

	if current_day > Weekday.SUNDAY:
		current_day = Weekday.MONDAY

	update_phase()

	player.reset_shop_stats()

	apply_phase()
	update_day_ui()

	print(
		"요일 변경: ",
		get_day_name(),
		" / ",
		get_phase_name()
	)


func update_phase():
	if current_day <= Weekday.FRIDAY:
		current_phase = GamePhase.SHOP
	else:
		current_phase = GamePhase.EXPEDITION


func apply_phase():
	if current_phase == GamePhase.SHOP:
		if customer_spawner.has_method(
			"set_shop_open"
		):
			customer_spawner.set_shop_open(
				true
			)

	else:
		if customer_spawner.has_method(
			"set_shop_open"
		):
			customer_spawner.set_shop_open(
				false
			)


func get_phase_name() -> String:
	if current_phase == GamePhase.SHOP:
		return "영업"

	return "원정"


func update_day_ui():
	if day_label == null:
		return

	if closing_shop:
		day_label.text = (
			get_day_name()
			+ " / 폐점 정리 중"
		)
		return

	day_label.text = (
		get_day_name()
		+ " / "
		+ get_phase_name()
	)


func wait_for_customers_to_leave():
	while true:
		var customers: Array = (
			get_tree().get_nodes_in_group("customer")
		)

		if customers.is_empty():
			return

		print(
			"남은 손님: ",
			customers.size()
		)

		await get_tree().create_timer(
			0.25
		).timeout



func get_period() -> String:
	if current_hour >= 9 and current_hour < 13:
		return "morning"

	if current_hour >= 13 and current_hour < 17:
		return "day"

	if current_hour >= 17 and current_hour < 21:
		return "evening"

	return "night"


func get_period_name() -> String:
	match get_period():
		"morning":
			return "아침"

		"day":
			return "낮"

		"evening":
			return "저녁"

		"night":
			return "심야"

	return ""



func is_player_control_time() -> bool:
	return (
		current_hour >= 9
		and current_hour < 21
	)



func update_time_ui():
	if time_label == null:
		return

	if current_phase == GamePhase.EXPEDITION:
		time_label.text = "원정 기간"
		return

	if fast_forwarding_to_morning:
		time_label.text = (
			format_hour(current_hour)
			+ " / 심야 시간 경과"
		)
		return

	if night_auto_running:
		time_label.text = (
			format_hour(current_hour)
			+ " / 심야 자동영업 ×"
			+ str(int(night_auto_time_scale))
		)

		return

	if night_closed:
		time_label.text = (
			format_hour(current_hour)
			+ " / 심야 폐점"
		)
		return

	time_label.text = (
		format_hour(current_hour)
		+ " / "
		+ get_period_name()
	)


func format_hour(hour: int) -> String:
	return "%02d:00" % hour


func _on_hour_timer_timeout():
	var old_period: String = get_period()

	current_hour += 1

	if current_hour >= 24:
		current_hour = 0

	# 심야 자동영업이 09:00에 도착
	if (
		current_hour == 9
		and night_auto_running
	):
		finish_night_auto_operation()

	var new_period: String = get_period()

	if current_hour == 21:

		# =========================
		# 금요일 마지막 영업
		# =========================
		if current_day == Weekday.FRIDAY:
			await close_shop_for_expedition_and_settle()

		# =========================
		# 월~목 일반 영업
		# =========================
		else:
			var night_staffed: bool = (
				check_full_night_staffing()
			)

			if night_staffed:
				night_closed = false

				print(
					"[심야 영업] 근무 인원 확보"
				)

				show_day_summary()

			else:
				await close_shop_for_night_and_settle()

	print(
		"[시간] ",
		format_hour(current_hour),
		" / ",
		get_period_name()
	)

	hour_changed.emit(
		current_hour
	)

	if old_period != new_period:
		current_period = new_period

		period_changed.emit(
			new_period
		)

		print(
			"[시간대 변경] ",
			get_period_name()
		)

	update_time_ui()


func open_shop():
	if shop_open:
		return

	if not can_open_shop():
		return

	shop_open = true
	night_closed = false

	open_shop_button.visible = false

	# 손님 생성 시스템 다시 활성화
	customer_spawner.process_mode = (
		Node.PROCESS_MODE_INHERIT
	)

	print(
		"[가게] CustomerSpawner 활성화 / mode: ",
		customer_spawner.process_mode
	)

	customer_spawner.set_shop_open(true)

	hour_timer.start()

	shop_opened.emit()

	update_time_ui()

	print(
		"[가게] 영업 시작 / ",
		format_hour(current_hour)
	)

func has_real_furniture(group_name: String) -> bool:
	var nodes: Array = (
		get_tree().get_nodes_in_group(
			group_name
		)
	)

	for node in nodes:
		if not is_instance_valid(node):
			continue

		# 건축 미리보기 제외
		if bool(
			node.get_meta(
				"is_build_preview",
				false
			)
		):
			continue

		return true

	return false

func can_open_shop() -> bool:
	var has_door: bool = (
		has_real_furniture("door")
	)

	var has_register: bool = (
		has_real_furniture("register")
	)

	if not has_door:
		print(
			"[가게] 오픈 실패: 문이 없습니다."
		)
		return false

	if not has_register:
		print(
			"[가게] 오픈 실패: 계산대가 없습니다."
		)
		return false

	return true

func has_worker_at_hour(hour: int) -> bool:
	var actors = get_node_or_null("../Actors")

	if actors == null:
		print("[심야 검사] Actors를 찾지 못했습니다.")
		return false

	for actor in actors.get_children():
		# Player 등 Worker가 아닌 노드 제외
		if not actor.has_method("is_hour_in_shift"):
			continue

		if actor.is_hour_in_shift(hour):
			return true

	return false

func check_full_night_staffing() -> bool:
	var night_hours: Array[int] = [
		21, 22, 23,
		0, 1, 2, 3, 4, 5, 6, 7, 8
	]

	var fully_staffed: bool = true

	print("====================")
	print("[심야 근무 검사 시작]")

	for hour in night_hours:
		var staffed: bool = has_worker_at_hour(hour)

		print(
			"%02d:00 → " % hour,
			"직원 있음" if staffed else "직원 없음"
		)

		if not staffed:
			fully_staffed = false

	if fully_staffed:
		print("[심야 결과] 21:00~09:00 전체 근무 가능")
	else:
		print("[심야 결과] 근무 공백 있음 → 심야 영업 불가")

	print("====================")

	return fully_staffed

func send_all_customers_out():
	var customers: Array = (
		get_tree().get_nodes_in_group(
			"customer"
		)
	)

	print(
		"[심야 폐점] 퇴장시킬 손님 수: ",
		customers.size()
	)

	for customer in customers:
		if not is_instance_valid(customer):
			continue

		if customer.has_method("go_to_exit"):
			customer.go_to_exit()

func close_shop_for_night():
	if night_closed:
		return

	night_closed = true

	print("[심야 폐점] 근무 직원 부족")

	# 21:00에서 시간 정지
	hour_timer.stop()

	update_time_ui()

	# 신규 손님 생성 종료
	customer_spawner.set_shop_open(false)

	customer_spawner.process_mode = (
		Node.PROCESS_MODE_DISABLED
	)

	# 기존 손님 전원 퇴장
	send_all_customers_out()

	print(
		"[심야 폐점] 시간 정지: ",
		format_hour(current_hour)
	)

func resolve_night_operation():
	# 원정일이면 심야 편의점 영업을 하지 않음
	if current_phase != GamePhase.SHOP:
		return

	var night_staffed: bool = (
		check_full_night_staffing()
	)

	if not night_staffed:
		close_shop_for_night()
		return

	night_closed = false

	print(
		"[심야 영업] 근무 인원 확보"
	)

	start_night_auto_operation()

func send_all_workers_out():
	var actors = get_node_or_null(
		"../Actors"
	)

	if actors == null:
		return

	var worker_count: int = 0

	for actor in actors.get_children():
		# Worker가 아닌 Player 등 제외
		if not actor.has_method(
			"request_shift_end"
		):
			continue

		# 이미 퇴근한 직원은 제외
		if not actor.visible:
			continue

		worker_count += 1

		actor.request_shift_end()

	print(
		"[심야 폐점] 퇴근시킬 직원 수: ",
		worker_count
	)

func wait_for_night_close_complete():
	while true:
		var customers: Array = (
			get_tree().get_nodes_in_group(
				"customer"
			)
		)

		var active_workers: int = 0

		var actors = get_node_or_null(
			"../Actors"
		)

		if actors != null:
			for actor in actors.get_children():
				if not actor.has_method(
					"request_shift_end"
				):
					continue

				if actor.visible:
					active_workers += 1

		print(
			"[심야 폐점 정리] 손님: ",
			customers.size(),
			" / 직원: ",
			active_workers
		)

		if (
			customers.is_empty()
			and active_workers == 0
		):
			print(
				"[심야 폐점] 모든 손님/직원 퇴장 완료"
			)
			return

		await get_tree().create_timer(
			0.25
		).timeout

func close_shop_for_night_and_settle():
	# 먼저 폐점 시작
	close_shop_for_night()

	# 직원들도 전부 퇴근
	send_all_workers_out()

	print(
		"[심야 폐점] 모든 인원 퇴장 대기"
	)

	# 손님 + 직원 모두 없어질 때까지 대기
	await wait_for_night_close_complete()

	# 모든 정리가 끝난 뒤 결산
	show_day_summary()

func fast_forward_to_morning():
	if fast_forwarding_to_morning:
		return

	fast_forwarding_to_morning = true

	# 일반 HourTimer는 정지
	hour_timer.stop()

	# 손님도 계속 생성 금지
	customer_spawner.set_shop_open(false)

	customer_spawner.process_mode = (
		Node.PROCESS_MODE_DISABLED
	)

	print("[심야] 아침까지 빠른 시간 진행 시작")

	while current_hour != 9:
		await get_tree().create_timer(
			night_fast_forward_delay
		).timeout

		current_hour += 1

		if current_hour >= 24:
			current_hour = 0

		current_period = get_period()

		hour_changed.emit(
			current_hour
		)

		update_time_ui()

		print(
			"[심야 배속] ",
			format_hour(current_hour)
		)

	# =========================
	# 09:00 도착
	# =========================
	fast_forwarding_to_morning = false

	night_closed = false
	shop_open = false
	closing_shop = false

	current_period = get_period()

	open_shop_button.visible = true

	update_time_ui()
	update_day_ui()

	period_changed.emit(
		current_period
	)

	print(
		"[다음 날] ",
		current_day,
		"일차 / 09:00 / 오픈 준비"
	)

func start_night_auto_operation():
	if night_auto_running:
		return

	night_auto_running = true
	night_closed = false

	# 현재 배속 기억
	saved_time_scale = Engine.time_scale

	# =========================
	# 플레이어 제거
	# =========================
	if is_instance_valid(player):
		player.velocity = Vector2.ZERO

		saved_player_collision_layer = (
			player.collision_layer
		)

		saved_player_collision_mask = (
			player.collision_mask
		)

		# 화면에서 숨김
		player.visible = false

		# 심야 자동영업 중 충돌하지 않게 함
		player.collision_layer = 0
		player.collision_mask = 0

		# 플레이어 조작 정지
		player.set_physics_process(false)
		player.set_process_input(false)
		player.set_process_unhandled_input(false)

	# B 건축모드 입력도 차단
	if is_instance_valid(build_manager):
		build_manager.set_process_unhandled_input(
			false
		)

	# =========================
	# 실제 게임 전체 배속
	# =========================
	Engine.time_scale = night_auto_time_scale

	update_time_ui()

	print(
		"[심야 자동영업] 시작 / ",
		night_auto_time_scale,
		"배속"
	)

func finish_night_auto_operation():
	if not night_auto_running:
		return

	night_auto_running = false

	# 원래 속도로 복구
	Engine.time_scale = saved_time_scale

	# =========================
	# 플레이어 복귀
	# =========================
	if is_instance_valid(player):
		player.collision_layer = (
			saved_player_collision_layer
		)

		player.collision_mask = (
			saved_player_collision_mask
		)

		player.visible = true

		player.set_physics_process(true)
		player.set_process_input(true)
		player.set_process_unhandled_input(true)

		player.velocity = Vector2.ZERO

	# 건축모드 B키 다시 허용
	if is_instance_valid(build_manager):
		build_manager.set_process_unhandled_input(
			true
		)

	update_time_ui()

	print(
		"[심야 자동영업] 종료 / 09:00"
	)

func enter_expedition_phase():
	print(
		"[원정] ",
		current_day,
		"일차 원정 단계 진입"
	)

	# 편의점 시간 정지
	hour_timer.stop()

	# 가게 영업 종료
	shop_open = false
	night_closed = false

	# 손님 생성 완전 중단
	if customer_spawner.has_method(
		"set_shop_open"
	):
		customer_spawner.set_shop_open(false)

	customer_spawner.process_mode = (
		Node.PROCESS_MODE_DISABLED
	)

	# 남아 있는 손님이 있다면 퇴장
	send_all_customers_out()

	# 직원도 퇴근
	send_all_workers_out()

	# 오픈 버튼 숨김
	if open_shop_button != null:
		open_shop_button.visible = false

	update_day_ui()
	update_time_ui()

	print("[원정] 편의점 영업 시스템 정지")


func _unhandled_input(event):
	if not event is InputEventKey:
		return

	if not event.pressed or event.echo:
		return



func get_day_name() -> String:
	match current_day:
		Weekday.MONDAY:
			return "월요일"

		Weekday.TUESDAY:
			return "화요일"

		Weekday.WEDNESDAY:
			return "수요일"

		Weekday.THURSDAY:
			return "목요일"

		Weekday.FRIDAY:
			return "금요일"

		Weekday.SATURDAY:
			return "토요일"

		Weekday.SUNDAY:
			return "일요일"

	return ""

func close_shop_for_expedition_and_settle():
	if closing_shop:
		return

	closing_shop = true

	print("[주간 영업 종료] 금요일 21:00")

	# 시간 정지
	hour_timer.stop()

	# ★ 가게 자체를 닫음
	# 이후 새 근무자가 출근하면 안 됨
	shop_open = false

	# 신규 손님 생성 중지
	if customer_spawner.has_method(
		"set_shop_open"
	):
		customer_spawner.set_shop_open(false)

	customer_spawner.process_mode = (
		Node.PROCESS_MODE_DISABLED
	)

	# 현재 손님 전부 퇴장
	send_all_customers_out()

	# 현재 직원 전부 퇴근
	send_all_workers_out()

	update_day_ui()

	await wait_for_night_close_complete()

	closing_shop = false

	print(
		"[주간 영업 종료] 모든 인원 퇴장 완료"
	)

	show_day_summary()

func enter_expedition_scene():
	print("[원정] 출발 준비")

	# =========================
	# 편의점 상태 저장
	# =========================
	if (
		build_manager != null
		and build_manager.has_method(
			"save_store_layout"
		)
	):
		build_manager.save_store_layout()

	# =========================
	# 플레이어 상태 저장
	# =========================
	if (
		player != null
		and player.has_method(
			"get_persistent_state"
		)
	):
		GameState.save_player_state(
			player.get_persistent_state()
		)

	# 토요일부터 원정 시작
	current_day = Weekday.SATURDAY
	GameState.current_day = current_day

	print(
		"[원정] 시작 요일: ",
		get_day_name()
	)

	get_tree().change_scene_to_file(
		"res://scenes/expedition.tscn"
	)
