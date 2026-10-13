class_name RequestNotebookView
extends HBoxContainer
## 책 왼쪽의 목록을 고르면 오른쪽의 기록만 바꾼다.
var menu: Control
var world: Node
var rows: Array[Dictionary] = []
var list: VBoxContainer
var detail_page: VBoxContainer
var category := "active"
var selected_id := ""
var selection_buttons: Dictionary = {}
var category_buttons: Dictionary = {}

func _ready() -> void:
	name = "RequestNotebook"
	set_meta("book_spread", true)
	custom_minimum_size.y = 350
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", int(BookLayout.GUTTER))
	rows = RequestNotebookData.entries()
	category = str(menu.get_meta("notebook_category", "active"))
	selected_id = str(menu.get_meta("notebook_selection", ""))
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 12)
	add_child(left)
	left.add_child(_label("부탁 수첩", UiTypography.BOOK_HEADING_SIZE))
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 8)
	left.add_child(filters)
	for pair in [["active", "진행"], ["done", "완료"], ["neighbors", "이웃"], ["memories", "기록"]]:
		var button := _button(str(pair[1]), UiTypography.SMALL_SIZE)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_select_category.bind(str(pair[0])))
		filters.add_child(button)
		category_buttons[pair[0]] = button
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	detail_page = VBoxContainer.new()
	detail_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_page.add_theme_constant_override("separation", 12)
	add_child(detail_page)
	_select_category(category)

func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", InteractionUiStyle.INK)
	return label

func _button(text: String, font_size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", font_size)
	button.custom_minimum_size.y = 44
	InteractionUiStyle.apply_button(button)
	return button

func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _select_category(value: String) -> void:
	category = value
	menu.set_meta("notebook_category", category)
	for key in category_buttons:
		category_buttons[key].add_theme_stylebox_override("normal", InteractionUiStyle.patch("tab_selected" if key == category else "tab_normal"))
	_clear(list)
	selection_buttons.clear()
	var available: Array[Dictionary] = []
	for row in rows:
		if row["category"] == category: available.append(row)
	var found := false
	for row in available:
		if row["id"] == selected_id: found = true
	if not found: selected_id = str(available[0]["id"]) if not available.is_empty() else ""
	for row in available:
		var button := _button(str(row["title"]), UiTypography.SMALL_SIZE)
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.tooltip_text = str(row["title"])
		button.pressed.connect(_select.bind(str(row["id"])))
		list.add_child(button)
		selection_buttons[row["id"]] = button
	if available.is_empty(): list.add_child(_label("아직 남긴 기록이 없습니다.", UiTypography.SMALL_SIZE))
	_select(selected_id)

func _select(id: String) -> void:
	selected_id = id
	menu.set_meta("notebook_selection", id)
	for key in selection_buttons:
		selection_buttons[key].add_theme_stylebox_override("normal", InteractionUiStyle.patch("tab_selected" if key == id else "tab_normal"))
	_clear(detail_page)
	var selected: Dictionary = {}
	for row in rows:
		if row["id"] == id: selected = row; break
	if selected.is_empty():
		detail_page.add_child(_label("주민과 나눈 약속을 이곳에 남깁니다.", UiTypography.SMALL_SIZE))
		return
	detail_page.add_child(_label(str(selected["title"]), UiTypography.BOOK_HEADING_SIZE))
	var detail := RequestNotebookData.detail(selected)
	detail_page.add_child(_label(str(detail.get("context", "")), UiTypography.SMALL_SIZE))
	if float(detail["progress"]) >= 0:
		var bar := ProgressBar.new()
		bar.name = "RequestProgress"
		bar.value = float(detail["progress"])
		bar.custom_minimum_size.y = 26
		bar.add_theme_font_size_override("font_size", UiTypography.SMALL_SIZE)
		detail_page.add_child(bar)
	var scroll := ScrollContainer.new()
	scroll.name = "RequestDetailScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_page.add_child(scroll)
	var text := _label(str(detail["text"]), UiTypography.BOOK_BODY_SIZE)
	text.name = "RequestDetail"
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(text)
	if not str(detail.get("reward", "")).is_empty():
		var reward := _label(str(detail["reward"]), UiTypography.SMALL_SIZE)
		reward.name = "RequestReward"
		detail_page.add_child(reward)
	var target := RequestNotebookData.destination(world, id)
	var director := world.get_node_or_null("VillageJournalDirector") as VillageJournalDirector
	var tracked := director != null and director.tracked_id == id
	var button := _button("표시 해제" if tracked else "목적지 표시", UiTypography.BOOK_CONTROL_SIZE)
	button.name = "RequestDestination"
	button.disabled = director == null or (target == null and not tracked)
	button.pressed.connect(func():
		if director != null: director.set_tracked(id)
		_select(id))
	detail_page.add_child(button)
