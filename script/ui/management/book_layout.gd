class_name BookLayout
extends RefCounted
## 관리 창의 각 탭을 "펼친 책의 두 쪽"에 맞게 배치한다. 왼쪽 쪽 = 분류·목록·요약, 오른쪽 쪽 = 상세·행동.
## 탭 안의 노드와 신호는 그대로 두고 크기·간격·부모만 조정한다(탭 스크립트의 @onready 경로는 _ready 때 이미 잡혀 있다).
## 인벤토리 탭은 InventoryDetailPane 이 따로 맡는다.

const GUTTER := 32.0  # 두 쪽 사이 간격(가운데 제본 홈 폭)


static func apply(menu: Control) -> void:
	_blueprint(menu)
	_production(menu)
	_employee(menu)
	_construction(menu)
	_schedule(menu)
	_history(menu)


# 가로 한 줄 분류 버튼 줄을 왼쪽 쪽 폭으로 제한한다(container 크기가 바뀔 때마다 따라간다).
static func limit_to_left_half(node: Control,container: Control) -> void:
	node.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var fit := func() -> void:
		node.custom_minimum_size.x = maxf((container.size.x - GUTTER) * 0.5,0.0)
	container.resized.connect(fit)
	fit.call_deferred()


static func _expand(node: Control) -> void:
	node.custom_minimum_size.x = 0.0
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.size_flags_stretch_ratio = 1.0


static func _blueprint(menu: Control) -> void:
	var vbox: Control = menu.blueprint_content.get_node("MainVBox")
	var body: HBoxContainer = vbox.get_node("Body")
	body.add_theme_constant_override("separation",int(GUTTER))
	_expand(body.get_node("LeftPanel"))
	_expand(body.get_node("DetailPanel"))
	limit_to_left_half(vbox.get_node("CategoryTabs"),vbox)


static func _production(menu: Control) -> void:
	var prod: Control = menu.management_production
	limit_to_left_half(prod.get_node("ProductionTabBar"),prod)
	var body: HBoxContainer = prod.get_node("MainHBox")
	body.add_theme_constant_override("separation",int(GUTTER))
	_expand(body.get_node("LeftPanel"))
	_expand(body.get_node("RightPanel"))


static func _employee(menu: Control) -> void:
	var vbox: Control = menu.employee_content.get_node("MainVBox")
	limit_to_left_half(vbox.get_node("Tabs"),vbox)
	limit_to_left_half(vbox.get_node("MessageLabel"),vbox)
	var grid: GridContainer = vbox.get_node("EmployeeScroll/EmployeeList")
	grid.add_theme_constant_override("h_separation",int(GUTTER))
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL


# 건설: 왼쪽 쪽에 구역 이름과 현재 상태, 오른쪽 쪽에 다음 단계와 확장 버튼.
static func _construction(menu: Control) -> void:
	var vbox: Control = menu.construction_content.get_node("MainVBox")
	limit_to_left_half(vbox.get_node("AreaTabs"),vbox)
	var margin: Control = vbox.get_node("ContentPanel/ContentMargin")
	var old: Control = margin.get_node("ContentVBox")
	var row := HBoxContainer.new()
	row.name = "SpreadRow"
	row.add_theme_constant_override("separation",int(GUTTER))
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(row)
	var left := VBoxContainer.new()
	var right := VBoxContainer.new()
	for page in [left,right]:
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.add_theme_constant_override("separation",12)
		row.add_child(page)
	for name in ["AreaTitleLabel","CurrentInfoLabel"]:
		var n: Node = old.get_node(name)
		old.remove_child(n)
		left.add_child(n)
	for name in ["NextInfoLabel","ExpandButton","NoteLabel"]:
		var n: Node = old.get_node(name)
		old.remove_child(n)
		right.add_child(n)
	old.visible = false


static func _flow_list(list: VBoxContainer) -> void:
	list.set_script(BookFlowVBox)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.update_minimum_size()


static func _schedule(menu: Control) -> void:
	var vbox: Control = menu.schedule_content.get_node("MarginContainer/ScheduleVBox")
	_flow_list(vbox.get_node("ScheduleScroll/ScheduleList"))


static func _history(menu: Control) -> void:
	var vbox: Control = menu.history_content.get_node("MarginContainer/HistoryVBox")
	limit_to_left_half(vbox.get_node("InfoTabBar"),vbox)
	_flow_list(vbox.get_node("HistoryScroll/HistoryList"))
