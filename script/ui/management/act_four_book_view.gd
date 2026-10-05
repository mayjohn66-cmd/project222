class_name ActFourBookView
extends RefCounted

static func install(menu: Control) -> void:
	var button := Button.new()
	button.name = "MilestonesButton"
	button.text = "이정표"
	button.visible = ActFourFlow.started()
	button.pressed.connect(menu.select_info_tab.bind(ManagementMenu.InfoTab.MILESTONES))
	menu.info_tab_bar.add_child(button)
	menu.set_meta("act4_button",button)
static func refresh_button(menu: Control) -> void:
	var button: Button = menu.get_meta("act4_button",null)
	if button == null: return
	button.visible = ActFourFlow.started()
	button.disabled = menu.current_info_tab == ManagementMenu.InfoTab.MILESTONES
	# 소탭 다섯 개가 왼쪽 쪽에 모두 읽히도록 완전한 짧은 이름을 쓴다.
	menu.basic_info_button.text = "기본" if button.visible else "기본 정보"
	menu.detail_info_button.text = "상세" if button.visible else "상세 정보"
	menu.sales_trend_button.text = "매출" if button.visible else "매출 추이"
	menu.extra_record_button.text = "기록" if button.visible else "추가 기록"
	if not button.visible and menu.current_info_tab == ManagementMenu.InfoTab.MILESTONES:
		menu.current_info_tab = ManagementMenu.InfoTab.BASIC
static func render(menu: Control) -> void:
	# 두 자식은 BookFlowVBox가 각각 왼쪽·오른쪽 쪽에 배치한다.
	var left := _page(menu.history_list,"MilestonePage")
	var right := _page(menu.history_list,"CluePage")
	_label(left,"길목의 이정표 · %d/5" % ActFourFlow.milestone_count(),22)
	for entry in ActFourFlow.SETTINGS.milestones:
		_label(left,("● " if ActFourFlow.milestone_complete(entry) else "○ ") + str(entry["name"]),18)
	_label(left,"지금 이어갈 이야기",19)
	_label(left,ActFourFlow.current_goal(),16)
	_label(right,"유적의 단서 수첩",22)
	var clues := ActFourFlow.clues()
	if clues.is_empty(): _label(right,"아직 남겨 둔 단서는 없습니다. 길 위의 이야기는 유적을 찾지 않아도 이어집니다.",17)
	for clue in clues: _label(right,"· " + clue,17)
	_label(right,"단서는 답을 정하지 않고, 이웃과 나눈 질문으로 남습니다.",16)
static func _page(row: Control, name_text: String) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.name = name_text
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_stretch_ratio = 1.0
	page.add_theme_constant_override("separation",12)
	row.add_child(page)
	return page
static func _label(parent: Control, text: String, font_size: int) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size",font_size)
	parent.add_child(label)
static func add_schedule(menu: Control) -> void:
	if not ActFourFlow.done("a6_crossroad_market"): return
	var entry := VBoxContainer.new()
	menu.schedule_list.add_child(entry)
	_label(entry,"길이 모이는 날 · 계절 장터",20)
	_label(entry,"매 계절 %d~%d일 · 준비와 판매 뒤 이웃에게 후일담 듣기\n이미 맡은 준비는 다음 장터 철에도 이어갈 수 있어요." % [VillageExpansionFlow.SETTINGS.festival_start_day,VillageExpansionFlow.SETTINGS.festival_end_day],17)
