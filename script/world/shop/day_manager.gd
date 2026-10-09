extends Node

# 편의점의 하루 흐름을 조정한다.
# 영업 시작·종료, 하루 경계(06:00) 정산, 원정 전환과 저장 가능 시점을 관리한다.
# 하루는 06:00에 시작해 다음 날 06:00에 정산하며, 영업 중에는 24시간 시간이 흐른다.


const CHECKPOINT_FILE_SERVICE_SCRIPT = preload(
	"res://script/core/persistence/checkpoint_file_service.gd"
)

var checkpoint_file_service = CHECKPOINT_FILE_SERVICE_SCRIPT.new()

enum GamePhase {
	SHOP,
	EXPEDITION
}

const Weekday = CalendarData.Weekday

signal shop_opened

var expedition_transition_pending := false
var shop_open: bool = false
var current_day: int = Weekday.FRIDAY
var current_phase: GamePhase = GamePhase.SHOP

var summary_open: bool = false
var closing_shop: bool = false
var first_settlement_done: bool = false

@onready var day_label: Label = $"../UI/HUD/DayLabel"
@onready var player = $"../Actors/Player"
@onready var customer_spawner = $"../CustomerSpawner"
@onready var day_summary_center: CenterContainer = $"../UI/DaySummaryCenter"
@onready var summary_text: Label = $"../UI/DaySummaryCenter/DaySummaryPanel/VBoxContainer/SummaryText"
@onready var next_day_button: Button = $"../UI/DaySummaryCenter/DaySummaryPanel/VBoxContainer/NextDayButton"
@onready var build_manager = $"../BuildManager"
@onready var save_status_label: Label = (
	$"../UI/HUD/SaveStatusLabel"
)

@onready var management_menu: Control = (
	$"../UI/ManagementMenu"
)

@onready var game_menu: GameMenu = (
	$"../UI/GameMenu"
)

var return_title_pending: bool = false

var save_status_remaining: float = 0.0

signal hour_changed(hour: int)
signal period_changed(period: String)

@export var current_hour: int = GameConfig.DAY_START_HOUR

@onready var open_shop_button: Button = (
	$"../UI/HUD/OpenShopButton"
)
@onready var hour_timer: Timer = $HourTimer
@onready var time_label: Label = $"../UI/HUD/TimeLabel"

var current_period: String = ""
var save_failure_reason: String = ""
var displayed_minute: int = 0
var pending_absence: Dictionary = {}

# =========================
# 초기화
# =========================

func _ready():
	# 정산창이 열린 상태에서도 버튼 입력을 받을 수 있도록 함
	process_mode = Node.PROCESS_MODE_ALWAYS
	day_summary_center.process_mode = Node.PROCESS_MODE_ALWAYS
	day_summary_center.visible = false

	next_day_button.text = "확인"
	next_day_button.pressed.connect(
		confirm_next_day
	)

	# GameState를 요일의 기준으로 사용
	current_day = GameState.current_day
	var return_context: Dictionary = GameState.get_meta("shop_return_context",{})
	current_hour = int(return_context.get("hour",GameConfig.DAY_START_HOUR))

	# 원정에서 돌아왔다면 자리를 비운 시간을 나중에 정산한다(_install_world_interactions 뒤).
	if float(return_context.get("expedition_seconds", 0.0)) > 0.0:
		pending_absence = return_context.duplicate(true)
	first_settlement_done = GameState.first_settlement_done

	hour_timer.process_mode = Node.PROCESS_MODE_PAUSABLE

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

	management_menu.visible = false

	if open_shop_button == null:
		push_error(
			"[DayManager] OpenShopButton이 연결되지 않았습니다."
		)
		return

	open_shop_button.visible = false
	open_shop_button.disabled = false
	open_shop_button.mouse_filter = Control.MOUSE_FILTER_STOP

	if not open_shop_button.pressed.is_connected(
		open_shop
	):
		open_shop_button.pressed.connect(
			open_shop
		)

	update_time_ui()

	save_status_label.hide()

	call_deferred(
		"_setup_common_game_menu"
	)
	call_deferred("_install_world_interactions")
	call_deferred("_settle_expedition_absence")

# =========================
# 영업 종료와 일일 정산
# =========================

func request_day_end():
	# 영업일이면 정산창 표시
	if current_phase == GamePhase.SHOP:
		end_shop_day()
		return

	# 원정일은 아직 시스템이 없으므로
	# 테스트에서는 바로 다음 날로 진행
	advance_to_next_day()


func end_shop_day() -> void:
	if summary_open or closing_shop:
		return

	if current_phase != GamePhase.SHOP:
		return


	await close_shop_for_day_end_and_settle()


func show_day_summary():
	if summary_open:
		return

	var stats: Dictionary = (
		player.get_daily_shop_stats()
	)

	var active_event_ids: Array[String] = []

	var active_events: Array[Dictionary] = (
		StoreEventData.get_active_events(
			GameState.total_day
		)
	)

	for event_data in active_events:
		var event_id: String = str(
			event_data.get(
				"event_id",
				""
			)
		)

		if not event_id.is_empty():
			active_event_ids.append(
				event_id
			)

	stats["active_event_ids"] = (
		active_event_ids
	)


	GameState.record_daily_shop_result(
		GameState.total_day,
		current_day,
		stats
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

	var visitor_counts: Dictionary = stats.get(
		"visitors_by_customer_type",
		{}
	)

	var sold_items: Dictionary = stats.get(
		"sold_items",
		{}
	)

	var unmet_demand: Dictionary = stats.get(
		"unmet_demand",
		{}
	)

	var most_frequent_customer_text: String = (
		get_most_frequent_customer_text(
			visitor_counts
		)
	)

	var best_selling_item_text: String = (
		get_highest_item_count_text(
			sold_items,
			"판매 기록 없음"
		)
	)

	var most_unmet_item_text: String = (
		get_highest_item_count_text(
			unmet_demand,
			"놓친 수요 없음"
		)
	)


	var purchase_rate: float = 0.0

	if visitors > 0:
		purchase_rate = (
			float(sales)
			/ float(visitors)
			* 100.0
		)

	var settlement_period: String = "06:00 ~ 익일 06:00"

	summary_text.text = (
		CalendarData.get_display_date(
			GameState.total_day
		)
		+ " / "
		+ get_day_name()
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
		+ "\n\n가장 많이 방문한 손님: "
		+ most_frequent_customer_text
		+ "\n가장 많이 팔린 상품: "
		+ best_selling_item_text
		+ "\n가장 많이 놓친 수요: "
		+ most_unmet_item_text
	)

	summary_open = true
	day_summary_center.visible = true

	# 결산 확인 전까지 전체 게임 정지
	get_tree().paused = true

func confirm_next_day():
	if not summary_open:
		return

	summary_open = false
	day_summary_center.visible = false

	get_tree().paused = false

	first_settlement_done = true
	GameState.first_settlement_done = true


	# =========================
	# 모든 요일에 동일하게 다음 영업일로 진행
	# =========================
	advance_to_next_day()

	# 다음 날 06:00에 시간이 멈춘 채로 정비(건축·근무표·저장) 후 영업을 시작한다.
	update_time_ui()


func advance_to_next_day() -> void:
	current_day = (
		GameState.advance_calendar_day()
	)

	update_phase()

	player.reset_shop_stats()

	apply_phase()
	update_day_ui()

func update_phase():
	current_phase = GamePhase.SHOP


func apply_phase() -> void:
	var can_spawn: bool = (
		current_phase == GamePhase.SHOP
		and shop_open
		and not closing_shop
		and not summary_open
	)

	if can_spawn:
		customer_spawner.process_mode = Node.PROCESS_MODE_INHERIT
		customer_spawner.set_shop_open(true)
	else:
		customer_spawner.set_shop_open(false)
		customer_spawner.process_mode = Node.PROCESS_MODE_DISABLED


func get_phase_name() -> String:
	if current_phase == GamePhase.SHOP:
		return "영업"

	return "원정"


func update_day_ui():
	if day_label == null:
		return
	day_label.text = CalendarData.get_display_date(GameState.total_day) + "\n" + get_day_name() + " · " + ("폐점 정리" if closing_shop else get_phase_name())


func wait_for_customers_to_leave():
	while true:
		var customers: Array = (
			get_tree().get_nodes_in_group("customer")
		)

		if customers.is_empty():
			return

		await get_tree().create_timer(
			0.25
		).timeout



# =========================
# 시간과 영업 상태
# =========================

func get_period() -> String:
	return EmployeeData.get_period_at_hour(current_hour)


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



func update_time_ui():
	if time_label == null:
		return

	if current_phase == GamePhase.EXPEDITION:
		time_label.text = "원정 기간"
		return

	time_label.text = (
		format_hour(current_hour, get_display_minute())
		+ " / "
		+ get_period_name()
	)


# 시계가 흐르는 동안 이번 시(時)의 앞 절반은 :00, 뒤 절반은 :30으로 보여 준다(30분 단위).
func get_display_minute() -> int:
	if hour_timer == null or hour_timer.is_stopped():
		return 0

	if hour_timer.wait_time <= 0.0:
		return 0

	var elapsed_ratio: float = (
		1.0 - hour_timer.time_left / hour_timer.wait_time
	)

	return 30 if elapsed_ratio >= 0.5 else 0


func format_hour(hour: int, minute: int = 0) -> String:
	return "%02d:%02d" % [hour, minute]


func _on_hour_timer_timeout():
	if (
		return_title_pending
		or closing_shop
		or summary_open
	):
		return
	var old_period: String = get_period()

	current_hour += 1

	if current_hour >= 24:
		current_hour = 0

	var new_period: String = get_period()

	# 하루 경계(06:00): 정산하고 시간을 멈춘 채 다음 날 정비로 들어간다.
	if current_hour == GameConfig.DAY_START_HOUR:
		await end_shop_day()

	hour_changed.emit(
		current_hour
	)

	if old_period != new_period:
		current_period = new_period

		period_changed.emit(
			new_period
		)

	update_time_ui()


func open_shop():

	if shop_open or closing_shop or summary_open:
		return

	if not can_open_shop():
		return

	shop_open = true

	open_shop_button.visible = false

	customer_spawner.process_mode = (
		Node.PROCESS_MODE_INHERIT
	)

	customer_spawner.set_shop_open(true)

	# 재개점으로 시계의 진행률을 초기화하지 않는다.
	if hour_timer.is_stopped():
		hour_timer.start()

	shop_opened.emit()

	update_time_ui()


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
		return false

	if not has_register:
		return false

	return true

# =========================
# 인원 정리
# =========================

func send_all_customers_out():
	var customers: Array = (
		get_tree().get_nodes_in_group(
			"customer"
		)
	)

	for customer in customers:
		if not is_instance_valid(customer):
			continue

		if customer.has_method("go_to_exit"):
			customer.go_to_exit()

func send_all_workers_out():
	var actors = get_node_or_null(
		"../Actors"
	)

	if actors == null:
		return

	for actor in actors.get_children():
		# Worker가 아닌 Player 등 제외
		if not actor.has_method(
			"request_shift_end"
		):
			continue

		# 이미 퇴근한 직원은 제외
		if not actor.visible:
			continue

		actor.request_shift_end()


func wait_for_shop_close_complete():
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

		if (
			customers.is_empty()
			and active_workers == 0
		):
			return

		await get_tree().create_timer(
			0.25
		).timeout

func close_shop_for_day_end_and_settle() -> void:
	if summary_open or closing_shop:
		return

	closing_shop = true
	shop_open = false

	# 06:00에서 시간 정지
	hour_timer.stop()

	# 신규 손님 생성 종료, 기존 손님·직원 퇴장
	customer_spawner.set_shop_open(false)
	customer_spawner.process_mode = Node.PROCESS_MODE_DISABLED
	send_all_customers_out()
	send_all_workers_out()

	update_day_ui()
	update_time_ui()

	await wait_for_shop_close_complete()

	show_day_summary()

	closing_shop = false
	update_day_ui()


func enter_expedition_phase():
	# 편의점 시간 정지
	hour_timer.stop()

	# 가게 영업 종료
	shop_open = false

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

# =========================
# 원정 전환과 저장
# =========================

func _unhandled_input(event):
	if return_title_pending:
		return
	if not event is InputEventKey:
		return

	if not event.pressed or event.echo:
		return

	if event.keycode == KEY_F5:
		var saved: bool = save_preparation_checkpoint()

		if saved:
			show_save_status(
				"퀵 세이브 완료",
				true
			)
		else:
			show_save_status(
				save_failure_reason,
				false
			)

		get_viewport().set_input_as_handled()



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

	await wait_for_shop_close_complete()

	closing_shop = false

	show_day_summary()

func enter_expedition_scene():
	if expedition_transition_pending: return
	if closing_shop or summary_open:
		return

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

	expedition_transition_pending = true
	GameState.set_meta("shop_return_context",{
		"hour":current_hour,
		"minute":get_display_minute(),
		"was_open":shop_open,
		"expedition_seconds":0.0,
		"stats":player.get_daily_shop_stats(),
		"position":[player.global_position.x,player.global_position.y]
	})
	GameState.set_meta("shop_expedition_prep",true)
	close_shop_manually()

	# SceneTree removes the current scene immediately. Defer until the triggering
	# player's input callback has consumed its event and returned.
	call_deferred("_commit_expedition_scene_change")

func _commit_expedition_scene_change() -> void:
	if not expedition_transition_pending or not is_inside_tree(): return
	var scene_error: Error = (
		get_tree().change_scene_to_file(
			GameConfig.EXPEDITION_SCENE_PATH
		)
	)

	if scene_error != OK:
		expedition_transition_pending = false
		GameState.remove_meta("shop_expedition_prep")
		var interactions = get_parent().get_node_or_null("WorldInteractions")
		if interactions: interactions.show_message("던전 장면을 불러오지 못했습니다. 다시 시도해주세요.")
		push_error(
			"[원정] 씬 전환에 실패했습니다: "
			+ str(scene_error)
		)

func save_preparation_checkpoint(
	target_path: String = GameState.SAVE_PATH
) -> bool:
	save_failure_reason = ""

	if current_phase != GamePhase.SHOP:
		save_failure_reason = "원정 중에는 저장할 수 없습니다."
		return false

	if (
		current_hour != GameConfig.DAY_START_HOUR
		or shop_open
		or summary_open
		or closing_shop
	):
		save_failure_reason = "오전 9시 오픈 준비 중에 저장할 수 있습니다."
		return false

	if not is_instance_valid(build_manager):
		save_failure_reason = "저장에 필요한 정보를 찾지 못했습니다."
		return false

	if (
		build_manager.build_mode
		or build_manager.build_move_service.is_active()
	):
		save_failure_reason = "건축 배치를 먼저 확정해주세요."
		return false

	if get_tree().paused:
		save_failure_reason = "열린 창을 닫은 뒤 저장해주세요."
		return false

	if not get_tree().get_nodes_in_group("customer").is_empty():
		save_failure_reason = "손님이 모두 퇴장한 뒤 저장해주세요."
		return false

	var actors_node: Node = get_node_or_null("../Actors")

	if actors_node == null:
		save_failure_reason = "저장에 필요한 정보를 찾지 못했습니다."
		return false

	for actor in actors_node.get_children():
		if not actor.has_method("request_shift_end"):
			continue

		if actor.visible or actor.on_duty or actor.shift_ending:
			save_failure_reason = "직원이 모두 퇴근한 뒤 저장해주세요."
			return false

	build_manager.save_store_layout()

	GameState.current_day = current_day
	GameState.first_settlement_done = first_settlement_done

	if is_instance_valid(player):
		GameState.save_player_state(
			player.get_persistent_state()
		)

	# 편의점에서 만든 저장은 편의점으로 불러온다.
	GameState.clear_expedition_checkpoint()

	var data: Dictionary = GameState.create_save_data()

	var save_result: Dictionary = (
		checkpoint_file_service.write_verified_checkpoint(
			data,
			target_path
		)
	)

	if not bool(save_result.get("success", false)):
		save_failure_reason = str(
			save_result.get(
				"message",
				"저장 파일을 만들지 못했습니다."
			)
		)
		return false

	return true

func show_save_status(
	message: String,
	success: bool
) -> void:
	save_status_label.text = message

	if success:
		save_status_label.modulate = Color(
			0.6,
			1.0,
			0.6
		)
	else:
		save_status_label.modulate = Color(
			1.0,
			0.75,
			0.4
		)

	save_status_remaining = 3.0
	save_status_label.show()

func _process(delta: float) -> void:
	var minute: int = get_display_minute()

	if minute != displayed_minute:
		displayed_minute = minute
		update_time_ui()

	if save_status_remaining <= 0.0:
		return

	save_status_remaining = maxf(
		save_status_remaining - delta,
		0.0
	)

	if save_status_remaining <= 0.0:
		save_status_label.hide()


func _on_management_button_pressed() -> void:
	if not is_instance_valid(
		management_menu
	):
		return

	if management_menu.has_method(
		"open_menu"
	):
		management_menu.call(
			"open_menu"
		)

func _on_info_button_pressed() -> void:
	if not is_instance_valid(
		management_menu
	):
		return

	if not management_menu.has_method(
		"open_menu"
	):
		push_warning(
			"[정보] 관리 메뉴를 열 수 없습니다."
		)
		return

	management_menu.call(
		"open_menu",
		ManagementTabs.MenuTab.HISTORY
	)

# =========================
# 정산 표시용 집계
# =========================

func get_most_frequent_customer_text(
	visitor_counts: Dictionary
) -> String:
	if visitor_counts.is_empty():
		return "기록 없음"

	var highest_count: int = 0
	var highest_type_names: Array[String] = []

	for raw_customer_type_id in visitor_counts.keys():
		var customer_type_id: String = str(
			raw_customer_type_id
		)

		var visitor_count: int = int(
			visitor_counts.get(
				customer_type_id,
				0
			)
		)

		if visitor_count <= 0:
			continue

		var display_name: String = (
			CustomerTypeData.get_display_name(
				customer_type_id
			)
		)

		if visitor_count > highest_count:
			highest_count = visitor_count

			highest_type_names.clear()
			highest_type_names.append(
				display_name
			)

		elif visitor_count == highest_count:
			highest_type_names.append(
				display_name
			)

	if highest_type_names.is_empty():
		return "기록 없음"

	return (
		", ".join(highest_type_names)
		+ " ("
		+ str(highest_count)
		+ "명)"
	)

func get_highest_item_count_text(
	item_counts: Dictionary,
	empty_text: String
) -> String:
	if item_counts.is_empty():
		return empty_text

	var highest_count: int = 0
	var highest_item_names: Array[String] = []

	for raw_item_id in item_counts.keys():
		var item_id: String = str(
			raw_item_id
		)

		var item_count: int = int(
			item_counts.get(
				item_id,
				0
			)
		)

		if item_count <= 0:
			continue

		var item_name: String = (
			ItemData.get_item_name(
				item_id
			)
		)

		if item_count > highest_count:
			highest_count = item_count

			highest_item_names.clear()
			highest_item_names.append(
				item_name
			)

		elif item_count == highest_count:
			highest_item_names.append(
				item_name
			)

	if highest_item_names.is_empty():
		return empty_text

	return (
		", ".join(highest_item_names)
		+ " ("
		+ str(highest_count)
		+ "개)"
	)

func _on_game_menu_save_slot_requested(
	path: String,
	slot_index: int
) -> void:
	var success: bool = (
		save_preparation_checkpoint(
			path
		)
	)

	game_menu.notify_save_finished(
		success
	)

	if success:
		show_save_status(
			"세이브 슬롯 "
			+ str(slot_index + 1)
			+ " 저장 완료",
			true
		)
	else:
		show_save_status(
			save_failure_reason,
			false
		)

func _on_game_menu_return_title_requested() -> void:
	if (
		summary_open
		or closing_shop
	):
		show_save_status(
			"정산을 마친 뒤 돌아갈 수 있습니다.",
			false
		)
		return

	if is_instance_valid(build_manager):
		if (
			build_manager.build_mode
			or build_manager.build_move_service.is_active()
		):
			show_save_status(
				"건축 배치를 먼저 확정해주세요.",
				false
			)
			return

	if get_tree().paused:
		show_save_status(
			"열린 창을 닫은 뒤 돌아가주세요.",
			false
		)
		return

	return_title_pending = true

	var scene_tree: SceneTree = get_tree()

	var scene_error: Error = (
		scene_tree.change_scene_to_file(
			GameConfig.TITLE_SCENE_PATH
		)
	)

	if scene_error != OK:
		return_title_pending = false

		show_save_status(
			"시작 화면을 열지 못했습니다.",
			false
		)

		push_error(
			"[시작 화면 복귀] 씬 전환 실패: "
			+ str(scene_error)
		)
		return

	scene_tree.paused = false

func _setup_common_game_menu() -> void:
	if not is_instance_valid(game_menu):
		push_error(
			"[공통 메뉴] GameMenu를 찾지 못했습니다."
		)
		return

	game_menu.build_action_enabled = true
	game_menu.info_button.text = "건설"
	if not game_menu.build_requested.is_connected(build_manager.start_build_mode):
		game_menu.build_requested.connect(build_manager.start_build_mode)

	if not game_menu.management_requested.is_connected(
		_on_management_button_pressed
	):
		game_menu.management_requested.connect(
			_on_management_button_pressed
		)

	if not game_menu.info_requested.is_connected(
		_on_info_button_pressed
	):
		game_menu.info_requested.connect(
			_on_info_button_pressed
		)

	if not game_menu.save_slot_requested.is_connected(
		_on_game_menu_save_slot_requested
	):
		game_menu.save_slot_requested.connect(
			_on_game_menu_save_slot_requested
		)

	if not game_menu.return_title_requested.is_connected(
		_on_game_menu_return_title_requested
	):
		game_menu.return_title_requested.connect(
			_on_game_menu_return_title_requested
		)

# Manual door closure is not a day-end settlement and never changes the date.
func close_shop_manually() -> void:
	shop_open = false
	# 문 닫기는 입장만 막는다. 정산 전까지 하루의 시계는 계속 흐른다.
	customer_spawner.set_shop_open(false)
	customer_spawner.process_mode = Node.PROCESS_MODE_DISABLED
	send_all_customers_out()
	open_shop_button.hide()
	update_day_ui()
	update_time_ui()

func toggle_shop_at_door() -> String:
	if closing_shop or summary_open:
		return "현재 정산 중입니다. 잠시 기다려주세요."
	if shop_open:
		close_shop_manually()
		return "영업을 마쳤습니다. 남은 손님들이 퇴장합니다."
	if not can_open_shop():
		return "출입문과 계산대를 설치한 뒤 영업할 수 있습니다."
	open_shop()
	return "가게를 열었습니다. 손님을 맞이하세요."

func _install_world_interactions() -> void:
	var interaction = preload("res://script/world/shop/world_interactions.gd").new()
	interaction.name = "WorldInteractions"
	get_parent().add_child(interaction)
	var fishing = preload("res://script/world/shop/fishing/fishing_director.gd").new()
	fishing.name = "FishingDirector"
	get_parent().add_child(fishing)
	var context: Dictionary = GameState.get_meta("shop_return_context",{})
	var return_position: Array = context.get("position",[])
	if return_position.size() == 2:
		player.global_position = Vector2(float(return_position[0]),float(return_position[1]))
	var stats: Dictionary = context.get("stats",{})
	if not stats.is_empty():
		player.total_visitors = int(stats.get("visitors",0))
		player.successful_sales = int(stats.get("sales",0))
		player.missed_sales = int(stats.get("missed",0))
		player.daily_revenue = int(stats.get("revenue",0))
		player.daily_visitors_by_customer_type = stats.get("visitors_by_customer_type",{}).duplicate(true)
		player.daily_sold_items = stats.get("sold_items",{}).duplicate(true)
		player.daily_unmet_demand = stats.get("unmet_demand",{}).duplicate(true)
		player.update_shop_stats_ui()
	if GameState.has_meta("shop_return_context"): GameState.remove_meta("shop_return_context")


# =========================
# 원정 중 자리를 비운 시간 정산
# =========================

# 원정 안에서는 상점 시간이 GameConfig.EXPEDITION_TIME_SCALE 배율로 흐른다.
# 돌아오면 그 시간만큼 시각을 흘리고, 영업 중이었다면 그동안의 손님·판매를 계산한다.
# 하루 경계(06:00)를 넘으면 06:00까지만 계산하고 정산 화면을 띄운다(남은 시간은 버림).
func _settle_expedition_absence() -> void:
	if pending_absence.is_empty():
		return

	var context: Dictionary = pending_absence
	pending_absence = {}

	var seconds: float = float(context.get("expedition_seconds", 0.0))

	if seconds <= 0.0 or hour_timer.wait_time <= 0.0:
		return

	var hours: float = (
		seconds
		* GameConfig.EXPEDITION_TIME_SCALE
		/ hour_timer.wait_time
	)

	var start_hour: int = current_hour
	var until_boundary: int = posmod(
		GameConfig.DAY_START_HOUR - start_hour,
		24
	)

	if until_boundary == 0:
		until_boundary = 24

	var crossed_boundary: bool = hours >= float(until_boundary)
	var simulated_hours: float = minf(hours, float(until_boundary))

	var result: Dictionary = {}

	if bool(context.get("was_open", false)):
		result = ShopOfflineSimulator.simulate(
			get_tree(),
			player,
			start_hour,
			simulated_hours
		)

	if crossed_boundary:
		current_hour = GameConfig.DAY_START_HOUR
	else:
		current_hour = (
			start_hour + int(floor(simulated_hours))
		) % 24

	current_period = get_period()

	hour_changed.emit(current_hour)
	period_changed.emit(current_period)
	update_time_ui()

	_show_absence_result(result, simulated_hours, crossed_boundary, bool(context.get("was_open", false)))

	if crossed_boundary:
		await end_shop_day()


func _show_absence_result(
	result: Dictionary,
	simulated_hours: float,
	crossed_boundary: bool,
	was_open: bool
) -> void:
	var text: String = "원정에서 돌아왔습니다.\n\n"

	if was_open:
		text += ShopOfflineSimulator.format_summary(
			result,
			simulated_hours
		)
	else:
		text += "가게를 닫고 나갔기 때문에 손님이 오지 않았습니다.\n(자리를 비운 시간: 약 %.1f시간)" % simulated_hours

	if crossed_boundary:
		text += "\n\n하루가 지나 정산합니다."

	var dialog := AcceptDialog.new()
	dialog.title = "자리를 비운 동안"
	dialog.dialog_text = text
	dialog.process_mode = Node.PROCESS_MODE_ALWAYS

	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)

	get_parent().get_node("UI").add_child(dialog)
	dialog.popup_centered()
