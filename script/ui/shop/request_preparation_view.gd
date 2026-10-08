class_name RequestPreparationView
extends Node
var host: VillageJournalPanel
var tabs: HBoxContainer
var history_button: Button
var preparation_button: Button
var history: ScrollContainer
var preparation: ScrollContainer
var list: VBoxContainer
var showing_preparation := false
var elapsed := 0.0
var signature := ""
var visible_lines: Array[Dictionary] = []

func _ready() -> void:
	var column := host.root.get_child(0)
	for child in column.get_children():
		if child is ScrollContainer: history = child; break
	tabs = HBoxContainer.new()
	column.add_child(tabs)
	column.move_child(tabs,2)
	history_button = _button("이웃 기록",false)
	preparation_button = _button("물품 준비",true)
	preparation = ScrollContainer.new()
	preparation.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preparation.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(preparation)
	column.move_child(preparation,4)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation",18)
	preparation.add_child(list)
	preparation.hide()
	tabs.hide()

func _button(title: String, mode: bool) -> Button:
	var button := Button.new()
	button.text = title
	button.toggle_mode = true
	button.custom_minimum_size.y = 42
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host._style_button(button)
	button.pressed.connect(func(): select(mode))
	tabs.add_child(button)
	return button

func select(mode: bool) -> void:
	var previous := showing_preparation
	showing_preparation = mode and tabs.visible
	if showing_preparation: host.message.text = "수첩을 닫고 물품을 준비한 뒤, 부탁한 사람이나 게시판에서 전달하세요."
	elif previous: host.message.text = host.introduction()
	history.visible = not showing_preparation
	preparation.visible = showing_preparation
	history_button.button_pressed = not showing_preparation
	preparation_button.button_pressed = showing_preparation

func environment() -> Dictionary:
	var world := host.world
	var manager := world.get_node_or_null("DayManager")
	var hour: float = float(manager.current_hour) + manager.get_display_minute() / 60.0 if manager != null else float(GameConfig.DAY_START_HOUR)
	return {"day":GameState.total_day,"hour":hour,"season":CalendarData.get_season_id(GameState.total_day),
		"weather":str(WorldWeatherData.forecast(GameState.total_day,hour)["kind"])}

func refresh() -> void:
	if not is_instance_valid(host.world): return
	var rows := RequestPreparationData.entries()
	tabs.visible = RequestPreparationData.ENABLED and not rows.is_empty()
	visible_lines.clear()
	var context := environment()
	for entry in rows:
		visible_lines.append({"title":entry["title"],"text":RequestPreparationData.information(host.world,entry,context)})
	var next := JSON.stringify(visible_lines)
	if next != signature:
		signature = next
		var scroll := preparation.scroll_vertical
		for child in list.get_children():
			list.remove_child(child)
			child.queue_free()
		_text("맡은 물품을 천천히 준비해요",21)
		_text("전달 가능한 재고와 현장에서 꺼내야 할 보관 재고를 따로 확인합니다. 같은 물품을 쓰는 부탁은 하나에 전달하면 다른 부탁의 재고도 줄어듭니다.",17)
		for line in visible_lines:
			_text(str(line["title"]),20)
			_text(str(line["text"]),17)
		preparation.set_deferred("scroll_vertical",scroll)
	select(showing_preparation)

func _text(value: String, font_size: int) -> void:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size",font_size)
	list.add_child(label)

func _process(delta: float) -> void:
	if not host.root.visible: return
	elapsed += delta
	if elapsed >= 0.5:
		elapsed = 0.0
		refresh()
