class_name ExpeditionLoadoutGuide
extends Node
const ENABLED := true
var prep: Control
var entry: Button
var overlay: Control
var root: PanelContainer
var list: VBoxContainer
var scroll: ScrollContainer
var close_button: Button
var current: Dictionary = {}
var elapsed := 0.0
var prior_focus: Control

static func install(target: Control) -> void:
	if not ENABLED: return
	var guide := ExpeditionLoadoutGuide.new()
	guide.name = "LoadoutGuide"
	guide.prep = target
	target.add_child(guide)

func _ready() -> void:
	entry = Button.new()
	entry.name = "LoadoutGuideButton"
	entry.text = "장비 사용 안내"
	entry.tooltip_text = "가방에 넣은 장비의 공격 방식과 채집 도구를 확인합니다."
	entry.position = Vector2(0,10)
	entry.size = Vector2(178,34)
	prep.bag_content.get_node("MainVBox/DepartureFooter").add_child(entry)
	entry.pressed.connect(display)
	overlay = Control.new()
	overlay.name = "LoadoutGuideOverlay"
	var layer := CanvasLayer.new()
	layer.layer = 25
	add_child(layer)
	layer.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02,0.03,0.02,0.7)
	overlay.add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root = PanelContainer.new()
	overlay.add_child(root)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f7eddb")
	style.border_color = Color("725039")
	style.set_border_width_all(4)
	style.set_content_margin_all(16)
	root.add_theme_stylebox_override("panel",style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",10)
	root.add_child(column)
	column.add_child(label("이번 원정의 장비",22))
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation",12)
	scroll.add_child(list)
	close_button = Button.new()
	close_button.text = "가방 정리로 돌아가기 [Esc]"
	close_button.custom_minimum_size.y = 40
	for property in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]: close_button.add_theme_color_override(property,Color("38220f"))
	column.add_child(close_button)
	close_button.pressed.connect(close)
	get_viewport().size_changed.connect(fit)
	prep.visibility_changed.connect(_visibility_changed)
	prep.bag_content.visibility_changed.connect(_visibility_changed)
	root.minimum_size_changed.connect(func(): call_deferred("fit"))
	overlay.hide()

func label(text: String, font_size: int = 17) -> Label:
	var value := Label.new()
	value.text = text
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value.add_theme_font_size_override("font_size",UiTypography.size(font_size))
	value.add_theme_color_override("font_color",Color("38220f"))
	return value

func display() -> void:
	if not prep.is_visible_in_tree() or not prep.bag_content.is_visible_in_tree(): return
	prior_focus = get_viewport().gui_get_focus_owner()
	current.clear()
	refresh()
	overlay.show()
	fit()
	close_button.grab_focus()

func close() -> void:
	overlay.hide()
	if is_instance_valid(prior_focus) and prior_focus.is_visible_in_tree(): prior_focus.grab_focus()
	elif entry.is_visible_in_tree(): entry.grab_focus()
	prior_focus = null

func _visibility_changed() -> void:
	if not prep.is_visible_in_tree() or not prep.bag_content.is_visible_in_tree(): close()

func fit() -> void:
	var screen := get_viewport().get_visible_rect().size
	root.size = Vector2(minf(600,screen.x - 32),minf(520,screen.y - 32))
	root.position = (screen-root.size)*0.5

func _process(delta: float) -> void:
	if not overlay.is_visible_in_tree(): return
	elapsed += delta
	if elapsed < 0.2: return
	elapsed = 0
	refresh()

func refresh() -> void:
	var next := ExpeditionLoadoutGuideData.snapshot(prep.get_prepared_bag_model(),prep.bag_content._get_owned_model())
	if next == current: return
	var old_scroll := scroll.scroll_vertical
	current = next
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	list.add_child(label("왼쪽은 보유 장비, 오른쪽은 이번 원정에 가져갈 가방입니다.\n보유 장비를 오른쪽으로 끌어 넣어야 전투·채집에 사용됩니다. [R]로 선택 장비를 회전할 수 있습니다."))
	if not current["valid"]:
		list.add_child(label("가방을 먼저 정리해 주세요.\n" + str(current["message"])))
	else:
		list.add_child(label("처음 들 무기 · " + str(current["attack_name"]),20))
		list.add_child(label(str(current["attack_style"]) + "\n방 안에서는 공격 버튼 또는 [J / Space]로 기본 공격합니다."))
		if current["can_swap"]: list.add_child(label("무기가 둘이면 방 안의 무기 교체 버튼 또는 [Q]로 바꿉니다. 무기마다 공격 방식이 달라지고, 들고 있는 무기의 공격 보너스를 사용합니다."))
		elif current["weapons"].is_empty(): list.add_child(label("가방에 무기가 없어 맨손으로 출발합니다. 보유한 무기가 있다면 가방에 넣어 보세요."))
		_section("가방에 넣은 무기",current["weapons"],"",true)
		_section("가방에 넣은 방어구",current["armor"],"방어구를 넣지 않았습니다. 보유한 방어구를 넣으면 방어에 도움이 됩니다.")
		_section("가방에 넣은 채집 도구",current["tools"],"도구를 넣지 않았습니다. 물 채집에는 채집용 물병이 필요합니다.",true)
		var unpacked_tool := false
		for data in current["unpacked"]:
			if data["type"] == ExpeditionEquipmentData.TYPE_TOOL:
				unpacked_tool = true
				list.add_child(label(str(data["name"]) + "은 보유 중입니다. 사용하려면 오른쪽 가방으로 옮겨 주세요."))
		if current["tools"].is_empty() and not unpacked_tool:
			var hint := ResidentMerchantSupply.next_step()
			if not hint.is_empty(): list.add_child(label(hint))
	_section("보유 중 · 이번 가방에 넣지 않은 장비",current["unpacked"],"보유 장비를 모두 가방에 넣었거나, 따로 보유한 장비가 없습니다.")
	list.add_child(label("안내를 닫고 가방을 정리한 뒤 출발하세요. 가져올 재료가 들어갈 빈칸도 남겨 두면 좋습니다."))
	scroll.set_deferred("scroll_vertical",old_scroll)
	call_deferred("fit")

func _section(heading: String, entries: Array, empty: String, describe: bool = false) -> void:
	if entries.is_empty() and empty.is_empty(): return
	list.add_child(label(heading,19))
	if entries.is_empty():
		list.add_child(label(empty))
		return
	for data in entries:
		var text := ExpeditionLoadoutGuideData.title(data)
		if describe and not str(data["use"]).is_empty(): text += "\n" + str(data["use"])
		list.add_child(label(text))

func _input(event: InputEvent) -> void:
	if not overlay.is_visible_in_tree(): return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_focus_next") or event.is_action_pressed("ui_focus_prev"):
		close_button.grab_focus()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and not event.is_action("ui_accept") and not event.is_action("ui_focus_next") and not event.is_action("ui_focus_prev") and not event.is_action("ui_up") and not event.is_action("ui_down") and not event.is_action("ui_left") and not event.is_action("ui_right"):
		# 가방 회전·원정 저장 등 뒤 화면 단축키의 동작을 막는다.
		get_viewport().set_input_as_handled()
