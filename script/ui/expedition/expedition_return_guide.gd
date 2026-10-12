class_name ExpeditionReturnGuide
extends Node
## Optional inline help shares the existing result scroll. Confirm remains fixed.
var host: PanelContainer
var entry: Button
var note: Label
var scroll: ScrollContainer
var showing := false

static func attach(panel: PanelContainer) -> void:
	if not ExpeditionReturnGuideData.ENABLED: return
	var guide := ExpeditionReturnGuide.new()
	guide.name = "ReturnGuide"
	guide.host = panel
	panel.add_child(guide)

func _ready() -> void:
	scroll = host.get_node("VBoxContainer/ResultScroll")
	note = Label.new()
	note.name = "ReturnGuideText"
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size",UiTypography.size(18))
	note.hide()
	host.get_node("VBoxContainer/ResultScroll/ResultBody").add_child(note)
	entry = Button.new()
	entry.name = "ReturnGuideButton"
	entry.text = "물품 활용 안내 보기"
	entry.toggle_mode = true
	entry.custom_minimum_size.y = 40
	for color in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
		entry.add_theme_color_override(color,Color(0.22,0.13,0.06,1))
	var column := host.get_node("VBoxContainer")
	column.add_child(entry)
	column.move_child(entry,column.get_child_count()-2)
	entry.toggled.connect(select)
	host.visibility_changed.connect(_visibility_changed)
	_visibility_changed()

func expedition() -> Node:
	var node := host.get_parent()
	while node != null:
		if node.scene_file_path == "res://scenes/expedition/expedition.tscn": return node
		node = node.get_parent()
	return null

func _visibility_changed() -> void:
	showing = false
	note.hide()
	entry.set_pressed_no_signal(false)
	entry.text = "물품 활용 안내 보기"
	entry.visible = expedition() != null

func select(open: bool) -> void:
	var world := expedition()
	showing = open and host.is_visible_in_tree() and world != null
	entry.set_pressed_no_signal(showing)
	entry.text = "물품 활용 안내 접기" if showing else "물품 활용 안내 보기"
	note.visible = showing
	if showing:
		note.text = str(ExpeditionReturnGuideData.snapshot(world.expedition_bag)["text"])
		await get_tree().process_frame
		await get_tree().process_frame
		if is_inside_tree() and showing: scroll.scroll_vertical = int(note.position.y)
	else:
		scroll.scroll_vertical = 0

func _input(event: InputEvent) -> void:
	if not showing or not host.is_visible_in_tree(): return
	if event.is_action_pressed("ui_cancel"):
		select(false)
		entry.grab_focus()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_focus_next") or event.is_action_pressed("ui_focus_prev"):
		var target := host.get_node("VBoxContainer/ResultConfirmButton") if get_viewport().gui_get_focus_owner() == entry else entry
		target.grab_focus()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and not event.is_action("ui_accept") and not event.is_action("ui_up") and not event.is_action("ui_down") and not event.is_action("ui_left") and not event.is_action("ui_right"):
		# Do not rotate the selected bag item or quick-save behind the open help.
		get_viewport().set_input_as_handled()
