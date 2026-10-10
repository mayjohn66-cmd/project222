class_name BlacksmithServicePanel
extends CanvasLayer
signal action_requested(id: String)
signal closed
var root: PanelContainer
var backdrop: ColorRect
var list: VBoxContainer
var close_button: Button
var confirm_button: Button
var message: Label
var detail: Label
var item_icon: TextureRect
var title: Label
var cards: Dictionary = {}
var tabs: Dictionary = {}
var mode := "hello"
var selected: Dictionary = {}
func _ready() -> void:
	layer = 25
	backdrop = ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0,0,0,0.45)
	add_child(backdrop)
	root = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f7eddb")
	style.border_color = Color("725039")
	style.set_border_width_all(4)
	style.set_content_margin_all(16)
	root.add_theme_stylebox_override("panel",style)
	add_child(root)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",8)
	root.add_child(column)
	title = label("대장장이 · 장비를 오래 쓰는 손",22)
	column.add_child(title)
	var row := HBoxContainer.new()
	column.add_child(row)
	for id in ["hello", "craft", "enhance"]:
		var button := make_button({"hello":"안부", "craft":"장비 제작", "enhance":"장비 강화"}[id])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(button)
		tabs[id] = button
		button.pressed.connect(func(): select_mode(id))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation",10)
	scroll.add_child(list)
	message = label("",16)
	message.max_lines_visible = 3
	column.add_child(message)
	confirm_button = make_button("장비를 선택하세요")
	confirm_button.pressed.connect(func(): action_requested.emit("enhance"))
	column.add_child(confirm_button)
	close_button = make_button("닫기 [E / Esc]")
	close_button.pressed.connect(close)
	column.add_child(close_button)
	get_viewport().size_changed.connect(fit)
	root.minimum_size_changed.connect(func(): call_deferred("fit"))
	fit()
	hide_panel()
func label(text: String, size: int) -> Label:
	var value := Label.new()
	value.text = text
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value.add_theme_font_size_override("font_size",size)
	value.add_theme_color_override("font_color",Color("38220f"))
	return value
func make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 40
	for property in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]: button.add_theme_color_override(property,Color("38220f"))
	return button
func fit() -> void:
	var screen := get_viewport().get_visible_rect().size
	root.size = Vector2(minf(740,screen.x - 32),minf(570,screen.y - 32))
	root.position = (screen-root.size)*0.5
func display() -> void:
	message.text = ""
	root.show()
	backdrop.show()
	select_mode("hello")
	fit()
	close_button.grab_focus()
func hide_panel() -> void:
	root.hide()
	backdrop.hide()
func select_mode(id: String) -> void:
	mode = id
	selected.clear()
	message.text = UiText.t("service.supply.instructions")
	refresh()
	call_deferred("fit")
func refresh() -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	cards.clear()
	for id in tabs: tabs[id].disabled = id == mode
	confirm_button.visible = mode == "enhance"
	confirm_button.disabled = true
	if mode == "hello":
		list.add_child(label(BlacksmithProgressionFlow.next_step(),18))
		var button := make_button("원정에서 돌아온 안부" if BlacksmithProgressionFlow.afterglow_ready() else "잠깐 이야기하기")
		list.add_child(button)
		button.pressed.connect(func(): action_requested.emit("hello"))
		return
	if mode == "craft":
		for recipe in VillageSmithyFlow.recipes():
			var id := str(recipe["id"])
			if not RecipeUnlockData.is_recipe_available(id): continue
			var text := str(recipe["title"]) + "\n"
			for material in recipe["materials"]: text += "%s %d/%d · " % [ItemData.get_item_name(str(material["item_id"])),GameState.get_item_count(str(material["item_id"])),int(material["amount"])]
			var reason := VillageSmithyFlow.blocked_reason(id)
			if not reason.is_empty(): text += "\n" + reason
			var costs := {}
			for material in recipe["materials"]:
				var item := str(material["item_id"])
				costs[item] = int(costs.get(item,0)) + int(material["amount"])
			var supply := NpcServiceSupplyGuide.missing(self,costs)
			if not supply.is_empty(): text += "\n" + supply
			list.add_child(label(text,18))
			var button := make_button("제작하기")
			button.disabled = not VillageSmithyFlow.blocked_reason(id).is_empty()
			list.add_child(button)
			cards[id] = {"action":button}
			button.pressed.connect(func(): action_requested.emit("craft:" + id))
		if cards.is_empty(): list.add_child(label("아직 배운 장비 제조법이 없습니다. 원정에서 얻은 두루마리를 살펴보세요.",18))
		return
	list.add_child(label("손질할 장비를 선택하고 필요한 재료를 확인하세요.\n같은 종류의 장비도 번호가 다르면 별도로 다듬습니다.",17))
	for entry in BlacksmithEquipmentAdapter.entries():
		var id := int(entry["instance_id"])
		var button := make_button("%s +%d · %s · 장비 #%d" % [ItemData.get_item_name(str(entry["item_id"])),int(entry.get("enhancement_level",0)),"보유 장비" if entry["source"] == "owned" else "원정 가방",id])
		list.add_child(button)
		cards[str(id)] = {"action":button}
		button.pressed.connect(func(): selected = entry.duplicate(true); refresh_detail())
	if cards.is_empty(): list.add_child(label("다듬을 수 있는 보유 장비가 없습니다.",18))
	var detail_row := HBoxContainer.new()
	list.add_child(detail_row)
	item_icon = TextureRect.new()
	item_icon.custom_minimum_size = Vector2(64,64)
	item_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	item_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	item_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	item_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_row.add_child(item_icon)
	item_icon.hide()
	detail = label("장비를 선택하면 현재 단계와 다음 단계 재료를 확인할 수 있습니다.",18)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_row.add_child(detail)
	confirm_button.text = "장비를 선택하세요"
func refresh_detail() -> void:
	if selected.is_empty(): return
	var id := str(selected["item_id"])
	item_icon.texture = ItemData.get_item_icon(id)
	item_icon.visible = item_icon.texture != null
	var level := int(selected.get("enhancement_level",0))
	var check := EquipmentEnhancementService.get_enhancement_check(selected)
	var data := ExpeditionEquipmentData.get_equipment_data(id)
	var capped := level >= int(data.get("max_enhancement_level",0))
	var text := "%s · +%d · 최대 단계\n" % [ItemData.get_item_name(id),level] if capped else "%s · +%d → +%d\n" % [ItemData.get_item_name(id),level,level + 1]
	text += "최대 +%d · 강화 비용은 재료만 사용합니다.\n" % int(data.get("max_enhancement_level",0))
	text += str(ItemData.get_item(id).get("description","")) + "\n"
	if data.get("equipment_type","") == ExpeditionEquipmentData.TYPE_WEAPON: text += ExpeditionWeaponLoadout.get_style_text(id) + "\n"
	for material in check.get("costs", {}): text += "%s %d개 · 보유 %d개\n" % [ItemData.get_item_name(str(material)),int(check["costs"][material]),GameState.get_item_count(str(material))]
	if not check.get("success",false): text += str(check.get("message","강화할 수 없습니다."))
	var supply := NpcServiceSupplyGuide.missing(self,check.get("costs",{}))
	if not supply.is_empty(): text += "\n" + supply
	detail.text = text
	confirm_button.text = "최대 단계입니다" if capped else "선택 장비 #%d · +%d 강화 확정" % [int(selected["instance_id"]),level+1]
	confirm_button.disabled = not check.get("success",false)
	call_deferred("fit")
	call_deferred("reveal_detail")
func reveal_detail() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree() or not root.visible or not is_instance_valid(detail): return
	var scroll := list.get_parent() as ScrollContainer
	scroll.ensure_control_visible(detail)
func close() -> void:
	hide_panel()
	selected.clear()
	closed.emit()
func _input(event: InputEvent) -> void:
	if not root.visible or (event is InputEventKey and event.is_echo()): return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
