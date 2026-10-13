class_name ManagementMenu
extends Control
const PRESENTATION = preload("res://script/ui/management/management_presentation.gd")

# 관리 메뉴의 탭 전환과 공통 정보 표시를 담당한다.
# 인벤토리·생산·직원·설계도 화면의 세부 동작은 각 하위 씬에 위임한다.


const MenuTab = ManagementTabs.MenuTab
const InfoTab = ManagementTabs.InfoTab

var current_info_tab: ManagementTabs.InfoTab = ManagementTabs.InfoTab.BASIC

@onready var info_tab_bar: HBoxContainer = (
	$DimBackground/CenterContainer/MainPanel/MainVBox/Body/ContentArea/HistoryContent/MarginContainer/HistoryVBox/InfoTabBar
)

@onready var basic_info_button: Button = (
	info_tab_bar.get_node("BasicInfoButton")
)

@onready var detail_info_button: Button = (
	info_tab_bar.get_node("DetailInfoButton")
)

@onready var sales_trend_button: Button = (
	info_tab_bar.get_node("SalesTrendButton")
)

@onready var extra_record_button: Button = (
	info_tab_bar.get_node("ExtraRecordButton")
)


@onready var inventory_button: Button = (
	$DimBackground/CenterContainer/MainPanel/MainVBox/Body/Navigation/InventoryButton
)

@onready var production_button: Button = (
	$DimBackground/CenterContainer/MainPanel/MainVBox/Body/Navigation/ProductionButton
)

@onready var employee_button: Button = (
	$DimBackground/CenterContainer/MainPanel/MainVBox/Body/Navigation/EmployeeButton
)

@onready var blueprint_button: Button = (
	$DimBackground/CenterContainer/MainPanel/MainVBox/Body/Navigation/BlueprintButton
)

@onready var close_button: Button = (
	$DimBackground/CenterContainer/MainPanel/MainVBox/Header/HeaderMargin/HeaderRow/CloseButton
)

@onready var schedule_button: Button = (
	$DimBackground/CenterContainer/MainPanel/MainVBox/Body/Navigation/ScheduleButton
)

@onready var inventory_content: Control = (
	$DimBackground/CenterContainer/MainPanel/MainVBox/Body/ContentArea/InventoryContent
)

@onready var production_content: Control = (
	$DimBackground/CenterContainer/MainPanel/MainVBox/Body/ContentArea/ProductionContent
)

@onready var employee_content: Control = (
	$DimBackground/CenterContainer/MainPanel/MainVBox/Body/ContentArea/EmployeeContent
)

@onready var blueprint_content: Control = (
	$DimBackground/CenterContainer/MainPanel/MainVBox/Body/ContentArea/BlueprintContent
)

@onready var history_button: Button = (
	$DimBackground/CenterContainer/MainPanel/MainVBox/Body/Navigation/HistoryButton
)

@onready var history_content: Control = (
	$DimBackground/CenterContainer/MainPanel/MainVBox/Body/ContentArea/HistoryContent
)

@onready var history_title_label: Label = (
	$DimBackground/CenterContainer/MainPanel/MainVBox/Body/ContentArea/HistoryContent/MarginContainer/HistoryVBox/HistoryTitleLabel
)

@onready var history_list: VBoxContainer = (
	$DimBackground/CenterContainer/MainPanel/MainVBox/Body/ContentArea/HistoryContent/MarginContainer/HistoryVBox/HistoryScroll/HistoryList
)

@onready var construction_button: Button = (
	$DimBackground/CenterContainer/MainPanel/MainVBox/Body/Navigation/ConstructionButton
)

@onready var construction_content: Control = (
	$DimBackground/CenterContainer/MainPanel/MainVBox/Body/ContentArea/ConstructionContent
)

@onready var money_label: Label = (
	$DimBackground/CenterContainer/MainPanel/MainVBox/Footer/FooterMargin/FooterRow/MoneyLabel
)

@onready var info_label: Label = (
	$DimBackground/CenterContainer/MainPanel/MainVBox/Footer/FooterMargin/FooterRow/InfoLabel
)

@onready var management_inventory = (
	$DimBackground/CenterContainer/MainPanel/MainVBox/Body/ContentArea/InventoryContent/ManagementInventory
)

@onready var management_production: Control = (
	$DimBackground/CenterContainer/MainPanel/MainVBox/Body/ContentArea/ProductionContent/ManagementProduction
)

@onready var schedule_content: Control = (
	$DimBackground/CenterContainer/MainPanel/MainVBox/Body/ContentArea/ScheduleContent
)

@onready var schedule_current_date_label: Label = (
	$DimBackground/CenterContainer/MainPanel/MainVBox/Body/ContentArea/ScheduleContent/MarginContainer/ScheduleVBox/CurrentDateLabel
)

@onready var schedule_list: VBoxContainer = (
	$DimBackground/CenterContainer/MainPanel/MainVBox/Body/ContentArea/ScheduleContent/MarginContainer/ScheduleVBox/ScheduleScroll/ScheduleList
)


var current_tab: MenuTab = MenuTab.INVENTORY
var _paused_by_menu: bool = false
var space_menu: ShopSpaceMenu
var request_button: Button
var request_content: Control
var request_list: VBoxContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	RequestNotebookTab.install(self)
	space_menu = ShopSpaceMenu.new()
	add_child(space_menu)
	inventory_button.pressed.connect(
		select_tab.bind(
			MenuTab.INVENTORY
		)
	)

	production_button.pressed.connect(
		select_tab.bind(
			MenuTab.PRODUCTION
		)
	)

	employee_button.pressed.connect(
		select_tab.bind(
			MenuTab.EMPLOYEE
		)
	)

	blueprint_button.pressed.connect(
		select_tab.bind(
			MenuTab.BLUEPRINT
		)
	)

	construction_button.pressed.connect(
		select_tab.bind(
			MenuTab.CONSTRUCTION
		)
	)

	if construction_content.has_signal(
		"expansion_completed"
	):
		construction_content.expansion_completed.connect(
			_on_construction_expansion_completed
		)

	schedule_button.pressed.connect(
		select_tab.bind(
			MenuTab.SCHEDULE
		)
	)

	history_button.pressed.connect(
		select_tab.bind(
			MenuTab.HISTORY
		)
	)

	close_button.pressed.connect(
		close_menu
	)

	select_tab(
		MenuTab.INVENTORY
	)

	basic_info_button.pressed.connect(
		select_info_tab.bind(InfoTab.BASIC)
	)

	detail_info_button.pressed.connect(
		select_info_tab.bind(InfoTab.DETAIL)
	)

	sales_trend_button.pressed.connect(
		select_info_tab.bind(InfoTab.TREND)
	)

	extra_record_button.pressed.connect(
		select_info_tab.bind(InfoTab.RECORD)
	)

	ActFourBookView.install(self)
	PRESENTATION.install(self)
	visible = false


func open_menu(
	tab: MenuTab = MenuTab.INVENTORY
) -> void:
	if visible and not bool(get_meta("book_closing", false)):
		return

	visible = true
	get_tree().call_group("tutorial_director","hide_panel_for_menu")  # 책에 가리지 않도록 안내 패널을 숨긴다
	PRESENTATION.play_open(self)

	get_tree().call_group(
		"build_manager",
		"set_management_input_blocked",
		true
	)

	select_tab(tab)
	refresh_common_info()

	if not get_tree().paused:
		get_tree().paused = true
		_paused_by_menu = true
	else:
		_paused_by_menu = false

	DebugLog.write("[관리 메뉴] 열기")


func close_menu() -> void:
	if not visible or bool(get_meta("book_closing", false)):
		return

	if not PRESENTATION.play_close(self):
		visible = false

	get_tree().call_group(
		"build_manager",
		"set_management_input_blocked",
		false
	)

	if _paused_by_menu:
		get_tree().paused = false
		_paused_by_menu = false

	DebugLog.write("[관리 메뉴] 닫기")


func select_tab(
	tab: MenuTab
) -> void:
	if space_menu != null and not space_menu.tab_available(int(tab)):
		tab = MenuTab.INVENTORY
	current_tab = tab
	PRESENTATION.apply_tab(self)

	# 모든 내용 숨김
	inventory_content.visible = false
	production_content.visible = false
	employee_content.visible = false
	blueprint_content.visible = false
	schedule_content.visible = false
	history_content.visible = false
	construction_content.visible = false
	request_content.visible = false

	# 본문 상태와 포스트잇의 쪽 위치는 별도로 표시한다.
	inventory_button.button_pressed = false
	production_button.button_pressed = false
	employee_button.button_pressed = false
	blueprint_button.button_pressed = false
	schedule_button.button_pressed = false
	history_button.button_pressed = false
	construction_button.button_pressed = false
	request_button.button_pressed = false

	match tab:
		MenuTab.INVENTORY:
			inventory_content.visible = true
			inventory_button.button_pressed = true

			info_label.text = (
				UiText.t("management.tab.inventory.desc")
			)

			management_inventory.refresh_inventory_if_changed()

		MenuTab.PRODUCTION:
			production_content.visible = true
			production_button.button_pressed = true
			info_label.text = UiText.t("management.tab.production.desc")
			if management_production.has_method(
				"refresh_view"
			):
				management_production.refresh_view()


		MenuTab.EMPLOYEE:
			employee_content.visible = true
			employee_button.button_pressed = true

			info_label.text = (
				UiText.t("management.tab.employee.desc")
			)

			if employee_content.has_method("refresh_view"):
				employee_content.call("refresh_view")


		MenuTab.BLUEPRINT:
			blueprint_content.visible = true
			blueprint_button.button_pressed = true

			info_label.text = (
				UiText.t("management.tab.blueprint.desc")
			)

			if blueprint_content.has_method("refresh_view"):
				blueprint_content.call("refresh_view")

		MenuTab.CONSTRUCTION:
			construction_content.visible = true
			construction_button.button_pressed = true

			info_label.text = (
				UiText.t("management.tab.construction.desc")
			)

			if construction_content.has_method(
				"refresh_view"
			):
				construction_content.call(
					"refresh_view"
				)

		MenuTab.SCHEDULE:
			schedule_content.visible = true
			schedule_button.button_pressed = true
			refresh_schedule()


			info_label.text = (
				UiText.t("management.tab.schedule.desc")
			)


		MenuTab.HISTORY:
			history_content.visible = true
			history_button.button_pressed = true

			refresh_shop_history()

			info_label.text = (
				UiText.t("management.tab.history.desc")
			)

		MenuTab.REQUESTS:
			request_content.visible = true
			request_button.button_pressed = true
			info_label.text = ""
			RequestNotebookTab.refresh(self)


func refresh_common_info() -> void:
	money_label.text = (
		"소지금: "
		+ str(
			GameState.get_money()
		)
		+ " G"
	)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("management_menu"):
		if visible and not bool(get_meta("book_closing", false)):
			close_menu()
		else:
			open_menu(current_tab)

		get_viewport().set_input_as_handled()
		return

	if visible and not bool(get_meta("book_closing", false)) and event.is_action_pressed("ui_cancel"):
		close_menu()
		get_viewport().set_input_as_handled()

func refresh_schedule() -> void:
	for child in schedule_list.get_children():
		schedule_list.remove_child(child)
		child.queue_free()
	ActFourBookView.add_schedule(self)

	schedule_current_date_label.text = (
		"현재 날짜: "
		+ CalendarData.get_display_date(
			GameState.total_day
		)
	)

	var discovered_ids: Array[String] = (
		GameState.get_discovered_store_event_ids()
	)

	var discovered_events: Array[Dictionary] = []

	for event_id in discovered_ids:
		var event_data: Dictionary = (
			StoreEventData.get_event_occurrence(
				event_id, GameState.get_store_event_discovery_day(event_id)
			)
		)

		if event_data.is_empty():
			continue

		# 마무리된 이야기도 남겨 실제 영업 기록과 함께 돌아본다.
		event_data["discovery_day"] = (
			GameState.get_store_event_discovery_day(
				event_id
			)
		)

		discovered_events.append(
			event_data
		)

	discovered_events.sort_custom(
		_sort_events_by_start_day
	)

	if discovered_events.is_empty():
		var empty_label := Label.new()

		empty_label.text = "아직 들은 행사 소식이 없습니다."
		empty_label.add_theme_font_size_override("font_size", UiTypography.SMALL_SIZE)

		empty_label.horizontal_alignment = (
			HORIZONTAL_ALIGNMENT_CENTER
		)

		empty_label.autowrap_mode = (
			TextServer.AUTOWRAP_WORD_SMART
		)

		schedule_list.add_child(
			empty_label
		)

		return

	for kind in ["common", "seasonal"]:
		var entries: Array[Dictionary] = []
		for event in discovered_events:
			if str(event.get("event_kind", "common")) == kind: entries.append(event)
		if entries.is_empty(): continue
		var heading := Label.new()
		heading.text = "공용 이벤트" if kind == "common" else "계절 이벤트"
		heading.add_theme_font_size_override("font_size", UiTypography.size(20))
		schedule_list.add_child(heading)
		for event in entries: _create_schedule_entry(event)


func _sort_events_by_start_day(
	event_a: Dictionary,
	event_b: Dictionary
) -> bool:
	return (
		int(event_a.get("start_day", 0))
		< int(event_b.get("start_day", 0))
	)


func _create_schedule_entry(
	event_data: Dictionary
) -> void:
	var event_id := str(event_data.get("event_id", ""))
	var start_day := int(event_data.get("start_day", 0))
	var end_day := int(event_data.get("end_day", 0))

	var event_panel := PanelContainer.new()

	event_panel.custom_minimum_size = Vector2(
		0,
		150
	)

	event_panel.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)

	var margin := MarginContainer.new()

	margin.add_theme_constant_override(
		"margin_left",
		16
	)

	margin.add_theme_constant_override(
		"margin_top",
		12
	)

	margin.add_theme_constant_override(
		"margin_right",
		16
	)

	margin.add_theme_constant_override(
		"margin_bottom",
		12
	)

	event_panel.add_child(
		margin
	)

	var label := Label.new()

	label.autowrap_mode = (
		TextServer.AUTOWRAP_WORD_SMART
	)

	label.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)

	label.text = StoreEventStory.note_text(event_data, GameState.total_day)

	if GameState.total_day > end_day:
		label.text += (
			"\n\n[그 무렵의 영업 기록]\n"
			+ get_schedule_result_text(
				event_id,
				start_day,
				end_day
			)
		)

	margin.add_child(
		label
	)

	schedule_list.add_child(
		event_panel
	)
	StoreEventPreparationView.attach(self, event_data)


func _get_schedule_status_text(
	start_day: int,
	end_day: int
) -> String:
	var current_total_day: int = (
		GameState.total_day
	)

	if current_total_day < start_day:
		var remaining_days: int = (
			start_day
			- current_total_day
		)

		return (
			"예정 D-"
			+ str(remaining_days)
		)

	if current_total_day <= end_day:
		if current_total_day == end_day:
			return "진행 중 · 오늘 종료"

		return (
			"진행 중 · 종료까지 "
			+ str(end_day - current_total_day)
			+ "일"
		)

	return "종료"

func _refresh_daily_history_list() -> void:
	_reset_info_labels()

	history_title_label.text = (
		"편의점 정보 · 영업 기록"
	)

	var history: Array[Dictionary] = (
		GameState.get_daily_shop_history()
	)

	history.sort_custom(
		_sort_shop_history_newest_first
	)

	if history.is_empty():
		var empty_label := Label.new()

		empty_label.text = (
			"아직 완료된 영업 기록이 없습니다."
		)

		empty_label.horizontal_alignment = (
			HORIZONTAL_ALIGNMENT_CENTER
		)

		history_list.add_child(
			empty_label
		)

		return

	for record in history:
		_create_shop_history_entry(
			record
		)


func _sort_shop_history_newest_first(
	record_a: Dictionary,
	record_b: Dictionary
) -> bool:
	return (
		int(record_a.get("total_day", 0))
		> int(record_b.get("total_day", 0))
	)

func _create_shop_history_entry(
	record: Dictionary
) -> void:
	var result_day: int = int(
		record.get(
			"total_day",
			1
		)
	)

	var weekday: int = int(
		record.get(
			"weekday",
			1
		)
	)

	var visitors: int = int(
		record.get("visitors", 0)
	)

	var sales: int = int(
		record.get("sales", 0)
	)

	var missed: int = int(
		record.get("missed", 0)
	)

	var revenue: int = int(
		record.get("revenue", 0)
	)

	var purchase_rate: float = 0.0

	if visitors > 0:
		purchase_rate = (
			float(sales)
			/ float(visitors)
			* 100.0
		)

	var sold_items: Dictionary = record.get(
		"sold_items",
		{}
	)

	var unmet_demand: Dictionary = record.get(
		"unmet_demand",
		{}
	)

	var top_sold_item: String = (
		_get_history_top_item_text(
			sold_items,
			"판매 기록 없음"
		)
	)

	var top_unmet_item: String = (
		_get_history_top_item_text(
			unmet_demand,
			"놓친 수요 없음"
		)
	)

	var panel := PanelContainer.new()

	panel.custom_minimum_size = Vector2(
		0,
		185
	)

	panel.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)

	var margin := MarginContainer.new()

	margin.add_theme_constant_override(
		"margin_left",
		16
	)

	margin.add_theme_constant_override(
		"margin_top",
		10
	)

	margin.add_theme_constant_override(
		"margin_right",
		16
	)

	margin.add_theme_constant_override(
		"margin_bottom",
		10
	)

	panel.add_child(
		margin
	)

	var label := Label.new()

	label.autowrap_mode = (
		TextServer.AUTOWRAP_WORD_SMART
	)

	label.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)

	label.text = (
		CalendarData.get_display_date(
			result_day
		)
		+ " / "
		+ _get_history_weekday_name(
			weekday
		)
		+ "\n방문객 "
		+ str(visitors)
		+ "명 · 구매 "
		+ str(sales)
		+ "명 · 실패 "
		+ str(missed)
		+ "명"
		+ "\n구매율 "
		+ str(roundi(purchase_rate))
		+ "% · 매출 "
		+ str(revenue)
		+ "G"
		+ "\n가장 많이 팔린 상품: "
		+ top_sold_item
		+ "\n가장 많이 놓친 수요: "
		+ top_unmet_item
	)

	var active_event_ids: Array = (
		record.get(
			"active_event_ids",
			[]
		)
	)

	var active_event_names: Array[String] = []

	for raw_event_id in active_event_ids:
		var event_id: String = str(
			raw_event_id
		)

		var event_data: Dictionary = (
			StoreEventData.get_event(
				event_id
			)
		)

		if event_data.is_empty():
			continue

		var event_title: String = str(
			event_data.get(
				"title",
				event_id
			)
		)

		active_event_names.append(
			event_title
		)

	if not active_event_names.is_empty():
		label.text += (
			"\n적용 이벤트: "
			+ ", ".join(active_event_names)
		)

	margin.add_child(
		label
	)

	history_list.add_child(
		panel
	)

func _get_history_top_item_text(
	item_counts: Dictionary,
	empty_text: String
) -> String:
	if item_counts.is_empty():
		return empty_text

	var highest_count: int = 0
	var names: Array[String] = []

	for raw_item_id in item_counts.keys():
		var item_id: String = str(
			raw_item_id
		)

		var count: int = int(
			item_counts.get(
				item_id,
				0
			)
		)

		if count <= 0:
			continue

		var item_name: String = (
			ItemData.get_item_name(
				item_id
			)
		)

		if count > highest_count:
			highest_count = count
			names.clear()
			names.append(item_name)

		elif count == highest_count:
			names.append(item_name)

	if names.is_empty():
		return empty_text

	return (
		", ".join(names)
		+ " ("
		+ str(highest_count)
		+ "개)"
	)


func _get_history_weekday_name(
	weekday: int
) -> String:
	match weekday:
		1:
			return "월요일"
		2:
			return "화요일"
		3:
			return "수요일"
		4:
			return "목요일"
		5:
			return "금요일"
		6:
			return "토요일"
		7:
			return "일요일"

	return "알 수 없는 요일"



func get_schedule_result_text(
	event_id: String,
	start_day: int,
	end_day: int
) -> String:
	var history: Array[Dictionary] = (
		GameState.get_daily_shop_history()
	)

	var business_days: int = 0
	var total_visitors: int = 0
	var total_sales: int = 0
	var total_missed: int = 0
	var total_revenue: int = 0

	var sold_totals: Dictionary = {}
	var unmet_totals: Dictionary = {}

	for record in history:
		var result_day: int = int(
			record.get(
				"total_day",
				0
			)
		)

		if (
			result_day < start_day
			or result_day > end_day
		):
			continue

		var active_event_ids: Array = (
			record.get(
				"active_event_ids",
				[]
			)
		)

		if not active_event_ids.has(
			event_id
		):
			continue

		business_days += 1

		total_visitors += int(
			record.get("visitors", 0)
		)

		total_sales += int(
			record.get("sales", 0)
		)

		total_missed += int(
			record.get("missed", 0)
		)

		total_revenue += int(
			record.get("revenue", 0)
		)

		var sold_items: Dictionary = (
			record.get(
				"sold_items",
				{}
			)
		)

		for raw_item_id in sold_items.keys():
			var item_id: String = str(
				raw_item_id
			)

			sold_totals[item_id] = (
				int(
					sold_totals.get(
						item_id,
						0
					)
				)
				+ int(sold_items[item_id])
			)

		var unmet_demand: Dictionary = (
			record.get(
				"unmet_demand",
				{}
			)
		)

		for raw_item_id in unmet_demand.keys():
			var item_id: String = str(
				raw_item_id
			)

			unmet_totals[item_id] = (
				int(
					unmet_totals.get(
						item_id,
						0
					)
				)
				+ int(unmet_demand[item_id])
			)

	if business_days <= 0:
		return "기록된 영업 결과가 없습니다."

	var purchase_rate: float = 0.0

	if total_visitors > 0:
		purchase_rate = (
			float(total_sales)
			/ float(total_visitors)
			* 100.0
		)

	var top_sold_item: String = (
		_get_history_top_item_text(
			sold_totals,
			"판매 기록 없음"
		)
	)

	var top_unmet_item: String = (
		_get_history_top_item_text(
			unmet_totals,
			"놓친 수요 없음"
		)
	)

	return (
		"영업일: %d일"
		% business_days
		+ "\n방문객: %d명 · 구매: %d명 · 실패: %d명"
		% [
			total_visitors,
			total_sales,
			total_missed
		]
		+ "\n구매율: %d%% · 총매출: %dG"
		% [
			roundi(purchase_rate),
			total_revenue
		]
		+ "\n가장 많이 팔린 상품: "
		+ top_sold_item
		+ "\n가장 많이 놓친 수요: "
		+ top_unmet_item
	)

func select_info_tab(tab: InfoTab) -> void:
	current_info_tab = tab
	refresh_shop_history()


func refresh_shop_history() -> void:
	ActFourBookView.refresh_button(self)
	# 현재 선택한 버튼 하나만 비활성화
	InteractionUiStyle.select_tab(basic_info_button,current_info_tab == InfoTab.BASIC)
	InteractionUiStyle.select_tab(detail_info_button,current_info_tab == InfoTab.DETAIL)
	InteractionUiStyle.select_tab(sales_trend_button,current_info_tab == InfoTab.TREND)
	InteractionUiStyle.select_tab(extra_record_button,current_info_tab == InfoTab.RECORD)

	# 이정표 탭은 자식이 쪽(page) 둘뿐이어야 하므로 보관한 글 칸을 비운다. 나머지 탭은 글 칸을 다시 쓴다.
	_reset_info_labels(current_info_tab != InfoTab.MILESTONES)
	refresh_common_info()

	match current_info_tab:
		InfoTab.MILESTONES:
			history_title_label.text = "길목의 이정표"
			ActFourBookView.render(self)
		InfoTab.BASIC:
			history_title_label.text = "편의점 기본 정보"
			_show_basic_store_info()

		InfoTab.DETAIL:
			history_title_label.text = "편의점 상세 정보"
			_show_detailed_store_info()

		InfoTab.TREND:
			history_title_label.text = "매출 추이"
			_show_sales_trend()

		InfoTab.RECORD:
			_refresh_daily_history_list()
			history_title_label.text = "추가 기록 · 날짜별 영업"


# 정보 탭의 글 칸(Label)은 트리에 둔 채 다시 쓴다. 한글 글을 새로 만들거나 트리에서 뺐다 넣으면 글자 배치(shaping)를 처음부터 다시 해
# 열 때마다 수십 ms가 들어 책이 끊겼다. 같은 글이면 text 대입은 아무 일도 하지 않는다(2026-10-09).
const INFO_TEXT_META := "info_text"
var _info_labels: Array[Label] = []
var _info_next: int = 0


# 기록 목록을 새로 채우기 전에 호출한다: keep 이면 글 칸은 숨기기만 하고 나머지(표·행)는 지운다. keep 이 아니면 글 칸도 지운다.
func _reset_info_labels(keep: bool = true) -> void:
	for child in history_list.get_children():
		if keep and child is Label and child.has_meta(INFO_TEXT_META):
			child.visible = false
		else:
			history_list.remove_child(child)
			child.queue_free()

	if not keep:
		_info_labels.clear()

	_info_next = 0


func _add_store_info_text(text: String) -> void:
	var label: Label

	if _info_next < _info_labels.size() and is_instance_valid(_info_labels[_info_next]):
		label = _info_labels[_info_next]
	else:
		label = Label.new()
		label.set_meta(INFO_TEXT_META, true)
		label.autowrap_mode = (
			TextServer.AUTOWRAP_WORD_SMART
		)
		label.size_flags_horizontal = (
			Control.SIZE_EXPAND_FILL
		)
		label.add_theme_font_size_override(
			"font_size",
			UiTypography.size(20)
		)
		history_list.add_child(label)

		if _info_next < _info_labels.size():
			_info_labels[_info_next] = label
		else:
			_info_labels.append(label)

	_info_next += 1
	label.text = text  # 같은 글이면 아무 일도 하지 않는다
	label.visible = true
	history_list.move_child(label, -1)  # 이번 목록의 끝으로(다른 칸 순서를 지킨다)

func _show_basic_store_info() -> void:
	_show_store_decoration_info()

	_add_store_info_text(
		"현재 날짜: "
		+ CalendarData.get_display_date(
			GameState.total_day
		)
		+ "\n소지금: %d G" % GameState.get_money()
	)

	var scene: Node = get_tree().current_scene

	if scene == null:
		_add_store_info_text(
			"\n현재 영업 정보를 가져올 수 없습니다."
		)
		return

	var player_node: Node = (
		scene.get_node_or_null("Actors/Player")
	)

	if (
		not is_instance_valid(player_node)
		or not player_node.has_method(
			"get_daily_shop_stats"
		)
	):
		_add_store_info_text(
			"\n편의점 실행 중에 영업 현황을 확인할 수 있습니다."
		)
		return

	var stats: Dictionary = (
		player_node.call("get_daily_shop_stats")
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

	var lines: Array[String] = [
		"[현재 영업 현황]",
		"방문객: %d명" % visitors,
		"구매 성공: %d명" % sales,
		"판매 실패: %d명" % missed,
		"구매율: %d%%" % roundi(purchase_rate),
		"매출: %d G" % revenue
	]

	_add_store_info_text(
		"\n" + "\n".join(lines)
	)

	_add_store_info_text(
		"\n※ 현재 정산 구간의 통계입니다."
		+ "\n매출은 비용을 차감한 순이익과 다릅니다."
	)

func _show_detailed_store_info() -> void:
	var history: Array[Dictionary] = (
		GameState.get_daily_shop_history()
	)

	if history.is_empty():
		_add_store_info_text(
			"아직 정산이 완료된 영업 기록이 없습니다."
		)
		return

	var total_visitors: int = 0
	var total_sales: int = 0
	var total_revenue: int = 0
	var total_sold_amount: int = 0

	var sold_totals: Dictionary = {}
	var unmet_totals: Dictionary = {}

	for record in history:
		total_visitors += int(record.get("visitors", 0))
		total_sales += int(record.get("sales", 0))
		total_revenue += int(record.get("revenue", 0))

		var sold_items: Dictionary = record.get(
			"sold_items",
			{}
		)

		for raw_item_id in sold_items.keys():
			var item_id: String = str(raw_item_id)
			var amount: int = int(sold_items[raw_item_id])

			total_sold_amount += amount
			sold_totals[item_id] = (
				int(sold_totals.get(item_id, 0))
				+ amount
			)

		var unmet_demand: Dictionary = record.get(
			"unmet_demand",
			{}
		)

		for raw_item_id in unmet_demand.keys():
			var item_id: String = str(raw_item_id)
			var amount: int = int(unmet_demand[raw_item_id])

			unmet_totals[item_id] = (
				int(unmet_totals.get(item_id, 0))
				+ amount
			)

	var purchase_rate: float = 0.0

	if total_visitors > 0:
		purchase_rate = (
			float(total_sales)
			/ float(total_visitors)
			* 100.0
		)

	var average_revenue: int = roundi(
		float(total_revenue) / float(history.size())
	)

	var summary_lines: Array[String] = [
		"[누적 영업 실적]",
		"정산된 영업일: %d일" % history.size(),
		"누적 매출: %d G" % total_revenue,
		"영업일당 평균 매출: %d G" % average_revenue,
		"누적 방문객: %d명" % total_visitors,
		"구매 성공: %d명" % total_sales,
		"전체 구매율: %d%%" % roundi(purchase_rate),
		"총 판매량: %d개" % total_sold_amount
	]

	_add_store_info_text(
		"\n".join(summary_lines)
	)

	_add_store_info_text(
		"\n[가장 많이 팔린 상품]\n"
		+ _get_history_top_item_text(
			sold_totals,
			"판매 기록 없음"
		)
	)

	_add_store_info_text(
		"\n[상품별 누적 판매량]\n"
		+ _format_store_item_counts(
			sold_totals,
			"판매 기록 없음"
		)
	)

	_add_store_info_text(
		"\n[상품별 놓친 수요]\n"
		+ _format_store_item_counts(
			unmet_totals,
			"놓친 수요 없음"
		)
	)

	_add_store_info_text(
		"\n정산이 완료된 기록 기준입니다."
	)


func _format_store_item_counts(
	item_counts: Dictionary,
	empty_text: String
) -> String:
	var item_ids: Array[String] = []

	for raw_item_id in item_counts.keys():
		var item_id: String = str(raw_item_id)

		if int(item_counts.get(item_id, 0)) > 0:
			item_ids.append(item_id)

	if item_ids.is_empty():
		return empty_text

	# 화면을 다시 열어도 같은 순서로 표시
	item_ids.sort()

	var lines: Array[String] = []

	for item_id in item_ids:
		lines.append(
			"%s: %d개" % [
				ItemData.get_item_name(item_id),
				int(item_counts[item_id])
			]
		)

	return "\n".join(lines)

func _show_sales_trend() -> void:
	var history: Array[Dictionary] = (
		GameState.get_daily_shop_history().duplicate(true)
	)

	if history.is_empty():
		_add_store_info_text(
			"아직 정산이 완료된 영업 기록이 없습니다."
		)
		return

	# 기존 정렬 함수로 최신 기록부터 정렬
	history.sort_custom(
		_sort_shop_history_newest_first
	)

	var recent_records: Array[Dictionary] = []
	var record_count: int = mini(history.size(), 14)

	for index in range(record_count):
		recent_records.append(history[index])

	# 그래프는 오래된 날짜부터 보여준다.
	recent_records.reverse()

	var highest_revenue: int = 0
	var total_revenue: int = 0
	var highest_dates: Array[String] = []

	for record in recent_records:
		var revenue: int = int(
			record.get("revenue", 0)
		)
		var result_day: int = int(
			record.get("total_day", 1)
		)

		total_revenue += revenue

		var date_text: String = (
			CalendarData.get_display_date(result_day)
		)

		if revenue > highest_revenue:
			highest_revenue = revenue
			highest_dates.clear()
			highest_dates.append(date_text)
		elif revenue == highest_revenue:
			highest_dates.append(date_text)

	var average_revenue: int = roundi(
		float(total_revenue) / float(record_count)
	)

	var summary_lines: Array[String] = [
		"최근 정산된 영업 기록 %d건" % record_count,
		"기간 매출: %d G" % total_revenue,
		"영업일당 평균: %d G" % average_revenue,
		"기간 최고 매출: %d G" % highest_revenue
	]

	if highest_revenue > 0:
		summary_lines.append(
			"최고 매출일: " + ", ".join(highest_dates)
		)

	_add_store_info_text(
		"\n".join(summary_lines)
	)

	_add_store_info_text(
		"\n[날짜별 매출]"
	)

	for record in recent_records:
		_add_sales_trend_row(
			record,
			highest_revenue
		)

	_add_store_info_text(
		"\n정산된 날짜만 표시합니다."
		+ "\n기록이 없는 원정일은 매출 0G로 계산하지 않습니다."
	)


func _add_sales_trend_row(
	record: Dictionary,
	highest_revenue: int
) -> void:
	var result_day: int = int(
		record.get("total_day", 1)
	)
	var revenue: int = int(
		record.get("revenue", 0)
	)

	var row := VBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)

	var caption := Label.new()
	caption.text = (
		CalendarData.get_display_date(result_day)
		+ " · %d G" % revenue
	)
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.add_theme_font_size_override("font_size", UiTypography.size(18))
	row.add_child(caption)

	var bar := ProgressBar.new()
	bar.custom_minimum_size.y = 22
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.min_value = 0.0

	# 모든 날짜에 같은 눈금을 사용한다.
	# 전부 0G여도 최대값은 1 이상으로 유지한다.
	bar.max_value = float(maxi(highest_revenue, 1))
	bar.value = float(revenue)
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.16, 0.18, 0.22)
	bar.add_theme_stylebox_override(
		"background",
		background
	)

	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.25, 0.65, 0.90)
	bar.add_theme_stylebox_override(
		"fill",
		fill
	)

	row.add_child(bar)

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 10
	row.add_child(spacer)

	history_list.add_child(row)

func _show_store_decoration_info() -> void:
	var manager: Node = get_tree().get_first_node_in_group(
		"build_manager"
	)

	# 그룹으로 찾지 못하면 현재 메인 씬에서 확인
	if not is_instance_valid(manager):
		var scene: Node = get_tree().current_scene

		if is_instance_valid(scene):
			manager = scene.get_node_or_null("BuildManager")

	if not is_instance_valid(manager):
		_add_store_info_text(
			"[매장 효과]\nBuildManager를 찾지 못했습니다."
		)
		return

	if not manager.has_method("get_decoration_effect"):
		_add_store_info_text(
			"[매장 효과]\nBuildManager에 get_decoration_effect()가 없습니다."
		)
		return

	if not manager.has_method("get_customer_weight_bonuses"):
		_add_store_info_text(
			"[매장 효과]\nBuildManager에 get_customer_weight_bonuses()가 없습니다."
		)
		return

	var reputation: float = float(
		manager.call("get_decoration_effect", "reputation")
	)
	var resident_reputation: int = ResidentRequestFlow.reputation()

	# 평판만 원래 점수로 보관하므로 방문 보너스로 변환
	var visit_bonus: float = (
		DecorationEffectService.get_reputation_visit_bonus(
			reputation + resident_reputation
		)
	)

	# 구매욕구와 손님 가중치는 이미 감소 곡선이 적용된 값
	var extra_purchase_chance: float = float(
		manager.call("get_decoration_effect", "purchase_desire")
	)

	var customer_bonuses: Dictionary = manager.call(
		"get_customer_weight_bonuses"
	)

	var lines: Array[String] = [
		"[매장 치장 효과]",
		"치장 평판: %.1f" % reputation,
		"주민 부탁 평판: %d" % resident_reputation,
		"평판에 따른 방문 빈도 보너스: +%.1f%%" % (
			visit_bonus * 100.0
		),
		"치장에 따른 추가 구매 확률: %.1f%%" % (
			extra_purchase_chance * 100.0
		),
		"추가 구매는 요구량과 여분 재고가 확보된 경우에 적용됩니다."
	]

	# 제공된 월드 구조: BuildManager와 CustomerSpawner는 형제 노드
	var world: Node = manager.get_parent()
	var spawner: Node = null

	if is_instance_valid(world):
		spawner = world.get_node_or_null("CustomerSpawner")

	if is_instance_valid(spawner):
		var timer: Timer = (
			spawner.get_node_or_null("SpawnTimer") as Timer
		)

		var raw_base_interval: Variant = spawner.get(
			"base_spawn_interval"
		)
		var raw_max_customers: Variant = spawner.get(
			"max_customers"
		)
		var raw_shop_open: Variant = spawner.get("shop_open")

		lines.append("")
		lines.append("[손님 방문]")

		if (
			raw_base_interval is float
			or raw_base_interval is int
		):
			var base_interval: float = float(raw_base_interval)

			if base_interval > 0.0:
				var expected_interval: float = (
					base_interval / (1.0 + visit_bonus)
				)

				lines.append(
					"현재 배치 기준 생성 간격: %.2f초"
					% expected_interval
				)

		if is_instance_valid(timer):
			if raw_shop_open == true:
				lines.append(
					"생성 타이머 설정 간격: %.2f초"
					% timer.wait_time
				)
			else:
				lines.append("영업 시작 시 방문 간격이 적용됩니다.")

		if raw_max_customers is int:
			lines.append(
				"최대 동시 손님: %d명" % int(raw_max_customers)
			)

		lines.append(
			"최대 인원에 도달하면 추가 방문이 대기됩니다."
		)

	lines.append("")
	lines.append("[손님 유형별 치장 보너스]")

	var target_ids: Array[String] = []

	for raw_target in customer_bonuses:
		var target: String = str(raw_target)

		if float(customer_bonuses[target]) > 0.0:
			target_ids.append(target)

	target_ids.sort()

	if target_ids.is_empty():
		lines.append("적용 중인 유형별 보너스가 없습니다.")
	else:
		for target in target_ids:
			var bonus: float = float(customer_bonuses[target])

			lines.append(
				"%s: 등장 가중치 +%.1f%%"
				% [
					CustomerTypeData.get_display_name(target),
					bonus * 100.0
				]
			)

	lines.append("")
	lines.append(
		"등장 가중치는 등장 확률과 다르며, 이벤트 보정은 별도로 적용됩니다."
	)
	lines.append(
		"같은 효과를 많이 배치할수록 추가 효율이 감소합니다."
	)
	lines.append(
		"치장 효과는 매장의 확정된 배치를 기준으로 합니다.\n"
	)

	_add_store_info_text("\n".join(lines))

func _on_construction_expansion_completed() -> void:
	refresh_common_info()
