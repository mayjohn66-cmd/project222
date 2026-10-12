class_name FoodShelfLifePanel
extends AcceptDialog

var rows: VBoxContainer
var scroll: ScrollContainer
var pause_owned := false
var previous_pause := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	title = "마감 정리"
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
	visibility_changed.connect(_restore_pause)

func _fit() -> void:
	var bounds := get_parent().get_viewport().get_visible_rect().size
	scroll.custom_minimum_size = Vector2(minf(560, bounds.x - 64), minf(330, bounds.y - 150))
	size = Vector2i(minf(610, bounds.x - 32), minf(450, bounds.y - 40))

func _label(text_value: String) -> void:
	var label := Label.new()
	label.text = text_value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color("51382d"))
	label.add_theme_font_size_override("font_size", UiTypography.size(16))
	rows.add_child(label)

func open() -> void:
	if visible: return
	FoodShelfLife.settle()
	refresh()
	_fit()
	previous_pause = get_tree().paused
	pause_owned = true
	get_tree().paused = true
	popup_centered(size)

func refresh() -> void:
	FoodShelfLife.settle()
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	_label("오래된 재고부터 자동으로 판매합니다.\n오래 남겨 둘 식품은 냉장함·냉동함에서 보관하세요.")
	if FoodShelfLife.learning(): _label("첫 거래와 원재료 판매를 배우는 동안 식품의 기한은 줄어들지 않습니다.")
	var markdown := CheckButton.new()
	markdown.text = "자동 할인 · 기한 %d일 전부터 %d%%" % [FoodShelfLife.SETTINGS.markdown_days, FoodShelfLife.SETTINGS.markdown_percent]
	markdown.button_pressed = FoodShelfLife.state()["markdown"]
	markdown.add_theme_color_override("font_color", Color("51382d"))
	rows.add_child(markdown)
	markdown.toggled.connect(func(on: bool) -> void:
		FoodShelfLife.state()["markdown"] = on
		refresh())
	_label(FoodShelfLife.morning_summary())
	if FoodShelfLife.state()["waste"].is_empty(): _label("따로 정리할 식품이 없습니다.")
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

func _acknowledge() -> void:
	FoodShelfLife.state()["learned"] = true
	hide()

func _restore_pause() -> void:
	if not visible and pause_owned:
		get_tree().paused = previous_pause
		pause_owned = false

func _exit_tree() -> void:
	if pause_owned:
		get_tree().paused = previous_pause
		pause_owned = false
