class_name PreservationPanel
extends AcceptDialog

var inventory_view: Control
var rows: VBoxContainer
var message: Label
var contents_scroll: ScrollContainer
var host: Node  # 월드 모드(가구에서 열 때)의 기준 노드. 크기 계산에 쓴다
var unit_filter: String = ""  # 비어 있지 않으면 이 설비 하나만 보여 준다(월드 모드)

static func install(view: Control) -> void:
	# The compact shelf/warehouse transfer view keeps its existing controls.
	var ancestor: Node = view.get_parent()
	while ancestor != null and not ancestor is ManagementMenu: ancestor = ancestor.get_parent()
	if ancestor == null: return
	var world: Node = ancestor.get_parent()
	while world != null:
		if world.scene_file_path == "res://scenes/expedition/expedition.tscn": return
		world = world.get_parent()
	var panel := PreservationPanel.new()
	panel.inventory_view = view
	view.add_child(panel)

# 가게에 놓인 냉장함·냉동함에서 바로 연다. 가구를 만들어 놓은 것이 설치이므로 아직 설치 전이면 대금 없이 설치한다.
static func open_for_unit(from: Node, id: String) -> void:
	if PreservationService.unit(id).is_empty(): return
	var panel: PreservationPanel = from.get_node_or_null("PreservationWorldPanel") as PreservationPanel

	if panel == null:
		panel = PreservationPanel.new()
		panel.name = "PreservationWorldPanel"
		panel.host = from
		from.add_child(panel)

	panel.unit_filter = id
	PreservationService.settle()
	if not PreservationService.installed(id): PreservationService.install(id, true)
	panel.open()

func _ready() -> void:
	title = "가게 보관 설비"
	process_mode = Node.PROCESS_MODE_ALWAYS
	ok_button_text = "돌아가기"
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color("f5e5c9")
	paper.set_content_margin_all(12)
	add_theme_stylebox_override("panel", paper)
	add_theme_color_override("title_color", Color("51382d"))
	for state in ["font_color", "font_focus_color", "font_hover_color", "font_pressed_color"]:
		get_ok_button().add_theme_color_override(state, Color("51382d"))
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 600
	column.add_theme_constant_override("separation", 10)
	add_child(column)
	contents_scroll = ScrollContainer.new()
	contents_scroll.custom_minimum_size.y = 170
	contents_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	contents_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var scroll_paper := StyleBoxFlat.new()
	scroll_paper.bg_color = Color("f5e5c9")
	contents_scroll.add_theme_stylebox_override("panel", scroll_paper)
	column.add_child(contents_scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	contents_scroll.add_child(body)
	var intro := _label()
	intro.text = "겨울을 여름까지 남겨 두려면\n서리 얼음은 다음 아침에 물이 됩니다. 새순·물박하는 계절이 지나면 시들어요.\n보관 설비에 넣거나 베이킹 작업대에서 말려 두세요."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(intro)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 10)
	body.add_child(rows)
	message = _label()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(message)
	about_to_popup.connect(_fit)
	confirmed.connect(_refresh_inventory)
	close_requested.connect(_refresh_inventory)

func _process(_delta: float) -> void:
	if visible and inventory_view != null and not inventory_view.is_visible_in_tree(): hide()

func _bounds() -> Vector2:
	var anchor: Node = inventory_view if inventory_view != null else host
	return anchor.get_viewport().get_visible_rect().size

func _fit() -> void:
	var bounds := _bounds()
	var desired := Vector2i(minf(650, bounds.x - 32), minf(470, bounds.y - 40))
	contents_scroll.custom_minimum_size.y = maxf(100, desired.y - 90)
	size = desired

func open() -> void:
	PreservationService.settle()
	message.text = "설비는 가게에 고정 설치됩니다. 계절 재료는 보존되고 식품은 냉장 시 천천히 변하며 냉동 시 멈춥니다.\n부탁을 전달하려면 필요한 만큼 꺼내 게시판에 가져가세요."
	refresh()
	popup_centered(Vector2i(minf(650, _bounds().x - 32), minf(470, _bounds().y - 40)))

func refresh() -> void:
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	for unit in PreservationService.SETTINGS.units:
		var id := str(unit["id"])
		if not unit_filter.is_empty() and id != unit_filter: continue
		var header := _label()
		header.text = "%s · %d/%d개 · 소지금 %d G" % [unit["name"], PreservationService.count(id), unit["capacity"], GameState.money]
		rows.add_child(header)
		var description := _label()
		description.text = str(unit["description"])
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rows.add_child(description)
		if not PreservationService.installed(id):
			var install_button := _button("설치 %d G" % unit["cost"], _install.bind(id))
			install_button.disabled = not GameState.can_afford(int(unit["cost"]))
			rows.add_child(install_button)
			continue
		for item in unit["accepts"]:
			var row := HBoxContainer.new()
			var caption := _label()
			caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			caption.text = "%s · 창고 %d / 보관 %d" % [ItemData.get_item_name(item), GameState.get_item_count(item), int(GameState.preservation_state[id].get(item, 0))]
			if FoodShelfLife.tracked(item):
				caption.tooltip_text = FoodShelfLife.describe(item, FoodShelfLife.state()[id].get(item, []))
			row.add_child(caption)
			var put := _button("넣기", _move.bind(id, item, true))
			put.disabled = GameState.get_item_count(item) <= 0 or PreservationService.count(id) >= int(unit["capacity"])
			row.add_child(put)
			var take := _button("꺼내기", _move.bind(id, item, false))
			take.disabled = int(GameState.preservation_state[id].get(item, 0)) <= 0
			row.add_child(take)
			rows.add_child(row)
	var notices: Array = GameState.preservation_state.get("notices", [])
	if not notices.is_empty():
		var record := _label()
		record.text = "최근 변형\n" + "\n".join(notices.slice(maxi(0, notices.size() - 3)))
		record.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rows.add_child(record)

func _button(text_value: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.add_theme_color_override("font_color", Color("51382d"))
	button.add_theme_font_size_override("font_size", 16)
	button.pressed.connect(action)
	return button

func _label() -> Label:
	var label := Label.new()
	label.add_theme_color_override("font_color", Color("51382d"))
	label.add_theme_font_size_override("font_size", 16)
	return label

func _install(id: String) -> void:
	if PreservationService.install(id): message.text = "%s을 설치했습니다. 재료를 넣으면 계절이 지나도 보존됩니다." % PreservationService.unit(id)["name"]
	else: message.text = "소지금과 이미 설치한 설비를 확인해 주세요."
	refresh()
	_refresh_inventory()

func _move(id: String, item: String, putting: bool) -> void:
	var moved := PreservationService.deposit(id, item) if putting else PreservationService.withdraw(id, item)
	if moved > 0:
		message.text = "%s 1개를 %s." % [ItemData.get_item_name(item), "넣었습니다" if putting else "꺼냈습니다"]
		message.text += " 남은 유통기한은 그대로 이어집니다." if FoodShelfLife.tracked(item) else " 꺼낸 얼음은 다음 아침 전에 사용하거나 다시 보관하세요."
	else: message.text = "재고와 보관함의 빈자리를 확인해 주세요."
	refresh()
	_refresh_inventory()

func _refresh_inventory() -> void:
	if inventory_view == null or not is_instance_valid(inventory_view): return
	inventory_view.refresh_inventory()
	var ancestor: Node = inventory_view.get_parent()
	while ancestor != null and not ancestor is ManagementMenu: ancestor = ancestor.get_parent()
	if ancestor is ManagementMenu: ancestor.refresh_common_info()
