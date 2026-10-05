class_name FoodShelfLifePanel
extends AcceptDialog

var inventory_view: Control
var rows: VBoxContainer
var scroll: ScrollContainer

static func install(view: Control) -> void:
	var ancestor := view.get_parent()
	while ancestor != null and not ancestor is ManagementMenu: ancestor = ancestor.get_parent()
	if ancestor == null: return
	var world := ancestor.get_parent()
	while world != null:
		if world.scene_file_path == "res://scenes/expedition/expedition.tscn": return
		world = world.get_parent()
	var panel := FoodShelfLifePanel.new()
	panel.inventory_view = view
	view.add_child(panel)
	var button := Button.new()
	button.name = "FoodShelfLifeButton"
	button.text = "식품 관리"
	button.tooltip_text = "유통기한 · 마감 할인 · 기한 지난 식품 정리"
	# The book's inventory list occupies its left page. Keep extra actions on
	# their own row so they do not overflow the category tabs into the detail page.
	var actions := HBoxContainer.new()
	actions.name = "FoodCareActions"
	var column := view.get_node("MainVBox")
	column.add_child(actions)
	column.move_child(actions, 1)
	actions.add_child(button)
	button.pressed.connect(panel.open)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	title = "먼저 내놓을 식품"
	ok_button_text = "돌아가기"
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color("f5e5c9")
	paper.set_content_margin_all(14)
	add_theme_stylebox_override("panel", paper)
	add_theme_color_override("title_color", Color("51382d"))
	for font_state in ["font_color", "font_focus_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_hover_pressed_color"]:
		get_ok_button().add_theme_color_override(font_state, Color("51382d"))
	scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 330)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 12)
	scroll.add_child(rows)
	about_to_popup.connect(_fit)
	confirmed.connect(_acknowledge)
	close_requested.connect(_acknowledge)

func _fit() -> void:
	var bounds := inventory_view.get_viewport().get_visible_rect().size
	scroll.custom_minimum_size = Vector2(minf(560, bounds.x - 64), minf(330, bounds.y - 150))
	size = Vector2i(minf(610, bounds.x - 32), minf(450, bounds.y - 40))

func _label(text_value: String) -> void:
	var label := Label.new()
	label.text = text_value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color("51382d"))
	label.add_theme_font_size_override("font_size", 16)
	rows.add_child(label)

func open() -> void:
	FoodShelfLife.settle()
	refresh()
	_fit()
	popup_centered(size)

func refresh() -> void:
	FoodShelfLife.settle()
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	_label("빵을 언제까지 내놓을 수 있을까?\n오래된 재고부터 손님에게 건네고, 기한이 가까우면 할인해 보자.\n메뉴 → 운영 → 인벤토리에서 냉장·냉동 보관도 할 수 있다.")
	if FoodShelfLife.learning(): _label("첫 거래와 원재료 판매를 배우는 동안 식품의 기한은 줄어들지 않습니다.")
	var markdown := CheckButton.new()
	markdown.text = "마감 %d일 전부터 %d%% 할인" % [FoodShelfLife.SETTINGS.markdown_days, FoodShelfLife.SETTINGS.markdown_percent]
	markdown.button_pressed = FoodShelfLife.state()["markdown"]
	markdown.add_theme_color_override("font_color", Color("51382d"))
	rows.add_child(markdown)
	markdown.toggled.connect(func(on: bool) -> void:
		FoodShelfLife.state()["markdown"] = on
		refresh()
		_refresh_inventory())
	_label(FoodShelfLife.morning_summary())
	for item in FoodShelfLife.rules():
		var food := FoodShelfLife.state()
		var owned: int = GameState.get_item_count(item)
		var cold := int(GameState.preservation_state["fridge"].get(item, 0)) + int(GameState.preservation_state["freezer"].get(item, 0))
		if owned + cold > 0:
			_label("%s · 창고 %d / 냉장·냉동 %d\n%s" % [ItemData.get_item_name(item), owned, cold, FoodShelfLife.describe(item, food["inventory"].get(item, []))])
	for item in FoodShelfLife.state()["waste"]:
		var amount := int(FoodShelfLife.state()["waste"][item])
		_label("%s %d개 · 기한 지남 / 판매 불가" % [ItemData.get_item_name(item), amount])
		var actions := HBoxContainer.new()
		rows.add_child(actions)
		for recycle in [false, true]:
			var button := Button.new()
			button.text = "폐기" if not recycle else "%d개 → 퇴비 재료 %d개" % [FoodShelfLife.SETTINGS.recycle_input, FoodShelfLife.SETTINGS.recycle_output]
			button.disabled = recycle and amount < FoodShelfLife.SETTINGS.recycle_input
			button.pressed.connect(_clear.bind(item, amount, recycle))
			actions.add_child(button)

func _clear(item: String, amount: int, recycle: bool) -> void:
	FoodShelfLife.discard(item, amount, recycle)
	refresh()
	_refresh_inventory()

func _refresh_inventory() -> void:
	if is_instance_valid(inventory_view): inventory_view.refresh_inventory()

func _acknowledge() -> void:
	FoodShelfLife.state()["learned"] = true
	_refresh_inventory()
